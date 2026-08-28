defmodule Playstead.Import.UploadSlots do
  @moduledoc """
  Per-device concurrent-upload accounting for D-10's "at most two
  simultaneous uploads per device" rule.

  `Playstead.RateLimiter` (Hammer, fixed-window) only counts hits within
  a time window — it has no decrement, so it cannot represent "how many
  uploads are in flight right now" (a genuinely concurrent, not rate,
  limit). This module is a small `:ets`-backed counter for exactly that
  — not a second rate limiter, since it never makes a time-windowed
  decision; `PlaysteadWeb.Plugs.UploadConcurrency` is its only caller.
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

  @doc "Attempts to acquire one upload slot for `device_id`. `:ok` if under `max`, else `:error`."
  @spec acquire(binary(), pos_integer()) :: :ok | :error
  def acquire(device_id, max) do
    count = :ets.update_counter(@table, device_id, {2, 1}, {device_id, 0})

    if count <= max do
      :ok
    else
      release(device_id)
      :error
    end
  end

  @doc "Releases one upload slot for `device_id`. Safe to call even if none was ever acquired."
  @spec release(binary()) :: :ok
  def release(device_id) do
    :ets.update_counter(@table, device_id, {2, -1}, {device_id, 0})
    :ok
  end
end
