defmodule PlaysteadWeb.Api.V1.DevicesController do
  @moduledoc """
  Authenticated `/api/v1/devices` endpoints (D-10, D-11). `me/2` and
  `rotate/2` operate on `conn.assigns.current_device`, set by
  `PlaysteadWeb.Plugs.DeviceAuth`. The owner-facing list/rename/revoke
  surface is a separate console-side concern (plan 01-04 task 3).
  """

  use PlaysteadWeb, :controller

  alias Playstead.{Idempotency, Pairing}

  action_fallback PlaysteadWeb.Api.V1.FallbackController

  @doc "GET /api/v1/devices/me"
  def me(conn, _params) do
    device = conn.assigns.current_device
    json(conn, device_json(device))
  end

  @doc """
  PATCH /api/v1/devices/me — device self-report refresh (D-20a).
  Idempotency-Key gated by `PlaysteadWeb.Plugs.Idempotency`; the actual
  write is wrapped by `Playstead.Idempotency.execute/4` so the receipt
  and the effect share one transaction.
  """
  def update(conn, params) do
    device = conn.assigns.current_device
    attrs = %{claimed_name: params["device_name"], app_version: params["app_version"]}

    run_idempotent(conn, device, fn ->
      case Pairing.update_self_report(device, attrs) do
        {:ok, updated} -> {:ok, 200, device_json(updated)}
        {:error, changeset} -> {:error, changeset}
      end
    end)
  end

  @doc """
  POST /api/v1/devices/me/rotate — Idempotency-Key gated, receipt and
  effect share one transaction via `Playstead.Idempotency.execute/4`.
  """
  def rotate(conn, _params) do
    device = conn.assigns.current_device

    run_idempotent(conn, device, fn ->
      case Pairing.rotate_credential(device) do
        {:ok, %{credential_plaintext: credential, fingerprint_prefix: fingerprint_prefix}} ->
          {:ok, 201, %{credential: credential, fingerprint_prefix: fingerprint_prefix}}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  defp run_idempotent(conn, device, effect_fun) do
    key = conn.assigns.idempotency_key
    fingerprint = conn.assigns.idempotency_fingerprint

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

      {:error, reason} ->
        PlaysteadWeb.Api.V1.FallbackController.call(conn, {:error, reason})
    end
  end

  defp device_json(device) do
    %{
      id: device.id,
      name: device.name,
      claimed_name: device.claimed_name,
      platform: device.platform,
      app_version: device.app_version,
      paired_at: device.paired_at,
      last_seen_at: device.last_seen_at
    }
  end
end
