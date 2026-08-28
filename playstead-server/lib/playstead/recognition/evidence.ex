defmodule Playstead.Recognition.Evidence do
  @moduledoc """
  One append-only recognition evidence row (D-16, D-18, T-02-24).
  Nothing in the application updates or deletes a row here — a second
  recognition of the same blob simply inserts another row; the
  asset's *current* state is derived from the newest evidence while a
  receipt's outcome (recorded elsewhere) stays terminal.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "recognitions" do
    belongs_to :blob, Playstead.Blobs.Blob
    belongs_to :asset_set, Playstead.Catalogue.AssetSet
    field :provider_name, :string
    field :provider_version, :string
    field :status, :string
    field :confidence, :string
    field :reference_name, :string
    field :evidence, :map, default: %{}

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def create_changeset(evidence, attrs) do
    evidence
    |> cast(attrs, [
      :blob_id,
      :asset_set_id,
      :provider_name,
      :provider_version,
      :status,
      :confidence,
      :reference_name,
      :evidence
    ])
    |> validate_required([:provider_name, :provider_version, :status])
  end

  @type t :: %__MODULE__{}
end
