defmodule Playstead.Repo.Migrations.AddMetadataProviderDescription do
  use Ecto.Migration

  def change do
    alter table(:metadata_provider_evidence) do
      add :provider_description, :text
    end
  end
end
