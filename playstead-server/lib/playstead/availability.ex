defmodule Playstead.Availability do
  @moduledoc """
  Plan 03-13 (LIBR-02 gap closure): the device-reported availability
  read model. Each paired device reports its own per-asset-set facts
  (downloading/verified/pinned/missing_dependency/download_percent);
  the server stores them per device and merges them per user at read
  time — the console never derives these facts itself.

  `replace_for_device/2` performs a full replacement of one device's
  reported rows inside a single `Ecto.Multi` transaction, so a failed
  report can never leave a device with a partially-cleared row set
  (T-03-13-05). `facts_for_user/1` merges across all of a user's
  devices using the "true on any device" rule decided at this plan's
  Task 1 checkpoint: a boolean fact is true if true on any device, and
  `download_percent` is the maximum across devices.

  Every query here is scope-first (T-03-13-02): `replace_for_device/2`
  filters incoming entries to asset sets owned by the reporting
  device's own user before any insert, and `facts_for_user/1` only ever
  reads rows already scoped to `user_id`. A device can never write, and
  a user can never read, another user's reported facts.

  This read model is a convenience view only (T-03-13-03, accepted
  spoofing risk): the launch path never consults it, and the Mac
  client's own `AvailabilityState.derive` remains the sole authority
  for whether a game can actually start.
  """

  import Ecto.Query, warn: false

  alias Playstead.Availability.DeviceReport
  alias Playstead.Catalogue.AssetSet
  alias Playstead.Repo

  # Matches the order of magnitude of D-10's queue cap (500) with
  # headroom for a large multi-system library; a report above this size
  # is rejected outright rather than streamed into a transaction
  # (T-03-13-04).
  @max_entries 5000

  @doc """
  Fully replaces `device`'s reported rows with `entries` inside one
  transaction. `entries` is a list of maps (string- or atom-keyed) with
  an `asset_set_id` and any of `downloading`, `verified`, `pinned`,
  `missing_dependency`, `download_percent`.

  Entries naming an asset set not owned by `device.user_id` are
  silently dropped before insert — no row is ever written for them.
  An entry with a `download_percent` outside 0..100 fails the whole
  call with a changeset error rather than being clamped. A call with
  more than #{@max_entries} entries is rejected outright with
  `{:error, :too_many_entries}`.
  """
  @spec replace_for_device(Playstead.Pairing.Device.t(), [map()]) ::
          {:ok, :replaced} | {:error, term()}
  def replace_for_device(device, entries) when is_list(entries) do
    if length(entries) > @max_entries do
      {:error, :too_many_entries}
    else
      normalized = Enum.map(entries, &normalize_entry/1)
      owned_ids = owned_asset_set_ids(device.user_id, normalized)
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      changesets =
        normalized
        |> Enum.filter(&MapSet.member?(owned_ids, Map.get(&1, "asset_set_id")))
        |> Enum.map(&build_changeset(device, now, &1))

      multi =
        changesets
        |> Enum.with_index()
        |> Enum.reduce(
          Ecto.Multi.new()
          |> Ecto.Multi.delete_all(
            :delete_existing,
            from(r in DeviceReport, where: r.device_id == ^device.id)
          ),
          fn {changeset, index}, multi ->
            Ecto.Multi.insert(multi, {:report, index}, changeset)
          end
        )

      case Repo.transaction(multi) do
        {:ok, _changes} -> {:ok, :replaced}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  @doc """
  Returns a map of `asset_set_id => facts` for every asset set any of
  `user_id`'s paired devices has reported on, merged by the any-device
  rule. Returns facts only — `downloading`, `download_percent`,
  `verified`, `pinned`, `missing_dependency` — never a computed ladder
  rank or state (D-21): no key here ever names a rank, and no column
  in the underlying table is named `state`, `rank`, or
  `availability_state`.
  """
  @spec facts_for_user(pos_integer()) :: %{optional(String.t()) => map()}
  def facts_for_user(user_id) do
    DeviceReport
    |> where([r], r.user_id == ^user_id)
    |> Repo.all()
    |> Enum.group_by(& &1.asset_set_id)
    |> Map.new(fn {asset_set_id, rows} -> {asset_set_id, merge_rows(rows)} end)
  end

  defp merge_rows(rows) do
    Enum.reduce(
      rows,
      %{
        downloading: false,
        download_percent: 0,
        verified: false,
        pinned: false,
        missing_dependency: false
      },
      fn row, acc ->
        %{
          downloading: acc.downloading or row.downloading,
          download_percent: max(acc.download_percent, row.download_percent),
          verified: acc.verified or row.verified,
          pinned: acc.pinned or row.pinned,
          missing_dependency: acc.missing_dependency or row.missing_dependency
        }
      end
    )
  end

  defp normalize_entry(entry) do
    Map.new(entry, fn {k, v} -> {to_string(k), v} end)
  end

  defp owned_asset_set_ids(user_id, normalized_entries) do
    ids =
      normalized_entries
      |> Enum.map(&Map.get(&1, "asset_set_id"))
      |> Enum.reject(&is_nil/1)

    AssetSet
    |> where([a], a.user_id == ^user_id and a.id in ^ids)
    |> select([a], a.id)
    |> Repo.all()
    |> MapSet.new()
  rescue
    Ecto.Query.CastError -> MapSet.new()
  end

  defp build_changeset(device, now, entry) do
    attrs =
      entry
      |> Map.take(["downloading", "verified", "pinned", "missing_dependency", "download_percent"])
      |> Map.merge(%{
        "device_id" => device.id,
        "user_id" => device.user_id,
        "asset_set_id" => Map.get(entry, "asset_set_id"),
        "reported_at" => now
      })

    DeviceReport.changeset(%DeviceReport{}, attrs)
  end
end
