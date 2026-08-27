defmodule Playstead.Sync.ChangeJournalTest do
  use Playstead.DataCase, async: true

  import Playstead.AccountsFixtures
  import Playstead.PairingFixtures
  import Playstead.SyncFixtures

  alias Playstead.Pairing
  alias Playstead.Sync.{ChangeJournal, EntityKind, Entry}

  describe "EntityKind.all/0" do
    test "returns exactly the six registered kinds" do
      assert EntityKind.all() == [:device, :pairing, :catalogue, :job, :transfer, :save]
    end

    test "valid?/1 accepts atoms and strings for registered kinds" do
      assert EntityKind.valid?(:device)
      assert EntityKind.valid?("device")
      refute EntityKind.valid?(:not_a_kind)
      refute EntityKind.valid?("not_a_kind")
    end
  end

  describe "append/4" do
    test "assigns strictly increasing sequence values" do
      user = owner_fixture()

      entry1 = journal_entry_fixture(user.id, :device, "device-1", %{name: "First"})
      entry2 = journal_entry_fixture(user.id, :device, "device-1", %{name: "Renamed"})

      assert entry2.seq > entry1.seq
    end

    test "rejects an unregistered entity kind" do
      user = owner_fixture()

      assert {:error, changeset} = ChangeJournal.append(user.id, :not_a_kind, "x", %{})
      assert "is not a registered entity kind" in errors_on(changeset).entity_kind
    end

    test "records an upsert operation with the given payload" do
      user = owner_fixture()
      entry = journal_entry_fixture(user.id, :device, "device-1", %{name: "Owner's Mac"})

      assert entry.operation == "upsert"
      assert entry.payload == %{name: "Owner's Mac"}
      assert entry.entity_kind == "device"
      assert entry.entity_id == "device-1"

      # A fresh read from the database round-trips jsonb payloads with
      # string keys regardless of what was inserted.
      [reloaded] = ChangeJournal.read_after(user.id, entry.seq - 1, 1)
      assert reloaded.payload == %{"name" => "Owner's Mac"}
    end
  end

  describe "tombstone/3" do
    test "records a deletion a resuming reader observes, with an empty payload" do
      user = owner_fixture()
      journal_entry_fixture(user.id, :device, "device-1", %{name: "Owner's Mac"})
      tombstone = journal_tombstone_fixture(user.id, :device, "device-1")

      assert tombstone.operation == "tombstone"
      assert tombstone.payload == %{}

      entries = ChangeJournal.read_after(user.id, 0, 100)
      assert Enum.any?(entries, &(&1.id == tombstone.id and &1.operation == "tombstone"))
    end
  end

  describe "read_after/3" do
    test "returns only entries for the calling scope, in sequence order" do
      owner = owner_fixture()
      other = owner_fixture()

      e1 = journal_entry_fixture(owner.id, :device, "d1", %{})
      e2 = journal_entry_fixture(owner.id, :device, "d2", %{})
      _other_entry = journal_entry_fixture(other.id, :device, "d3", %{})

      entries = ChangeJournal.read_after(owner.id, 0, 100)

      assert Enum.map(entries, & &1.id) == [e1.id, e2.id]
    end

    test "an entry for one owner is never returned to another owner's read, even with that owner's valid cursor value" do
      owner = owner_fixture()
      other = owner_fixture()

      owner_entry = journal_entry_fixture(owner.id, :device, "d1", %{})

      # `other` reads starting from before `owner_entry`'s seq — if
      # partitioning were broken, this would leak `owner_entry`.
      entries = ChangeJournal.read_after(other.id, owner_entry.seq - 1, 100)

      refute Enum.any?(entries, &(&1.id == owner_entry.id))
    end

    test "respects the limit and returns entries strictly after after_seq" do
      user = owner_fixture()
      entries = for i <- 1..5, do: journal_entry_fixture(user.id, :device, "d#{i}", %{})
      [_e1, e2, e3 | _rest] = entries

      page = ChangeJournal.read_after(user.id, e2.seq, 1)
      assert [only] = page
      assert only.id == e3.id
    end
  end

  describe "max_seq/1 and inserted_at_for/1" do
    test "max_seq/1 is 0 for a fresh user and tracks the highest seq written" do
      user = owner_fixture()
      assert ChangeJournal.max_seq(user.id) == 0

      entry = journal_entry_fixture(user.id, :device, "d1", %{})
      assert ChangeJournal.max_seq(user.id) == entry.seq
    end

    test "inserted_at_for/1 returns nil for seq 0 and the entry's timestamp otherwise" do
      user = owner_fixture()
      assert ChangeJournal.inserted_at_for(0) == nil

      entry = journal_entry_fixture(user.id, :device, "d1", %{})
      assert %DateTime{} = ChangeJournal.inserted_at_for(entry.seq)
    end
  end

  describe "Playstead.Pairing producers (D-21 wiring)" do
    test "revoking a device produces a tombstone entry a resuming reader observes" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)

      baseline = ChangeJournal.max_seq(device.user_id)

      {:ok, _revoked} = Pairing.revoke_device(scope, device.id)

      entries = ChangeJournal.read_after(device.user_id, baseline, 100)

      assert Enum.any?(entries, fn e ->
               e.entity_kind == "device" and e.entity_id == device.id and e.operation == "tombstone"
             end)
    end

    test "renaming a device produces a device upsert entry" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)

      baseline = ChangeJournal.max_seq(device.user_id)

      {:ok, _renamed} = Pairing.rename_device(scope, device.id, "New Name")

      entries = ChangeJournal.read_after(device.user_id, baseline, 100)

      assert Enum.any?(entries, fn e ->
               e.entity_kind == "device" and e.entity_id == device.id and e.operation == "upsert" and
                 e.payload["name"] == "New Name"
             end)
    end

    test "approving a pairing request produces a pairing upsert entry" do
      scope = user_scope_fixture()
      {request, _device_code} = pairing_request_fixture()

      {:ok, _approved} = Pairing.approve(scope, request.id)

      entries = ChangeJournal.read_after(scope.user.id, 0, 100)

      assert Enum.any?(entries, fn e ->
               e.entity_kind == "pairing" and e.entity_id == request.id and
                 e.payload["status"] == "approved"
             end)
    end

    test "redeeming an approved request produces device upsert and pairing upsert entries" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)

      entries = ChangeJournal.read_after(scope.user.id, 0, 100)
      kinds = Enum.map(entries, & &1.entity_kind)

      assert "device" in kinds
      assert "pairing" in kinds
      assert Enum.any?(entries, &(&1.entity_id == device.id and &1.entity_kind == "device"))
    end
  end

  describe "Entry schema" do
    test "create_changeset requires the core fields" do
      changeset = Entry.create_changeset(%Entry{}, %{})
      refute changeset.valid?
    end
  end
end
