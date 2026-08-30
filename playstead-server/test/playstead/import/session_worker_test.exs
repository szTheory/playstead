defmodule Playstead.Import.SessionWorkerTest.InsufficientSpaceStore do
  @moduledoc false
  @behaviour Playstead.Blobs.Store

  @impl true
  def open_write(_byte_size_hint), do: {:error, :insufficient_space}

  @impl true
  def write_chunk(ref, _chunk), do: {:ok, ref}

  @impl true
  def commit(_ref, _opts \\ []), do: {:error, :insufficient_space}

  @impl true
  def abort(_ref), do: :ok

  @impl true
  def exists?(_sha256), do: false

  @impl true
  def stat(_sha256), do: {:error, :not_found}

  @impl true
  def byte_size_of(_sha256), do: {:error, :not_found}

  @impl true
  def stream(_sha256, _range \\ nil), do: {:error, :not_found}

  @impl true
  def read_leading(_sha256, _byte_count), do: {:error, :not_found}

  @impl true
  def digest_from_offset(_sha256, _offset), do: {:error, :not_found}

  @impl true
  def free_bytes, do: 0

  @impl true
  def writable?, do: true

  @impl true
  def delete(_path), do: :ok

  @impl true
  def adopt_temp_file(_path, _digest_map), do: {:error, :insufficient_space}
end

