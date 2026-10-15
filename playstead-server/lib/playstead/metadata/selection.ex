defmodule Playstead.Metadata.Selection do
  @moduledoc "An owner's selected private presentation metadata for an existing game asset set."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @max_description_bytes 65_536

  schema "metadata_selections" do
    field :user_id, :id
    belongs_to :asset_set, Playstead.Catalogue.AssetSet
    field :description, :string
    field :revision, :integer
    field :field_revisions, :map, default: %{}
    field :selections, :map, default: %{}
    field :field_sources, :map, default: %{}
    field :deleted_fields, :map, default: %{}
    field :evidence, :map, default: %{}
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(selection, attrs) do
    selection
    |> cast(
      attrs,
      [
        :user_id,
        :asset_set_id,
        :description,
        :revision,
        :field_revisions,
        :selections,
        :field_sources,
        :deleted_fields,
        :evidence,
        :deleted_at
      ],
      empty_values: []
    )
    |> validate_required([:user_id, :asset_set_id, :revision])
    |> validate_number(:revision, greater_than: 0)
    |> validate_change(:description, fn :description, value ->
      if byte_size(value) <= @max_description_bytes do
        []
      else
        [description: "must be at most #{@max_description_bytes} UTF-8 bytes"]
      end
    end)
    |> foreign_key_constraint(:asset_set_id)
    |> unique_constraint([:user_id, :asset_set_id],
      name: :metadata_selections_user_id_asset_set_id_index
    )
  end
end
