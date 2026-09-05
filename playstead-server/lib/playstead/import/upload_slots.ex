defmodule Playstead.Import.UploadSlots do
  @moduledoc """
  Per-bucket concurrent-upload accounting for D-10's "at most two
  simultaneous uploads per device" rule (and, since CR-02's gap
  closure, the save-lane's own namespaced budget, D-33).

  `Playstead.RateLimiter` (Hammer, fixed-window) only counts hits within
  a time window — it has no decrement, so it cannot represent "how many
  uploads are in flight right now" (a genuinely concurrent, not rate,
  limit). This module is a small `:ets`-backed counter for exactly that
  — not a second rate limiter, since it never makes a time-windowed
  decision; `PlaysteadWeb.Plugs.UploadConcurrency` is its only caller.

  Every acquire/release is keyed by a `(bucket, unique_key)` pair.
  `bucket` is the budget being spent from (a device id for imports, or
  `Blobs.save_upload_slot_key/1`'s `"save:" <> device_id` for saves).
  `unique_key` identifies the specific upload attempt: re-acquiring the
  same `(bucket, unique_key)` pair -- e.g. a retried request for the
  same in-flight upload -- is a no-op success and does NOT consume a
  second slot from the bucket's budget. The imports call site passes a
  fresh, never-repeated `unique_key` per call, so its behavior is
  unchanged: every acquire there is still a genuinely new slot. The
  save-upload call site dedupes on the path's `command_id`, which is
  stable across retries of the same streamed upload (D-16) -- see
  `PlaysteadWeb.Plugs.UploadConcurrency`'s moduledoc for why that
  matters for a route that cannot use `:idempotency`.
  """

  use GenServer

  @table __MODULE__

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, {:write_concurrency, true}])
    {:ok, %{}}
  end

  @doc """
  Attempts to acquire one upload slot from `bucket`'s budget, deduped
  by `unique_key`. If `(bucket, unique_key)` already holds a slot (a
  retry of an in-flight upload), returns `:ok` without consuming
  another one. `:ok` if under `max` (or already held), else `:error`.
  """
  @spec acquire(binary(), binary(), pos_integer()) :: :ok | :error
  def acquire(bucket, unique_key, max) do
    held_key = {:held, bucket, unique_key}

    case :ets.lookup(@table, held_key) do
      [{^held_key, true}] ->
        :ok

      [] ->
        count = :ets.update_counter(@table, bucket, {2, 1}, {bucket, 0})

        if count <= max do
          :ets.insert(@table, {held_key, true})
          :ok
        else
          :ets.update_counter(@table, bucket, {2, -1}, {bucket, 0})
          :error
        end
    end
  end

  @doc """
  Releases the slot held by `(bucket, unique_key)`. Safe to call even
  if none was ever acquired, and safe to call more than once (the
  second call is a no-op).
  """
  @spec release(binary(), binary()) :: :ok
  def release(bucket, unique_key) do
    held_key = {:held, bucket, unique_key}

    case :ets.lookup(@table, held_key) do
      [{^held_key, true}] ->
        :ets.delete(@table, held_key)
        :ets.update_counter(@table, bucket, {2, -1}, {bucket, 0})
        :ok

      [] ->
        :ok
    end
  end
end
