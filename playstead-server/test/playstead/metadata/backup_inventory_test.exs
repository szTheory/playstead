defmodule Playstead.Metadata.BackupInventoryTest do
  use Playstead.DataCase, async: false

  import Ecto.Query
  import Playstead.AccountsFixtures
  import Playstead.CatalogueFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Playstead.{Blobs, Repo}
  alias Playstead.Metadata.PrivateMedia
  alias Playstead.Recovery
  alias Playstead.Recovery.BackupSet

  defmodule DecoderFake do
    def decode(bytes, _mime, _opts), do: {:ok, "derived preview bytes " <> bytes}
  end

  test "backup inventory preserves original media while derivative reclaim leaves canonical objects intact" do
    Sandbox.unboxed_run(Repo, &run_backup_roundtrip/0)
  end

  defp run_backup_roundtrip do
    owner = user_scope_fixture().user
    asset_set = asset_set_fixture(owner.id)

    original = "synthetic user authored image bytes #{Ecto.UUID.generate()}"
    derivative = "derived preview bytes " <> original

    owned_hashes =
      Enum.map(
        [original, derivative],
        &(:crypto.hash(:sha256, &1) |> Base.encode16(case: :lower))
      )

    blob_root = Playstead.Blobs.Store.LocalDisk.blob_path()

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Repo.delete_all(
          from media in Playstead.Metadata.PrivateMedia.Item,
            where: media.asset_set_id == ^asset_set.id
        )

        Repo.delete_all(
          from member in Playstead.Catalogue.AssetMember,
            where: member.asset_set_id == ^asset_set.id
        )

        Repo.delete_all(from set in Playstead.Catalogue.AssetSet, where: set.id == ^asset_set.id)
        Repo.delete_all(from user in Playstead.Accounts.User, where: user.id == ^owner.id)
        Repo.delete_all(from blob in Playstead.Blobs.Blob, where: blob.sha256 in ^owned_hashes)

        Enum.each(owned_hashes, fn hash ->
          File.rm(Playstead.Blobs.Store.LocalDisk.object_path(blob_root, hash))
        end)
      end)
    end)

    assert {:ok, media} =
             PrivateMedia.create(owner.id, asset_set.id, original, "image/png",
               decoder: DecoderFake
             )

    original_hash = media.original_sha256
    derivative_hash = media.derived_sha256
    {:ok, original_before} = Blobs.stream(original_hash)
    {:ok, derivative_before} = Blobs.stream(derivative_hash)
    assert Enum.join(original_before) == original
    assert Enum.join(derivative_before) == derivative

    # Detaching the generated preview must preserve its owner manifest and source CAS bytes.
    assert {:ok, detached} = PrivateMedia.remove_derived(owner.id, asset_set.id, media.id)
    assert detached.original_sha256 == original_hash
    assert detached.derived_sha256 == nil
    assert Blobs.exists?(original_hash)
    assert Blobs.exists?(derivative_hash)

    assert Repo.get!(Playstead.Catalogue.AssetSet, asset_set.id).member_fingerprint ==
             asset_set.member_fingerprint

    dump_root =
      Path.join(System.tmp_dir!(), "playstead-media-backup-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dump_root)
    on_exit(fn -> File.rm_rf!(dump_root) end)

    command = %{
      "schema" => "playstead.recovery-command.v1",
      "id" => Ecto.UUID.generate(),
      "correlation_id" => Ecto.UUID.generate(),
      "kind" => "full",
      "metadata" => %{"release" => "test", "configuration" => %{}, "parent" => nil}
    }

    assert {:ok, %{command: captured}} =
             Recovery.capture(command,
               dump_root: dump_root,
               command_runner: fn _exe, args, _opts ->
                 path = Enum.at(args, Enum.find_index(args, &(&1 == "--file")) + 1)
                 File.write!(path, "PGDMP synthetic database dump")
                 {"", 0}
               end
             )

    assert Enum.any?(captured["inventory"], &(&1["sha256"] == original_hash))

    assert Enum.any?(
             captured["inventory"],
             &(&1["sha256"] == original_hash and &1["kind"] == "private_media_original")
           )

    assert Enum.any?(captured["inventory"], &(&1["sha256"] == derivative_hash))
    dump_path = Path.wildcard(Path.join(dump_root, "database-*.dump")) |> List.first()

    {:ok, members} =
      BackupSet.materialize(Map.put(captured, "dump_path", dump_path), &Blobs.stream/1)

    assert Enum.any?(members.manifest["coverage"]["entries"], &(&1["sha256"] == original_hash))

    assert Enum.any?(
             members.manifest["coverage"]["entries"],
             &(&1["sha256"] == original_hash and &1["kind"] == "private_media_original")
           )

    assert Enum.any?(members.manifest["coverage"]["entries"], &(&1["sha256"] == derivative_hash))
    backup_root = Path.join(dump_root, "independent-backups")
    assert {:ok, %{path: backup_path}} = BackupSet.publish(backup_root, members)

    restored_path =
      Path.join([backup_path, "objects", String.slice(original_hash, 0, 2), original_hash])

    assert File.read!(restored_path) == original
    assert {:ok, _} = Playstead.Recovery.Verifier.verify(backup_path)
  end
end
