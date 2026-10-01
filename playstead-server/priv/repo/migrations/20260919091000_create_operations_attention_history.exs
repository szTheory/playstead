defmodule Playstead.Repo.Migrations.CreateOperationsAttentionHistory do
  use Ecto.Migration

  def change do
    create table(:operations_attention_history) do
      add :component, :string, null: false
      add :state, :string, null: false
      add :code, :string, null: false
      add :evidence_at, :utc_datetime_usec, null: false
      add :remedy, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:operations_attention_history, [:component, :state, :code])
  end
end
