defmodule Playstead.Recovery do
  @moduledoc "Durable recovery command boundary; timestamps are never backup freshness evidence."

  import Ecto.Query, warn: false

  alias Playstead.Blobs.Blob
  alias Playstead.Repo
  alias Playstead.Recovery.{BackupSet, Worker}

  @spec preflight_backup_destination() :: {:ok, %{independence: String.t()}} | {:error, atom()}
  def preflight_backup_destination do
    case System.get_env("PLAYSTEAD_BACKUP_DESTINATION") do
      destination when is_binary(destination) and destination != "" ->
        BackupSet.preflight_destination(destination, Playstead.Blobs.Store.LocalDisk.blob_path())

      _ ->
        {:error, :destination_missing}
    end
  end

  @doc "A deliberately allowlisted durable-record read for the release CLI."
  @spec backup_status(binary()) :: {:ok, map()} | {:error, atom()}
  def backup_status(id) when is_binary(id) do
    with {:ok, dumped_id} <- Ecto.UUID.dump(id),
         {:ok, %{rows: [[kind, state, correlation_id, receipt]]}} <-
           Ecto.Adapters.SQL.query(
             Repo,
             "SELECT kind, state, correlation_id, receipt FROM recovery_records WHERE id = $1",
             [dumped_id]
           ),
         {:ok, correlation_id} <- Ecto.UUID.load(correlation_id) do
      {:ok, %{kind: kind, state: state, correlation_id: correlation_id, receipt: receipt}}
    else
      :error -> {:error, :backup_not_found}
      {:ok, %{rows: []}} -> {:error, :backup_not_found}
      {:error, _} -> {:error, :backup_status_unavailable}
      _ -> {:error, :backup_status_unavailable}
    end
  end

  def backup_status(_), do: {:error, :backup_not_found}

  @spec request_backup(map()) :: {:ok, binary()} | {:error, term()}
  def request_backup(%{destination: destination, kind: kind} = attrs)
      when kind in [:full, :incremental] do
    id = Ecto.UUID.generate()
    correlation_id = Map.get(attrs, :correlation_id, Ecto.UUID.generate())

    command = backup_command(attrs, id, correlation_id)

    with {:ok, dumped_id} <- Ecto.UUID.dump(id),
         {:ok, dumped_correlation_id} <- Ecto.UUID.dump(correlation_id) do
      Repo.transaction(fn ->
        sql = """
        INSERT INTO recovery_records (id, kind, state, destination_root, correlation_id, command, inserted_at, updated_at)
        VALUES ($1, $2, 'planned', $3, $4, $5, NOW(), NOW())
        ON CONFLICT (correlation_id) DO NOTHING
        RETURNING id
        """

        case Ecto.Adapters.SQL.query(Repo, sql, [
               dumped_id,
               Atom.to_string(kind),
               destination,
               dumped_correlation_id,
               command
             ]) do
          {:ok, %{rows: [[record_id]]}} ->
            with {:ok, recovery_id} <- Ecto.UUID.load(record_id),
                 {:ok, _job} <- apply(Worker, :enqueue, [recovery_id, correlation_id]) do
              recovery_id
            else
              :error -> Repo.rollback(:invalid_recovery_id)
              {:error, reason} -> Repo.rollback(reason)
            end

          {:ok, %{rows: []}} ->
            Repo.rollback(:duplicate_command)

          {:error, reason} ->
            Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, record_id} -> {:ok, record_id}
        {:error, reason} -> {:error, reason}
      end
    else
      :error -> {:error, :invalid_correlation_id}
    end
  end

  def request_backup(_), do: {:error, :invalid_backup_request}

  @doc false
  @spec capture(map(), keyword()) ::
          {:ok, %{command: map(), dump_path: String.t()}} | {:error, atom()}
  def capture(command, opts \\ [])

  def capture(%{"schema" => "playstead.recovery-command.v1"} = command, opts) do
    dump_root = Keyword.get(opts, :dump_root, System.tmp_dir!())

    Repo.transaction(
      fn ->
        with {:ok, snapshot} <- export_snapshot(),
             inventory <- snapshot_inventory(),
             {:ok, dump_path} <-
               BackupSet.capture_dump(snapshot, dump_root,
                 database_url: database_url(),
                 command_runner: Keyword.get(opts, :command_runner, &System.cmd/3)
               ) do
          %{command: Map.put(command, "inventory", inventory), dump_path: dump_path}
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end,
      isolation: :repeatable_read
    )
    |> case do
      {:ok, captured} -> {:ok, captured}
      {:error, reason} -> {:error, reason}
    end
  end

  def capture(_, _), do: {:error, :invalid_recovery_command}

  defp backup_command(attrs, id, correlation_id) do
    %{
      "schema" => "playstead.recovery-command.v1",
      "id" => id,
      "correlation_id" => correlation_id,
      "kind" => Atom.to_string(attrs.kind),
      "metadata" => %{
        "release" => Application.spec(:playstead, :vsn) |> to_string(),
        "configuration" => %{"storage" => "local"},
        "parent" => Map.get(attrs, :parent)
      }
    }
  end

  defp export_snapshot do
    case Ecto.Adapters.SQL.query(Repo, "SELECT pg_export_snapshot()", []) do
      {:ok, %{rows: [[snapshot]]}} when is_binary(snapshot) and snapshot != "" -> {:ok, snapshot}
      _ -> {:error, :database_snapshot_unavailable}
    end
  end

  defp snapshot_inventory do
    Repo.all(from(blob in Blob, where: blob.scan_state == "clean", order_by: [asc: blob.sha256]))
    |> Enum.map(fn blob ->
      %{"sha256" => blob.sha256, "size_bytes" => blob.size_bytes, "kind" => "cas"}
    end)
  end

  defp database_url do
    repo_config = Repo.config()

    (System.get_env("DATABASE_URL") || Keyword.get(repo_config, :url) ||
       database_url_from(repo_config))
    |> case do
      "ecto://" <> rest -> "postgresql://" <> rest
      url -> url
    end
  end

  defp database_url_from(config) do
    username = config |> Keyword.get(:username) |> uri_component()
    password = config |> Keyword.get(:password) |> uri_component()

    userinfo =
      case {username, password} do
        {nil, _} -> nil
        {user, nil} -> user
        {user, pass} -> user <> ":" <> pass
      end

    database = config |> Keyword.fetch!(:database) |> uri_component()

    %URI{
      scheme: "postgresql",
      userinfo: userinfo,
      host: Keyword.fetch!(config, :hostname),
      port: Keyword.get(config, :port),
      path: "/" <> database
    }
    |> URI.to_string()
  end

  defp uri_component(nil), do: nil
  defp uri_component(value), do: URI.encode(to_string(value), &URI.char_unreserved?/1)
end
