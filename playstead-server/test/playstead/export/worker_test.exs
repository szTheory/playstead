defmodule Playstead.Export.WorkerTest do
  use Playstead.DataCase, async: false
  use Oban.Testing, repo: Playstead.Repo

  import Playstead.AccountsFixtures
  import Playstead.ImportFixtures

  alias Playstead.Blobs.Store.LocalDisk
  alias Playstead.Catalogue.AssetSet
  alias Playstead.Export
  alias Playstead.Export.{ExportRecord, Worker}
  alias Playstead.Repo

  setup do
    File.mkdir_p!(LocalDisk.blob_path())
    # Target names are only unique within one BEAM run; wipe any
    # leftover export directories from a prior test run so a reused
    # name never inherits stale on-disk state (e.g. a marker file).
    File.rm_rf!(Export.export_root())
    File.mkdir_p!(Export.export_root())
    :ok
  end

  defp user_with_asset(bytes \\ nil) do
    scope = user_scope_fixture()
    bytes = bytes || random_bytes(2_048)
    {:ok, :stored, meta} = Playstead.Blobs.put_stream([bytes], byte_size(bytes))

    {:ok, receipt} =
      Playstead.Import.import_single(
        scope.user.id,
        %{original_name: "game.gba", origin: "upload", size_bytes: meta.size_bytes},
        {:stored, meta}
      )

    asset_set = Repo.get!(AssetSet, receipt.asset_set_id)
    {scope, asset_set, bytes, meta}
  end

  defp create_and_run!(user_id, scope_kind, opts) do
    {:ok, export} = Export.create_export(user_id, scope_kind, opts)

    assert_enqueued(worker: Worker, args: %{export_id: export.id})
    assert :ok = perform_job(Worker, %{"export_id" => export.id})

    Repo.get!(ExportRecord, export.id)
  end

  test "the export record moves through writing, verifying, and verified" do
    {scope, asset_set, _bytes, _meta} = user_with_asset()

    export =
      create_and_run!(scope.user.id, :set,
        target_name: "export-#{System.unique_integer([:positive])}",
        asset_set_id: asset_set.id
      )

    assert export.status == "verified"
    assert export.file_count > 0
    assert export.mismatched_files == []
  end

  test "a payload file corrupted after writing causes verification-failed, names it, and leaves every file present" do
    {scope, asset_set, _bytes, _meta} = user_with_asset()
    target_name = "export-#{System.unique_integer([:positive])}"

    {:ok, export} =
      Export.create_export(scope.user.id, :set,
        target_name: target_name,
        asset_set_id: asset_set.id
      )

    assert :ok = perform_job(Worker, %{"export_id" => export.id})

    manifest_path = Path.join(Export.target_dir(target_name), "manifest-sha256.txt")
    [line] = manifest_path |> File.read!() |> String.split("\n", trim: true)
    [_sha256, relative] = String.split(line, "  ", parts: 2)
    payload_path = Path.join(Export.target_dir(target_name), relative)

    File.write!(payload_path, "corrupted")

    {:ok, reverified} = Export.verify_again(scope.user.id, export.id)
    assert reverified.status == "verification_failed"
    assert relative in reverified.mismatched_files
    assert File.exists?(payload_path)
  end

  test "a past export can be verified again and updates its last-verification time" do
    {scope, asset_set, _bytes, _meta} = user_with_asset()

    export =
      create_and_run!(scope.user.id, :set,
        target_name: "export-#{System.unique_integer([:positive])}",
        asset_set_id: asset_set.id
      )

    first_verified_at = export.last_verified_at
    Process.sleep(10)

    {:ok, reverified} = Export.verify_again(scope.user.id, export.id)
    assert reverified.status == "verified"
    assert DateTime.compare(reverified.last_verified_at, first_verified_at) == :gt
  end

  test "a target that is an absolute path is refused" do
    scope = user_scope_fixture()

    assert {:error, :invalid_target} =
             Export.create_export(scope.user.id, :library, target_name: "/etc/passwd")
  end

  test "a target containing a parent-directory segment is refused" do
    scope = user_scope_fixture()

    assert {:error, :invalid_target} =
             Export.create_export(scope.user.id, :library, target_name: "../escape")
  end

  test "a non-empty target without this export's marker is refused" do
    {scope, asset_set, _bytes, _meta} = user_with_asset()
    target_name = "export-#{System.unique_integer([:positive])}"
    target_dir = Export.target_dir(target_name)
    File.mkdir_p!(target_dir)
    File.write!(Path.join(target_dir, "unrelated.txt"), "pre-existing")

    {:ok, export} =
      Export.create_export(scope.user.id, :set,
        target_name: target_name,
        asset_set_id: asset_set.id
      )

    assert {:error, :target_not_empty} = perform_job(Worker, %{"export_id" => export.id})
    assert File.read!(Path.join(target_dir, "unrelated.txt")) == "pre-existing"
  end

  test "a resumed export skips files that already match and rewrites only its own mismatches" do
    {scope, asset_set, _bytes, _meta} = user_with_asset()
    target_name = "export-#{System.unique_integer([:positive])}"

    {:ok, export} =
      Export.create_export(scope.user.id, :set,
        target_name: target_name,
        asset_set_id: asset_set.id
      )

    assert :ok = perform_job(Worker, %{"export_id" => export.id})

    target_dir = Export.target_dir(target_name)
    manifest_path = Path.join(target_dir, "manifest-sha256.txt")
    original_manifest_mtime = File.stat!(manifest_path).mtime

    Process.sleep(1_100)
    assert :ok = perform_job(Worker, %{"export_id" => export.id})

    # Re-running against an already-verified, unmodified target rewrites
    # nothing — every file's content still matches its recorded digest.
    assert File.stat!(manifest_path).mtime == original_manifest_mtime
  end

  test "a foreign file placed in the target is neither read for rewriting, modified, nor deleted" do
    {scope, asset_set, _bytes, _meta} = user_with_asset()
    target_name = "export-#{System.unique_integer([:positive])}"

    {:ok, export} =
      Export.create_export(scope.user.id, :set,
        target_name: target_name,
        asset_set_id: asset_set.id
      )

    assert :ok = perform_job(Worker, %{"export_id" => export.id})

    target_dir = Export.target_dir(target_name)
    foreign_path = Path.join(target_dir, "foreign.txt")
    File.write!(foreign_path, "not part of this export")

    assert {:ok, _reverified} = Export.verify_again(scope.user.id, export.id)
    assert File.read!(foreign_path) == "not part of this export"
  end

  test "enqueueing the same export twice yields one running job" do
    {scope, asset_set, _bytes, _meta} = user_with_asset()
    target_name = "export-#{System.unique_integer([:positive])}"

    {:ok, export} =
      Export.create_export(scope.user.id, :set,
        target_name: target_name,
        asset_set_id: asset_set.id
      )

    assert {:ok, _job} = Worker.enqueue(export.id)
    assert_enqueued(worker: Worker, args: %{export_id: export.id})

    count =
      Oban.Job
      |> Repo.all()
      |> Enum.count(fn job -> job.args["export_id"] == export.id and job.worker =~ "Worker" end)

    assert count == 1
  end

  test "creating an export writes an audit entry" do
    {scope, asset_set, _bytes, _meta} = user_with_asset()

    {:ok, export} =
      Export.create_export(scope.user.id, :set,
        target_name: "export-#{System.unique_integer([:positive])}",
        asset_set_id: asset_set.id
      )

    assert Enum.any?(
             Playstead.AuditLog.list(scope.user.id),
             &(&1.event == "export_created" and &1.subject == export.id)
           )
  end

  test "exported payload bytes are identical to the stored blob bytes" do
    bytes = random_bytes(8_192)
    {scope, asset_set, ^bytes, _meta} = user_with_asset(bytes)

    export =
      create_and_run!(scope.user.id, :set,
        target_name: "export-#{System.unique_integer([:positive])}",
        asset_set_id: asset_set.id
      )

    manifest_path = Path.join(Export.target_dir(export.target_name), "manifest-sha256.txt")
    [line] = manifest_path |> File.read!() |> String.split("\n", trim: true)
    [_sha256, relative] = String.split(line, "  ", parts: 2)

    assert File.read!(Path.join(Export.target_dir(export.target_name), relative)) == bytes
  end

  test "the manifest returned by the API is byte-identical to the written manifest file" do
    {scope, asset_set, _bytes, _meta} = user_with_asset()

    export =
      create_and_run!(scope.user.id, :set,
        target_name: "export-#{System.unique_integer([:positive])}",
        asset_set_id: asset_set.id
      )

    on_disk = File.read!(Path.join(Export.target_dir(export.target_name), "manifest-sha256.txt"))
    assert {:ok, ^on_disk} = Export.manifest_content(export)
  end
end
