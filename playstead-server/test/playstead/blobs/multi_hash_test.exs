defmodule Playstead.Blobs.MultiHashTest do
  use ExUnit.Case, async: true

  import Playstead.ImportFixtures

  alias Playstead.Blobs.MultiHash

  test "chunked and single-shot hashing of the same bytes yield the same SHA-256" do
    bytes = random_bytes(5_500_000)

    single_shot = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

    chunked =
      bytes
      |> chunk_uneven([17, 1_048_576, 3, 2_000_000, 999_999])
      |> Enum.reduce(MultiHash.init(), &MultiHash.update(&2, &1))
      |> MultiHash.finalize()

    assert chunked.sha256 == single_shot
  end

  test "the same SHA-256 results whether bytes arrive as one chunk or many uneven chunks" do
    bytes = random_bytes(10_000)

    one_chunk = MultiHash.init() |> MultiHash.update(bytes) |> MultiHash.finalize()

    many_chunks =
      bytes
      |> chunk_uneven([1, 2, 4000, 9995])
      |> Enum.reduce(MultiHash.init(), &MultiHash.update(&2, &1))
      |> MultiHash.finalize()

    assert one_chunk.sha256 == many_chunks.sha256
  end

  test "finalize/1 returns lowercase hexadecimal for all four digests" do
    digests = MultiHash.init() |> MultiHash.update(known_short_bytes()) |> MultiHash.finalize()

    assert digests.sha256 == known_short_bytes_sha256_hex()

    for digest <- [digests.sha256, digests.sha1, digests.md5, digests.crc32] do
      assert digest == String.downcase(digest)
      assert digest =~ ~r/^[0-9a-f]+$/
    end
  end

  test "crc32 is padded to exactly 8 lowercase hex characters" do
    digests = MultiHash.init() |> MultiHash.update("a") |> MultiHash.finalize()
    assert String.length(digests.crc32) == 8
  end

  # Splits `bytes` into chunks of the given uneven sizes, with any
  # remainder as a final chunk.
  defp chunk_uneven(bytes, sizes) do
    {chunks, rest} =
      Enum.reduce(sizes, {[], bytes}, fn size, {acc, remaining} ->
        take = min(size, byte_size(remaining))
        <<chunk::binary-size(take), rest::binary>> = remaining
        {[chunk | acc], rest}
      end)

    Enum.reverse(if rest == <<>>, do: chunks, else: [rest | chunks])
  end
end
