defmodule Playstead.Formats.Validators.NesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Playstead.Formats.Validators.Nes
  alias Playstead.RomFixtures

  test "matches an original iNES header and reports mapper" do
    assert {:match, evidence} = Nes.recognize(RomFixtures.valid_nes_ines(1))
    assert evidence.tier == :signature
    assert evidence.generation == :ines
    assert evidence.mapper == 1
  end

  test "matches an NES 2.0 header and reports mapper" do
    assert {:match, evidence} = Nes.recognize(RomFixtures.valid_nes2(2))
    assert evidence.generation == :nes2
    assert evidence.mapper == 2
  end

  test "does not match another system's valid header" do
    assert Nes.recognize(RomFixtures.valid_gba()) == :no_match
  end

  test "does not match empty input" do
    assert Nes.recognize(<<>>) == :no_match
  end

  test "does not match input truncated before the header ends" do
    assert Nes.recognize(RomFixtures.truncated_nes()) == :no_match
  end

  property "never raises for arbitrary binaries of arbitrary length" do
    check all(bytes <- binary()) do
      result = Nes.recognize(bytes)
      assert result == :no_match or match?({:match, %{tier: :signature}}, result)
    end
  end
end
