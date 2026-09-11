defmodule Playstead.Availability.DeviceReport do
  @moduledoc """
  A single reported availability fact row for one device/asset-set pair
  (plan 03-13). Facts only, never a computed ladder rank (D-21) — the
  rank is derived fresh on every render by `StatusSlot.describe/2` from
  these booleans/percent, never stored here.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "device_asset_availability" do
    field :user_id, :id
    belongs_to :device, Playstead.Pairing.Device
    belongs_to :asset_set, Playstead.Catalogue.AssetSet

    field :downloading, :boolean, default: false
    field :verified, :boolean, default: false
    field :pinned, :boolean, default: false
    field :missing_dependency, :boolean, default: false
    field :download_percent, :integer, default: 0
    field :reported_at, :utc_datetime_usec

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(report, attrs) do
    report
    |> cast(attrs, [
      :device_id,
      :user_id,
      :asset_set_id,
      :downloading,
      :verified,
      :pinned,
      :missing_dependency,
      :download_percent,
      :reported_at
    ])
    |> validate_required([:device_id, :user_id, :asset_set_id, :reported_at])
    |> validate_number(:download_percent,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    )
    |> check_constraint(:download_percent,
      name: :download_percent_range,
      message: "must be between 0 and 100"
    )
    |> foreign_key_constraint(:device_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:asset_set_id)
  end

  @type t :: %__MODULE__{}
end
