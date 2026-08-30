defmodule Playstead.Repo.Migrations.CreateCurationOrderedLists do
  use Ecto.Migration

  def change do
    # D-09/D-10: manual, flat, ordered collections. `position` is a
    # fractional-index string (Playstead.Curation.Position) so listing
    # in order is a plain index scan.
    create table(:curation_collections, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :position, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:curation_collections, [:user_id, :position])

    create table(:curation_collection_members, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :collection_id,
          references(:curation_collections, type: :binary_id, on_delete: :delete_all),
          null: false

      add :asset_set_id, references(:asset_sets, type: :binary_id, on_delete: :delete_all),
        null: false

      add :position, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:curation_collection_members, [:collection_id, :asset_set_id])
    create index(:curation_collection_members, [:collection_id, :position])

    # D-07/D-09: one play queue per user -- a backlog/watchlist, never a
    # per-device playback buffer.
    create table(:curation_queue_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :asset_set_id, references(:asset_sets, type: :binary_id, on_delete: :delete_all),
        null: false

      add :position, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:curation_queue_items, [:user_id, :asset_set_id])
    create index(:curation_queue_items, [:user_id, :position])
  end
end
