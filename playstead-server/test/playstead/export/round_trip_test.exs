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
  import Playstead.PairingFixtures

  alias Playstead.Blobs
  alias Playstead.Blobs.Blob
  alias Playstead.Blobs.Store.LocalDisk
  alias Playstead.Catalogue.{AssetMember, AssetSet}
  alias Playstead.Export
  alias Playstead.Export.{ExportRecord, Verifier, Worker}
  alias Playstead.Import
  alias Playstead.Import.FolderImport
  alias Playstead.Repo
  alias Playstead.Saves

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

  # Plan 04-21 task 3: determinism and re-export stability against the
  # real saves loader now that real save-revision data flows through
  # the export pipeline (WINDOWS #30 / PORT-01).

  # Like `import_bytes!/3`, but tolerates the blob already existing in
  # the content-addressed store (e.g. a second user importing the same
  # ROM bytes another user already imported).
  defp import_bytes_any!(user_id, name, bytes) do
    {:ok, _status, meta} = Playstead.Blobs.put_stream([bytes], byte_size(bytes))

    {:ok, receipt} =
      Import.import_single(
        user_id,
        %{original_name: name, origin: "upload", size_bytes: meta.size_bytes},
        {:stored, meta}
      )

    Repo.get!(AssetSet, receipt.asset_set_id)
  end

  defp commit_save!(scope, device, content_key, bytes, extra_attrs \\ %{}) do
    {:ok, _status, meta} = Blobs.put_stream([bytes], byte_size(bytes))
    command_id = Ecto.UUID.generate()

    {:ok, _pending} =
      Saves.record_pending_upload(scope.user.id, device.id, command_id, meta.sha256, meta.size_bytes)

    attrs =
      Map.merge(
        %{"id" => Ecto.UUID.generate(), "command_id" => command_id, "content_key" => content_key},
        extra_attrs
      )

    Saves.commit_revision(scope.user.id, device, attrs)
  end

  defp saves_revision_files(target_name) do
    Export.target_dir(target_name)
    |> Path.join("data/*/*/saves/revisions/*")
    |> Path.wildcard()
    |> Enum.map(&Path.basename/1)
    |> Enum.sort()
  end

  test "an appended revision never renumbers or renames a pre-existing revision's exported file (D-59)" do
    scope = user_scope_fixture()
    bytes = random_bytes(1_024)
    asset_set = import_bytes!(scope.user.id, "game.gba", bytes)
    rom_sha256 = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
    %{device: device} = device_fixture(scope)

    {:ok, revision_1} = commit_save!(scope, device, rom_sha256, random_bytes(64))

    {:ok, _revision_2} =
      commit_save!(scope, device, rom_sha256, random_bytes(64), %{"parent_revision_id" => revision_1.id})

    target_name_before = "export-#{System.unique_integer([:positive])}"
    export_and_run!(scope.user.id, :set, target_name: target_name_before, asset_set_id: asset_set.id)
    files_before = saves_revision_files(target_name_before)
    assert length(files_before) == 2

    revision_2 = Repo.get_by!(Playstead.Saves.Revision, save_line_id: revision_1.save_line_id, parent_revision_id: revision_1.id)

    {:ok, _revision_3} =
      commit_save!(scope, device, rom_sha256, random_bytes(64), %{"parent_revision_id" => revision_2.id})

    target_name_after = "export-#{System.unique_integer([:positive])}"
    export_and_run!(scope.user.id, :set, target_name: target_name_after, asset_set_id: asset_set.id)
    files_after = saves_revision_files(target_name_after)
    assert length(files_after) == 3

    # The two pre-existing revisions' filenames -- exact string
    # equality on seq AND digest -- are unchanged by the append. A
    # shifted or reused seq is the specific defect this asserts against.
    assert Enum.take(files_after, 2) == files_before
  end

  test "two revisions sharing one recorded_at keep identical seq and filenames across two independent exports (D-59)" do
    scope = user_scope_fixture()
    bytes = random_bytes(1_024)
    asset_set = import_bytes!(scope.user.id, "game.gba", bytes)
    rom_sha256 = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
    %{device: device} = device_fixture(scope)

    {:ok, base_revision} = commit_save!(scope, device, rom_sha256, random_bytes(64))

    # Commit the lexically-GREATER id first -- with no id tiebreaker,
    # Postgres has nothing to sort the tied pair by and returns them
    # in whatever order the scan produced, which is the insertion
    # order deliberately inverted here.
    [lower_id, greater_id] = Enum.sort([Ecto.UUID.generate(), Ecto.UUID.generate()])

    {:ok, greater_child} =
      commit_save!(scope, device, rom_sha256, random_bytes(64), %{
        "id" => greater_id,
        "parent_revision_id" => base_revision.id
      })

    {:ok, lower_child} =
      commit_save!(scope, device, rom_sha256, random_bytes(64), %{
        "id" => lower_id,
        "parent_revision_id" => base_revision.id
      })

    tied_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    {2, nil} =
      Repo.update_all(
        from(r in Playstead.Saves.Revision, where: r.id in [^greater_child.id, ^lower_child.id]),
        set: [recorded_at: tied_at]
      )

    reloaded_greater = Repo.get!(Playstead.Saves.Revision, greater_child.id)
    reloaded_lower = Repo.get!(Playstead.Saves.Revision, lower_child.id)

    # The tie must be REAL before anything about ordering is asserted
    # -- otherwise the whole test could pass vacuously because the tie
    # was never constructed.
    assert DateTime.compare(reloaded_greater.recorded_at, reloaded_lower.recorded_at) == :eq

    target_name_1 = "export-tie-1-#{System.unique_integer([:positive])}"
    target_name_2 = "export-tie-2-#{System.unique_integer([:positive])}"

    export_and_run!(scope.user.id, :set, target_name: target_name_1, asset_set_id: asset_set.id)
    export_and_run!(scope.user.id, :set, target_name: target_name_2, asset_set_id: asset_set.id)

    # Two independent plan-and-write runs, not a resumed no-op over
    # the first run's directory.
    assert target_name_1 != target_name_2

    files_1 = saves_revision_files(target_name_1)
    files_2 = saves_revision_files(target_name_2)

    # A run that produced zero or one file would otherwise make the
    # list-equality assertion below trivially true.
    assert length(files_1) == 3
    assert length(files_2) == 3

    assert files_1 == files_2

    digest8 = fn revision -> String.slice(revision.blob_sha256, 0, 8) end
    lower_digest8 = digest8.(reloaded_lower)
    greater_digest8 = digest8.(reloaded_greater)

    lower_filename_1 = Enum.find(files_1, &String.contains?(&1, lower_digest8))
    lower_filename_2 = Enum.find(files_2, &String.contains?(&1, lower_digest8))
    greater_filename_1 = Enum.find(files_1, &String.contains?(&1, greater_digest8))
    greater_filename_2 = Enum.find(files_2, &String.contains?(&1, greater_digest8))

    refute is_nil(lower_filename_1)
    refute is_nil(greater_filename_1)

    # List equality of files_1/files_2 alone would still pass if both
    # runs happened to be wrong in the same way -- pinning the
    # lower-id-to-lower-seq mapping is what actually asserts the
    # tiebreaker rather than mere run-to-run repeatability.
    assert lower_filename_1 == lower_filename_2
    assert greater_filename_1 == greater_filename_2
    assert String.slice(lower_filename_1, 0, 6) < String.slice(greater_filename_1, 0, 6)
  end

  test "re-running the export worker twice against one target leaves every payload byte-identical and still verifies" do
    scope = user_scope_fixture()
    bytes = random_bytes(1_024)
    asset_set = import_bytes!(scope.user.id, "game.gba", bytes)
    rom_sha256 = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
    %{device: device} = device_fixture(scope)

    {:ok, _revision} = commit_save!(scope, device, rom_sha256, random_bytes(64))

    target_name = "export-#{System.unique_integer([:positive])}"

    {:ok, export} =
      Export.create_export(scope.user.id, :set, target_name: target_name, asset_set_id: asset_set.id)

    assert :ok = perform_job(Worker, %{"export_id" => export.id})

    target_dir = Export.target_dir(target_name)
    files_first_run = Path.wildcard(Path.join(target_dir, "data/**/*")) |> Enum.reject(&File.dir?/1)
    contents_first_run = Map.new(files_first_run, &{&1, File.read!(&1)})

    assert :ok = perform_job(Worker, %{"export_id" => export.id})

    files_second_run = Path.wildcard(Path.join(target_dir, "data/**/*")) |> Enum.reject(&File.dir?/1)
    contents_second_run = Map.new(files_second_run, &{&1, File.read!(&1)})

    assert contents_first_run == contents_second_run

    reverified = Repo.get!(ExportRecord, export.id)
    assert {:ok, _} = Verifier.verify(Export.target_dir(reverified.target_name))
  end

  test "a second user sharing the same content_key never sees the first user's save bytes (T-04-21-01)" do
    scope_a = user_scope_fixture()
    scope_b = user_scope_fixture()
    bytes = random_bytes(1_024)
    rom_sha256 = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

    asset_set_a = import_bytes!(scope_a.user.id, "game.gba", bytes)
    asset_set_b = import_bytes_any!(scope_b.user.id, "game.gba", bytes)

    %{device: device_a} = device_fixture(scope_a)
    %{device: device_b} = device_fixture(scope_b)

    {:ok, revision_a} = commit_save!(scope_a, device_a, rom_sha256, random_bytes(64))
    {:ok, _revision_b} = commit_save!(scope_b, device_b, rom_sha256, random_bytes(64))

    target_name_a = "export-a-#{System.unique_integer([:positive])}"
    target_name_b = "export-b-#{System.unique_integer([:positive])}"

    export_and_run!(scope_a.user.id, :set, target_name: target_name_a, asset_set_id: asset_set_a.id)
    export_and_run!(scope_b.user.id, :set, target_name: target_name_b, asset_set_id: asset_set_b.id)

    manifest_a = File.read!(Path.join(Export.target_dir(target_name_a), "manifest-sha256.txt"))
    manifest_b = File.read!(Path.join(Export.target_dir(target_name_b), "manifest-sha256.txt"))

    refute manifest_b =~ revision_a.blob_sha256
    refute manifest_a == manifest_b
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
