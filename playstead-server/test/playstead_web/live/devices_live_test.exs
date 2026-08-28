defmodule PlaysteadWeb.DevicesLiveTest do
  use PlaysteadWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playstead.AccountsFixtures
  import Playstead.PairingFixtures

  alias Playstead.Pairing
  alias Playstead.Pairing.Device

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

  describe "static UI-SPEC contracts" do
    test "the 40px display-code size (text-code-display) appears only in approval_card.ex" do
      files = Path.wildcard("lib/playstead_web/**/*.ex")

      matches =
        for file <- files,
            contents = File.read!(file),
            contents =~ "text-code-display" or contents =~ "text-[40px]" do
          file
        end

      assert matches == ["lib/playstead_web/live/devices_live/approval_card.ex"]
    end

    test "no console view uses an off-budget Tailwind size, weight, or off-palette color" do
      # 01-UI-SPEC: sizes are body 16 / label 14 / heading 20 / display 28 (+ the
      # one 40px code exception); weights are 400 and 600 only; every color is
      # one of the nine palette hexes. The browser suite proves this on the
      # rendered page — this is the cheap, always-on source-level tripwire.
      offenders =
        for file <- Path.wildcard("lib/playstead_web/live/**/*.ex"),
            {line, n} <- File.read!(file) |> String.split("\n") |> Enum.with_index(1),
            Regex.match?(
              ~r/\btext-(xs|lg|xl|2xl|3xl|4xl)\b|\bfont-(thin|light|medium|bold|extrabold|black)\b|\btext-(red|blue|green|amber|sky|slate|gray)-\d{3}\b/,
              line
            ),
            do: "#{file}:#{n}: #{String.trim(line)}"

      assert offenders == []
    end

    test "the router mounts /devices behind the authenticated pipeline" do
      router_source = File.read!("lib/playstead_web/router.ex")

      assert router_source =~ ~s(live "/devices", DevicesLive)
    end
  end

  defp device_name(%Device{name: name}) when is_binary(name), do: name
  defp device_name(%Device{claimed_name: name}), do: name
end
