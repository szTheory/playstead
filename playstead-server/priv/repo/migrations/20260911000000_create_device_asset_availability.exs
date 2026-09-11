defmodule Playstead.Repo.Migrations.CreateDeviceAssetAvailability do
  use Ecto.Migration

  def change do
    # Plan 03-13 (LIBR-02 gap closure): per-device reported availability
    # facts (D-21 — facts only, never a computed/stored ladder rank).
    # `replace_for_device/2` fully replaces a device's row set inside one
    # transaction, so a stale row can never survive a report.
    create table(:device_asset_availability, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :device_id, references(:devices, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :asset_set_id, references(:asset_sets, type: :binary_id, on_delete: :delete_all),
        null: false

      add :downloading, :boolean, null: false, default: false
      add :verified, :boolean, null: false, default: false
      add :pinned, :boolean, null: false, default: false
      add :missing_dependency, :boolean, null: false, default: false
      add :download_percent, :integer, null: false, default: 0
      add :reported_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:device_asset_availability, [:device_id, :asset_set_id])
    create index(:device_asset_availability, [:user_id, :asset_set_id])

    create constraint(:device_asset_availability, :download_percent_range,
             check: "download_percent >= 0 AND download_percent <= 100"
           )
  end
end
