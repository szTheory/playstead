defmodule PlaysteadWeb.Api.V1.EnrichmentController do
  @moduledoc "Owner-scoped durable provider enrichment commands and status."
  use PlaysteadWeb, :controller

  alias Playstead.Idempotency
  alias Playstead.Metadata.{EnrichmentWorker, ProviderMediaCache}

  action_fallback PlaysteadWeb.Api.V1.FallbackController

  def estimate(conn, %{"selected_asset_set_ids" => ids} = params) do
    case EnrichmentWorker.estimate_preparation(
           conn.assigns.current_device.user_id,
           ids,
           Map.get(params, "mode", "balanced")
         ) do
      {:ok, estimate} -> json(conn, estimate)
      {:error, reason} -> provider_error(conn, reason)
    end
  end

  def estimate(conn, _), do: provider_error(conn, :invalid_selection)

  def create(conn, %{"asset_set_id" => asset_set_id, "mode" => "prepare"} = params) do
    user_id = conn.assigns.current_device.user_id
    ids = Map.get(params, "selected_asset_set_ids", [asset_set_id])
    estimate = Map.get(params, "estimate")

    mutate(conn, fn ->
      case EnrichmentWorker.prepare(user_id, ids, estimate,
             profile_mode: Map.get(params, "profile_mode", "balanced")
           ) do
        {:ok, %{jobs: jobs, estimate: total}} ->
          {:ok, 202, %{jobs: Enum.map(jobs, &job_json/1), estimate: total}}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  def create(conn, %{"asset_set_id" => asset_set_id, "mode" => mode}) do
    user_id = conn.assigns.current_device.user_id

    mutate(conn, fn ->
      case EnrichmentWorker.enqueue(user_id, asset_set_id, mode) do
        {:ok, job} -> {:ok, 202, job_json(job)}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  def create(conn, _), do: provider_error(conn, :invalid_request)

  def show(conn, %{"job_id" => job_id}) do
    with {:ok, job} <- EnrichmentWorker.status(conn.assigns.current_device.user_id, job_id) do
      json(conn, job_json(job))
    else
      {:error, reason} -> provider_error(conn, reason)
    end
  end

  def cancel(conn, %{"job_id" => job_id}) do
    mutate(conn, fn ->
      case EnrichmentWorker.cancel(conn.assigns.current_device.user_id, job_id) do
        {:ok, job} -> {:ok, 200, job_json(job)}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  def media(conn, %{"asset_set_id" => asset_set_id, "object_id" => object_id}) do
    case ProviderMediaCache.read(conn.assigns.current_device.user_id, asset_set_id, object_id) do
      {:ok, %{bytes: bytes}} ->
        conn
        |> put_resp_header("cache-control", "private, no-store")
        |> put_resp_content_type("image/png")
        |> send_resp(200, bytes)

      {:error, reason} ->
        provider_error(conn, reason)
    end
  end

  def cache_usage(conn, _params) do
    json(conn, ProviderMediaCache.usage(conn.assigns.current_device.user_id))
  end

  def cache_reclaim(conn, _params) do
    user_id = conn.assigns.current_device.user_id

    mutate(conn, fn ->
      case ProviderMediaCache.reclaim(user_id) do
        {:ok, result} -> {:ok, 200, Map.merge(ProviderMediaCache.usage(user_id), result)}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp mutate(conn, effect) do
    device = conn.assigns.current_device

    case Idempotency.execute(
           device.id,
           conn.assigns.idempotency_key,
           conn.assigns.idempotency_fingerprint,
           effect
         ) do
      {:ok, status, body} ->
        conn |> put_status(status) |> json(body)

      {:error, :conflict} ->
        PlaysteadWeb.Problem.send_problem(
          conn,
          409,
          :idempotency_key_conflict,
          "A request with this Idempotency-Key is already being processed."
        )

      {:error, reason} ->
        provider_error(conn, reason)
    end
  end

  defp job_json(job) do
    %{
      id: job.id,
      asset_set_id: job.asset_set_id,
      provider: job.provider,
      policy_revision: job.policy_revision,
      mode: job.mode,
      state: job.state,
      progress: job.progress,
      results: job.results,
      estimate: %{
        requests: job.request_estimate,
        bytes: job.byte_estimate,
        storage: job.storage_estimate
      },
      last_error: job.last_error,
      retry_after_at: job.retry_after_at,
      inserted_at: job.inserted_at,
      updated_at: job.updated_at
    }
  end

  defp provider_error(conn, reason) when reason in [:consent_required, :consent_stale] do
    PlaysteadWeb.Problem.send_problem(
      conn,
      409,
      reason,
      "Current explicit title and system consent is required before provider enrichment."
    )
  end

  defp provider_error(conn, :image_rights_unverified) do
    PlaysteadWeb.Problem.send_problem(
      conn,
      403,
      :image_rights_unverified,
      "Provider image rights have not been verified for this owner and use."
    )
  end

  defp provider_error(conn, :not_found) do
    PlaysteadWeb.Problem.send_problem(
      conn,
      404,
      :not_found,
      "The enrichment resource was not found."
    )
  end

  defp provider_error(conn, reason)
       when reason in [
              :invalid_selection,
              :invalid_request,
              :estimate_mismatch,
              :explicit_estimate_required
            ] do
    PlaysteadWeb.Problem.send_problem(
      conn,
      422,
      :validation_failed,
      "The selected games or displayed preparation estimate are invalid."
    )
  end

  defp provider_error(conn, reason) when reason in [:queue_full, :user_queue_full] do
    conn
    |> put_resp_header("retry-after", "60")
    |> PlaysteadWeb.Problem.send_problem(
      429,
      :enrichment_capacity,
      "The bounded enrichment queue is full."
    )
  end

  defp provider_error(conn, reason),
    do: PlaysteadWeb.Api.V1.FallbackController.call(conn, {:error, reason})
end
