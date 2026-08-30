defmodule Playstead.Attention.UnknownSystemTest do
  @moduledoc """
  Behaviour proof for gap 1 of 02-VERIFICATION.md (task 2 of
  02-09-PLAN.md): a real import with no extension claim and no header
  claim lands exactly one grouped `unknown_system` inbox item, and both
  of D-26's quiet `unrecognized` reasons (`no_reference_installed`,
  `no_match`) have live producers while staying out of the inbox.
  """
  use Playstead.DataCase, async: true

  import Playstead.AccountsFixtures

  alias Playstead.Attention
  alias Playstead.Blobs
  alias Playstead.Import
  alias Playstead.Import.{Session, SourceFile}
  alias Playstead.Recognition.{DatPack, ReferenceEntry}
  alias Playstead.Repo

  setup do
    File.mkdir_p!(Playstead.Blobs.Store.LocalDisk.blob_path())
    :ok
  end

  defp import_bytes(user, name, bytes, opts \\ []) do
    {:ok, status, meta} = Blobs.put_stream([bytes], byte_size(bytes))

    Import.import_single(
      user.id,
      %{original_name: name, origin: "upload", size_bytes: byte_size(bytes)},
      {status, meta},
      Keyword.put(opts, :format_bytes, bytes)
    )
  end

  defp create_session(user, id) do
    %Session{}
    |> Session.create_changeset(%{id: id, user_id: user.id, origin: "inbox"})
    |> Repo.insert!()
  end

  defp stage_and_complete(user, session_id, name, bytes) do
    {:ok, status, meta} = Blobs.put_stream([bytes], byte_size(bytes))

    {:ok, source_file} =
      %SourceFile{}
      |> SourceFile.stage_changeset(%{
        user_id: user.id,
        import_session_id: session_id,
        original_name: name,
        origin: "inbox",
        relative_path: name,
        size_bytes: byte_size(bytes)
      })
      |> Repo.insert()

    Import.complete_staged_file(user.id, source_file, {status, meta}, format_bytes: bytes)
  end

  # Random bytes with no recognized extension: no validator matches
  # these bytes, so format_result is {:unknown, :none, _} and the
  # extension guess is nil — the genuine "no claim on either axis"
  # case D-16 defines.
  defp no_claim_bytes(n \\ 300), do: :crypto.strong_rand_bytes(n)

  describe "one item for a single file with no claim on either axis" do
    test "a single upload with no extension claim and no header claim yields exactly one open item" do
      user = owner_fixture()
      {:ok, receipt} = import_bytes(user, "mystery.dat", no_claim_bytes())

      # No pack is installed, so the receipt also carries the quiet
      # no_reference_installed reason — but the attention item raised is
      # the more specific unknown_system one (Derive consults
      # unknown_system? before outcome/reason).
      assert receipt.outcome == "unrecognized"
      assert receipt.reason == "no_reference_installed"
      assert Attention.count(user.id) == 1
      [item] = Map.get(Attention.list_items(user.id), "unknown_system")
      assert item.reason == "unknown_system"
      assert item.count == 1
    end
  end

  describe "grouping (D-26, T-02-64)" do
    test "three no-claim files staged in one session yield one open item with count 3" do
      user = owner_fixture()
      session_id = "sess-unknown-system"
      create_session(user, session_id)

      for i <- 1..3 do
        {:ok, _receipt} =
          stage_and_complete(user, session_id, "unknown#{i}.dat", no_claim_bytes(64) <> <<i>>)
      end

      assert Attention.count(user.id) == 1
      [item] = Map.get(Attention.list_items(user.id), "unknown_system")
      assert item.count == 3
    end

    test "two no-claim files imported as separate single uploads yield two open items" do
      user = owner_fixture()

      {:ok, _r1} = import_bytes(user, "one.dat", no_claim_bytes())
      {:ok, _r2} = import_bytes(user, "two.dat", no_claim_bytes())

      assert Attention.count(user.id) == 2
      items = Map.get(Attention.list_items(user.id), "unknown_system")
      assert length(items) == 2
    end
  end

  describe "quiet reasons stay out of the inbox (D-26)" do
    test "a supported format with no DatPack installed yields no_reference_installed and zero items" do
      user = owner_fixture()
      bytes = Playstead.RomFixtures.valid_gba()

      {:ok, receipt} = import_bytes(user, "game.gba", bytes)

      assert receipt.outcome == "unrecognized"
      assert receipt.reason == "no_reference_installed"
      assert Attention.count(user.id) == 0
    end

    test "a supported format with a pack installed that matches nothing yields no_match and zero items" do
      user = owner_fixture()
      bytes = Playstead.RomFixtures.valid_gba()

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
          name: "Unrelated Game",
          sha1: :crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)
        })
        |> Repo.insert()

      {:ok, receipt} = import_bytes(user, "game.gba", bytes)

      assert receipt.outcome == "unrecognized"
      assert receipt.reason == "no_match"
      assert Attention.count(user.id) == 0
    end
  end

  describe "an archive still gets its own reason, not unknown_system" do
    test "a zip import yields the archives-kept-unopened item, not an unknown-system one" do
      user = owner_fixture()
      bytes = Playstead.RomFixtures.zip_magic()

      {:ok, receipt} = import_bytes(user, "collection.zip", bytes)

      assert receipt.outcome == "unrecognized"
      assert receipt.reason == "archive_not_opened"
      assert Attention.count(user.id) == 1
      assert Map.get(Attention.list_items(user.id), "unknown_system") == nil
      [item] = Map.get(Attention.list_items(user.id), "archives_kept_unopened")
      assert item.reason == "archives_kept_unopened"
    end
  end
end
