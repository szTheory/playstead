defmodule PlaysteadWeb.Browser.CopyTest do
  @moduledoc """
  The copywriting-contract strings that are visible by default on a screen,
  asserted in the browser (Wallaby's text/2 only returns *rendered* text, so
  this also proves nothing hides them). The full 20-string contract is in
  `PlaysteadWeb.CopyContractTest` (LiveViewTest).
  """
  use PlaysteadWeb.BrowserCase, async: false

  alias PlaysteadWeb.BrowserScreens

  feature "login: the no-email helper, Locked out? link and primary CTA", %{session: session} do
    {session, _} = BrowserScreens.open(session, :login)

    assert Wallaby.Browser.text(session, css("#no-mail-helper")) ==
             "No email will ever be sent — this server never sends mail."

    assert Wallaby.Browser.text(session, css("#locked-out-link")) == "Locked out?"
    assert attr(session, css("#locked-out-link"), "href") =~ "/docs/recovery"
    assert Wallaby.Browser.text(session, css("#login_submit")) == "Log in"
  end

  feature "sudo: the re-authentication prompt", %{session: session} do
    {session, _} = BrowserScreens.open(session, :sudo)

    assert Wallaby.Browser.text(session, css("h1")) ==
             "Confirm it's you — enter your password to continue."
  end

  feature "devices: the pairing evidence micro-copy, Approve / Deny, and the deny confirmation",
          %{
            session: session
          } do
    {session, %{pending: pending}} = BrowserScreens.open(session, :devices)

    assert Wallaby.Browser.text(session, css("#pairing-request-#{pending.id}-hint")) ==
             "Only approve if this code matches the one on your Mac's screen."

    assert Wallaby.Browser.text(session, css("#approve-#{pending.id}")) == "Approve"
    assert Wallaby.Browser.text(session, css("#deny-#{pending.id}")) == "Deny"

    assert attr(session, css("#deny-#{pending.id}"), "data-confirm") ==
             "Deny this pairing request? The Mac will need to request pairing again."

    # Approve is never destructive-red; Deny is never accent-blue.
    refute same_color?(
             computed_style(session, "#approve-#{pending.id}", "backgroundColor"),
             "#EF4444"
           )

    refute same_color?(computed_style(session, "#deny-#{pending.id}", "color"), "#38BDF8")
    assert same_color?(computed_style(session, "#deny-#{pending.id}", "color"), "#EF4444")
  end

  feature "devices: the revoke confirmation names the device and states the consequence", %{
    session: session
  } do
    {session, %{active: active}} = BrowserScreens.open(session, :devices)

    assert attr(session, css("#device-#{active.id}-revoke"), "data-confirm") ==
             "Revoke Studio Mac? This device will lose access immediately. Its downloaded games and saves stay on it and remain playable offline — only syncing with this server stops."
  end

  feature "setup: intermediate CTAs say Continue, the last says Finish setup, and the backup nudge is one line of copy",
          %{
            session: session
          } do
    {session, %{token: token}} = BrowserScreens.open(session, :setup)
    assert Wallaby.Browser.text(session, css("#setup_token_submit")) == "Continue"

    session =
      session
      |> fill_in(css("#setup_token"), with: token)
      |> click(css("#setup_token_submit"))
      |> assert_has(css("#owner_submit", text: "Continue"))
      |> fill_in(css("#owner_email"), with: "owner@example.com")
      |> fill_in(css("#owner_password"), with: "a very long password")
      |> fill_in(css("#owner_password_confirmation"), with: "a very long password")
      |> click(css("#owner_submit"))
      |> assert_has(css("#continue_to_readiness", text: "Continue"))
      |> click(css("#continue_to_readiness"))
      |> assert_has(css("#finish_setup", text: "Finish setup"))

    assert Wallaby.Browser.text(session, css("#backup-nudge")) ==
             "Your library lives in this server's storage. Set up a backup destination soon — a copy on the same disk is not a backup."
  end
end
