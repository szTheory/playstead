defmodule Playstead.Repo.Migrations.CreateOperationsFailureEvidence do
  use Ecto.Migration

  def change do
    create table(:operations_failure_evidence, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :correlation_id, :uuid, null: false
      add :subsystem, :string, null: false
      add :code, :string, null: false
      add :state, :string, null: false, default: "failed"
      timestamps(type: :utc_datetime_usec)
    end

    create index(:operations_failure_evidence, [:correlation_id, :inserted_at])
  end
end
