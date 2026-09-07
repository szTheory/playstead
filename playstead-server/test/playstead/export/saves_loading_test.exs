defmodule Playstead.Export.SavesLoadingTest do
  @moduledoc """
  Plan 04-21 task 1: the tracer proving one real save line's bytes
  reach a written, verified bag. WINDOWS #30 / PORT-01 — before this,
  every production export wrote a valid-shaped but empty `saves/`
  slot because `Export.to_layout_input/1` never attached a `:saves`
  key.
  """

  use Playstead.DataCase, async: false
  use Oban.Testing, repo: Playstead.Repo

  import Playstead.AccountsFixtures
  import Playstead.ImportFixtures
  import Playstead.PairingFixtures

  alias Playstead.Blobs
  alias Playstead.Blobs.Store.LocalDisk
  alias Playstead.Export
  alias Playstead.Export.{ExportRecord, Verifier, Worker}
  alias Playstead.Repo
  alias Playstead.Saves

  setup do
    File.mkdir_p!(LocalDisk.blob_path())
    File.rm_rf!(Export.export_root())
    File.mkdir_p!(Export.export_root())
    :ok
  end

  defp user_with_asset(bytes \\ nil) do
    scope = user_scope_fixture()
    bytes = bytes || random_bytes(2_048)
    {:ok, :stored, meta} = Blobs.put_stream([bytes], byte_size(bytes))

    {:ok, receipt} =
      Playstead.Import.import_single(
        scope.user.id,
        %{original_name: "game.gba", origin: "upload", size_bytes: meta.size_bytes},
        {:stored, meta}
      )

    asset_set = Export.fetch_asset_set(scope.user.id, receipt.asset_set_id)
    {scope, asset_set, bytes, meta}
  end

  defp commit_save!(scope, device, content_key, bytes, extra_attrs \\ []) do
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
      %{"id" => Ecto.UUID.generate(), "command_id" => command_id, "content_key" => content_key}
      |> Map.merge(Map.new(extra_attrs, fn {k, v} -> {to_string(k), v} end))

    Saves.commit_revision(scope.user.id, device, attrs)
  end

  defp create_and_run!(user_id, scope_kind, opts) do
    {:ok, export} = Export.create_export(user_id, scope_kind, opts)
    assert :ok = perform_job(Worker, %{"export_id" => export.id})
    Repo.get!(ExportRecord, export.id)
  end

  test "an export of a game with one committed save revision writes that revision's real bytes into the bag" do
    {scope, asset_set, _rom_bytes, rom_meta} = user_with_asset()
    %{device: device} = device_fixture(scope)
    save_bytes = random_bytes(512)

    {:ok, revision} = commit_save!(scope, device, rom_meta.sha256, save_bytes)

    export =
      create_and_run!(scope.user.id, :set,
        target_name: "export-#{System.unique_integer([:positive])}",
        asset_set_id: asset_set.id
      )

    assert export.status == "verified"

    target_dir = Export.target_dir(export.target_name)

    revisions_dir =
      target_dir
      |> Path.join("data/*/*/saves/revisions")
      |> Path.wildcard()
      |> List.first()

    refute is_nil(revisions_dir), "expected a saves/revisions directory to exist"

    [revision_file] = File.ls!(revisions_dir)
    written_bytes = File.read!(Path.join(revisions_dir, revision_file))

    assert :crypto.hash(:sha256, written_bytes) |> Base.encode16(case: :lower) ==
             revision.blob_sha256

    manifest_content = File.read!(Path.join(target_dir, "manifest-sha256.txt"))
    assert manifest_content =~ revision_file

    assert {:ok, _} = Verifier.verify(target_dir)
  end

  test "an asset set with zero save lines still produces an empty saves/ slot and a bag that verifies" do
    {scope, asset_set, _bytes, _meta} = user_with_asset()

    export =
      create_and_run!(scope.user.id, :set,
        target_name: "export-#{System.unique_integer([:positive])}",
        asset_set_id: asset_set.id
      )

    assert export.status == "verified"

    target_dir = Export.target_dir(export.target_name)

    revisions_dir =
      target_dir
      |> Path.join("data/*/*/saves/revisions")
      |> Path.wildcard()
      |> List.first()

    assert is_nil(revisions_dir), "expected no saves/revisions directory for a game with no saves"

    assert {:ok, _} = Verifier.verify(target_dir)
  end

  test "deleting the :saves key from to_layout_input/2 makes this test go red (falsification check)" do
    {scope, asset_set, _rom_bytes, rom_meta} = user_with_asset()
    %{device: device} = device_fixture(scope)
    {:ok, _revision} = commit_save!(scope, device, rom_meta.sha256, random_bytes(256))

    saves = Export.load_save_revisions(scope.user.id, asset_set)
    assert saves != []

    with_saves = Export.to_layout_input(asset_set, saves)
    assert with_saves.saves == saves

    without_saves = Export.to_layout_input(asset_set)
    assert without_saves.saves == []
  end
end
