defmodule Playstead.Sync.ChangeJournal do
  @moduledoc """
  The append-only, commit-order-fenced change journal (PROT-05, D-21).

  `append/4` and `tombstone/3` must be called inside the same
  transaction as the mutation they record — this module never opens its
  own transaction for the write, so the caller's ambient transaction is
  what makes the journal entry atomic with the effect it describes (the
  same discipline `Playstead.Idempotency.execute/4` follows, for the
  same reason: an entry written after commit can be lost in the gap).

  ## Commit-order fencing

  `seq` is a database-assigned `bigserial`. The subtle correctness
  property D-21 requires is that a reader must never observe `seq =
  N+1` while `seq = N` is still uncommitted — a naive
  `WHERE seq > cursor ORDER BY seq` read would otherwise let a
  slower-committing lower-`seq` transaction be silently skipped forever
  once a reader has stepped past the higher `seq` that committed first
  (the cursor-gap lost update D-21 rules out).

  This module fences on the *write* side instead of the read side:
  every write acquires `pg_advisory_xact_lock/1` on a fixed key before
  assigning its `seq`, and Postgres only releases a transaction-scoped
  advisory lock at COMMIT or ROLLBACK. A second writer therefore cannot
  acquire a new `seq` until the first writer's transaction has fully
  concluded — seq-assignment order and commit order can never diverge.
  That single invariant is what makes the plain, un-fenced
  `WHERE seq > cursor ORDER BY seq` in `read_after/3` safe with no
  read-side machinery at all.
  """

  import Ecto.Query, warn: false

  alias Playstead.Repo
  alias Playstead.Sync.{Entry, EntityKind}

  # Fixed advisory-lock key for the journal's single write-serialization
  # point. A personal single-owner server (T-01-49) makes global write
  # serialization an acceptable simplicity tradeoff.
  @advisory_lock_key 0x504C4159_53544544

  @doc """
  Appends an upsert entry for `entity_kind`/`entity_id`, scoped to
  `user_id`. `entity_kind` must be one of `Playstead.Sync.EntityKind.all/0`.
  """
  @spec append(pos_integer(), atom() | String.t(), String.t() | binary(), map()) ::
          {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def append(user_id, entity_kind, entity_id, payload \\ %{}) do
    write(user_id, entity_kind, entity_id, "upsert", payload)
  end

  @doc """
  Records a deletion as a tombstone entry — always an empty payload
  (T-01-47: a deletion must reveal nothing about the deleted content).
  A resuming client observes this entry exactly like any other and
  removes the entity from its local state.
  """
  @spec tombstone(pos_integer(), atom() | String.t(), String.t() | binary()) ::
          {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def tombstone(user_id, entity_kind, entity_id) do
    write(user_id, entity_kind, entity_id, "tombstone", %{})
  end

  defp write(user_id, entity_kind, entity_id, operation, payload) do
    acquire_write_lock()

    %Entry{}
    |> Entry.create_changeset(%{
      user_id: user_id,
      entity_kind: to_string(entity_kind),
      entity_id: to_string(entity_id),
      operation: operation,
      payload: payload
    })
    |> maybe_validate_kind(entity_kind)
    |> Repo.insert()
  end

  defp maybe_validate_kind(changeset, entity_kind) do
    if EntityKind.valid?(entity_kind) do
      changeset
    else
      Ecto.Changeset.add_error(changeset, :entity_kind, "is not a registered entity kind")
    end
  end

  # Blocks until any earlier writer in-flight on this key has committed
  # or rolled back. Re-entrant within the same session/transaction —
  # calling this more than once in one transaction (e.g. a mutation that
  # appends two entries) never self-deadlocks.
  defp acquire_write_lock do
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [@advisory_lock_key])
    :ok
  end

  @doc """
  Returns entries for `user_id` with `seq > after_seq`, in sequence
  order. An entry written for one owner is never returned to another
  owner's read, regardless of what `after_seq` decodes to (T-01-45) —
  this function is the single per-owner partitioning boundary for the
  journal.
  """
  @spec read_after(pos_integer(), non_neg_integer(), pos_integer()) :: [Entry.t()]
  def read_after(user_id, after_seq, limit) do
    from(e in Entry,
      where: e.user_id == ^user_id,
      where: e.seq > ^after_seq,
      order_by: [asc: e.seq],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc "The highest sequence value ever assigned for `user_id`'s journal, or `0` if none."
  @spec max_seq(pos_integer()) :: non_neg_integer()
  def max_seq(user_id) do
    from(e in Entry, where: e.user_id == ^user_id, select: max(e.seq))
    |> Repo.one()
    |> case do
      nil -> 0
      seq -> seq
    end
  end

  @doc "The `inserted_at` of the entry at `seq`, or `nil` if it doesn't exist (e.g. `seq == 0`)."
  @spec inserted_at_for(non_neg_integer()) :: DateTime.t() | nil
  def inserted_at_for(0), do: nil

  def inserted_at_for(seq) do
    from(e in Entry, where: e.seq == ^seq, select: e.inserted_at) |> Repo.one()
  end
end
