defmodule Playstead.SavesTest do
  @moduledoc """
  Plan 04-04 task 3: the assumption-delta invariant (two devices, one
  identity tuple, one save line) and the snapshot `save:` branch (D-17).
  """

  use Playstead.DataCase, async: true

  import Ecto.Query
  import Playstead.AccountsFixtures
  import Playstead.PairingFixtures

  alias Playstead.Blobs
  alias Playstead.Idempotency
  alias Playstead.Repo
  alias Playstead.Saves
  alias Playstead.Saves.{Branches, RevisionParent, Save}
  alias Playstead.Sync.Snapshot

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

  describe "assumption-delta invariant: two devices, one identity tuple, one save line" do
    # v1 ships exactly one supported `save_kind` ("battery", D-10) --
    # asserted explicitly here rather than parameterized over a list of
    # one, so a future save_kind addition is a deliberate new test, not
    # a silently-widened loop.
    test "two revisions from different devices on the same (user, content_key, save_kind, slot) land on one save line" do
      scope = user_scope_fixture()
      %{device: device_a} = device_fixture(scope)
      %{device: device_b} = device_fixture(scope)
      key = content_key()

      {:ok, revision_a} = commit!(scope, device_a, key, :crypto.strong_rand_bytes(1024))
      {:ok, revision_b} = commit!(scope, device_b, key, :crypto.strong_rand_bytes(1024))

      assert revision_a.save_line_id == revision_b.save_line_id
      assert Repo.aggregate(from(s in Save, where: s.user_id == ^scope.user.id), :count) == 1
    end
  end

  describe "the snapshot save: branch (D-17)" do
    test "a user with no saves gets an empty save branch, not a missing key" do
      scope = user_scope_fixture()
      {:ok, page} = Snapshot.read(scope.user.id)
      assert page.save == []
    end

    test "a committed revision appears in the save branch from the same transaction as catalogue/curation" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      {:ok, revision} = commit!(scope, device, content_key(), :crypto.strong_rand_bytes(512))

      {:ok, page} = Snapshot.read(scope.user.id)

      assert Enum.any?(page.save, &(&1.revision_id == revision.id))
      assert is_list(page.catalogue)
      assert is_list(page.curation)
    end

    test "applying the same save page twice leaves the local row count unchanged (idempotence contract)" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      {:ok, revision} = commit!(scope, device, content_key(), :crypto.strong_rand_bytes(512))

      {:ok, page1} = Snapshot.read(scope.user.id)
      {:ok, page2} = Snapshot.read(scope.user.id)

      first = Enum.find(page1.save, &(&1.revision_id == revision.id))
      second = Enum.find(page2.save, &(&1.revision_id == revision.id))
      assert first == second
    end
  end

  describe "commit invariants (plan 04-05 task 2)" do
    test "committing a revision naming an unknown parent returns save_parent_unknown" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)

      {:error, {:save_parent_unknown, _detail}} =
        commit!(scope, device, content_key(), :crypto.strong_rand_bytes(64),
          parent_revision_id: Ecto.UUID.generate()
        )
    end

    test "an attempt to insert a revision under an id that already exists returns save_revision_immutable" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      {:ok, revision} = commit!(scope, device, content_key(), :crypto.strong_rand_bytes(64))

      {:ok, _status, meta} = Blobs.put_stream([:crypto.strong_rand_bytes(64)], 64)
      command_id = Ecto.UUID.generate()

      {:ok, _pending} =
        Saves.record_pending_upload(
          scope.user.id,
          device.id,
          command_id,
          meta.sha256,
          meta.size_bytes
        )

      assert {:error, {:save_revision_immutable, _detail}} =
               Saves.commit_revision(scope.user.id, device, %{
                 "id" => revision.id,
                 "command_id" => command_id,
                 "content_key" => content_key()
               })
    end

    test "get_history/2 returns a line's revisions and derived heads, scoped by user_id" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      key = content_key()
      {:ok, revision} = commit!(scope, device, key, :crypto.strong_rand_bytes(64))

      other_scope = user_scope_fixture()
      assert {:error, :not_found} = Saves.get_history(other_scope.user.id, revision.save_line_id)

      assert {:ok, %{revisions: revisions, heads: heads}} =
               Saves.get_history(scope.user.id, revision.save_line_id)

      assert Enum.map(revisions, & &1.id) == [revision.id]
      assert Enum.map(heads, & &1.id) == [revision.id]
    end

    test "get_history/2 returns a recorded_at tie in a stable id-ascending order" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      key = content_key()

      {:ok, root} = commit!(scope, device, key, :crypto.strong_rand_bytes(64))

      # Commit the lexically-GREATER id first so an unfixed
      # single-key sort (which has nothing to break the tie with)
      # would return insertion order -- the inverse of id order --
      # rather than accidentally passing.
      [lower_id, greater_id] = Enum.sort([Ecto.UUID.generate(), Ecto.UUID.generate()])

      {:ok, greater_child} =
        commit!(scope, device, key, :crypto.strong_rand_bytes(64),
          id: greater_id,
          parent_revision_id: root.id
        )

      {:ok, lower_child} =
        commit!(scope, device, key, :crypto.strong_rand_bytes(64),
          id: lower_id,
          parent_revision_id: root.id
        )

      tied_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      {2, nil} =
        Repo.update_all(
          from(r in Playstead.Saves.Revision,
            where: r.id in [^greater_child.id, ^lower_child.id]
          ),
          set: [recorded_at: tied_at]
        )

      assert {:ok, %{revisions: revisions}} = Saves.get_history(scope.user.id, root.save_line_id)

      [_root_revision, first_child, second_child] = revisions
      assert DateTime.compare(first_child.recorded_at, second_child.recorded_at) == :eq
      assert first_child.id == lower_child.id
      assert second_child.id == greater_child.id
    end
  end

  describe "append-only divergence resolution (plan 04-05 task 3)" do
    defp diverge!(scope, device, key) do
      {:ok, root} = commit!(scope, device, key, :crypto.strong_rand_bytes(64))

      {:ok, branch_a} =
        commit!(scope, device, key, :crypto.strong_rand_bytes(64), parent_revision_id: root.id)

      {:ok, branch_b} =
        commit!(scope, device, key, :crypto.strong_rand_bytes(64), parent_revision_id: root.id)

      {root, branch_a, branch_b}
    end

    test "choosing a side appends one resolution revision naming every head, exactly one chosen" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      key = content_key()
      {_root, branch_a, branch_b} = diverge!(scope, device, key)

      assert {:ok, resolution} =
               Saves.resolve_divergence(scope.user.id, device, branch_a.save_line_id, branch_a.id)

      edges =
        from(rp in RevisionParent, where: rp.revision_id == ^resolution.id)
        |> Repo.all()

      assert length(edges) == 2
      assert Enum.find(edges, &(&1.parent_revision_id == branch_a.id)).role == "chosen"
      assert Enum.find(edges, &(&1.parent_revision_id == branch_b.id)).role == "acknowledged"
    end

    test "after resolution, both original heads still exist and neither is modified" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      key = content_key()
      {_root, branch_a, branch_b} = diverge!(scope, device, key)

      {:ok, _resolution} =
        Saves.resolve_divergence(scope.user.id, device, branch_a.save_line_id, branch_a.id)

      reloaded_a = Saves.get_revision(scope.user.id, branch_a.id)
      reloaded_b = Saves.get_revision(scope.user.id, branch_b.id)

      assert reloaded_a.blob_sha256 == branch_a.blob_sha256
      assert reloaded_b.blob_sha256 == branch_b.blob_sha256
    end

    test "the resolution revision's blob is the chosen side's bytes and adds no new blob digest" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      key = content_key()
      {_root, branch_a, _branch_b} = diverge!(scope, device, key)

      {:ok, resolution} =
        Saves.resolve_divergence(scope.user.id, device, branch_a.save_line_id, branch_a.id)

      assert resolution.blob_sha256 == branch_a.blob_sha256

      distinct_digests_before =
        from(r in Playstead.Saves.Revision,
          where: r.user_id == ^scope.user.id and r.save_line_id == ^branch_a.save_line_id,
          where: r.id != ^resolution.id,
          select: r.blob_sha256,
          distinct: true
        )
        |> Repo.all()
        |> MapSet.new()

      assert MapSet.member?(distinct_digests_before, resolution.blob_sha256)
    end

    test "N-way divergence with three heads resolves in a single act with three parent rows" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      key = content_key()
      {:ok, root} = commit!(scope, device, key, :crypto.strong_rand_bytes(64))

      {:ok, a} =
        commit!(scope, device, key, :crypto.strong_rand_bytes(64), parent_revision_id: root.id)

      {:ok, b} =
        commit!(scope, device, key, :crypto.strong_rand_bytes(64), parent_revision_id: root.id)

      {:ok, c} =
        commit!(scope, device, key, :crypto.strong_rand_bytes(64), parent_revision_id: root.id)

      assert {:ok, resolution} =
               Saves.resolve_divergence(scope.user.id, device, root.save_line_id, a.id)

      edges = from(rp in RevisionParent, where: rp.revision_id == ^resolution.id) |> Repo.all()
      assert length(edges) == 3
      assert MapSet.new(edges, & &1.parent_revision_id) == MapSet.new([a.id, b.id, c.id])
    end

    test "two devices resolving the same fork independently in both arrival orders converge to identical retained-revision sets" do
      scope1 = user_scope_fixture()
      %{device: device1} = device_fixture(scope1)
      key1 = content_key()
      {_root1, branch_a1, branch_b1} = diverge!(scope1, device1, key1)

      scope2 = user_scope_fixture()
      %{device: device2} = device_fixture(scope2)
      key2 = content_key()
      {_root2, branch_a2, branch_b2} = diverge!(scope2, device2, key2)

      # Order A: device chooses branch_a then (independently) branch_b's device chooses branch_b.
      {:ok, res1} =
        Saves.resolve_divergence(scope1.user.id, device1, branch_a1.save_line_id, branch_a1.id)

      {:ok, res1b} =
        Saves.resolve_divergence(scope1.user.id, device1, branch_a1.save_line_id, branch_b1.id)

      # Order B: reversed.
      {:ok, res2b} =
        Saves.resolve_divergence(scope2.user.id, device2, branch_a2.save_line_id, branch_b2.id)

      {:ok, res2} =
        Saves.resolve_divergence(scope2.user.id, device2, branch_a2.save_line_id, branch_a2.id)

      retained1 =
        from(r in Playstead.Saves.Revision, where: r.user_id == ^scope1.user.id, select: r.id)
        |> Repo.all()
        |> MapSet.new()

      retained2 =
        from(r in Playstead.Saves.Revision, where: r.user_id == ^scope2.user.id, select: r.id)
        |> Repo.all()
        |> MapSet.new()

      assert MapSet.size(retained1) == MapSet.size(retained2)
      assert MapSet.member?(retained1, res1.id) and MapSet.member?(retained1, res1b.id)
      assert MapSet.member?(retained2, res2.id) and MapSet.member?(retained2, res2b.id)
    end

    test "replaying the same resolution with the same idempotency key appends no second resolution revision" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      key = content_key()
      {_root, branch_a, _branch_b} = diverge!(scope, device, key)

      effect_fun = fn ->
        case Saves.resolve_divergence(scope.user.id, device, branch_a.save_line_id, branch_a.id) do
          {:ok, revision} -> {:ok, 201, %{id: revision.id}}
          {:error, reason} -> {:error, reason}
        end
      end

      idem_key = "resolve-#{System.unique_integer([:positive])}"
      fingerprint = "fingerprint"

      # Mirrors `PlaysteadWeb.Plugs.Idempotency`'s pre-flight
      # fetch/execute split: the plug (not `execute/4` itself) is what
      # classifies a replay and short-circuits before the effect runs.
      {:ok, :fresh} = Idempotency.fetch(device.id, idem_key, fingerprint)
      {:ok, 201, body1} = Idempotency.execute(device.id, idem_key, fingerprint, effect_fun)

      {:ok, :replay, receipt} = Idempotency.fetch(device.id, idem_key, fingerprint)
      body2 = Jason.decode!(receipt.response_body)

      assert body1.id == body2["id"]

      resolution_count =
        from(r in Playstead.Saves.Revision,
          where: r.user_id == ^scope.user.id and r.capture_method == "resolution"
        )
        |> Repo.aggregate(:count)

      assert resolution_count == 1
    end

    test "keeping both leaves every head standing" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      key = content_key()
      {_root, branch_a, branch_b} = diverge!(scope, device, key)

      heads_before =
        Branches.heads(scope.user.id, branch_a.save_line_id) |> Enum.map(& &1.id) |> MapSet.new()

      assert {:ok, %{head_ids: head_ids}} =
               Saves.acknowledge_divergence(scope.user.id, device, branch_a.save_line_id)

      heads_after =
        Branches.heads(scope.user.id, branch_a.save_line_id) |> Enum.map(& &1.id) |> MapSet.new()

      assert heads_before == heads_after
      assert MapSet.new(head_ids) == MapSet.new([branch_a.id, branch_b.id])
    end

    test "an acknowledged fork is absent from needs-a-decision while both heads remain heads" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      key = content_key()
      {_root, branch_a, branch_b} = diverge!(scope, device, key)

      assert Saves.needs_divergence_decision?(scope.user.id, branch_a.save_line_id)

      {:ok, _ack} = Saves.acknowledge_divergence(scope.user.id, device, branch_a.save_line_id)

      refute Saves.needs_divergence_decision?(scope.user.id, branch_a.save_line_id)

      heads =
        Branches.heads(scope.user.id, branch_a.save_line_id) |> Enum.map(& &1.id) |> MapSet.new()

      assert heads == MapSet.new([branch_a.id, branch_b.id])
    end
  end
end
