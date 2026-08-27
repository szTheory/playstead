defmodule PlaysteadWeb.SessionsLiveTest do
  use PlaysteadWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playstead.AccountsFixtures

  alias Playstead.Accounts
  alias Playstead.Accounts.Scope

  setup :register_and_log_in_user

  defp make_sudo_fresh(conn) do
    token = get_session(conn, :user_token)
    override_token_authenticated_at(token, DateTime.utc_now(:second))
    conn
  end

  describe "GET /settings/sessions" do
    test "redirects to /sudo without a fresh sudo confirmation", %{conn: conn} do
      token = get_session(conn, :user_token)
      stale_at = DateTime.add(DateTime.utc_now(:second), -30, :minute)
      override_token_authenticated_at(token, stale_at)

      assert {:error, {:redirect, %{to: "/sudo"}}} = live(conn, ~p"/settings/sessions")
    end

    test "renders once sudo mode is fresh", %{conn: conn} do
      conn = make_sudo_fresh(conn)
      {:ok, _lv, html} = live(conn, ~p"/settings/sessions")

      assert html =~ "Sessions"
    end

    test "renders the generic label for a session with no client string", %{conn: conn} do
      conn = make_sudo_fresh(conn)
      {:ok, _lv, html} = live(conn, ~p"/settings/sessions")

      assert html =~ "Browser session"
    end
  end

  describe "revoking a session" do
    test "revoking one session leaves another session's token valid", %{conn: conn, user: user} do
      other_token = Accounts.generate_user_session_token(user)
      conn = make_sudo_fresh(conn)

      {:ok, lv, _html} = live(conn, ~p"/settings/sessions")

      other_session =
        Enum.find(Accounts.list_sessions(Scope.for_user(user)), &(&1.token == other_token))

      lv |> element("#session-#{other_session.id} button") |> render_click()

      refute Accounts.get_user_by_session_token(other_token)
      # The current session's own token, established by register_and_log_in_user, still works.
      assert Accounts.get_user_by_session_token(get_session(conn, :user_token))
    end
  end
end
