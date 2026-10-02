defmodule Playstead.Recovery.Worker do
  @moduledoc "Bounded, recovery-record-unique background work for backup publication."

  use Oban.Worker,
    queue: :recovery,
    max_attempts: 5,
    unique: [keys: [:recovery_id], states: [:available, :scheduled, :executing, :retryable]]

  alias Playstead.{Blobs, Operations, Recovery, Repo}
  alias Playstead.Blobs.Store.LocalDisk
  alias Playstead.Recovery.BackupSet

  @spec enqueue(binary()) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def enqueue(recovery_id, correlation_id \\ nil) when is_binary(recovery_id) do
    args = %{recovery_id: recovery_id}

    args =
      if is_binary(correlation_id), do: Map.put(args, :correlation_id, correlation_id), else: args

    args |> new() |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"recovery_id" => recovery_id} = args}) do
    {:ok, dumped_recovery_id} = Ecto.UUID.dump(recovery_id)

    case Ecto.Adapters.SQL.query(
           Repo,
           "SELECT destination_root, command FROM recovery_records WHERE id = $1",
           [
             dumped_recovery_id
           ]
         ) do
      {:ok, %{rows: [[destination_root, command]]}} ->
        mark_state(dumped_recovery_id, "staging")

        publish(
          dumped_recovery_id,
          destination_root,
          command,
          Map.get(args, "correlation_id", command["correlation_id"])
        )

      _ ->
        {:discard, :recovery_record_not_found}
    end
  end

  defp publish(recovery_id, destination_root, command, correlation_id) do
    result = capture_and_publish(recovery_id, destination_root, command)

    case result do
      {:ok, receipt} ->
        Ecto.Adapters.SQL.query(
          Repo,
          "UPDATE recovery_records SET state = 'published', receipt = $2, updated_at = NOW() WHERE id = $1",
          [recovery_id, receipt]
        )

        :ok

      {:error, reason} ->
        code = stable_failure_code(reason)
        :ok = Operations.record_failure(correlation_id, "storage", code)

        Ecto.Adapters.SQL.query(
          Repo,
          "UPDATE recovery_records SET state = 'failed', failure_evidence = $2, updated_at = NOW() WHERE id = $1",
          [recovery_id, %{code: code, correlation_id: correlation_id}]
        )

        {:error, reason}
    end
  end

  defp capture_and_publish(recovery_id, destination_root, command) do
    with {:ok, %{command: captured_command, dump_path: dump_path}} <- Recovery.capture(command) do
      try do
        with :ok <- persist_captured_command(recovery_id, captured_command),
             {:ok, set} <-
               BackupSet.materialize(
                 Map.put(captured_command, "dump_path", dump_path),
                 &read_blob/1
               ),
             {:ok, %{receipt: receipt}} <-
               BackupSet.publish(destination_root, set,
                 canonical_root: LocalDisk.blob_path(),
                 attested: true
               ) do
          {:ok, receipt}
        end
      after
        # The file is an unpublished staging artifact. Never let a retry reuse
        # it after its exported PostgreSQL snapshot has ended.
        _ = File.rm(dump_path)
      end
    end
  end

  defp persist_captured_command(recovery_id, command) do
    case Ecto.Adapters.SQL.query(
           Repo,
           "UPDATE recovery_records SET command = $2, updated_at = NOW() WHERE id = $1",
           [recovery_id, command]
         ) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, :recovery_command_persist_failed}
    end
  end

  defp stable_failure_code(:destination_overlaps_canonical), do: "destination_overlaps_canonical"
  defp stable_failure_code(:destination_same_filesystem), do: "destination_same_filesystem"
  defp stable_failure_code(:not_found), do: "object_not_found"
  defp stable_failure_code(_), do: "storage_operation_failed"

  defp read_blob(sha256), do: Blobs.stream(sha256)

  defp mark_state(id, state) do
    Ecto.Adapters.SQL.query(
      Repo,
      "UPDATE recovery_records SET state = $2, updated_at = NOW() WHERE id = $1 AND state IN ('planned', 'staging')",
      [id, state]
    )
  end
end
