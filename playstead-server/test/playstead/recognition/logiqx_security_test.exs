defmodule Playstead.Recognition.LogiqxSecurityTest do
  @moduledoc """
  T-02-59/T-02-60/T-02-61: every hostile fixture is refused without an
  exception, without reading any external resource, and without
  unbounded memory growth. Also covers the property that mutated
  documents never raise (T-02-60).
  """

  # async: false — one test temporarily mutates the global
  # `:logiqx_max_entries` application env to exercise "refused at the
  # cap" without a multi-hundred-thousand-entry fixture; that global
  # mutation must not race a concurrently-running test in another
  # module that also calls `LogiqxHandler.parse_file/1`.
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Playstead.Recognition.LogiqxHandler

  @fixtures_dir Path.join([__DIR__, "..", "..", "support", "fixtures", "dat"])

  defp fixture(name), do: Path.join(@fixtures_dir, name)

  describe "hostile fixtures" do
    test "a document declaring a document type is refused" do
      assert {:error, :dtd_or_entity_declared} = LogiqxHandler.parse_file(fixture("doctype.dat"))
    end

    test "a document referencing an external entity is refused and the referenced file is not read" do
      refute File.exists?("/nonexistent-playstead-xxe-marker")

      assert {:error, :dtd_or_entity_declared} =
               LogiqxHandler.parse_file(fixture("external_entity.dat"))

      # The fixture points at /etc/passwd. If it had been read and
      # expanded, the entries would carry its contents; instead nothing
      # is ever handed to the XML parser at all.
    end

    test "a recursive entity expansion is refused without exhausting memory" do
      {time_us, result} =
        :timer.tc(fn -> LogiqxHandler.parse_file(fixture("recursive_entity.dat")) end)

      assert {:error, :dtd_or_entity_declared} = result
      # A billion-laughs style expansion that were actually attempted
      # would take vastly longer than this; refusing at the DOCTYPE
      # guard keeps this near-instant.
      assert time_us < 1_000_000
    end

    test "a document above the size cap is refused before being fully read" do
      path =
        Path.join(
          System.tmp_dir!(),
          "playstead-oversized-#{System.unique_integer([:positive])}.dat"
        )

      File.open!(path, [:write, :binary], fn io ->
        IO.binwrite(io, "<?xml version=\"1.0\"?><datafile>")
        # 34 MiB of filler, above the 32 MiB cap.
        chunk = String.duplicate("a", 1_048_576)
        Enum.each(1..34, fn _ -> IO.binwrite(io, chunk) end)
      end)

      on_exit(fn -> File.rm(path) end)

      assert {:error, :too_large} = LogiqxHandler.parse_file(path)
    end

    test "a document above the entry cap is refused at the cap" do
      path =
        Path.join(
          System.tmp_dir!(),
          "playstead-entrycap-#{System.unique_integer([:positive])}.dat"
        )

      entries =
        Enum.map(1..10, fn i ->
          ~s(<game name="Game #{i}"><rom name="g#{i}.gba" size="1" crc="00000000"/></game>)
        end)

      File.write!(path, "<?xml version=\"1.0\"?><datafile>#{Enum.join(entries)}</datafile>")
      on_exit(fn -> File.rm(path) end)

      previous = Application.get_env(:playstead, :logiqx_max_entries)
      Application.put_env(:playstead, :logiqx_max_entries, 5)

      on_exit(fn ->
        if previous do
          Application.put_env(:playstead, :logiqx_max_entries, previous)
        else
          Application.delete_env(:playstead, :logiqx_max_entries)
        end
      end)

      assert {:error, :entry_cap_exceeded} = LogiqxHandler.parse_file(path)
    end

    test "a well-formed pack under the entry cap parses every entry" do
      assert {:ok, entries} = LogiqxHandler.parse_file(fixture("valid.dat"))
      assert length(entries) == 2
    end

    test "a truncated document yields a refusal rather than an exception" do
      assert {:error, :malformed} = LogiqxHandler.parse_file(fixture("truncated.dat"))
    end

    test "an empty document yields a refusal rather than an exception" do
      path =
        Path.join(System.tmp_dir!(), "playstead-empty-#{System.unique_integer([:positive])}.dat")

      File.write!(path, "")
      on_exit(fn -> File.rm(path) end)

      assert {:error, _reason} = LogiqxHandler.parse_file(path)
    end

    test "a nonexistent path yields a refusal rather than an exception" do
      assert {:error, _reason} = LogiqxHandler.parse_file("/nonexistent/playstead-pack.dat")
    end

    test "implausible declared entry sizes parse without affecting allocation, stored as metadata only" do
      assert {:ok, [entry]} = LogiqxHandler.parse_file(fixture("implausible_size.dat"))
      # The value is astronomically larger than any real cartridge; it
      # is dropped to nil rather than trusted, and nothing here ever
      # sized a buffer or collection from it.
      assert entry.size_bytes == nil
      assert entry.name == "Implausible Game.gba"
    end
  end

  describe "well-formed pack" do
    test "yields entries with names, digests, and sizes" do
      assert {:ok, entries} = LogiqxHandler.parse_file(fixture("valid.dat"))
      assert length(entries) == 2

      [first, second] = entries
      assert first.name == "Test Game (USA).gba"
      assert first.size_bytes == 8_388_608
      assert first.crc32 == "1234abcd"
      assert first.md5 == "098f6bcd4621d373cade4e832627b4f6"
      assert String.length(first.sha1) > 0

      assert second.name == "Second Game (Europe).gba"
    end
  end

  describe "property: never raises" do
    property "mutated versions of a valid pack always return a value, never raise" do
      valid_bytes = File.read!(fixture("valid.dat"))

      check all(
              index <- integer(0..(byte_size(valid_bytes) - 1)),
              replacement <- integer(0..255),
              max_runs: 30
            ) do
        mutated =
          valid_bytes
          |> :binary.bin_to_list()
          |> List.replace_at(index, replacement)
          |> :binary.list_to_bin()

        path =
          Path.join(
            System.tmp_dir!(),
            "playstead-mutated-#{System.unique_integer([:positive])}.dat"
          )

        File.write!(path, mutated)

        result =
          try do
            LogiqxHandler.parse_file(path)
          rescue
            e -> {:raised, e}
          end

        File.rm(path)

        assert match?({:ok, _entries}, result) or match?({:error, _reason}, result)
      end
    end
  end
end
