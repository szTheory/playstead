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

  @type t :: %__MODULE__{}
end
