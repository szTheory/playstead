defmodule Playstead.Blobs.Release do
  @moduledoc """
  A per-user release decision over a shared, quarantined blob (D-28).
  The machine quarantine verdict lives on `Playstead.Blobs.Blob` itself
  (shared, since the bytes are shared); this table is the user-scoped
  fact that this particular user chose to release those bytes for
  their own use. One user's row here never changes another user's row.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "blob_releases" do
    field :user_id, :id
    belongs_to :blob, Playstead.Blobs.Blob
    field :resolution, :string
    field :released_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(release, attrs) do
    release
    |> cast(attrs, [:user_id, :blob_id, :resolution, :released_at])
    |> validate_required([:user_id, :blob_id, :resolution, :released_at])
    |> unique_constraint([:user_id, :blob_id])
  end

  @type t :: %__MODULE__{}
end
