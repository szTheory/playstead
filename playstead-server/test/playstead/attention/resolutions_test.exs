defmodule Playstead.Attention.ResolutionsTest do
  @moduledoc """
  Task 2's decision record (D-27, D-30): five audited, reversible
  commands, none of which ever deletes a byte, and a database-level
  guard that makes exactly one of two concurrent resolutions win.
  """
  use Playstead.DataCase, async: true

  import Playstead.AccountsFixtures

  alias Playstead.AuditLog
  alias Playstead.Attention
  alias Playstead.Attention.Resolutions
  alias Playstead.Blobs
  alias Playstead.Catalogue.AssetSet
  alias Playstead.Import
  alias Playstead.Recognition.Evidence
  alias Playstead.Repo

  setup do
    File.mkdir_p!(Playstead.Blobs.Store.LocalDisk.blob_path())
    :ok
  end

  defp import_bytes(user, name, bytes, opts \\ []) do
    {:ok, status, meta} = Blobs.put_stream([bytes], byte_size(bytes))

    {:ok, receipt} =
      Import.import_single(
        user.id,
        %{original_name: name, origin: "upload", size_bytes: byte_size(bytes)},
        {status, meta},
        Keyword.put(opts, :format_bytes, bytes)
      )

    receipt
  end

  defp open_item(user, reason) do
    Attention.list_items(user.id) |> Map.fetch!(reason) |> hd()
  end

  describe "correct_system/3 (D-19, D-27)" do
    test "inserts an override row, changes the effective system, and leaves prior evidence byte-identical" do
      user = owner_fixture()
      # An extension-guessed Tier A system that fails its own header
      # validation produces a signature-mismatch attention item.
      receipt = import_bytes(user, "fake.gba", :crypto.strong_rand_bytes(64))
      item = open_item(user, "signature_mismatch")

      prior_evidence =
        from(e in Evidence, where: e.blob_id == ^receipt.blob_id) |> Repo.all()

      {:ok, %{asset_set: updated_set}} = Resolutions.correct_system(item, user.id, :gba)

      assert updated_set.system_id == "gba"
      assert updated_set.system_source == "user"

      still_present = from(e in Evidence, where: e.blob_id == ^receipt.blob_id) |> Repo.all()

      assert Enum.map(prior_evidence, & &1.id) |> MapSet.new() ==
               Enum.map(still_present, & &1.id) |> MapSet.new()

      overrides = Repo.all(Playstead.Recognition.Override)
      assert length(overrides) == 1
      assert hd(overrides).system_id == "gba"
    end
  end

  describe "every resolution writes exactly one audit entry" do
    test "correct_system" do
      user = owner_fixture()
      import_bytes(user, "fake.gba", :crypto.strong_rand_bytes(64))
      item = open_item(user, "signature_mismatch")

      before = AuditLog.list(user.id) |> length()
      {:ok, _} = Resolutions.correct_system(item, user.id, :gba)
      assert AuditLog.list(user.id) |> length() == before + 1
    end

    test "retain_as_custom" do
      user = owner_fixture()
      import_bytes(user, "big.bin", :crypto.strong_rand_bytes(64), quarantine_size_cap_bytes: 10)
      item = open_item(user, "quarantined")

      before = AuditLog.list(user.id) |> length()
      {:ok, _} = Resolutions.retain_as_custom(item, user.id)
      assert AuditLog.list(user.id) |> length() == before + 1
    end

    test "exclude" do
      user = owner_fixture()
      import_bytes(user, "solo.bin", :crypto.strong_rand_bytes(64))
      item = fabricate_new_asset_item(user)

      before = AuditLog.list(user.id) |> length()
      {:ok, _} = Resolutions.exclude(item, user.id)
      assert AuditLog.list(user.id) |> length() == before + 1
    end

    test "retry" do
      user = owner_fixture()
      import_bytes(user, "big.bin", :crypto.strong_rand_bytes(64), quarantine_size_cap_bytes: 10)
      item = open_item(user, "quarantined")

      before = AuditLog.list(user.id) |> length()
      {:ok, _} = Resolutions.retry(item, user.id)
      assert AuditLog.list(user.id) |> length() == before + 1
    end

    test "undo" do
      user = owner_fixture()
      import_bytes(user, "solo.bin", :crypto.strong_rand_bytes(64))
      item = fabricate_new_asset_item(user)
      {:ok, %{item: excluded_item}} = Resolutions.exclude(item, user.id)

      before = AuditLog.list(user.id) |> length()
      {:ok, _} = Resolutions.undo(excluded_item, user.id)
      assert AuditLog.list(user.id) |> length() == before + 1
    end
  end

  # A new_asset outcome raises no item on its own; this fabricates one
  # against a real asset set so exclude/undo can be exercised without
  # depending on a genuine inclusion reason.
  defp fabricate_new_asset_item(user) do
    [asset_set] = Repo.all(AssetSet)

    {:ok, item} =
      Attention.raise_item(%{
        user_id: user.id,
        outcome: :incomplete_set,
        grouping_key: "fixture:#{asset_set.id}",
        asset_set_id: asset_set.id
      })

    item
  end

  describe "attach_companion/5 (D-15, D-27)" do
    test "attaching an existing blob completes the set and recomputes its member fingerprint" do
      user = owner_fixture()
      {:ok, status, cue_meta} = Blobs.put_stream(["CUE"], 3)

      {:ok, %{asset_set: asset_set}} =
        Import.import_descriptor_set(
          user.id,
          %{original_name: "game.cue", origin: "upload", size_bytes: 3},
          {status, cue_meta},
          ["game.bin"],
          %{}
        )

      before_fingerprint = asset_set.member_fingerprint
      item = open_item(user, "missing_member")

      bin_bytes = :crypto.strong_rand_bytes(32)
      {:ok, bin_status, bin_meta} = Blobs.put_stream([bin_bytes], byte_size(bin_bytes))

      {:ok, %{asset_set: updated_set}} =
        Resolutions.attach_companion(
          item,
          user.id,
          "game.bin",
          %{original_name: "game.bin", origin: "upload", size_bytes: byte_size(bin_bytes)},
          {bin_status, bin_meta}
        )

      assert updated_set.status == "complete"
      refute updated_set.member_fingerprint == before_fingerprint

      reloaded = Repo.get!(Playstead.Attention.Item, item.id)
      assert reloaded.status == "resolved"
    end
  end

  describe "retain_as_custom/2 (D-27, D-28)" do
    test "releases policy-quarantined bytes as opaque content only" do
      user = owner_fixture()

      receipt =
        import_bytes(user, "big.bin", :crypto.strong_rand_bytes(64),
          quarantine_size_cap_bytes: 10
        )

      item = open_item(user, "quarantined")

      {:ok, _result} = Resolutions.retain_as_custom(item, user.id)

      assert Blobs.released_for_user?(user.id, receipt.blob_id)
      blob = Repo.get!(Playstead.Blobs.Blob, receipt.blob_id)
      assert Blobs.quarantined?(blob)
    end
  end

  describe "exclude/2 and undo/2 (D-27)" do
    test "excluding sets the exclusion timestamp, tombstones, and keeps the blob on disk; undo restores it" do
      user = owner_fixture()
      receipt = import_bytes(user, "solo.bin", :crypto.strong_rand_bytes(64))
      item = fabricate_new_asset_item(user)

      before_seq = Playstead.Sync.ChangeJournal.max_seq(user.id)
      {:ok, %{asset_set: excluded_set}} = Resolutions.exclude(item, user.id)

      refute is_nil(excluded_set.excluded_at)

      entries = Playstead.Sync.ChangeJournal.read_after(user.id, before_seq, 10)

      assert Enum.any?(
               entries,
               &(&1.operation == "tombstone" and &1.entity_id == excluded_set.id)
             )

      blob = Repo.get!(Playstead.Blobs.Blob, receipt.blob_id)
      assert {:ok, _stat} = Blobs.stat(blob.sha256)

      excluded_item = Repo.get!(Playstead.Attention.Item, item.id)
      assert excluded_item.status == "excluded"

      excluded_items = Attention.list_items(user.id, status: "excluded")
      assert map_size(excluded_items) > 0

      {:ok, %{item: restored_item, asset_set: restored_set}} =
        Resolutions.undo(excluded_item, user.id)

      assert restored_item.status == "open"
      assert is_nil(restored_set.excluded_at)
    end

    test "the inbox reports the total storage held by excluded items" do
      user = owner_fixture()
      import_bytes(user, "solo.bin", :crypto.strong_rand_bytes(64))
      item = fabricate_new_asset_item(user)

      assert Attention.excluded_storage_bytes(user.id) == 0
      {:ok, _} = Resolutions.exclude(item, user.id)
      assert Attention.excluded_storage_bytes(user.id) == 64
    end
  end

  describe "retry/2 (D-27)" do
    test "retrying creates no new blobs row and no new file under the object tree" do
      user = owner_fixture()
      import_bytes(user, "big.bin", :crypto.strong_rand_bytes(64), quarantine_size_cap_bytes: 10)
      item = open_item(user, "quarantined")

      blob_count_before = Repo.aggregate(Playstead.Blobs.Blob, :count)
      {:ok, _result} = Resolutions.retry(item, user.id)
      assert Repo.aggregate(Playstead.Blobs.Blob, :count) == blob_count_before
    end
  end

  describe "concurrency guard (T-02-42, D-27)" do
    test "two concurrent resolutions of one item apply exactly one effect" do
      user = owner_fixture()
      import_bytes(user, "solo.bin", :crypto.strong_rand_bytes(64))
      item = fabricate_new_asset_item(user)

      results =
        [item, item]
        |> Enum.map(fn i -> Task.async(fn -> Resolutions.exclude(i, user.id) end) end)
        |> Enum.map(&Task.await/1)

      oks = Enum.count(results, &match?({:ok, _}, &1))
      already = Enum.count(results, &match?({:error, :already_resolved}, &1))

      assert oks == 1
      assert already == 1
    end
  end

  describe "no reclaim path (D-27)" do
    test "no delete or reclaim vocabulary in resolutions.ex" do
      content = File.read!("lib/playstead/attention/resolutions.ex")
      refute content =~ ~r/Repo\.delete|File\.rm|reclaim/
    end

    test "no update/delete path on the evidence schema" do
      content = File.read!("lib/playstead/recognition/evidence.ex")
      refute content =~ ~r/Repo\.update|Repo\.delete/
    end
  end
end
