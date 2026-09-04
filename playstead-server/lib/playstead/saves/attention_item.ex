defmodule Playstead.Saves.AttentionItem do
  @moduledoc """
  A user-scoped saves attention item (D-66): its own frozen reason
  vocabulary (`divergence`, `capture_blocked`, `retention_backstop`),
  deliberately disjoint from `Playstead.Attention.Reason`. `grouping_key`
  is what collapses repeated raises for the same thing (a fork, a
  blocked line, a crossed backstop) into one upserted row rather than
  a duplicate -- the unique index on `(user_id, grouping_key, reason)`
  is the collision authority `Playstead.Saves.AttentionSource` relies
  on, copying `Playstead.Attention.Item`'s upsert shape structurally
  without sharing its table or vocabulary.
  """

  use Ecto.Schema
  import Ecto.Changeset

  # D-66: the saves-owned reason vocabulary. Never merged into or
  # aliased from `Playstead.Attention.Reason`.
  @reasons ~w(divergence capture_blocked retention_backstop)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "save_attention_items" do
    field :user_id, :id
    field :reason, :string
    field :grouping_key, :string
    field :save_line_id, :binary_id
    field :count, :integer, default: 1
    field :evidence, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc "The frozen set of saves-owned attention reasons."
  @spec reasons() :: [String.t()]
  def reasons, do: @reasons

  @doc false
  def create_changeset(item, attrs) do
    item
    |> cast(attrs, [:user_id, :reason, :grouping_key, :save_line_id, :evidence])
    |> validate_required([:user_id, :reason, :grouping_key])
    |> validate_inclusion(:reason, @reasons)
  end

  @doc false
  def bump_count_changeset(item) do
    change(item, count: item.count + 1)
  end

  @type t :: %__MODULE__{}
end
