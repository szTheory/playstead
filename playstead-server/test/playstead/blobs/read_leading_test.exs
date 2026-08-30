defmodule Playstead.Blobs.ReadLeadingTest do
  @moduledoc """
  Bounded-read proof for `Playstead.Blobs.read_leading/2` through the
  `Playstead.Blobs` seam (task 1 of 02-09-PLAN.md): a stored object
  shorter than the budget returns all of its bytes, a stored object
  longer than the budget returns exactly the budget's worth, an
  unknown digest is `{:error, :not_found}`, and the committed object is
  never touched by the read.
  """
  use Playstead.DataCase, async: false

  import ExUnit.CaptureLog
  import Playstead.ImportFixtures

  alias Playstead.Blobs
  alias Playstead.Blobs.Store.LocalDisk

  setup do
    File.mkdir_p!(LocalDisk.blob_path())
    :ok
  end

  defp put(bytes) do
    {:ok, _status, meta} = Blobs.put_stream([bytes], byte_size(bytes))
    meta
  end

  test "a stored object shorter than the budget returns all of its bytes" do
    bytes = random_bytes(40)
    meta = put(bytes)

    assert {:ok, ^bytes} = Blobs.read_leading(meta.sha256, 66_048)
  end

  test "a stored object longer than the budget returns exactly the budget's worth, matching the object's own leading bytes" do
    bytes = random_bytes(100_000)
    meta = put(bytes)

    assert {:ok, leading} = Blobs.read_leading(meta.sha256, 66_048)
    assert byte_size(leading) == 66_048
    assert leading == binary_part(bytes, 0, 66_048)
  end

  test "an unknown digest returns {:error, :not_found}" do
    assert {:error, :not_found} = Blobs.read_leading(String.duplicate("0", 64), 66_048)
  end

  test "the committed object still exists with its original size after the read" do
    bytes = random_bytes(100_000)
    meta = put(bytes)

    path = LocalDisk.object_path(LocalDisk.blob_path(), meta.sha256)
    original_size = File.stat!(path).size

    {:ok, _leading} = Blobs.read_leading(meta.sha256, 66_048)

    assert File.exists?(path)
    assert File.stat!(path).size == original_size
    assert File.read!(path) == bytes
  end

  test "defaults the byte count to 66,048 when none is given" do
    bytes = random_bytes(100_000)
    meta = put(bytes)

    assert {:ok, leading} = Blobs.read_leading(meta.sha256)
    assert byte_size(leading) == 66_048
  end

  # WR-01 regression: an open failure other than :enoent (a permissions
  # fault here) must still degrade to {:error, :not_found} for the
  # caller's existing nil-degradation behaviour, but — unlike a
  # genuinely missing object — it must be logged distinctly so an
  # operational fault on the blob volume is not silently indistinguishable
  # from "no such object."
  test "an open failure other than :enoent still returns {:error, :not_found} but is logged distinctly" do
    bytes = random_bytes(64)
    meta = put(bytes)
    path = LocalDisk.object_path(LocalDisk.blob_path(), meta.sha256)

    File.chmod!(path, 0o000)

    on_exit(fn -> File.chmod(path, 0o644) end)

    log =
      capture_log(fn ->
        assert {:error, :not_found} = Blobs.read_leading(meta.sha256, 66_048)
      end)

    assert log =~ "read_leading/2 failed to open committed object #{meta.sha256}"
  end
end
