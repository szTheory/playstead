defmodule Playstead.SavesLineageScopingTest do
  @moduledoc """
  Gap closure for CR-01 (04-REVIEW-server.md): a submitted
  `parent_revision_id` must be scoped to the save line being committed
  to, not merely to the calling user, and the database must refuse a
  cross-save-line parent link even if the application forgot to check.
  """

  use Playstead.DataCase, async: true

  import Playstead.AccountsFixtures
  import Playstead.PairingFixtures

  alias Playstead.Blobs
  alias Playstead.Repo
  alias Playstead.Saves
  alias Playstead.Saves.Revision

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

  describe "commit_revision/3 refuses a cross-save-line parent (CR-01)" do
    test "a parent belonging to a different save line for the SAME user is refused with save_parent_unknown" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)

      # Two different content_keys => two different save lines for the
      # same user (D-10 identity tuple).
      {:ok, line_a_revision} =
        commit!(scope, device, content_key(), :crypto.strong_rand_bytes(64))

      assert {:error, {:save_parent_unknown, _detail}} =
               commit!(scope, device, content_key(), :crypto.strong_rand_bytes(64),
                 parent_revision_id: line_a_revision.id
               )
    end

    test "a same-save-line parent still succeeds exactly as before" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      key = content_key()

      {:ok, root} = commit!(scope, device, key, :crypto.strong_rand_bytes(64))

      assert {:ok, child} =
               commit!(scope, device, key, :crypto.strong_rand_bytes(64),
                 parent_revision_id: root.id
               )

      assert child.parent_revision_id == root.id
      assert child.save_line_id == root.save_line_id
    end

    test "a nil parent still succeeds -- a first revision on a line has no parent" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)

      assert {:ok, revision} =
               commit!(scope, device, content_key(), :crypto.strong_rand_bytes(64))

      assert is_nil(revision.parent_revision_id)
    end

    test "a parent belonging to a different USER remains refused, as it is today" do
      scope_a = user_scope_fixture()
      %{device: device_a} = device_fixture(scope_a)

      {:ok, other_users_revision} =
        commit!(scope_a, device_a, content_key(), :crypto.strong_rand_bytes(64))

      scope_b = user_scope_fixture()
      %{device: device_b} = device_fixture(scope_b)

      assert {:error, {:save_parent_unknown, _detail}} =
               commit!(scope_b, device_b, content_key(), :crypto.strong_rand_bytes(64),
                 parent_revision_id: other_users_revision.id
               )
    end

    test "a direct Repo.insert bypassing the context is rejected by the DATABASE constraint" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)

      {:ok, line_a_revision} =
        commit!(scope, device, content_key(), :crypto.strong_rand_bytes(64))

      {:ok, line_b_revision} =
        commit!(scope, device, content_key(), :crypto.strong_rand_bytes(64))

      changeset =
        Revision.create_changeset(%Revision{}, %{
          id: Ecto.UUID.generate(),
          user_id: scope.user.id,
          save_line_id: line_b_revision.save_line_id,
          # line_a_revision belongs to a DIFFERENT save line than
          # line_b_revision -- the composite FK on
          # (parent_revision_id, save_line_id) must reject this insert
          # even though the application-level check in
          # `Saves.resolve_parent/2` is entirely bypassed here.
          parent_revision_id: line_a_revision.id,
          blob_sha256: line_b_revision.blob_sha256,
          size_bytes: line_b_revision.size_bytes,
          recorded_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert %{parent_revision_id: ["does not exist"]} = errors_on(changeset)
    end

    test "a same-save-line direct Repo.insert is accepted by the database constraint" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      key = content_key()

      {:ok, root} = commit!(scope, device, key, :crypto.strong_rand_bytes(64))

      changeset =
        Revision.create_changeset(%Revision{}, %{
          id: Ecto.UUID.generate(),
          user_id: scope.user.id,
          save_line_id: root.save_line_id,
          parent_revision_id: root.id,
          blob_sha256: root.blob_sha256,
          size_bytes: root.size_bytes,
          recorded_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        })

      assert {:ok, revision} = Repo.insert(changeset)
      assert revision.parent_revision_id == root.id
    end
  end

  describe "the refusal reuses a registered save problem code" do
    test "save_parent_unknown is registered in PlaysteadWeb.ErrorCodes" do
      assert Map.has_key?(PlaysteadWeb.ErrorCodes.registry(), :save_parent_unknown)
      assert PlaysteadWeb.ErrorCodes.status_for(:save_parent_unknown) == 409
    end
  end
end
