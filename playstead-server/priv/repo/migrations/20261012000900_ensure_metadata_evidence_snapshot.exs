defmodule Playstead.Repo.Migrations.EnsureMetadataEvidenceSnapshot do
  use Ecto.Migration

  def change do
    alter table(:metadata_selections) do
      add_if_not_exists :evidence, :map, null: false, default: %{}
    end
  end
end
