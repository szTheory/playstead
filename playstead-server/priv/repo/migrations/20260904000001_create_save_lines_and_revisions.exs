defmodule Playstead.Repo.Migrations.CreateSaveLinesAndRevisions do
  use Ecto.Migration

  def change do
    # D-10: save-line identity is (user_id, content_key, save_kind, slot),
    # never asset_set_id -- content_key is the ROM sha256 so a re-import
    # cannot orphan every save on a game. Client-suppliable binary_id
    # primary key, following curation's D-08/D-09 shape.
    create table(:save_lines, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :content_key, :string, null: false
      add :save_kind, :string, null: false, default: "battery"
      add :slot, :string, null: false, default: "0"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:save_lines, [:user_id, :content_key, :save_kind, :slot])
    create index(:save_lines, [:user_id])

    # D-09/D-11: immutable parent-pointer revision DAG. NULL
    # parent_revision_id means root. D-10's Discretion note: the
    # (save_line_id, parent_revision_id) index is required for
    # branch-head derivation (a head is a revision with no children).
    create table(:save_revisions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :save_line_id, references(:save_lines, type: :binary_id, on_delete: :delete_all), null: false

      add :parent_revision_id, references(:save_revisions, type: :binary_id, on_delete: :nilify_all)

      add :blob_sha256, :string, null: false
      add :size_bytes, :integer, null: false
      add :origin_device_id, references(:devices, type: :binary_id, on_delete: :nilify_all)

      # D-15: device-claimed time is stored as evidence only, never
      # orderable. `recorded_at` (server-assigned) is the only orderable
      # time.
      add :device_captured_at, :utc_datetime_usec
      add :recorded_at, :utc_datetime_usec, null: false

      # D-17: provenance carried from day one.
      add :capture_method, :string
      add :adapter_id, :string
      add :adapter_version, :string
      add :save_format, :string
      add :format_confidence, :string
      add :play_session_id, :binary_id

      timestamps(type: :utc_datetime)
    end

    create index(:save_revisions, [:save_line_id, :parent_revision_id])
    create index(:save_revisions, [:user_id])
    create index(:save_revisions, [:blob_sha256])

    # D-16: the streamed-upload half cannot fingerprint a body, so the
    # PUT endpoint commits bytes into the CAS and records the resulting
    # digest here, keyed by the client-supplied command_id, for the
    # POST metadata-commit half to look up. TTL'd (`expires_at`); a
    # future sweep job is out of scope for this plan (T-04-04-07).
    create table(:save_pending_uploads, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :device_id, references(:devices, type: :binary_id, on_delete: :delete_all), null: false
      add :blob_sha256, :string, null: false
      add :size_bytes, :integer, null: false
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:save_pending_uploads, [:user_id])
  end
end
