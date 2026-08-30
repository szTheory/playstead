defmodule Playstead.Repo.Migrations.CreateCurationFavorites do
  use Ecto.Migration

  def change do
    # D-08/D-09: client-supplied binary_id primary key (UUIDv7 natural
    # key) so a repeated favorite intent converges through the unique
    # index below rather than duplicating.
    create table(:curation_favorites, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :asset_set_id, references(:asset_sets, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:curation_favorites, [:user_id, :asset_set_id])
    create index(:curation_favorites, [:user_id])
  end
end
