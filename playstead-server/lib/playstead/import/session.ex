defmodule Playstead.Import.Session do
  @moduledoc """
  A durable, folder-level import session (D-01, D-05, D-06). The id is
  client-supplied so the same "stage this folder" request is idempotent
  by construction, matching the command-id idiom used elsewhere.

  `state` and `requested_control` are two separate persisted columns,
  following `Playstead.Pairing.PairingRequest`'s schema idiom exactly:
  `requested_control` is never cached in worker memory, never read from
  a socket, and never routed through the global Oban queue pause — the
  session worker re-reads this column from the database before every
  file, which is the entire mechanism the pause/resume/cancel design
  depends on.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @states ~w(staged running paused completed cancelled failed)
  @controls ~w(run pause cancel)

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :binary_id
  schema "import_sessions" do
    field :user_id, :id
    field :origin, :string
    field :state, :string, default: "staged"
    field :requested_control, :string, default: "run"

    field :file_count, :integer, default: 0
    field :total_bytes, :integer, default: 0
    field :files_completed, :integer, default: 0
    field :bytes_completed, :integer, default: 0
    field :counts_by_outcome, :map, default: %{}

    field :enumeration_completed_at, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc "The frozen set of persisted session states."
  def states, do: @states

  @doc "The frozen set of requested-control values."
  def controls, do: @controls

  @doc false
  def create_changeset(session, attrs) do
    session
    |> cast(attrs, [:id, :user_id, :origin, :file_count, :total_bytes])
    |> validate_required([:id, :user_id, :origin])
    |> put_change(:state, "staged")
    |> put_change(:requested_control, "run")
    |> put_change(:enumeration_completed_at, DateTime.utc_now())
    |> unique_constraint(:id, name: :import_sessions_pkey)
  end

  @doc false
  def state_changeset(session, state) when state in @states do
    change(session, state: state)
  end

  @doc false
  def control_changeset(session, control) when control in @controls do
    change(session, requested_control: control)
  end

  @doc false
  def progress_changeset(session, attrs) do
    cast(session, attrs, [:files_completed, :bytes_completed, :counts_by_outcome])
  end

  @type t :: %__MODULE__{}
end
