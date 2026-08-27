defmodule Playstead.Codes do
  @moduledoc """
  Human-comparable random codes built from a Base-20 consonant alphabet
  (D-07's pairing display code convention, e.g. `MKTV-QRZC`) — reused here
  for recovery codes (D-05b) so both surfaces share one visual language.

  Vowels are excluded so codes never accidentally spell words, and
  characters are drawn with rejection sampling against
  `:crypto.strong_rand_bytes/1` so the distribution is uniform (a plain
  `rem/2` against a byte would bias toward the first characters of the
  alphabet, since 256 is not a multiple of 20).
  """

  @alphabet ~c"BCDFGHJKLMNPQRSTVWXZ"
  @alphabet_size length(@alphabet)

  @doc """
  Generates a single grouped code of `group_count` groups of `group_size`
  characters each, joined with `-` (e.g. `random_code(2, 4)` produces
  something shaped like `MKTV-QRZC`).
  """
  def random_code(group_count \\ 2, group_size \\ 4) do
    1..group_count
    |> Enum.map(fn _ -> random_group(group_size) end)
    |> Enum.join("-")
  end

  defp random_group(size) do
    1..size
    |> Enum.map(fn _ -> Enum.at(@alphabet, random_index()) end)
    |> List.to_string()
  end

  # Rejection sampling: discard bytes that would introduce modulo bias
  # (256 is not evenly divisible by 20), then retry.
  defp random_index do
    usable_max = 256 - rem(256, @alphabet_size)

    case :crypto.strong_rand_bytes(1) do
      <<byte>> when byte < usable_max -> rem(byte, @alphabet_size)
      _ -> random_index()
    end
  end
end
