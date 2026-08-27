defmodule Playstead.Repo.Migrations.CreateChangeJournalEntries do
  use Ecto.Migration

  def change do
    # D-21: the recovery spine for PROT-05. `seq` is a database-assigned
    # bigserial. Commit-order fencing (the subtle correctness property:
    # a reader must never observe seq N+1 while seq N is still
    # uncommitted) is enforced entirely on the *write* side —
    # `Playstead.Sync.ChangeJournal.write/5` holds a transaction-scoped
    # Postgres advisory lock (`pg_advisory_xact_lock/1`) for the whole
    # writing transaction, so `seq` assignment is serialized with commit:
    # a second writer cannot acquire a new `seq` until the first writer's
    # transaction has committed or rolled back. This guarantees
    # seq-assignment order and commit order are always the same
    # ordering, which is what makes a plain `WHERE seq > cursor ORDER BY
    # seq` read on the other side (`ChangeJournal.read_after/3`) safe —
    # no separate read-side fencing query is needed.
    create table(:change_journal_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :seq, :bigserial, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :entity_kind, :string, null: false
      add :entity_id, :string, null: false
      # "upsert" or "tombstone" (T-01-47: tombstone payload is always
      # empty — a deletion reveals nothing about the deleted content).
      add :operation, :string, null: false
      add :payload, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:change_journal_entries, [:seq])
    create index(:change_journal_entries, [:user_id, :seq])
    create index(:change_journal_entries, [:inserted_at])
  end
end
