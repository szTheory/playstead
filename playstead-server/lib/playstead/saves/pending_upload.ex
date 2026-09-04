defmodule Playstead.Saves.PendingUpload do
  @moduledoc """
  Links a client-supplied upload `command_id` to the blob digest the
  streamed `PUT /api/v1/saves/uploads/:command_id` half already
  committed into the CAS (D-16). `Idempotency.fingerprint/1`
  canonicalizes a parsed body and cannot fingerprint a stream, which is
  exactly why the upload and the metadata commit are two endpoints:
  this row is how the metadata commit (`POST /api/v1/saves/revisions`)
  finds the digest the client never has to resend. `id` is the
  command_id itself. TTL'd via `expires_at`; a sweep job for expired
  rows is out of scope for this plan (T-04-04-07).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  schema "save_pending_uploads" do
    field :user_id, :id
    field :device_id, :binary_id
    field :blob_sha256, :string
    field :size_bytes, :integer
    field :expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(pending, attrs) do
    pending
    |> cast(attrs, [:id, :user_id, :device_id, :blob_sha256, :size_bytes, :expires_at])
    |> validate_required([:id, :user_id, :device_id, :blob_sha256, :size_bytes, :expires_at])
  end

  @type t :: %__MODULE__{}
end
