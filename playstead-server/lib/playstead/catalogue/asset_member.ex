defmodule Playstead.Catalogue.AssetMember do
  @moduledoc """
  One physical member of an `Playstead.Catalogue.AssetSet` (e.g. a disc,
  a save, a manual scan). `blob_id` is nullable so a required-but-
  missing member is representable (`incomplete_set`, D-25).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "asset_members" do
    belongs_to :asset_set, Playstead.Catalogue.AssetSet
    field :ordinal, :integer
    field :role, :string
    field :required, :boolean, default: true
    belongs_to :blob, Playstead.Blobs.Blob
    field :declared_name, :string
    field :export_path, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(member, attrs) do
    member
    |> cast(attrs, [
      :asset_set_id,
      :ordinal,
      :role,
      :required,
      :blob_id,
      :declared_name,
      :export_path
    ])
    |> validate_required([:asset_set_id, :ordinal, :role])
  end

  @type t :: %__MODULE__{}
end
