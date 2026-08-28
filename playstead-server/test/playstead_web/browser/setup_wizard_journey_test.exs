defmodule PlaysteadWeb.Browser.SetupWizardJourneyTest do
  @moduledoc """
  UAT #2/#3 as an end-to-end browser journey: a fresh server's setup token
  from the boot banner → the four-step wizard → recovery codes shown once →
  honest readiness → /setup 404s forever → the owner logs in with the
  password, then with a recovery code, and a spent code is refused.
  """
  use PlaysteadWeb.BrowserCase, async: false

  alias Playstead.{Accounts, Setup}
  alias PlaysteadWeb.BrowserScreens

  @email "owner@example.com"
  @password "correct horse battery staple"

  feature "first run: token → credentials → recovery codes → readiness → login → recovery login",
          %{
            session: session
          } do
    token = BrowserScreens.minted_token()

    session =
      session
      |> visit_live("/setup")
      |> assert_has(css("#setup-step-1"))
      |> fill_in(css("#setup_token"), with: token)
      |> click(css("#setup_token_submit"))
      |> assert_has(css("#setup-step-2"))
      |> fill_in(css("#owner_email"), with: @email)
      |> fill_in(css("#owner_password"), with: @password)
      |> fill_in(css("#owner_password_confirmation"), with: @password)
      |> click(css("#owner_submit"))
      |> assert_has(css("#setup-step-3"))
      |> assert_has(css("#recovery-codes [data-role=code]", count: 10))

    codes =
      js(
        session,
        "return Array.from(document.querySelectorAll('#recovery-codes [data-role=code]')).map(e => e.textContent.trim());"
      )

    assert length(Enum.uniq(codes)) == 10
    assert Enum.all?(codes, &(String.length(&1) >= 8))

    # Recovery codes are displayed exactly once: the owner exists now and
    # the wizard never re-renders step 3 for a fresh visit.
    assert %Accounts.User{} = Accounts.get_owner()

    session =
      session
      |> click(css("#continue_to_readiness"))
      |> assert_has(css("#readiness [data-state]", count: 3))
      |> assert_has(css("#readiness-database[data-state=ok]"))
      |> assert_has(css("#backup-nudge"))
      |> click(css("#finish_setup"))
      |> assert_has(css("#login_form"))

    assert current_path(session) == "/log-in"

    # /setup is closed permanently — a plain 404, not a redirect.
    session = visit(session, "/setup")
    assert Wallaby.Browser.text(session) =~ "Not Found"
    assert Setup.verify_token(token) == {:error, :invalid_or_expired}

    # Password login through the real form.
    session =
      session
      |> log_in_via_browser(@email, @password)
      |> assert_has(css("#nav-account", text: @email))

    session
    |> visit_live("/devices")
    |> assert_has(css("#devices-empty"))
    |> click(css("#log-out"))
    |> assert_has(css("#nav-log-in"))

    # Recovery-code login (D-05b): one code works exactly once.
    [code | _] = codes

    session =
      session
      |> visit_live("/log-in/recovery")
      |> fill_in(css("#recovery_login_form_code"), with: code)
      |> click(css("#recovery_submit"))
      |> assert_has(css("#nav-account", text: @email))

    session
    |> click(css("#log-out"))
    |> assert_has(css("#nav-log-in"))
    |> visit_live("/log-in/recovery")
    |> fill_in(css("#recovery_login_form_code"), with: code)
    |> click(css("#recovery_submit"))
    |> assert_has(
      css("#recovery_error", text: "That recovery code didn't match, or was already used.")
    )
    |> assert_gone(css("#nav-account"))
  end
end
