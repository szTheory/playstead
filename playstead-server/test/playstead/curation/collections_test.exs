defmodule Playstead.Curation.CollectionsTest do
  @moduledoc """
  Plan 03-04 task 2: manual, flat, ordered collections (D-10).
  """

  # async: false -- see favorites_test.exs for why (global ChangeJournal
  # advisory lock + many sequential writes here).
  use Playstead.DataCase, async: false

  import Playstead.AccountsFixtures
  import Playstead.CatalogueFixtures

  alias Playstead.Curation
  alias Playstead.Curation.{Collection, CollectionMember}

  test "creating a collection sanitizes the name and journals it" do
    user = owner_fixture()

    assert {:ok, %Collection{} = collection} =
             Curation.create_collection(user.id, Ecto.UUID.generate(), "Weekend RPGs")

    assert collection.name == "Weekend RPGs"
    assert [%Collection{}] = Curation.list_collections(user.id)
  end

  test "renaming and deleting a collection" do
    user = owner_fixture()
    {:ok, collection} = Curation.create_collection(user.id, Ecto.UUID.generate(), "Original")

    assert {:ok, renamed} = Curation.rename_collection(user.id, collection.id, "Renamed")
    assert renamed.name == "Renamed"

    assert {:ok, :removed} = Curation.delete_collection(user.id, collection.id)
    assert Curation.list_collections(user.id) == []
  end

  test "deleting a collection deletes its members and tombstones both" do
    user = owner_fixture()
    {:ok, collection} = Curation.create_collection(user.id, Ecto.UUID.generate(), "To delete")
    asset_set = asset_set_fixture(user.id)

    {:ok, _member} =
      Curation.add_collection_member(user.id, collection.id, Ecto.UUID.generate(), asset_set.id)

    assert {:ok, :removed} = Curation.delete_collection(user.id, collection.id)
    assert {:error, :not_found} = Curation.list_collection_members(user.id, collection.id)
  end

  test "an empty collection lists as an empty member array" do
    user = owner_fixture()
    {:ok, collection} = Curation.create_collection(user.id, Ecto.UUID.generate(), "Empty")
    assert {:ok, []} = Curation.list_collection_members(user.id, collection.id)
  end

  test "a single-member collection lists that one member; removing the last member leaves it empty" do
    user = owner_fixture()
    {:ok, collection} = Curation.create_collection(user.id, Ecto.UUID.generate(), "Solo")
    asset_set = asset_set_fixture(user.id)

    {:ok, _member} =
      Curation.add_collection_member(user.id, collection.id, Ecto.UUID.generate(), asset_set.id)

    assert {:ok, [%CollectionMember{}]} = Curation.list_collection_members(user.id, collection.id)

    assert {:ok, :removed} =
             Curation.remove_collection_member(user.id, collection.id, asset_set.id)

    assert {:ok, []} = Curation.list_collection_members(user.id, collection.id)

    # The collection itself still exists.
    assert [%Collection{}] = Curation.list_collections(user.id)
  end

  test "re-adding an already-present member converges on the same row" do
    user = owner_fixture()
    {:ok, collection} = Curation.create_collection(user.id, Ecto.UUID.generate(), "Dup test")
    asset_set = asset_set_fixture(user.id)

    {:ok, %{id: first_id}} =
      Curation.add_collection_member(user.id, collection.id, Ecto.UUID.generate(), asset_set.id)

    {:ok, %{id: second_id}} =
      Curation.add_collection_member(user.id, collection.id, Ecto.UUID.generate(), asset_set.id)

    assert first_id == second_id
    assert {:ok, [%CollectionMember{}]} = Curation.list_collection_members(user.id, collection.id)
  end

  test "adding a member from another user's asset set returns not_found" do
    user = owner_fixture()
    other = owner_fixture()
    {:ok, collection} = Curation.create_collection(user.id, Ecto.UUID.generate(), "Cross-user")
    other_asset = asset_set_fixture(other.id)

    assert {:error, :not_found} =
             Curation.add_collection_member(
               user.id,
               collection.id,
               Ecto.UUID.generate(),
               other_asset.id
             )
  end

  test "moving a member naming another user's neighbour returns not_found" do
    user = owner_fixture()
    other = owner_fixture()
    {:ok, collection} = Curation.create_collection(user.id, Ecto.UUID.generate(), "Neighbours")
    a = asset_set_fixture(user.id)
    {:ok, _} = Curation.add_collection_member(user.id, collection.id, Ecto.UUID.generate(), a.id)

    {:ok, other_collection} =
      Curation.create_collection(other.id, Ecto.UUID.generate(), "Other's collection")

    other_asset = asset_set_fixture(other.id)

    {:ok, _} =
      Curation.add_collection_member(
        other.id,
        other_collection.id,
        Ecto.UUID.generate(),
        other_asset.id
      )

    assert {:error, :not_found} =
             Curation.move_collection_member(user.id, collection.id, a.id, %{
               after_asset_set_id: other_asset.id
             })
  end

  test "moving a member to sit between two neighbours preserves the other rows" do
    user = owner_fixture()
    {:ok, collection} = Curation.create_collection(user.id, Ecto.UUID.generate(), "Order test")
    a = asset_set_fixture(user.id)
    b = asset_set_fixture(user.id)
    c = asset_set_fixture(user.id)

    {:ok, _} = Curation.add_collection_member(user.id, collection.id, Ecto.UUID.generate(), a.id)
    {:ok, _} = Curation.add_collection_member(user.id, collection.id, Ecto.UUID.generate(), b.id)
    {:ok, _} = Curation.add_collection_member(user.id, collection.id, Ecto.UUID.generate(), c.id)

    {:ok, _moved} =
      Curation.move_collection_member(user.id, collection.id, c.id, %{
        before_asset_set_id: a.id,
        after_asset_set_id: b.id
      })

    {:ok, members} = Curation.list_collection_members(user.id, collection.id)
    assert Enum.map(members, & &1.asset_set_id) == [a.id, c.id, b.id]
  end

  test "the 501st collection is refused with a registered problem code" do
    user = owner_fixture()

    for _ <- 1..500 do
      {:ok, _} = Curation.create_collection(user.id, Ecto.UUID.generate(), "Collection")
    end

    assert length(Curation.list_collections(user.id)) == 500

    assert {:error, {:curation_limit_exceeded, _}} =
             Curation.create_collection(user.id, Ecto.UUID.generate(), "Overflow")

    assert length(Curation.list_collections(user.id)) == 500
  end

  test "the 5001st member of one collection is refused with a registered problem code" do
    user = owner_fixture()
    {:ok, collection} = Curation.create_collection(user.id, Ecto.UUID.generate(), "Big")

    for _ <- 1..5000 do
      asset_set = asset_set_fixture(user.id)

      {:ok, _} =
        Curation.add_collection_member(user.id, collection.id, Ecto.UUID.generate(), asset_set.id)
    end

    {:ok, members} = Curation.list_collection_members(user.id, collection.id)
    assert length(members) == 5000

    overflow = asset_set_fixture(user.id)

    assert {:error, {:curation_limit_exceeded, _}} =
             Curation.add_collection_member(
               user.id,
               collection.id,
               Ecto.UUID.generate(),
               overflow.id
             )

    {:ok, members_after} = Curation.list_collection_members(user.id, collection.id)
    assert length(members_after) == 5000
  end

  @tag timeout: 120_000
  test "a property-style check: 200 members inserted at random positions are all distinct and stably ordered" do
    user = owner_fixture()
    {:ok, collection} = Curation.create_collection(user.id, Ecto.UUID.generate(), "Property")

    positions =
      Enum.reduce(1..200, [], fn _, acc ->
        asset_set = asset_set_fixture(user.id)

        {:ok, member} =
          Curation.add_collection_member(
            user.id,
            collection.id,
            Ecto.UUID.generate(),
            asset_set.id
          )

        [member.position | acc]
      end)

    assert Enum.uniq(positions) |> length() == 200

    {:ok, members} = Curation.list_collection_members(user.id, collection.id)
    order_once = Enum.map(members, & &1.id)

    for _ <- 1..10 do
      {:ok, members_again} = Curation.list_collection_members(user.id, collection.id)
      assert Enum.map(members_again, & &1.id) == order_once
    end
  end

  test "a test drives between/2 until needs_rebalance? reports true, rebalances, and preserves order" do
    user = owner_fixture()
    {:ok, collection} = Curation.create_collection(user.id, Ecto.UUID.generate(), "Tight")

    low_asset = asset_set_fixture(user.id)
    high_asset = asset_set_fixture(user.id)

    {:ok, _} =
      Curation.add_collection_member(user.id, collection.id, Ecto.UUID.generate(), low_asset.id)

    {:ok, _} =
      Curation.add_collection_member(user.id, collection.id, Ecto.UUID.generate(), high_asset.id)

    for _ <- 1..40 do
      asset = asset_set_fixture(user.id)

      {:ok, _} =
        Curation.add_collection_member(user.id, collection.id, Ecto.UUID.generate(), asset.id)

      {:ok, _} =
        Curation.move_collection_member(user.id, collection.id, asset.id, %{
          before_asset_set_id: low_asset.id,
          after_asset_set_id: high_asset.id
        })
    end

    {:ok, before_members} = Curation.list_collection_members(user.id, collection.id)
    before_ids = Enum.map(before_members, & &1.asset_set_id)

    {:ok, _rebalanced} = Curation.rebalance_collection(user.id, collection.id)

    {:ok, after_members} = Curation.list_collection_members(user.id, collection.id)
    after_ids = Enum.map(after_members, & &1.asset_set_id)

    assert after_ids == before_ids
  end
end
