defmodule PlaysteadWeb.Plugs.UploadConcurrency do
  @moduledoc """
  Caps simultaneous uploads per device at two (D-10). Attaches after
  `PlaysteadWeb.Plugs.DeviceAuth` and `PlaysteadWeb.Plugs.Idempotency` —
  it must come after idempotency so a replayed request (which never
  reaches the controller) never consumes a slot. Backed by
  `Playstead.Import.UploadSlots`, not `Playstead.RateLimiter` — see that
  module's moduledoc for why a fixed-window rate limiter can't represent
  "how many uploads are in flight right now".
  """

  import Plug.Conn

  alias Playstead.Import.UploadSlots
  alias PlaysteadWeb.Problem

  @behaviour Plug

  @max_concurrent_uploads 2

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    device = conn.assigns.current_device

    case UploadSlots.acquire(device.id, max_concurrent_uploads()) do
      :ok ->
        register_before_send(conn, fn conn ->
          UploadSlots.release(device.id)
          conn
        end)

      :error ->
        conn
        |> Problem.send_problem(
          429,
          :too_many_uploads,
          "This device already has the maximum number of uploads in progress."
        )
        |> halt()
    end
  end

  defp max_concurrent_uploads, do: @max_concurrent_uploads
end
