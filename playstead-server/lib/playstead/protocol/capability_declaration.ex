defmodule Playstead.Protocol.CapabilityDeclaration do
  @moduledoc """
  A device's most recent client-hello capability declaration (D-19).

  Unique on `device_id`: a repeat hello refreshes this row in place
  rather than accumulating history, and two concurrent hellos from the
  same device converge to exactly one row via the unique index plus an
  `on_conflict` upsert (`Playstead.Protocol.Negotiation.store_declaration/2`).
  Pairing's `claimed_capabilities` (plan 01-04) is the initial
  declaration; this table is the per-session refresh.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "capability_declarations" do
    field :device_id, :binary_id
    field :capabilities, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(declaration, attrs) do
    declaration
    |> cast(attrs, [:device_id, :capabilities])
    |> validate_required([:device_id])
    |> unique_constraint(:device_id)
  end

  @type t :: %__MODULE__{}
end
