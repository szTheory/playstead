defmodule Playstead.Recognition.DatPack do
  @moduledoc """
  A reference pack an administrator has supplied, with its full
  provenance (D-18, T-02-63): where it came from, when it was
  retrieved, its upstream version, its own file hash, the licence
  claim the administrator asserted with a free-text note, and the
  transform version of the importer that read it.

  Playstead never ships, fetches, or redistributes reference data —
  every row here exists only because an administrator uploaded a file.
  Recording the licence claim is the point: the administrator asserted
  it, the product displays it, and the product itself never claims any
  rights over data it did not create.
  """

  use Ecto.Schema
  import Ecto.Changeset

  # A closed vocabulary (D-18: "licence claim (enum + note)"). `note` is
  # always available for the nuance a fixed enum cannot capture — the
  # common reference packs range from public domain (Redump) through
  # share-alike (libretro-database, CC BY-SA 4.0) to entirely unstated
  # (No-Intro), so "unstated" and "other" are first-class values, not
  # error cases.
  @license_claims ~w(public_domain share_alike all_rights_reserved unstated other)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "dat_packs" do
    field :user_id, :id
    field :source, :string
    field :retrieved_at, :utc_datetime
    field :upstream_version, :string
    field :file_sha256, :string
    field :license_claim, :string
    field :license_note, :string
    field :transform_version, :string
    field :entry_count, :integer, default: 0

    has_many :reference_entries, Playstead.Recognition.ReferenceEntry

    timestamps(type: :utc_datetime)
  end

  @doc "The frozen licence-claim vocabulary."
  def license_claims, do: @license_claims

  @doc false
  def create_changeset(dat_pack, attrs) do
    dat_pack
    |> cast(attrs, [
      :user_id,
      :source,
      :retrieved_at,
      :upstream_version,
      :file_sha256,
      :license_claim,
      :license_note,
      :transform_version,
      :entry_count
    ])
    |> validate_required([:user_id, :file_sha256, :license_claim, :transform_version])
    |> validate_inclusion(:license_claim, @license_claims)
    |> unique_constraint([:user_id, :file_sha256])
  end

  @type t :: %__MODULE__{}
end
