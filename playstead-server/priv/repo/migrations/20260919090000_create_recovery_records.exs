defmodule Playstead.Repo.Migrations.CreateRecoveryRecords do
  use Ecto.Migration

  def change do
    create table(:recovery_records, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :kind, :string, null: false
      add :state, :string, null: false
      add :destination_root, :text, null: false
      add :correlation_id, :uuid, null: false
      # This is the immutable recovery command: the worker never rebuilds
      # its inventory from mutable request input on a retry.
      add :command, :map, null: false
      add :parent_receipt_id, :string
      add :receipt, :map
      add :failure_evidence, :map
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:recovery_records, [:correlation_id])
    create index(:recovery_records, [:state, :inserted_at])
  end
end
