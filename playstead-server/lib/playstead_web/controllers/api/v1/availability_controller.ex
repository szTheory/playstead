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
    entries = Map.get(params, "entries", [])
    do_replace(conn, entries)
  end

  # WR-04 (03-16, gap closure): entries must be a list of maps before it
  # ever reaches Availability.replace_for_device/2, whose only guard is
  # `is_list` — a non-list, or a list holding a non-map element, used to
  # raise uncaught into a generic 500 inside normalize_entry/1 where
  # every sibling endpoint returns 422. This mirrors
  # ImportsController.precheck/2's guard-clause-plus-catch-all shape: a
  # matching clause for the valid case, a catch-all that returns an
  # {:error, {:validation_failed, detail}} tuple for the already-declared
  # action_fallback to render. An absent "entries" key is not matched
  # here at all — replace/2 defaults it to [] above, a valid empty full
  # replacement, exactly as it behaved before this guard existed.
  defp do_replace(conn, entries) when is_list(entries) do
    if Enum.all?(entries, &is_map/1) do
      device = conn.assigns.current_device
      key = conn.assigns.idempotency_key
      fingerprint = conn.assigns.idempotency_fingerprint

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
    else
      {:error,
       {:validation_failed,
        "The \"entries\" list must contain only objects, not other value types."}}
    end
  end

  defp do_replace(_conn, _entries) do
    {:error, {:validation_failed, "The \"entries\" field must be a list."}}
  end
end
