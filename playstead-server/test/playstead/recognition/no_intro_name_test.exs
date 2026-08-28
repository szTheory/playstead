defmodule Playstead.Recognition.NoIntroNameTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Playstead.Recognition.NoIntroName

  test "parses a standard-convention filename into a title plus region, language, version, and development-status tags" do
    name = "Super Playstead Quest (USA) (En) (v1.1) (Beta).sfc"

    assert {:ok, %{title: "Super Playstead Quest", tags: tags}} = NoIntroName.parse(name)
    assert tags.region == "USA"
    assert tags.languages == "En"
    assert tags.version == "v1.1"
    assert tags.dev_status == "Beta"
  end

  test "an unparseable filename yields no match" do
    assert NoIntroName.parse("just_a_plain_rom_name.gba") == :no_match
  end

  test "does not raise for empty or malformed input" do
    assert NoIntroName.parse("") == :no_match
    assert NoIntroName.parse("(((") == :no_match
  end

  property "never raises for arbitrary strings" do
    check all(str <- string(:printable)) do
      result = NoIntroName.parse(str)
      assert result == :no_match or match?({:ok, %{title: _, tags: _}}, result)
    end
  end
end
