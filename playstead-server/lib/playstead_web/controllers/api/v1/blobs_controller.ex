defmodule PlaysteadWeb.Api.V1.BlobsController do
  @moduledoc """
  `GET`/`HEAD /api/v1/blobs/:sha256` (D-10, D-19). Authorisation is by
  whether the calling user has a `source_file` referencing that blob —
  never by the hash alone, which would make this endpoint a cross-user
  read oracle (D-13).

  D-19 freezes the Range/If-Range/206/416/HEAD contract as published
  client protocol: a GET with no `Range` header returns `200` with
  `Accept-Ranges: bytes` and a quoted ETag; a single satisfiable
  `bytes=first-` or `bytes=first-last` range returns `206` with
  `Content-Range`; an out-of-bounds first byte position returns `416`
  with `Content-Range: bytes */size`; a multi-range, malformed,
  suffix-range, or foreign-unit header collapses to the full `200`
  body rather than raising; `HEAD` mirrors `GET`'s status and headers
  with no body. `authorized?/2` and `playable?/2` gate every one of
  these branches identically — a Range-shaped request must never skip
  the ownership/quarantine checks the unranged request passes.
  """

  use PlaysteadWeb, :controller

  import Ecto.Query

  alias Playstead.Import.SourceFile
  alias Playstead.Repo

  action_fallback PlaysteadWeb.Api.V1.FallbackController

  def show(conn, %{"sha256" => sha256}) do
    respond(conn, sha256, :get)
  end

  def head_show(conn, %{"sha256" => sha256}) do
    respond(conn, sha256, :head)
  end

  defp respond(conn, sha256, method) do
    device = conn.assigns.current_device

    with true <- authorized?(device.user_id, sha256),
         true <- playable?(device.user_id, sha256),
         {:ok, size} <- Playstead.Blobs.byte_size_of(sha256) do
      etag = etag_for(sha256)

      conn
      |> put_resp_header("etag", etag)
      |> put_resp_header("accept-ranges", "bytes")
      |> serve(sha256, size, etag, method)
    else
      false -> {:error, :not_found}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp authorized?(user_id, sha256) do
    from(sf in SourceFile,
      join: b in assoc(sf, :blob),
      where: sf.user_id == ^user_id and b.sha256 == ^sha256
    )
    |> Repo.exists?()
  end

  # D-28: a quarantined blob is never served as playable content until
  # this user has their own release decision recorded — the machine
  # verdict on the shared bytes is never enough on its own.
  defp playable?(user_id, sha256) do
    case Playstead.Blobs.get_by_sha256(sha256) do
      nil ->
        false

      blob ->
        not Playstead.Blobs.quarantined?(blob) or
          Playstead.Blobs.released_for_user?(user_id, blob.id)
    end
  end

  defp serve(conn, sha256, size, etag, method) do
    case range_decision(conn, size, etag) do
      :full -> serve_full(conn, sha256, size, method)
      {:ok, first, last} -> send_range(conn, sha256, first, last, size, method)
      :not_satisfiable -> send_not_satisfiable(conn, size)
    end
  end

  defp serve_full(conn, _sha256, size, :head) do
    conn
    |> put_resp_content_type("application/octet-stream")
    |> put_resp_header("content-length", Integer.to_string(size))
    |> send_resp(200, "")
  end

  defp serve_full(conn, sha256, _size, :get) do
    case Playstead.Blobs.stream(sha256) do
      {:ok, stream} ->
        conn
        |> put_resp_content_type("application/octet-stream")
        |> send_chunked(200)
        |> stream_chunks(stream)

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  defp send_range(conn, sha256, first, last, size, method) do
    content_length = last - first + 1

    conn =
      conn
      |> put_resp_content_type("application/octet-stream")
      |> put_resp_header("content-range", "bytes #{first}-#{last}/#{size}")
      |> put_resp_header("content-length", Integer.to_string(content_length))

    case method do
      :head ->
        send_resp(conn, 206, "")

      :get ->
        case Playstead.Blobs.stream(sha256, first..last) do
          {:ok, stream} ->
            body = Enum.into(stream, <<>>)
            send_resp(conn, 206, body)

          {:error, :not_found} ->
            {:error, :not_found}
        end
    end
  end

  defp send_not_satisfiable(conn, size) do
    conn
    |> put_resp_header("content-range", "bytes */#{size}")
    |> PlaysteadWeb.Problem.send_problem(
      416,
      :range_not_satisfiable,
      "The requested range is not satisfiable."
    )
  end

  # Only the `bytes=` unit with a single non-negative first byte
  # position is accepted (D-19). A multi-range (comma), a foreign
  # unit, a suffix-range (`bytes=-500`), or a malformed spec all
  # collapse to `:none` (the full-200 path) rather than raising — this
  # keeps the frozen contract to exactly one shape a client must
  # implement. An out-of-range first byte position is the only case
  # that yields `:not_satisfiable`; an over-long last byte position is
  # clamped to the final byte instead of rejected. A zero-length
  # object has no satisfiable byte position at all, so any well-formed
  # Range header on it yields `:not_satisfiable`.
  defp parse_range(conn, size) do
    case get_req_header(conn, "range") do
      [range_header] -> evaluate_range(range_header, size)
      _ -> :none
    end
  end

  defp evaluate_range(header, size) do
    case String.split(header, "=", parts: 2) do
      ["bytes", spec] ->
        if String.contains?(spec, ",") do
          :none
        else
          case single_range(spec, size) do
            {:ok, first, last} -> {:ok, first, last}
            :not_satisfiable -> :not_satisfiable
            :invalid -> :none
          end
        end

      _ ->
        :none
    end
  end

  defp single_range(spec, size) do
    case String.split(spec, "-", parts: 2) do
      [first_str, last_str] ->
        case parse_non_neg_int(first_str) do
          {:ok, first} -> resolve_range(first, last_str, size)
          :error -> :invalid
        end

      _ ->
        :invalid
    end
  end

  defp resolve_range(_first, _last_str, 0), do: :not_satisfiable
  defp resolve_range(first, _last_str, size) when first >= size, do: :not_satisfiable
  defp resolve_range(first, "", size), do: {:ok, first, size - 1}

  defp resolve_range(first, last_str, size) do
    case parse_non_neg_int(last_str) do
      {:ok, last} -> {:ok, first, min(last, size - 1)}
      :error -> :invalid
    end
  end

  defp parse_non_neg_int(str) do
    case Integer.parse(str) do
      {n, ""} when n >= 0 -> {:ok, n}
      _ -> :error
    end
  end

  # If-Range is a strong comparison against the quoted ETag the
  # response would emit. A mismatch discards the Range and serves the
  # full 200 body — this is precisely the branch a resuming client
  # detects to decide it must truncate its partial file and restart.
  defp range_decision(conn, size, etag) do
    case parse_range(conn, size) do
      :none ->
        :full

      range_result ->
        if if_range_ok?(conn, etag), do: range_result, else: :full
    end
  end

  defp if_range_ok?(conn, etag) do
    case get_req_header(conn, "if-range") do
      [value] -> value == etag
      _ -> true
    end
  end

  defp etag_for(sha256), do: "\"#{sha256}\""

  defp stream_chunks(conn, stream) do
    Enum.reduce_while(stream, conn, fn chunk, conn ->
      case Plug.Conn.chunk(conn, chunk) do
        {:ok, conn} -> {:cont, conn}
        {:error, _reason} -> {:halt, conn}
      end
    end)
  end
end
