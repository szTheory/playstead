defmodule PlaysteadWeb.RecoveryLoginLiveTest do
  use PlaysteadWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playstead.AccountsFixtures

  describe "GET /log-in/recovery" do
    test "renders the single-use recovery code form with the D-05b copy", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/log-in/recovery")

      assert has_element?(lv, "h1", "Log in with a recovery code")
      assert has_element?(lv, "#recovery_login_form")
      assert has_element?(lv, "#recovery_submit", "Log in")

      assert has_element?(
               lv,
               "#recovery_login_form input[name='recovery[code]'][autocomplete=off]"
             )

      assert render(lv) =~ "ten single-use codes you saved at setup"
      refute render(lv) =~ "email"
    end

    test "the submit button carries the loading contract", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/log-in/recovery")
      assert has_element?(lv, "#recovery_submit[phx-disable-with]")
    end

    test "a failed recovery login re-renders with the inline error", %{conn: conn} do
      _owner = owner_fixture()

      conn = post(conn, ~p"/log-in/recovery", %{"recovery" => %{"code" => "nope-nope"}})
      assert redirected_to(conn) == ~p"/log-in/recovery"

      {:ok, lv, _html} = live(conn, ~p"/log-in/recovery")
      assert has_element?(lv, "#recovery_error")
    end
  end
end
