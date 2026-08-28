defmodule Playstead.Import.Receipt do
  @moduledoc """
  The immutable per-source-file receipt (D-24, D-25). Written once
  inside the same transaction as the mutation it records and never
  updated afterward — the durable proof of what happened to one
  uploaded file, readable long after the catalogue around it changes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Playstead.Import.Outcome

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "import_receipts" do
    field :user_id, :id
    belongs_to :source_file, Playstead.Import.SourceFile
    belongs_to :blob, Playstead.Blobs.Blob
    belongs_to :asset_set, Playstead.Catalogue.AssetSet
    field :outcome, :string
    field :reason, :string
    field :sha256, :string
    field :size_bytes, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(receipt, attrs) do
    receipt
    |> cast(attrs, [
      :user_id,
      :source_file_id,
      :blob_id,
      :asset_set_id,
      :outcome,
      :reason,
      :sha256,
      :size_bytes
    ])
    |> validate_required([:user_id, :source_file_id, :outcome])
    |> validate_change(:outcome, fn :outcome, value ->
      if Outcome.valid?(value), do: [], else: [outcome: "is not a recognized outcome code"]
    end)
  end

  @type t :: %__MODULE__{}
end
