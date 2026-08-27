defmodule PlaysteadWeb.Api.V1.DevicesControllerTest do
  use PlaysteadWeb.ApiCase, async: true

  import Playstead.PairingFixtures
  import Playstead.AccountsFixtures

  alias Playstead.Pairing

  describe "GET /api/v1/devices/me" do
    test "returns the authenticated device's own record", %{conn: conn} do
      scope = user_scope_fixture()
      %{device: device, credential_plaintext: token} = device_fixture(scope)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/v1/devices/me")

      body = json_response(conn, 200)
      assert body["id"] == device.id
      assert body["claimed_name"] == device.claimed_name
    end

    test "rejects a request with no Authorization header", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/devices/me")
      assert_problem(conn, 401, :unauthorized)
    end
  end

  describe "POST /api/v1/devices/me/rotate" do
    test "issues a new credential without invalidating the old one immediately", %{conn: conn} do
      scope = user_scope_fixture()
      %{device: device, credential_plaintext: old_token} = device_fixture(scope)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{old_token}")
        |> put_req_header("idempotency-key", "rotate-#{System.unique_integer([:positive])}")
        |> post(~p"/api/v1/devices/me/rotate")

      assert %{"credential" => new_token, "fingerprint_prefix" => fp} = json_response(conn, 201)
      assert is_binary(new_token)
      assert is_binary(fp)

      # Old credential still works — rotation is use-activated, not forced.
      still_works =
        build_conn()
        |> put_req_header("authorization", "Bearer #{old_token}")
        |> get(~p"/api/v1/devices/me")

      assert %{"id" => id} = json_response(still_works, 200)
      assert id == device.id
    end
  end

  describe "PROT-02 isolation contract" do
    test "revoking one device returns device_revoked for it and 200 for the other, in one test" do
      scope = user_scope_fixture()
      %{device: device_a, credential_plaintext: token_a} = device_fixture(scope)
      %{device: device_b, credential_plaintext: token_b} = device_fixture(scope)

      {:ok, _} = Pairing.revoke_device(scope, device_a.id)

      revoked_conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_a}")
        |> get(~p"/api/v1/devices/me")

      assert_problem(revoked_conn, 401, :device_revoked)

      working_conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_b}")
        |> get(~p"/api/v1/devices/me")

      assert %{"id" => id} = json_response(working_conn, 200)
      assert id == device_b.id
    end
  end
end
