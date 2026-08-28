defmodule Playstead.Recognition.ReferenceEntry do
  @moduledoc """
  One entry read from a reference pack (D-18, D-20): a name and the
  digests `Playstead.Recognition.LogiqxHandler` extracted for it.
  `size_bytes` is stored strictly as metadata — a declared size from an
  administrator-supplied file — and is never consulted to size an
  allocation or a collection anywhere in this application (T-02-61).

  Digests are matched against `blobs`' own legacy digest columns and
  against `Playstead.Blobs.BlobFingerprint`'s headerless-offset digests,
  because reference packs hash content without its console header.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "reference_entries" do
    belongs_to :dat_pack, Playstead.Recognition.DatPack
    field :name, :string
    field :crc32, :string
    field :md5, :string
    field :sha1, :string
    field :size_bytes, :integer

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def create_changeset(entry, attrs) do
    entry
    |> cast(attrs, [:dat_pack_id, :name, :crc32, :md5, :sha1, :size_bytes])
    |> validate_required([:dat_pack_id, :name])
  end

  @type t :: %__MODULE__{}
end
