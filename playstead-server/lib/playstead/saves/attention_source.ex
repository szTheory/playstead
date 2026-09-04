defmodule Playstead.Saves.AttentionSource do
  @moduledoc """
  The saves-owned attention source (D-66). Divergence, blocked
  capture, and per-user retention-backstop crossings raise items
  through this context's own table and its own reason vocabulary
  (`Playstead.Saves.AttentionItem.reasons/0`) -- `Playstead.Attention.Reason`
  is a frozen, nine-member, import-recognition-scoped vocabulary and
  is never widened by this module, never aliased, never imported.

  `raise_*` upserts by `(user_id, grouping_key, reason)` exactly like
  `Playstead.Attention.raise_item/1`'s `on_conflict: [inc: [count: 1]]`
  pattern -- raising the same item twice increments its count rather
  than inserting a duplicate row. `clear_*` deletes the row outright:
  there is no "resolved"/"excluded" status lifecycle here, only
  "currently raised" or "not currently raised" -- clearing a fork's
  divergence item (by resolving or acknowledging it) and never seeing
  it again unless a genuinely new divergent commit arrives is exactly
  what D-52's "never re-raised" promise requires, and it falls out of
  this shape for free: nothing re-raises an item on its own, only a
  caller explicitly deciding "this needs attention again" does.

  `list_items/1` and `count/1` mirror `Playstead.Attention.list_items/2`
  and `Playstead.Attention.count/1`'s shapes exactly, so
  `PlaysteadWeb.AttentionLive` can union this source's rows with
  `Playstead.Attention`'s at read time (`Map.merge/3`) -- the union
  happens in the view layer; neither context learns about the other's
  rows.
  """

  import Ecto.Query, warn: false

  alias Playstead.Repo
  alias Playstead.Saves.AttentionItem

  @doc """
  Raises (or upserts/increments) a divergence item for `save_line_id`
  -- one item per fork, regardless of how many heads it has.
  """
  @spec raise_divergence(pos_integer(), binary()) :: {:ok, AttentionItem.t()} | {:error, term()}
  def raise_divergence(user_id, save_line_id) do
    upsert(user_id, "divergence", save_line_id, save_line_id)
  end

  @doc "Clears the divergence item for `save_line_id`, if any is currently raised."
  @spec clear_divergence(pos_integer(), binary()) :: {:ok, non_neg_integer()}
  def clear_divergence(user_id, save_line_id) do
    clear(user_id, "divergence", save_line_id)
  end

  @doc "Raises (or upserts/increments) a blocked-capture item for `save_line_id` (D-31)."
  @spec raise_capture_blocked(pos_integer(), binary()) ::
          {:ok, AttentionItem.t()} | {:error, term()}
  def raise_capture_blocked(user_id, save_line_id) do
    upsert(user_id, "capture_blocked", save_line_id, save_line_id)
  end

  @doc "Clears the blocked-capture item for `save_line_id`, if any is currently raised."
  @spec clear_capture_blocked(pos_integer(), binary()) :: {:ok, non_neg_integer()}
  def clear_capture_blocked(user_id, save_line_id) do
    clear(user_id, "capture_blocked", save_line_id)
  end

  @doc """
  Raises (or upserts/increments) a retention-backstop item for
  `user_id` once `count` has reached `backstop` (D-28) -- pressure as
  attention, never a refusal. A no-op below the threshold. `kind` is
  `:revision_count` or `:storage_bytes`, each its own grouping key so
  crossing one never masks the other.
  """
  @spec maybe_raise_backstop(pos_integer(), atom(), non_neg_integer(), non_neg_integer()) :: :ok
  def maybe_raise_backstop(user_id, kind, count, backstop)
      when is_integer(count) and is_integer(backstop) and count >= backstop do
    upsert(user_id, "retention_backstop", "backstop:#{kind}", nil)
    :ok
  end

  def maybe_raise_backstop(_user_id, _kind, _count, _backstop), do: :ok

  @doc """
  `user_id`'s currently-raised saves attention items, grouped by
  reason -- the same `%{reason => [item]}` shape
  `Playstead.Attention.list_items/2` returns, so the two maps union
  with a plain `Map.merge/3` at the `AttentionLive` view layer.
  """
  @spec list_items(pos_integer()) :: %{String.t() => [AttentionItem.t()]}
  def list_items(user_id) do
    from(i in AttentionItem,
      where: i.user_id == ^user_id,
      order_by: [asc: i.inserted_at, asc: i.id]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.reason)
  end

  @doc "The count of `user_id`'s currently-raised saves attention items."
  @spec count(pos_integer()) :: non_neg_integer()
  def count(user_id) do
    from(i in AttentionItem, where: i.user_id == ^user_id) |> Repo.aggregate(:count)
  end

  defp upsert(user_id, reason, grouping_key, save_line_id) do
    attrs = %{
      user_id: user_id,
      reason: reason,
      grouping_key: grouping_key,
      save_line_id: save_line_id
    }

    changeset = AttentionItem.create_changeset(%AttentionItem{}, attrs)

    Repo.insert(changeset,
      on_conflict: [inc: [count: 1]],
      conflict_target: [:user_id, :grouping_key, :reason],
      returning: true
    )
  end

  defp clear(user_id, reason, grouping_key) do
    {count, _} =
      from(i in AttentionItem,
        where: i.user_id == ^user_id and i.reason == ^reason and i.grouping_key == ^grouping_key
      )
      |> Repo.delete_all()

    {:ok, count}
  end
end
