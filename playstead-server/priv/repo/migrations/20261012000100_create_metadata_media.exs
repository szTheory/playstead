defmodule Playstead.Repo.Migrations.CreateMetadataMedia do
  use Ecto.Migration

  def change do
    create table(:metadata_media, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :asset_set_id, references(:asset_sets, type: :binary_id, on_delete: :delete_all),
        null: false

      add :original_sha256, :string, null: false, size: 64
      add :original_size_bytes, :bigint, null: false
      add :original_mime, :string, null: false
      add :derived_sha256, :string, size: 64
      add :derived_size_bytes, :bigint
      add :provenance, :map, null: false, default: %{}
      timestamps(type: :utc_datetime)
    end

    create index(:metadata_media, [:user_id, :asset_set_id, :inserted_at])

    create constraint(:metadata_media, :metadata_media_original_size_positive,
             check: "original_size_bytes > 0"
           )

    create constraint(:metadata_media, :metadata_media_derived_pair,
             check: "(derived_sha256 IS NULL) = (derived_size_bytes IS NULL)"
           )

    create constraint(:metadata_media, :metadata_media_kind_valid,
             check: "original_mime IN ('text/plain', 'image/png', 'image/jpeg')"
           )
  end
end
