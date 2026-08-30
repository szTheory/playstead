defmodule Playstead.Curation.CollectionMember do
  @moduledoc """
  One asset set's membership in one `Playstead.Curation.Collection`
  (D-10). `id` is client-supplied. The unique index on
  `(collection_id, asset_set_id)` is what makes re-adding an already
  present member converge instead of duplicating.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  schema "curation_collection_members" do
    field :user_id, :id
    field :collection_id, :binary_id
    field :asset_set_id, :binary_id
    field :position, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(member, attrs) do
    member
    |> cast(attrs, [:id, :user_id, :collection_id, :asset_set_id, :position])
    |> validate_required([:id, :user_id, :collection_id, :asset_set_id, :position])
    |> unique_constraint([:collection_id, :asset_set_id],
      name: :curation_collection_members_collection_id_asset_set_id_index
    )
  end

  @doc false
  def reposition_changeset(member, attrs) do
    member
    |> cast(attrs, [:position])
    |> validate_required([:position])
  end

  @type t :: %__MODULE__{}
end
