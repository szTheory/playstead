defmodule Playstead.RomFixtures do
  @moduledoc """
  Byte-level fixture corpus for every format validator (task 1 of
  02-03-PLAN.md): valid headers, truncated headers, checksum-mismatch
  headers, cross-system extension confusion, and archive magic bytes.
  """

  @gba_logo <<0x24, 0xFF, 0xAE, 0x51, 0x69, 0x9A, 0xA2, 0x21, 0x3D, 0x84, 0x82, 0x0A>>
  @gb_logo <<0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B>>

  @doc "A valid 192-byte GBA header with a correct logo prefix and checksum."
  def valid_gba(title \\ "PLAYSTEAD") do
    base = :binary.copy(<<0>>, 192)

    base =
      base
      |> replace_bytes(0x04, @gba_logo)
      |> replace_bytes(0xA0, pad(title, 12))
      |> replace_bytes(0xAC, pad("PSTD", 4))
      |> replace_bytes(0xB0, pad("01", 2))
      |> replace_bytes(0xB2, <<0x96>>)

    checksum = compute_gba_checksum(base)
    replace_bytes(base, 0xBD, <<checksum>>)
  end

  defp compute_gba_checksum(header) do
    0xA0..0xBC
    |> Enum.reduce(0, fn i, acc -> acc - :binary.at(header, i) end)
    |> Kernel.-(0x19)
    |> Bitwise.band(0xFF)
  end

  def truncated_gba, do: binary_part(valid_gba(), 0, 100)

  def bad_checksum_gba do
    valid = valid_gba()
    bad_byte = Bitwise.bxor(:binary.at(valid, 0xBD), 0xFF)

    binary_part(valid, 0, 0xBD) <>
      <<bad_byte>> <> binary_part(valid, 0xBE, byte_size(valid) - 0xBE)
  end

  @doc "A valid Game Boy header (0x150 bytes) with correct logo and checksum."
  def valid_gb(cgb_flag \\ 0x00) do
    prefix = :binary.copy(<<0>>, 0x104)
    logo = @gb_logo <> :binary.copy(<<0>>, 48 - 8)
    title = pad("PLAYSTEAD", 15) <> <<cgb_flag>>
    rest_before_checksum = :binary.copy(<<0>>, 0x14D - 0x144)

    header_without_checksum = prefix <> logo <> title <> rest_before_checksum
    checksum = compute_gb_checksum(header_without_checksum <> <<0>>)

    header_without_checksum <> <<checksum>> <> <<0, 0>>
  end

  defp compute_gb_checksum(header) do
    0x134..0x14C
    |> Enum.reduce(0, fn i, acc -> acc - :binary.at(header, i) - 1 end)
    |> Bitwise.band(0xFF)
  end

  def truncated_gb, do: binary_part(valid_gb(), 0, 50)

  def bad_checksum_gb do
    valid = valid_gb()
    bad_byte = Bitwise.bxor(:binary.at(valid, 0x14D), 0xFF)

    binary_part(valid, 0, 0x14D) <>
      <<bad_byte>> <> binary_part(valid, 0x14E, byte_size(valid) - 0x14E)
  end

  @doc "A valid iNES header (16 bytes)."
  def valid_nes_ines(mapper \\ 1) do
    flags6 = Bitwise.bsl(Bitwise.band(mapper, 0x0F), 4)
    flags7 = Bitwise.band(mapper, 0xF0)
    <<0x4E, 0x45, 0x53, 0x1A, 1, 1, flags6, flags7, 0, 0, 0, 0, 0, 0, 0, 0>>
  end

  @doc "A valid NES 2.0 header (16 bytes)."
  def valid_nes2(mapper \\ 2) do
    flags6 = Bitwise.bsl(Bitwise.band(mapper, 0x0F), 4)
    flags7 = Bitwise.bor(Bitwise.band(mapper, 0xF0), 0x08)
    <<0x4E, 0x45, 0x53, 0x1A, 1, 1, flags6, flags7, 0, 0, 0, 0, 0, 0, 0, 0>>
  end

  def truncated_nes, do: binary_part(valid_nes_ines(), 0, 8)

  @doc "A valid SNES LoROM header at 0x7FC0 with checksum/complement satisfied."
  def valid_snes_lorom(copier? \\ false) do
    build_snes(0x7FC0, copier?)
  end

  def valid_snes_hirom(copier? \\ false) do
    build_snes(0xFFC0, copier?)
  end

  defp build_snes(header_offset, copier?) do
    offset = if copier?, do: 512, else: 0
    total_size = offset + header_offset + 0x20
    base = :binary.copy(<<0>>, total_size)

    checksum = 0x1234
    complement = Bitwise.bxor(checksum, 0xFFFF)

    checksum_le = <<Bitwise.band(checksum, 0xFF), Bitwise.bsr(checksum, 8)>>
    complement_le = <<Bitwise.band(complement, 0xFF), Bitwise.bsr(complement, 8)>>

    checksum_pos = offset + header_offset + 0x1C

    base
    |> replace_bytes(checksum_pos, checksum_le)
    |> replace_bytes(checksum_pos + 2, complement_le)
  end

  defp replace_bytes(binary, pos, bytes) do
    prefix = binary_part(binary, 0, pos)
    suffix_start = pos + byte_size(bytes)
    suffix = binary_part(binary, suffix_start, byte_size(binary) - suffix_start)
    prefix <> bytes <> suffix
  end

  @doc "A valid Mega Drive header with SEGA signature at 0x100."
  def valid_md(serial \\ "GM 00000000-00", region \\ "JUE") do
    total_size = 0x1F3
    base = :binary.copy(<<0x20>>, total_size)

    base
    |> replace_bytes(0x100, "SEGA")
    |> replace_bytes(0x183, pad(serial, 14))
    |> replace_bytes(0x1F0, pad(region, 3))
  end

  def truncated_md, do: binary_part(valid_md(), 0, 0x110)

  # Archive magic-byte fixtures (D-21) — signature bytes only, never a
  # real archive body, since detection must never open the container.
  def zip_magic, do: <<0x50, 0x4B, 0x03, 0x04>> <> :binary.copy(<<0>>, 16)
  def sevenz_magic, do: <<0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C>> <> :binary.copy(<<0>>, 16)
  def rar_magic, do: <<0x52, 0x61, 0x72, 0x21, 0x1A, 0x07>> <> :binary.copy(<<0>>, 16)
  def gzip_magic, do: <<0x1F, 0x8B>> <> :binary.copy(<<0>>, 16)
  def xz_magic, do: <<0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00>> <> :binary.copy(<<0>>, 16)
  def zstd_magic, do: <<0x28, 0xB5, 0x2F, 0xFD>> <> :binary.copy(<<0>>, 16)

  @doc "A zip whose extension is misleadingly a ROM extension — detection is by bytes only."
  def zip_with_rom_extension_bytes, do: zip_magic()

  @doc "A valid GBA header immediately followed by a zip signature — bytes win over any archive claim."
  def gba_polyglot_with_trailing_archive do
    valid_gba() <> <<0x50, 0x4B, 0x03, 0x04>>
  end

  # CUE descriptor fixtures.
  def valid_cue(bin_name \\ "game.bin") do
    """
    FILE "#{bin_name}" BINARY
      TRACK 01 MODE1/2352
        INDEX 01 00:00:00
    """
  end

  def cue_with_parent_traversal do
    """
    FILE "../secret.bin" BINARY
      TRACK 01 MODE1/2352
        INDEX 01 00:00:00
    """
  end

  def cue_with_absolute_path do
    """
    FILE "/etc/passwd" BINARY
      TRACK 01 MODE1/2352
        INDEX 01 00:00:00
    """
  end

  def cue_with_windows_drive_path do
    """
    FILE "C:\\\\Windows\\\\system.bin" BINARY
      TRACK 01 MODE1/2352
        INDEX 01 00:00:00
    """
  end

  def cue_with_nul_byte do
    "FILE \"game\0.bin\" BINARY\n  TRACK 01 MODE1/2352\n    INDEX 01 00:00:00\n"
  end

  def cue_exceeding_entry_cap do
    tracks =
      1..100
      |> Enum.map(fn n ->
        "  TRACK #{String.pad_leading(to_string(n), 2, "0")} MODE1/2352\n    INDEX 01 00:00:00"
      end)
      |> Enum.join("\n")

    "FILE \"game.bin\" BINARY\n" <> tracks <> "\n"
  end

  defp pad(str, size) do
    bytes = :binary.part(str <> :binary.copy(<<0>>, size), 0, size)
    bytes
  end
end
