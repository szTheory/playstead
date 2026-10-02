defmodule Playstead.Operations.DiagnosticBundle do
  @moduledoc """
  Builds the support-facing diagnostic projection from explicit allowlisted
  Operations evidence. It never accepts arbitrary log data or serializes
  storage locations, content identity, request data, credentials, or output.
  """

  import Ecto.Query, warn: false

  alias Playstead.{Operations, Repo}

  @schema "playstead.diagnostic-bundle.v1"
  @max_bytes 64 * 1024
  @max_summaries 20
  @expires_in_seconds 3_600
  @rate_limit 10

  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  @spec expires_in_seconds() :: pos_integer()
  def expires_in_seconds, do: @expires_in_seconds

  @spec allow_request?(binary()) :: :ok | {:error, :rate_limited}
  def allow_request?(device_id) when is_binary(device_id) do
    case Playstead.RateLimiter.hit("diagnostic-bundle:#{device_id}", :timer.hours(1), @rate_limit) do
      {:allow, _} -> :ok
      {:deny, _} -> {:error, :rate_limited}
    end
  end

  @spec build(String.t() | nil) :: {:ok, map()} | {:error, :not_found | :invalid_correlation}
  def build(correlation_id \\ nil)

  def build(nil), do: {:ok, bundle([])}

  def build(correlation_id) when is_binary(correlation_id) do
    case for_correlation(correlation_id) do
      {:ok, summary} -> {:ok, bundle([summary])}
      {:error, :not_found} -> {:error, :not_found}
      {:error, :invalid_correlation} -> {:error, :invalid_correlation}
    end
  end

  def build(_), do: {:error, :invalid_correlation}

  @spec for_correlation(String.t()) :: {:ok, map()} | {:error, :not_found | :invalid_correlation}
  def for_correlation(correlation_id) when is_binary(correlation_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(correlation_id),
         {:ok, dumped_uuid} <- Ecto.UUID.dump(uuid),
         %{subsystem: subsystem, state: state, code: code, updated_at: updated_at} <-
           failure_summary(dumped_uuid) do
      {:ok,
       %{
         correlation_id: correlation_id,
         subsystem: subsystem,
         state: state,
         code: code,
         evidence_at: updated_at |> utc_datetime() |> DateTime.to_iso8601()
       }}
    else
      :error -> {:error, :invalid_correlation}
      nil -> {:error, :not_found}
    end
  end

  def for_correlation(_), do: {:error, :invalid_correlation}

  defp bundle(summaries) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    bundle = %{
      schema: @schema,
      generated_at: DateTime.to_iso8601(now),
      expires_at: now |> DateTime.add(@expires_in_seconds, :second) |> DateTime.to_iso8601(),
      version: %{release: Application.spec(:playstead, :vsn) |> to_string(), api: "v1"},
      configuration: %{storage: "local", backup_destination: "operator_managed"},
      components: component_projection(),
      queue: queue_projection(),
      correlation_summaries: Enum.take(summaries, @max_summaries)
    }

    if byte_size(Jason.encode!(bundle)) <= @max_bytes, do: bundle, else: minimal_bundle(now)
  end

  defp minimal_bundle(now) do
    %{
      schema: @schema,
      generated_at: DateTime.to_iso8601(now),
      expires_at: now |> DateTime.add(@expires_in_seconds, :second) |> DateTime.to_iso8601(),
      version: %{release: Application.spec(:playstead, :vsn) |> to_string(), api: "v1"},
      configuration: %{storage: "local"},
      components: [],
      queue: %{},
      correlation_summaries: []
    }
  end

  defp component_projection do
    Operations.snapshot()
    |> Enum.map(fn row ->
      %{
        id: Atom.to_string(row.id),
        state: Atom.to_string(row.state),
        code: row.code,
        evidence_at: DateTime.to_iso8601(row.evidence_at)
      }
    end)
  end

  defp queue_projection do
    case Repo.query("SELECT state, COUNT(*) FROM oban_jobs GROUP BY state") do
      {:ok, %{rows: rows}} -> %{counts: Map.new(rows, fn [state, count] -> {state, count} end)}
      _ -> %{counts: %{}}
    end
  rescue
    _ -> %{counts: %{}}
  end

  defp failure_summary(correlation_id) do
    evidence =
      Repo.one(
        from e in "operations_failure_evidence",
          where: e.correlation_id == ^correlation_id,
          order_by: [desc: e.updated_at],
          limit: 1,
          select: %{
            subsystem: e.subsystem,
            state: e.state,
            code: e.code,
            updated_at: e.updated_at
          }
      )

    evidence || recovery_summary(correlation_id)
  end

  defp recovery_summary(correlation_id),
    do:
      Repo.one(
        from r in "recovery_records",
          where: r.correlation_id == ^correlation_id,
          order_by: [desc: r.updated_at],
          limit: 1,
          select: %{
            subsystem: "recovery",
            state: r.state,
            code:
              fragment(
                "CASE WHEN ? = 'failed' THEN 'recovery_failed' WHEN ? = 'published' THEN 'recovery_published' WHEN ? = 'staging' THEN 'recovery_in_progress' ELSE 'recovery_planned' END",
                r.state,
                r.state,
                r.state
              ),
            updated_at: r.updated_at
          }
      )

  defp utc_datetime(%DateTime{} = datetime), do: datetime
  defp utc_datetime(%NaiveDateTime{} = datetime), do: DateTime.from_naive!(datetime, "Etc/UTC")
end
