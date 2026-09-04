defmodule Playstead.Saves.RevisionParent do
  @moduledoc """
  One parent edge of a revision that names more than one parent (D-48):
  a divergence-resolution revision. The ordinary single-parent case
  keeps using `Playstead.Saves.Revision.parent_revision_id` directly --
  this row exists only for the N-way case a single column cannot
  express. `role` is `"chosen"` for exactly one parent per resolution
  revision and `"acknowledged"` for every other one. The unique index
  on `(revision_id, parent_revision_id)` is what makes a replayed
  resolution commit (same idempotency key) insert no duplicate edge.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @foreign_key_type :binary_id

  @roles ~w(chosen acknowledged)

  schema "save_revision_parents" do
    field :revision_id, :binary_id
    field :parent_revision_id, :binary_id
    field :role, :string

    timestamps(type: :utc_datetime)
  end

  @doc "The valid `role` values."
  @spec roles() :: [String.t()]
  def roles, do: @roles

  @doc false
  def create_changeset(revision_parent, attrs) do
    revision_parent
    |> cast(attrs, [:revision_id, :parent_revision_id, :role])
    |> validate_required([:revision_id, :parent_revision_id, :role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:revision_id, :parent_revision_id],
      name: :save_revision_parents_revision_id_parent_revision_id_index
    )
    |> foreign_key_constraint(:revision_id)
    |> foreign_key_constraint(:parent_revision_id)
  end

  @type t :: %__MODULE__{}
end
