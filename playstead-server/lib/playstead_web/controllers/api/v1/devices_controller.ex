defmodule PlaysteadWeb.Api.V1.DevicesController do
  @moduledoc """
  Authenticated `/api/v1/devices` endpoints (D-10, D-11). `me/2` and
  `rotate/2` operate on `conn.assigns.current_device`, set by
  `PlaysteadWeb.Plugs.DeviceAuth`. The owner-facing list/rename/revoke
  surface is a separate console-side concern (plan 01-04 task 3).
  """

  use PlaysteadWeb, :controller

  alias Playstead.Pairing

  action_fallback PlaysteadWeb.Api.V1.FallbackController

  @doc "GET /api/v1/devices/me"
  def me(conn, _params) do
    device = conn.assigns.current_device

    json(conn, %{
      id: device.id,
      name: device.name,
      claimed_name: device.claimed_name,
      platform: device.platform,
      app_version: device.app_version,
      paired_at: device.paired_at,
      last_seen_at: device.last_seen_at
    })
  end

  @doc "POST /api/v1/devices/me/rotate"
  def rotate(conn, _params) do
    device = conn.assigns.current_device

    with {:ok, %{credential_plaintext: credential, fingerprint_prefix: fingerprint_prefix}} <-
           Pairing.rotate_credential(device) do
      conn
      |> put_status(:created)
      |> json(%{credential: credential, fingerprint_prefix: fingerprint_prefix})
    end
  end
end
