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
    field :import_session_id, :string
    field :staging_state, :string
    field :attempt_count, :integer, default: 0
    field :last_failure_reason, :string

    timestamps(type: :utc_datetime)
  end

  @staging_states ~w(pending completed skipped failed)

  @doc "The frozen set of per-row staging states (D-08)."
  def staging_states, do: @staging_states

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

  # The staging write path (task 1, plan 02-05): a row created directly
  # from a folder scan, with no blob yet -- `staging_state` starts
  # `"pending"`, the durable cursor `Playstead.Import.SessionWorker`
  # advances one row at a time.
  @doc false
  def stage_changeset(source_file, attrs) do
    source_file
    |> cast(attrs, [
      :user_id,
      :import_session_id,
      :original_name,
      :origin,
      :relative_path,
      :size_bytes,
      :mtime
    ])
    |> validate_required([:user_id, :original_name, :origin, :relative_path, :size_bytes])
    |> put_change(:staging_state, "pending")
  end

  @doc false
  def staging_state_changeset(source_file, state, reason \\ nil) when state in @staging_states do
    source_file
    |> change(staging_state: state, last_failure_reason: reason)
  end

  @doc false
  def blob_changeset(source_file, blob_id) do
    change(source_file, blob_id: blob_id)
  end

  @doc false
  def increment_attempt_changeset(source_file) do
    change(source_file, attempt_count: source_file.attempt_count + 1)
  end

  @type t :: %__MODULE__{}
end
