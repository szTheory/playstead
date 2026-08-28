defmodule PlaysteadWeb.Plugs.DeviceAuthTest do
  use Playstead.DataCase, async: true

  import Playstead.PairingFixtures
  import Playstead.AccountsFixtures

  alias Playstead.Pairing
  alias Playstead.Pairing.Device
  alias PlaysteadWeb.Plugs.DeviceAuth

  defp conn_with_auth_header(token) do
    Phoenix.ConnTest.build_conn()
    |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
  end

  describe "call/2" do
    test "accepts a valid credential from the Authorization header" do
      scope = user_scope_fixture()
      %{device: device, credential_plaintext: token} = device_fixture(scope)

      conn = token |> conn_with_auth_header() |> DeviceAuth.call(DeviceAuth.init([]))

      refute conn.halted
      assert conn.assigns.current_device.id == device.id
    end

    test "rejects a credential supplied only as a query parameter" do
      scope = user_scope_fixture()
      %{credential_plaintext: token} = device_fixture(scope)

      conn =
        Phoenix.ConnTest.build_conn(:get, "/api/v1/devices/me?token=#{token}")
        |> DeviceAuth.call(DeviceAuth.init([]))

      assert conn.halted
      assert conn.status == 401
    end

    test "rejects an unknown credential" do
      conn =
        "not-a-real-token"
        |> conn_with_auth_header()
        |> DeviceAuth.call(DeviceAuth.init([]))

      assert conn.halted
      assert conn.status == 401

      body = Jason.decode!(conn.resp_body)
      assert body["code"] == "unauthorized"
    end

    test "rejects a revoked device's credential with device_revoked" do
      scope = user_scope_fixture()
      %{device: device, credential_plaintext: token} = device_fixture(scope)

      Repo.update!(
        Device.revoke_changeset(device, DateTime.utc_now() |> DateTime.truncate(:second))
      )

      conn = token |> conn_with_auth_header() |> DeviceAuth.call(DeviceAuth.init([]))

      assert conn.halted
      assert conn.status == 401
      body = Jason.decode!(conn.resp_body)
      assert body["code"] == "device_revoked"
    end
  end

  describe "rotation handoff (D-10)" do
    test "the old credential keeps authenticating until the new one is first used, then stops" do
      scope = user_scope_fixture()
      %{device: device, credential_plaintext: old_token} = device_fixture(scope)

      {:ok, %{credential_plaintext: new_token}} = Pairing.rotate_credential(device)

      # Old token still works right after rotation — no forced cutover.
      conn = old_token |> conn_with_auth_header() |> DeviceAuth.call(DeviceAuth.init([]))
      refute conn.halted
      assert conn.assigns.current_device.id == device.id

      # First use of the new token activates it and drops the old one.
      conn = new_token |> conn_with_auth_header() |> DeviceAuth.call(DeviceAuth.init([]))
      refute conn.halted
      assert conn.assigns.current_device.id == device.id

      # The old token no longer authenticates.
      conn = old_token |> conn_with_auth_header() |> DeviceAuth.call(DeviceAuth.init([]))
      assert conn.halted
      assert conn.status == 401
    end
  end
end
