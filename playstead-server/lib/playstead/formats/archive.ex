defmodule Playstead.Formats.Archive do
  @moduledoc """
  Opaque archive/container detection by leading magic bytes only (D-21,
  T-02-19). Detection stops the instant a signature matches: nothing is
  listed, no central directory is read, no byte is decompressed, and no
  declared internal size is ever consulted — declared sizes lie, which
  is exactly why deep archive inspection is a separate, deferred spike
  with its own adversarial corpus and isolation requirements.

  Detection is by magic bytes and never by extension: a renamed archive
  is still recognised, and a ROM wearing a misleading archive extension
  is still read as a ROM by `Playstead.Formats.identify/2` (magic-byte
  archive detection runs first and short-circuits only on an actual
  match).
  """

  @signatures [
    {:zip, <<0x50, 0x4B, 0x03, 0x04>>},
    {:zip, <<0x50, 0x4B, 0x05, 0x06>>},
    {:zip, <<0x50, 0x4B, 0x07, 0x08>>},
    {:sevenz, <<0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C>>},
    {:rar, <<0x52, 0x61, 0x72, 0x21, 0x1A, 0x07>>},
    {:gzip, <<0x1F, 0x8B>>},
    {:xz, <<0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00>>},
    {:zstd, <<0x28, 0xB5, 0x2F, 0xFD>>}
  ]

  @doc """
  Detects a container by its leading magic bytes. Returns
  `{:match, kind}` for a recognised container signature or `:no_match`
  for anything else, including empty and truncated input. Never raises.
  """
  @spec detect(binary()) :: {:match, atom()} | :no_match
  def detect(binary) when is_binary(binary) do
    Enum.find_value(@signatures, :no_match, fn {kind, signature} ->
      if match_prefix?(binary, signature), do: {:match, kind}
    end)
  rescue
    _ -> :no_match
  end

  def detect(_binary), do: :no_match

  defp match_prefix?(binary, signature) do
    size = byte_size(signature)
    byte_size(binary) >= size and binary_part(binary, 0, size) == signature
  end
end
