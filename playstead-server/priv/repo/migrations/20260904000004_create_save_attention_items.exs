defmodule Playstead.Repo.Migrations.CreateSaveAttentionItems do
  use Ecto.Migration

  def change do
    # D-66: a saves-owned attention table with its own reason
    # vocabulary (divergence, capture_blocked, retention_backstop) --
    # `Playstead.Attention.Reason` (import-recognition-scoped) is
    # never touched. Unioned into the inbox view at read time by
    # `PlaysteadWeb.AttentionLive`; neither context learns about the
    # other's rows or table.
    create table(:save_attention_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :reason, :string, null: false
      add :grouping_key, :string, null: false
      add :save_line_id, :binary_id
      add :count, :integer, null: false, default: 1
      add :evidence, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:save_attention_items, [:user_id])

    # D-66: the upsert-by-grouping-key conflict target -- raising the
    # same item twice increments `count` rather than inserting a
    # duplicate row, mirroring attention_items' equivalent index.
    create unique_index(:save_attention_items, [:user_id, :grouping_key, :reason],
             name: :save_attention_items_user_grouping_reason_index
           )
  end
end
