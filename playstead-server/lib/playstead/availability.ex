defmodule Playstead.Availability do
  @moduledoc """
  Plan 03-13 (LIBR-02 gap closure): the device-reported availability
  read model. Each paired device reports its own per-asset-set facts
  (downloading/verified/pinned/missing_dependency/download_percent);
  the server stores them per device and merges them per user at read
  time — the console never derives these facts itself.

  `replace_for_device/3` performs a full replacement of one device's
  reported rows inside a single `Ecto.Multi` transaction, so a failed
  report can never leave a device with a partially-cleared row set
  (T-03-13-05). Sequence-bearing replacements advance a durable
  per-device watermark in that same transaction. Only a strictly newer
  sequence can replace rows; requests without a sequence keep the legacy
  replacement behavior and have no ordering guarantee. `facts_for_user/1`
  merges across all of a user's
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
  @max_report_sequence 9_223_372_036_854_775_807

  @sequence_guard_sql """
  INSERT INTO device_availability_report_watermarks
    (device_id, accepted_report_sequence, inserted_at, updated_at)
  VALUES ($1, $2, NOW(), NOW())
  ON CONFLICT (device_id) DO UPDATE
  SET accepted_report_sequence = EXCLUDED.accepted_report_sequence,
      updated_at = EXCLUDED.updated_at
  WHERE device_availability_report_watermarks.accepted_report_sequence < EXCLUDED.accepted_report_sequence
  RETURNING device_id
  """

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
    replace_for_device(device, entries, nil)
  end

  @spec replace_for_device(Playstead.Pairing.Device.t(), [map()], nil | pos_integer()) ::
          {:ok, :replaced} | {:error, term()}
  def replace_for_device(device, entries, report_sequence) when is_list(entries) do
    cond do
      length(entries) > @max_entries ->
        {:error, :too_many_entries}

      not valid_report_sequence?(report_sequence) ->
        {:error,
         {:validation_failed, "The \"report_sequence\" field must be a positive integer."}}

      true ->
        normalized = Enum.map(entries, &normalize_entry/1)
        owned_ids = owned_asset_set_ids(device.user_id, normalized)
        now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

        changesets =
          normalized
          |> Enum.filter(&MapSet.member?(owned_ids, Map.get(&1, "asset_set_id")))
          |> Enum.map(&build_changeset(device, now, &1))

        multi =
          Ecto.Multi.new()
          |> add_report_sequence_guard(device.id, report_sequence)
          |> Ecto.Multi.delete_all(
            :delete_existing,
            from(r in DeviceReport, where: r.device_id == ^device.id)
          )
          |> then(fn multi ->
            changesets
            |> Enum.with_index()
            |> Enum.reduce(multi, fn {changeset, index}, multi ->
              Ecto.Multi.insert(multi, {:report, index}, changeset)
            end)
          end)

        case Repo.transaction(multi) do
          {:ok, _changes} ->
            {:ok, :replaced}

          {:error, :report_sequence, :stale_report_sequence, _changes} ->
            {:error,
             {:validation_failed,
              "The \"report_sequence\" must be greater than the last accepted sequence."}}

          {:error, _step, reason, _changes} ->
            {:error, reason}
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

  defp add_report_sequence_guard(multi, _device_id, nil), do: multi

  defp add_report_sequence_guard(multi, device_id, report_sequence) do
    Ecto.Multi.run(multi, :report_sequence, fn repo, _changes ->
      case repo.query(@sequence_guard_sql, [Ecto.UUID.dump!(device_id), report_sequence]) do
        {:ok, %{num_rows: 1}} ->
          {:ok, :advanced}

        {:ok, %{num_rows: 0}} ->
          {:error, :stale_report_sequence}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  defp valid_report_sequence?(nil), do: true

  defp valid_report_sequence?(sequence) do
    is_integer(sequence) and sequence > 0 and sequence <= @max_report_sequence
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
