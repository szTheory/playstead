defmodule Playstead.Formats.Validators.Snes do
  @moduledoc """
  Tier B (structure-validated) SNES header recognition (D-14). SNES
  carries no fixed magic signature, so this applies the internal
  checksum/complement relationship at both the LoROM and HiROM header
  locations, with and without a 512-byte copier header. Its result is
  always labelled with the structural tier so no consumer mistakes a
  heuristic pass for a confirmed signature. Pure binary pattern
  matching only, and never raises for any input.
  """

  @copier_offset 512
  @lorom_header 0x7FC0
  @hirom_header 0xFFC0

  @doc "Recognizes an SNES internal header, or returns `:no_match` for anything else. Never raises."
  @spec recognize(binary()) :: {:match, map()} | :no_match
  def recognize(binary) when is_binary(binary) do
    check(binary, 0, :lorom, @lorom_header) ||
      check(binary, 0, :hirom, @hirom_header) ||
      check(binary, @copier_offset, :lorom, @lorom_header) ||
      check(binary, @copier_offset, :hirom, @hirom_header) ||
      :no_match
  rescue
    _ -> :no_match
  end

  def recognize(_binary), do: :no_match

  defp check(binary, offset, layout, header_offset) do
    header_start = offset + header_offset

    if byte_size(binary) >= header_start + 0x20 do
      checksum = read_le16(binary, header_start + 0x1C)
      complement = read_le16(binary, header_start + 0x1E)

      if checksum != 0 and Bitwise.bxor(checksum, complement) == 0xFFFF do
        {:match,
         %{tier: :structure, layout: layout, checksum: checksum, copier_header: offset > 0}}
      end
    end
  end

  defp read_le16(binary, offset) do
    <<lo, hi>> = binary_part(binary, offset, 2)
    hi * 256 + lo
  end
end
