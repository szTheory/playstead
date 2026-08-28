defmodule Playstead.Formats.Validators.Gba do
  @moduledoc """
  Tier A (signature-validated) Game Boy Advance header recognition
  (D-14, GBATEK). Confirms the fixed Nintendo logo bytes and the header
  checksum, and reports the ASCII title and game code as evidence.
  Pure binary pattern matching only, reads at most the 192-byte header,
  and never raises for any input.
  """

  @header_size 192
  # GBATEK-documented fixed logo bytes (first 12 of the 156-byte logo
  # block) that every GBA boot ROM and open-source validator checks.
  @logo_prefix <<0x24, 0xFF, 0xAE, 0x51, 0x69, 0x9A, 0xA2, 0x21, 0x3D, 0x84, 0x82, 0x0A>>

  @doc "Recognizes a GBA header, or returns `:no_match` for anything else. Never raises."
  @spec recognize(binary()) :: {:match, map()} | :no_match
  def recognize(binary) when is_binary(binary) do
    if byte_size(binary) >= @header_size do
      binary |> binary_part(0, @header_size) |> check()
    else
      :no_match
    end
  rescue
    _ -> :no_match
  end

  def recognize(_binary), do: :no_match

  defp check(header) do
    if binary_part(header, 0x04, 12) == @logo_prefix do
      verify_checksum(header)
    else
      :no_match
    end
  end

  defp verify_checksum(header) do
    expected = :binary.at(header, 0xBD)
    computed = compute_checksum(header)

    if expected == computed do
      {:match,
       %{
         tier: :signature,
         title: binary_part(header, 0xA0, 12) |> clean_ascii(),
         game_code: binary_part(header, 0xAC, 4) |> clean_ascii()
       }}
    else
      :no_match
    end
  end

  defp compute_checksum(header) do
    0xA0..0xBC
    |> Enum.reduce(0, fn i, acc -> acc - :binary.at(header, i) end)
    |> Kernel.-(0x19)
    |> Bitwise.band(0xFF)
  end

  defp clean_ascii(bytes) do
    bytes
    |> :binary.bin_to_list()
    |> Enum.take_while(&(&1 != 0))
    |> List.to_string()
  rescue
    _ -> ""
  end
end
