defmodule Playstead.Recognition.DatPackImporterTest do
  use Playstead.DataCase, async: true

  import Playstead.AccountsFixtures

  alias Playstead.AuditLog
  alias Playstead.Recognition.{DatPack, DatPackImporter, ReferenceEntry}
  alias Playstead.Repo

  @fixtures_dir Path.join([__DIR__, "..", "..", "support", "fixtures", "dat"])
  defp fixture(name), do: Path.join(@fixtures_dir, name)

  defp provenance(overrides \\ %{}) do
    Map.merge(
      %{
        source: "https://example.com/no-intro-test.dat",
        upstream_version: "2026-08-01",
        license_claim: :unstated,
        license_note: "No published licence for this pack.",
        transform_version: "1"
      },
      overrides
    )
  end

  setup do
    %{user: owner_fixture()}
  end

  test "importing a well-formed pack records provenance and entries", %{user: user} do
    assert {:ok, %DatPack{} = pack} =
             DatPackImporter.import_pack(user.id, fixture("valid.dat"), provenance())

    assert pack.user_id == user.id
    assert pack.source == "https://example.com/no-intro-test.dat"
    assert pack.upstream_version == "2026-08-01"
    assert pack.license_claim == "unstated"
    assert pack.license_note == "No published licence for this pack."
    assert pack.transform_version == "1"
    assert byte_size(pack.file_sha256) == 64
    assert %DateTime{} = pack.retrieved_at
    assert pack.entry_count == 2

    entries = Repo.all(ReferenceEntry) |> Enum.filter(&(&1.dat_pack_id == pack.id))
    assert length(entries) == 2
    assert Enum.any?(entries, &(&1.name == "Test Game (USA).gba"))
    assert Enum.any?(entries, &(&1.crc32 == "1234abcd"))
  end

  test "importing writes an audit entry with the provenance", %{user: user} do
    assert {:ok, pack} = DatPackImporter.import_pack(user.id, fixture("valid.dat"), provenance())

    [entry] = AuditLog.list_by_subject(pack.id)
    assert entry.event == "reference_pack_imported"
    assert entry.metadata["file_sha256"] == pack.file_sha256
    assert entry.metadata["license_claim"] == "unstated"
    assert entry.metadata["entry_count"] == 2
  end

  test "importing the same pack twice does not duplicate its entries", %{user: user} do
    assert {:ok, first} = DatPackImporter.import_pack(user.id, fixture("valid.dat"), provenance())

    assert {:ok, second} =
             DatPackImporter.import_pack(user.id, fixture("valid.dat"), provenance())

    assert first.id == second.id
    assert Repo.aggregate(DatPack, :count) == 1
    assert Repo.aggregate(ReferenceEntry, :count) == 2
  end

  test "a malformed pack is refused and stores nothing", %{user: user} do
    assert {:error, :dtd_or_entity_declared} =
             DatPackImporter.import_pack(user.id, fixture("doctype.dat"), provenance())

    assert Repo.aggregate(DatPack, :count) == 0
    assert Repo.aggregate(ReferenceEntry, :count) == 0
  end

  test "a truncated pack is refused and stores nothing", %{user: user} do
    assert {:error, :malformed} =
             DatPackImporter.import_pack(user.id, fixture("truncated.dat"), provenance())

    assert Repo.aggregate(DatPack, :count) == 0
  end

  test "removing a pack writes an audit entry and leaves no reference_entries behind", %{
    user: user
  } do
    assert {:ok, pack} = DatPackImporter.import_pack(user.id, fixture("valid.dat"), provenance())
    assert {:ok, _removed} = DatPackImporter.remove_pack(pack, user.id)

    assert Repo.aggregate(DatPack, :count) == 0
    assert Repo.aggregate(ReferenceEntry, :count) == 0

    events = AuditLog.list_by_subject(pack.id) |> Enum.map(& &1.event)
    assert "reference_pack_removed" in events
  end

  test "lists a user's packs newest first", %{user: user} do
    {:ok, _first} = DatPackImporter.import_pack(user.id, fixture("valid.dat"), provenance())

    packs = DatPackImporter.list_packs(user.id)
    assert length(packs) == 1
  end
end
