defmodule Playstead.Sync.Entry do
  @moduledoc """
  A single append-only change-journal row (PROT-05, D-21). `seq` is a
  database-assigned `bigserial`, read back after insert
  (`read_after_writes: true`) — application code never sets it
  directly. `operation` is `"upsert"` or `"tombstone"`; a tombstone
  always carries an empty `payload` (T-01-47).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Playstead.Sync.EntityKind

  @operations ~w(upsert tombstone)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "change_journal_entries" do
    field :seq, :integer, read_after_writes: true
    field :user_id, :id
    field :entity_kind, :string
    field :entity_id, :string
    field :operation, :string
    field :payload, :map, default: %{}

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "The valid `operation` values."
  def operations, do: @operations

  @doc false
  def create_changeset(entry, attrs) do
    entry
    |> cast(attrs, [:user_id, :entity_kind, :entity_id, :operation, :payload])
    |> validate_required([:user_id, :entity_kind, :entity_id, :operation])
    |> validate_inclusion(:entity_kind, Enum.map(EntityKind.all(), &to_string/1))
    |> validate_inclusion(:operation, @operations)
  end

  @type t :: %__MODULE__{}
end
