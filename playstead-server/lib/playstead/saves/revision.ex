defmodule Playstead.Saves.Revision do
  @moduledoc """
  One immutable node in a save line's parent-pointer revision DAG
  (D-09, D-11). `id` is client-supplied (a UUIDv7, same natural-key
  discipline as `Playstead.Curation.Favorite`). `parent_revision_id`
  `nil` means root; a second root on a line that already has a head is
  a genuine divergence, not an error (D-11) -- this schema places no
  constraint forbidding it.

  `recorded_at` is server-assigned at insert time and is the only
  orderable time (D-15); `device_captured_at` is stored as evidence
  only and is never used for ordering.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  schema "save_revisions" do
    field :user_id, :id
    field :save_line_id, :binary_id
    field :parent_revision_id, :binary_id
    field :blob_sha256, :string
    field :size_bytes, :integer
    field :origin_device_id, :binary_id
    field :device_captured_at, :utc_datetime_usec
    field :recorded_at, :utc_datetime_usec
    field :capture_method, :string
    field :adapter_id, :string
    field :adapter_version, :string
    field :save_format, :string
    field :format_confidence, :string
    field :play_session_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(revision, attrs) do
    revision
    |> cast(attrs, [
      :id,
      :user_id,
      :save_line_id,
      :parent_revision_id,
      :blob_sha256,
      :size_bytes,
      :origin_device_id,
      :device_captured_at,
      :recorded_at,
      :capture_method,
      :adapter_id,
      :adapter_version,
      :save_format,
      :format_confidence,
      :play_session_id
    ])
    |> validate_required([
      :id,
      :user_id,
      :save_line_id,
      :blob_sha256,
      :size_bytes,
      :recorded_at
    ])
    |> validate_format(:blob_sha256, ~r/^[0-9a-f]{64}$/,
      message: "must be a 64-character lowercase hex sha256"
    )
    |> foreign_key_constraint(:save_line_id)
    |> foreign_key_constraint(:parent_revision_id)
  end

  @type t :: %__MODULE__{}
end
