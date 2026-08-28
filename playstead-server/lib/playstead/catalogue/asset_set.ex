defmodule Playstead.Catalogue.AssetSet do
  @moduledoc """
  A user-scoped logical asset (D-34, D-37) — one game, made up of one or
  more `Playstead.Catalogue.AssetMember` rows. `member_fingerprint` is
  the natural key computed by `Playstead.Catalogue.member_fingerprint/1`;
  the unique index on the user/fingerprint pair is what makes "no
  duplicate logical record" a database guarantee.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "asset_sets" do
    field :user_id, :id
    field :system_id, :string
    field :system_source, :string
    field :display_title, :string
    field :title_source, :string
    field :status, :string, default: "active"
    field :member_fingerprint, :string
    field :excluded_at, :utc_datetime
    field :provenance, :map, default: %{}

    has_many :asset_members, Playstead.Catalogue.AssetMember

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(asset_set, attrs) do
    asset_set
    |> cast(attrs, [
      :user_id,
      :system_id,
      :system_source,
      :display_title,
      :title_source,
      :status,
      :member_fingerprint,
      :excluded_at,
      :provenance
    ])
    |> validate_required([:user_id, :member_fingerprint])
    |> unique_constraint([:user_id, :member_fingerprint],
      name: :asset_sets_user_id_member_fingerprint_index
    )
  end

  @type t :: %__MODULE__{}
end
