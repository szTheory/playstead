defmodule PlaysteadWeb.Api.V1.OperationsController do
  @moduledoc "Owner-device diagnostic bundle endpoint with bounded durable replay."

  use PlaysteadWeb, :controller

  alias Playstead.{Idempotency, Operations.DiagnosticBundle}

  action_fallback PlaysteadWeb.Api.V1.FallbackController

  def create_diagnostic_bundle(conn, params) do
    device = conn.assigns.current_device
    key = conn.assigns.idempotency_key
    fingerprint = conn.assigns.idempotency_fingerprint

    result =
      Idempotency.execute(
        device.id,
        key,
        fingerprint,
        fn ->
          with :ok <- DiagnosticBundle.allow_request?(device.id),
               {:ok, bundle} <- DiagnosticBundle.build(params["correlation_id"]) do
            {:ok, 201, bundle}
          else
            {:error, :rate_limited} ->
              {:error,
               {:rate_limited, "Too many diagnostic bundle requests. Please try again later."}}

            {:error, :not_found} ->
              {:error, :not_found}

            {:error, :invalid_correlation} ->
              {:error, {:not_found, "No eligible diagnostic evidence was found."}}
          end
        end,
        expires_in_seconds: DiagnosticBundle.expires_in_seconds()
      )

    case result do
      {:ok, status, body} -> conn |> put_status(status) |> json(body)
      {:error, :conflict} -> conflict_problem(conn)
      {:error, reason} -> PlaysteadWeb.Api.V1.FallbackController.call(conn, {:error, reason})
    end
  end

  defp conflict_problem(conn) do
    conn
    |> put_resp_header("retry-after", "1")
    |> PlaysteadWeb.Problem.send_problem(
      409,
      :idempotency_key_conflict,
      "A request with this Idempotency-Key is already being processed."
    )
  end
end
