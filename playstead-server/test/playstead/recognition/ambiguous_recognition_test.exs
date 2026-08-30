defmodule Playstead.Recognition.AmbiguousRecognitionTest do
  @moduledoc """
  Plan 02-10 gap closure (02-VERIFICATION.md gap 1's second half):
  `unrecognized{ambiguous}` had no live detector — `lookup_by/2` ended
  every digest query with `limit: 1`, silently picking whichever row
  Postgres ordered first. This covers the detector: two conflicting
  reference entries sharing one digest raise exactly one
  `ambiguous_recognition` item naming both candidates, never a silent
  pick, and the item clears through the existing resolutions.
  """

  use Playstead.DataCase, async: true

  import Ecto.Query
  import Playstead.AccountsFixtures

  alias Playstead.Attention
  alias Playstead.Attention.{Item, Resolutions}
  alias Playstead.Blobs
  alias Playstead.Blobs.Blob
  alias Playstead.Catalogue.AssetMember
  alias Playstead.Catalogue.AssetSet
  alias Playstead.Import
  alias Playstead.Recognition
  alias Playstead.Recognition.{DatPack, Evidence, ReferenceEntry}
  alias Playstead.Repo

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

  defp evidence_rows(blob_id) do
    from(e in Evidence, where: e.blob_id == ^blob_id) |> Repo.all()
  end

  test "two conflicting entries sharing one digest raise exactly one ambiguous_recognition item naming both, and the asset stays unmatched" do
    user = owner_fixture()
    blob = blob_fixture()
    asset_set = asset_set_fixture(user, blob)

    {_pack_a, entry_a} = dat_pack_fixture(user, %{name: "Game A", sha1: blob.sha1})
    {_pack_b, entry_b} = dat_pack_fixture(user, %{name: "Game B", sha1: blob.sha1})

    assert %{identified: 0, ambiguous: 1} = Recognition.reidentify(user.id)

    items = from(i in Item, where: i.user_id == ^user.id) |> Repo.all()
    assert [item] = items
    assert item.reason == "ambiguous_recognition"
    assert item.status == "open"

    names = get_in(item.evidence, ["candidates"]) |> Enum.map(& &1["name"])
    assert Enum.sort(names) == Enum.sort([entry_a.name, entry_b.name])

    reloaded_set = Repo.get!(AssetSet, asset_set.id)
    refute reloaded_set.system_source == "reference"
  end

  test "the ambiguous branch appends exactly one new evidence row and modifies no pre-existing row" do
    user = owner_fixture()
    blob = blob_fixture()
    asset_set = asset_set_fixture(user, blob)

    {:ok, prior_evidence} =
      %Evidence{}
      |> Evidence.create_changeset(%{
        blob_id: blob.id,
        asset_set_id: asset_set.id,
        provider_name: "header_evidence",
        provider_version: "1",
        status: "no_reference_installed",
        evidence: %{}
      })
      |> Repo.insert()

    dat_pack_fixture(user, %{name: "Game A", sha1: blob.sha1})
    dat_pack_fixture(user, %{name: "Game B", sha1: blob.sha1})

    before_rows = evidence_rows(blob.id)
    assert length(before_rows) == 1

    Recognition.reidentify(user.id)

    after_rows = evidence_rows(blob.id)
    assert length(after_rows) == 2

    reloaded_prior = Repo.get!(Evidence, prior_evidence.id)
    assert reloaded_prior.id == prior_evidence.id
    assert reloaded_prior.inserted_at == prior_evidence.inserted_at
    assert reloaded_prior.status == "no_reference_installed"
  end

  test "running reidentify/2 a second time over the same unresolved blob does not create a second item" do
    user = owner_fixture()
    blob = blob_fixture()
    asset_set_fixture(user, blob)

    dat_pack_fixture(user, %{name: "Game A", sha1: blob.sha1})
    dat_pack_fixture(user, %{name: "Game B", sha1: blob.sha1})

    assert %{ambiguous: 1} = Recognition.reidentify(user.id)
    assert %{identified: 0, ambiguous: 0} = Recognition.reidentify(user.id)

    assert Attention.count(user.id) == 1
  end

  test "two entries with the same SHA-1, name, and dat_pack_id promote to matched as a single match" do
    user = owner_fixture()
    blob = blob_fixture()
    asset_set_fixture(user, blob)

    {:ok, pack} =
      %DatPack{}
      |> DatPack.create_changeset(%{
        user_id: user.id,
        file_sha256: :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower),
        license_claim: "unstated",
        transform_version: "1"
      })
      |> Repo.insert()

    {:ok, _entry1} =
      %ReferenceEntry{}
      |> ReferenceEntry.create_changeset(%{
        dat_pack_id: pack.id,
        name: "Duplicate Row Game",
        sha1: blob.sha1
      })
      |> Repo.insert()

    {:ok, _entry2} =
      %ReferenceEntry{}
      |> ReferenceEntry.create_changeset(%{
        dat_pack_id: pack.id,
        name: "Duplicate Row Game",
        sha1: blob.sha1
      })
      |> Repo.insert()

    assert %{identified: 1, ambiguous: 0} = Recognition.reidentify(user.id)
    assert Attention.count(user.id) == 0
  end

  test "a single matching entry still promotes to matched and resolves the asset set's open attention items, unchanged" do
    user = owner_fixture()
    blob = blob_fixture()
    asset_set = asset_set_fixture(user, blob)

    {:ok, item} =
      Attention.raise_item(%{
        user_id: user.id,
        outcome: :unrecognized,
        reason: "signature_mismatch",
        grouping_key: "fixture:#{asset_set.id}",
        asset_set_id: asset_set.id
      })

    dat_pack_fixture(user, %{name: "Single Match Game", sha1: blob.sha1})
    assert %{identified: 1, ambiguous: 0} = Recognition.reidentify(user.id)

    reloaded_item = Repo.get!(Item, item.id)
    assert reloaded_item.status == "resolved"
  end

  test "resolving the ambiguous item through correct_system clears it" do
    user = owner_fixture()
    blob = blob_fixture()
    asset_set_fixture(user, blob)

    dat_pack_fixture(user, %{name: "Game A", sha1: blob.sha1})
    dat_pack_fixture(user, %{name: "Game B", sha1: blob.sha1})
    Recognition.reidentify(user.id)

    item = Repo.get_by!(Item, user_id: user.id, reason: "ambiguous_recognition")

    assert {:ok, _result} = Resolutions.correct_system(item, user.id, "gba")
    reloaded = Repo.get!(Item, item.id)
    assert reloaded.status == "resolved"
  end

  test "resolving the ambiguous item through retain_as_custom clears it" do
    user = owner_fixture()
    blob = blob_fixture()
    asset_set_fixture(user, blob)

    dat_pack_fixture(user, %{name: "Game A", sha1: blob.sha1})
    dat_pack_fixture(user, %{name: "Game B", sha1: blob.sha1})
    Recognition.reidentify(user.id)

    item = Repo.get_by!(Item, user_id: user.id, reason: "ambiguous_recognition")

    assert {:ok, _result} = Resolutions.retain_as_custom(item, user.id)
    reloaded = Repo.get!(Item, item.id)
    assert reloaded.status == "resolved"
  end

  # CR-01 regression (02-REVIEW.md gap-closure pass): an import-time
  # ambiguous determination (`Import.classify_recognized/8` ->
  # `reference_match_reason/3`) and a later `Recognition.reidentify/2`
  # rediscovery of the very same digest conflict must converge on
  # exactly one `ambiguous_recognition` attention item, not two.
  describe "import-time ambiguous detection converges with reidentify (CR-01)" do
    setup do
      File.mkdir_p!(Playstead.Blobs.Store.LocalDisk.blob_path())
      :ok
    end

    test "import while two packs conflict, then reidentify/2, raises exactly one item" do
      user = owner_fixture()
      bytes = :crypto.strong_rand_bytes(512)

      {:ok, status, meta} = Blobs.put_stream([bytes], byte_size(bytes))

      {_pack_a, entry_a} = dat_pack_fixture(user, %{name: "Game A", sha1: meta.sha1})
      {_pack_b, entry_b} = dat_pack_fixture(user, %{name: "Game B", sha1: meta.sha1})

      {:ok, receipt} =
        Import.import_single(
          user.id,
          %{original_name: "mystery.rom", origin: "upload", size_bytes: byte_size(bytes)},
          {status, meta},
          format_bytes: bytes
        )

      assert receipt.outcome == "unrecognized"
      assert receipt.reason == "ambiguous"

      assert Attention.count(user.id) == 1

      items = from(i in Item, where: i.user_id == ^user.id) |> Repo.all()
      assert [item] = items
      assert item.reason == "ambiguous_recognition"
      assert item.grouping_key == "ambiguous_recognition:#{receipt.blob_id}"

      names = get_in(item.evidence, ["candidates"]) |> Enum.map(& &1["name"])
      assert Enum.sort(names) == Enum.sort([entry_a.name, entry_b.name])

      # The import-time path must have written the same reference_match
      # evidence row reidentify/2's own ambiguous branch writes — that
      # is what excludes this blob from unmatched_candidates/1 so a
      # later pack install does not re-raise a second, differently-keyed
      # item for the same conflict.
      assert [%Evidence{provider_name: "reference_match", status: "ambiguous"}] =
               from(e in Evidence,
                 where: e.blob_id == ^receipt.blob_id and e.provider_name == "reference_match"
               )
               |> Repo.all()

      # A third, unrelated pack triggers reidentify/2 (D-18). The same
      # conflict is still unresolved, but must not raise a second item.
      dat_pack_fixture(user, %{name: "Game A", sha1: meta.sha1})
      assert %{identified: 0, ambiguous: 0} = Recognition.reidentify(user.id)

      assert Attention.count(user.id) == 1
    end
  end
end
