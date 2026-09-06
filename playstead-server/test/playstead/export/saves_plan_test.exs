defmodule Playstead.Export.SavesPlanTest do
  use ExUnit.Case, async: true

  alias Playstead.Export.SavesPlan

  defp ts(offset_seconds), do: DateTime.add(~U[2026-01-01 00:00:00Z], offset_seconds, :second)

  defp revision(overrides) do
    Map.merge(
      %{
        id: Ecto.UUID.generate(),
        sha256: :crypto.hash(:sha256, Ecto.UUID.generate()) |> Base.encode16(case: :lower),
        size_bytes: 32_768,
        recorded_at: ts(0),
        save_kind: "system_save",
        is_head: true,
        branch_key: nil
      },
      Map.new(overrides)
    )
  end

  test "a linear line of three revisions is named 000001/000002/000003 in recorded_at order" do
    r1 = revision(recorded_at: ts(0), is_head: false)
    r2 = revision(recorded_at: ts(10), is_head: false)
    r3 = revision(recorded_at: ts(20), is_head: true)

    plan = SavesPlan.plan([r1, r2, r3])
    [e1, e2, e3] = plan.entries

    assert e1.seq == 1
    assert e2.seq == 2
    assert e3.seq == 3

    digest1 = String.slice(r1.sha256, 0, 8)
    digest2 = String.slice(r2.sha256, 0, 8)
    digest3 = String.slice(r3.sha256, 0, 8)

    assert Path.basename(e1.relative) == "000001-#{digest1}.sav"
    assert Path.basename(e2.relative) == "000002-#{digest2}.sav"
    assert Path.basename(e3.relative) == "000003-#{digest3}.sav"
  end

  test "a fork's revisions carry branch letters derived from a stable branch_key, stable across two planning runs" do
    shared = revision(recorded_at: ts(0), is_head: false, branch_key: nil)
    left = revision(recorded_at: ts(10), is_head: true, branch_key: "left-fork")
    right = revision(recorded_at: ts(10), is_head: true, branch_key: "right-fork")

    revisions = [shared, left, right]

    plan_a = SavesPlan.plan(revisions)
    plan_b = SavesPlan.plan(revisions)

    assert plan_a == plan_b

    entries_by_id = Map.new(plan_a.entries, &{&1.revision_id, &1})
    # "left-fork" < "right-fork" lexicographically -> a, b
    assert entries_by_id[left.id].branch == "a"
    assert entries_by_id[right.id].branch == "b"
    assert entries_by_id[shared.id].branch == nil
  end

  test "renaming the origin device between two planning runs produces identical filenames" do
    r1 = revision(recorded_at: ts(0), is_head: false, branch_key: "fork-a")
    r2 = revision(recorded_at: ts(5), is_head: true, branch_key: "fork-b")

    plan_before = SavesPlan.plan([Map.put(r1, :device_name, "Jons-MacBook"), r2])
    plan_after = SavesPlan.plan([Map.put(r1, :device_name, "Studio-Mini"), r2])

    assert Enum.map(plan_before.entries, & &1.relative) ==
             Enum.map(plan_after.entries, & &1.relative)
  end

  test "appending a fourth revision leaves the first three revisions' names and sequence numbers unchanged" do
    r1 = revision(recorded_at: ts(0), is_head: false)
    r2 = revision(recorded_at: ts(10), is_head: false)
    r3 = revision(recorded_at: ts(20), is_head: false)
    r4 = revision(recorded_at: ts(30), is_head: true)

    before_plan = SavesPlan.plan([r1, r2, r3])
    after_plan = SavesPlan.plan([r1, r2, r3, r4])

    before_by_id = Map.new(before_plan.entries, &{&1.revision_id, &1})
    after_by_id = Map.new(after_plan.entries, &{&1.revision_id, &1})

    for r <- [r1, r2, r3] do
      assert before_by_id[r.id].relative == after_by_id[r.id].relative
      assert before_by_id[r.id].seq == after_by_id[r.id].seq
    end
  end

  test "a linear slot's plan includes a drop-in entry named from the primary member's basename" do
    r1 = revision(recorded_at: ts(0), is_head: true)

    plan = SavesPlan.plan([r1], primary_basename: "Pokemon Emerald (USA).gba")

    assert plan.drop_in.relative == "saves/Pokemon Emerald (USA).sav"
    assert plan.drop_in.sha256 == r1.sha256
  end

  test "a diverged slot's plan includes no drop-in entry" do
    left = revision(recorded_at: ts(0), is_head: true, branch_key: "a-branch")
    right = revision(recorded_at: ts(0), is_head: true, branch_key: "b-branch")

    plan = SavesPlan.plan([left, right], primary_basename: "game.gba")

    assert plan.diverged?
    assert plan.drop_in == nil
  end

  test "a revision with a save_kind other than system_save produces no drop-in entry" do
    r1 = revision(recorded_at: ts(0), is_head: true, save_kind: "save_state")

    plan = SavesPlan.plan([r1], primary_basename: "game.gba")

    refute plan.diverged?
    assert plan.drop_in == nil
  end

  test "planning the same inputs twice produces equal plan structs" do
    revisions = [
      revision(recorded_at: ts(0), is_head: false),
      revision(recorded_at: ts(5), is_head: true)
    ]

    assert SavesPlan.plan(revisions, primary_basename: "game.gba") ==
             SavesPlan.plan(revisions, primary_basename: "game.gba")
  end

  test "a set with zero save revisions produces a plan with an empty entry list and no error" do
    plan = SavesPlan.plan([])

    assert plan.entries == []
    assert plan.branches == [%{branch: nil, revisions: []}]
    assert plan.drop_in == nil
    refute plan.diverged?
  end

  test "a primary member literally named saves routes the drop-in stem through the reserved-name guard" do
    r1 = revision(recorded_at: ts(0), is_head: true)

    plan = SavesPlan.plan([r1], primary_basename: "saves.gba")

    refute Path.basename(plan.drop_in.relative, ".sav") == "saves"
    assert plan.drop_in.relative == "saves/saves-save.sav"
  end

  test "a revision whose bytes never uploaded is marked missing and excluded from the manifest-eligible digest" do
    r1 = revision(recorded_at: ts(0), is_head: true, bytes: :missing)

    plan = SavesPlan.plan([r1], primary_basename: "game.gba")
    [entry] = plan.entries

    assert entry.bytes == :missing
    assert entry.sha256 == r1.sha256
    # a missing-bytes head never earns a drop-in copy
    assert plan.drop_in == nil
  end

  test "plan/2 breaks a recorded_at tie by revision id regardless of input list order" do
    [lower_id, greater_id] = Enum.sort([Ecto.UUID.generate(), Ecto.UUID.generate()])

    lower = revision(id: lower_id, recorded_at: ts(0), is_head: false)
    greater = revision(id: greater_id, recorded_at: ts(0), is_head: true)

    plan_forward = SavesPlan.plan([lower, greater])
    plan_reversed = SavesPlan.plan([greater, lower])

    assert plan_forward == plan_reversed

    entries_by_id = Map.new(plan_forward.entries, &{&1.revision_id, &1})
    assert entries_by_id[lower.id].seq < entries_by_id[greater.id].seq

    reversed_entries_by_id = Map.new(plan_reversed.entries, &{&1.revision_id, &1})
    assert reversed_entries_by_id[lower.id].seq < reversed_entries_by_id[greater.id].seq
  end

  test "no Repo, filesystem, or clock call is made anywhere in the module" do
    source = File.read!("lib/playstead/export/saves_plan.ex")
    refute source =~ ~r/Repo\.|File\.|DateTime\.utc_now|NaiveDateTime\.utc_now/i
  end
end
