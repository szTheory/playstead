defmodule Playstead.Metadata.Conflict do
  @moduledoc "Durable alternatives for a concurrent owner edit to one presentation field."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "metadata_conflicts" do
    field :user_id, :id
    field :asset_set_id, :binary_id
    field :field, :string
    field :base_revision, :integer
    field :current_revision, :integer
    field :current_alternative, :map
    field :incoming_alternative, :map
    field :resolved_at, :utc_datetime
    field :resolved_by_device_id, :binary_id
    timestamps(type: :utc_datetime)
  end

  def changeset(conflict, attrs) do
    conflict
    |> cast(attrs, [
      :user_id,
      :asset_set_id,
      :field,
      :base_revision,
      :current_revision,
      :current_alternative,
      :incoming_alternative,
      :resolved_at,
      :resolved_by_device_id
    ])
    |> validate_required([
      :user_id,
      :asset_set_id,
      :field,
      :base_revision,
      :current_revision,
      :current_alternative,
      :incoming_alternative
    ])
    |> validate_number(:base_revision, greater_than_or_equal_to: 0)
    |> validate_number(:current_revision, greater_than: 0)
    |> foreign_key_constraint(:asset_set_id)
  end
end
