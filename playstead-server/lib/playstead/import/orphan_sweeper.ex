defmodule Playstead.Import.OrphanSweeper do
  @moduledoc """
  Clears leftover temporary files under the blob volume's `tmp/`
  subdirectory (D-29). Scoped strictly to `tmp/` — it never removes or
  renames anything under `objects/`. A failed or crash-interrupted
  write leaves nothing visible per D-29; this is how the temp file from
  that interrupted write eventually gets cleaned up, without ever
  endangering committed content.

  Runs once at application boot (supervised in `Playstead.Application`)
  and is also callable directly, e.g. from tests or an operator console.
  """

  use GenServer

  alias Playstead.Blobs.Store.LocalDisk

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, %{}, {:continue, :sweep}}
  end

  @impl true
  def handle_continue(:sweep, state) do
    sweep()
    {:noreply, state}
  end

  @doc """
  Removes every entry under `tmp/` at least `min_age_seconds` old
  (default `0`, i.e. everything). Never touches `objects/` — it only
  ever lists and deletes inside the `tmp/` subdirectory.
  """
  @spec sweep(non_neg_integer()) :: :ok
  def sweep(min_age_seconds \\ 0) do
    tmp_dir = Path.join(LocalDisk.blob_path(), "tmp")

    case File.ls(tmp_dir) do
      {:ok, entries} ->
        now = System.os_time(:second)

        Enum.each(entries, fn entry ->
          path = Path.join(tmp_dir, entry)
          maybe_delete(path, now, min_age_seconds)
        end)

        :ok

      {:error, _reason} ->
        :ok
    end
  end

  defp maybe_delete(path, now, min_age_seconds) do
    case File.stat(path, time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} ->
        if now - mtime >= min_age_seconds do
          LocalDisk.delete(path)
        end

      {:error, _reason} ->
        :ok
    end
  end
end
