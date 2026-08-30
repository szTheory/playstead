defmodule Playstead.Curation.Collection do
  @moduledoc """
  A user's manual, flat, ordered collection of games (D-10). `id` is
  client-supplied (D-09's UUIDv7 natural key). `position` is a
  `Playstead.Curation.Position` fractional-index string among the
  user's collections.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  schema "curation_collections" do
    field :user_id, :id
    field :name, :string
    field :position, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(collection, attrs) do
    collection
    |> cast(attrs, [:id, :user_id, :name, :position])
    |> validate_required([:id, :user_id, :name, :position])
  end

  @doc false
  def rename_changeset(collection, attrs) do
    collection
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end

  @doc false
  def reposition_changeset(collection, attrs) do
    collection
    |> cast(attrs, [:position])
    |> validate_required([:position])
  end

  @type t :: %__MODULE__{}
end
