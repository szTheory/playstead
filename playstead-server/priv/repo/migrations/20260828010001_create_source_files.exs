defmodule Playstead.Repo.Migrations.CreateSourceFiles do
  use Ecto.Migration

  def change do
    # D-08: user-scoped; blob_id is nullable while an import is in
    # flight. original_name is stored byte-exact -- never sanitized on
    # write, since it is raw material for the reconcile fingerprint.
    create table(:source_files, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :blob_id, references(:blobs, type: :binary_id, on_delete: :nilify_all)
      add :original_name, :string, null: false
      add :origin, :string, null: false
      add :relative_path, :string
      add :size_bytes, :bigint, null: false
      add :mtime, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:source_files, [:user_id])
    create index(:source_files, [:blob_id])
  end
end
