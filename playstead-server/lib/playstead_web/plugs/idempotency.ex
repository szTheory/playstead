defmodule PlaysteadWeb.Plugs.Idempotency do
  @moduledoc """
  Requires an `Idempotency-Key` header on mutating `/api/v1` routes
  (D-20a, PROT-04). Attaches after `PlaysteadWeb.Plugs.DeviceAuth`, so
  `conn.assigns.current_device` is already set.

  Performs the pre-flight replay/conflict/mismatch classification via
  `Playstead.Idempotency.fetch/3`:

  - No header: halts with `idempotency_key_missing`.
  - A complete receipt with a matching fingerprint: halts and replays
    the stored response verbatim, never touching the controller.
  - A complete receipt with a different fingerprint: halts with 422
    `idempotency_key_mismatch`.
  - An in-flight receipt: halts with 409 `idempotency_key_conflict` and
    a `Retry-After` header.
  - Otherwise: assigns `:idempotency_key` and `:idempotency_fingerprint`
    onto the conn so the controller can call
    `Playstead.Idempotency.execute/4`.
  """

  import Plug.Conn

  alias Playstead.Idempotency

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case get_req_header(conn, "idempotency-key") do
      [key] when key != "" -> classify(conn, key)
      _ -> missing(conn)
    end
  end

  defp classify(conn, key) do
    device = conn.assigns.current_device

    fp =
      Idempotency.fingerprint(%{method: conn.method, path: conn.request_path, body: conn.params})

    case Idempotency.fetch(device.id, key, fp) do
      {:ok, :fresh} ->
        signal_reliability_duplicate_ready(conn)

        conn
        |> assign(:idempotency_key, key)
        |> assign(:idempotency_fingerprint, fp)

      {:ok, :replay, receipt} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(receipt.response_status, receipt.response_body)
        |> halt()

      {:error, :mismatch} ->
        conn
        |> PlaysteadWeb.Problem.send_problem(
          422,
          :idempotency_key_mismatch,
          "This Idempotency-Key was already used with a different request."
        )
        |> halt()

      {:error, :in_flight} ->
        conn
        |> put_resp_header("retry-after", "1")
        |> PlaysteadWeb.Problem.send_problem(
          409,
          :idempotency_key_conflict,
          "A request with this Idempotency-Key is already being processed."
        )
        |> halt()
    end
  end

  # The duplicate marker is available only to the isolated mac_ci save
  # fixture. It is written after the real preflight lookup observes `fresh`,
  # so releasing the first request proves the subsequent unique-index race.
  defp signal_reliability_duplicate_ready(conn) do
    if conn.method == "POST" and conn.request_path == "/api/v1/saves/revisions" do
      with root when is_binary(root) <-
             Application.get_env(:playstead, :mac_ci_save_test_control_root),
           [token] <- get_req_header(conn, "x-playstead-test-duplicate"),
           {:ok, canonical} <- Ecto.UUID.cast(token),
           true <- canonical == token do
        directory = Path.join(root, "save-e2e-" <> token)

        with {:ok, %File.Stat{type: :directory}} <- File.lstat(directory),
             {:ok, ^token} <- File.read(Path.join(directory, "owner")),
             {:ok, io} <- File.open(Path.join(directory, "duplicate-ready"), [:write, :exclusive]) do
          :ok = IO.binwrite(io, token)
          :ok = File.close(io)
        else
          _ -> :ok
        end
      else
        _ -> :ok
      end
    end

    :ok
  end

  defp missing(conn) do
    conn
    |> PlaysteadWeb.Problem.send_problem(
      422,
      :idempotency_key_missing,
      "An Idempotency-Key header is required for this request."
    )
    |> halt()
  end
end
