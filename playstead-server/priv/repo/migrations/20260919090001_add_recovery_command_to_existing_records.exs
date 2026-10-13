defmodule Playstead.Repo.Migrations.AddRecoveryCommandToExistingRecords do
  use Ecto.Migration

  @legacy_command ~s({"schema":"playstead.recovery-command.v1","legacy_unrecoverable":true})

  def up do
    # `20260919090000` may already have been applied by an early Phase 05
    # checkout. Never rewrite its history: add the column independently and
    # fail in-flight legacy work rather than allowing it to infer new scope.
    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'recovery_records' AND column_name = 'command'
      ) THEN
        ALTER TABLE recovery_records ADD COLUMN command jsonb;
      END IF;
    END $$;
    """)

    execute("""
    UPDATE recovery_records
    SET state = 'failed',
        failure_evidence = jsonb_build_object('reason', 'legacy_recovery_command_missing'),
        updated_at = NOW()
    WHERE state IN ('planned', 'staging', 'verifying')
    """)

    execute(
      "UPDATE recovery_records SET command = '#{@legacy_command}'::jsonb WHERE command IS NULL"
    )

    alter table(:recovery_records) do
      modify :command, :map, null: false
    end
  end

  def down do
    execute("ALTER TABLE recovery_records DROP COLUMN IF EXISTS command")
  end
end
