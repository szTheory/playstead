defmodule Playstead.Repo.Migrations.CreateRecognitions do
  use Ecto.Migration

  def change do
    # D-16, D-18, T-02-24: append-only evidence rows. Nothing in the
    # application ever updates or deletes a row here — corrections are
    # additive rows, never rewrites.
    create table(:recognitions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :blob_id, references(:blobs, type: :binary_id, on_delete: :nilify_all)
      add :asset_set_id, references(:asset_sets, type: :binary_id, on_delete: :nilify_all)
      add :provider_name, :string, null: false
      add :provider_version, :string, null: false
      add :status, :string, null: false
      add :confidence, :string
      add :reference_name, :string
      add :evidence, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:recognitions, [:blob_id])
    create index(:recognitions, [:asset_set_id])
  end
end
