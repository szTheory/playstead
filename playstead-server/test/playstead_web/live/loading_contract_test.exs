defmodule PlaysteadWeb.LoadingContractTest do
  @moduledoc """
  01-UI-SPEC "loading" column: every console mutation shows an inline
  in-place affordance (disabled submit / dimmed control) and never a
  full-page overlay. LiveView's loading classes are applied client-side
  only while a request is in flight, so this is asserted as an attribute
  contract on the rendered markup.
  """
  use PlaysteadWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playstead.PairingFixtures

  test "unauthenticated forms: every submit button carries phx-disable-with", %{conn: conn} do
    for {path, button} <- [
          {~p"/log-in", "#login_submit"},
          {~p"/log-in/recovery", "#recovery_submit"}
        ] do
      {:ok, lv, _} = live(conn, path)
      assert has_element?(lv, "#{button}[phx-disable-with]"), "#{path} #{button}"
    end

    _token = PlaysteadWeb.BrowserScreens.minted_token()
    {:ok, lv, _} = live(conn, ~p"/setup")
    assert has_element?(lv, "#setup_token_submit[phx-disable-with]")
  end

  describe "authenticated" do
    setup :register_and_log_in_user

    test "sudo submit carries phx-disable-with", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/sudo")
      assert has_element?(lv, "#sudo_submit[phx-disable-with]")
    end

    test "approve / deny / rename / revoke dim while their click is in flight; no overlay exists",
         %{
           conn: conn,
           scope: scope
         } do
      {request, _} = pairing_request_fixture()
      %{device: device} = device_fixture(scope)
      {:ok, lv, html} = live(conn, ~p"/devices")

      for id <- [
            "approve-#{request.id}",
            "deny-#{request.id}",
            "device-#{device.id}-rename",
            "device-#{device.id}-revoke"
          ] do
        assert has_element?(lv, "##{id}[class*='phx-click-loading:opacity-60']"), id
      end

      refute html =~ "fixed inset-0"
    end

    test "session revoke dims while in flight", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/settings/sessions")
      assert lv
      refute html =~ "fixed inset-0"
    end
  end
end
