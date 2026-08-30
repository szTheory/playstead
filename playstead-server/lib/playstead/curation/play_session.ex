defmodule Playstead.Curation.PlaySession do
  @moduledoc """
  A coarse recorded play session (D-07): an id, a game, a start, and
  an end -- nothing else. Records no input, no duration breakdown, no
  achievement, and no device telemetry beyond what the device
  credential already identifies. Recent and Continue are the only two
  things this schema exists to derive; anything further is analytics
  this phase has deliberately deferred.

  `id` is client-supplied. `started_at`/`ended_at` are
  `utc_datetime_usec` so ordering under a burst of sessions posted
  from the same outbox flush stays deterministic.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  schema "curation_play_sessions" do
    field :user_id, :id
    field :asset_set_id, :binary_id
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def create_changeset(session, attrs) do
    session
    |> cast(attrs, [:id, :user_id, :asset_set_id, :started_at, :ended_at])
    |> validate_required([:id, :user_id, :asset_set_id, :started_at])
  end

  @type t :: %__MODULE__{}
end
