defmodule Playstead.Blobs.FingerprintsTest do
  @moduledoc """
  Plan 02-10 gap closure: `Playstead.Blobs.Fingerprints.ensure_headerless/2`
  is the production writer 02-VERIFICATION.md found missing from all of
  `lib/` — this covers a real headered NES/SNES import writing exactly
  one applicable row idempotently, zero rows for headerless/random
  bytes, and the lazy backfill on the reidentify path matching a
  headerless-keyed DAT entry against a real ROM.
  """

  use Playstead.DataCase, async: true

  import Ecto.Query
  import Playstead.AccountsFixtures
  import Playstead.ImportFixtures

  alias Playstead.Blobs
  alias Playstead.Blobs.{BlobFingerprint, MultiHash}
  alias Playstead.Import
  alias Playstead.Recognition
  alias Playstead.Recognition.{DatPack, ReferenceEntry}
  alias Playstead.Repo
  alias Playstead.RomFixtures

  setup do
    File.mkdir_p!(Playstead.Blobs.Store.LocalDisk.blob_path())
    :ok
  end

  defp store!(bytes) do
    {:ok, status, meta} = Blobs.put_stream([bytes], byte_size(bytes))
    {status, meta}
  end

  defp import!(user_id, bytes, name, opts \\ []) do
    {status, meta} = store!(bytes)

    {:ok, receipt} =
      Import.import_single(
        user_id,
        %{original_name: name, origin: "upload", size_bytes: byte_size(bytes)},
        {status, meta},
        opts
      )

    {receipt, meta}
  end

  defp fingerprints_for(blob_id) do
    Repo.all(from(f in BlobFingerprint, where: f.blob_id == ^blob_id))
  end

  defp expected_digest(bytes, offset) do
    path = Path.join(System.tmp_dir!(), "fp-expected-#{System.unique_integer([:positive])}.bin")
    File.write!(path, bytes)

    on_exit(fn -> File.rm(path) end)

    {:ok, digests} = MultiHash.digest_from_offset(path, offset)
    digests
  end

  # --- production writer on the import path -----------------------------

  test "a headered NES import writes exactly one nes_header_skip16 row with correct digests" do
    %{user: user} = user_scope_fixture()
    bytes = RomFixtures.valid_nes_ines(3) <> :crypto.strong_rand_bytes(256)

    {_receipt, meta} = import!(user.id, bytes, "game.nes")

    rows = fingerprints_for(meta.blob_id)
    assert [row] = rows
    assert row.kind == "nes_header_skip16"
    assert row.offset == 16

    expected = expected_digest(bytes, 16)
    assert row.crc32 == expected.crc32
    assert row.md5 == expected.md5
    assert row.sha1 == expected.sha1
  end

  test "a headered SNES LoROM import writes exactly one snes_copier_skip512 row" do
    %{user: user} = user_scope_fixture()
    bytes = RomFixtures.valid_snes_lorom(true)

    {_receipt, meta} = import!(user.id, bytes, "game.sfc")

    rows = fingerprints_for(meta.blob_id)
    assert [row] = rows
    assert row.kind == "snes_copier_skip512"
    assert row.offset == 512

    expected = expected_digest(bytes, 512)
    assert row.crc32 == expected.crc32
    assert row.md5 == expected.md5
    assert row.sha1 == expected.sha1
  end

  test "a headered SNES HiROM import (the raised read ceiling case) writes the copier row" do
    %{user: user} = user_scope_fixture()
    bytes = RomFixtures.valid_snes_hirom(true)

    {_receipt, meta} = import!(user.id, bytes, "game.sfc")

    assert [%{kind: "snes_copier_skip512", offset: 512}] = fingerprints_for(meta.blob_id)
  end

  test "re-importing identical bytes (CAS returns :existing) still leaves exactly one row" do
    %{user: user} = user_scope_fixture()
    bytes = RomFixtures.valid_nes_ines(1) <> :crypto.strong_rand_bytes(128)

    {_receipt1, meta1} = import!(user.id, bytes, "game.nes")
    assert {:existing, meta2} = store!(bytes)
    assert meta1.blob_id == meta2.blob_id

    {:ok, _receipt2} =
      Import.import_single(
        user.id,
        %{original_name: "game-copy.nes", origin: "upload", size_bytes: byte_size(bytes)},
        {:existing, meta2}
      )

    assert [_one_row] = fingerprints_for(meta1.blob_id)
  end

  test "a headerless SNES file and a random-bytes file both write zero rows" do
    %{user: user} = user_scope_fixture()

    {_r1, meta1} = import!(user.id, RomFixtures.valid_snes_lorom(false), "headerless.sfc")
    assert fingerprints_for(meta1.blob_id) == []

    {_r2, meta2} = import!(user.id, random_bytes(300), "mystery.bin")
    assert fingerprints_for(meta2.blob_id) == []
  end

  # --- lazy backfill on the reidentify path ------------------------------

  test "a DAT pack keyed to the headerless SHA-1 matches a real headered NES import via reidentify/2" do
    %{user: user} = user_scope_fixture()
    bytes = RomFixtures.valid_nes_ines(5) <> :crypto.strong_rand_bytes(512)

    {_receipt, meta} = import!(user.id, bytes, "game.nes")
    expected = expected_digest(bytes, 16)

    {:ok, pack} =
      %DatPack{}
      |> DatPack.create_changeset(%{
        user_id: user.id,
        file_sha256: :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower),
        license_claim: "unstated",
        transform_version: "1"
      })
      |> Repo.insert()

    {:ok, _entry} =
      %ReferenceEntry{}
      |> ReferenceEntry.create_changeset(%{
        dat_pack_id: pack.id,
        name: "Headerless NES Game",
        sha1: expected.sha1
      })
      |> Repo.insert()

    assert %{identified: 1} = Recognition.reidentify(user.id)

    scope = %Playstead.Accounts.Scope{user: user}
    asset = Playstead.Catalogue.list_assets(scope) |> hd()
    assert asset.identification_state == :identified
    assert Repo.get!(Playstead.Blobs.Blob, meta.blob_id) != nil
  end

  test "a blob whose fingerprint row was never written is back-filled lazily by reidentify/2 with no Oban worker" do
    %{user: user} = user_scope_fixture()
    bytes = RomFixtures.valid_nes_ines(7) <> :crypto.strong_rand_bytes(64)

    # Import with the fingerprint writer's effect undone afterward, to
    # prove reidentify/2 computes it itself rather than depending on
    # import-time writes.
    {_receipt, meta} = import!(user.id, bytes, "game.nes")
    Repo.delete_all(from(f in BlobFingerprint, where: f.blob_id == ^meta.blob_id))
    assert fingerprints_for(meta.blob_id) == []

    expected = expected_digest(bytes, 16)

    {:ok, pack} =
      %DatPack{}
      |> DatPack.create_changeset(%{
        user_id: user.id,
        file_sha256: :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower),
        license_claim: "unstated",
        transform_version: "1"
      })
      |> Repo.insert()

    {:ok, _entry} =
      %ReferenceEntry{}
      |> ReferenceEntry.create_changeset(%{
        dat_pack_id: pack.id,
        name: "Backfilled NES Game",
        sha1: expected.sha1
      })
      |> Repo.insert()

    assert %{identified: 1} = Recognition.reidentify(user.id)
    assert [_row] = fingerprints_for(meta.blob_id)
  end
end
