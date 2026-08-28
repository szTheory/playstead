defmodule Playstead.Repo.Migrations.CreateExports do
  use Ecto.Migration

  def change do
    # D-33/D-36/D-38/D-40: the durable export record. `target_name` is
    # the single sanitized path component under the configured export
    # root (never a free-form absolute path). `status` moves through
    # writing -> verifying -> verified | verification_failed.
    create table(:exports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :scope, :string, null: false
      add :scope_asset_set_id, references(:asset_sets, type: :binary_id, on_delete: :nilify_all)
      add :target_name, :string, null: false

      add :status, :string, null: false, default: "writing"
      add :set_count, :integer, null: false, default: 0
      add :file_count, :integer, null: false, default: 0
      add :total_bytes, :bigint, null: false, default: 0

      add :sidecar_schema_id, :string
      add :generator_version, :string

      add :mismatched_files, {:array, :string}, null: false, default: []

      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
      add :last_verified_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:exports, [:user_id])
    create index(:exports, [:status])

    create constraint(:exports, :status_must_be_known,
             check: "status IN ('writing', 'verifying', 'verified', 'verification_failed')"
           )

    create constraint(:exports, :scope_must_be_known, check: "scope IN ('set', 'library')")
  end
end
