defmodule Playstead.Recognition.HeaderEvidenceTest do
  @moduledoc """
  Covers both the pure `Playstead.Recognition.HeaderEvidence` provider
  logic and the DB-backed alias/possible-variant detection performed by
  `Playstead.Recognition.recognize_and_record/3` (task 2 of
  02-03-PLAN.md).
  """

  use Playstead.DataCase, async: true

  import Playstead.AccountsFixtures
  import Playstead.ImportFixtures

  alias Playstead.Blobs
  alias Playstead.Import
  alias Playstead.Recognition
  alias Playstead.Recognition.Evidence
  alias Playstead.Recognition.HeaderEvidence
  alias Playstead.Repo

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

    receipt
  end

  describe "Provider behaviour" do
    test "declares name, version, and recognize" do
      assert HeaderEvidence.name() == "header_evidence"
      assert is_binary(HeaderEvidence.version())
      assert function_exported?(HeaderEvidence, :recognize, 2)
    end

    test "a first-time recognition with no reference data returns the no-reference status" do
      result = HeaderEvidence.recognize(%{}, nil)
      assert result.status == :no_reference_installed
    end

    test "a file whose leading bytes are a patch signature is reported as patched, never applied" do
      result = HeaderEvidence.recognize(%{bytes: "PATCH" <> random_bytes(20)}, nil)
      assert result.status == :patched
      assert result.evidence.patch_kind == :ips
    end
  end

  describe "recognize_and_record/3 (DB-backed)" do
    test "recognising the same blob twice produces two rows and updates neither" do
      %{user: user} = user_scope_fixture()
      bytes = random_bytes(1_024)
      {_status, meta} = store!(bytes)

      facts = %{blob_id: meta.blob_id, sha256: meta.sha256}

      {_result1, row1} = Recognition.recognize_and_record(user.id, facts, nil)
      {_result2, row2} = Recognition.recognize_and_record(user.id, facts, nil)

      assert row1.id != row2.id
      assert Repo.aggregate(Evidence, :count) == 2
    end

    test "a first-time recognition with no reference data is not classified as a failure" do
      %{user: user} = user_scope_fixture()
      receipt = import!(user.id, random_bytes(512), "mystery.rom")

      assert receipt.outcome == "new_asset"
    end

    test "identical bytes under a different name in the same user's library yield an alias result with no new blob" do
      %{user: user} = user_scope_fixture()
      bytes = random_bytes(2_048)

      _first = import!(user.id, bytes, "game.rom")
      {_status, meta} = store!(bytes)

      facts = %{
        blob_id: meta.blob_id,
        sha256: meta.sha256,
        exclude_source_file_id: nil
      }

      {result, _row} = Recognition.recognize_and_record(user.id, facts, nil)
      assert result.status == :alias

      assert Repo.aggregate(Playstead.Blobs.Blob, :count) == 1
    end

    test "two different-byte files sharing a header serial on the same system yield a possible-variant result" do
      %{user: user} = user_scope_fixture()

      md1 = Playstead.RomFixtures.valid_md("GM 00001009-00", "JUE")
      md2 = Playstead.RomFixtures.valid_md("GM 00001009-00", "JUE") <> <<0xFF, 0xFF>>

      {_s1, meta1} = store!(md1)
      format1 = Playstead.Formats.identify(md1, "one.md")

      {result1, _row1} =
        Recognition.recognize_and_record(
          user.id,
          %{blob_id: meta1.blob_id, sha256: meta1.sha256},
          format1
        )

      assert result1.status == :no_reference_installed

      {_s2, meta2} = store!(md2)
      format2 = Playstead.Formats.identify(md2, "two.md")

      {result2, _row2} =
        Recognition.recognize_and_record(
          user.id,
          %{blob_id: meta2.blob_id, sha256: meta2.sha256},
          format2
        )

      assert result2.status == :possible_variant
    end
  end

  describe "wired into the import pipeline" do
    test "a standard-convention filename parses into title plus tags on the resulting asset set" do
      %{user: user} = user_scope_fixture()
      bytes = random_bytes(300)

      receipt =
        import!(user.id, bytes, "My Game (USA) (En).rom", format_bytes: bytes)

      asset_set = Repo.get!(Playstead.Catalogue.AssetSet, receipt.asset_set_id)
      assert asset_set.display_title == "My Game"
      assert asset_set.title_source == "filename_parsed"
    end

    test "an unparseable filename yields the sanitized filename stem as the display title" do
      %{user: user} = user_scope_fixture()
      bytes = random_bytes(300)

      receipt = import!(user.id, bytes, "plainname.rom", format_bytes: bytes)

      asset_set = Repo.get!(Playstead.Catalogue.AssetSet, receipt.asset_set_id)
      assert asset_set.display_title == "plainname"
      assert asset_set.title_source == "filename_stem"
    end

    test "the original filename is byte-identical after import, including for a name the display title had to sanitize" do
      %{user: user} = user_scope_fixture()
      bytes = random_bytes(300)
      original_name = "weird​name.rom"

      receipt = import!(user.id, bytes, original_name, format_bytes: bytes)

      source_file = Repo.get!(Playstead.Import.SourceFile, receipt.source_file_id)
      assert source_file.original_name == original_name
    end

    test "a header that contradicts the extension yields a confirmation-needed result naming both readings" do
      md_bytes = Playstead.RomFixtures.valid_md()

      result =
        Playstead.Catalogue.assign_system(
          :gba,
          Playstead.Formats.identify(md_bytes, "game.gba"),
          nil
        )

      assert {:confirmation_needed, %{extension: :gba, header: :md}} = result
    end

    test "a user override wins over both extension and header and writes an audit entry" do
      %{user: user} = user_scope_fixture()
      bytes = random_bytes(300)
      receipt = import!(user.id, bytes, "game.gba", format_bytes: bytes)
      asset_set = Repo.get!(Playstead.Catalogue.AssetSet, receipt.asset_set_id)

      assert {:ok, updated} = Playstead.Catalogue.override_system(asset_set, :snes, user.id)
      assert updated.system_id == "snes"
      assert updated.system_source == "user"

      entries = Playstead.AuditLog.list(user.id)
      assert Enum.any?(entries, &(&1.event == "asset_set_system_overridden"))
    end
  end
end
