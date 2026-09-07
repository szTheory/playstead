defmodule Playstead.Repo.Migrations.AddSavesScopeToExportRecords do
  use Ecto.Migration

  def change do
    # D-57: unlike `include_excluded`, `saves_scope` is a user choice
    # and must be persisted so a re-enqueued or resumed job reproduces
    # the same plan rather than reading a default.
    alter table(:exports) do
      add :saves_scope, :string, null: false, default: "all"
    end

    create constraint(:exports, :saves_scope_must_be_known,
             check: "saves_scope IN ('all', 'none')"
           )
  end
end
