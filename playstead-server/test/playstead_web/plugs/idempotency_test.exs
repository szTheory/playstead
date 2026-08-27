defmodule PlaysteadWeb.Plugs.IdempotencyTest do
  use PlaysteadWeb.ApiCase, async: true

  import Playstead.PairingFixtures
  import Playstead.AccountsFixtures

  defp authed(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")
  defp with_key(conn, key), do: put_req_header(conn, "idempotency-key", key)

  describe "PATCH /api/v1/devices/me" do
    test "a mutating request without an Idempotency-Key header is rejected and produces no effect",
         %{conn: conn} do
      scope = user_scope_fixture()
      %{device: device, credential_plaintext: token} = device_fixture(scope)

      conn =
        conn
        |> authed(token)
        |> patch(~p"/api/v1/devices/me", %{"device_name" => "New Name"})

      assert_problem(conn, 422, :idempotency_key_missing)

      reloaded = Playstead.Repo.get!(Playstead.Pairing.Device, device.id)
      assert reloaded.claimed_name == device.claimed_name
    end

    test "a replay with the same key and payload returns the identical status/body and exactly one effect row",
         %{conn: conn} do
      scope = user_scope_fixture()
      %{device: device, credential_plaintext: token} = device_fixture(scope)
      key = "replay-key-#{System.unique_integer([:positive])}"

      first =
        conn
        |> authed(token)
        |> with_key(key)
        |> patch(~p"/api/v1/devices/me", %{"device_name" => "Renamed Mac"})

      first_body = json_response(first, 200)

      second =
        build_conn()
        |> authed(token)
        |> with_key(key)
        |> patch(~p"/api/v1/devices/me", %{"device_name" => "Renamed Mac"})

      assert second.status == first.status
      assert json_response(second, 200) == first_body

      reloaded = Playstead.Repo.get!(Playstead.Pairing.Device, device.id)
      assert reloaded.claimed_name == "Renamed Mac"
    end

    test "a replay with the same key and a different payload returns 422 idempotency_key_mismatch and produces no second effect",
         %{conn: conn} do
      scope = user_scope_fixture()
      %{device: device, credential_plaintext: token} = device_fixture(scope)
      key = "mismatch-key-#{System.unique_integer([:positive])}"

      _first =
        conn
        |> authed(token)
        |> with_key(key)
        |> patch(~p"/api/v1/devices/me", %{"device_name" => "First Name"})

      second =
        build_conn()
        |> authed(token)
        |> with_key(key)
        |> patch(~p"/api/v1/devices/me", %{"device_name" => "Second Name"})

      assert_problem(second, 422, :idempotency_key_mismatch)

      reloaded = Playstead.Repo.get!(Playstead.Pairing.Device, device.id)
      assert reloaded.claimed_name == "First Name"
    end

    test "a retry racing an in-flight receipt returns 409 idempotency_key_conflict with a Retry-After header",
         %{conn: conn} do
      scope = user_scope_fixture()
      %{device: device, credential_plaintext: token} = device_fixture(scope)
      key = "in-flight-key-#{System.unique_integer([:positive])}"

      Playstead.IdempotencyFixtures.in_flight_receipt_fixture(
        device_id: device.id,
        idempotency_key: key
      )

      conn =
        conn
        |> authed(token)
        |> with_key(key)
        |> patch(~p"/api/v1/devices/me", %{"device_name" => "Whatever"})

      assert_problem(conn, 409, :idempotency_key_conflict)
      assert get_resp_header(conn, "retry-after") != []
    end

    test "the same key from a different device is treated as a distinct request", %{conn: conn} do
      scope = user_scope_fixture()
      %{credential_plaintext: token_a} = device_fixture(scope)
      %{credential_plaintext: token_b} = device_fixture(scope)
      key = "shared-key-#{System.unique_integer([:positive])}"

      conn_a =
        conn
        |> authed(token_a)
        |> with_key(key)
        |> patch(~p"/api/v1/devices/me", %{"device_name" => "A's Name"})

      assert conn_a.status == 200

      conn_b =
        build_conn()
        |> authed(token_b)
        |> with_key(key)
        |> patch(~p"/api/v1/devices/me", %{"device_name" => "B's Name"})

      assert conn_b.status == 200
    end
  end

  describe "POST /api/v1/devices/me/rotate" do
    test "a replay with the same key returns the identical response and does not re-execute",
         %{conn: conn} do
      scope = user_scope_fixture()
      %{credential_plaintext: token} = device_fixture(scope)
      key = "rotate-key-#{System.unique_integer([:positive])}"

      first =
        conn
        |> authed(token)
        |> with_key(key)
        |> post(~p"/api/v1/devices/me/rotate")

      first_body = json_response(first, 201)

      second =
        build_conn()
        |> authed(token)
        |> with_key(key)
        |> post(~p"/api/v1/devices/me/rotate")

      assert json_response(second, 201) == first_body
    end

    test "requires an Idempotency-Key header", %{conn: conn} do
      scope = user_scope_fixture()
      %{credential_plaintext: token} = device_fixture(scope)

      conn =
        conn
        |> authed(token)
        |> post(~p"/api/v1/devices/me/rotate")

      assert_problem(conn, 422, :idempotency_key_missing)
    end
  end

  test "no code path or response body describes a replay as a duplicate request", %{conn: conn} do
    scope = user_scope_fixture()
    %{credential_plaintext: token} = device_fixture(scope)
    key = "invisible-key-#{System.unique_integer([:positive])}"

    conn =
      conn
      |> authed(token)
      |> with_key(key)
      |> patch(~p"/api/v1/devices/me", %{"device_name" => "Quiet Retry"})

    refute json_response(conn, 200) |> Jason.encode!() =~ ~r/duplicate/i
  end
end
