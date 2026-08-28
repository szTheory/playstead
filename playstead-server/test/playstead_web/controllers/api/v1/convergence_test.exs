defmodule PlaysteadWeb.Api.V1.ConvergenceTest do
  @moduledoc """
  The PROT-05/D-21 contract-gate proof: a client that missed every
  intermediate change converges to state identical to a fresh client's,
  whether it recovers via `/changes` alone or via 410-then-snapshot.
  Structurally compares reconstructed state (not response bodies), and
  proves a deletion (device revocation) never survives as a phantom row
  in either reconstruction path.
  """

  use PlaysteadWeb.ApiCase, async: false

  import Ecto.Query
  import Playstead.PairingFixtures
  import Playstead.AccountsFixtures

  alias Playstead.Pairing
  alias Playstead.Repo
  alias Playstead.Sync.{Compaction, Entry}

  defp authed_conn(token) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer #{token}")
  end

  defp changes(token, cursor \\ nil) do
    conn =
      if cursor do
        authed_conn(token) |> get(~p"/api/v1/changes?cursor=#{cursor}")
      else
        authed_conn(token) |> get(~p"/api/v1/changes")
      end

    json_response(conn, conn.status)
  end

  defp snapshot(token) do
    conn = authed_conn(token) |> get(~p"/api/v1/snapshot")
    json_response(conn, 200)
  end

  # Applies a stream of /changes entries to a local in-memory map of
  # `entity_id => payload`, exactly like a real client's local cache
  # merge logic would: an upsert sets/replaces the entity, a tombstone
  # removes it entirely.
  defp apply_entries(state, entries) do
    Enum.reduce(entries, state, fn entry, acc ->
      case entry["operation"] do
        "tombstone" -> Map.delete(acc, entry["entity_id"])
        "upsert" -> Map.put(acc, entry["entity_id"], entry["payload"])
      end
    end)
  end

  defp drain_changes(token, cursor, state) do
    %{"entries" => entries, "cursor" => next_cursor, "has_more" => has_more} =
      changes(token, cursor)

    state = apply_entries(state, entries)

    if has_more do
      drain_changes(token, next_cursor, state)
    else
      state
    end
  end

  defp snapshot_state(token) do
    %{"entries" => entries} = snapshot(token)

    Enum.into(entries, %{}, fn e -> {e["entity_id"], e["payload"]} end)
  end

  test "a client that misses every change converges via /changes-only, via 410-then-snapshot, and a tombstoned device is absent from both" do
    scope = user_scope_fixture()

    # Device A is a fresh-client viewpoint used as ground truth; device
    # B is the resuming client under test that goes "offline" (and
    # stays authenticated throughout — it is never itself the device
    # being revoked); device C is a third device whose lifecycle events
    # happen while B is offline, including the tombstone-producing
    # revocation B must observe on resume.
    %{device: device_a, credential_plaintext: token_a} = device_fixture(scope)
    %{credential_plaintext: token_b} = device_fixture(scope)
    %{device: device_c} = device_fixture(scope)

    # Baseline: the state device B's local cache already holds (a
    # snapshot of everything paired so far), and B's own journal cursor
    # at that same point — both taken before any of the mutations below.
    baseline_state = snapshot_state(token_a)
    %{"cursor" => baseline_cursor} = changes(token_b)

    # Device B "goes offline" while these mutations happen through the
    # real API/domain layer, accumulating upserts and a tombstone.
    {:ok, _} = Pairing.rename_device(scope, device_c.id, "Renamed While B Was Offline")
    {:ok, %{fingerprint_prefix: _}} = Pairing.rotate_credential(device_c)
    {:ok, revoked} = Pairing.revoke_device(scope, device_c.id)

    assert revoked.revoked_at

    # A fresh client's full read, via snapshot alone — the ground truth
    # every recovery path must match.
    fresh_state = snapshot_state(token_a)

    # --- Path one: /changes only, from the pre-offline baseline. ---
    changes_only_state = drain_changes(token_b, baseline_cursor, baseline_state)

    assert changes_only_state == fresh_state
    refute Map.has_key?(changes_only_state, device_c.id)

    # --- Path two: force the baseline cursor to expire (410), take a
    # snapshot, and resume /changes from its as-of cursor. ---
    #
    # Everything written so far — including C's rename/revoke tombstone
    # — gets compacted away, so there is a genuine gap after
    # `baseline_cursor`. A harmless mutation on device A afterwards
    # gives the journal a fresh surviving entry, which is what makes
    # the 410 boundary well-defined rather than "the journal is empty."
    max_seq_before_compaction = Playstead.Sync.ChangeJournal.max_seq(device_a.user_id)

    old_timestamp =
      DateTime.utc_now()
      |> DateTime.add(-(Compaction.horizon() + 1) * 24 * 60 * 60, :second)
      |> DateTime.truncate(:second)

    from(e in Entry, where: e.seq <= ^max_seq_before_compaction)
    |> Repo.update_all(set: [inserted_at: old_timestamp])

    {:ok, _} = Pairing.rename_device(scope, device_a.id, "Harmless Fresh Mutation")

    {:ok, _removed} = Compaction.run()

    expired_conn =
      authed_conn(token_b) |> get(~p"/api/v1/changes?cursor=#{baseline_cursor}")

    assert_problem(expired_conn, 410, :cursor_expired)

    %{"cursor" => as_of_cursor} = snapshot(token_a)
    snapshot_baseline = snapshot_state(token_a)

    resumed_state = drain_changes(token_b, as_of_cursor, snapshot_baseline)

    # The ground truth for path two is re-read after the harmless
    # mutation above (path one's `fresh_state` predates it).
    fresh_state_after_harmless_mutation = snapshot_state(token_a)

    assert resumed_state == fresh_state_after_harmless_mutation
    refute Map.has_key?(resumed_state, device_c.id)
  end

  test "GET /api/v1/snapshot writes no rows" do
    scope = user_scope_fixture()
    %{credential_plaintext: token} = device_fixture(scope)

    entry_count_before = Repo.aggregate(Entry, :count)
    device_count_before = Repo.aggregate(Playstead.Pairing.Device, :count)

    _ = snapshot(token)

    assert Repo.aggregate(Entry, :count) == entry_count_before
    assert Repo.aggregate(Playstead.Pairing.Device, :count) == device_count_before
  end

  test "a write that lands after the snapshot's pinned as-of is not duplicated when the feed is resumed" do
    # Sandboxed, single-connection variant. The genuinely concurrent cases
    # — a competing commit *inside* the snapshot transaction, and a
    # multi-page read with writes interleaved between pages — run against
    # real, independent Postgres transactions in
    # `Playstead.Sync.SnapshotConcurrencyTest` (async: false, sandbox
    # `:auto` mode), which `Ecto.Adapters.SQL.Sandbox.allow/3` cannot
    # produce here.
    scope = user_scope_fixture()
    %{device: device, credential_plaintext: token} = device_fixture(scope)

    %{"cursor" => as_of_cursor} = snapshot(token)

    {:ok, _} = Pairing.rename_device(scope, device.id, "Written After The Snapshot")

    %{"entries" => entries} = changes(token, as_of_cursor)

    matching = Enum.filter(entries, &(&1["entity_id"] == device.id))
    assert length(matching) == 1
  end

  test "resuming /changes from a snapshot's as-of cursor returns no entry already contained in the snapshot" do
    scope = user_scope_fixture()
    %{device: device, credential_plaintext: token} = device_fixture(scope)

    %{"cursor" => as_of_cursor} = snapshot(token)

    # No new mutations happened between the snapshot and this /changes
    # call, so resuming from its as-of cursor must yield nothing new —
    # in particular, not the device's own pairing/creation entries the
    # snapshot already reflects.
    %{"entries" => entries} = changes(token, as_of_cursor)

    refute Enum.any?(entries, &(&1["entity_id"] == device.id))
  end
end
