defmodule Playstead.Repo.Migrations.AddCommandIdToDeviceCredentials do
  use Ecto.Migration

  def change do
    # D-20b: client-generated UUIDv7 natural key for the rotate_credential
    # effect. Nullable — Postgres unique indexes allow any number of
    # NULLs, so rows minted before this column existed (or via a caller
    # that supplies no command_id) are unaffected. A replayed rotation
    # with the same command_id converges to this row via on_conflict
    # upsert rather than minting a second credential.
    alter table(:device_credentials) do
      add :command_id, :string
    end

    create unique_index(:device_credentials, [:command_id])
  end
end
