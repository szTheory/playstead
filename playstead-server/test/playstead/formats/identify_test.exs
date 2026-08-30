defmodule Playstead.FormatsTest do
  @moduledoc """
  Covers `Playstead.Formats.identify/2`'s bounded-read ceiling (task 1
  of 02-09-PLAN.md): an SNES HiROM image carrying a 512-byte copier
  header needs 512 + 0xFFC0 + 0x20 = 66,048 bytes to be recognized, and
  the pre-#3210-fix 65,536-byte ceiling made that structurally
  impossible regardless of what the caller supplied.
  """
  use ExUnit.Case, async: true

  alias Playstead.Formats
  alias Playstead.RomFixtures

  test "an SNES HiROM image with a copier header is recognized now that the ceiling admits it" do
    assert {:snes, :structure, evidence} =
             Formats.identify(RomFixtures.valid_snes_hirom(true), "game.sfc")

    assert evidence.copier_header == true
    assert evidence.layout == :hirom
  end

  test "an SNES HiROM image without a copier header is still recognized" do
    assert {:snes, :structure, evidence} =
             Formats.identify(RomFixtures.valid_snes_hirom(false), "game.sfc")

    assert evidence.copier_header == false
  end
end
