defmodule Playstead.Repo.Migrations.CreatePairingRequests do
  use Ecto.Migration

  def change do
    create table(:pairing_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # D-08: only the hash of the client-generated device_code is ever
      # stored — the plaintext is never persisted.
      add :device_code_hash, :string, null: false
      # D-07/D-08: visual-comparison-only, never an authorization input.
      add :display_code, :string, null: false

      # Claimed fields are named to make their untrusted, client-reported
      # provenance obvious at every read site (D-09).
      add :claimed_device_name, :string
      add :claimed_platform, :string
      add :claimed_app_version, :string
      add :claimed_capabilities, :map, null: false, default: %{}

      # Observed field: taken only from the trusted proxy hop (D-09).
      add :requesting_ip, :string

      add :status, :string, null: false, default: "pending"
      add :approved_by_user_id, references(:users, on_delete: :nilify_all)
      add :expires_at, :utc_datetime, null: false
      add :redeemed_at, :utc_datetime

      # usec precision (not the app-wide default): eviction picks the
      # single oldest pending row, and the app-wide :utc_datetime second
      # truncation ties every request created within the same second,
      # making "oldest" ambiguous under any real pairing-request burst.
      timestamps(type: :utc_datetime_usec)
    end

    create index(:pairing_requests, [:status])
    create index(:pairing_requests, [:status, :inserted_at])
    create unique_index(:pairing_requests, [:device_code_hash])
  end
end
