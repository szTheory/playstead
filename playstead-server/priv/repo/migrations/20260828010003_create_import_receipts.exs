defmodule Playstead.Repo.Migrations.CreateImportReceipts do
  use Ecto.Migration

  def change do
    # D-25: outcome is constrained to the nine frozen codes at the
    # database level too, not just in the application changeset.
    create table(:import_receipts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :source_file_id, references(:source_files, type: :binary_id, on_delete: :delete_all),
        null: false

      add :blob_id, references(:blobs, type: :binary_id, on_delete: :nilify_all)
      add :asset_set_id, references(:asset_sets, type: :binary_id, on_delete: :nilify_all)
      add :outcome, :string, null: false
      add :reason, :string
      add :sha256, :string
      add :size_bytes, :bigint

      timestamps(type: :utc_datetime)
    end

    create index(:import_receipts, [:user_id])
    create index(:import_receipts, [:source_file_id])

    create constraint(:import_receipts, :outcome_must_be_known,
             check: """
             outcome IN (
               'new_asset', 'exact_duplicate', 'alias', 'variant',
               'incomplete_set', 'unrecognized', 'patched', 'quarantined',
               'failed_safely'
             )
             """
           )
  end
end
