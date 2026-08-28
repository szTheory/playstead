defmodule PlaysteadWeb.Browser.SmokeTest do
  use PlaysteadWeb.BrowserCase, async: false

  feature "the console serves a live page with both webfonts loaded", %{session: session} do
    session =
      session
      |> visit_live("/log-in")
      |> ensure_font_loaded("Inter")
      |> ensure_font_loaded("JetBrains Mono")

    faces = font_faces(session)
    assert ["Inter", "100 900", "loaded"] in faces
    assert ["JetBrains Mono", "400", "loaded"] in faces
    assert ["JetBrains Mono", "600", "loaded"] in faces

    assert same_color?(computed_style(session, "body", "backgroundColor"), "#0F172A")
    assert computed_style(session, "h1", "fontSize") == "28px"
  end

  feature "a cookie-authenticated session reaches an owner-only LiveView on the sandbox", %{
    session: session
  } do
    user = owner_fixture()

    session
    |> log_in_via_cookie(session_user(user))
    |> visit_live("/devices")
    |> assert_has(css("#devices-empty"))
    |> assert_has(css("#nav-account", text: user.email))
  end

  defp session_user(user), do: user
end
