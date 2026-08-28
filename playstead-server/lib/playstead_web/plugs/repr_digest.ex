defmodule PlaysteadWeb.Plugs.ReprDigest do
  @moduledoc """
  Requires an RFC 9530 `Repr-Digest` header carrying a `sha-256` entry
  and a `Content-Length` header on `/api/v1` upload routes (D-02, D-10).

  Follows the classify-then-halt-or-continue shape of
  `PlaysteadWeb.Plugs.Idempotency`. RFC 9530 encodes the digest as
  base64 of the raw 32 digest bytes wrapped in colons
  (`sha-256=:<base64>:`), while everything else in this phase —
  content-addressed paths, receipts, manifests — uses lowercase
  hexadecimal. This plug decodes the header form to raw bytes and
  re-encodes to lowercase hex once, here, so every downstream comparison
  in the write path is hex-to-hex: a base64-versus-hex mix-up here would
  make every legitimate upload fail `import_digest_mismatch` in a way
  that looks like a client bug (RESEARCH.md).

  On success, assigns `:expected_sha256` (lowercase hex) and
  `:declared_length` onto the conn, and merges those same two facts
  into `conn.params` under keys no route or client body ever supplies
  (`"__repr_digest_sha256"`, `"__declared_length"`) — never replacing
  `conn.params` wholesale, which would erase the `command_id` path
  parameter Phoenix has already merged in by the time pipeline plugs
  run. `PlaysteadWeb.Plugs.Idempotency` (unchanged, unforked)
  fingerprints on `conn.params`, so this is what makes the upload's
  idempotency fingerprint cover method + path + digest + declared
  length instead of the request body — the body itself is never
  fingerprinted, which is what makes replaying a multi-gigabyte upload
  cheap (D-02).
  """

  import Plug.Conn

  alias PlaysteadWeb.Problem

  @behaviour Plug

  @sha256_entry ~r/sha-256=:([A-Za-z0-9+\/=]+):/

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    with {:ok, expected_sha256} <- parse_repr_digest(conn),
         {:ok, declared_length} <- parse_content_length(conn),
         :ok <- check_length(declared_length) do
      conn
      |> assign(:expected_sha256, expected_sha256)
      |> assign(:declared_length, declared_length)
      |> Map.update!(:params, fn params ->
        Map.merge(params, %{
          "__repr_digest_sha256" => expected_sha256,
          "__declared_length" => declared_length
        })
      end)
    else
      {:error, :missing_digest} ->
        reject(
          conn,
          422,
          :import_digest_mismatch,
          "A Repr-Digest header with a sha-256 entry is required."
        )

      {:error, :bad_digest} ->
        reject(conn, 422, :import_digest_mismatch, "The Repr-Digest header could not be parsed.")

      {:error, :missing_length} ->
        reject(conn, 411, :upload_length_required, "A Content-Length header is required.")

      {:error, :empty} ->
        reject(conn, 422, :import_empty_file, "The uploaded file must not be empty.")

      {:error, :too_large} ->
        reject(
          conn,
          413,
          :import_file_too_large,
          "The uploaded file exceeds the configured maximum size."
        )
    end
  end

  defp parse_repr_digest(conn) do
    case get_req_header(conn, "repr-digest") do
      [header] ->
        case Regex.run(@sha256_entry, header) do
          [_full, base64] ->
            case Base.decode64(base64) do
              {:ok, raw} -> {:ok, Base.encode16(raw, case: :lower)}
              :error -> {:error, :bad_digest}
            end

          nil ->
            {:error, :missing_digest}
        end

      _ ->
        {:error, :missing_digest}
    end
  end

  defp parse_content_length(conn) do
    case get_req_header(conn, "content-length") do
      [value] ->
        case Integer.parse(value) do
          {length, ""} when length >= 0 -> {:ok, length}
          _ -> {:error, :missing_length}
        end

      _ ->
        {:error, :missing_length}
    end
  end

  defp check_length(0), do: {:error, :empty}

  defp check_length(length) do
    if length > max_upload_bytes() do
      {:error, :too_large}
    else
      :ok
    end
  end

  defp max_upload_bytes do
    Application.get_env(:playstead, :max_upload_bytes, 8_589_934_592)
  end

  defp reject(conn, status, code, detail) do
    conn
    |> Problem.send_problem(status, code, detail)
    |> halt()
  end
end
