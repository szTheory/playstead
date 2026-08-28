defmodule Playstead.Repo.Migrations.CreateAssetSetsAndMembers do
  use Ecto.Migration

  def change do
    # D-37: member_fingerprint is the natural key; the unique index on
    # the user/fingerprint pair makes "no duplicate logical record" a
    # database guarantee rather than an application intention.
    create table(:asset_sets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :system_id, :string
      add :system_source, :string
      add :display_title, :string
      add :title_source, :string
      add :status, :string, null: false, default: "active"
      add :member_fingerprint, :string, null: false
      add :excluded_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:asset_sets, [:user_id, :member_fingerprint])

    create table(:asset_members, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :asset_set_id, references(:asset_sets, type: :binary_id, on_delete: :delete_all),
        null: false

      add :ordinal, :integer, null: false
      add :role, :string, null: false
      add :required, :boolean, null: false, default: true
      add :blob_id, references(:blobs, type: :binary_id, on_delete: :nilify_all)
      add :declared_name, :string
      add :export_path, :string

      timestamps(type: :utc_datetime)
    end

    create index(:asset_members, [:asset_set_id])
    create index(:asset_members, [:blob_id])
  end
end
