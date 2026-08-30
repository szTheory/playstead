defmodule Playstead.Curation.Favorite do
  @moduledoc """
  A user's favorite of one `Playstead.Catalogue.AssetSet` (D-07/D-08).
  `id` is client-supplied (D-09's UUIDv7 natural key); the unique index
  on `(user_id, asset_set_id)` is what makes a repeated favorite intent
  converge on the same row instead of duplicating.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  schema "curation_favorites" do
    field :user_id, :id
    field :asset_set_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(favorite, attrs) do
    favorite
    |> cast(attrs, [:id, :user_id, :asset_set_id])
    |> validate_required([:id, :user_id, :asset_set_id])
    |> unique_constraint([:user_id, :asset_set_id],
      name: :curation_favorites_user_id_asset_set_id_index
    )
  end

  @type t :: %__MODULE__{}
end
