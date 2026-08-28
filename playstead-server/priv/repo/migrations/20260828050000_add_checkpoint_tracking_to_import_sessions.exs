defmodule Playstead.Repo.Migrations.AddCheckpointTrackingToImportSessions do
  use Ecto.Migration

  def change do
    # D-09/D-30: throttled journal checkpoints track their own last-fired
    # position so `Playstead.Import.Progress.checkpoint/2` never needs to
    # re-derive it from the journal itself.
    alter table(:import_sessions) do
      add :last_checkpoint_at, :utc_datetime_usec
      add :last_checkpointed_bytes, :bigint
    end
  end
end
