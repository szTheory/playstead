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

  describe "POST /api/v1/device-pairing/requests/:id/redeem" do
    test "an approved request redeems exactly once, returning the credential", %{conn: conn} do
      scope = user_scope_fixture()
      {request, device_code} = approved_pairing_request_fixture(scope)

      conn =
        post(conn, ~p"/api/v1/device-pairing/requests/#{request.id}/redeem", %{
          "device_code" => device_code
        })

      assert %{"device_id" => device_id, "credential" => credential, "fingerprint_prefix" => fp} =
               json_response(conn, 201)

      assert is_binary(device_id)
      assert is_binary(credential)
      assert is_binary(fp)
    end

    test "a second redemption of the same request returns 409 and issues no second credential",
         %{conn: conn} do
      scope = user_scope_fixture()
      {request, device_code} = approved_pairing_request_fixture(scope)

      conn1 =
        post(conn, ~p"/api/v1/device-pairing/requests/#{request.id}/redeem", %{
          "device_code" => device_code
        })

      assert conn1.status == 201

      conn2 =
        post(build_conn(), ~p"/api/v1/device-pairing/requests/#{request.id}/redeem", %{
          "device_code" => device_code
        })

      assert_problem(conn2, 409, :pairing_request_already_redeemed)
      assert Playstead.Repo.aggregate(Playstead.Pairing.DeviceCredential, :count) == 1
    end

    test "two concurrent redemptions of the same request produce exactly one credential row" do
      scope = user_scope_fixture()
      {request, device_code} = approved_pairing_request_fixture(scope)
      parent = self()

      tasks =
        for _ <- 1..2 do
          Task.async(fn ->
            Ecto.Adapters.SQL.Sandbox.allow(Playstead.Repo, parent, self())
            Pairing.redeem(request.id, device_code)
          end)
        end

      results = Task.await_many(tasks)

      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Enum.count(results, &match?({:error, :pairing_request_already_redeemed}, &1)) == 1
      assert Playstead.Repo.aggregate(Playstead.Pairing.DeviceCredential, :count) == 1
    end

    test "an incorrect device_code returns an error indistinguishable from not-approved",
         %{conn: conn} do
      scope = user_scope_fixture()
      {request, _device_code} = approved_pairing_request_fixture(scope)

      conn =
        post(conn, ~p"/api/v1/device-pairing/requests/#{request.id}/redeem", %{
          "device_code" => "wrong-code"
        })

      assert_problem(conn, 409, :pairing_request_not_approved)
    end

    test "a pending (not yet approved) request cannot be redeemed", %{conn: conn} do
      {request, device_code} = pairing_request_fixture()

      conn =
        post(conn, ~p"/api/v1/device-pairing/requests/#{request.id}/redeem", %{
          "device_code" => device_code
        })

      assert_problem(conn, 409, :pairing_request_not_approved)
    end
  end

  describe "authenticated device endpoints" do
    test "a redeemed credential authenticates GET /api/v1/devices/me from the header",
         %{conn: conn} do
      scope = user_scope_fixture()
      %{credential_plaintext: token, device: device} = device_fixture(scope)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/v1/devices/me")

      assert %{"id" => id} = json_response(conn, 200)
      assert id == device.id
    end

    test "a query-param credential is rejected", %{conn: conn} do
      scope = user_scope_fixture()
      %{credential_plaintext: token} = device_fixture(scope)

      conn = get(conn, ~p"/api/v1/devices/me?token=#{token}")

      assert_problem(conn, 401, :unauthorized)
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
