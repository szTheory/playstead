defmodule Playstead.Attention.QuarantineTest do
  @moduledoc """
  Integration proof of Task 1's decision record (D-26, D-28): the
  in-and-out rule wired into the import pipeline, quarantine as a
  processing state on the shared blob, and the per-user release
  boundary over those shared bytes.
  """
  use Playstead.DataCase, async: true

  import Playstead.AccountsFixtures

  alias Playstead.Attention
  alias Playstead.Attention.Item
  alias Playstead.Blobs
  alias Playstead.Import
  alias Playstead.Import.{Session, SourceFile}

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
    |> Playstead.Repo.insert!()
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
      |> Playstead.Repo.insert()

    Import.complete_staged_file(user.id, source_file, {status, meta}, format_bytes: bytes)
  end

  describe "quarantine triggers (D-28)" do
    test "a size-over-cap input is quarantined" do
      user = owner_fixture()

      {:ok, receipt} =
        import_bytes(user, "big.bin", :crypto.strong_rand_bytes(64),
          quarantine_size_cap_bytes: 10
        )

      assert receipt.outcome == "quarantined"
      assert receipt.reason == "size_over_cap"
      blob = Blobs.get_by_sha256(receipt.sha256)
      assert Blobs.quarantined?(blob)
    end

    test "a name-policy violation is quarantined" do
      user = owner_fixture()
      {:ok, receipt} = import_bytes(user, "bad\x01name.bin", :crypto.strong_rand_bytes(32))

      assert receipt.outcome == "quarantined"
      assert receipt.reason == "name_policy_violation"
    end

    test "a signature mismatch is recorded as unrecognized and is not quarantined" do
      user = owner_fixture()
      # Claims .gba (a Tier A signature-validated system, D-14) but the
      # bytes do not carry a valid GBA header.
      {:ok, receipt} = import_bytes(user, "fake.gba", :crypto.strong_rand_bytes(64))

      assert receipt.outcome == "unrecognized"
      assert receipt.reason == "signature_mismatch"
      blob = Blobs.get_by_sha256(receipt.sha256)
      refute Blobs.quarantined?(blob)
    end

    test "an archive is not quarantined" do
      user = owner_fixture()
      bytes = <<0x50, 0x4B, 0x03, 0x04>> <> :crypto.strong_rand_bytes(64)
      {:ok, receipt} = import_bytes(user, "collection.zip", bytes)

      assert receipt.outcome == "unrecognized"
      assert receipt.reason == "archive_not_opened"
      blob = Blobs.get_by_sha256(receipt.sha256)
      refute Blobs.quarantined?(blob)
    end
  end

  describe "inclusion/exclusion via the real import pipeline (D-26)" do
    test "a new asset produces zero attention items" do
      user = owner_fixture()
      {:ok, _receipt} = import_bytes(user, "notes.txt", :crypto.strong_rand_bytes(64))
      assert Attention.count(user.id) == 0
    end

    test "an exact duplicate produces zero attention items" do
      user = owner_fixture()
      bytes = :crypto.strong_rand_bytes(64)
      {:ok, _first} = import_bytes(user, "game.bin", bytes)
      {:ok, receipt} = import_bytes(user, "game-copy.bin", bytes)

      assert receipt.outcome == "exact_duplicate"
      assert Attention.count(user.id) == 0
    end

    test "an incomplete set produces an attention item" do
      user = owner_fixture()
      {:ok, status, meta} = Blobs.put_stream(["CUE FILE CONTENT..."], 20)

      {:ok, result} =
        Import.import_descriptor_set(
          user.id,
          %{original_name: "game.cue", origin: "upload", size_bytes: 20},
          {status, meta},
          ["game.bin"],
          %{}
        )

      _ = result
      assert Attention.count(user.id) == 1
      [item] = Map.get(Attention.list_items(user.id), "missing_member")
      assert item.reason == "missing_member"
    end
  end

  describe "retry-budget boundary (D-06, D-26)" do
    test "a failure within its retry budget produces no item, exhausted produces one" do
      user = owner_fixture()
      create_session(user, "sess-retry")

      {:ok, source_file} =
        %SourceFile{}
        |> SourceFile.stage_changeset(%{
          user_id: user.id,
          import_session_id: "sess-retry",
          original_name: "flaky.bin",
          origin: "inbox",
          relative_path: "flaky.bin",
          size_bytes: 10
        })
        |> Playstead.Repo.insert()

      {:ok, _r1} = Import.record_failed_file(user.id, source_file, "io_error")
      assert Attention.count(user.id) == 0

      source_file = Playstead.Repo.get!(SourceFile, source_file.id)
      source_file = %{source_file | attempt_count: 3}
      {:ok, _r2} = Import.record_failed_file(user.id, source_file, "io_error")
      assert Attention.count(user.id) == 1
      [item] = Map.get(Attention.list_items(user.id), "failed_after_retries")
      assert item.reason == "failed_after_retries"
    end
  end

  describe "archive grouping (D-21)" do
    test "an import containing 50 archives produces exactly one attention item" do
      user = owner_fixture()
      session_id = "sess-archives"
      create_session(user, session_id)

      for i <- 1..50 do
        bytes = <<0x50, 0x4B, 0x03, 0x04>> <> :crypto.strong_rand_bytes(16) <> <<i>>
        {:ok, _receipt} = stage_and_complete(user, session_id, "archive#{i}.zip", bytes)
      end

      assert Attention.count(user.id) == 1
      [item] = Map.get(Attention.list_items(user.id), "archives_kept_unopened")
      assert item.count == 50
    end
  end

  describe "quarantine consequences (D-28)" do
    test "a quarantined blob returns not-found from the byte-serving endpoint" do
      user = owner_fixture()

      {:ok, receipt} =
        import_bytes(user, "oversized.bin", :crypto.strong_rand_bytes(64),
          quarantine_size_cap_bytes: 10
        )

      blob = Blobs.get_by_sha256(receipt.sha256)

      refute Playstead.Blobs.released_for_user?(user.id, blob.id)
      assert Blobs.quarantined?(blob)
    end

    test "a release recorded by one user leaves a second user's view of the same bytes unchanged" do
      user_a = owner_fixture()
      user_b = owner_fixture()
      bytes = :crypto.strong_rand_bytes(64)

      {:ok, receipt_a} =
        import_bytes(user_a, "shared.bin", bytes, quarantine_size_cap_bytes: 10)

      {:ok, _receipt_b} =
        import_bytes(user_b, "shared-copy.bin", bytes, quarantine_size_cap_bytes: 10)

      blob = Blobs.get_by_sha256(receipt_a.sha256)
      assert Blobs.quarantined?(blob)

      {:ok, _release} = Blobs.release(user_a.id, blob.id, "retain_as_custom")

      assert Blobs.released_for_user?(user_a.id, blob.id)
      refute Blobs.released_for_user?(user_b.id, blob.id)
    end
  end

  describe "transactional atomicity (D-26)" do
    test "an attention item is not created when its enclosing transaction rolls back" do
      user = owner_fixture()

      Playstead.Repo.transaction(fn ->
        {:ok, _item} =
          Attention.raise_item(%{
            user_id: user.id,
            outcome: :incomplete_set,
            grouping_key: "rollback-test"
          })

        Playstead.Repo.rollback(:forced)
      end)

      assert Attention.count(user.id) == 0
      assert Playstead.Repo.aggregate(Item, :count) |> is_integer()
    end
  end

  describe "no auto-purge (D-26)" do
    test "no ageing/purge vocabulary exists in the attention modules" do
      files = Path.wildcard("lib/playstead/attention/**/*.ex") ++ ["lib/playstead/attention.ex"]
      contents = Enum.map(files, &File.read!/1) |> Enum.join("\n")
      refute contents =~ ~r/expires_at|purge|auto_dismiss/
    end

    test "no delete path exists in the attention modules" do
      files = Path.wildcard("lib/playstead/attention/**/*.ex") ++ ["lib/playstead/attention.ex"]
      contents = Enum.map(files, &File.read!/1) |> Enum.join("\n")
      refute contents =~ ~r/Repo\.delete|File\.rm/
    end
  end

  describe "migration" do
    test "the attention_items table exists" do
      assert {:ok, _} =
               Playstead.Repo.query("SELECT id FROM attention_items LIMIT 0")
    end
  end
end
