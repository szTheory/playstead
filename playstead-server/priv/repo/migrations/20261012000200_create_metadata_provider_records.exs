defmodule Playstead.Repo.Migrations.CreateMetadataProviderRecords do
  use Ecto.Migration

  def change do
    create table(:metadata_provider_consents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :asset_set_id, references(:asset_sets, type: :binary_id, on_delete: :delete_all),
        null: false

      add :provider, :string, null: false
      add :enabled, :boolean, null: false, default: false
      add :revision, :integer, null: false, default: 1
      add :disclosure_revision, :string
      add :disclosed_title, :string
      add :disclosed_system, :string
      add :image_terms_revision, :string
      add :image_grant_scope, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:metadata_provider_consents, [:user_id, :asset_set_id, :provider],
             name: :metadata_provider_consents_owner_asset_provider_index
           )

    create constraint(:metadata_provider_consents, :metadata_provider_consents_revision_positive,
             check: "revision > 0"
           )

    create table(:metadata_provider_evidence, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :asset_set_id, references(:asset_sets, type: :binary_id, on_delete: :delete_all),
        null: false

      add :provider, :string, null: false
      add :provider_version, :string, null: false
      add :external_id, :bigint, null: false
      add :title, :string, null: false
      add :platform_id, :integer, null: false
      add :platform, :string, null: false
      add :confidence, :string, null: false
      add :match_kind, :string, null: false, default: "suggestion"
      add :attribution, :string, null: false
      add :terms_url, :string, null: false
      add :policy_revision, :string, null: false
      add :cache_expires_at, :utc_datetime, null: false
      add :license_expires_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:metadata_provider_evidence, [:user_id, :asset_set_id, :provider])

    create constraint(:metadata_provider_evidence, :metadata_provider_evidence_confidence_valid,
             check: "confidence IN ('high', 'low')"
           )

    create constraint(:metadata_provider_evidence, :metadata_provider_evidence_suggestion_only,
             check: "match_kind = 'suggestion'"
           )
  end
end
