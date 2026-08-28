defmodule Playstead.Import.SourceFile do
  @moduledoc """
  A user-scoped record of one file an import read from (D-08, D-13).
  `blob_id` is nullable while an import is in flight. `original_name`
  is stored byte-exact — never sanitized or truncated on write, since
  it is the reconcile key's raw material — and `origin`/`relative_path`/
  `size_bytes`/`mtime` are the four-part fingerprint D-08's reconcile
  will key off in a later plan.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "source_files" do
    field :user_id, :id
    belongs_to :blob, Playstead.Blobs.Blob
    field :original_name, :string
    field :origin, :string
    field :relative_path, :string
    field :size_bytes, :integer
    field :mtime, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(source_file, attrs) do
    source_file
    |> cast(attrs, [
      :user_id,
      :blob_id,
      :original_name,
      :origin,
      :relative_path,
      :size_bytes,
      :mtime
    ])
    |> validate_required([:user_id, :original_name, :origin, :size_bytes])
  end

  @type t :: %__MODULE__{}
end
