defmodule Playstead.Export.LayoutTest do
  use ExUnit.Case, async: true

  alias Playstead.Export.Layout

  defp member(overrides \\ []) do
    Map.merge(
      %{
        ordinal: 0,
        role: "primary",
        required: true,
        declared_name: "game.gba",
        sha256: "a" |> String.duplicate(64),
        size_bytes: 1024
      },
      Map.new(overrides)
    )
  end

  defp set(overrides \\ []) do
    Map.merge(
      %{
        id: Ecto.UUID.generate(),
        system_id: "gba",
        display_title: "Some Title",
        status: "complete",
        member_fingerprint: "fp-#{System.unique_integer([:positive])}",
        excluded: false,
        members: [member()]
      },
      Map.new(overrides)
    )
  end

  test "planning the same library twice produces identical output" do
    sets = [set(), set(display_title: "Another Title")]

    assert Layout.plan(sets) == Layout.plan(sets)
  end

  test "output is fully sorted by relative directory" do
    sets = [
      set(display_title: "Zelda"),
      set(display_title: "Adventure")
    ]

    plan = Layout.plan(sets)
    dirs = Enum.map(plan.sets, & &1.relative_dir)
    assert dirs == Enum.sort(dirs)
  end

  test "a nil system_id places the set under the unsorted folder" do
    plan = Layout.plan([set(system_id: nil, display_title: "Homebrew")])
    [entry] = plan.sets
    assert String.starts_with?(entry.relative_dir, "unsorted/")
  end

  test "incomplete, unrecognized, and custom sets are placed and carry their status" do
    sets = [
      set(status: "incomplete", display_title: "Half Set"),
      set(status: "unrecognized", display_title: "Mystery", system_id: nil),
      set(status: "custom", display_title: "Homebrew Hack")
    ]

    plan = Layout.plan(sets)
    statuses = Enum.map(plan.sets, & &1.status)
    assert "incomplete" in statuses
    assert "unrecognized" in statuses
    assert "custom" in statuses
  end

  test "two colliding titles in one system are disambiguated and a non-colliding title carries no suffix" do
    sets = [
      set(display_title: "Chrono Trigger", system_id: "snes"),
      set(display_title: "chrono trigger", system_id: "snes"),
      set(display_title: "Unique Title", system_id: "snes")
    ]

    plan = Layout.plan(sets)
    folder_names = Enum.map(plan.sets, &Path.basename(&1.relative_dir))

    colliding = Enum.reject(folder_names, &(&1 == "Unique Title"))
    assert Enum.all?(colliding, &String.contains?(&1, "-"))
    assert "Unique Title" in folder_names
  end

  test "a member named identically to the reserved saves folder is renamed" do
    plan = Layout.plan([set(members: [member(declared_name: "saves")])])
    [entry] = plan.sets
    [member_plan] = entry.members

    refute member_plan.exported_name == "saves"
    assert member_plan.name_changed?
  end

  test "a changed name records both the original and the exported form" do
    plan = Layout.plan([set(members: [member(declared_name: "bad/name.rom")])])
    [entry] = plan.sets
    [member_plan] = entry.members

    assert member_plan.original_name == "bad/name.rom"
    assert member_plan.exported_name != member_plan.original_name
    assert member_plan.name_changed?
  end

  test "a safe original basename is exported unchanged" do
    plan = Layout.plan([set(members: [member(declared_name: "game.gba")])])
    [entry] = plan.sets
    [member_plan] = entry.members

    assert member_plan.exported_name == "game.gba"
    refute member_plan.name_changed?
  end

  test "quarantined content is placed under the quarantine folder" do
    plan =
      Layout.plan([], quarantined: [%{sha256: String.duplicate("b", 64), size_bytes: 10}])

    [entry] = plan.quarantine
    assert String.starts_with?(entry.relative, "quarantine/")
  end

  test "user-excluded items are absent by default and present when opted in" do
    sets = [set(excluded: true, display_title: "Excluded")]

    assert Layout.plan(sets).sets == []
    assert length(Layout.plan(sets, include_excluded: true).sets) == 1
  end
end
