defmodule PlaysteadWeb.Api.V1.PairingController do
  @moduledoc """
  The unauthenticated device-pairing ceremony endpoints (D-07, D-08):
  request creation and status polling. Neither endpoint accepts the
  display code as an input — there is no guessable-code surface. The
  redemption endpoint (task 2) also lives here, since the client has no
  credential yet at that point either.
  """

  use PlaysteadWeb, :controller

  alias Playstead.Pairing

  action_fallback PlaysteadWeb.Api.V1.FallbackController

  @doc "POST /api/v1/device-pairing/requests"
  def create(conn, params) do
    attrs = Map.put(params, "requesting_ip", conn.assigns[:client_ip])

    with {:ok, request} <- Pairing.create_request(attrs) do
      conn
      |> put_status(:created)
      |> json(%{
        id: request.id,
        display_code: request.display_code,
        poll_interval: Pairing.poll_interval_seconds(),
        expires_at: request.expires_at
      })
    end
  end

  @doc "GET /api/v1/device-pairing/requests/:id"
  def show(conn, %{"id" => id}) do
    with :ok <- Pairing.check_poll_rate(id),
         {:ok, request} <- Pairing.get_request_status(id) do
      json(conn, %{status: request.status})
    else
      {:error, :slow_down} ->
        PlaysteadWeb.Problem.send_problem(
          conn,
          429,
          :slow_down,
          "Polling too fast. Please wait for the advertised interval."
        )

      {:error, :not_found} ->
        PlaysteadWeb.Problem.send_problem(conn, 404, :not_found, "Pairing request not found.")
    end
  end

  @doc """
  POST /api/v1/device-pairing/requests/:id/redeem

  Unauthenticated — the client has no credential yet, only the
  `device_code` it generated at request time (D-08).
  """
  def redeem(conn, %{"id" => id} = params) do
    case Pairing.redeem(id, params["device_code"]) do
      {:ok, result} ->
        conn
        |> put_status(:created)
        |> json(%{
          device_id: result.device.id,
          credential: result.credential_plaintext,
          fingerprint_prefix: result.credential.fingerprint_prefix
        })

      {:error, :not_found} ->
        PlaysteadWeb.Problem.send_problem(conn, 404, :not_found, "Pairing request not found.")

      {:error, :pairing_request_expired} ->
        PlaysteadWeb.Problem.send_problem(
          conn,
          410,
          :pairing_request_expired,
          "This pairing request has expired."
        )

      {:error, :pairing_request_already_redeemed} ->
        PlaysteadWeb.Problem.send_problem(
          conn,
          409,
          :pairing_request_already_redeemed,
          "This pairing request has already been redeemed."
        )

      {:error, :pairing_request_not_approved} ->
        PlaysteadWeb.Problem.send_problem(
          conn,
          409,
          :pairing_request_not_approved,
          "This pairing request has not been approved."
        )
    end
  end
end
