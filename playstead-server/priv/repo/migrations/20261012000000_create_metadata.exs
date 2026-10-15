defmodule Playstead.Repo.Migrations.CreateMetadata do
  use Ecto.Migration

  def change do
    create table(:metadata_selections, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :asset_set_id,
          references(:asset_sets, type: :binary_id, on_delete: :delete_all),
          null: false

      add :description, :text, null: false
      add :revision, :integer, null: false
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:metadata_selections, [:user_id, :asset_set_id])
    create index(:metadata_selections, [:asset_set_id])
  end
end
