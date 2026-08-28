defmodule Playstead.Attention.Item do
  @moduledoc """
  A user-scoped attention item (D-26). References whichever of a
  source file, an asset set, or a blob caused it — nullable, since not
  every reason has all three. `grouping_key` is what collapses many
  archives kept unopened within one import into exactly one item
  (D-21): for a session-scoped import it is the session id, otherwise
  a value unique to that one submission.

  Nothing here ever ages out, times out, or is swept away (D-26) —
  there is deliberately no time-to-live column and no scheduled
  cleanup of this table anywhere in the application.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Playstead.Attention.Reason

  @statuses ~w(open resolved excluded)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "attention_items" do
    field :user_id, :id
    field :reason, :string
    field :grouping_key, :string
    field :import_session_id, :string
    belongs_to :source_file, Playstead.Import.SourceFile
    belongs_to :asset_set, Playstead.Catalogue.AssetSet
    belongs_to :blob, Playstead.Blobs.Blob
    field :status, :string, default: "open"
    field :resolved_at, :utc_datetime
    field :count, :integer, default: 1
    field :evidence, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc "The frozen set of persisted resolution statuses."
  def statuses, do: @statuses

  @doc false
  def create_changeset(item, attrs) do
    item
    |> cast(attrs, [
      :user_id,
      :reason,
      :grouping_key,
      :import_session_id,
      :source_file_id,
      :asset_set_id,
      :blob_id,
      :evidence
    ])
    |> validate_required([:user_id, :reason, :grouping_key])
    |> validate_change(:reason, fn :reason, value ->
      if Reason.valid?(value), do: [], else: [reason: "is not a registered attention reason"]
    end)
    |> put_change(:status, "open")
  end

  @doc false
  def resolve_changeset(item) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    change(item, status: "resolved", resolved_at: now)
  end

  @doc false
  def reopen_changeset(item) do
    change(item, status: "open", resolved_at: nil)
  end

  @doc false
  def bump_count_changeset(item) do
    change(item, count: item.count + 1)
  end

  @type t :: %__MODULE__{}
end
