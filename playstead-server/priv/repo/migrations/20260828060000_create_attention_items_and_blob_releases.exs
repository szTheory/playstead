defmodule Playstead.Repo.Migrations.CreateAttentionItemsAndBlobReleases do
  use Ecto.Migration

  def change do
    # D-26: the inbox table. No expires_at column and no cron sweep
    # anywhere references this table — nothing here ages out.
    create table(:attention_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :reason, :string, null: false
      add :grouping_key, :string, null: false
      add :import_session_id, :string

      add :source_file_id, references(:source_files, type: :binary_id, on_delete: :nilify_all)
      add :asset_set_id, references(:asset_sets, type: :binary_id, on_delete: :nilify_all)
      add :blob_id, references(:blobs, type: :binary_id, on_delete: :nilify_all)

      add :status, :string, null: false, default: "open"
      add :resolved_at, :utc_datetime
      add :count, :integer, null: false, default: 1
      add :evidence, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:attention_items, [:user_id, :status])

    # D-26/D-21: exactly one grouped archives item per import — the
    # collision authority `Playstead.Attention.raise_item/1`'s
    # `on_conflict` upsert relies on.
    create unique_index(:attention_items, [:user_id, :grouping_key, :reason],
             name: :attention_items_user_grouping_reason_index
           )

    # D-28: the machine quarantine verdict lives on the shared blob
    # (blobs.scan_state); the release decision is per user and belongs
    # here, on the user's own record — a release by one user never
    # touches another's row.
    create table(:blob_releases, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :blob_id, references(:blobs, type: :binary_id, on_delete: :delete_all), null: false
      add :resolution, :string, null: false
      add :released_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:blob_releases, [:user_id, :blob_id])
  end
end
