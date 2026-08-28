defmodule PlaysteadWeb.Api.V1.HelloControllerTest do
  use PlaysteadWeb.ApiCase, async: true

  import Playstead.PairingFixtures
  import Playstead.AccountsFixtures

  @compatible_capabilities %{
    "protocol" => %{"min" => "1.0.0", "max" => "1.0.0"},
    "app" => %{"min" => "1.0.0", "max" => "1.0.0"},
    "cache" => %{"min" => "1.0.0", "max" => "1.0.0"},
    "transfer" => %{"min" => "1.0.0", "max" => "1.0.0"},
    "adapter" => %{"min" => "1.0.0", "max" => "1.0.0"},
    "save" => %{"min" => "1.0.0", "max" => "1.0.0"}
  }

  defp authed_conn(conn, token) do
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "POST /api/v1/hello" do
    test "a compatible hello returns the compatible verdict", %{conn: conn} do
      scope = user_scope_fixture()
      %{credential_plaintext: token} = device_fixture(scope)

      conn =
        conn
        |> authed_conn(token)
        |> post(~p"/api/v1/hello", %{"capabilities" => @compatible_capabilities})

      assert %{"verdict" => "compatible"} = json_response(conn, 200)
    end

    test "an incompatible protocol range returns 422 with code capability_incompatible and a full remedy",
         %{conn: conn} do
      scope = user_scope_fixture()
      %{credential_plaintext: token} = device_fixture(scope)

      incompatible =
        Map.put(@compatible_capabilities, "protocol", %{"min" => "0.1.0", "max" => "0.5.0"})

      conn =
        conn
        |> authed_conn(token)
        |> post(~p"/api/v1/hello", %{"capabilities" => incompatible})

      body = assert_problem(conn, 422, :capability_incompatible)
      remedy = body["remedy"]

      assert Enum.sort(Map.keys(remedy)) == [
               "detail_url",
               "minimum_required",
               "side_too_old",
               "who_must_act"
             ]

      assert remedy["side_too_old"] == "client"
      assert remedy["who_must_act"] == "user"
    end

    test "a device with an incompatible verdict can still GET /api/v1/capabilities and its own device record",
         %{conn: conn} do
      scope = user_scope_fixture()
      %{device: device, credential_plaintext: token} = device_fixture(scope)

      incompatible =
        Map.put(@compatible_capabilities, "protocol", %{"min" => "0.1.0", "max" => "0.5.0"})

      _ =
        conn
        |> authed_conn(token)
        |> post(~p"/api/v1/hello", %{"capabilities" => incompatible})

      caps_conn = get(build_conn(), ~p"/api/v1/capabilities")
      assert caps_conn.status == 200

      me_conn =
        build_conn()
        |> authed_conn(token)
        |> get(~p"/api/v1/devices/me")

      assert %{"id" => id} = json_response(me_conn, 200)
      assert id == device.id
    end

    test "an unrecognized capability key returns the same verdict as the same hello without it",
         %{conn: conn} do
      scope = user_scope_fixture()
      %{credential_plaintext: token} = device_fixture(scope)

      with_unknown =
        Map.put(@compatible_capabilities, "quantum_teleport", %{
          "min" => "9.9.9",
          "max" => "9.9.9"
        })

      conn =
        conn
        |> authed_conn(token)
        |> post(~p"/api/v1/hello", %{"capabilities" => with_unknown})

      assert %{"verdict" => "compatible"} = json_response(conn, 200)
    end

    test "repeating an identical hello returns an identical verdict and leaves one declaration row",
         %{conn: conn} do
      scope = user_scope_fixture()
      %{device: device, credential_plaintext: token} = device_fixture(scope)

      first =
        conn
        |> authed_conn(token)
        |> post(~p"/api/v1/hello", %{"capabilities" => @compatible_capabilities})

      second =
        build_conn()
        |> authed_conn(token)
        |> post(~p"/api/v1/hello", %{"capabilities" => @compatible_capabilities})

      assert json_response(first, 200) == json_response(second, 200)

      count =
        Playstead.Protocol.CapabilityDeclaration
        |> Playstead.Repo.all()
        |> Enum.count(&(&1.device_id == device.id))

      assert count == 1
    end

    test "rejects a request with no Authorization header", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/hello", %{"capabilities" => @compatible_capabilities})
      assert_problem(conn, 401, :unauthorized)
    end
  end
end
