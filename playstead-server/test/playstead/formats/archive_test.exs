defmodule Playstead.Formats.ArchiveTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Playstead.Formats.Archive
  alias Playstead.RomFixtures

  test "recognises zip, 7z, rar, gzip, xz, and zstd magic signatures" do
    assert Archive.detect(RomFixtures.zip_magic()) == {:match, :zip}
    assert Archive.detect(RomFixtures.sevenz_magic()) == {:match, :sevenz}
    assert Archive.detect(RomFixtures.rar_magic()) == {:match, :rar}
    assert Archive.detect(RomFixtures.gzip_magic()) == {:match, :gzip}
    assert Archive.detect(RomFixtures.xz_magic()) == {:match, :xz}
    assert Archive.detect(RomFixtures.zstd_magic()) == {:match, :zstd}
  end

  test "does not match a valid ROM header" do
    assert Archive.detect(RomFixtures.valid_gba()) == :no_match
  end

  test "does not match empty input" do
    assert Archive.detect(<<>>) == :no_match
  end

  test "recognises a zip whose extension was renamed to a ROM extension (bytes, not extension)" do
    assert Archive.detect(RomFixtures.zip_with_rom_extension_bytes()) == {:match, :zip}
  end

  test "a valid ROM header wins over a trailing archive signature via Playstead.Formats.identify/2" do
    bytes = RomFixtures.gba_polyglot_with_trailing_archive()
    assert {:gba, :signature, _evidence} = Playstead.Formats.identify(bytes, "game.zip")
  end

  property "never raises for arbitrary binaries of arbitrary length" do
    check all(bytes <- binary()) do
      result = Archive.detect(bytes)
      assert result == :no_match or match?({:match, atom} when is_atom(atom), result)
    end
  end
end
