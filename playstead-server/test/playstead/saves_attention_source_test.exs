defmodule Playstead.SavesAttentionSourceTest do
  @moduledoc """
  Plan 04-10 task 1: the saves-owned attention source (D-66) --
  `Playstead.Attention.Reason` stays frozen while divergence, blocked
  capture, and per-user backstops raise items through
  `Playstead.Saves.AttentionSource`'s own table and vocabulary.
  """

  use Playstead.DataCase, async: true

  import Playstead.AccountsFixtures
  import Playstead.PairingFixtures

  alias Playstead.Attention
  alias Playstead.Blobs
  alias Playstead.Saves
  alias Playstead.Saves.AttentionSource

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

  describe "Playstead.Attention.Reason stays frozen (D-66)" do
    test "the frozen nine-member vocabulary is unchanged" do
      assert Attention.Reason.all() == [
               :missing_member,
               :quarantined,
               :patch_file_detected,
               :failed_after_retries,
               :ambiguous_recognition,
               :signature_mismatch,
               :unknown_system,
               :confirm_system,
               :archives_kept_unopened
             ]
    end
  end

  describe "raising a divergence item" do
    test "a fork (two heads on one line) raises exactly one saves attention item with the fork's grouping key" do
      scope = user_scope_fixture()
      %{device: device_a} = device_fixture(scope)
      %{device: device_b} = device_fixture(scope)
      key = content_key()

      {:ok, revision_a} = commit!(scope, device_a, key, :crypto.strong_rand_bytes(1024))
      {:ok, revision_b} = commit!(scope, device_b, key, :crypto.strong_rand_bytes(1024))

      assert revision_a.save_line_id == revision_b.save_line_id
      line_id = revision_a.save_line_id

      grouped = AttentionSource.list_items(scope.user.id)
      assert [item] = grouped["divergence"]
      assert item.grouping_key == line_id
      assert item.count == 1
    end

    test "raising the same item twice upserts and increments rather than duplicating" do
      scope = user_scope_fixture()
      %{device: device_a} = device_fixture(scope)
      %{device: device_b} = device_fixture(scope)
      key = content_key()

      {:ok, revision_a} = commit!(scope, device_a, key, :crypto.strong_rand_bytes(1024))
      {:ok, _revision_b} = commit!(scope, device_b, key, :crypto.strong_rand_bytes(1024))
      # A third device commits a new root on the same line -- a second,
      # independent trigger for the same fork's divergence item.
      {:ok, _revision_c} =
        commit!(scope, device_a, key, :crypto.strong_rand_bytes(1024), origin: "external")

      grouped = AttentionSource.list_items(scope.user.id)
      assert [item] = grouped["divergence"]
      assert item.grouping_key == revision_a.save_line_id
      assert item.count >= 2
    end
  end

  describe "resolving and acknowledging clear the divergence item (D-52)" do
    test "resolving a fork clears its divergence attention item" do
      scope = user_scope_fixture()
      %{device: device_a} = device_fixture(scope)
      %{device: device_b} = device_fixture(scope)
      key = content_key()

      {:ok, revision_a} = commit!(scope, device_a, key, :crypto.strong_rand_bytes(1024))
      {:ok, _revision_b} = commit!(scope, device_b, key, :crypto.strong_rand_bytes(1024))
      line_id = revision_a.save_line_id

      assert %{"divergence" => [_item]} = AttentionSource.list_items(scope.user.id)

      assert {:ok, _resolution} =
               Saves.resolve_divergence(scope.user.id, device_a, line_id, revision_a.id)

      refute Map.has_key?(AttentionSource.list_items(scope.user.id), "divergence")
    end

    test "acknowledging a fork (keep both) clears its item and the fork is never re-raised" do
      scope = user_scope_fixture()
      %{device: device_a} = device_fixture(scope)
      %{device: device_b} = device_fixture(scope)
      key = content_key()

      {:ok, revision_a} = commit!(scope, device_a, key, :crypto.strong_rand_bytes(1024))
      {:ok, _revision_b} = commit!(scope, device_b, key, :crypto.strong_rand_bytes(1024))
      line_id = revision_a.save_line_id

      assert %{"divergence" => [_item]} = AttentionSource.list_items(scope.user.id)

      assert {:ok, _ack} = Saves.acknowledge_divergence(scope.user.id, device_a, line_id)

      refute Map.has_key?(AttentionSource.list_items(scope.user.id), "divergence")
      refute Saves.needs_divergence_decision?(scope.user.id, line_id)

      # Re-asking still reports "no decision needed" for this exact,
      # already-acknowledged head set -- an acknowledged fork is never
      # re-raised for itself (D-52), even on a second read.
      refute Map.has_key?(AttentionSource.list_items(scope.user.id), "divergence")
      refute Saves.needs_divergence_decision?(scope.user.id, line_id)
    end
  end

  describe "blocked capture" do
    test "a blocked capture raises a saves attention item, and clearing the blockage clears it" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      key = content_key()
      {:ok, revision} = commit!(scope, device, key, :crypto.strong_rand_bytes(1024))
      line_id = revision.save_line_id

      assert {:ok, _item} = Saves.report_capture_blocked(scope.user.id, line_id)
      assert %{"capture_blocked" => [item]} = AttentionSource.list_items(scope.user.id)
      assert item.grouping_key == line_id

      assert {:ok, 1} = Saves.clear_capture_blocked(scope.user.id, line_id)
      refute Map.has_key?(AttentionSource.list_items(scope.user.id), "capture_blocked")
    end
  end

  describe "per-user retention backstops (D-28)" do
    test "crossing a backstop raises an item and refuses no commit" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)

      assert :ok =
               AttentionSource.maybe_raise_backstop(
                 scope.user.id,
                 :revision_count,
                 100_001,
                 100_000
               )

      assert %{"retention_backstop" => [item]} = AttentionSource.list_items(scope.user.id)
      assert item.grouping_key == "backstop:revision_count"

      # The next commit still succeeds -- a backstop crossing is
      # surfaced as attention, never enforced as a refusal.
      assert {:ok, _revision} =
               commit!(scope, device, content_key(), :crypto.strong_rand_bytes(1024))
    end

    test "below the threshold, no item is raised" do
      scope = user_scope_fixture()

      assert :ok = AttentionSource.maybe_raise_backstop(scope.user.id, :storage_bytes, 5, 100)
      refute Map.has_key?(AttentionSource.list_items(scope.user.id), "retention_backstop")
    end
  end

  describe "the inbox union at read time (D-66)" do
    test "a user with neither kind of item gets an empty inbox, not an error" do
      scope = user_scope_fixture()

      assert Attention.list_items(scope.user.id) == %{}
      assert AttentionSource.list_items(scope.user.id) == %{}

      merged =
        Map.merge(Attention.list_items(scope.user.id), AttentionSource.list_items(scope.user.id))

      assert merged == %{}
    end

    test "the union combines Playstead.Attention items and saves items for one user" do
      scope = user_scope_fixture()
      %{device: device_a} = device_fixture(scope)
      %{device: device_b} = device_fixture(scope)
      key = content_key()

      {:ok, _revision_a} = commit!(scope, device_a, key, :crypto.strong_rand_bytes(1024))
      {:ok, _revision_b} = commit!(scope, device_b, key, :crypto.strong_rand_bytes(1024))

      {:ok, _import_item} =
        Attention.raise_item(%{
          user_id: scope.user.id,
          unknown_system?: true,
          grouping_key: Ecto.UUID.generate()
        })

      merged =
        Map.merge(
          Attention.list_items(scope.user.id),
          AttentionSource.list_items(scope.user.id),
          fn _reason, a, b -> a ++ b end
        )

      assert Map.has_key?(merged, "unknown_system")
      assert Map.has_key?(merged, "divergence")
    end
  end
end
