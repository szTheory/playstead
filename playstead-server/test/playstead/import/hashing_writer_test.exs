defmodule Playstead.Import.HashingWriterTest do
  use Playstead.DataCase, async: false

  alias Playstead.Blobs.MultiHash
  alias Playstead.Blobs.Store.LocalDisk
  alias Playstead.Import.HashingWriter

  setup do
    File.mkdir_p!(LocalDisk.blob_path())
    :ok
  end

  defp write_all(state, chunks) do
    Enum.reduce(chunks, {:ok, state}, fn
      chunk, {:ok, state} -> HashingWriter.write_chunk(chunk, state)
      chunk, {:error, _reason, state} -> HashingWriter.write_chunk(chunk, state)
    end)
  end

  test "a multi-chunk write's digest equals the single-pass digest of the same bytes" do
    bytes = :crypto.strong_rand_bytes(300_000)
    <<a::binary-size(100_000), b::binary-size(100_000), c::binary-size(100_000)>> = bytes

    assert {:ok, state} = HashingWriter.init([])
    assert {:ok, state} = write_all(state, [a, b, c])
    assert {:ok, state} = HashingWriter.close(state, :done)

    meta = HashingWriter.meta(state)
    on_exit(fn -> File.rm(meta.path) end)
    assert meta.digests.sha256 == MultiHash.sha256_of(bytes)
    assert meta.digests.size_bytes == byte_size(bytes)
  end

  test "uneven chunk sizes produce the same digest as equal-sized chunks" do
    bytes = :crypto.strong_rand_bytes(97)

    {:ok, even_state} = HashingWriter.init([])
    {:ok, even_state} = write_all(even_state, for(<<c::binary-size(1) <- bytes>>, do: c))
    {:ok, even_state} = HashingWriter.close(even_state, :done)

    <<uneven1::binary-size(3), uneven2::binary-size(50), uneven3::binary-size(44)>> = bytes
    {:ok, uneven_state} = HashingWriter.init([])
    {:ok, uneven_state} = write_all(uneven_state, [uneven1, uneven2, uneven3])
    {:ok, uneven_state} = HashingWriter.close(uneven_state, :done)

    on_exit(fn ->
      File.rm(HashingWriter.meta(even_state).path)
      File.rm(HashingWriter.meta(uneven_state).path)
    end)

    assert HashingWriter.meta(even_state).digests.sha256 ==
             HashingWriter.meta(uneven_state).digests.sha256
  end

  test "a successful close leaves the temporary file present with the reported byte count" do
    bytes = :crypto.strong_rand_bytes(1_024)

    {:ok, state} = HashingWriter.init([])
    {:ok, state} = HashingWriter.write_chunk(bytes, state)
    {:ok, state} = HashingWriter.close(state, :done)

    meta = HashingWriter.meta(state)
    on_exit(fn -> File.rm(meta.path) end)
    assert File.exists?(meta.path)
    assert File.stat!(meta.path).size == byte_size(bytes)
    assert meta.digests.size_bytes == byte_size(bytes)
  end

  test "a non-success close removes the temporary file" do
    {:ok, state} = HashingWriter.init([])
    {:ok, state} = HashingWriter.write_chunk("partial", state)
    path = state.path

    assert {:ok, _state} = HashingWriter.close(state, :cancel)
    refute File.exists?(path)
  end

  test "an error reason also removes the temporary file" do
    {:ok, state} = HashingWriter.init([])
    path = state.path

    assert {:ok, _state} = HashingWriter.close(state, {:error, :chunk_timeout})
    refute File.exists?(path)
  end

  test "an unopenable temporary path yields an error tuple rather than raising" do
    # A plain file (not a directory) as the blob path root: `File.mkdir_p`
    # on a "tmp" child of it fails with `:enotdir`/`:eexist` rather than
    # raising. Uses the writer's own `:blob_path` override so this test
    # never touches the shared `PLAYSTEAD_BLOB_PATH` directory or the OS
    # environment (both would race concurrently-running async tests).
    blocking_file =
      Path.join(System.tmp_dir!(), "playstead-hashing-writer-blocker-#{System.unique_integer([:positive])}")

    File.write!(blocking_file, "not a directory")
    on_exit(fn -> File.rm(blocking_file) end)

    assert {:error, _reason} = HashingWriter.init(blob_path: blocking_file)
  end

  test "an upload exceeding the browser ceiling is rejected before the writer is engaged" do
    ceiling = Application.get_env(:playstead, :max_browser_upload_bytes)

    assert {:error, :file_too_large} = HashingWriter.init(size_hint: ceiling + 1)
  end

  test "an upload at exactly the browser ceiling is not rejected by the writer" do
    ceiling = Application.get_env(:playstead, :max_browser_upload_bytes)

    assert {:ok, state} = HashingWriter.init(size_hint: ceiling)
    assert {:ok, state} = HashingWriter.close(state, :done)
    on_exit(fn -> File.rm(state.path) end)
    refute is_nil(state.digests)
  end

  test "the temporary path is under the configured blob volume path" do
    {:ok, state} = HashingWriter.init([])
    on_exit(fn -> File.rm(state.path) end)

    assert String.starts_with?(state.path, LocalDisk.blob_path())
    assert String.contains?(state.path, "/tmp/")
  end

  test "no Task.async/Task.await usage in the writer" do
    source = File.read!("lib/playstead/import/hashing_writer.ex")

    count =
      source
      |> String.split("\n")
      |> Enum.reject(&(String.trim(&1) |> String.starts_with?("#")))
      |> Enum.join("\n")
      |> then(&Regex.scan(~r/Task\.async|Task\.await/, &1))
      |> length()

    assert count == 0
  end
end
