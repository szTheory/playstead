defmodule Playstead.Import.CataloguePayloadTest do
  @moduledoc """
  D-23: the frozen `catalogue` change-journal payload carries exactly
  its specified fields and nothing else (task 3 of 02-03-PLAN.md).
  """

  use Playstead.DataCase, async: true

  import Playstead.AccountsFixtures
  import Playstead.ImportFixtures

  alias Playstead.Blobs
  alias Playstead.Catalogue
  alias Playstead.Catalogue.AssetSet
  alias Playstead.Catalogue.Payload
  alias Playstead.Import
  alias Playstead.Repo
  alias Playstead.Sync.Snapshot

  setup do
    File.mkdir_p!(Playstead.Blobs.Store.LocalDisk.blob_path())
    :ok
  end

  defp store!(bytes) do
    {:ok, status, meta} = Blobs.put_stream([bytes], byte_size(bytes))
    {status, meta}
  end

  defp import_one!(user_id, name) do
    bytes = random_bytes(256)
    {status, meta} = store!(bytes)

    {:ok, receipt} =
      Import.import_single(
        user_id,
        %{original_name: name, origin: "upload", size_bytes: byte_size(bytes)},
        {status, meta}
      )

    receipt
  end

  test "Payload.build/1 returns exactly the frozen key set" do
    %{user: user} = user_scope_fixture()
    receipt = import_one!(user.id, "game.rom")

    asset_set =
      AssetSet
      |> Repo.get!(receipt.asset_set_id)
      |> Repo.preload(asset_members: :blob)

    payload = Payload.build(asset_set)

    assert MapSet.new(Map.keys(payload)) == MapSet.new(Payload.frozen_keys())
  end

  test "the payload never carries a source path, legacy digest, or provenance field" do
    %{user: user} = user_scope_fixture()
    receipt = import_one!(user.id, "game.rom")

    asset_set =
      AssetSet
      |> Repo.get!(receipt.asset_set_id)
      |> Repo.preload(asset_members: :blob)

    payload = Payload.build(asset_set)
    keys = payload |> Map.keys() |> Enum.map(&to_string/1)

    refute Enum.any?(keys, &(&1 =~ ~r/relative_path|original_name|md5|sha1|crc32|provenance/i))
  end

  test "excluding a set emits a catalogue tombstone a resuming reader observes" do
    %{user: user} = user_scope_fixture()
    receipt = import_one!(user.id, "game.rom")
    asset_set = Repo.get!(AssetSet, receipt.asset_set_id)

    before_seq = Playstead.Sync.ChangeJournal.max_seq(user.id)

    {:ok, _updated} = Catalogue.exclude_set(asset_set, user.id)

    entries = Playstead.Sync.ChangeJournal.read_after(user.id, before_seq, 10)
    assert Enum.any?(entries, &(&1.operation == "tombstone" and &1.entity_id == asset_set.id))
  end

  test "the snapshot returns a catalogue branch and its as-of cursor from one transaction" do
    %{user: user} = user_scope_fixture()
    _receipt = import_one!(user.id, "game.rom")

    {:ok, page} = Snapshot.read(user.id)

    assert is_list(page.catalogue)
    assert length(page.catalogue) == 1
    assert is_binary(page.cursor)
  end
end
