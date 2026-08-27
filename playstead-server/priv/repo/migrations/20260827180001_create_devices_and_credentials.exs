defmodule Playstead.Repo.Migrations.CreateDevicesAndCredentials do
  use Ecto.Migration

  def change do
    # D-10: device identity and device credential are separate tables so
    # rotation and re-pairing preserve device history.
    create table(:devices, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false

      # Owner-editable; never overwritten by the client's self-report.
      add :name, :string
      # The client's self-report, preserved separately (D-11).
      add :claimed_name, :string
      add :platform, :string
      add :app_version, :string

      add :paired_at, :utc_datetime, null: false
      add :last_seen_at, :utc_datetime
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:devices, [:user_id])

    create table(:device_credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :device_id, references(:devices, type: :binary_id, on_delete: :delete_all), null: false

      # Only the hash is ever stored (D-10); the plaintext is returned
      # exactly once at issuance and never again.
      add :token_hash, :string, null: false
      # SHA-256 fingerprint prefix for the console — it never sees the
      # token itself.
      add :fingerprint_prefix, :string

      add :activated_at, :utc_datetime
      add :last_used_at, :utc_datetime

      # Use-activated rotation handoff: the old row stays valid, marked
      # superseded, until the new one is first used.
      add :superseded_by_id, references(:device_credentials, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:device_credentials, [:device_id])
    create unique_index(:device_credentials, [:token_hash])
  end
end
