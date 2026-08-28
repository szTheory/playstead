defmodule Playstead.Repo.Migrations.CreateBlobs do
  use Ecto.Migration

  def change do
    # D-11, D-13: blobs are global, content-addressed, and carry no
    # user column — physical bytes are shared, every logical record
    # (source_files, asset_members) is user-scoped and references a
    # blob. The unique index on sha256 is the collision authority the
    # write path relies on instead of a check-then-act exists? read.
    create table(:blobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :sha256, :string, null: false
      add :size_bytes, :bigint, null: false
      add :crc32, :string
      add :md5, :string
      add :sha1, :string
      add :scan_state, :string, null: false, default: "clean"
      add :scan_reason, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:blobs, [:sha256])

    create table(:blob_fingerprints, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :blob_id, references(:blobs, type: :binary_id, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :offset, :bigint, null: false
      add :crc32, :string
      add :md5, :string
      add :sha1, :string

      timestamps(type: :utc_datetime)
    end

    create index(:blob_fingerprints, [:blob_id])
  end
end
