defmodule PlaysteadWeb.Api.V1.AvailabilityController do
  @moduledoc """
  `PUT /api/v1/devices/me/availability` — a paired device reports its
  own per-asset-set availability facts (plan 03-13, LIBR-02 gap
  closure). Mirrors `PlaySessionsController.create/2`'s
  `Idempotency.execute/4` call shape verbatim.

  This endpoint is a convenience read model only (T-03-13-03): nothing
  on the launch path consults it, and a device asserting facts it does
  not actually hold cannot make an unavailable game launchable.
  """

  use PlaysteadWeb, :controller

  alias Playstead.{Availability, Idempotency}

  action_fallback PlaysteadWeb.Api.V1.FallbackController

  @doc "PUT /api/v1/devices/me/availability"
  def replace(conn, params) do
    device = conn.assigns.current_device
    key = conn.assigns.idempotency_key
    fingerprint = conn.assigns.idempotency_fingerprint
    entries = Map.get(params, "entries", [])

    effect_fun = fn ->
      case Availability.replace_for_device(device, entries) do
        {:ok, :replaced} -> {:ok, 200, %{}}
        {:error, reason} -> {:error, reason}
      end
    end

    case Idempotency.execute(device.id, key, fingerprint, effect_fun) do
      {:ok, status, body} ->
        conn |> put_status(status) |> json(body)

      {:error, :conflict} ->
        conn
        |> put_resp_header("retry-after", "1")
        |> PlaysteadWeb.Problem.send_problem(
          409,
          :idempotency_key_conflict,
          "A request with this Idempotency-Key is already being processed."
        )

      {:error, :too_many_entries} ->
        PlaysteadWeb.Problem.send_problem(
          conn,
          422,
          :curation_limit_exceeded,
          "A device availability report cannot list more than 5000 entries."
        )

      {:error, reason} ->
        PlaysteadWeb.Api.V1.FallbackController.call(conn, {:error, reason})
    end
  end
end
