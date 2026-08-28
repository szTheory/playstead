defmodule PlaysteadWeb.Browser.AuthSessionsJourneyTest do
  @moduledoc """
  UAT #4 as an end-to-end browser journey: login → the sessions list →
  revoke another session without ending this one → a stale sudo is sent to
  /sudo and returned to the pending page after re-confirming → log out.
  """
  use PlaysteadWeb.BrowserCase, async: false

  alias Playstead.Accounts

  feature "sessions: list, revoke one, stale sudo round-trip, log out", %{session: session} do
    password = valid_user_password()
    user = owner_fixture(%{password: password, password_confirmation: password})

    session =
      session
      |> log_in_via_browser(user.email, password)
      |> assert_has(css("#nav-account", text: user.email))

    # A fresh login is a fresh sudo: the sessions page renders directly.
    session =
      session
      |> visit_live("/settings/sessions")
      |> assert_has(css("#sessions [data-current=true]", count: 1))

    other = Accounts.generate_user_session_token(user, "Firefox on a laptop")
    other_id = Playstead.Repo.get_by!(Accounts.UserToken, token: other).id

    session =
      session
      |> visit_live("/settings/sessions")
      |> assert_has(css("#session-#{other_id}-label", text: "Firefox on a laptop"))
      |> click(css("#session-#{other_id}-revoke"))
      |> assert_gone(css("#session-#{other_id}"))
      |> assert_has(css("#sessions [data-current=true]", count: 1))

    assert is_nil(Accounts.get_user_by_session_token(other))
    assert Accounts.list_sessions(Accounts.Scope.for_user(user)) |> length() == 1

    # Age this browser's session past the sudo window: the next dangerous
    # page is gated, a wrong password stays on /sudo, the right one returns.
    [%{token: mine}] = Accounts.list_sessions(Accounts.Scope.for_user(user))
    override_token_authenticated_at(mine, DateTime.utc_now(:second) |> DateTime.add(-30, :minute))

    session =
      session
      |> visit("/settings/sessions")
      |> assert_has(css("#sudo_form"))

    # The router plug stores the return target in the session (no query param).
    assert current_path(session) == "/sudo"

    session =
      session
      |> fill_in(css("#sudo_form_password"), with: "wrong")
      |> click(css("#sudo_submit"))
      |> assert_has(css("#sudo_error", text: "That password didn't match."))
      |> fill_in(css("#sudo_form_password"), with: password)
      |> click(css("#sudo_submit"))
      |> assert_has(css("#sessions"))

    assert current_path(session) == "/settings/sessions"

    session
    |> click(css("#log-out"))
    |> assert_has(css("#nav-log-in"))
    |> visit("/devices")
    |> assert_has(css("#login_form"))
  end
end
