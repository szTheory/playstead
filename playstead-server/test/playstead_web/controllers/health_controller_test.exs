defmodule PlaysteadWeb.HealthControllerTest do
  use PlaysteadWeb.ConnCase, async: true

  test "GET /healthz returns 200 and no component detail when the app is up", %{conn: conn} do
    conn = get(conn, ~p"/healthz")

    assert conn.status == 200
    body = json_response(conn, 200)

    # D-16: no per-check map, no error text, no version string.
    assert Map.keys(body) == ["status"]
    refute Map.has_key?(body, "version")
    refute Map.has_key?(body, "checks")
    refute Map.has_key?(body, "database")
  end
end
