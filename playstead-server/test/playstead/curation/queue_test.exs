defmodule Playstead.Curation.QueueTest do
  @moduledoc """
  Plan 03-04 task 2: the play queue's fractional-index ordering
  (D-07/D-09/D-10).
  """

  # async: false -- see favorites_test.exs for why (global ChangeJournal
  # advisory lock + many sequential writes here).
  use Playstead.DataCase, async: false

  import Playstead.AccountsFixtures
  import Playstead.CatalogueFixtures

  alias Playstead.Curation
  alias Playstead.Curation.QueueItem
  alias Playstead.Sync.ChangeJournal

  test "enqueuing adds one row and one journal entry" do
    user = owner_fixture()
    asset_set = asset_set_fixture(user.id)

    assert {:ok, %QueueItem{} = item} =
             Curation.enqueue(user.id, Ecto.UUID.generate(), asset_set.id)

    assert [%QueueItem{}] = Curation.list_queue(user.id)

    entries = ChangeJournal.read_after(user.id, 0, 10)
    entry = Enum.find(entries, &(&1.entity_id == item.id))
    assert entry.payload["type"] == "queue_item"
  end

  test "re-enqueuing an already-queued game converges on the same row" do
    user = owner_fixture()
    asset_set = asset_set_fixture(user.id)

    {:ok, %{id: first_id}} = Curation.enqueue(user.id, Ecto.UUID.generate(), asset_set.id)
    {:ok, %{id: second_id}} = Curation.enqueue(user.id, Ecto.UUID.generate(), asset_set.id)

    assert first_id == second_id
    assert [%QueueItem{}] = Curation.list_queue(user.id)
  end

  test "dequeuing removes the row and tombstones it; dequeuing again is a no-op" do
    user = owner_fixture()
    asset_set = asset_set_fixture(user.id)
    {:ok, item} = Curation.enqueue(user.id, Ecto.UUID.generate(), asset_set.id)

    assert {:ok, :removed} = Curation.dequeue(user.id, asset_set.id)
    assert Curation.list_queue(user.id) == []

    entries = ChangeJournal.read_after(user.id, 0, 10)
    tombstone = Enum.find(entries, &(&1.entity_id == item.id and &1.operation == "tombstone"))
    assert tombstone.payload == %{}

    assert {:ok, :removed} = Curation.dequeue(user.id, asset_set.id)
  end

  test "enqueuing another user's asset set returns not_found" do
    owner = owner_fixture()
    other = owner_fixture()
    asset_set = asset_set_fixture(other.id)

    assert {:error, :not_found} = Curation.enqueue(owner.id, Ecto.UUID.generate(), asset_set.id)
  end

  test "moving to the position an item already occupies is a no-op" do
    user = owner_fixture()
    a = asset_set_fixture(user.id)
    b = asset_set_fixture(user.id)
    c = asset_set_fixture(user.id)

    {:ok, item_a} = Curation.enqueue(user.id, Ecto.UUID.generate(), a.id)
    {:ok, _item_b} = Curation.enqueue(user.id, Ecto.UUID.generate(), b.id)
    {:ok, _item_c} = Curation.enqueue(user.id, Ecto.UUID.generate(), c.id)

    # a's real neighbours are (nil, b) -- moving it there again changes nothing.
    assert {:ok, unchanged} = Curation.move_queue_item(user.id, a.id, %{after_asset_set_id: b.id})
    assert unchanged.position == item_a.position
  end

  test "moving to sit between two adjacent items succeeds without moving any other row" do
    user = owner_fixture()
    a = asset_set_fixture(user.id)
    b = asset_set_fixture(user.id)
    c = asset_set_fixture(user.id)

    {:ok, _} = Curation.enqueue(user.id, Ecto.UUID.generate(), a.id)
    {:ok, _} = Curation.enqueue(user.id, Ecto.UUID.generate(), b.id)
    {:ok, item_c} = Curation.enqueue(user.id, Ecto.UUID.generate(), c.id)

    {:ok, moved_c} =
      Curation.move_queue_item(user.id, c.id, %{
        before_asset_set_id: a.id,
        after_asset_set_id: b.id
      })

    assert moved_c.id == item_c.id

    ordered = Curation.list_queue(user.id) |> Enum.map(& &1.asset_set_id)
    assert ordered == [a.id, c.id, b.id]
  end

  test "a move naming another user's neighbour returns not_found" do
    user = owner_fixture()
    other = owner_fixture()
    a = asset_set_fixture(user.id)
    other_asset = asset_set_fixture(other.id)
    {:ok, _} = Curation.enqueue(other.id, Ecto.UUID.generate(), other_asset.id)
    {:ok, _} = Curation.enqueue(user.id, Ecto.UUID.generate(), a.id)

    assert {:error, :not_found} =
             Curation.move_queue_item(user.id, a.id, %{after_asset_set_id: other_asset.id})
  end

  test "the 501st queue item is refused with a registered problem code and the count stays at the cap" do
    user = owner_fixture()

    for _ <- 1..500 do
      asset_set = asset_set_fixture(user.id)
      {:ok, _} = Curation.enqueue(user.id, Ecto.UUID.generate(), asset_set.id)
    end

    assert length(Curation.list_queue(user.id)) == 500

    overflow = asset_set_fixture(user.id)

    assert {:error, {:curation_limit_exceeded, _}} =
             Curation.enqueue(user.id, Ecto.UUID.generate(), overflow.id)

    assert length(Curation.list_queue(user.id)) == 500
    assert PlaysteadWeb.ErrorCodes.status_for(:curation_limit_exceeded) == 422
  end

  test "rebalancing after running out of precision preserves the visible order" do
    user = owner_fixture()
    low_asset = asset_set_fixture(user.id)
    high_asset = asset_set_fixture(user.id)

    {:ok, _} = Curation.enqueue(user.id, Ecto.UUID.generate(), low_asset.id)
    {:ok, _} = Curation.enqueue(user.id, Ecto.UUID.generate(), high_asset.id)

    # Repeatedly insert new items between the same two neighbours until
    # the fractional index runs out of practical precision and the
    # move path is forced to rebalance.
    inserted_ids =
      Enum.reduce(1..40, [], fn _, acc ->
        asset = asset_set_fixture(user.id)

        {:ok, item} =
          Curation.enqueue(user.id, Ecto.UUID.generate(), asset.id)

        {:ok, _moved} =
          Curation.move_queue_item(user.id, asset.id, %{
            before_asset_set_id: low_asset.id,
            after_asset_set_id: high_asset.id
          })

        [item.asset_set_id | acc]
      end)

    before_order = Curation.list_queue(user.id) |> Enum.map(& &1.asset_set_id)

    assert hd(before_order) == low_asset.id
    assert List.last(before_order) == high_asset.id
    assert Enum.sort(inserted_ids) == Enum.sort(before_order -- [low_asset.id, high_asset.id])

    {:ok, _rebalanced} = Curation.rebalance_queue(user.id)

    after_order = Curation.list_queue(user.id) |> Enum.map(& &1.asset_set_id)
    assert after_order == before_order
  end
end
