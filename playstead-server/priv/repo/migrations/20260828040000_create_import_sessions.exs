defmodule Playstead.Repo.Migrations.CreateImportSessions do
  use Ecto.Migration

  def change do
    # D-05/D-06: the session id is client-supplied (like a command_id),
    # so the same session enqueue request is idempotent by construction.
    # `state` is the persisted lifecycle; `requested_control` is a
    # separately-stored column re-read by the worker between every file
    # rather than cached (the pairing-request schema idiom).
    create table(:import_sessions, primary_key: false) do
      add :id, :string, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :origin, :string, null: false
      add :state, :string, null: false, default: "staged"
      add :requested_control, :string, null: false, default: "run"

      add :file_count, :integer, null: false, default: 0
      add :total_bytes, :bigint, null: false, default: 0
      add :files_completed, :integer, null: false, default: 0
      add :bytes_completed, :bigint, null: false, default: 0
      add :counts_by_outcome, :map, null: false, default: %{}

      add :enumeration_completed_at, :utc_datetime_usec
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec

      # usec precision: a fast burst of sessions (or a resumed session's
      # rows) must have deterministic ordering the same way pairing
      # requests do.
      timestamps(type: :utc_datetime_usec)
    end

    create index(:import_sessions, [:user_id])
    create index(:import_sessions, [:state])

    create constraint(:import_sessions, :state_must_be_known,
             check: "state IN ('staged', 'running', 'paused', 'completed', 'cancelled', 'failed')"
           )

    create constraint(:import_sessions, :requested_control_must_be_known,
             check: "requested_control IN ('run', 'pause', 'cancel')"
           )

    # D-08: the reconcile fingerprint (origin, relative_path, size_bytes,
    # mtime) already exists on source_files from plan 02-02 -- this only
    # adds session membership, per-row staging state, and the bounded
    # retry counter the session worker needs.
    alter table(:source_files) do
      add :import_session_id, references(:import_sessions, type: :string, on_delete: :nilify_all)
      add :staging_state, :string
      add :attempt_count, :integer, null: false, default: 0
      add :last_failure_reason, :string
    end

    create index(:source_files, [:import_session_id])

    create constraint(:source_files, :staging_state_must_be_known,
             check:
               "staging_state IS NULL OR staging_state IN ('pending', 'completed', 'skipped', 'failed')"
           )

    # Deterministic per-session ordering (relative_path) and the
    # reconcile lookup key, scoped to the owning user so two users'
    # sessions can never collide.
    create index(:source_files, [:import_session_id, :relative_path])
    create index(:source_files, [:user_id, :origin, :relative_path, :size_bytes, :mtime])
  end
end
