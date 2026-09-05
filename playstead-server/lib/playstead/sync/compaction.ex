defmodule Playstead.Sync.Compaction do
  @moduledoc """
  Horizon-bounded compaction for the change journal (PROT-05, D-21).

  `horizon/0` is expressed in days, on the same scale as
  `Playstead.Idempotency.retention_days/0`, and is guaranteed to never
  read below its own floor even if a future change shortens receipt
  retention (D-21 requires the compaction horizon to be at least as
  long as receipt retention, so outbox replay and cursor resync stay
  mutually consistent) — `run/0` removes entries older than that
  horizon, and whatever survives naturally defines the exact 410
  boundary: a cursor at or after the oldest surviving sequence is
  serviceable, anything before it is definitively expired.
  """

  import Ecto.Query, warn: false

  alias Playstead.Repo
  alias Playstead.Idempotency
  alias Playstead.Sync.Entry

  # D-21's own floor, independent of `Playstead.Idempotency`'s current
  # retention value — if a future change shortens receipt retention,
  # the horizon must not silently follow it below this floor.
  @floor_days 90

  # WS-01 (04-REVIEW.md): `Playstead.Saves.acknowledge_divergence/3`
  # ("Keep both", D-52) writes a `fork_acknowledged` marker into the
  # journal under `entity_kind: "save"` — the same kind ordinary save
  # revisions use, distinguished only by this payload `type`.
  # `Saves.fork_acknowledged?/3` derives D-52's "never re-raised for
  # that fork" guarantee from exactly these rows, with no time bound of
  # its own. Before this fix, `run/0` deleted every entry past
  # `horizon/0` regardless of kind, so a fork acknowledged longer ago
  # than the horizon silently lost its evidence and got re-raised at
  # the user — the exact event-horizon mistake D-17 solved for revision
  # lineage by moving it out of the journal entirely. Exempting these
  # markers from deletion is the smaller fix: it keeps the journal as
  # their durable home rather than adding a schema migration for a
  # dedicated acknowledgment table (that shape is the better long-term
  # answer per D-17's own precedent — see the SUMMARY for this plan).
  @fork_acknowledged_type "fork_acknowledged"

  @doc "The retention horizon (days), always >= `Playstead.Idempotency.retention_days/0` and this module's own floor."
  @spec horizon() :: pos_integer()
  def horizon, do: max(@floor_days, Idempotency.retention_days())

  # The condition identifying a `fork_acknowledged` marker -- shared
  # between `run/0`'s delete exemption and `oldest_surviving_seq/0`'s
  # boundary computation, which must agree on what "survives normally"
  # means or the 410 contract below breaks.
  defp fork_acknowledged_dynamic do
    dynamic(
      [e],
      e.entity_kind == "save" and fragment("?->>'type' = ?", e.payload, ^@fork_acknowledged_type)
    )
  end

  # The negation, built by wrapping the positive condition -- pinning a
  # `dynamic/2` result inside another `dynamic/2` call is how Ecto
  # composes them; a bare `not (^exempt)` inline in a `where:` is not a
  # valid interpolation site.
  defp not_fork_acknowledged_dynamic do
    exempt = fork_acknowledged_dynamic()
    dynamic([e], not (^exempt))
  end

  @doc """
  Removes journal entries older than `horizon/0`, except
  `fork_acknowledged` markers (WS-01) — those survive indefinitely so
  `Saves.fork_acknowledged?/3` never loses its evidence. Invoked by a
  scheduled Oban job. Correctness of `/changes`'s 410 decision never
  depends on this having run recently — it only depends on it never
  running *more* aggressively than `horizon/0` allows for entries that
  aren't exempt.
  """
  @spec run() :: {:ok, non_neg_integer()}
  def run do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-horizon() * 24 * 60 * 60, :second)
      |> DateTime.truncate(:second)

    {count, _} =
      from(e in Entry, where: e.inserted_at < ^cutoff, where: ^not_fork_acknowledged_dynamic())
      |> Repo.delete_all()

    {:ok, count}
  end

  @doc """
  The lowest surviving `seq` across the whole journal, or `nil` if the
  journal is empty (nothing has ever been compacted away — every cursor
  is serviceable).

  WR-04 (01-REVIEW.md): this is deliberately a global minimum across all
  owners, not scoped per-user, even though `seq` is what `Sync.expired?/1`
  compares a given user's cursor against. That's only correct because (a)
  `seq` is a single monotonic `bigserial` shared by every owner's journal
  entries, and (b) `compact/0` above deletes rows purely by age
  (`inserted_at < cutoff`), never by owner. A future change that
  partitions compaction per-owner (e.g. to let an under-utilized user's
  history survive longer) would silently break `Sync.expired?/1`'s
  boundary check unless this function is reconsidered at the same time —
  don't "fix" this into a per-user `WHERE user_id = ...` query without
  also revisiting the cross-owner `seq` ordering guarantee it relies on.

  A `fork_acknowledged` marker exempted from `run/0`'s deletion (WS-01)
  is deliberately excluded from this minimum: it can survive far past
  `horizon/0`, and letting it pull the global minimum backward would
  make a stale cursor whose intervening *ordinary* entries were
  genuinely compacted away look serviceable when it is not — silently
  reintroducing the gap this function exists to make impossible to miss.
  """
  @spec oldest_surviving_seq() :: non_neg_integer() | nil
  def oldest_surviving_seq do
    from(e in Entry, where: ^not_fork_acknowledged_dynamic(), select: min(e.seq)) |> Repo.one()
  end
end
