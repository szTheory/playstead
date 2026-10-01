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
        if docker_available?(), do: run_fixture!(), else: System.halt(77)

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
    root =
      Path.join(
        System.tmp_dir!(),
        "playstead-restore-proof-#{System.unique_integer([:positive])}"
      )

    project = "playstead-restore-source-#{System.unique_integer([:positive])}"
    source_file = Path.join(root, "source.compose.yml")
    File.mkdir_p!(root)
    File.write!(source_file, source_compose())

    try do
      :ok = source(project, source_file, ["up", "-d"])

      :ok = await_source(project, source_file, 20)

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

      case Restore.retain([published.path],
             canonical_project: "playstead",
             canonical_roots: [Path.join(root, "canonical")],
             target_root: target_root,
             handoff_output: handoff_output,
             cleanup_failed_target: true
           ) do
        {:ok, receipt, _handoff} ->
          case Restore.cleanup(target_root: target_root, handoff_output: handoff_output) do
            :ok ->
              Mix.shell().info("restore proof verified: #{receipt["correlation_id"]}")

              Mix.shell().info(
                "PLAYSTEAD_RECOVERY_FIXTURE_JSON=" <>
                  Jason.encode!(%{
                    "schema_version" => 1,
                    "run_id" => receipt["correlation_id"],
                    "lane" => "linux_restore_fixture",
                    "stages" => receipt["stages"],
                    "outcome" => "passed"
                  })
              )

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
    after
      _ = source(project, source_file, ["down", "--volumes", "--remove-orphans"])
      File.rm_rf(root)
    end
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
