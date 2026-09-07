defmodule Playstead.SavesBranchesTest do
  @moduledoc """
  Plan 04-05 task 1: the revision DAG's accept-and-branch commits and
  derived branch heads (D-11, D-12, D-13, D-14, D-15).
  """

  use Playstead.DataCase, async: true

  import Ecto.Query, warn: false
  import Playstead.AccountsFixtures
  import Playstead.PairingFixtures

  alias Playstead.Blobs
  alias Playstead.Saves
  alias Playstead.Saves.Branches

  setup do
    File.mkdir_p!(Blobs.Store.LocalDisk.blob_path())
    :ok
  end

  defp content_key,
    do: :crypto.hash(:sha256, :crypto.strong_rand_bytes(16)) |> Base.encode16(case: :lower)

  defp commit!(scope, device, content_key, bytes, extra_attrs \\ %{}) do
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
      Map.merge(
        %{"id" => Ecto.UUID.generate(), "command_id" => command_id, "content_key" => content_key},
        extra_attrs
      )

    Saves.commit_revision(scope.user.id, device, attrs)
  end

  describe "accept-and-branch commits (D-13)" do
    test "a linear chain of two commits produces exactly one head" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      key = content_key()

      {:ok, root} = commit!(scope, device, key, :crypto.strong_rand_bytes(64))

      {:ok, child} =
        commit!(scope, device, key, :crypto.strong_rand_bytes(64), %{
          "parent_revision_id" => root.id
        })

      heads = Branches.heads(scope.user.id, root.save_line_id)
      assert Enum.map(heads, & &1.id) == [child.id]
      refute Branches.diverged?(scope.user.id, root.save_line_id)
    end

    test "two commits naming the same parent both succeed and produce two heads" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      key = content_key()

      {:ok, root} = commit!(scope, device, key, :crypto.strong_rand_bytes(64))

      {:ok, branch_a} =
        commit!(scope, device, key, :crypto.strong_rand_bytes(64), %{
          "parent_revision_id" => root.id
        })

      {:ok, branch_b} =
        commit!(scope, device, key, :crypto.strong_rand_bytes(64), %{
          "parent_revision_id" => root.id
        })

      heads = Branches.heads(scope.user.id, root.save_line_id)
      assert MapSet.new(Enum.map(heads, & &1.id)) == MapSet.new([branch_a.id, branch_b.id])
      assert Branches.diverged?(scope.user.id, root.save_line_id)
    end

    test "a second root on a line that already has a head is accepted and produces two heads (D-11)" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      key = content_key()

      {:ok, first_root} = commit!(scope, device, key, :crypto.strong_rand_bytes(64))
      {:ok, second_root} = commit!(scope, device, key, :crypto.strong_rand_bytes(64))

      assert first_root.save_line_id == second_root.save_line_id
      assert is_nil(first_root.parent_revision_id)
      assert is_nil(second_root.parent_revision_id)

      heads = Branches.heads(scope.user.id, first_root.save_line_id)
      assert MapSet.new(Enum.map(heads, & &1.id)) == MapSet.new([first_root.id, second_root.id])
    end
  end

  describe "Branches.heads/2" do
    test "a line with no revisions returns an empty list" do
      scope = user_scope_fixture()
      assert Branches.heads(scope.user.id, Ecto.UUID.generate()) == []
    end

    test "heads/2 returns a recorded_at tie in a stable id-ascending order" do
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
        commit!(scope, device, key, :crypto.strong_rand_bytes(64), %{
          "id" => greater_id,
          "parent_revision_id" => root.id
        })

      {:ok, lower_child} =
        commit!(scope, device, key, :crypto.strong_rand_bytes(64), %{
          "id" => lower_id,
          "parent_revision_id" => root.id
        })

      tied_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      {2, nil} =
        Playstead.Repo.update_all(
          from(r in Playstead.Saves.Revision,
            where: r.id in [^greater_child.id, ^lower_child.id]
          ),
          set: [recorded_at: tied_at]
        )

      heads = Branches.heads(scope.user.id, root.save_line_id)

      assert Enum.map(heads, & &1.id) == [lower_child.id, greater_child.id]
    end
  end

  describe "base evidence (D-12)" do
    test "a base_sha256 mismatch is recorded as base_matched: false and the commit still succeeds" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      key = content_key()

      {:ok, root} = commit!(scope, device, key, :crypto.strong_rand_bytes(64))

      {:ok, child} =
        commit!(scope, device, key, :crypto.strong_rand_bytes(64), %{
          "parent_revision_id" => root.id,
          "base_sha256" => "not-the-parent-digest"
        })

      assert child.base_matched == false
    end

    test "a base_sha256 matching the named parent's blob digest is recorded as base_matched: true" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      key = content_key()

      {:ok, root} = commit!(scope, device, key, :crypto.strong_rand_bytes(64))

      {:ok, child} =
        commit!(scope, device, key, :crypto.strong_rand_bytes(64), %{
          "parent_revision_id" => root.id,
          "base_sha256" => root.blob_sha256
        })

      assert child.base_matched == true
    end
  end

  describe "ordering is by server recorded_at, never device time (D-15)" do
    test "a revision whose device_captured_at contradicts arrival order still sorts by recorded_at" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      key = content_key()

      earlier_claimed =
        DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:microsecond)

      later_claimed =
        DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:microsecond)

      {:ok, first_committed} =
        commit!(scope, device, key, :crypto.strong_rand_bytes(64), %{
          "device_captured_at" => later_claimed
        })

      {:ok, second_committed} =
        commit!(scope, device, key, :crypto.strong_rand_bytes(64), %{
          "parent_revision_id" => first_committed.id,
          "device_captured_at" => earlier_claimed
        })

      heads = Branches.heads(scope.user.id, first_committed.save_line_id)
      assert Enum.map(heads, & &1.id) == [second_committed.id]
      assert DateTime.compare(first_committed.recorded_at, second_committed.recorded_at) == :lt
    end
  end
end
