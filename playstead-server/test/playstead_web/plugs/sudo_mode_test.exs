defmodule PlaysteadWeb.Plugs.SudoModeTest do
  use PlaysteadWeb.ConnCase, async: true

  alias Playstead.Accounts.Scope
  alias PlaysteadWeb.Plugs.SudoMode

  import Playstead.AccountsFixtures

  defp scoped_conn(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.assign(:current_scope, Scope.for_user(user))
  end

  describe "require_sudo/2 (also exercised via call/2)" do
    test "passes through when the user has a fresh sudo confirmation", %{conn: conn} do
      user = %{owner_fixture() | authenticated_at: DateTime.utc_now()}
      conn = conn |> scoped_conn(user) |> SudoMode.call(SudoMode.init([]))

      refute conn.halted
    end

    test "redirects to /sudo when there is no sudo confirmation at all", %{conn: conn} do
      user = owner_fixture()
      conn = conn |> scoped_conn(user) |> SudoMode.call(SudoMode.init([]))

      assert conn.halted
      assert redirected_to(conn) == "/sudo"
    end

    test "a protected action attempted with a stale sudo confirmation is not performed", %{
      conn: conn
    } do
      stale_at = DateTime.add(DateTime.utc_now(), -30, :minute)
      user = %{owner_fixture() | authenticated_at: stale_at}

      conn = conn |> scoped_conn(user) |> SudoMode.call(SudoMode.init([]))

      assert conn.halted
      assert redirected_to(conn) == "/sudo"
    end

    test "stores the current path as the return-to target before redirecting", %{conn: _conn} do
      user = owner_fixture()

      conn =
        Phoenix.ConnTest.build_conn(:get, "/settings/sessions")
        |> scoped_conn(user)
        |> SudoMode.call(SudoMode.init([]))

      assert get_session(conn, :user_return_to) == "/settings/sessions"
    end

    test "redirects to /sudo when there is no authenticated user at all", %{conn: conn} do
      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Plug.Conn.assign(:current_scope, nil)
        |> SudoMode.call(SudoMode.init([]))

      assert conn.halted
      assert redirected_to(conn) == "/sudo"
    end
  end
end
