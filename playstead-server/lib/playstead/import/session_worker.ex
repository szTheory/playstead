defmodule Playstead.Import.SessionWorker do
  @moduledoc """
  The one-job-per-session durable cursor for a staged import (D-05,
  D-06, D-08). Exactly one job exists per session, unique on the
  session identifier, on the dedicated `:import` queue configured with
  concurrency 1 (`config/config.exs`) — per-file job fan-out is
  explicitly rejected, since the open-source Oban engine has no global
  concurrency control and a fan-out design would have to pause
  thousands of individual jobs to pause one user's session.

  Each `perform/1` processes exactly one bounded batch of pending
  files (`Playstead.Import.Session`'s configured concurrency, default
  2) and, if more pending rows remain and the control is still `"run"`,
  self-chains by enqueuing the next batch as a fresh job for the same
  session id. This keeps any single job's runtime bounded and makes
  the cooperative control check — re-read from the session row before
  every batch, never the framework's own global queue pause — testable
  one batch at a time. The worker's durable cursor is the pending
  `source_files` rows themselves; nothing about where the session is
  lives in this process's memory, so a crash mid-file costs only that
  one file (its row was never marked complete before the crash) rather
  than the session's whole progress.

  Uniqueness deliberately excludes the `:executing` state: a batch
  self-chains by inserting its own continuation *while the current job
  is still executing*, so `:executing` must not conflict with the
  insert it performs on its own behalf. `:available`/`:scheduled`
  still gives the load-bearing guarantee (D-05): a second external
  enqueue attempt (e.g. a duplicate resume click) while a continuation
  is already queued converges on the one queued job.
  """

  use Oban.Worker,
    queue: :import,
    max_attempts: 10,
    unique: [keys: [:session_id], states: [:available, :scheduled]]

  import Ecto.Query, warn: false

  alias Playstead.AuditLog
  alias Playstead.Blobs
  alias Playstead.Blobs.Blob
  alias Playstead.Import
  alias Playstead.Import.{OrphanSweeper, Session, SourceFile}
  alias Playstead.Repo

  @chunk_size 1_048_576
  @max_attempts_per_row 3

  @doc "Enqueues the durable per-session job. `mode` is `\"run\"` or `\"full_verify\"`."
  @spec enqueue(String.t(), String.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(session_id, mode \\ "run") do
    %{session_id: session_id, mode: mode}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"session_id" => session_id} = args}) do
    mode = Map.get(args, "mode", "run")
    session = Session |> Repo.get!(session_id) |> ensure_running()

    case session.requested_control do
      "cancel" ->
        apply_cancel(session)
        :ok

      "pause" ->
        pause(session)
        :ok

      "run" ->
        run_one_batch(session, mode)
    end
  end

  defp ensure_running(session) do
    session =
      if session.state in ["staged", "paused"] do
        session |> Session.state_changeset("running") |> Repo.update!()
      else
        session
      end

    if is_nil(session.started_at) do
      session |> Ecto.Changeset.change(started_at: DateTime.utc_now()) |> Repo.update!()
    else
      session
    end
  end

  defp run_one_batch(session, mode) do
    case next_pending(session.id) do
      [] ->
        complete(session)
        :ok

      batch ->
        case process_batch(session, batch, mode) do
          :ok -> continue_or_stop(session, mode)
          {:disk_full, source_file} -> handle_disk_full(session, source_file)
        end
    end
  end

  defp continue_or_stop(session, mode) do
    if next_pending(session.id) == [] do
      complete(Repo.get!(Session, session.id))
    else
      session = Repo.get!(Session, session.id)
      if session.requested_control == "run", do: enqueue(session.id, mode)
    end

    :ok
  end

  defp next_pending(session_id) do
    from(sf in SourceFile,
      where: sf.import_session_id == ^session_id and sf.staging_state == "pending",
      order_by: [asc: sf.relative_path],
      limit: ^concurrency()
    )
    |> Repo.all()
  end

  defp concurrency, do: Application.get_env(:playstead, :import_concurrency, 2)

  # Each row owns its own private hash accumulator threaded
  # sequentially through that one file's chunks
  # (`Playstead.Blobs.MultiHash`, unchanged from the single-file path);
  # nothing here parallelizes chunks within a single file. Rows within
  # one batch (bounded by `concurrency/0`, default 2) are processed one
  # at a time in this process rather than fanned out across OS
  # processes — the bound is on how many files one job claims per
  # cooperative-control check, not on scheduler-level parallelism.
  defp process_batch(session, batch, mode) do
    Enum.reduce_while(batch, :ok, fn source_file, :ok ->
      case process_row(session, source_file, mode) do
        :ok -> {:cont, :ok}
        {:disk_full, source_file} -> {:halt, {:disk_full, source_file}}
      end
    end)
  end

  defp process_row(session, source_file, mode) do
    source_file = source_file |> SourceFile.increment_attempt_changeset() |> Repo.update!()

    case reconcile_match(session.user_id, source_file, mode) do
      %SourceFile{} = prior -> reuse_prior_content(session.user_id, source_file, prior)
      nil -> hash_and_commit(session, source_file)
    end
  end

  # D-08's hybrid reconcile: a row whose four-part fingerprint (origin,
  # relative path, size, mtime) matches an existing terminal row is
  # unchanged and never re-hashed; forced full verification bypasses
  # this and always re-hashes.
  defp reconcile_match(_user_id, _source_file, "full_verify"), do: nil

  defp reconcile_match(user_id, source_file, _mode) do
    from(sf in SourceFile,
      where: sf.user_id == ^user_id,
      where: sf.origin == ^source_file.origin,
      where: sf.relative_path == ^source_file.relative_path,
      where: sf.size_bytes == ^source_file.size_bytes,
      where: sf.mtime == ^source_file.mtime,
      where: sf.staging_state == "completed",
      where: sf.id != ^source_file.id,
      where: not is_nil(sf.blob_id),
      order_by: [desc: sf.updated_at],
      limit: 1
    )
    |> Repo.one()
  end

  defp reuse_prior_content(user_id, source_file, %SourceFile{blob_id: blob_id}) do
    blob = Repo.get!(Blob, blob_id)
    {:ok, _receipt} = Import.complete_staged_file(user_id, source_file, {:existing, blob_meta(blob)})
    :ok
  end

  defp blob_meta(%Blob{} = blob) do
    %{
      sha256: blob.sha256,
      size_bytes: blob.size_bytes,
      crc32: blob.crc32,
      md5: blob.md5,
      sha1: blob.sha1,
      blob_id: blob.id
    }
  end

  defp hash_and_commit(session, source_file) do
    path = source_path(source_file)

    case File.stat(path) do
      {:error, _reason} ->
        Import.record_failed_file(session.user_id, source_file, "io_error")
        :ok

      {:ok, %File.Stat{size: size}} ->
        commit_stream(session, source_file, size, path)
    end
  end

  defp commit_stream(session, source_file, size, path) do
    case Blobs.put_stream(File.stream!(path, [], @chunk_size), size) do
      {:ok, status, meta} ->
        {:ok, _receipt} = Import.complete_staged_file(session.user_id, source_file, {status, meta})
        :ok

      {:error, :insufficient_space} ->
        {:disk_full, source_file}

      {:error, _reason} ->
        Import.record_failed_file(session.user_id, source_file, "io_error")
        :ok
    end
  end

  defp source_path(%SourceFile{origin: "inbox", relative_path: relative_path}) do
    Path.join(Application.get_env(:playstead, :inbox_path), relative_path)
  end

  defp handle_disk_full(session, source_file) do
    Import.record_failed_file(session.user_id, source_file, "disk_full")
    session |> Session.state_changeset("paused") |> Repo.update!()
    :ok
  end

  defp pause(session) do
    if session.state not in ["completed", "cancelled"] do
      session |> Session.state_changeset("paused") |> Repo.update!()
    end
  end

  defp complete(session) do
    session
    |> Ecto.Changeset.change(finished_at: DateTime.utc_now())
    |> Session.state_changeset("completed")
    |> Repo.update!()
  end

  @doc """
  Marks a session's remaining pending rows as skipped, leaves every
  completed copy in place, records an audit entry, and marks the
  session cancelled. Called by `Playstead.Import.cancel_session/2`
  directly when no job is running (`staged`/`paused`/`failed`), or by
  this worker's own loop once it observes `requested_control ==
  "cancel"` between batches.
  """
  @spec apply_cancel(Session.t()) :: {:ok, Session.t()}
  def apply_cancel(session) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(sf in SourceFile,
      where: sf.import_session_id == ^session.id and sf.staging_state == "pending"
    )
    |> Repo.update_all(set: [staging_state: "skipped", updated_at: now])

    AuditLog.record(session.user_id, :import_session_cancelled, %{subject: session.id})

    {:ok,
     session
     |> Ecto.Changeset.change(finished_at: DateTime.utc_now())
     |> Session.state_changeset("cancelled")
     |> Repo.update!()}
  end

  @doc "Whether `source_file` has exhausted its bounded retry attempts."
  @spec exhausted_retries?(SourceFile.t()) :: boolean()
  def exhausted_retries?(%SourceFile{attempt_count: count}), do: count >= @max_attempts_per_row

  @doc "Sweeps orphaned temp files left by an interrupted write (D-29)."
  @spec sweep_orphans() :: :ok
  def sweep_orphans, do: OrphanSweeper.sweep(0)
end
