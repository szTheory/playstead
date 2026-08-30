defmodule Playstead.Repo.Migrations.CreateCurationPlaySessionsAndDismissals do
  use Ecto.Migration

  def change do
    # D-07: a play session carries an id, a game, a start, and an end
    # -- nothing else. utc_datetime_usec so ordering under a burst of
    # sessions posted together from the outbox is deterministic.
    create table(:curation_play_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :asset_set_id, references(:asset_sets, type: :binary_id, on_delete: :delete_all),
        null: false

      add :started_at, :utc_datetime_usec, null: false
      add :ended_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:curation_play_sessions, [:user_id, :asset_set_id, :started_at])

    create table(:curation_continue_dismissals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :asset_set_id, references(:asset_sets, type: :binary_id, on_delete: :delete_all),
        null: false

      add :dismissed_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:curation_continue_dismissals, [:user_id, :asset_set_id])
  end
end
