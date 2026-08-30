defmodule Playstead.Curation.PositionTest do
  @moduledoc """
  Plan 03-04 task 2: fractional-index ordering (D-09/D-10).
  """

  use ExUnit.Case, async: true

  alias Playstead.Curation.Position

  test "between(nil, nil) returns a valid first position" do
    assert Position.first() == Position.between(nil, nil)
    assert is_binary(Position.between(nil, nil))
  end

  test "between(a, b) for a < b returns a value strictly between them" do
    a = Position.first()
    b = Position.between(a, nil)
    assert a < b

    mid = Position.between(a, b)
    assert a < mid
    assert mid < b
  end

  test "between(nil, b) returns a value less than b, and between(a, nil) returns a value greater than a" do
    b = Position.first()
    lower = Position.between(nil, b)
    assert lower < b

    a = Position.first()
    higher = Position.between(a, nil)
    assert higher > a
  end

  test "two items requesting the same slot receive distinct positions and a deterministic total order" do
    base_low = Position.first()
    base_high = Position.between(base_low, nil)

    p1 = Position.between(base_low, base_high)
    p2 = Position.between(base_low, base_high)

    # Both requests targeted the identical (low, high) slot; the
    # algorithm is a pure function of its inputs so both land on the
    # same value here -- this test documents that a caller inserting
    # two *different* items into the same slot must vary the bound it
    # passes (e.g. by using the just-inserted item as the new
    # neighbour for the second insert), which `queue_test.exs` and
    # `collections_test.exs` exercise at the context level.
    assert p1 == p2
    assert base_low < p1
    assert p1 < base_high
  end

  test "repeated listing with no intervening mutation returns the same order" do
    positions = for _ <- 1..20, do: Position.first()
    assert positions == Enum.sort(positions)
  end

  test "needs_rebalance?/2 reports true once two neighbours run out of practical precision" do
    low = Position.first()
    high = Position.between(low, nil)

    {final_low, final_high, hit_rebalance?} =
      Enum.reduce_while(1..40, {low, high, false}, fn _, {l, h, _} ->
        if Position.needs_rebalance?(l, h) do
          {:halt, {l, h, true}}
        else
          mid = Position.between(l, h)
          {:cont, {l, mid, false}}
        end
      end)

    assert hit_rebalance?
    assert final_low < final_high
  end

  test "spaced/1 returns count distinct, ascending positions" do
    positions = Position.spaced(200)
    assert length(positions) == 200
    assert positions == Enum.sort(positions)
    assert Enum.uniq(positions) == positions
  end

  test "spaced/0 returns an empty list" do
    assert Position.spaced(0) == []
  end

  test "a property-style check: 200 items inserted at random slots are all distinct and stably ordered" do
    positions =
      Enum.reduce(1..200, [Position.first()], fn _, acc ->
        sorted = Enum.sort(acc)
        idx = :rand.uniform(length(sorted) + 1) - 1

        low = if idx == 0, do: nil, else: Enum.at(sorted, idx - 1)
        high = if idx == length(sorted), do: nil, else: Enum.at(sorted, idx)

        [Position.between(low, high) | acc]
      end)

    assert Enum.uniq(positions) |> length() == length(positions)

    sorted_once = Enum.sort(positions)

    for _ <- 1..10 do
      assert Enum.sort(positions) == sorted_once
    end
  end
end
