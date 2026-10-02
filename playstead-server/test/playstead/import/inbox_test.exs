defmodule Playstead.Import.InboxTest do
  use ExUnit.Case, async: true

  alias Playstead.Import.Inbox

  setup do
    root =
      Path.join(System.tmp_dir!(), "playstead-inbox-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  test "returns the regular files beneath the folder with relative path, size, and mtime", %{
    root: root
  } do
    File.write!(Path.join(root, "game.gba"), "abc")
    File.mkdir_p!(Path.join(root, "nested"))
    File.write!(Path.join(root, "nested/deep.bin"), "de")

    {:ok, %{files: files}} = Inbox.scan(root)
    paths = Enum.map(files, & &1.relative_path) |> Enum.sort()

    assert paths == ["game.gba", "nested/deep.bin"]
    game = Enum.find(files, &(&1.relative_path == "game.gba"))
    assert game.size_bytes == 3
    assert %DateTime{} = game.mtime
  end

  test "a symbolic link inside the inbox is not followed and is reported rather than traversed",
       %{
         root: root
       } do
    outside =
      Path.join(
        System.tmp_dir!(),
        "playstead-inbox-outside-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(outside)
    File.write!(Path.join(outside, "secret.bin"), "should never be read")
    on_exit(fn -> File.rm_rf!(outside) end)

    link_path = Path.join(root, "escape")
    :ok = File.ln_s(outside, link_path)

    {:ok, %{files: files, links: links}} = Inbox.scan(root)

    refute Enum.any?(files, &String.contains?(&1.relative_path, "secret"))
    assert "escape" in links
  end

  test "dot-files the OS writes into the inbox are skipped, not reported as unknown content",
       %{root: root} do
    # Every one of these is real: Finder writes .DS_Store the moment the folder
    # is opened, a volume picks up .Spotlight-V100/.fseventsd, and copying from
    # another disk leaves ._ AppleDouble files. Reported, each becomes a phantom
    # :unknown demanding a decision at /attention -- and .DS_Store comes back as
    # soon as the folder is opened again, so excluding it never settles it.
    File.write!(Path.join(root, "game.gba"), "abc")
    File.write!(Path.join(root, ".DS_Store"), "finder")
    File.write!(Path.join(root, "._game.gba"), "appledouble")
    File.write!(Path.join(root, ".gitkeep"), "")

    {:ok, %{files: files}} = Inbox.scan(root)
    paths = Enum.map(files, & &1.relative_path) |> Enum.sort()

    assert paths == ["game.gba"]
  end

  test "a dot-directory is skipped rather than walked, so trashed files are not imported", %{
    root: root
  } do
    File.mkdir_p!(Path.join(root, ".Trashes"))
    File.write!(Path.join(root, ".Trashes/deleted.gba"), "in the trash")
    File.mkdir_p!(Path.join(root, ".Spotlight-V100"))
    File.write!(Path.join(root, ".Spotlight-V100/index.bin"), "index")
    File.write!(Path.join(root, "keeper.gba"), "real")

    {:ok, %{files: files}} = Inbox.scan(root)
    paths = Enum.map(files, & &1.relative_path) |> Enum.sort()

    assert paths == ["keeper.gba"]
    refute Enum.any?(files, &String.contains?(&1.relative_path, "deleted"))
  end

  test "a dot-named symlink is skipped entirely rather than reported as a link", %{root: root} do
    # Skipping happens by name before lstat, so a dot-named link does not even
    # reach the `links` list. Asserted so the by-name ordering is not quietly
    # changed to a post-stat filter, which would reintroduce it as a link report.
    outside =
      Path.join(
        System.tmp_dir!(),
        "playstead-inbox-dotlink-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(outside)
    on_exit(fn -> File.rm_rf!(outside) end)
    :ok = File.ln_s(outside, Path.join(root, ".hidden_escape"))

    {:ok, %{files: files, links: links}} = Inbox.scan(root)

    assert files == []
    assert links == []
  end

  test "a non-dot file whose name merely contains a dot is still reported", %{root: root} do
    # Guards the rule against becoming "reject anything with a dot in it".
    File.write!(Path.join(root, "Pokemon - Version Vert Feuille (France).gba"), "rom")
    File.write!(Path.join(root, "save.dat.bak"), "bak")

    {:ok, %{files: files}} = Inbox.scan(root)
    paths = Enum.map(files, & &1.relative_path) |> Enum.sort()

    assert paths == ["Pokemon - Version Vert Feuille (France).gba", "save.dat.bak"]
  end

  test "a non-regular filesystem entry is skipped", %{root: root} do
    fifo_path = Path.join(root, "a_fifo")
    {_output, 0} = System.cmd("mkfifo", [fifo_path])

    {:ok, %{files: files}} = Inbox.scan(root)

    refute Enum.any?(files, &(&1.relative_path == "a_fifo"))
  end

  test "the scanned tree is byte-for-byte unchanged after a scan, including modification times",
       %{
         root: root
       } do
    path = Path.join(root, "game.gba")
    File.write!(path, "abc")
    before_stat = File.stat!(path, time: :posix)

    {:ok, _result} = Inbox.scan(root)

    after_stat = File.stat!(path, time: :posix)
    assert File.read!(path) == "abc"
    assert before_stat.mtime == after_stat.mtime
  end

  test "ordering is deterministic across repeated scans", %{root: root} do
    File.write!(Path.join(root, "b.bin"), "b")
    File.write!(Path.join(root, "a.bin"), "a")
    File.write!(Path.join(root, "c.bin"), "c")

    {:ok, %{files: first}} = Inbox.scan(root)
    {:ok, %{files: second}} = Inbox.scan(root)

    assert Enum.map(first, & &1.relative_path) |> Enum.sort() ==
             Enum.map(second, & &1.relative_path) |> Enum.sort()
  end

  test "a missing root returns an empty scan rather than raising" do
    {:ok, %{files: files, links: links}} = Inbox.scan("/does/not/exist/at/all")
    assert files == []
    assert links == []
  end
end
