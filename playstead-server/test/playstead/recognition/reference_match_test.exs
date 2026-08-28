defmodule Playstead.Recognition.ReferenceMatchTest do
  @moduledoc """
  D-17 through D-20, D-25, D-26, D-27: installing a reference pack
  upgrades identification on already-stored digests, never re-reads a
  blob's bytes, never rewrites a receipt or an existing evidence row,
  resolves ambiguity it can settle, and raises no new attention item
  for content that stays unmatched.
  """

  use Playstead.DataCase, async: true

  import Ecto.Query
  import Playstead.AccountsFixtures

  alias Playstead.Attention
  alias Playstead.Attention.Item
  alias Playstead.Blobs.{Blob, BlobFingerprint}
  alias Playstead.Catalogue.AssetMember
  alias Playstead.Catalogue.AssetSet
  alias Playstead.Import.{Receipt, SourceFile}
  alias Playstead.Recognition
  alias Playstead.Recognition.{DatPack, Evidence, Override, ReferenceEntry, ReferenceMatch}
  alias Playstead.Repo
  alias Playstead.Sync.ChangeJournal

  # --- fixtures ------------------------------------------------------

  defp blob_fixture(attrs \\ %{}) do
    default = %{
      sha256: :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower),
      size_bytes: 1024,
      crc32: :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower),
      md5: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower),
      sha1: :crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)
    }

    {:ok, blob} = %Blob{} |> Blob.create_changeset(Map.merge(default, attrs)) |> Repo.insert()
    blob
  end

  defp asset_set_fixture(user, blob, attrs \\ %{}) do
    default = %{
      user_id: user.id,
      status: "active",
      member_fingerprint: "fixture:#{Ecto.UUID.generate()}",
      display_title: "Fixture Game"
    }

    {:ok, asset_set} =
      %AssetSet{} |> AssetSet.create_changeset(Map.merge(default, attrs)) |> Repo.insert()

    {:ok, _member} =
      %AssetMember{}
      |> AssetMember.create_changeset(%{
        asset_set_id: asset_set.id,
        ordinal: 0,
        role: "primary",
        blob_id: blob.id,
        declared_name: "fixture.gba"
      })
      |> Repo.insert()

    asset_set
  end

  defp dat_pack_fixture(user, entry_attrs) do
    {:ok, pack} =
      %DatPack{}
      |> DatPack.create_changeset(%{
        user_id: user.id,
        file_sha256: :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower),
        license_claim: "unstated",
        transform_version: "1"
      })
      |> Repo.insert()

    {:ok, entry} =
      %ReferenceEntry{}
      |> ReferenceEntry.create_changeset(Map.put(entry_attrs, :dat_pack_id, pack.id))
      |> Repo.insert()

    {pack, entry}
  end

  defp receipt_fixture(user, asset_set, blob, outcome) do
    {:ok, source_file} =
      %SourceFile{}
      |> SourceFile.create_changeset(%{
        user_id: user.id,
        original_name: "fixture.gba",
        origin: "upload",
        size_bytes: blob.size_bytes
      })
      |> Repo.insert()

    {:ok, receipt} =
      %Receipt{}
      |> Receipt.create_changeset(%{
        user_id: user.id,
        source_file_id: source_file.id,
        blob_id: blob.id,
        asset_set_id: asset_set.id,
        outcome: outcome,
        sha256: blob.sha256,
        size_bytes: blob.size_bytes
      })
      |> Repo.insert()

    receipt
  end

  defp latest_evidence(blob_id) do
    from(e in Evidence, where: e.blob_id == ^blob_id, order_by: [desc: e.inserted_at], limit: 1)
    |> Repo.one()
  end

  # --- behaviour compliance -------------------------------------------

  test "declares the existing recognition provider behaviour" do
    behaviours = ReferenceMatch.module_info(:attributes)[:behaviour] || []
    assert Playstead.Recognition.Provider in behaviours
  end

  # --- digest matching --------------------------------------------------

  test "a headerless-offset fingerprint succeeds where the full-file digest alone would not" do
    user = owner_fixture()
    # This blob's own full-file digests match nothing installed.
    blob = blob_fixture()

    {:ok, fingerprint} =
      %BlobFingerprint{}
      |> BlobFingerprint.create_changeset(%{
        blob_id: blob.id,
        kind: "nes_header_skip16",
        offset: 16,
        crc32: "cafef00d",
        md5: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        sha1: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
      })
      |> Repo.insert()

    {_pack, entry} =
      dat_pack_fixture(user, %{
        name: "Headerless Match Game",
        crc32: "cafef00d",
        md5: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        sha1: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        size_bytes: 1024
      })

    assert :no_match = ReferenceMatch.match(blob, [])
    assert {:match, matched_entry} = ReferenceMatch.match(blob, [fingerprint])
    assert matched_entry.id == entry.id
  end

  test "matching reads no bytes from the blob store — the blob's file never exists on disk" do
    user = owner_fixture()
    # No file is ever written to the blob store for this row; a real
    # byte read would fail loudly. A successful match therefore proves
    # matching touched only database rows.
    blob = blob_fixture(%{sha1: "cccccccccccccccccccccccccccccccccccccccc"})
    asset_set = asset_set_fixture(user, blob)

    dat_pack_fixture(user, %{
      name: "No Read Game",
      sha1: "cccccccccccccccccccccccccccccccccccccccc"
    })

    assert %{identified: 1} = Recognition.reidentify(user.id)
    assert latest_evidence(blob.id).status == "matched"
    assert asset_set.id != nil
  end

  # --- appended evidence, promotion, receipts -----------------------

  test "a match appends an evidence row with exact confidence, reference name, provider name/version" do
    user = owner_fixture()
    blob = blob_fixture()
    asset_set = asset_set_fixture(user, blob)

    {_pack, entry} = dat_pack_fixture(user, %{name: "Provider Fields Game", sha1: blob.sha1})

    assert %{identified: 1} = Recognition.reidentify(user.id)

    evidence = latest_evidence(blob.id)
    assert evidence.confidence == "exact"
    assert evidence.reference_name == entry.name
    assert evidence.provider_name == "reference_match"
    assert evidence.provider_version == "1"
    assert evidence.asset_set_id == asset_set.id
  end

  test "the asset's current identification state and catalogue payload change after a match" do
    user = owner_fixture()
    scope = %Playstead.Accounts.Scope{user: user}
    blob = blob_fixture()
    _asset_set = asset_set_fixture(user, blob)

    dat_pack_fixture(user, %{name: "Identified Game", sha1: blob.sha1})

    before_state =
      Playstead.Catalogue.list_assets(scope) |> hd() |> Map.fetch!(:identification_state)

    assert before_state == :unidentified

    Recognition.reidentify(user.id)

    after_state =
      Playstead.Catalogue.list_assets(scope) |> hd() |> Map.fetch!(:identification_state)

    assert after_state == :identified
  end

  test "the receipt for that asset still reports the outcome recorded at import" do
    user = owner_fixture()
    blob = blob_fixture()
    asset_set = asset_set_fixture(user, blob)
    receipt = receipt_fixture(user, asset_set, blob, "unrecognized")

    dat_pack_fixture(user, %{name: "Terminal Receipt Game", sha1: blob.sha1})
    Recognition.reidentify(user.id)

    reloaded = Repo.get!(Receipt, receipt.id)
    assert reloaded.outcome == "unrecognized"
  end

  test "a user override still outranks a reference match" do
    user = owner_fixture()
    blob = blob_fixture()
    asset_set = asset_set_fixture(user, blob, %{system_id: "gba", system_source: "user"})

    {:ok, _override} =
      %Override{}
      |> Override.create_changeset(%{
        user_id: user.id,
        asset_set_id: asset_set.id,
        system_id: "gba"
      })
      |> Repo.insert()

    dat_pack_fixture(user, %{name: "Override Outranks Game", sha1: blob.sha1})
    Recognition.reidentify(user.id)

    reloaded = Repo.get!(AssetSet, asset_set.id)
    assert reloaded.system_id == "gba"
    assert reloaded.system_source == "user"
  end

  # --- attention ------------------------------------------------------

  test "a previously ambiguous attention item is resolved by a match with no human action" do
    user = owner_fixture()
    blob = blob_fixture()
    asset_set = asset_set_fixture(user, blob)

    {:ok, item} =
      Attention.raise_item(%{
        user_id: user.id,
        outcome: :unrecognized,
        reason: "ambiguous",
        grouping_key: "fixture:#{asset_set.id}",
        asset_set_id: asset_set.id
      })

    assert item.status == "open"

    dat_pack_fixture(user, %{name: "Resolves Ambiguity Game", sha1: blob.sha1})
    Recognition.reidentify(user.id)

    reloaded = Repo.get!(Item, item.id)
    assert reloaded.status == "resolved"
  end

  test "an asset that was quiet before and remains unmatched afterwards gains no attention item" do
    user = owner_fixture()
    blob = blob_fixture()
    _asset_set = asset_set_fixture(user, blob)

    # A pack with an entry that matches nothing about this blob.
    dat_pack_fixture(user, %{
      name: "Unrelated Game",
      sha1: :crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)
    })

    assert %{identified: 0} = Recognition.reidentify(user.id)
    assert Attention.count(user.id) == 0
  end

  test "a possible-variant reading becomes a certain variant only on a reference match" do
    user = owner_fixture()
    blob = blob_fixture()
    asset_set = asset_set_fixture(user, blob)

    {:ok, _prior_evidence} =
      %Evidence{}
      |> Evidence.create_changeset(%{
        blob_id: blob.id,
        asset_set_id: asset_set.id,
        provider_name: "header_evidence",
        provider_version: "1",
        status: "possible_variant",
        confidence: "header",
        evidence: %{}
      })
      |> Repo.insert()

    dat_pack_fixture(user, %{name: "Variant Confirmed Game", sha1: blob.sha1})
    Recognition.reidentify(user.id)

    evidence = latest_evidence(blob.id)
    assert evidence.status == "variant"
    assert evidence.confidence == "exact"
  end

  # --- journal ----------------------------------------------------------

  test "a catalogue journal entry is emitted for a changed asset and none for an unchanged one" do
    user = owner_fixture()

    matched_blob = blob_fixture()
    matched_set = asset_set_fixture(user, matched_blob)

    unmatched_blob = blob_fixture()
    unmatched_set = asset_set_fixture(user, unmatched_blob)

    dat_pack_fixture(user, %{name: "Journal Match Game", sha1: matched_blob.sha1})

    before_seq = ChangeJournal.max_seq(user.id)
    Recognition.reidentify(user.id)

    entries = ChangeJournal.read_after(user.id, before_seq, 100)
    entity_ids = Enum.map(entries, & &1.entity_id)

    assert matched_set.id in entity_ids
    refute unmatched_set.id in entity_ids
  end

  # --- pack removal -----------------------------------------------------

  test "removing a pack leaves every evidence row in place" do
    user = owner_fixture()
    blob = blob_fixture()
    asset_set_fixture(user, blob)

    {pack, _entry} = dat_pack_fixture(user, %{name: "Removed Pack Game", sha1: blob.sha1})
    Recognition.reidentify(user.id)

    before_ids =
      from(e in Evidence, where: e.blob_id == ^blob.id) |> Repo.all() |> Enum.map(& &1.id)

    assert before_ids != []

    {:ok, _} = Playstead.Recognition.DatPackImporter.remove_pack(pack, user.id)

    after_ids =
      from(e in Evidence, where: e.blob_id == ^blob.id) |> Repo.all() |> Enum.map(& &1.id)

    assert MapSet.new(before_ids) == MapSet.new(after_ids)
  end
end
