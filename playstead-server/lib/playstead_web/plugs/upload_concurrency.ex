defmodule PlaysteadWeb.Plugs.UploadConcurrency do
  @moduledoc """
  Caps simultaneous uploads at two per budget bucket (D-10, D-33).
  Attaches after `PlaysteadWeb.Plugs.DeviceAuth`. On the imports route
  it also comes after `PlaysteadWeb.Plugs.Idempotency`, so a replayed
  request (which never reaches the controller) never consumes a slot.
  Backed by `Playstead.Import.UploadSlots`, not `Playstead.RateLimiter`
  — see that module's moduledoc for why a fixed-window rate limiter
  can't represent "how many uploads are in flight right now".

  Two options configure which budget and which dedup key are used:

    * `:bucket_fn` (default: identity) — maps `device.id` to the
      budget key. The imports route uses the default (budget = the
      bare device id); the save-upload route passes
      `&Playstead.Blobs.save_upload_slot_key/1` so save uploads spend
      from a `"save:" <> device_id` budget, never contending with a
      concurrent game import for the same device (D-33 / CR-02).

    * `:dedupe_param` (default: none) — a `conn.params` key whose value
      identifies a specific upload attempt, so a retry of the exact
      same upload is a no-op against the budget rather than a second
      slot. The imports route omits this: that route sits on
      `:idempotency`, which already rejects a concurrent retry before
      it reaches this plug, so every call here is a genuinely new
      upload and each gets its own single-use key. The save-upload
      route is deliberately off `:idempotency` (D-16 — a stream cannot
      be fingerprinted), so it dedupes on `command_id`, which stays
      stable across retries of the same upload; without this, a client
      retry after a dropped connection would consume a second slot
      from the device's own two-slot save budget for what is really
      still just one upload in flight.
  """

  import Plug.Conn

  alias Playstead.Import.UploadSlots
  alias PlaysteadWeb.Problem

  @behaviour Plug

  @max_concurrent_uploads 2

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    device = conn.assigns.current_device
    bucket_fn = Keyword.get(opts, :bucket_fn, & &1)
    bucket = bucket_fn.(device.id)
    unique_key = unique_key_for(conn, opts)

    case UploadSlots.acquire(bucket, unique_key, max_concurrent_uploads()) do
      :ok ->
        register_before_send(conn, fn conn ->
          UploadSlots.release(bucket, unique_key)
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

  defp unique_key_for(conn, opts) do
    param = Keyword.get(opts, :dedupe_param)
    value = param && conn.params[param]

    case value do
      nil -> "req:" <> unique_request_id()
      "" -> "req:" <> unique_request_id()
      value -> to_string(value)
    end
  end

  defp unique_request_id, do: inspect(System.unique_integer([:positive, :monotonic]))

  defp max_concurrent_uploads, do: @max_concurrent_uploads
end
