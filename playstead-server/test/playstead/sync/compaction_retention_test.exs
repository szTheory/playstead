defmodule Playstead.Sync.CompactionRetentionTest do
  @moduledoc """
  WS-01 (04-REVIEW.md / 04-17-PLAN.md task 3): `Compaction.run/0`
  unconditionally deleted every journal entry past `horizon/0`,
  including `fork_acknowledged` markers (D-52's "Keep both", written by
  `Saves.acknowledge_divergence/3`). `Saves.fork_acknowledged?/3` derives
  D-52's "never re-raised for that fork" guarantee from exactly those
  markers with no time bound of its own, so once one aged past the
  horizon and got deleted, the next commit on that line silently
  re-raised a fork the user had already resolved -- the exact
  event-horizon mistake D-17 solved for revision lineage, reintroduced
  here.

  These tests assert the fix: an acknowledgment survives past the
  horizon and keeps suppressing the divergence decision, ordinary
  entries are still deleted on schedule (retention is narrowed, not
  disabled), an unacknowledged fork is unaffected, and compaction stays
  idempotent.
  """

  use Playstead.DataCase, async: true

  import Ecto.Query
  import Playstead.AccountsFixtures
  import Playstead.PairingFixtures

  alias Playstead.Blobs
  alias Playstead.Repo
  alias Playstead.Saves
  alias Playstead.Saves.Branches
  alias Playstead.Sync.{Compaction, Entry}

  setup do
    File.mkdir_p!(Blobs.Store.LocalDisk.blob_path())
    :ok
  end

  defp content_key,
    do: :crypto.hash(:sha256, :crypto.strong_rand_bytes(16)) |> Base.encode16(case: :lower)

  defp commit!(scope, device, content_key, bytes, extra_attrs \\ []) do
    {:ok, _status, meta} = Blobs.put_stream([bytes], byte_size(bytes))

    command_id = Ecto.UUID.generate()

    {:ok, _pending} =
      Saves.record_pending_upload(
        scope.user.id,
        device.id,
        command_id,
        meta.sha256,
        meta.size_bytes
      )

    attrs =
      %{
        "id" => Ecto.UUID.generate(),
        "command_id" => command_id,
        "content_key" => content_key
      }
      |> Map.merge(Map.new(extra_attrs, fn {k, v} -> {to_string(k), v} end))

    Saves.commit_revision(scope.user.id, device, attrs)
  end

  defp diverge!(scope, device, key) do
    {:ok, root} = commit!(scope, device, key, :crypto.strong_rand_bytes(64))

    {:ok, branch_a} =
      commit!(scope, device, key, :crypto.strong_rand_bytes(64), parent_revision_id: root.id)

    {:ok, branch_b} =
      commit!(scope, device, key, :crypto.strong_rand_bytes(64), parent_revision_id: root.id)

    {root, branch_a, branch_b}
  end

  defp age_all_entries!(horizon_days) do
    old_timestamp =
      DateTime.utc_now()
      |> DateTime.add(-(horizon_days + 1) * 24 * 60 * 60, :second)
      |> DateTime.truncate(:second)

    Repo.update_all(from(e in Entry), set: [inserted_at: old_timestamp])
  end

  describe "run/0 exempts fork_acknowledged markers from deletion (WS-01)" do
    test "an acknowledgment older than Compaction.horizon/0 survives and fork_acknowledged?/3 still returns true" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      key = content_key()
      {_root, branch_a, branch_b} = diverge!(scope, device, key)

      assert {:ok, _ack} =
               Saves.acknowledge_divergence(scope.user.id, device, branch_a.save_line_id)

      refute Saves.needs_divergence_decision?(scope.user.id, branch_a.save_line_id)

      age_all_entries!(Compaction.horizon())

      assert {:ok, _removed} = Compaction.run()

      refute Saves.needs_divergence_decision?(scope.user.id, branch_a.save_line_id),
             "an acknowledgment older than the horizon must still suppress the divergence decision"

      heads =
        Branches.heads(scope.user.id, branch_a.save_line_id) |> Enum.map(& &1.id) |> MapSet.new()

      assert heads == MapSet.new([branch_a.id, branch_b.id]),
             "both heads must still stand -- nothing is ever deleted (D-48)"
    end

    test "an ordinary journal entry older than the horizon is still deleted -- retention is narrowed, not disabled" do
      user = owner_fixture()

      old_entry = Playstead.SyncFixtures.journal_entry_fixture(user.id, :device, "d1", %{})

      old_timestamp =
        DateTime.utc_now()
        |> DateTime.add(-(Compaction.horizon() + 1) * 24 * 60 * 60, :second)
        |> DateTime.truncate(:second)

      Repo.update_all(from(e in Entry, where: e.id == ^old_entry.id),
        set: [inserted_at: old_timestamp]
      )

      recent_entry = Playstead.SyncFixtures.journal_entry_fixture(user.id, :device, "d2", %{})

      assert {:ok, removed} = Compaction.run()
      assert removed >= 1
      refute Repo.get(Entry, old_entry.id)
      assert Repo.get(Entry, recent_entry.id)
    end

    test "a two-head line with no acknowledgment is still reported diverged after compaction runs" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      key = content_key()
      {_root, branch_a, _branch_b} = diverge!(scope, device, key)

      assert Saves.needs_divergence_decision?(scope.user.id, branch_a.save_line_id)

      age_all_entries!(Compaction.horizon())
      assert {:ok, _removed} = Compaction.run()

      assert Saves.needs_divergence_decision?(scope.user.id, branch_a.save_line_id),
             "compaction must not manufacture an acknowledgment that was never given"
    end

    test "running compaction twice changes nothing the second time" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      key = content_key()
      {_root, branch_a, _branch_b} = diverge!(scope, device, key)

      assert {:ok, _ack} =
               Saves.acknowledge_divergence(scope.user.id, device, branch_a.save_line_id)

      age_all_entries!(Compaction.horizon())

      assert {:ok, _first_removed} = Compaction.run()
      assert {:ok, second_removed} = Compaction.run()

      assert second_removed == 0, "a second compaction pass must find nothing new to remove"
      refute Saves.needs_divergence_decision?(scope.user.id, branch_a.save_line_id)
    end

    test "oldest_surviving_seq/0 is not pulled backward by a surviving acknowledgment entry" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      key = content_key()
      {_root, branch_a, _branch_b} = diverge!(scope, device, key)

      assert {:ok, _ack} =
               Saves.acknowledge_divergence(scope.user.id, device, branch_a.save_line_id)

      ack_entry =
        from(e in Entry,
          where:
            e.entity_kind == "save" and fragment("?->>'type' = ?", e.payload, "fork_acknowledged"),
          order_by: [desc: e.seq],
          limit: 1
        )
        |> Repo.one()

      age_all_entries!(Compaction.horizon())

      recent_entry =
        Playstead.SyncFixtures.journal_entry_fixture(scope.user.id, :device, "recent-device", %{})

      assert {:ok, _removed} = Compaction.run()

      # The acknowledgment survived (aged past the horizon, exempted from
      # deletion) but must not become the reported boundary -- only the
      # oldest *ordinary* surviving entry may, or a cursor sitting between
      # the two would be told it's serviceable when the entries it needs
      # were, in fact, compacted away.
      assert Compaction.oldest_surviving_seq() == recent_entry.seq
      assert ack_entry.seq < recent_entry.seq

      assert Repo.get(Entry, ack_entry.id),
             "precondition: the acknowledgment entry itself must have survived"
    end
  end
end
