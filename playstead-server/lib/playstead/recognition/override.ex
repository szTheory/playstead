defmodule Playstead.Recognition.Override do
  @moduledoc """
  A user's correction over a machine-produced system/title guess
  (D-19, D-27). Additive only — nothing in the application ever
  updates or deletes a row here, and nothing here ever touches
  `Playstead.Recognition.Evidence`. An override always outranks
  extension and header evidence; the machine's reading and the user's
  correction both stay permanently visible so a later reference pack
  can be reconciled against either.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "recognition_overrides" do
    field :user_id, :id
    belongs_to :asset_set, Playstead.Catalogue.AssetSet
    field :system_id, :string
    field :title, :string
    field :audit_entry_id, :integer

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def create_changeset(override, attrs) do
    override
    |> cast(attrs, [:user_id, :asset_set_id, :system_id, :title, :audit_entry_id])
    |> validate_required([:user_id, :asset_set_id])
  end

  @type t :: %__MODULE__{}
end
