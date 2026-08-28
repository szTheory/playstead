defmodule Playstead.Formats.Validators.Nes do
  @moduledoc """
  Tier A (signature-validated) NES header recognition (D-14, nesdev
  iNES/NES 2.0). Confirms the `"NES\\x1A"` magic and reports the
  mapper number plus header generation (original iNES vs NES 2.0).
  Pure binary pattern matching only, reads at most the 16-byte header,
  and never raises for any input.
  """

  @header_size 16
  @magic <<0x4E, 0x45, 0x53, 0x1A>>

  @doc "Recognizes an iNES/NES 2.0 header, or returns `:no_match` for anything else. Never raises."
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

  defp check(<<@magic, _prg, _chr, flags6, flags7, _rest::binary>>) do
    mapper = Bitwise.bor(Bitwise.band(flags7, 0xF0), Bitwise.bsr(flags6, 4))
    generation = if Bitwise.band(flags7, 0x0C) == 0x08, do: :nes2, else: :ines

    {:match, %{tier: :signature, mapper: mapper, generation: generation}}
  end

  defp check(_header), do: :no_match
end
