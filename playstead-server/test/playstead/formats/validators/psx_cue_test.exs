defmodule Playstead.Formats.Validators.PsxCueTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Playstead.Formats.Validators.PsxCue
  alias Playstead.RomFixtures

  test "matches a valid CUE descriptor" do
    assert {:match, evidence} = PsxCue.recognize(RomFixtures.valid_cue())
    assert evidence.tier == :structure
    assert evidence.files == ["game.bin"]
  end

  test "refuses a descriptor exceeding the entry cap" do
    assert PsxCue.recognize(RomFixtures.cue_exceeding_entry_cap()) == :no_match
  end

  test "refuses input above the size cap" do
    oversized = RomFixtures.valid_cue() <> :binary.copy("x", 70_000)
    assert PsxCue.recognize(oversized) == :no_match
  end

  test "rejects a referenced name containing a parent-directory segment" do
    assert PsxCue.recognize(RomFixtures.cue_with_parent_traversal()) == :no_match
  end

  test "rejects a referenced name that is an absolute path" do
    assert PsxCue.recognize(RomFixtures.cue_with_absolute_path()) == :no_match
  end

  test "rejects a referenced name that is a Windows drive-letter path" do
    assert PsxCue.recognize(RomFixtures.cue_with_windows_drive_path()) == :no_match
  end

  test "rejects a referenced name containing a NUL byte" do
    assert PsxCue.recognize(RomFixtures.cue_with_nul_byte()) == :no_match
  end

  test "accepts only the BINARY file type" do
    cue = "FILE \"game.wav\" WAVE\n  TRACK 01 AUDIO\n    INDEX 01 00:00:00\n"
    assert PsxCue.recognize(cue) == :no_match
  end

  test "does not match empty input" do
    assert PsxCue.recognize(<<>>) == :no_match
  end

  property "never raises for arbitrary binaries of arbitrary length" do
    check all(bytes <- binary()) do
      result = PsxCue.recognize(bytes)
      assert result == :no_match or match?({:match, %{tier: :structure}}, result)
    end
  end
end
