defmodule Playstead.Pairing.DisplayCode do
  @moduledoc """
  The human-readable pairing display code (D-07): 8 characters drawn from
  the same Base-20 consonant alphabet as `Playstead.Codes` (no vowels, no
  ambiguous characters), grouped as `XXXX-XXXX`.

  This code is only ever compared visually by the owner against the
  Mac's screen — it is never an input to any authorization decision.
  Redemption requires the separate 256-bit `device_code` (D-08).
  """

  @alphabet ~c"BCDFGHJKLMNPQRSTVWXZ"
  @alphabet_size length(@alphabet)
  @raw_length 8

  @doc "Generates a fresh grouped display code, e.g. `MKTV-QRZC`."
  @spec generate() :: String.t()
  def generate do
    1..@raw_length
    |> Enum.map(fn _ -> Enum.at(@alphabet, random_index()) end)
    |> List.to_string()
    |> format()
  end

  @doc "Formats an 8-character raw code into two groups of four, hyphen-joined."
  @spec format(String.t()) :: String.t()
  def format(<<a::binary-size(4), b::binary-size(4)>>), do: a <> "-" <> b

  @doc "The alphabet this module draws from, for property-style tests."
  @spec alphabet() :: [char()]
  def alphabet, do: @alphabet

  # Rejection sampling: discard bytes that would introduce modulo bias
  # (256 is not evenly divisible by 20), then retry — same technique as
  # `Playstead.Codes`.
  defp random_index do
    usable_max = 256 - rem(256, @alphabet_size)

    case :crypto.strong_rand_bytes(1) do
      <<byte>> when byte < usable_max -> rem(byte, @alphabet_size)
      _ -> random_index()
    end
  end
end
