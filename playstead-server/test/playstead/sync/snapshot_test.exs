defmodule Playstead.Sync.SnapshotTest do
  use Playstead.DataCase, async: true

  import Playstead.AccountsFixtures
  import Playstead.CatalogueFixtures
  import Playstead.PairingFixtures

  alias Playstead.Curation
  alias Playstead.Sync.{Cursor, Snapshot}

  test "pages with page_size, reports has_more and next_after_id, and pins as_of across pages" do
    scope = user_scope_fixture()
    devices = for _ <- 1..5, do: device_fixture(scope).device
    ids = devices |> Enum.map(& &1.id) |> Enum.sort()

    {:ok, page1} = Snapshot.read(scope.user.id, page_size: 2)
    assert page1.has_more
    assert Enum.map(page1.entries, & &1.entity_id) == Enum.take(ids, 2)
    assert page1.next_after_id == Enum.at(ids, 1)
    {:ok, seq} = Cursor.decode(page1.cursor)

    {:ok, page2} =
      Snapshot.read(scope.user.id, page_size: 2, as_of: seq, after_id: page1.next_after_id)

    assert page2.has_more
    assert Enum.map(page2.entries, & &1.entity_id) == Enum.slice(ids, 2, 2)
    assert page2.cursor == page1.cursor

    {:ok, page3} =
      Snapshot.read(scope.user.id, page_size: 2, as_of: seq, after_id: page2.next_after_id)

    refute page3.has_more
    assert Enum.map(page3.entries, & &1.entity_id) == Enum.drop(ids, 4)
    assert page3.next_after_id == nil
  end

  test "the default page size is 200 and the between_reads hook is a no-op by default" do
    scope = user_scope_fixture()
    _ = device_fixture(scope)
    {:ok, page} = Snapshot.read(scope.user.id)
    refute page.has_more
    assert length(page.entries) == 1
  end

  test "an empty journal anchors the snapshot on now and yields cursor 0" do
    scope = user_scope_fixture()
    {:ok, page} = Snapshot.read(scope.user.id)
    assert page.entries == []
    assert {:ok, 0} = Cursor.decode(page.cursor)
  end

  test "a user with no curation rows gets an empty curation branch" do
    scope = user_scope_fixture()
    {:ok, page} = Snapshot.read(scope.user.id)
    assert page.curation == []
  end

  test "the curation branch lists a favorite from the same transaction as catalogue and job" do
    scope = user_scope_fixture()
    asset_set = asset_set_fixture(scope.user.id)
    {:ok, _favorite} = Curation.add_favorite(scope.user.id, Ecto.UUID.generate(), asset_set.id)

    {:ok, page} = Snapshot.read(scope.user.id)

    assert [%{type: "favorite", asset_set_id: id}] = page.curation
    assert id == asset_set.id
    assert is_list(page.catalogue)
    assert is_list(page.job)
  end
end
