defmodule Playstead.Curation.QueueItem do
  @moduledoc """
  One item in a user's play queue -- a backlog/watchlist, not a
  per-device playback buffer (D-07). `id` is client-supplied. The
  unique index on `(user_id, asset_set_id)` is what makes re-enqueuing
  an already-queued game converge instead of duplicating.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  schema "curation_queue_items" do
    field :user_id, :id
    field :asset_set_id, :binary_id
    field :position, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(item, attrs) do
    item
    |> cast(attrs, [:id, :user_id, :asset_set_id, :position])
    |> validate_required([:id, :user_id, :asset_set_id, :position])
    |> unique_constraint([:user_id, :asset_set_id],
      name: :curation_queue_items_user_id_asset_set_id_index
    )
  end

  @doc false
  def reposition_changeset(item, attrs) do
    item
    |> cast(attrs, [:position])
    |> validate_required([:position])
  end

  @type t :: %__MODULE__{}
end
