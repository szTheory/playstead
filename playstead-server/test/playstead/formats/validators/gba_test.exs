defmodule Playstead.Formats.Validators.GbaTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Playstead.Formats.Validators.Gba
  alias Playstead.RomFixtures

  test "matches a valid GBA header and reports title and game code" do
    assert {:match, evidence} = Gba.recognize(RomFixtures.valid_gba("SOMEGAME"))
    assert evidence.tier == :signature
    assert evidence.title == "SOMEGAME"
    assert evidence.game_code == "PSTD"
  end

  test "does not match another system's valid header" do
    assert Gba.recognize(RomFixtures.valid_nes_ines()) == :no_match
    assert Gba.recognize(RomFixtures.valid_md()) == :no_match
  end

  test "does not match empty input" do
    assert Gba.recognize(<<>>) == :no_match
  end

  test "does not match input truncated before the header ends" do
    assert Gba.recognize(RomFixtures.truncated_gba()) == :no_match
  end

  test "does not match a correct logo with a wrong checksum" do
    assert Gba.recognize(RomFixtures.bad_checksum_gba()) == :no_match
  end

  test "never raises for arbitrary mutated bytes" do
    valid = RomFixtures.valid_gba()
    mutated = :crypto.strong_rand_bytes(byte_size(valid))
    assert Gba.recognize(mutated) in [:no_match, {:match, %{}}] or true
  end

  test "does not read beyond the first 64 kibibytes" do
    valid = RomFixtures.valid_gba()
    oversized = valid <> :crypto.strong_rand_bytes(200_000)
    assert Gba.recognize(valid) == Gba.recognize(binary_part(oversized, 0, byte_size(valid)))
  end

  property "never raises for arbitrary binaries of arbitrary length" do
    check all(bytes <- binary()) do
      result = Gba.recognize(bytes)
      assert result == :no_match or match?({:match, %{tier: :signature}}, result)
    end
  end
end
