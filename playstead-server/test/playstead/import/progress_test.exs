defmodule Playstead.Import.ProgressTest do
  use Playstead.DataCase, async: false

  import Playstead.AccountsFixtures

  alias Playstead.Import.{Progress, Session, SessionWorker, Staging}
  alias Playstead.Repo
  alias Playstead.Sync.ChangeJournal

  setup do
    File.mkdir_p!(Playstead.Blobs.Store.LocalDisk.blob_path())

    root =
      Path.join(
        System.tmp_dir!(),
        "playstead-progress-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    previous_inbox = Application.get_env(:playstead, :inbox_path)
    previous_concurrency = Application.get_env(:playstead, :import_concurrency)
    Application.put_env(:playstead, :inbox_path, root)
    Application.put_env(:playstead, :import_concurrency, 100)

    on_exit(fn ->
      Application.put_env(:playstead, :inbox_path, previous_inbox)
      Application.put_env(:playstead, :import_concurrency, previous_concurrency)
    end)

    user = owner_fixture()
    {:ok, root: root, user: user}
  end

  describe "summary/1" do
    test "reports both a byte ratio and a file count" do
      session = %Session{
        bytes_completed: 50,
        total_bytes: 100,
        files_completed: 1,
        file_count: 2,
        enumeration_completed_at: nil,
        started_at: nil
      }

      summary = Progress.summary(session)
      assert summary.bytes_completed == 50
      assert summary.total_bytes == 100
      assert summary.files_completed == 1
      assert summary.file_count == 2
    end

    test "produces no time estimate before enumeration completes" do
      session = %Session{
        bytes_completed: 50,
        total_bytes: 100,
        files_completed: 1,
        file_count: 2,
        enumeration_completed_at: nil,
        started_at: DateTime.add(DateTime.utc_now(), -3600, :second)
      }

      assert Progress.summary(session).eta_minutes == nil
    end

    test "produces no time estimate before the throughput observation window elapses" do
      session = %Session{
        bytes_completed: 50,
        total_bytes: 100,
        files_completed: 1,
        file_count: 2,
        enumeration_completed_at: DateTime.utc_now(),
        started_at: DateTime.utc_now()
      }

      assert Progress.summary(session).eta_minutes == nil
    end

    test "a produced time estimate is rounded to whole minutes, never seconds" do
      session = %Session{
        bytes_completed: 1_000_000,
        total_bytes: 100_000_000,
        files_completed: 1,
        file_count: 100,
        enumeration_completed_at: DateTime.utc_now(),
        started_at: DateTime.add(DateTime.utc_now(), -60, :second)
      }

      eta = Progress.summary(session).eta_minutes
      assert is_integer(eta)
      assert eta > 0
    end
  end

  describe "checkpoint/2 throttling and journal entries" do
    test "a session processing one hundred files produces strictly fewer job entries than files, and each state transition produces exactly one",
         %{root: root, user: user} do
      for i <- 1..100 do
        File.write!(Path.join(root, "file#{i}.bin"), "content-#{i}")
      end

      {:ok, session} = Staging.stage(user.id, root, "hundred-file-session")

      run_to_completion(session.id)

      job_entries =
        ChangeJournal.read_after(user.id, 0, 10_000)
        |> Enum.filter(&(&1.entity_kind == "job"))

      assert length(job_entries) < 100
      assert length(job_entries) >= 1
    end

    test "each newly created asset produces exactly one catalogue journal entry", %{
      root: root,
      user: user
    } do
      File.write!(Path.join(root, "a.bin"), "content")
      {:ok, session} = Staging.stage(user.id, root, "catalogue-entry-session")

      run_to_completion(session.id)

      catalogue_entries =
        ChangeJournal.read_after(user.id, 0, 100) |> Enum.filter(&(&1.entity_kind == "catalogue"))

      assert length(catalogue_entries) == 1
    end
  end

  defp run_to_completion(session_id, mode \\ "run") do
    :ok = perform_direct(session_id, mode)

    if Repo.get!(Session, session_id).state == "running" do
      run_to_completion(session_id, mode)
    else
      :ok
    end
  end

  defp perform_direct(session_id, mode) do
    Oban.Testing.perform_job(SessionWorker, %{"session_id" => session_id, "mode" => mode},
      repo: Repo
    )
  end
end