defmodule Playstead.Import.SessionWorkerTest do
  use Playstead.DataCase, async: false
  use Oban.Testing, repo: Playstead.Repo

  import Playstead.AccountsFixtures

  alias Playstead.AuditLog
  alias Playstead.Import
  alias Playstead.Import.{Session, SessionWorker, SourceFile, Staging}
  alias Playstead.Repo

  setup do
    File.mkdir_p!(Playstead.Blobs.Store.LocalDisk.blob_path())

    root =
      Path.join(System.tmp_dir!(), "playstead-worker-test-#{System.unique_integer([:positive])}")

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

  defp perform(session_id, mode \\ "run") do
    perform_job(SessionWorker, %{"session_id" => session_id, "mode" => mode})
  end

  defp pending_rows(session_id) do
    Repo.all(
      from(sf in SourceFile,
        where: sf.import_session_id == ^session_id,
        order_by: sf.relative_path
      )
    )
  end

  test "the worker is unique on the session id, on the dedicated import queue" do
    opts = SessionWorker.__opts__()
    assert Keyword.get(opts, :queue) == :import
    assert Keyword.get(opts, :unique)[:keys] == [:session_id]
  end

  test "config.exs configures the import queue with concurrency 1" do
    queues = Application.get_env(:playstead, Oban) |> Keyword.fetch!(:queues)
    assert Keyword.get(queues, :import) == 1
  end

  test "enqueueing the same session twice yields one running job", %{root: root, user: user} do
    File.write!(Path.join(root, "a.bin"), "a")
    {:ok, session} = Staging.stage(user.id, root, "dup-session")

    {:ok, _job1} = SessionWorker.enqueue(session.id, "run")
    {:ok, _job2} = SessionWorker.enqueue(session.id, "run")

    assert Enum.count(all_enqueued(worker: SessionWorker)) == 1
  end

  test "pausing mid-session completes the in-flight file and leaves the remaining rows pending",
       %{root: root, user: user} do
    File.write!(Path.join(root, "a.bin"), "a")
    File.write!(Path.join(root, "b.bin"), "b")
    {:ok, session} = Staging.stage(user.id, root, "pause-session")

    assert :ok = perform(session.id)

    rows = pending_rows(session.id)
    assert Enum.count(rows, &(&1.staging_state == "completed")) == 1
    assert Enum.count(rows, &(&1.staging_state == "pending")) == 1

    {:ok, _} = Import.pause_session(user.id, session.id)
    [continuation] = all_enqueued(worker: SessionWorker)
    assert :ok = perform_job(SessionWorker, continuation.args)

    rows = pending_rows(session.id)
    assert Enum.count(rows, &(&1.staging_state == "completed")) == 1
    assert Enum.count(rows, &(&1.staging_state == "pending")) == 1
    assert Repo.get!(Session, session.id).state == "paused"
  end

  test "resuming continues from the first pending row rather than the beginning", %{
    root: root,
    user: user
  } do
    File.write!(Path.join(root, "a.bin"), "a")
    File.write!(Path.join(root, "b.bin"), "b")
    {:ok, session} = Staging.stage(user.id, root, "resume-session")

    :ok = perform(session.id)
    {:ok, _} = Import.pause_session(user.id, session.id)

    {:ok, _} = Import.resume_session(user.id, session.id)
    [job] = all_enqueued(worker: SessionWorker)
    assert :ok = perform_job(SessionWorker, job.args)

    rows = pending_rows(session.id)
    assert Enum.all?(rows, &(&1.staging_state == "completed"))
    assert Repo.get!(Session, session.id).state == "completed"
  end

  test "retry re-queues only previously failed rows", %{root: root, user: user} do
    File.write!(Path.join(root, "a.bin"), "a")
    File.write!(Path.join(root, "b.bin"), "b")
    {:ok, session} = Staging.stage(user.id, root, "retry-session")

    [row_a, row_b] = pending_rows(session.id)
    Repo.update!(SourceFile.staging_state_changeset(row_a, "failed", "io_error"))
    Repo.update!(SourceFile.staging_state_changeset(row_b, "completed"))

    {:ok, _} = Import.retry_failed(user.id, session.id)

    rows = pending_rows(session.id)
    assert Enum.find(rows, &(&1.id == row_a.id)).staging_state == "pending"
    assert Enum.find(rows, &(&1.id == row_b.id)).staging_state == "completed"
  end

  test "a row stops being retried after three attempts", %{root: root, user: user} do
    File.write!(Path.join(root, "a.bin"), "a")
    {:ok, session} = Staging.stage(user.id, root, "attempt-limit-session")
    [row] = pending_rows(session.id)

    row = Repo.update!(SourceFile.staging_state_changeset(row, "failed", "io_error"))
    row = row |> Ecto.Changeset.change(attempt_count: 3) |> Repo.update!()

    {:ok, _} = Import.retry_failed(user.id, session.id)

    assert Repo.get!(SourceFile, row.id).staging_state == "failed"
  end

  test "cancelling leaves every already-committed blob and asset present and marks the remainder skipped",
       %{root: root, user: user} do
    File.write!(Path.join(root, "a.bin"), "a")
    File.write!(Path.join(root, "b.bin"), "b")
    {:ok, session} = Staging.stage(user.id, root, "cancel-session")

    :ok = perform(session.id)

    blob_count_before = Repo.aggregate(Playstead.Blobs.Blob, :count)

    {:ok, _} = Import.cancel_session(user.id, session.id)
    [continuation] = all_enqueued(worker: SessionWorker)
    assert :ok = perform_job(SessionWorker, continuation.args)

    rows = pending_rows(session.id)
    assert Enum.count(rows, &(&1.staging_state == "completed")) == 1
    assert Enum.count(rows, &(&1.staging_state == "skipped")) == 1
    assert Repo.aggregate(Playstead.Blobs.Blob, :count) == blob_count_before
    assert Repo.get!(Session, session.id).state == "cancelled"
  end

  test "cancelling writes an audit entry", %{root: root, user: user} do
    File.write!(Path.join(root, "a.bin"), "a")
    {:ok, session} = Staging.stage(user.id, root, "cancel-audit-session")

    {:ok, _} = Import.cancel_session(user.id, session.id)

    entries = AuditLog.list_by_subject(session.id)
    assert Enum.any?(entries, &(&1.event == "import_session_cancelled"))
  end

  test "a disk-full error pauses the session and produces exactly one receipt with the disk-full reason",
       %{root: root, user: user} do
    File.write!(Path.join(root, "a.bin"), "a")
    {:ok, session} = Staging.stage(user.id, root, "disk-full-session")

    previous_store = Application.get_env(:playstead, Playstead.Blobs)

    Application.put_env(:playstead, Playstead.Blobs,
      store: Playstead.Import.SessionWorkerTest.InsufficientSpaceStore
    )

    on_exit(fn -> Application.put_env(:playstead, Playstead.Blobs, previous_store) end)

    assert :ok = perform(session.id)

    Application.put_env(:playstead, Playstead.Blobs, previous_store)

    session = Repo.get!(Session, session.id)
    assert session.state == "paused"

    receipts = Import.list_session_receipts(user.id, session.id).entries

    assert Enum.count(receipts, &(&1.outcome == "failed_safely" and &1.reason == "disk_full")) ==
             1
  end
end
