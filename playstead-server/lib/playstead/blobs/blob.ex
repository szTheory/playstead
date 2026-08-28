defmodule Playstead.Blobs.Blob do
  @moduledoc """
  A physical, content-addressed blob (D-11, D-13). Deliberately carries
  no user column — physical bytes are global across every user's
  library, and the unique index on `sha256` is what makes one copy on
  disk correct. Every logical, user-scoped record (`Playstead.Import.SourceFile`,
  `Playstead.Catalogue.AssetMember`) references a blob, never the
  reverse.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "blobs" do
    field :sha256, :string
    field :size_bytes, :integer
    field :crc32, :string
    field :md5, :string
    field :sha1, :string
    field :scan_state, :string, default: "clean"
    field :scan_reason, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(blob, attrs) do
    blob
    |> cast(attrs, [:sha256, :size_bytes, :crc32, :md5, :sha1, :scan_state, :scan_reason])
    |> validate_required([:sha256, :size_bytes])
    |> unique_constraint(:sha256)
  end

  @doc "D-28: sets the shared quarantine state and reason on the bytes. Never moves them."
  @spec quarantine_changeset(t(), String.t()) :: Ecto.Changeset.t()
  def quarantine_changeset(blob, reason) do
    change(blob, scan_state: "quarantined", scan_reason: reason)
  end

  @doc "Whether this blob is currently in the quarantine processing state."
  @spec quarantined?(t()) :: boolean()
  def quarantined?(%__MODULE__{scan_state: "quarantined"}), do: true
  def quarantined?(%__MODULE__{}), do: false

  @type t :: %__MODULE__{}
end
