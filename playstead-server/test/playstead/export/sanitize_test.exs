defmodule Playstead.Export.SanitizeTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Playstead.Export.Sanitize

  describe "component/1" do
    property "never yields a result containing a parent-directory segment, a leading separator, or a NUL byte" do
      check all(name <- StreamData.string(:printable, min_length: 0, max_length: 60)) do
        {sanitized, _changed?} = Sanitize.component(name)

        refute String.contains?(sanitized, "..")
        refute String.starts_with?(sanitized, "/")
        refute String.contains?(sanitized, <<0>>)
      end
    end

    property "is idempotent" do
      check all(name <- StreamData.string(:printable, min_length: 0, max_length: 60)) do
        {once, _} = Sanitize.component(name)
        {twice, changed_again?} = Sanitize.component(once)

        assert once == twice
        refute changed_again?
      end
    end

    property "the root-anchored join always resolves inside the given root" do
      check all(name <- StreamData.string(:printable, min_length: 1, max_length: 60)) do
        {sanitized, _} = Sanitize.component(name)
        root = "/tmp/playstead-sanitize-root"

        case Sanitize.safe_join(root, sanitized) do
          {:ok, full} -> assert String.starts_with?(full, root)
          :error -> :ok
        end
      end
    end

    test "rejects (rewrites) a parent-directory segment" do
      {sanitized, changed?} = Sanitize.component("../etc/passwd")
      refute String.contains?(sanitized, "..")
      assert changed?
    end

    test "rejects (rewrites) an absolute path" do
      {sanitized, changed?} = Sanitize.component("/etc/passwd")
      refute String.starts_with?(sanitized, "/")
      assert changed?
    end

    test "rejects (rewrites) a drive-letter prefix" do
      {sanitized, changed?} = Sanitize.component("C:\\Windows\\System32")
      refute sanitized =~ ~r/^[A-Za-z]:/
      assert changed?
    end

    test "rejects (rewrites) a NUL byte" do
      {sanitized, changed?} = Sanitize.component(<<"file", 0, "name">>)
      refute String.contains?(sanitized, <<0>>)
      assert changed?
    end

    test "rejects (rewrites) a control character" do
      {sanitized, changed?} = Sanitize.component(<<"file", 1, "name">>)
      refute sanitized =~ <<1>>
      assert changed?
    end

    test "a safe original basename is exported unchanged" do
      assert Sanitize.component("Chrono Trigger (USA).sfc") == {"Chrono Trigger (USA).sfc", false}
    end

    test "bounds a component to the byte limit" do
      long_name = String.duplicate("a", 400)
      {sanitized, changed?} = Sanitize.component(long_name)
      assert byte_size(sanitized) <= 255
      assert changed?
    end

    test "non-binary input always yields a safe fallback" do
      assert {"unnamed", true} = Sanitize.component(nil)
    end
  end

  describe "safe?/1" do
    test "true for an already-safe name" do
      assert Sanitize.safe?("safe-name.rom")
    end

    test "false for a name requiring rewriting" do
      refute Sanitize.safe?("../escape")
    end
  end

  describe "collision_key/1 and reserved_saves_name?/1" do
    test "case and normalization insensitive" do
      assert Sanitize.collision_key("Saves") == Sanitize.collision_key("saves")
    end

    test "reserved_saves_name?/1 matches case-insensitively" do
      assert Sanitize.reserved_saves_name?("SAVES")
      refute Sanitize.reserved_saves_name?("not-saves")
    end
  end

  describe "safe_join/2" do
    test "resolves a safe relative path inside the root" do
      assert {:ok, "/tmp/root/data/file.rom"} =
               Sanitize.safe_join("/tmp/root", "data/file.rom")
    end

    test "refuses a path that would escape the root even via a raw .. segment" do
      assert Sanitize.safe_join("/tmp/root", "../escape") == :error
    end
  end
end
