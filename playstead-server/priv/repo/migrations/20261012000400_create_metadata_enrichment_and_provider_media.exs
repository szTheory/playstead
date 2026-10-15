defmodule Playstead.Repo.Migrations.CreateMetadataEnrichmentAndProviderMedia do
  use Ecto.Migration

  def change do
    alter table(:metadata_provider_evidence) do
      add :media_references, :map, null: false, default: %{}
    end

    create table(:metadata_enrichment_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :asset_set_id, references(:asset_sets, type: :binary_id, on_delete: :delete_all),
        null: false

      add :provider, :string, null: false, default: "igdb"
      add :query_fingerprint, :string, null: false
      add :policy_revision, :string, null: false
      add :mode, :string, null: false
      add :state, :string, null: false, default: "queued"
      add :progress, :map, null: false, default: %{}
      add :results, :map, null: false, default: %{}
      add :request_estimate, :integer, null: false, default: 1
      add :byte_estimate, :bigint, null: false, default: 0
      add :storage_estimate, :bigint, null: false, default: 0
      add :attempt_count, :integer, null: false, default: 0
      add :last_error, :string
      add :retry_after_at, :utc_datetime
      add :cancel_requested_at, :utc_datetime
      add :started_at, :utc_datetime
      add :finished_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:metadata_enrichment_jobs, [:user_id, :state])
    create index(:metadata_enrichment_jobs, [:asset_set_id, :inserted_at])

    create unique_index(
             :metadata_enrichment_jobs,
             [:user_id, :asset_set_id, :provider, :query_fingerprint],
             name: :metadata_enrichment_jobs_active_unique,
             where: "state IN ('queued', 'running')"
           )

    create table(:metadata_request_budgets, primary_key: false) do
      add :id, :integer, primary_key: true
      add :next_allowed_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    execute "INSERT INTO metadata_request_budgets (id, next_allowed_at, updated_at) VALUES (1, now(), now())",
            "DELETE FROM metadata_request_budgets WHERE id = 1"

    create table(:metadata_provider_media, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :asset_set_id, references(:asset_sets, type: :binary_id, on_delete: :delete_all),
        null: false

      add :provider, :string, null: false, default: "igdb"
      add :image_id, :string, null: false
      add :size, :string, null: false
      add :object_key, :string, null: false
      add :sha256, :string, null: false
      add :size_bytes, :bigint, null: false
      add :pinned, :boolean, null: false, default: false
      add :legally_refetchable, :boolean, null: false, default: false
      add :cache_expires_at, :utc_datetime, null: false
      add :license_expires_at, :utc_datetime
      add :last_accessed_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:metadata_provider_media, [:user_id, :asset_set_id, :image_id, :size],
             name: :metadata_provider_media_identity_index
           )

    create index(:metadata_provider_media, [:user_id, :last_accessed_at])

    create constraint(:metadata_provider_media, :metadata_provider_media_size_positive,
             check: "size_bytes > 0"
           )
  end
end
