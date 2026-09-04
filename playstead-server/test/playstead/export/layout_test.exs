defmodule Playstead.Export.LayoutTest do
  use Playstead.DataCase, async: false

  import Playstead.ImportFixtures

  alias Playstead.Blobs.Store.LocalDisk
  alias Playstead.Export.{BagitWriter, ExportRecord, Layout}

  setup do
    File.mkdir_p!(LocalDisk.blob_path())
    :ok
  end

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

  # --- D-57: opts[:saves] and persisted saves_scope ---

  defp put(bytes), do: Playstead.Blobs.put_stream([bytes], byte_size(bytes))

  defp ts(offset), do: DateTime.add(~U[2026-01-01 00:00:00Z], offset, :second)

  defp save_revision(sha256, overrides \\ []) do
    Map.merge(
      %{
        id: Ecto.UUID.generate(),
        sha256: sha256,
        size_bytes: 32_768,
        recorded_at: ts(0),
        save_kind: "system_save",
        is_head: true,
        branch_key: nil
      },
      Map.new(overrides)
    )
  end

  test "opts[:saves] defaults to :all: a set's supplied save revisions are planned" do
    {:ok, :stored, meta} = put(random_bytes(64))
    revisions = [save_revision(meta.sha256)]

    plan = Layout.plan([set(saves: revisions)])
    [entry] = plan.sets

    assert entry.saves_plan.entries != []
  end

  test "opts[:saves] :none omits the saves history entirely, regardless of what a set's input supplies" do
    {:ok, :stored, meta} = put(random_bytes(64))
    revisions = [save_revision(meta.sha256)]

    plan = Layout.plan([set(saves: revisions)], saves: :none)
    [entry] = plan.sets

    assert entry.saves_plan.entries == []
    assert entry.saves_plan.drop_in == nil
  end

  test "planning the same library twice with save revisions produces identical plans (plan purity)" do
    {:ok, :stored, meta} = put(random_bytes(64))
    revisions = [save_revision(meta.sha256)]
    sets = [set(saves: revisions)]

    assert Layout.plan(sets) == Layout.plan(sets)
  end

  # D-59: determinism is exactly plan purity, write reproducibility, and
  # append-only stability, with three named exceptions -- two inherited
  # from Phase 2 (bag-info.txt's Bagging-Date and the single
  # tagmanifest-sha256.txt line covering it) plus one this plan
  # introduces (the saves/{stem}.sav drop-in copy, which tracks the
  # slot's head and is therefore expected to change only when the head
  # itself changes -- not exercised by this test, which reuses one
  # unchanged plan, but named here so a fourth exception can never be
  # added silently).
  @determinism_exceptions ["bag-info.txt", "tagmanifest-sha256.txt"]

  defp hash_tree(dir) do
    dir
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Map.new(fn path ->
      relative = Path.relative_to(path, dir)
      {relative, :crypto.hash(:sha256, File.read!(path))}
    end)
  end

  test "two writes of the same plan produce byte-identical trees except the three named exceptions" do
    {:ok, :stored, meta} = put(random_bytes(128))

    layout =
      Layout.plan([
        set(
          members: [member(sha256: meta.sha256, size_bytes: meta.size_bytes)],
          saves: [save_revision(meta.sha256)]
        )
      ])

    dir_a = Path.join(System.tmp_dir!(), "playstead-det-a-#{System.unique_integer([:positive])}")
    dir_b = Path.join(System.tmp_dir!(), "playstead-det-b-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir_a) && File.rm_rf!(dir_b) end)

    assert {:ok, _} = BagitWriter.write_bag(dir_a, layout)
    assert {:ok, _} = BagitWriter.write_bag(dir_b, layout)

    tree_a = hash_tree(dir_a)
    tree_b = hash_tree(dir_b)

    differing =
      tree_a
      |> Map.keys()
      |> Enum.filter(fn key -> tree_a[key] != tree_b[key] end)

    assert Enum.all?(differing, &(&1 in @determinism_exceptions))

    stripped_a = Map.drop(tree_a, @determinism_exceptions)
    stripped_b = Map.drop(tree_b, @determinism_exceptions)
    assert stripped_a == stripped_b
  end

  test "appending a save revision and re-exporting leaves every previously written revision file byte-identical" do
    {:ok, :stored, meta_1} = put(random_bytes(64))
    {:ok, :stored, meta_2} = put(random_bytes(96))

    r1 = save_revision(meta_1.sha256, recorded_at: ts(0), is_head: false)
    r2 = save_revision(meta_2.sha256, recorded_at: ts(10), is_head: true)

    layout_before = Layout.plan([set(members: [], saves: [r1])])
    layout_after = Layout.plan([set(members: [], saves: [r1, r2])])

    dir = Path.join(System.tmp_dir!(), "playstead-append-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)

    assert {:ok, _} = BagitWriter.write_bag(dir, layout_before)
    [before_entry] = Enum.at(layout_before.sets, 0).saves_plan.entries
    revision_path = Path.join(dir, Path.join("data", before_entry.relative))
    bytes_before = File.read!(revision_path)

    assert {:ok, _} = BagitWriter.write_bag(dir, layout_after)
    assert File.read!(revision_path) == bytes_before
  end

  test "a re-enqueued job reproduces the same plan from the persisted saves_scope, never a default" do
    {:ok, :stored, meta} = put(random_bytes(64))
    revisions = [save_revision(meta.sha256)]
    sets = [set(saves: revisions)]

    record = %ExportRecord{saves_scope: "none"}

    plan_from_persisted =
      Layout.plan(sets, saves: Layout.saves_scope_atom(record.saves_scope))

    [entry] = plan_from_persisted.sets
    assert entry.saves_plan.entries == []

    # Reconstructing again from the same persisted record (as a
    # re-enqueued Oban job would, reading the row fresh) reproduces the
    # identical plan -- not the :all default a missing/forgotten
    # saves_scope would have silently fallen back to.
    assert Layout.plan(sets, saves: Layout.saves_scope_atom(record.saves_scope)) ==
             plan_from_persisted

    refute Layout.plan(sets, saves: Layout.saves_scope_atom(record.saves_scope)) ==
             Layout.plan(sets, saves: :all)
  end

  test "Layout never aliases the saves bounded context" do
    source = File.read!("lib/playstead/export/layout.ex")
    refute source =~ "Playstead.Saves"
  end
end
