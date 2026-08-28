defmodule Playstead.Blobs.BlobFingerprint do
  @moduledoc """
  A headerless-offset fingerprint for a blob (D-20): the CRC32/MD5/
  SHA-1 triple computed starting at a given byte offset, alongside the
  `kind` of fingerprint it represents (e.g. a specific console header
  format). Recognition (plan 02-03) is the first consumer; this schema
  exists now so the storage shape for it is settled.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "blob_fingerprints" do
    belongs_to :blob, Playstead.Blobs.Blob
    field :kind, :string
    field :offset, :integer
    field :crc32, :string
    field :md5, :string
    field :sha1, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(fingerprint, attrs) do
    fingerprint
    |> cast(attrs, [:blob_id, :kind, :offset, :crc32, :md5, :sha1])
    |> validate_required([:blob_id, :kind, :offset])
  end

  @type t :: %__MODULE__{}
end
