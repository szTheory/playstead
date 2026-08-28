defmodule Playstead.Formats.Validators.Gb do
  @moduledoc """
  Tier A (signature-validated) Game Boy / Game Boy Color header
  recognition (D-14, Pan Docs). Confirms the fixed logo bytes and the
  header checksum, and distinguishes colour-capable cartridges via the
  CGB flag. Pure binary pattern matching only, reads at most the
  header it needs, and never raises for any input.
  """

  @header_end 0x150
  @logo <<0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B>>

  @doc "Recognizes a GB/GBC header, or returns `:no_match` for anything else. Never raises."
  @spec recognize(binary()) :: {:match, map()} | :no_match
  def recognize(binary) when is_binary(binary) do
    if byte_size(binary) >= @header_end do
      binary |> binary_part(0, @header_end) |> check()
    else
      :no_match
    end
  rescue
    _ -> :no_match
  end

  def recognize(_binary), do: :no_match

  defp check(header) do
    if binary_part(header, 0x104, 8) == @logo do
      verify_checksum(header)
    else
      :no_match
    end
  end

  defp verify_checksum(header) do
    expected = :binary.at(header, 0x14D)
    computed = compute_checksum(header)

    if expected == computed do
      {:match,
       %{
         tier: :signature,
         title: binary_part(header, 0x134, 15) |> clean_ascii(),
         system: colour_system(:binary.at(header, 0x143))
       }}
    else
      :no_match
    end
  end

  defp colour_system(0x80), do: :gbc_compatible
  defp colour_system(0xC0), do: :gbc_only
  defp colour_system(_other), do: :gb

  defp compute_checksum(header) do
    0x134..0x14C
    |> Enum.reduce(0, fn i, acc -> acc - :binary.at(header, i) - 1 end)
    |> Bitwise.band(0xFF)
  end

  defp clean_ascii(bytes) do
    bytes
    |> :binary.bin_to_list()
    |> Enum.take_while(&(&1 != 0 and &1 < 128))
    |> List.to_string()
  rescue
    _ -> ""
  end
end
