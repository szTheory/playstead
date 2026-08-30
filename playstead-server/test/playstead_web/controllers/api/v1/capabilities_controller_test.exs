defmodule PlaysteadWeb.Api.V1.CapabilitiesControllerTest do
  use PlaysteadWeb.ConnCase, async: true

  @top_level_keys ~w(protocol server_build supported_client_ranges)
  @namespaces ~w(protocol app cache transfer adapter save)

  test "GET /api/v1/capabilities returns the frozen envelope", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/capabilities")

    assert conn.status == 200
    body = json_response(conn, 200)

    # D-18 meta-contract freeze: fail if a top-level key is added,
    # removed, or renamed — not merely if one is missing.
    assert Enum.sort(Map.keys(body)) == Enum.sort(@top_level_keys)

    assert body["protocol"]["major"] == 1
    assert is_integer(body["protocol"]["minor"])
    assert is_binary(body["server_build"])

    ranges = body["supported_client_ranges"]
    assert Enum.sort(Map.keys(ranges)) == Enum.sort(@namespaces)

    for namespace <- @namespaces do
      range = ranges[namespace]
      assert Enum.sort(Map.keys(range)) == ["max", "min"]
    end
  end

  test "D-19: transfer advertises max 1.1.0, every other namespace stays at 1.0.0", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/capabilities")
    ranges = json_response(conn, 200)["supported_client_ranges"]

    assert ranges["transfer"] == %{"min" => "1.0.0", "max" => "1.1.0"}

    for namespace <- @namespaces, namespace != "transfer" do
      assert ranges[namespace] == %{"min" => "1.0.0", "max" => "1.0.0"}
    end
  end

  test "GET /api/v1/capabilities requires no authentication", %{conn: conn} do
    # D-19: an incompatible/unauthenticated client is never locked out.
    conn = get(conn, ~p"/api/v1/capabilities")
    assert conn.status == 200
  end
end
