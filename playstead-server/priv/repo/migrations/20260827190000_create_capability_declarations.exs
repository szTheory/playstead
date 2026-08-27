defmodule Playstead.Repo.Migrations.CreateCapabilityDeclarations do
  use Ecto.Migration

  def change do
    # D-19: one row per device, refreshed on every hello. The unique
    # index on device_id is the concurrency primitive that makes two
    # concurrent identical hellos converge to exactly one row via
    # Negotiation.store_declaration/2's on_conflict upsert.
    create table(:capability_declarations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :device_id, references(:devices, type: :binary_id, on_delete: :delete_all), null: false
      add :capabilities, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:capability_declarations, [:device_id])
  end
end
