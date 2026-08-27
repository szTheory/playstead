defmodule PlaysteadWeb.Api.V1.PairingControllerTest do
  use PlaysteadWeb.ApiCase, async: false

  import Playstead.PairingFixtures
  import Playstead.AccountsFixtures

  alias Playstead.Pairing

  describe "POST /api/v1/device-pairing/requests" do
    test "creates a pairing request and returns the display code, poll interval, and expiry",
         %{conn: conn} do
      body = %{
        "device_code" => unique_device_code(),
        "device_name" => "Owner's Mac",
        "platform" => "macOS 15.0",
        "app_version" => "1.0.0",
        "capabilities" => %{}
      }

      conn = post(conn, ~p"/api/v1/device-pairing/requests", body)

      assert %{
               "id" => id,
               "display_code" => display_code,
               "poll_interval" => poll_interval,
               "expires_at" => _expires_at
             } = json_response(conn, 201)

      assert is_binary(id)
      assert Regex.match?(~r/^[A-Z]{4}-[A-Z]{4}$/, display_code)
      assert poll_interval == Pairing.poll_interval_seconds()
    end

    test "rejects a request missing device_code", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/device-pairing/requests", %{"device_name" => "No Code"})

      assert_problem(conn, 422, :validation_failed)
    end

    test "past the per-IP limit returns the rate_limited code", %{conn: conn} do
      # A unique fake IP per test avoids bleeding Hammer's shared ETS
      # counters into other tests (same pattern as ThrottleTest).
      unique = System.unique_integer([:positive])
      ip = {198, 51, div(unique, 256) |> rem(256), rem(unique, 256)}

      original = Application.get_env(:playstead, PlaysteadWeb.Plugs.Throttle, [])

      Application.put_env(:playstead, PlaysteadWeb.Plugs.Throttle,
        per_ip_limit: 1,
        per_account_limit: 1_000_000
      )

      on_exit(fn -> Application.put_env(:playstead, PlaysteadWeb.Plugs.Throttle, original) end)

      conn = Map.put(conn, :remote_ip, ip)

      conn1 =
        post(conn, ~p"/api/v1/device-pairing/requests", %{"device_code" => unique_device_code()})

      assert conn1.status == 201

      conn2 =
        conn
        |> Map.put(:remote_ip, ip)
        |> post(~p"/api/v1/device-pairing/requests", %{"device_code" => unique_device_code()})

      assert_problem(conn2, 429, :rate_limited)
    end
  end

  describe "GET /api/v1/device-pairing/requests/:id" do
    test "returns pending for a fresh request", %{conn: conn} do
      {request, _code} = pairing_request_fixture()

      conn = get(conn, ~p"/api/v1/device-pairing/requests/#{request.id}")

      assert json_response(conn, 200) == %{"status" => "pending"}
    end

    test "returns approved after approval", %{conn: conn} do
      scope = user_scope_fixture()
      {request, _code} = pairing_request_fixture()
      {:ok, _} = Pairing.approve(scope, request.id)

      conn = get(conn, ~p"/api/v1/device-pairing/requests/#{request.id}")

      assert json_response(conn, 200) == %{"status" => "approved"}
    end

    test "returns 404 for an unknown request", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/device-pairing/requests/#{Ecto.UUID.generate()}")

      assert_problem(conn, 404, :not_found)
    end

    test "polling faster than the advertised interval returns slow_down", %{conn: _conn} do
      {request, _code} = pairing_request_fixture()

      conn1 = get(build_conn(), ~p"/api/v1/device-pairing/requests/#{request.id}")
      assert conn1.status == 200

      conn2 = get(build_conn(), ~p"/api/v1/device-pairing/requests/#{request.id}")
      assert_problem(conn2, 429, :slow_down)
    end
  end

  describe "router surface" do
    test "no route accepts a display code as a path or query parameter" do
      source = File.read!("lib/playstead_web/router.ex")
      refute source =~ ":display_code"
      refute source =~ "display_code"
    end
  end
end
