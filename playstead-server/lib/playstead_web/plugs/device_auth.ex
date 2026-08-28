defmodule PlaysteadWeb.Plugs.DeviceAuth do
  @moduledoc """
  Header-only device credential authentication for `/api/v1` (D-10).

  Reads the credential exclusively from the `Authorization: Bearer
  <token>` header — never a query parameter, never a URL, never a
  fallback. A missing or malformed header, an unknown credential, and a
  revoked device's credential are all rejected; a revoked device gets
  the distinct `device_revoked` code so its client can offer "Pair
  Again" rather than a generic auth failure.

  On success, assigns `:current_device` onto the conn for downstream
  plugs/controllers.
  """

  import Plug.Conn

  alias Playstead.Pairing

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case bearer_token(conn) do
      {:ok, token} -> authenticate(conn, token)
      :error -> unauthorized(conn)
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      _ -> :error
    end
  end

  defp authenticate(conn, token) do
    case Pairing.authenticate(token) do
      {:ok, device} -> assign(conn, :current_device, device)
      {:error, :device_revoked} -> revoked(conn)
      {:error, :unauthorized} -> unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    conn
    |> PlaysteadWeb.Problem.send_problem(401, :unauthorized, "Authentication is required.")
    |> halt()
  end

  defp revoked(conn) do
    conn
    |> PlaysteadWeb.Problem.send_problem(
      401,
      :device_revoked,
      "This device's access was revoked."
    )
    |> halt()
  end
end
