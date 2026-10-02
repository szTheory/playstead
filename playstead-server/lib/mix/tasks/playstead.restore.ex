defmodule Mix.Tasks.Playstead.Restore do
  @shortdoc "Runs the fail-closed isolated Compose restore proof"
  use Mix.Task
  alias Playstead.Recovery.{BackupSet, Restore}

  @switches [
    compose_fixture: :boolean,
    retain: :boolean,
    cleanup: :boolean,
    backup_set: :keep,
    target_root: :string,
    handoff_output: :string,
    canonical_project: :string,
    canonical_root: :keep
  ]

  @impl Mix.Task
  def run(args) do
    {opts, paths, invalid} = OptionParser.parse(args, strict: @switches)

    case selected_mode(opts, paths, invalid) do
      :fixture ->
        if docker_available?() do
          run_fixture!()
        else
          Mix.shell().info("PLAYSTEAD_RECOVERY_FIXTURE_FAILURE_STAGE=source-compose-startup")
          System.halt(77)
        end

      :retain ->
        if docker_available?(), do: run_retained!(opts), else: System.halt(77)

      :cleanup ->
        if docker_available?(), do: cleanup_retained!(opts), else: System.halt(77)

      :invalid ->
        Mix.raise(usage())
    end
  end

  defp selected_mode(opts, paths, invalid) do
    selected = Enum.count([opts[:compose_fixture], opts[:retain], opts[:cleanup]], & &1)

    if invalid == [] and paths == [] and selected == 1 do
      cond do
        opts[:compose_fixture] -> :fixture
        opts[:retain] -> :retain
        opts[:cleanup] -> :cleanup
      end
    else
      :invalid
    end
  end

  defp run_retained!(opts) do
    Mix.Task.run("app.start")

    case Restore.retain(Keyword.get_values(opts, :backup_set),
           target_root: opts[:target_root],
           handoff_output: opts[:handoff_output],
           canonical_project: opts[:canonical_project],
           canonical_roots: Keyword.get_values(opts, :canonical_root)
         ) do
      {:ok, _receipt, output} -> Mix.shell().info(output)
      {:error, reason} -> Mix.raise("retained restore refused: #{inspect(reason)}")
    end
  end

  defp cleanup_retained!(opts) do
    Mix.Task.run("app.start")

    case Restore.cleanup(target_root: opts[:target_root], handoff_output: opts[:handoff_output]) do
      :ok -> Mix.shell().info("retained restore target cleaned up")
      {:error, reason} -> Mix.raise("retained cleanup refused: #{inspect(reason)}")
    end
  end

  defp usage do
    """
    usage:
      mix playstead.restore --compose-fixture
      mix playstead.restore --retain --backup-set ABSOLUTE_PATH [--backup-set ABSOLUTE_PATH ...] --target-root ABSOLUTE_NEW_DIRECTORY --handoff-output ABSOLUTE_NEW_DIRECTORY/server-handoff.json --canonical-project NAME --canonical-root ABSOLUTE_PATH [--canonical-root ABSOLUTE_PATH ...]
      mix playstead.restore --cleanup --target-root ABSOLUTE_DIRECTORY --handoff-output ABSOLUTE_DIRECTORY/server-handoff.json
    """
  end

  defp run_fixture! do
    Process.put(:playstead_recovery_fixture_failure_stage, "unknown")

    root =
      Path.join(
        System.tmp_dir!(),
        "playstead-restore-proof-#{System.unique_integer([:positive])}"
      )

    project = "playstead-restore-source-#{System.unique_integer([:positive])}"
    source_file = Path.join(root, "source.compose.yml")

    work_result =
      try do
        Process.put(:playstead_recovery_fixture_failure_stage, "source-fixture-filesystem-create")
        File.mkdir_p!(root)
        File.write!(source_file, source_compose())

        Process.put(:playstead_recovery_fixture_failure_stage, "source-compose-startup")
        :ok = source(project, source_file, ["up", "-d"])

        Process.put(:playstead_recovery_fixture_failure_stage, "source-readiness")
        :ok = await_source(project, source_file, 20)

        Process.put(:playstead_recovery_fixture_failure_stage, "source-fixture-database-seed")

        :ok =
          source(project, source_file, [
            "exec",
            "-T",
            "db",
            "psql",
            "-U",
            "restore_source",
            "-d",
            "restore_source",
            "-v",
            "ON_ERROR_STOP=1",
            "-c",
            "CREATE TABLE restore_fixture (id integer primary key, note text); INSERT INTO restore_fixture VALUES (1, 'real pg_dump source');"
          ])

        Process.put(:playstead_recovery_fixture_failure_stage, "source-dump")

        {:ok, dump} =
          source_output(project, source_file, [
            "exec",
            "-T",
            "db",
            "pg_dump",
            "-U",
            "restore_source",
            "-d",
            "restore_source",
            "--format=custom"
          ])

        Process.put(:playstead_recovery_fixture_failure_stage, "backup-publication")

        {:ok, set} =
          BackupSet.build(%{
            id: "fixture-full",
            correlation_id: "fixture-correlation",
            kind: :full,
            dump: %{relative: "database.dump", bytes: dump},
            members: [],
            metadata: %{release: "fixture", configuration: %{storage: "local"}}
          })

        {:ok, published} = BackupSet.publish(Path.join(root, "backups"), set, attested: true)

        target_root = Path.join(root, "target")
        handoff_output = Path.join(target_root, "server-handoff.json")

        Process.put(:playstead_recovery_fixture_failure_stage, "target-restore")

        case Restore.retain([published.path],
               canonical_project: "playstead",
               canonical_roots: [Path.join(root, "canonical")],
               target_root: target_root,
               handoff_output: handoff_output,
               cleanup_failed_target: true
             ) do
          {:ok, receipt, _handoff} ->
            Process.put(:playstead_recovery_fixture_failure_stage, "target-cleanup")

            case Restore.cleanup(target_root: target_root, handoff_output: handoff_output) do
              :ok ->
                {:ok, receipt["correlation_id"], receipt["stages"]}

              {:error, reason} ->
                Mix.raise("restore cleanup failed: #{inspect(reason)}")
            end

          {:error, receipt} when is_map(receipt) ->
            if receipt["cleanup_code"] do
              Mix.raise("restore proof failed: #{receipt["code"]}; target cleanup failed")
            else
              Mix.raise("restore proof failed: #{receipt["code"]}")
            end

          {:error, reason} ->
            Mix.raise("restore proof failed: #{inspect(reason)}")
        end
      rescue
        error ->
          {:failure, :error, error, __STACKTRACE__,
           Process.get(:playstead_recovery_fixture_failure_stage) || "unknown"}
      catch
        kind, reason ->
          {:failure, kind, reason, __STACKTRACE__,
           Process.get(:playstead_recovery_fixture_failure_stage) || "unknown"}
      end

    cleanup_result = cleanup_fixture(project, source_file, root)

    try do
      case {work_result, cleanup_result} do
        {{:ok, correlation_id, stages}, :ok} ->
          emit_fixture_result(correlation_id, stages)

        {{:failure, kind, reason, stacktrace, stage}, _cleanup_result} ->
          Mix.shell().info("PLAYSTEAD_RECOVERY_FIXTURE_FAILURE_STAGE=#{stage}")
          :erlang.raise(kind, reason, stacktrace)

        {{:ok, _correlation_id, _stages}, {:error, _}} ->
          Mix.shell().info("PLAYSTEAD_RECOVERY_FIXTURE_FAILURE_STAGE=target-cleanup")
          Mix.raise("restore fixture teardown failed")
      end
    after
      Process.delete(:playstead_recovery_fixture_failure_stage)
    end
  end

  defp emit_fixture_result(correlation_id, stages) do
    Process.put(:playstead_recovery_fixture_failure_stage, "result-validation")
    Mix.shell().info("restore proof verified: #{correlation_id}")

    Mix.shell().info(
      "PLAYSTEAD_RECOVERY_FIXTURE_JSON=" <>
        Jason.encode!(%{
          "schema_version" => 1,
          "run_id" => correlation_id,
          "lane" => "linux_restore_fixture",
          "stages" => stages,
          "outcome" => "passed"
        })
    )
  rescue
    _ ->
      Mix.shell().info("PLAYSTEAD_RECOVERY_FIXTURE_FAILURE_STAGE=result-validation")
      Mix.raise("restore fixture result validation failed")
  end

  defp cleanup_fixture(project, source_file, root) do
    compose_result =
      if File.regular?(source_file) do
        source(project, source_file, ["down", "--volumes", "--remove-orphans"])
      else
        :ok
      end

    remove_result =
      case File.rm_rf(root) do
        {:ok, _removed_paths} -> :ok
        {:error, _reason, _path} -> {:error, :target_cleanup_failed}
      end

    if compose_result == :ok and remove_result == :ok,
      do: :ok,
      else: {:error, :target_cleanup_failed}
  rescue
    _ -> {:error, :target_cleanup_failed}
  end

  defp docker_available?,
    do: match?({_, 0}, System.cmd("docker", ["compose", "version"], stderr_to_stdout: true))

  defp source(project, file, args) do
    case System.cmd("docker", ["compose", "--project-name", project, "-f", file | args],
           stderr_to_stdout: true
         ) do
      {_out, 0} -> :ok
      _ -> {:error, :source_compose_failed}
    end
  rescue
    _ -> {:error, :source_compose_failed}
  end

  defp source_output(project, file, args) do
    case System.cmd("docker", ["compose", "--project-name", project, "-f", file | args],
           stderr_to_stdout: true
         ) do
      {out, 0} -> {:ok, out}
      _ -> {:error, :source_dump_failed}
    end
  rescue
    _ -> {:error, :source_dump_failed}
  end

  defp await_source(_project, _file, 0), do: {:error, :source_database_unavailable}

  defp await_source(project, file, attempts) do
    case source(project, file, ["exec", "-T", "db", "pg_isready", "-U", "restore_source"]) do
      :ok ->
        :ok

      {:error, _} ->
        Process.sleep(500)
        await_source(project, file, attempts - 1)
    end
  end

  defp source_compose do
    """
    services:
      db:
        image: postgres:17.2
        environment:
          POSTGRES_USER: restore_source
          POSTGRES_PASSWORD: restore_source_password
          POSTGRES_DB: restore_source
    """
  end
end
