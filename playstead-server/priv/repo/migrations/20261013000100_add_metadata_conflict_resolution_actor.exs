defmodule Playstead.Repo.Migrations.AddMetadataConflictResolutionActor do
  use Ecto.Migration

  def change do
    alter table(:metadata_conflicts) do
      add :resolved_by_device_id, :binary_id
    end
  end
end
