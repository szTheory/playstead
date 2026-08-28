defmodule Playstead.Formats.Validators.SnesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Playstead.Formats.Validators.Snes
  alias Playstead.RomFixtures

  test "matches a valid LoROM header and labels the result structural" do
    assert {:match, evidence} = Snes.recognize(RomFixtures.valid_snes_lorom())
    assert evidence.tier == :structure
    assert evidence.layout == :lorom
  end

  test "matches a valid HiROM header" do
    assert {:match, evidence} = Snes.recognize(RomFixtures.valid_snes_hirom())
    assert evidence.layout == :hirom
  end

  test "applies the copier-header offset rule" do
    assert {:match, evidence} = Snes.recognize(RomFixtures.valid_snes_lorom(true))
    assert evidence.copier_header == true
  end

  test "does not match another system's valid header" do
    assert Snes.recognize(RomFixtures.valid_gba()) == :no_match
  end

  test "does not match empty input" do
    assert Snes.recognize(<<>>) == :no_match
  end

  test "does not match input truncated before the header ends" do
    assert Snes.recognize(binary_part(RomFixtures.valid_snes_lorom(), 0, 100)) == :no_match
  end

  property "never raises for arbitrary binaries of arbitrary length" do
    check all(bytes <- binary()) do
      result = Snes.recognize(bytes)
      assert result == :no_match or match?({:match, %{tier: :structure}}, result)
    end
  end
end
