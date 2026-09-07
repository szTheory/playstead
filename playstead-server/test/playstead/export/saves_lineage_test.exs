defmodule Playstead.Export.SavesLineageTest do
  @moduledoc """
  Plan 04-21 task 2: stable branch keys (D-58), honest kind mapping,
  and missing bytes.
  """

  use Playstead.DataCase, async: false
  use Oban.Testing, repo: Playstead.Repo

  import Playstead.AccountsFixtures
  import Playstead.ImportFixtures
  import Playstead.PairingFixtures

  alias Playstead.Blobs
  alias Playstead.Blobs.Store.LocalDisk
  alias Playstead.Export
  alias Playstead.Export.{ExportRecord, SavesLineage, Verifier, Worker}
  alias Playstead.Repo
  alias Playstead.Saves

  setup do
    File.mkdir_p!(LocalDisk.blob_path())
    File.rm_rf!(Export.export_root())
    File.mkdir_p!(Export.export_root())
    :ok
  end

  defp ts(offset_seconds),
    do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(offset_seconds, :second)

  defp revision(id, parent_id, offset),
    do: %{id: id, parent_revision_id: parent_id, recorded_at: ts(offset)}

  describe "SavesLineage.branch_keys/1 (pure)" do
    test "is pure by inspection -- no Saves, Repo, filesystem, or clock reference" do
      source = File.read!(Path.join(__DIR__, "../../../lib/playstead/export/saves_lineage.ex"))
      refute source =~ ~r/Playstead\.Saves|Repo\.|File\.|DateTime\.utc_now/
    end

    test "a linear history yields all-nil branch keys" do
      root = Ecto.UUID.generate()
      child = Ecto.UUID.generate()
      grandchild = Ecto.UUID.generate()

      revisions = [
        revision(root, nil, 0),
        revision(child, root, 1),
        revision(grandchild, child, 2)
      ]

      keys = SavesLineage.branch_keys(revisions)

      assert keys[root] == nil
      assert keys[child] == nil
      assert keys[grandchild] == nil
    end

    test "a two-way fork yields two distinct non-nil keys, inherited by every descendant of each side" do
      root = Ecto.UUID.generate()
      branch_a = Ecto.UUID.generate()
      branch_a_child = Ecto.UUID.generate()
      branch_b = Ecto.UUID.generate()

      revisions = [
        revision(root, nil, 0),
        revision(branch_a, root, 1),
        revision(branch_a_child, branch_a, 2),
        revision(branch_b, root, 1)
      ]

      keys = SavesLineage.branch_keys(revisions)

      # Shared pre-fork ancestor keeps nil.
      assert keys[root] == nil

      # Each side's fork root is its own id, and they differ.
      assert keys[branch_a] == branch_a
      assert keys[branch_b] == branch_b
      refute keys[branch_a] == keys[branch_b]

      # A descendant of branch_a inherits branch_a's key.
      assert keys[branch_a_child] == branch_a
    end

    test "running branch_keys/1 twice on the same input returns an equal map" do
      root = Ecto.UUID.generate()
      branch_a = Ecto.UUID.generate()
      branch_b = Ecto.UUID.generate()

      revisions = [
        revision(root, nil, 0),
        revision(branch_a, root, 1),
        revision(branch_b, root, 1)
      ]

      assert SavesLineage.branch_keys(revisions) == SavesLineage.branch_keys(revisions)
    end

    test "a cycle in parent_revision_id degrades to nil rather than looping" do
      a = Ecto.UUID.generate()
      b = Ecto.UUID.generate()

      revisions = [revision(a, b, 0), revision(b, a, 1)]

      keys = SavesLineage.branch_keys(revisions)
      assert keys[a] == nil
      assert keys[b] == nil
    end
  end

  describe "integration: real fork through the export pipeline" do
    defp user_with_asset do
      scope = user_scope_fixture()
      rom_bytes = random_bytes(1024)
      {:ok, :stored, meta} = Blobs.put_stream([rom_bytes], byte_size(rom_bytes))

      {:ok, receipt} =
        Playstead.Import.import_single(
          scope.user.id,
          %{original_name: "game.gba", origin: "upload", size_bytes: meta.size_bytes},
          {:stored, meta}
        )

      asset_set = Export.fetch_asset_set(scope.user.id, receipt.asset_set_id)
      {scope, asset_set, meta.sha256}
    end

    defp commit_save!(scope, device, content_key, bytes, extra_attrs \\ %{}) do
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
          %{
            "id" => Ecto.UUID.generate(),
            "command_id" => command_id,
            "content_key" => content_key
          },
          extra_attrs
        )

      Saves.commit_revision(scope.user.id, device, attrs)
    end

    defp create_and_run!(user_id, asset_set_id, target_name) do
      {:ok, export} =
        Export.create_export(user_id, :set, target_name: target_name, asset_set_id: asset_set_id)

      assert :ok = perform_job(Worker, %{"export_id" => export.id})
      Repo.get!(ExportRecord, export.id)
    end

    test "two sides of a real fork export under stable, distinct branch letters, and re-planning is stable" do
      {scope, asset_set, rom_sha256} = user_with_asset()
      %{device: device} = device_fixture(scope)

      {:ok, root} = commit_save!(scope, device, rom_sha256, random_bytes(64))

      {:ok, _branch_a} =
        commit_save!(scope, device, rom_sha256, random_bytes(64), %{
          "parent_revision_id" => root.id
        })

      {:ok, _branch_b} =
        commit_save!(scope, device, rom_sha256, random_bytes(64), %{
          "parent_revision_id" => root.id
        })

      export1 =
        create_and_run!(
          scope.user.id,
          asset_set.id,
          "export-#{System.unique_integer([:positive])}"
        )

      export2 =
        create_and_run!(
          scope.user.id,
          asset_set.id,
          "export-#{System.unique_integer([:positive])}"
        )

      assert export1.status == "verified"
      assert export2.status == "verified"

      files1 =
        Export.target_dir(export1.target_name)
        |> Path.join("data/*/*/saves/revisions/*")
        |> Path.wildcard()
        |> Enum.map(&Path.basename/1)
        |> Enum.sort()

      files2 =
        Export.target_dir(export2.target_name)
        |> Path.join("data/*/*/saves/revisions/*")
        |> Path.wildcard()
        |> Enum.map(&Path.basename/1)
        |> Enum.sort()

      assert files1 == files2
      assert length(files1) == 3

      # The two branch heads got two distinct branch letters embedded
      # in their filenames (the root has none, unlettered).
      lettered = Enum.filter(files1, &(&1 =~ ~r/^\d{6}-[a-z]-/))
      assert length(lettered) == 2

      letters =
        Enum.map(lettered, fn f ->
          [letter] = Regex.run(~r/^\d{6}-([a-z])-/, f, capture: :all_but_first)
          letter
        end)

      assert length(Enum.uniq(letters)) == 2
    end

    test "a battery line with a single linear head gets a saves/<stem>.sav drop-in copy" do
      {scope, asset_set, rom_sha256} = user_with_asset()
      %{device: device} = device_fixture(scope)

      {:ok, _revision} = commit_save!(scope, device, rom_sha256, random_bytes(64))

      export =
        create_and_run!(
          scope.user.id,
          asset_set.id,
          "export-#{System.unique_integer([:positive])}"
        )

      assert export.status == "verified"

      drop_in =
        Export.target_dir(export.target_name)
        |> Path.join("data/*/*/saves/*.sav")
        |> Path.wildcard()

      assert drop_in != []
    end

    test "a diverged line (multiple heads) gets no drop-in copy" do
      {scope, asset_set, rom_sha256} = user_with_asset()
      %{device: device} = device_fixture(scope)

      {:ok, root} = commit_save!(scope, device, rom_sha256, random_bytes(64))

      {:ok, _a} =
        commit_save!(scope, device, rom_sha256, random_bytes(64), %{
          "parent_revision_id" => root.id
        })

      {:ok, _b} =
        commit_save!(scope, device, rom_sha256, random_bytes(64), %{
          "parent_revision_id" => root.id
        })

      export =
        create_and_run!(
          scope.user.id,
          asset_set.id,
          "export-#{System.unique_integer([:positive])}"
        )

      assert export.status == "verified"

      drop_in =
        Export.target_dir(export.target_name)
        |> Path.join("data/*/*/saves/*.sav")
        |> Path.wildcard()

      assert drop_in == []
    end

    test "a revision whose blob is absent from the store produces no payload file, no manifest line, and a bag that still verifies" do
      {scope, asset_set, rom_sha256} = user_with_asset()
      %{device: device} = device_fixture(scope)

      missing_bytes = random_bytes(64)
      {:ok, missing_revision} = commit_save!(scope, device, rom_sha256, missing_bytes)

      # Delete the blob after committing the revision, so the DB knows
      # about a revision whose bytes are no longer on this server.
      LocalDisk.blob_path()
      |> LocalDisk.object_path(missing_revision.blob_sha256)
      |> File.rm()

      target_name = "export-#{System.unique_integer([:positive])}"
      export = create_and_run!(scope.user.id, asset_set.id, target_name)

      assert export.status == "verified"

      target_dir = Export.target_dir(target_name)

      revision_files =
        target_dir
        |> Path.join("data/*/*/saves/revisions/*")
        |> Path.wildcard()

      assert revision_files == []

      manifest_content = File.read!(Path.join(target_dir, "manifest-sha256.txt"))
      refute manifest_content =~ missing_revision.blob_sha256

      assert {:ok, _} = Verifier.verify(target_dir)
    end
  end
end
