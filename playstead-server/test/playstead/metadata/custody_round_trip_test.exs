defmodule Playstead.Metadata.CustodyRoundTripTest do
  use Playstead.DataCase, async: false
  use Oban.Testing, repo: Playstead.Repo

  import Playstead.AccountsFixtures
  import Playstead.CatalogueFixtures
  import Playstead.PairingFixtures

  alias Playstead.{Blobs, Metadata, Repo, Saves}
  alias Playstead.Catalogue.{AssetMember, AssetSet}
  alias Playstead.Export
  alias Playstead.Export.{ExportRecord, Worker}
  alias Playstead.Import.FolderImport
  alias Playstead.Metadata.PrivateMedia
  alias Playstead.Saves.Save

  setup do
    File.mkdir_p!(Blobs.Store.LocalDisk.blob_path())
    File.rm_rf!(Export.export_root())
    File.mkdir_p!(Export.export_root())
    :ok
  end

  test "exports authored private media originals and provenance in verified BagIt and restores them through supported import" do
    scope = user_scope_fixture()
    owner = scope.user
    asset_set = asset_set_fixture(owner.id)
    original = "authored private image caption and source\n"
    {:ok, media} = PrivateMedia.create(owner.id, asset_set.id, original, "text/plain")

    %{device: device} = device_fixture(scope)
    save_bytes = "persistent save bytes that must survive media restore\n"
    {:ok, _status, save_blob} = Blobs.put_stream([save_bytes], byte_size(save_bytes))
    command_id = Ecto.UUID.generate()

    {:ok, _pending} =
      Saves.record_pending_upload(
        owner.id,
        device.id,
        command_id,
        save_blob.sha256,
        save_blob.size_bytes
      )

    {:ok, save_revision} =
      Saves.commit_revision(owner.id, device, %{
        "id" => Ecto.UUID.generate(),
        "command_id" => command_id,
        "content_key" => String.duplicate("a", 64)
      })

    {:ok, selection} =
      Metadata.select_description(owner.id, asset_set.id, "Corrected title and description")

    save_count = Repo.aggregate(Save, :count)
    member_count = Repo.aggregate(AssetMember, :count)
    target = "custody-#{System.unique_integer([:positive])}"

    {:ok, export} =
      Export.create_export(owner.id, :set, target_name: target, asset_set_id: asset_set.id)

    assert :ok = perform_job(Worker, %{"export_id" => export.id})
    record = Repo.get!(ExportRecord, export.id)
    assert record.status == "verified"
    bag = Export.target_dir(target)
    assert {:ok, _} = Playstead.Export.Verifier.verify(bag)

    sidecar_path =
      Path.wildcard(Path.join([bag, "tags", "**", "playstead-set.json"])) |> List.first()

    sidecar = Jason.decode!(File.read!(sidecar_path))
    assert [media_entry] = sidecar["media"]
    assert media_entry["sha256"] == media.original_sha256
    assert media_entry["size_bytes"] == byte_size(original)
    assert media_entry["provenance"]["source"] == "user_upload"
    assert sidecar["metadata_selection"]["description"] == selection.description
    assert sidecar["metadata_selection"]["revision"] == selection.revision
    assert File.read!(Path.join(bag, media_entry["path"])) == original
    assert File.read!(Path.join(bag, "manifest-sha256.txt")) =~ media.original_sha256

    refute Enum.any?(
             File.read!(Path.join(bag, "manifest-sha256.txt")) |> String.split("\n"),
             &String.contains?(&1, "derived")
           )

    Repo.delete!(media)
    Repo.delete!(selection)
    assert {:ok, _receipts} = FolderImport.import_folder(owner.id, bag)
    assert {:ok, _receipts} = FolderImport.import_folder(owner.id, bag)
    {:ok, restored_items} = PrivateMedia.list(owner.id, asset_set.id)
    assert [restored] = restored_items
    assert restored.original_sha256 == media.original_sha256
    assert restored.original_size_bytes == media.original_size_bytes
    assert restored.provenance == %{"source" => "user_upload", "validated" => true}
    assert {:ok, ^original} = PrivateMedia.fetch_original(owner.id, asset_set.id, restored.id)
    assert {:ok, restored_selection} = Metadata.get_description(owner.id, asset_set.id)
    assert restored_selection.description == selection.description
    assert restored_selection.revision == selection.revision
    assert Repo.aggregate(AssetMember, :count) == member_count
    assert Repo.aggregate(Save, :count) == save_count
    assert Repo.get!(AssetSet, asset_set.id).member_fingerprint == asset_set.member_fingerprint
    assert {:ok, save_stream} = Blobs.stream(save_revision.blob_sha256)
    assert IO.iodata_to_binary(Enum.to_list(save_stream)) == save_bytes
    assert save_revision.blob_sha256 == save_blob.sha256
  end
end
