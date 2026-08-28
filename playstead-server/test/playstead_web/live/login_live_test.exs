defmodule PlaysteadWeb.LoginLiveTest do
  use PlaysteadWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playstead.AccountsFixtures

  describe "login page" do
    test "renders login page with the D-02 no-email helper text and a Locked out? link", %{
      conn: conn
    } do
      {:ok, _lv, html} = live(conn, ~p"/log-in")

      assert html =~ "Log in"
      assert html =~ "No email will ever be sent — this server never sends mail."
      assert html =~ "Locked out?"
      refute html =~ "Sign up"
      refute html =~ "Register"
    end
  end

  describe "user login - password" do
    test "redirects if user logs in with valid credentials", %{conn: conn} do
      user = owner_fixture()

      {:ok, lv, _html} = live(conn, ~p"/log-in")

      form =
        form(lv, "#login_form",
          user: %{email: user.email, password: valid_user_password(), remember_me: true}
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/devices"
    end

    test "redirects to login page with a flash error if credentials are invalid", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/log-in")

      form =
        form(lv, "#login_form", user: %{email: "test@email.com", password: "123456"})

      render_submit(form, %{user: %{remember_me: true}})

      conn = follow_trigger_action(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "That password didn't match. Try again, or use the recovery option below if you're locked out."

      assert redirected_to(conn) == ~p"/log-in"
    end
  end
end
