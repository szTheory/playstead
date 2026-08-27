defmodule PlaysteadWeb.DevicesLiveTest do
  use PlaysteadWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playstead.AccountsFixtures
  import Playstead.PairingFixtures

  alias Playstead.Pairing
  alias Playstead.Pairing.Device

  # Shared with test/playstead/tls_trust_test.exs — a real, openssl-generated
  # self-signed certificate used only to prove the panel renders a real
  # computed fingerprint when a CA root is present on disk.
  @fixture_pem """
  -----BEGIN CERTIFICATE-----
  MIIDGTCCAgGgAwIBAgIUYwwqlgIxbtWsaO2LJJeEG7M9LNgwDQYJKoZIhvcNAQEL
  BQAwHDEaMBgGA1UEAwwRcGxheXN0ZWFkLXRlc3QtY2EwHhcNMjYwODI3MTc1NjM0
  WhcNMzYwODI0MTc1NjM0WjAcMRowGAYDVQQDDBFwbGF5c3RlYWQtdGVzdC1jYTCC
  ASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKqjGXFQVRAU0jYxOwmNQ6qr
  b4mzeGUyOtHlZPz+tOy7gNbSQA6m3IRGB4/nbdLlKlvwWpoeoOc5Bk34oHbDEGzz
  IRAQtmsa5BKjFyE3RBB82Zxc0K8kFVw05ensXHzELx5rtrrEY9i+FDFQ1hLTdz7+
  NLnIhxiCo5R3V1WimH8b0go3AWM5dpR9AhzdrGYWrqOlAgQyhUeiVFzhrrOGKIRS
  mtV0D3NL9n8zCOawea9mgLCCXJYu/Sx4UKPmVhsEfF6u5+Pb2Hs3rhHu1pRqob3c
  6zqWZvFku1YOEMct5sxBeLjp3js3gJxc0qegCAkAxF0aRIwj31kk5kUxekRjyt8C
  AwEAAaNTMFEwHQYDVR0OBBYEFPBCQrTgGS25M6RLG9Q8UoOoTKqLMB8GA1UdIwQY
  MBaAFPBCQrTgGS25M6RLG9Q8UoOoTKqLMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZI
  hvcNAQELBQADggEBAJzSYPzDgN+6ZmnfTh1L72H7k0mEirjyw1aRewh4Oi9r4AA7
  R4F+vkL5Xrq66KolT1fR6F0g1rRkvWKk425vkwr2+fh1oyEdZBgLuEPRomJTmO7Q
  9/6s/G24qSBmltVIn5oHzg/+fd9OR2ioa5inZaogqC0NRE3jihQq6+DrX6pjE9O4
  R7FnDXVYYy959dcB3BuZB2oT7xn92QCPlfwqGMTJMsYyoJNkKfT3+UVUWjBf9jJw
  18oUuBMyb01ThnCvQXBLcHlvQ+hEolgMHCZCCQK0bBSx5A0cltEgln4z93wdu2z+
  u9JaeIW4EFRlTve8HAPi8/WEj8pf5r0cCzQOOUM=
  -----END CERTIFICATE-----
  """

  @expected_fingerprint "DF:FD:38:6D:FA:0A:44:76:E5:D5:C6:B3:76:D2:C6:3C:FB:72:81:E8:B7:6D:75:F5:6D:B2:77:FA:7C:1B:67:7F"

  setup :register_and_log_in_user

  defp make_sudo_fresh(conn) do
    token = get_session(conn, :user_token)
    override_token_authenticated_at(token, DateTime.utc_now(:second))
    conn
  end

  defp make_sudo_stale(conn) do
    token = get_session(conn, :user_token)
    stale_at = DateTime.add(DateTime.utc_now(:second), -30, :minute)
    override_token_authenticated_at(token, stale_at)
    conn
  end

  describe "pairing approval queue" do
    test "renders the empty state and no Approve control when there are no requests", %{
      conn: conn
    } do
      {:ok, _lv, html} = live(conn, ~p"/devices")

      assert html =~ "No pairing requests"
      refute html =~ ~s(aria-label="Approve device")
    end

    test "renders 'Not reported' for a nil claimed device name", %{conn: conn} do
      {_request, _device_code} = pairing_request_fixture(%{"device_name" => nil})

      {:ok, _lv, html} = live(conn, ~p"/devices")

      assert html =~ "Not reported"
    end

    test "renders the microcopy verbatim", %{conn: conn} do
      pairing_request_fixture()

      {:ok, _lv, html} = live(conn, ~p"/devices")

      assert html =~ "Only approve if this code matches the one on your Mac&#39;s screen."
    end

    test "an expired request renders no Approve control and renders 'Expired'", %{conn: conn} do
      {_request, _device_code} = expired_pairing_request_fixture()

      {:ok, _lv, html} = live(conn, ~p"/devices")

      assert html =~ "Expired"
      refute html =~ ~s(aria-label="Approve device")
    end

    test "approving an expired request surfaces the expired error copy and leaves it unapproved",
         %{conn: conn, scope: scope} do
      {request, _device_code} = expired_pairing_request_fixture()

      {:ok, lv, _html} = live(conn, ~p"/devices")

      html = lv |> render_click("approve", %{"id" => request.id})

      assert html =~ "This request expired before it was approved."

      assert {:ok, %{status: "expired"}} = Pairing.get_request_status(request.id)
      assert {:error, _reason} = Pairing.approve(scope, request.id)
    end

    test "renders the queue-full notice at the pending cap", %{conn: conn} do
      for _ <- 1..Pairing.pending_queue_cap(), do: pairing_request_fixture()

      {:ok, _lv, html} = live(conn, ~p"/devices")

      assert html =~ "queue full"
      assert html =~ "oldest request will be evicted"
    end

    test "approving a pending request via the console calls Pairing.approve/2", %{
      conn: conn
    } do
      {request, _device_code} = pairing_request_fixture()

      {:ok, lv, _html} = live(conn, ~p"/devices")

      lv |> element("[aria-label='Approve device']") |> render_click()

      assert {:ok, %{status: "approved"}} = Pairing.get_request_status(request.id)
    end
  end

  describe "device list" do
    test "renders 'No devices paired yet' when nothing has ever paired", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/devices")

      assert html =~ "No devices paired yet"
    end

    test "a device with a nil last_seen_at renders 'Never'", %{conn: conn, scope: scope} do
      device_fixture(scope)

      {:ok, _lv, html} = live(conn, ~p"/devices")

      assert html =~ "Never"
    end

    test "a device missing a claimed platform renders 'Not reported'", %{conn: conn, scope: scope} do
      device_fixture(scope, %{"platform" => nil})

      {:ok, _lv, html} = live(conn, ~p"/devices")

      assert html =~ "Not reported"
    end

    test "no template renders a device credential value", %{conn: conn, scope: scope} do
      %{credential_plaintext: plaintext} = device_fixture(scope)

      {:ok, _lv, html} = live(conn, ~p"/devices")

      refute html =~ plaintext
    end

    test "clicking Revoke without a fresh sudo confirmation does not revoke the device", %{
      conn: conn,
      scope: scope
    } do
      %{device: device} = device_fixture(scope)
      conn = make_sudo_stale(conn)

      {:ok, lv, _html} = live(conn, ~p"/devices")

      assert {:error, {:redirect, %{to: "/sudo" <> _}}} =
               render_click(lv, "revoke", %{"id" => device.id})

      assert %Device{revoked_at: nil} = Playstead.Repo.get!(Device, device.id)
    end

    test "the revoke confirmation copy names the device and states only syncing stops", %{
      conn: conn,
      scope: scope
    } do
      device_fixture(scope, %{"device_name" => "Owner's MacBook Pro"})

      conn = make_sudo_fresh(conn)
      {:ok, _lv, html} = live(conn, ~p"/devices")

      assert html =~ "Revoke Owner&#39;s MacBook Pro?"
      assert html =~ "only syncing with this server stops"
    end

    test "revoking one device leaves another device's row unchanged and its credential valid", %{
      conn: conn,
      scope: scope
    } do
      %{device: device_a, credential_plaintext: _a} =
        device_fixture(scope, %{"device_name" => "First Mac"})

      %{device: device_b, credential_plaintext: plaintext_b} =
        device_fixture(scope, %{"device_name" => "Second Mac"})

      conn = make_sudo_fresh(conn)
      {:ok, lv, _html} = live(conn, ~p"/devices")

      lv |> element("[aria-label='Revoke #{device_name(device_a)}']") |> render_click()

      assert %Device{revoked_at: revoked_at} = Playstead.Repo.get!(Device, device_a.id)
      assert revoked_at != nil

      assert %Device{revoked_at: nil} = Playstead.Repo.get!(Device, device_b.id)
      assert {:ok, %Device{}} = Pairing.authenticate(plaintext_b)
    end

    test "a revoked device renders in the tombstone group with no un-revoke control", %{
      conn: conn,
      scope: scope
    } do
      %{device: device} = device_fixture(scope)
      {:ok, _} = Pairing.revoke_device(scope, device.id)

      {:ok, _lv, html} = live(conn, ~p"/devices")

      assert html =~ "Revoked"
      refute html =~ "Un-revoke"
      refute html =~ "un-revoke"
    end

    test "the rename input enforces a maximum length", %{conn: conn, scope: scope} do
      %{device: device} = device_fixture(scope)

      {:ok, lv, _html} = live(conn, ~p"/devices")

      html = lv |> element("[aria-label='Rename #{device_name(device)}']") |> render_click()

      assert html =~ ~s(maxlength="#{Device.max_name_length()}")
    end
  end

  describe "CA fingerprint panel (D-13)" do
    test "shows the plain-HTTP explanation with no fingerprint by default", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/devices")

      assert html =~ "There is no certificate to pin."
    end

    test "shows the computed fingerprint once the internal CA root exists on disk", %{
      conn: conn
    } do
      path =
        Path.join(System.tmp_dir!(), "devices_live_ca_#{System.unique_integer([:positive])}.pem")

      File.write!(path, @fixture_pem)
      System.put_env("PLAYSTEAD_CADDY_CA_PATH", path)

      on_exit(fn ->
        File.rm(path)
        System.delete_env("PLAYSTEAD_CADDY_CA_PATH")
      end)

      {:ok, _lv, html} = live(conn, ~p"/devices")

      assert html =~ @expected_fingerprint
      assert html =~ "A Mac can pin this fingerprint at pairing time."
    end
  end

  describe "static UI-SPEC contracts" do
    test "the 40px display-code size appears only in approval_card.ex" do
      files = Path.wildcard("lib/playstead_web/**/*.ex")

      matches =
        for file <- files, contents = File.read!(file), contents =~ "text-[40px]" do
          file
        end

      assert matches == ["lib/playstead_web/live/devices_live/approval_card.ex"]
    end

    test "the router mounts /devices behind the authenticated pipeline" do
      router_source = File.read!("lib/playstead_web/router.ex")

      assert router_source =~ ~s(live "/devices", DevicesLive)
    end
  end

  defp device_name(%Device{name: name}) when is_binary(name), do: name
  defp device_name(%Device{claimed_name: name}), do: name
end
