defmodule PlaysteadWeb.OperationsLiveTest do
  use PlaysteadWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "an authenticated owner can mount and refresh the ordered operations view", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/operations")

    assert has_element?(live, "#operations")
    assert has_element?(live, "#operations-database")
    assert has_element?(live, "#operations-blobs")
    assert has_element?(live, "#operations-queue")
    assert has_element?(live, "#operations-migrations")
    assert has_element?(live, "#operations-capacity")
    assert has_element?(live, "#operations-backup")
    assert live |> element("#refresh-operations") |> render_click() =~ "Operations"
  end

  test "operations requires an authenticated owner", %{} do
    unauthenticated_conn = Phoenix.ConnTest.build_conn()

    assert {:error, {:redirect, %{to: "/log-in"}}} =
             live(unauthenticated_conn, ~p"/operations")
  end
end
