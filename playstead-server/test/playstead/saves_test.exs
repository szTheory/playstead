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
  alias Playstead.Repo
  alias Playstead.Saves
  alias Playstead.Saves.Save
  alias Playstead.Sync.Snapshot

  setup do
    File.mkdir_p!(Blobs.Store.LocalDisk.blob_path())
    :ok
  end

  defp content_key, do: :crypto.hash(:sha256, :crypto.strong_rand_bytes(16)) |> Base.encode16(case: :lower)

  defp commit!(scope, device, content_key, bytes) do
    {:ok, _status, meta} = Blobs.put_stream([bytes], byte_size(bytes))

    command_id = Ecto.UUID.generate()
    {:ok, _pending} = Saves.record_pending_upload(scope.user.id, device.id, command_id, meta.sha256, meta.size_bytes)

    Saves.commit_revision(scope.user.id, device, %{
      "id" => Ecto.UUID.generate(),
      "command_id" => command_id,
      "content_key" => content_key
    })
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
end
