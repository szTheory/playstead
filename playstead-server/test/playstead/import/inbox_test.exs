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
