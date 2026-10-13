defmodule Playstead.Operations do
  @moduledoc """
  Owner-only operations projection. It deliberately has no HTTP concerns and
  never feeds the public liveness endpoint: its richer evidence is for an
  authenticated operator deciding what to do next.
  """

  import Ecto.Query, warn: false

  alias Playstead.{Repo, Readiness}
  alias Playstead.Blobs.Store.LocalDisk

  @components [:database, :blobs, :queue, :migrations, :capacity, :backup]
  @fresh_for_seconds 86_400
  @probe_timeout 1_000

  @type state :: :healthy | :attention | :blocked | :not_configured

  @failure_subsystems ~w(recovery storage transfer save pairing)

  @doc "Records the allowlisted durable diagnostic projection for a failed operation."
  @spec record_failure(String.t(), String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def record_failure(correlation_id, subsystem, code, state \\ "failed")

  def record_failure(correlation_id, subsystem, code, state)
      when subsystem in @failure_subsystems and is_binary(code) and is_binary(state) do
    with {:ok, correlation_id} <- Ecto.UUID.cast(correlation_id),
         {:ok, dumped_correlation_id} <- Ecto.UUID.dump(correlation_id) do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      case Repo.query(
             "INSERT INTO operations_failure_evidence (id, correlation_id, subsystem, code, state, inserted_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6, $6)",
             [
               Ecto.UUID.dump(Ecto.UUID.generate()) |> elem(1),
               dumped_correlation_id,
               subsystem,
               code,
               state,
               now
             ]
           ) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :error -> {:error, :invalid_correlation_id}
    end
  end

  def record_failure(_, _, _, _), do: {:error, :invalid_failure_evidence}

  @spec component_ids() :: [atom()]
  def component_ids, do: @components

  @spec snapshot(keyword()) :: [map()]
  def snapshot(opts \\ []) do
    probes = Keyword.get(opts, :probes, %{})
    probe_fun = Keyword.get(opts, :probe_fun)

    rows =
      Enum.map(@components, fn id ->
        probe = Map.get(probes, id) || bounded_probe(fn -> run_probe(id, probe_fun) end)
        row(id, probe)
      end)

    Enum.each(rows, &record_actionable_transition/1)
    rows
  end

  @spec attention_history_count() :: non_neg_integer()
  def attention_history_count do
    Repo.one(from h in "operations_attention_history", select: count(h.id))
  end

  defp row(id, %{state: state} = probe)
       when state in [:healthy, :attention, :blocked, :not_configured] do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      id: id,
      state: state,
      code: Map.get(probe, :code),
      remedy: Map.get(probe, :remedy),
      evidence_at: Map.get(probe, :evidence_at, now)
    }
  end

  defp row(id, _),
    do:
      row(id, %{
        state: :blocked,
        code: "probe_invalid",
        remedy: "Review the operations probe configuration."
      })

  defp run_probe(id, nil), do: probe(id)
  defp run_probe(id, probe_fun) when is_function(probe_fun, 1), do: probe_fun.(id)

  defp bounded_probe(fun) do
    task = Task.async(fun)

    case Task.yield(task, @probe_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} ->
        result

      nil ->
        %{
          state: :attention,
          code: "probe_timeout",
          remedy: "Retry the bounded probe and inspect the affected service."
        }
    end
  catch
    :exit, _ ->
      %{state: :blocked, code: "probe_failed", remedy: "Inspect the affected service and retry."}
  end

  defp probe(:database) do
    case safe_query("SELECT 1") do
      :ok ->
        %{state: :healthy}

      :error ->
        %{state: :blocked, code: "database_unavailable", remedy: "Check PostgreSQL and retry."}
    end
  end

  defp probe(:blobs) do
    root = LocalDisk.blob_path()
    probe_path = Path.join(root, ".operations-probe-#{System.unique_integer([:positive])}")

    with :ok <- File.mkdir_p(root),
         :ok <- File.write(probe_path, "probe", [:binary]),
         {:ok, "probe"} <- File.read(probe_path),
         :ok <- File.rm(probe_path) do
      %{state: :healthy}
    else
      _ ->
        %{
          state: :blocked,
          code: "blob_store_unavailable",
          remedy: "Check the configured blob volume and its permissions."
        }
    end
  rescue
    _ ->
      %{
        state: :blocked,
        code: "blob_store_unavailable",
        remedy: "Check the configured blob volume and its permissions."
      }
  end

  defp probe(:queue) do
    with {:ok, %{rows: rows}} <-
           Repo.query("SELECT state, COUNT(*) FROM oban_jobs GROUP BY state") do
      counts = Map.new(rows, fn [state, count] -> {state, count} end)

      configured =
        Application.fetch_env!(:playstead, Oban) |> Keyword.fetch!(:queues) |> Keyword.keys()

      producers = Oban.check_all_queues()

      cond do
        Enum.any?(producers, & &1.paused) ->
          %{
            state: :attention,
            code: "queue_paused",
            remedy: "Resume the paused durable queue or complete its maintenance."
          }

        Enum.any?(configured, fn queue ->
          is_nil(Enum.find(producers, &(&1.queue == to_string(queue))))
        end) ->
          %{
            state: :attention,
            code: "queue_producer_missing",
            remedy: "Start the configured durable queue producer."
          }

        Map.get(counts, "discarded", 0) > 0 ->
          %{
            state: :blocked,
            code: "queue_discarded",
            remedy: "Inspect discarded jobs and resolve their failure evidence."
          }

        Map.get(counts, "retryable", 0) > 0 ->
          %{
            state: :attention,
            code: "queue_retrying",
            remedy: "Inspect retrying jobs before their retry budget is exhausted."
          }

        Map.get(counts, "available", 0) > 1_000 ->
          %{
            state: :attention,
            code: "queue_backlogged",
            remedy: "Reduce backlog or increase bounded worker capacity."
          }

        true ->
          %{state: :healthy}
      end
    else
      _ ->
        %{
          state: :blocked,
          code: "queue_unavailable",
          remedy: "Check the durable queue database connection."
        }
    end
  rescue
    _ ->
      %{
        state: :blocked,
        code: "queue_unavailable",
        remedy: "Check the durable queue database connection."
      }
  end

  defp probe(:migrations) do
    case Ecto.Migrator.with_repo(Repo, &Ecto.Migrator.migrations/1) do
      {:ok, migrations, _} ->
        if Enum.any?(migrations, fn {status, _, _} -> status == :down end) do
          %{
            state: :attention,
            code: "migrations_pending",
            remedy: "Run the documented migration before serving writes."
          }
        else
          %{state: :healthy}
        end

      _ ->
        %{
          state: :blocked,
          code: "migrations_unknown",
          remedy: "Check database access and migration state."
        }
    end
  rescue
    _ ->
      %{
        state: :blocked,
        code: "migrations_unknown",
        remedy: "Check database access and migration state."
      }
  end

  defp probe(:capacity) do
    case {Readiness.free_bytes(LocalDisk.blob_path()), LocalDisk.capacity_bytes()} do
      {available, capacity} when is_integer(available) and is_integer(capacity) ->
        if Readiness.fits_critical_free_space?(0, available) do
          %{state: :healthy}
        else
          %{
            state: :attention,
            code: "capacity_reserve_low",
            remedy: "Free capacity before accepting more durable data."
          }
        end

      _ ->
        %{
          state: :not_configured,
          code: "capacity_unknown",
          remedy: "Configure a readable filesystem capacity probe."
        }
    end
  rescue
    _ ->
      %{
        state: :not_configured,
        code: "capacity_unknown",
        remedy: "Configure a readable filesystem capacity probe."
      }
  end

  defp probe(:backup) do
    case latest_recovery_record() do
      nil ->
        %{state: :attention, code: "backup_missing", remedy: "Run and verify a backup."}

      %{state: "failed"} ->
        %{
          state: :blocked,
          code: "backup_failed",
          remedy: "Inspect recovery failure evidence and run a new verified backup."
        }

      %{receipt: %{"verified_at" => verified_at, "independence" => "operator_attested"}} ->
        backup_freshness(verified_at)

      _ ->
        %{
          state: :attention,
          code: "backup_unattested",
          remedy: "Verify the backup with an independent destination attestation."
        }
    end
  rescue
    _ ->
      %{
        state: :attention,
        code: "backup_unknown",
        remedy: "Inspect recovery records and verify a backup."
      }
  end

  defp backup_freshness(verified_at) when is_binary(verified_at) do
    with {:ok, timestamp, _} <- DateTime.from_iso8601(verified_at),
         true <- DateTime.diff(DateTime.utc_now(), timestamp, :second) <= @fresh_for_seconds do
      %{state: :healthy}
    else
      _ -> %{state: :attention, code: "backup_stale", remedy: "Run and verify a fresh backup."}
    end
  end

  defp backup_freshness(_),
    do: %{state: :attention, code: "backup_stale", remedy: "Run and verify a fresh backup."}

  defp latest_recovery_record do
    Repo.one(
      from r in "recovery_records",
        where: r.state in ["published", "failed"],
        order_by: [desc: r.updated_at],
        limit: 1,
        select: %{state: r.state, receipt: r.receipt}
    )
  end

  defp safe_query(sql) do
    case Repo.query(sql) do
      {:ok, _} -> :ok
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp record_actionable_transition(%{state: state, code: code} = row)
       when state in [:attention, :blocked] and is_binary(code) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.insert_all(
      "operations_attention_history",
      [
        %{
          component: Atom.to_string(row.id),
          state: Atom.to_string(state),
          code: code,
          evidence_at: row.evidence_at,
          remedy: row.remedy,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:component, :state, :code]
    )

    :ok
  rescue
    _ -> :ok
  end

  defp record_actionable_transition(_), do: :ok
end
