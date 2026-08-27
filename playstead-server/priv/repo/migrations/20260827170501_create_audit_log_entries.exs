defmodule Playstead.Repo.Migrations.CreateAuditLogEntries do
  use Ecto.Migration

  def change do
    # Append-only (D-05a, D-12, T-01-18): Playstead.AuditLog.record/3 is the
    # only write path. No update or delete function exists anywhere in the
    # application for this table.
    create table(:audit_log_entries) do
      add :user_id, references(:users, on_delete: :nilify_all)
      add :event, :string, null: false
      add :subject, :string
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:audit_log_entries, [:user_id])
    create index(:audit_log_entries, [:event])
  end
end
