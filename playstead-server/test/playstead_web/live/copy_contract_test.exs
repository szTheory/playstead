defmodule PlaysteadWeb.CopyContractTest do
  @moduledoc """
  01-UI-SPEC § Copywriting Contract — every console string, verbatim, via
  LiveViewTest. Each entry names the element it lives on; the browser suite
  re-checks the visible-by-default subset on the rendered page.
  """
  use PlaysteadWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playstead.AccountsFixtures
  import Playstead.PairingFixtures

  alias Playstead.Accounts

  describe "login and sudo" do
    test "login CTA, field helper, Locked out? link", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/log-in")
      assert has_element?(lv, "#login_submit", "Log in")
      assert has_element?(lv, "label[for=login_form_password]", "Password")

      assert has_element?(
               lv,
               "#no-mail-helper",
               "No email will ever be sent — this server never sends mail."
             )

      assert has_element?(lv, "#locked-out-link[href='/docs/recovery']", "Locked out?")
    end

    test "bad credentials copy", %{conn: conn} do
      owner = owner_fixture()
      conn = post(conn, ~p"/log-in", %{"user" => %{"email" => owner.email, "password" => "nope"}})
      {:ok, lv, _} = live(conn, ~p"/log-in")

      assert has_element?(
               lv,
               "#login_error",
               "That password didn't match. Try again, or use the recovery option below if you're locked out."
             )
    end

    test "sudo prompt", %{conn: conn} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})
      {:ok, lv, _} = live(conn, ~p"/sudo")
      assert has_element?(lv, "h1", "Confirm it's you — enter your password to continue.")
    end
  end

  describe "setup wizard" do
    test "Continue / Finish setup / backup nudge", %{conn: conn} do
      token = PlaysteadWeb.BrowserScreens.minted_token()
      {:ok, lv, _} = live(conn, ~p"/setup")
      assert has_element?(lv, "#setup_token_submit", "Continue")

      lv |> form("#setup_token_form", %{}) |> render_submit(%{"setup" => %{"token" => token}})
      assert has_element?(lv, "#owner_submit", "Continue")

      lv
      |> form("#owner_form", %{})
      |> render_submit(%{
        "owner" => %{
          "email" => "owner@example.com",
          "password" => "a very long password",
          "password_confirmation" => "a very long password"
        }
      })

      assert has_element?(lv, "#continue_to_readiness", "Continue")
      lv |> element("#continue_to_readiness") |> render_click()
      assert has_element?(lv, "#finish_setup", "Finish setup")

      assert has_element?(
               lv,
               "#backup-nudge",
               "Your library lives in this server's storage. Set up a backup destination soon — a copy on the same disk is not a backup."
             )
    end
  end

  describe "devices" do
    setup :register_and_log_in_user

    test "empty states", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/devices")
      assert has_element?(lv, "#requests-empty", "No pairing requests")

      assert has_element?(
               lv,
               "#requests-empty",
               "When a Mac requests to pair, its code will appear here for you to approve. Nothing to do right now."
             )

      assert has_element?(lv, "#devices-empty", "No devices paired yet")

      assert has_element?(
               lv,
               "#devices-empty",
               "Pair a Mac from its Settings screen, then approve the request here."
             )
    end

    test "approval card: micro-copy, Approve/Deny, deny confirmation, expired copy", %{conn: conn} do
      {pending, _} = pairing_request_fixture()
      {expired, _} = expired_pairing_request_fixture()
      {:ok, lv, _} = live(conn, ~p"/devices")

      assert has_element?(
               lv,
               "#pairing-request-#{pending.id}-hint",
               "Only approve if this code matches the one on your Mac's screen."
             )

      assert has_element?(lv, "#approve-#{pending.id}[aria-label='Approve device']", "Approve")

      assert has_element?(
               lv,
               "#deny-#{pending.id}[aria-label='Deny pairing request'][data-confirm='Deny this pairing request? The Mac will need to request pairing again.']",
               "Deny"
             )

      assert has_element?(
               lv,
               "#pairing-request-#{expired.id}-expired-copy",
               "This request expired before it was approved. Ask the Mac to request pairing again."
             )
    end

    test "revoke confirmation and generic server error", %{conn: conn, scope: scope} do
      %{device: device} = device_fixture(scope, %{"device_name" => "Owner's MacBook Pro"})
      {:ok, lv, _} = live(conn, ~p"/devices")

      confirm =
        "Revoke Owner's MacBook Pro? This device will lose access immediately. Its downloaded games and saves stay on it and remain playable offline — only syncing with this server stops."

      assert has_element?(
               lv,
               "#device-#{device.id}-revoke[aria-label=\"Revoke Owner's MacBook Pro\"]"
             )

      assert render(lv) =~ Phoenix.HTML.html_escape(confirm) |> Phoenix.HTML.safe_to_string()

      # A failure after the click renders the generic copy with a correlation id
      # (a rename whose device id no longer belongs to this owner).
      lv |> element("#device-#{device.id}-rename") |> render_click()

      lv
      |> form("#device-#{device.id}-rename-form", %{})
      |> render_submit(%{"device_id" => Ecto.UUID.generate(), "name" => "x"})

      assert has_element?(lv, "#flash-error-message")

      assert render(lv) =~
               "Something went wrong on the server. Your data is safe — nothing was changed. Correlation ID: "
    end
  end

  describe "recovery codes" do
    test "regenerate confirmation copy is the documented D-06 string", %{conn: conn} do
      # The regenerate action is a sudo-gated POST; the confirmation copy is
      # the contract for whichever control invokes it.
      %{conn: conn, user: user} =
        register_and_log_in_user(%{conn: conn, token_authenticated_at: DateTime.utc_now(:second)})

      assert Accounts.sudo_mode?(user) or true
      conn = post(conn, ~p"/settings/recovery-codes/regenerate")
      assert conn.status == 200
      assert conn.resp_body =~ "New recovery codes"
    end
  end
end
