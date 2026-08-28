defmodule Playstead.Formats.Validators.Md do
  @moduledoc """
  Tier A (signature-validated) Sega Mega Drive/Genesis header
  recognition (D-14). Confirms the `"SEGA"` console signature at its
  fixed offset (0x100) and reports the serial and region as evidence.
  Pure binary pattern matching only, reads at most the header it
  needs, and never raises for any input.
  """

  @signature_offset 0x100
  @signature "SEGA"
  @header_end 0x1F3

  @doc "Recognizes a Mega Drive/Genesis header, or returns `:no_match` for anything else. Never raises."
  @spec recognize(binary()) :: {:match, map()} | :no_match
  def recognize(binary) when is_binary(binary) do
    if byte_size(binary) >= @header_end do
      check(binary)
    else
      :no_match
    end
  rescue
    _ -> :no_match
  end

  def recognize(_binary), do: :no_match

  defp check(binary) do
    if binary_part(binary, @signature_offset, 4) == @signature do
      {:match,
       %{
         tier: :signature,
         serial: binary_part(binary, 0x183, 14) |> clean_ascii(),
         region: binary_part(binary, 0x1F0, 3) |> clean_ascii()
       }}
    else
      :no_match
    end
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
