defmodule Playstead.Formats.Validators.MdTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Playstead.Formats.Validators.Md
  alias Playstead.RomFixtures

  test "matches a valid Mega Drive header and reports serial and region" do
    assert {:match, evidence} = Md.recognize(RomFixtures.valid_md("GM 00001009-00", "JUE"))
    assert evidence.tier == :signature
    assert evidence.serial == "GM 00001009-00"
    assert evidence.region == "JUE"
  end

  test "does not match another system's valid header" do
    assert Md.recognize(RomFixtures.valid_gba()) == :no_match
  end

  test "does not match empty input" do
    assert Md.recognize(<<>>) == :no_match
  end

  test "does not match input truncated before the header ends" do
    assert Md.recognize(RomFixtures.truncated_md()) == :no_match
  end

  property "never raises for arbitrary binaries of arbitrary length" do
    check all(bytes <- binary()) do
      result = Md.recognize(bytes)
      assert result == :no_match or match?({:match, %{tier: :signature}}, result)
    end
  end
end
