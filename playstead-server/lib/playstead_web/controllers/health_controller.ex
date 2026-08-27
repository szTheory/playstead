defmodule PlaysteadWeb.HealthController do
  @moduledoc """
  Unauthenticated boolean health endpoint (D-16).

  Served outside any auth pipeline. Returns 200 when the app is up and
  `SELECT 1` succeeds against `Playstead.Repo`, 503 otherwise. The
  response body carries no component detail, no per-check map, no
  error text, and no version string — this shape is frozen. Richer
  per-component health (OPER-03) is Phase 5 under a different,
  authenticated route.
  """

  use PlaysteadWeb, :controller

  def show(conn, _params) do
    if database_up?() do
      conn
      |> put_status(200)
      |> json(%{status: "ok"})
    else
      conn
      |> put_status(503)
      |> json(%{status: "unavailable"})
    end
  end

  defp database_up? do
    case Playstead.Repo.query("SELECT 1") do
      {:ok, _result} -> true
      {:error, _reason} -> false
    end
  rescue
    _ -> false
  end
end
