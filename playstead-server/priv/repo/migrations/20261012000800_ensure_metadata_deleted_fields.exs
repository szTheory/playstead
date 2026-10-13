defmodule Playstead.Repo.Migrations.EnsureMetadataDeletedFields do
  use Ecto.Migration

  def change do
    alter table(:metadata_selections) do
      add_if_not_exists :deleted_fields, :map, null: false, default: %{}
    end
  end
end
