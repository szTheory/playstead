defmodule Playstead.Blobs.Store.LocalDiskRangeTest do
  @moduledoc """
  D-19: `LocalDisk.build_stream/2`'s range clause must never load a
  whole object into memory to serve a range (T-03-05). This exercises
  it against a fixture object larger than the module's own
  `@chunk_size` and asserts the stream yields only the requested
  extent, in bounded chunks rather than one materialised binary.
  """

  use Playstead.DataCase, async: false

  import Playstead.ImportFixtures

  alias Playstead.Blobs.Store.LocalDisk

  # Mirrors LocalDisk's own @chunk_size (1 MiB) — kept as a literal here
  # since the module does not expose it, matching the read-only
  # black-box discipline the rest of this test suite uses.
  @chunk_size 1_048_576

  setup do
    File.mkdir_p!(LocalDisk.blob_path())
    :ok
  end

  test "a range on an object larger than the chunk size returns only the requested extent, in bounded reads" do
    bytes = random_bytes(@chunk_size * 3)
    {:ok, :stored, meta} = Playstead.Blobs.put_stream([bytes], byte_size(bytes))

    first = @chunk_size + 100
    last = @chunk_size * 2 + 100

    {:ok, stream} = LocalDisk.stream(meta.sha256, first..last)
    chunks = Enum.to_list(stream)

    # Every yielded chunk is bounded by @chunk_size — proof the range
    # clause reads positionally rather than pulling the whole object
    # (or even the whole requested extent) into memory in one shot.
    assert Enum.all?(chunks, &(byte_size(&1) <= @chunk_size))
    assert length(chunks) > 1

    body = IO.iodata_to_binary(chunks)
    assert body == binary_part(bytes, first, last - first + 1)
  end

  test "a range whose last byte is clamped to size - 1 never reads past the object's end" do
    bytes = random_bytes(500)
    {:ok, :stored, meta} = Playstead.Blobs.put_stream([bytes], byte_size(bytes))

    {:ok, stream} = LocalDisk.stream(meta.sha256, 100..10_000)
    body = stream |> Enum.to_list() |> IO.iodata_to_binary()

    assert body == binary_part(bytes, 100, 400)
  end
end
