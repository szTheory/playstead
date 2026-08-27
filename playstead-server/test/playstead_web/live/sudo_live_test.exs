defmodule PlaysteadWeb.SudoLiveTest do
  use PlaysteadWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders the sudo re-authentication prompt with a clean single password field", %{
    conn: conn
  } do
    {:ok, _lv, html} = live(conn, ~p"/sudo")

    assert html =~ "Confirm it&#39;s you — enter your password to continue."
    assert html =~ ~s(type="password")
    refute html =~ "No email will ever be sent"
  end
end
