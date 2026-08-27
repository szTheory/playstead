defmodule PlaysteadWeb.SessionCookieTest do
  @moduledoc """
  End-to-end proof of D-06's cookie posture through the real router and
  `Plug.Session` pipeline (as opposed to `PlaysteadWeb.UserAuthTest`'s
  unit-level coverage of the remember-me cookie specifically): the
  session cookie itself carries `secure` only when the request's own
  scheme is HTTPS.
  """

  use PlaysteadWeb.ConnCase, async: true

  import Playstead.AccountsFixtures

  @session_cookie "_playstead_key"

  test "an https login receives a session cookie with the secure attribute", %{conn: conn} do
    user = owner_fixture()

    conn =
      post(conn, "https://localhost/log-in", %{
        "user" => %{"email" => user.email, "password" => valid_user_password()}
      })

    assert %{secure: true, http_only: true, same_site: "Lax"} = conn.resp_cookies[@session_cookie]
  end

  test "an http login receives a session cookie without the secure attribute", %{conn: conn} do
    user = owner_fixture()

    conn =
      post(conn, "http://localhost/log-in", %{
        "user" => %{"email" => user.email, "password" => valid_user_password()}
      })

    refute Map.has_key?(conn.resp_cookies[@session_cookie], :secure)
    assert %{http_only: true, same_site: "Lax"} = conn.resp_cookies[@session_cookie]
  end
end
