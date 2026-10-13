defmodule Playstead.Repo.Migrations.AddMetadataFieldRevisionsAndConflicts do
  use Ecto.Migration

  def change do
    alter table(:metadata_selections) do
      add_if_not_exists :field_revisions, :map, null: false, default: %{}
      add_if_not_exists :selections, :map, null: false, default: %{}
      add_if_not_exists :field_sources, :map, null: false, default: %{}
      add_if_not_exists :deleted_fields, :map, null: false, default: %{}
      add_if_not_exists :evidence, :map, null: false, default: %{}
    end

    create table(:metadata_conflicts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :asset_set_id,
          references(:asset_sets, type: :binary_id, on_delete: :delete_all),
          null: false

      add :field, :string, null: false
      add :base_revision, :integer, null: false
      add :current_revision, :integer, null: false
      add :current_alternative, :map, null: false
      add :incoming_alternative, :map, null: false
      add :resolved_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:metadata_conflicts, [:user_id, :asset_set_id, :field, :resolved_at])

    create constraint(:metadata_conflicts, :metadata_conflicts_revisions_valid,
             check: "base_revision >= 0 AND current_revision > 0"
           )
  end
end
