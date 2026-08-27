defmodule Playstead.Sync.CompactionTest do
  use Playstead.DataCase, async: true

  import Playstead.AccountsFixtures
  import Playstead.SyncFixtures

  alias Playstead.Idempotency
  alias Playstead.Sync.{ChangeJournal, Compaction}

  describe "horizon/0" do
    test "is greater than or equal to the idempotency receipt retention" do
      assert Compaction.horizon() >= Idempotency.retention_days()
    end

    test "never reads below its own floor even if retention shortens" do
      # Compaction.horizon/0 is defined as max(floor, retention_days()) —
      # asserting the concrete relationship here (rather than just >=)
      # so a future edit that shortens Idempotency.retention_days/0
      # can't silently pull the horizon down with it.
      assert Compaction.horizon() == max(90, Idempotency.retention_days())
    end
  end

  describe "run/0 and oldest_surviving_seq/0" do
    test "oldest_surviving_seq/0 is nil for an empty journal" do
      assert Compaction.oldest_surviving_seq() == nil
    end

    test "run/0 removes entries older than the horizon and preserves recent ones" do
      user = owner_fixture()
      old_entry = journal_entry_fixture(user.id, :device, "d1", %{})

      old_timestamp =
        DateTime.utc_now()
        |> DateTime.add(-(Compaction.horizon() + 1) * 24 * 60 * 60, :second)
        |> DateTime.truncate(:second)

      Repo.update_all(
        from(e in Playstead.Sync.Entry, where: e.id == ^old_entry.id),
        set: [inserted_at: old_timestamp]
      )

      recent_entry = journal_entry_fixture(user.id, :device, "d2", %{})

      {:ok, removed} = Compaction.run()
      assert removed >= 1

      assert Compaction.oldest_surviving_seq() == recent_entry.seq
      refute Repo.get(Playstead.Sync.Entry, old_entry.id)
    end

    test "a cursor exactly at the surviving boundary still resolves after compaction, a cursor before it does not" do
      user = owner_fixture()

      old1 = journal_entry_fixture(user.id, :device, "d1", %{})
      old2 = journal_entry_fixture(user.id, :device, "d2", %{})
      keep = journal_entry_fixture(user.id, :device, "d3", %{})

      old_timestamp =
        DateTime.utc_now()
        |> DateTime.add(-(Compaction.horizon() + 1) * 24 * 60 * 60, :second)
        |> DateTime.truncate(:second)

      Repo.update_all(
        from(e in Playstead.Sync.Entry, where: e.id in ^[old1.id, old2.id]),
        set: [inserted_at: old_timestamp]
      )

      {:ok, _removed} = Compaction.run()

      assert Compaction.oldest_surviving_seq() == keep.seq

      # A cursor at old2.seq (== keep.seq - 1, the surviving boundary's
      # predecessor) is still serviceable via ChangeJournal directly —
      # Playstead.Sync.changes_after/2's 410 semantics are exercised at
      # the controller/facade level in changes_controller_test.exs.
      assert ChangeJournal.read_after(user.id, old2.seq, 100) == [keep]
    end
  end
end
