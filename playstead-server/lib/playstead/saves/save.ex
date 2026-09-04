defmodule Playstead.Saves.Save do
  @moduledoc """
  A save line: the lineage root identified by `(user_id, content_key,
  save_kind, slot)` (D-10). `content_key` is the ROM sha256, not
  `asset_set_id`, so a re-import cannot orphan every save on a game.
  `id` is server-generated (not client-supplied, unlike `Revision`'s
  id) because the line itself is an internal grouping construct that
  every committing device converges onto via the unique index below,
  never a client-chosen identity.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  schema "save_lines" do
    field :user_id, :id
    field :content_key, :string
    field :save_kind, :string, default: "battery"
    field :slot, :string, default: "0"

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(save, attrs) do
    save
    |> cast(attrs, [:id, :user_id, :content_key, :save_kind, :slot])
    |> validate_required([:id, :user_id, :content_key, :save_kind, :slot])
    |> validate_format(:content_key, ~r/^[0-9a-f]{64}$/,
      message: "must be a 64-character lowercase hex sha256"
    )
    |> unique_constraint([:user_id, :content_key, :save_kind, :slot],
      name: :save_lines_user_id_content_key_save_kind_slot_index
    )
  end

  @type t :: %__MODULE__{}
end
