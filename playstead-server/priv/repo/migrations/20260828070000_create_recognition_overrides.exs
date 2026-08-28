defmodule Playstead.Repo.Migrations.CreateRecognitionOverrides do
  use Ecto.Migration

  def change do
    # D-19, D-27: additive user corrections. Never updated or deleted —
    # a correction is a new row, never a rewrite of a machine-produced
    # `recognitions` evidence row.
    create table(:recognition_overrides, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :asset_set_id, references(:asset_sets, type: :binary_id, on_delete: :delete_all),
        null: false

      add :system_id, :string
      add :title, :string
      add :audit_entry_id, :bigint

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:recognition_overrides, [:asset_set_id])
    create index(:recognition_overrides, [:user_id])
  end
end
