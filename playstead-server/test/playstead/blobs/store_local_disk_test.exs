defmodule Playstead.Blobs.Store.LocalDiskTest do
  use Playstead.DataCase, async: false

  import Playstead.ImportFixtures

  alias Playstead.Blobs.Blob
  alias Playstead.Blobs.Store.LocalDisk
  alias Playstead.Import.OrphanSweeper

  setup do
    blob_path = LocalDisk.blob_path()
    File.mkdir_p!(blob_path)
    :ok
  end

  defp put(bytes) do
    Playstead.Blobs.put_stream([bytes], byte_size(bytes))
  end

  test "a write of new content returns {:ok, :stored} and the bytes appear at the two-level content-addressed path" do
    bytes = random_bytes(2_048)
    {:ok, :stored, meta} = put(bytes)

    path = LocalDisk.object_path(LocalDisk.blob_path(), meta.sha256)
    assert File.read!(path) == bytes

    <<a::binary-size(2), b::binary-size(2), _rest::binary>> = meta.sha256
    assert path =~ "objects/sha256/#{a}/#{b}/#{meta.sha256}"
  end

  test "a write of content already present with a database row returns {:ok, :existing} and does not rewrite the file" do
    bytes = random_bytes(1_024)
    {:ok, :stored, meta} = put(bytes)

    path = LocalDisk.object_path(LocalDisk.blob_path(), meta.sha256)
    original_mtime = File.stat!(path).mtime

    Process.sleep(1_100)
    assert {:ok, :existing, meta2} = put(bytes)
    assert meta2.sha256 == meta.sha256
    assert File.stat!(path).mtime == original_mtime
    assert Repo.aggregate(Blob, :count) == 1
  end

  test "re-hashing after fsync detects on-disk bytes that differ from the streamed digest and refuses the commit" do
    before = count_objects()
    {:ok, ref} = LocalDisk.open_write(4)
    {:ok, ref} = LocalDisk.write_chunk(ref, "abcd")

    # Tamper with the temp file's bytes on disk before commit re-hashes it.
    File.write!(ref.tmp_path, "zzzz")

    assert {:error, :hash_mismatch} = LocalDisk.commit(ref, [])
    refute File.exists?(ref.tmp_path)
    assert count_objects() == before
  end

  test "a failed or aborted write leaves no file under objects/ and no temporary file behind" do
    before = count_objects()
    {:ok, ref} = LocalDisk.open_write(10)
    {:ok, ref} = LocalDisk.write_chunk(ref, "hello")
    :ok = LocalDisk.abort(ref)

    refute File.exists?(ref.tmp_path)
    assert count_objects() == before
  end

  test "two concurrent commits of byte-identical content produce exactly one blobs row" do
    bytes = random_bytes(4_096)

    tasks =
      for _ <- 1..8 do
        Task.async(fn -> put(bytes) end)
      end

    results = Task.await_many(tasks, 10_000)

    assert Enum.all?(results, fn
             {:ok, :stored, _meta} -> true
             {:ok, :existing, _meta} -> true
             _ -> false
           end)

    assert Enum.count(results, fn {:ok, status, _} -> status == :stored end) == 1
    assert Repo.aggregate(from(b in Blob, where: b.sha256 == ^sha256_hex(bytes)), :count) == 1
  end

  test "a file present at the content-addressed path with no database row is re-hashed and adopted" do
    bytes = random_bytes(512)
    sha256 = sha256_hex(bytes)
    path = LocalDisk.object_path(LocalDisk.blob_path(), sha256)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, bytes)

    assert Repo.aggregate(from(b in Blob, where: b.sha256 == ^sha256), :count) == 0

    assert {:ok, _status, meta} = put(bytes)
    assert meta.sha256 == sha256
    assert Repo.aggregate(from(b in Blob, where: b.sha256 == ^sha256), :count) == 1
    assert File.read!(path) == bytes
  end

  test "opening a write when free space is below the required margin returns a disk-full error before any bytes are written" do
    huge = Playstead.Readiness.free_bytes(LocalDisk.blob_path())

    case huge do
      available when is_integer(available) ->
        assert {:error, :insufficient_space} = LocalDisk.open_write(available * 1000)

      :unknown ->
        :ok
    end
  end

  test "the orphan sweeper removes a stale temporary file and leaves a committed blob untouched" do
    bytes = random_bytes(64)
    {:ok, :stored, meta} = put(bytes)
    object = LocalDisk.object_path(LocalDisk.blob_path(), meta.sha256)

    {:ok, stale_ref} = LocalDisk.open_write(4)
    {:ok, _stale_ref} = LocalDisk.write_chunk(stale_ref, "orph")
    File.close(stale_ref.io_device)

    assert File.exists?(stale_ref.tmp_path)
    OrphanSweeper.sweep(0)

    refute File.exists?(stale_ref.tmp_path)
    assert File.exists?(object)
  end

  defp sha256_hex(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp count_objects do
    objects_dir = Path.join(LocalDisk.blob_path(), "objects")

    case File.exists?(objects_dir) do
      true ->
        objects_dir |> Path.join("**/*") |> Path.wildcard() |> Enum.count(&(not File.dir?(&1)))

      false ->
        0
    end
  end
end
