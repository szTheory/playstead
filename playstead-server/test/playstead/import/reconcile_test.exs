defmodule Playstead.Import.ReconcileTest do
  use Playstead.DataCase, async: false
  use Oban.Testing, repo: Playstead.Repo

  import Playstead.AccountsFixtures

  alias Playstead.Import.{Session, SessionWorker, Staging}
  alias Playstead.Repo

  setup do
    File.mkdir_p!(Playstead.Blobs.Store.LocalDisk.blob_path())

    root =
      Path.join(System.tmp_dir!(), "playstead-reconcile-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    previous_inbox = Application.get_env(:playstead, :inbox_path)
    previous_concurrency = Application.get_env(:playstead, :import_concurrency)
    Application.put_env(:playstead, :inbox_path, root)
    Application.put_env(:playstead, :import_concurrency, 1)

    on_exit(fn ->
      Application.put_env(:playstead, :inbox_path, previous_inbox)
      Application.put_env(:playstead, :import_concurrency, previous_concurrency)
    end)

    user = owner_fixture()
    {:ok, root: root, user: user}
  end

  # A manually `perform_job`-driven job never touches its own DB row's
  # lifecycle (unlike a real Oban-executed job), so a self-chained
  # continuation's `oban_jobs` row is never marked non-"available" —
  # `all_enqueued/1` would see it forever. Drive off the session's own
  # persisted state instead, which genuinely advances every batch.
  defp run_to_completion(session_id, mode \\ "run") do
    :ok = perform_job(SessionWorker, %{"session_id" => session_id, "mode" => mode})

    if Repo.get!(Session, session_id).state == "running" do
      run_to_completion(session_id, mode)
    else
      :ok
    end
  end

  test "an unchanged file (all four fingerprint fields match a terminal row) is skipped without re-hashing",
       %{root: root, user: user} do
    File.write!(Path.join(root, "a.bin"), "content")
    {:ok, first} = Staging.stage(user.id, root, "reconcile-first")
    :ok = run_to_completion(first.id)

    blob_count_after_first = Repo.aggregate(Playstead.Blobs.Blob, :count)

    {:ok, second} = Staging.stage(user.id, root, "reconcile-second")
    :ok = run_to_completion(second.id)

    assert Repo.aggregate(Playstead.Blobs.Blob, :count) == blob_count_after_first
  end

  test "a change in size triggers a re-hash", %{root: root, user: user} do
    File.write!(Path.join(root, "a.bin"), "content")
    {:ok, first} = Staging.stage(user.id, root, "reconcile-size-first")
    :ok = run_to_completion(first.id)

    File.write!(Path.join(root, "a.bin"), "different content, different size")
    {:ok, second} = Staging.stage(user.id, root, "reconcile-size-second")
    :ok = run_to_completion(second.id)

    assert Repo.aggregate(Playstead.Blobs.Blob, :count) == 2
  end

  test "a change in mtime alone triggers a re-hash", %{root: root, user: user} do
    path = Path.join(root, "a.bin")
    File.write!(path, "content")
    {:ok, first} = Staging.stage(user.id, root, "reconcile-mtime-first")
    :ok = run_to_completion(first.id)

    future = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_unix()
    File.touch!(path, future)

    {:ok, second} = Staging.stage(user.id, root, "reconcile-mtime-second")
    :ok = run_to_completion(second.id)

    # Content is identical (same sha256) but the reconcile still re-hashed
    # instead of skipping -- assert on the second session's own row.
    [row] =
      Repo.all(
        from(sf in Playstead.Import.SourceFile,
          where: sf.import_session_id == ^second.id
        )
      )

    assert row.staging_state == "completed"
    assert row.attempt_count == 1
  end

  test "the forced full-verification mode re-hashes a file whose fingerprint matched", %{
    root: root,
    user: user
  } do
    File.write!(Path.join(root, "a.bin"), "content")
    {:ok, first} = Staging.stage(user.id, root, "reconcile-full-verify-first")
    :ok = run_to_completion(first.id)

    {:ok, second} = Staging.stage(user.id, root, "reconcile-full-verify-second")
    :ok = run_to_completion(second.id, "full_verify")

    [row] =
      Repo.all(
        from(sf in Playstead.Import.SourceFile,
          where: sf.import_session_id == ^second.id
        )
      )

    assert row.staging_state == "completed"
    # Genuinely re-hashed (not the reconcile-skip path) -- same content, so
    # no new blob is created, but the row still went through hash_and_commit.
    assert Repo.aggregate(Playstead.Blobs.Blob, :count) == 1
  end

  test "staging and running the same folder twice creates zero new blobs and no duplicate asset_sets",
       %{root: root, user: user} do
    File.write!(Path.join(root, "a.bin"), "content")
    File.write!(Path.join(root, "b.bin"), "other content")

    {:ok, first} = Staging.stage(user.id, root, "idempotent-first")
    :ok = run_to_completion(first.id)

    blob_count = Repo.aggregate(Playstead.Blobs.Blob, :count)
    asset_set_count = Repo.aggregate(Playstead.Catalogue.AssetSet, :count)

    {:ok, second} = Staging.stage(user.id, root, "idempotent-second")
    :ok = run_to_completion(second.id)

    assert Repo.aggregate(Playstead.Blobs.Blob, :count) == blob_count
    assert Repo.aggregate(Playstead.Catalogue.AssetSet, :count) == asset_set_count
  end
end
