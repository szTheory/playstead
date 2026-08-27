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

  @doc "The retention horizon (days), always >= `Playstead.Idempotency.retention_days/0` and this module's own floor."
  @spec horizon() :: pos_integer()
  def horizon, do: max(@floor_days, Idempotency.retention_days())

  @doc """
  Removes journal entries older than `horizon/0`. Invoked by a scheduled
  Oban job. Correctness of `/changes`'s 410 decision never depends on
  this having run recently — it only depends on it never running
  *more* aggressively than `horizon/0` allows.
  """
  @spec run() :: {:ok, non_neg_integer()}
  def run do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-horizon() * 24 * 60 * 60, :second)
      |> DateTime.truncate(:second)

    {count, _} = from(e in Entry, where: e.inserted_at < ^cutoff) |> Repo.delete_all()
    {:ok, count}
  end

  @doc """
  The lowest surviving `seq` across the whole journal, or `nil` if the
  journal is empty (nothing has ever been compacted away — every cursor
  is serviceable).
  """
  @spec oldest_surviving_seq() :: non_neg_integer() | nil
  def oldest_surviving_seq do
    from(e in Entry, select: min(e.seq)) |> Repo.one()
  end
end
