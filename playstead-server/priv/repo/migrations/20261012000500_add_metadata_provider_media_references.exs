defmodule Playstead.Repo.Migrations.AddMetadataProviderMediaReferences do
  use Ecto.Migration

  def change do
    alter table(:metadata_provider_evidence) do
      add_if_not_exists :media_references, :map, null: false, default: %{}
    end
  end
end
