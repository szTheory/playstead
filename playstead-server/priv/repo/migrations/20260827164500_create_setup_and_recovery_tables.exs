defmodule Playstead.Repo.Migrations.CreateSetupAndRecoveryTables do
  use Ecto.Migration

  def change do
    create table(:setup_tokens) do
      add :token_hash, :binary, null: false
      add :consumed_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    # Only the DB-level guarantee (not application logic alone) makes the
    # two-concurrent-claims property in OPER-02's edge probe hold: the
    # `claim/2` transaction's `UPDATE ... WHERE consumed_at IS NULL` is
    # what actually serializes the race, but this index still protects
    # against ever storing two active (unconsumed) tokens with the same
    # hash.
    create unique_index(:setup_tokens, [:token_hash])

    create table(:recovery_codes) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :code_hash, :string, null: false
      add :consumed_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:recovery_codes, [:user_id])
  end
end
