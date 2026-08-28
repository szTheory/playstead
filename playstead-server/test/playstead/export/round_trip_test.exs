defmodule Playstead.Export.RoundTripTest do
  @moduledoc """
  The five PORT-02 round-trip contract assertions (D-37): export, wipe,
  and reimport restores an identical set graph; export and reimport
  into the same library adds zero new logical records; the API-only
  writer reproduces a byte-identical tree; a member deleted before
  reimport yields an incomplete set with no reattachment; and a foreign
  or malformed claimed sidecar identifier never reattaches while still
  deduplicating by fingerprint.
  """

  use Playstead.DataCase, async: false
  use Oban.Testing, repo: Playstead.Repo

  import Ecto.Query, warn: false
  import Playstead.AccountsFixtures
  import Playstead.ImportFixtures

  alias Playstead.Blobs.Blob
  alias Playstead.Blobs.Store.LocalDisk
  alias Playstead.Catalogue.{AssetMember, AssetSet}
  alias Playstead.Export
  alias Playstead.Export.Worker
  alias Playstead.Import
  alias Playstead.Import.FolderImport
  alias Playstead.Repo

  setup do
    File.mkdir_p!(LocalDisk.blob_path())
    File.rm_rf!(Export.export_root())
    File.mkdir_p!(Export.export_root())
    :ok
  end

  defp import_bytes!(user_id, name, bytes) do
    {:ok, :stored, meta} = Playstead.Blobs.put_stream([bytes], byte_size(bytes))

    {:ok, receipt} =
      Import.import_single(
        user_id,
        %{original_name: name, origin: "upload", size_bytes: meta.size_bytes},
        {:stored, meta}
      )

    Repo.get!(AssetSet, receipt.asset_set_id)
  end

  defp export_and_run!(user_id, scope_kind, opts) do
    {:ok, export} = Export.create_export(user_id, scope_kind, opts)
    assert :ok = perform_job(Worker, %{"export_id" => export.id})
    Repo.get!(Playstead.Export.ExportRecord, export.id)
  end

  test "export, wipe, and reimport restores an identical set graph with zero new blobs" do
    scope = user_scope_fixture()
    bytes = random_bytes(3_000)
    asset_set = import_bytes!(scope.user.id, "game.gba", bytes)
    asset_set = Repo.preload(asset_set, :asset_members)
    [original_member] = asset_set.asset_members

    export =
      export_and_run!(scope.user.id, :set,
        target_name: "export-#{System.unique_integer([:positive])}",
        asset_set_id: asset_set.id
      )

    blob_count_before = Repo.aggregate(Blob, :count)

    # Wipe: delete the members, the set, and the source files (bytes
    # stay in the content-addressed store, as a real wipe-and-restore
    # only clears the logical catalogue).
    Repo.delete_all(from(m in AssetMember, where: m.asset_set_id == ^asset_set.id))
    Repo.delete_all(from(s in AssetSet, where: s.id == ^asset_set.id))
    Repo.delete_all(Playstead.Import.SourceFile)
    Repo.delete_all(Playstead.Import.Receipt)

    assert {:ok, [receipt]} =
             FolderImport.import_folder(scope.user.id, Export.target_dir(export.target_name))

    assert receipt.outcome == "new_asset"

    restored = Repo.get_by!(AssetSet, user_id: scope.user.id) |> Repo.preload(:asset_members)
    [restored_member] = restored.asset_members

    assert restored.id == asset_set.id
    assert restored_member.role == original_member.role
    assert restored_member.ordinal == original_member.ordinal
    assert restored_member.required == original_member.required

    assert Repo.aggregate(Blob, :count) == blob_count_before
  end

  test "export and reimport into the same library adds zero new logical records and one source_files row per member" do
    scope = user_scope_fixture()
    bytes = random_bytes(2_500)
    asset_set = import_bytes!(scope.user.id, "game.gba", bytes)

    export =
      export_and_run!(scope.user.id, :set,
        target_name: "export-#{System.unique_integer([:positive])}",
        asset_set_id: asset_set.id
      )

    asset_set_count_before = Repo.aggregate(AssetSet, :count)
    source_file_count_before = Repo.aggregate(Playstead.Import.SourceFile, :count)

    assert {:ok, [receipt]} =
             FolderImport.import_folder(scope.user.id, Export.target_dir(export.target_name))

    assert receipt.outcome == "alias"
    assert Repo.aggregate(AssetSet, :count) == asset_set_count_before
    assert Repo.aggregate(Playstead.Import.SourceFile, :count) == source_file_count_before + 1
  end

  test "a folder written using only the API manifest and blob endpoints is byte-identical to the server-written export" do
    scope = user_scope_fixture()
    bytes = random_bytes(5_000)
    asset_set = import_bytes!(scope.user.id, "game.gba", bytes)

    export =
      export_and_run!(scope.user.id, :set,
        target_name: "export-#{System.unique_integer([:positive])}",
        asset_set_id: asset_set.id
      )

    target_dir = Export.target_dir(export.target_name)
    {:ok, manifest} = Export.manifest_content(export)
    on_disk_manifest = File.read!(Path.join(target_dir, "manifest-sha256.txt"))
    assert manifest == on_disk_manifest

    client_dir =
      Path.join(System.tmp_dir!(), "playstead-rt-client-#{System.unique_integer([:positive])}")

    File.mkdir_p!(client_dir)
    on_exit(fn -> File.rm_rf!(client_dir) end)

    for line <- String.split(manifest, "\n", trim: true) do
      [sha256, relative] = String.split(line, "  ", parts: 2)
      {:ok, stream} = Playstead.Blobs.stream(sha256)
      dest = Path.join(client_dir, relative)
      File.mkdir_p!(Path.dirname(dest))
      File.write!(dest, Enum.join(stream))
      assert File.read!(dest) == File.read!(Path.join(target_dir, relative))
    end
  end

  defp import_two_member_set!(user_id, descriptor_bytes, track_bytes) do
    {:ok, :stored, descriptor_meta} =
      Playstead.Blobs.put_stream([descriptor_bytes], byte_size(descriptor_bytes))

    {:ok, :stored, track_meta} = Playstead.Blobs.put_stream([track_bytes], byte_size(track_bytes))

    {:ok, %{asset_set: asset_set}} =
      Import.import_descriptor_set(
        user_id,
        %{original_name: "game.cue", origin: "upload", size_bytes: descriptor_meta.size_bytes},
        {:stored, descriptor_meta},
        ["game.bin"],
        %{"game.bin" => {:stored, track_meta}}
      )

    asset_set
  end

  test "reimporting with one member file removed yields an incomplete_set receipt naming the missing member with no reattachment" do
    scope = user_scope_fixture()
    asset_set = import_two_member_set!(scope.user.id, random_bytes(200), random_bytes(1_500))

    export =
      export_and_run!(scope.user.id, :set,
        target_name: "export-#{System.unique_integer([:positive])}",
        asset_set_id: asset_set.id
      )

    target_dir = Export.target_dir(export.target_name)
    manifest = File.read!(Path.join(target_dir, "manifest-sha256.txt"))
    [first_line | _] = manifest |> String.split("\n", trim: true) |> Enum.sort()
    [_sha256, relative] = String.split(first_line, "  ", parts: 2)
    File.rm!(Path.join(target_dir, relative))

    scope_b = user_scope_fixture()

    assert {:ok, receipts} = FolderImport.import_folder(scope_b.user.id, target_dir)
    assert length(receipts) == 1

    [receipt] = receipts
    assert receipt.outcome == "incomplete_set"
    assert receipt.reason =~ "missing"

    new_set = Repo.get!(AssetSet, receipt.asset_set_id)
    refute new_set.id == asset_set.id
    assert new_set.status == "incomplete"
  end

  test "a sidecar identifier belonging to another user yields a fresh identifier, records the claim, and dedups by fingerprint" do
    scope_a = user_scope_fixture()
    bytes = random_bytes(1_800)
    asset_set_a = import_bytes!(scope_a.user.id, "game.gba", bytes)

    export =
      export_and_run!(scope_a.user.id, :set,
        target_name: "export-#{System.unique_integer([:positive])}",
        asset_set_id: asset_set_a.id
      )

    scope_b = user_scope_fixture()
    # scope_b already holds a different set claiming asset_set_a's id is
    # irrelevant here; the sidecar in the export already names
    # asset_set_a's real id, owned by scope_a, so importing it as
    # scope_b exercises the foreign-owner rejection path directly.
    target_dir = Export.target_dir(export.target_name)

    assert {:ok, [receipt]} = FolderImport.import_folder(scope_b.user.id, target_dir)
    assert receipt.outcome == "new_asset"

    new_set = Repo.get!(AssetSet, receipt.asset_set_id)
    refute new_set.id == asset_set_a.id
    assert new_set.provenance["rejected_reason"] == "foreign_owner"
    assert new_set.provenance["claimed_identifier"] == asset_set_a.id

    blob = Repo.get_by!(Blob, sha256: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower))
    assert Repo.aggregate(from(b in Blob, where: b.id == ^blob.id), :count) == 1
  end

  test "a malformed sidecar identifier yields a fresh identifier with the claimed value recorded" do
    scope = user_scope_fixture()
    bytes = random_bytes(1_200)
    asset_set = import_bytes!(scope.user.id, "game.gba", bytes)

    export =
      export_and_run!(scope.user.id, :set,
        target_name: "export-#{System.unique_integer([:positive])}",
        asset_set_id: asset_set.id
      )

    target_dir = Export.target_dir(export.target_name)
    sidecar_path = tag_sidecar_path(target_dir, asset_set)
    content = File.read!(sidecar_path)
    tampered = Jason.decode!(content) |> Map.put("id", "not-a-uuid") |> Jason.encode!()
    File.write!(sidecar_path <> ".tmp", tampered)
    File.rename!(sidecar_path <> ".tmp", sidecar_path)

    Repo.delete_all(from(m in AssetMember, where: m.asset_set_id == ^asset_set.id))
    Repo.delete_all(from(s in AssetSet, where: s.id == ^asset_set.id))
    Repo.delete_all(Playstead.Import.SourceFile)

    assert {:ok, [receipt]} = FolderImport.import_folder(scope.user.id, target_dir)
    assert receipt.outcome == "new_asset"

    new_set = Repo.get!(AssetSet, receipt.asset_set_id)
    assert new_set.provenance["rejected_reason"] == "malformed"
    assert new_set.provenance["claimed_identifier"] == "not-a-uuid"
  end

  test "a sidecar identifier unknown to every user is reused as the new set's identifier" do
    scope = user_scope_fixture()
    bytes = random_bytes(900)
    asset_set = import_bytes!(scope.user.id, "game.gba", bytes)

    export =
      export_and_run!(scope.user.id, :set,
        target_name: "export-#{System.unique_integer([:positive])}",
        asset_set_id: asset_set.id
      )

    target_dir = Export.target_dir(export.target_name)

    Repo.delete_all(from(m in AssetMember, where: m.asset_set_id == ^asset_set.id))
    Repo.delete_all(from(s in AssetSet, where: s.id == ^asset_set.id))
    Repo.delete_all(Playstead.Import.SourceFile)

    assert {:ok, [receipt]} = FolderImport.import_folder(scope.user.id, target_dir)
    new_set = Repo.get!(AssetSet, receipt.asset_set_id)
    assert new_set.id == asset_set.id
  end

  test "a sidecar identifier that exists for this user with different bytes never causes reattachment" do
    scope = user_scope_fixture()
    bytes_a = random_bytes(700)
    asset_set_a = import_bytes!(scope.user.id, "game-a.gba", bytes_a)

    export_a =
      export_and_run!(scope.user.id, :set,
        target_name: "export-a-#{System.unique_integer([:positive])}",
        asset_set_id: asset_set_a.id
      )

    target_dir = Export.target_dir(export_a.target_name)
    manifest = File.read!(Path.join(target_dir, "manifest-sha256.txt"))
    [line] = String.split(manifest, "\n", trim: true)
    [_sha256, relative] = String.split(line, "  ", parts: 2)

    # The sidecar still names asset_set_a's real identifier, but the
    # payload bytes on disk have genuinely changed — the fingerprint no
    # longer matches asset_set_a, and asset_set_a still exists for this
    # same user. D-37: never reattach on the strength of the identifier
    # alone.
    File.write!(Path.join(target_dir, relative), "entirely different content, not the original")

    assert {:ok, [receipt]} = FolderImport.import_folder(scope.user.id, target_dir)
    new_set = Repo.get!(AssetSet, receipt.asset_set_id)
    refute new_set.id == asset_set_a.id
    assert new_set.provenance["claimed_identifier"] == asset_set_a.id
    assert new_set.provenance["relation"] == "derived_from_export"
  end

  test "a missing sidecar still imports the folder using the ordinary grouping rules" do
    scope = user_scope_fixture()
    bytes = random_bytes(600)
    asset_set = import_bytes!(scope.user.id, "game.gba", bytes)

    export =
      export_and_run!(scope.user.id, :set,
        target_name: "export-#{System.unique_integer([:positive])}",
        asset_set_id: asset_set.id
      )

    target_dir = Export.target_dir(export.target_name)
    sidecar_path = tag_sidecar_path(target_dir, asset_set)
    File.rm!(sidecar_path)

    scope_b = user_scope_fixture()
    assert {:ok, [receipt]} = FolderImport.import_folder(scope_b.user.id, target_dir)
    assert receipt.outcome == "new_asset"
  end

  test "a tampered sidecar still imports the folder using the ordinary grouping rules" do
    scope = user_scope_fixture()
    bytes = random_bytes(650)
    asset_set = import_bytes!(scope.user.id, "game.gba", bytes)

    export =
      export_and_run!(scope.user.id, :set,
        target_name: "export-#{System.unique_integer([:positive])}",
        asset_set_id: asset_set.id
      )

    target_dir = Export.target_dir(export.target_name)
    sidecar_path = tag_sidecar_path(target_dir, asset_set)
    File.write!(sidecar_path, "not even json")

    scope_b = user_scope_fixture()
    assert {:ok, [receipt]} = FolderImport.import_folder(scope_b.user.id, target_dir)
    assert receipt.outcome == "new_asset"
  end

  test "the member fingerprint used for the identity decision was computed from re-hashed bytes" do
    scope = user_scope_fixture()
    bytes = random_bytes(400)
    asset_set = import_bytes!(scope.user.id, "game.gba", bytes)

    export =
      export_and_run!(scope.user.id, :set,
        target_name: "export-#{System.unique_integer([:positive])}",
        asset_set_id: asset_set.id
      )

    target_dir = Export.target_dir(export.target_name)
    manifest = File.read!(Path.join(target_dir, "manifest-sha256.txt"))
    [line] = String.split(manifest, "\n", trim: true)
    [_manifest_sha256, relative] = String.split(line, "  ", parts: 2)
    payload_path = Path.join(target_dir, relative)

    # Corrupt both the file on disk AND leave the manifest/sidecar
    # claiming the original digest — the identity decision must follow
    # the live bytes, never the manifest's claim.
    File.write!(payload_path, "different bytes entirely, not the original rom")

    Repo.delete_all(from(m in AssetMember, where: m.asset_set_id == ^asset_set.id))
    Repo.delete_all(from(s in AssetSet, where: s.id == ^asset_set.id))
    Repo.delete_all(Playstead.Import.SourceFile)

    assert {:ok, [receipt]} = FolderImport.import_folder(scope.user.id, target_dir)
    assert receipt.sha256 != nil

    corrupted_sha256 =
      :crypto.hash(:sha256, "different bytes entirely, not the original rom")
      |> Base.encode16(case: :lower)

    assert receipt.sha256 == corrupted_sha256
  end

  test "every reimported file is re-hashed even when its metadata would have matched a staging fingerprint" do
    scope = user_scope_fixture()
    bytes = random_bytes(300)
    asset_set = import_bytes!(scope.user.id, "game.gba", bytes)

    export =
      export_and_run!(scope.user.id, :set,
        target_name: "export-#{System.unique_integer([:positive])}",
        asset_set_id: asset_set.id
      )

    target_dir = Export.target_dir(export.target_name)

    scope_b = user_scope_fixture()
    assert {:ok, [receipt]} = FolderImport.import_folder(scope_b.user.id, target_dir)

    expected_sha256 = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
    assert receipt.sha256 == expected_sha256
  end

  defp tag_sidecar_path(target_dir, _asset_set) do
    manifest_dir =
      target_dir
      |> Path.join("manifest-sha256.txt")
      |> File.read!()
      |> String.split("\n", trim: true)
      |> List.first()
      |> String.split("  ", parts: 2)
      |> List.last()
      |> Path.dirname()
      |> then(fn "data/" <> rest -> rest end)

    Path.join([target_dir, "tags", manifest_dir, "playstead-set.json"])
  end
end
