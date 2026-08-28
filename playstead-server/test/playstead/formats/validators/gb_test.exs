defmodule Playstead.Formats.Validators.GbTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Playstead.Formats.Validators.Gb
  alias Playstead.RomFixtures

  test "matches a valid GB header" do
    assert {:match, evidence} = Gb.recognize(RomFixtures.valid_gb())
    assert evidence.tier == :signature
    assert evidence.system == :gb
  end

  test "distinguishes colour-capable cartridges" do
    assert {:match, %{system: :gbc_compatible}} = Gb.recognize(RomFixtures.valid_gb(0x80))
    assert {:match, %{system: :gbc_only}} = Gb.recognize(RomFixtures.valid_gb(0xC0))
  end

  test "does not match another system's valid header" do
    assert Gb.recognize(RomFixtures.valid_gba()) == :no_match
  end

  test "does not match empty input" do
    assert Gb.recognize(<<>>) == :no_match
  end

  test "does not match input truncated before the header ends" do
    assert Gb.recognize(RomFixtures.truncated_gb()) == :no_match
  end

  test "does not match a correct logo with a wrong checksum" do
    assert Gb.recognize(RomFixtures.bad_checksum_gb()) == :no_match
  end

  property "never raises for arbitrary binaries of arbitrary length" do
    check all(bytes <- binary()) do
      result = Gb.recognize(bytes)
      assert result == :no_match or match?({:match, %{tier: :signature}}, result)
    end
  end
end
