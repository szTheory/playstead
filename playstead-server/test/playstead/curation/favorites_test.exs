defmodule Playstead.Curation.FavoritesTest do
  @moduledoc """
  Plan 03-04 task 1: server-canonical favorites riding the change
  journal (D-07/D-08/D-09).
  """

  use Playstead.DataCase, async: true

  import Playstead.AccountsFixtures
  import Playstead.CatalogueFixtures

  alias Playstead.Curation
  alias Playstead.Curation.Favorite
  alias Playstead.Sync.ChangeJournal

  test "favoriting an asset set creates one row and one journal entry, atomically" do
    user = owner_fixture()
    asset_set = asset_set_fixture(user.id)
    id = Ecto.UUID.generate()

    assert {:ok, %Favorite{} = favorite} = Curation.add_favorite(user.id, id, asset_set.id)
    assert favorite.id == id
    assert favorite.asset_set_id == asset_set.id

    assert [%Favorite{}] = Curation.list_favorites(user.id)

    entries = ChangeJournal.read_after(user.id, 0, 10)
    assert [entry] = Enum.filter(entries, &(&1.entity_kind == "curation"))
    assert entry.entity_id == id
    assert entry.operation == "upsert"
    assert entry.payload["type"] == "favorite"
    assert entry.payload["asset_set_id"] == asset_set.id
  end

  test "the row and its journal entry are not created when the enclosing transaction rolls back" do
    user = owner_fixture()
    asset_set = asset_set_fixture(user.id)

    Repo.transaction(fn ->
      assert {:ok, _favorite} =
               Curation.add_favorite(user.id, Ecto.UUID.generate(), asset_set.id)

      Repo.rollback(:forced)
    end)

    assert Curation.list_favorites(user.id) == []
    assert ChangeJournal.read_after(user.id, 0, 10) == []
  end

  test "repeating the identical favorite intent leaves exactly one row and returns success both times" do
    user = owner_fixture()
    asset_set = asset_set_fixture(user.id)

    assert {:ok, %Favorite{id: first_id}} =
             Curation.add_favorite(user.id, Ecto.UUID.generate(), asset_set.id)

    assert {:ok, %Favorite{id: second_id}} =
             Curation.add_favorite(user.id, Ecto.UUID.generate(), asset_set.id)

    # The row converges on the original id via the (user_id, asset_set_id)
    # unique index — a second client-supplied id never creates a second row.
    assert first_id == second_id
    assert [%Favorite{}] = Curation.list_favorites(user.id)
  end

  test "a favorite request naming another user's asset set returns not_found" do
    owner = owner_fixture()
    other = owner_fixture()
    asset_set = asset_set_fixture(other.id)

    assert {:error, :not_found} =
             Curation.add_favorite(owner.id, Ecto.UUID.generate(), asset_set.id)
  end

  test "removing a favorite deletes the row and appends a tombstone with an empty payload" do
    user = owner_fixture()
    asset_set = asset_set_fixture(user.id)
    {:ok, favorite} = Curation.add_favorite(user.id, Ecto.UUID.generate(), asset_set.id)

    assert {:ok, :removed} = Curation.remove_favorite(user.id, asset_set.id)
    assert Curation.list_favorites(user.id) == []

    entries = ChangeJournal.read_after(user.id, 0, 10)
    tombstone = Enum.find(entries, &(&1.entity_id == favorite.id and &1.operation == "tombstone"))
    assert tombstone
    assert tombstone.payload == %{}
  end

  test "removing an already-removed favorite is accepted and changes nothing" do
    user = owner_fixture()
    asset_set = asset_set_fixture(user.id)

    assert {:ok, :removed} = Curation.remove_favorite(user.id, asset_set.id)
    assert Curation.list_favorites(user.id) == []
  end

  test "a user with no curation rows has an empty favorites list" do
    user = owner_fixture()
    assert Curation.list_favorites(user.id) == []
  end
end
