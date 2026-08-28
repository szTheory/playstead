defmodule PlaysteadWeb.DevicesLiveEnvTest do
  # `async: false` on purpose: DevicesLive reads the transport state through
  # `Playstead.TlsTrust.runtime_env/0` on mount, so the CA path is injected
  # globally via `:env_overrides` — safe only with no concurrent modules.
  use PlaysteadWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Playstead.TlsFixtures

  setup :register_and_log_in_user

  describe "CA fingerprint panel (D-13)" do
    test "shows the plain-HTTP explanation with no fingerprint by default", %{conn: conn} do
      put_env_overrides!(%{"PLAYSTEAD_CADDY_CA_PATH" => "/nonexistent/root.crt"})

      {:ok, _lv, html} = live(conn, ~p"/devices")

      assert html =~ "There is no certificate to pin."
    end

    test "shows the computed fingerprint once the internal CA root exists on disk", %{
      conn: conn
    } do
      path = write_fixture_cert!("devices_live_ca")
      put_env_overrides!(%{"PLAYSTEAD_CADDY_CA_PATH" => path})

      {:ok, _lv, html} = live(conn, ~p"/devices")

      assert html =~ expected_fingerprint()
      assert html =~ "A Mac can pin this fingerprint at pairing time."
    end

    test "names the transport honestly for an external proxy and a Let's Encrypt domain", %{
      conn: conn
    } do
      put_env_overrides!(%{"PLAYSTEAD_PROXY" => "external"})
      {:ok, _lv, html} = live(conn, ~p"/devices")
      refute html =~ expected_fingerprint()

      put_env_overrides!(%{"PLAYSTEAD_DOMAIN" => "example.com"})
      {:ok, _lv, html} = live(conn, ~p"/devices")
      refute html =~ expected_fingerprint()
    end
  end
end
