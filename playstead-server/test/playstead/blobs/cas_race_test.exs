defmodule Playstead.Blobs.CasRaceTest do
  @moduledoc """
  D-11 / RESEARCH Pitfall 4 under *real* concurrency: genuinely
  independent Postgres connections racing to commit byte-identical
  content. Ecto's sandbox normally runs a whole test on one shared
  connection, which only proves the code path handles a unique
  constraint violation — it can't prove two processes attempting the
  insert at literally the same instant still converge on one row. This
  module switches to `:auto` sandbox mode for its own duration (mirrors
  `Playstead.Sync.SnapshotConcurrencyTest`) so each task gets its own
  pooled connection and the race is real.
  """

  use ExUnit.Case, async: false

  @moduletag :integration

  import Playstead.ImportFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Playstead.Blobs.Blob
  alias Playstead.Blobs.Store.LocalDisk
  alias Playstead.Repo

  import Ecto.Query

  setup_all do
    Sandbox.mode(Repo, :auto)
    on_exit(fn -> Sandbox.mode(Repo, :manual) end)
    :ok
  end

  setup do
    File.mkdir_p!(LocalDisk.blob_path())
    on_exit(fn -> Repo.query!("TRUNCATE blobs, blob_fingerprints RESTART IDENTITY CASCADE") end)
    :ok
  end

  test "ten genuinely concurrent commits of identical bytes converge on exactly one blobs row" do
    bytes = random_bytes(8_192)
    sha256 = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

    tasks =
      for _ <- 1..10 do
        Task.async(fn -> Playstead.Blobs.put_stream([bytes], byte_size(bytes)) end)
      end

    results = Task.await_many(tasks, 15_000)

    assert Enum.all?(results, &match?({:ok, _status, _meta}, &1))
    assert Enum.count(results, fn {:ok, status, _} -> status == :stored end) == 1
    assert Repo.aggregate(from(b in Blob, where: b.sha256 == ^sha256), :count) == 1
  end
end
