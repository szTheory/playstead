defmodule PlaysteadWeb.Browser.StatesTest do
  @moduledoc """
  01-UI-SPEC § UI Considerations — the element × state matrix (E1 setup
  wizard, E2 login, E3 approval queue, E4 device list, E5 sessions, E6 sudo,
  E7 generic error surface) × {empty, error, partial, overflow,
  zero-one-many, long-text}, rendered in a real browser, including the three
  🧪 backstop cells the spec flagged as "human_needed unless evidence":
  recovery-code grid overflow, the sudo long validation message, and the
  generic error surface with a very long message. The `loading` column is
  an attribute contract and lives in `PlaysteadWeb.LoadingContractTest`.
  """
  use PlaysteadWeb.BrowserCase, async: false

  alias Playstead.{Accounts, Pairing}
  alias PlaysteadWeb.BrowserScreens

  # --- E1 setup wizard ---------------------------------------------------

  feature "E1 error: a wrong setup token renders the inline error and keeps the wizard on step 1",
          %{
            session: session
          } do
    {session, _} = BrowserScreens.open(session, :setup)

    session
    |> fill_in(css("#setup_token"), with: "definitely-not-the-token")
    |> click(css("#setup_token_submit"))
    |> assert_has(
      css("#setup_token_error", text: "This token is invalid or has already been used.")
    )
    |> assert_has(css("#setup-step-1"))
    |> assert_no_clip("#setup_token_error")
  end

  feature "E1 error: a too-short password renders the field error inline on step 2", %{
    session: session
  } do
    {session, %{token: token}} = BrowserScreens.open(session, :setup)

    session
    |> fill_in(css("#setup_token"), with: token)
    |> click(css("#setup_token_submit"))
    |> assert_has(css("#setup-step-2"))
    |> fill_in(css("#owner_email"), with: "owner@example.com")
    |> fill_in(css("#owner_password"), with: "short")
    |> fill_in(css("#owner_password_confirmation"), with: "short")
    |> click(css("#owner_submit"))
    |> assert_has(css("#setup-step-2 [data-role=error]"))
  end

  feature "E1 backstop: the recovery-code grid never clips its codes, and the backup nudge wraps",
          %{
            session: session
          } do
    {session, %{token: token}} = BrowserScreens.open(session, :setup)
    session = complete_credentials(session, token)

    assert_has(session, css("#recovery-codes [data-role=code]", count: 10))

    # Current format: every code fits its cell with no ellipsis.
    for i <- 0..9, do: assert_fits(session, "#recovery-code-#{i}")

    # Evidence for the "code count/format changes" caveat: the grid holds
    # codes up to 12 characters at the contract's 20px/0.04em without
    # clipping — the point at which a format change would need a layout
    # change is documented by this bound, not guessed.
    js(
      session,
      "for (const el of document.querySelectorAll('#recovery-codes [data-role=code]')) el.textContent = 'ABCDEF-GHIJK';"
    )

    for i <- 0..9, do: assert_fits(session, "#recovery-code-#{i}")
    assert_no_clip(session, "#recovery-codes")

    session
    |> click(css("#continue_to_readiness"))
    |> assert_has(css("#readiness [data-state]", count: 3))
    |> assert_no_clip("#backup-nudge")

    nudge = bbox(session, "#backup-nudge")
    line_height = px(computed_style(session, "#backup-nudge", "lineHeight"))
    assert nudge["h"] > line_height * 1.5, "the backup nudge should wrap onto more than one line"
  end

  feature "E1 zero-one-many: readiness always has exactly three rows, each :ok or :warning", %{
    session: session
  } do
    {session, %{token: token}} = BrowserScreens.open(session, :setup)

    session
    |> complete_credentials(token)
    |> click(css("#continue_to_readiness"))
    |> assert_has(css("#readiness [data-state]", count: 3))
    |> assert_gone(css("#readiness-loading"))

    states =
      js(
        session,
        "return Array.from(document.querySelectorAll('#readiness [data-state]')).map(e => [e.id, e.dataset.state]);"
      )

    assert Enum.map(states, &hd/1) == [
             "readiness-database",
             "readiness-volumes",
             "readiness-https"
           ]

    assert Enum.all?(states, fn [_, s] -> s in ["ok", "warning"] end)
    refute_has(session, css("#finish_setup[disabled]"))
  end

  # --- E2 login ------------------------------------------------------------

  feature "E2 error: a wrong password shows the exact copy, keeps the email, and wraps cleanly",
          %{
            session: session
          } do
    user = owner_fixture()

    session
    |> log_in_via_browser(user.email, "not the password")
    |> assert_has(
      css("#login_error",
        text:
          "That password didn't match. Try again, or use the recovery option below if you're locked out."
      )
    )
    |> assert_no_clip("#login_error")

    assert attr(session, css("#login_form_email"), "value") == user.email
  end

  # --- E3 pairing approval queue ------------------------------------------

  feature "E3 empty: the queue empty state shows the contract copy and no Approve control", %{
    session: session
  } do
    user = owner_fixture()

    session
    |> log_in_via_cookie(user)
    |> visit_live("/devices")
    |> assert_has(css("#requests-empty", text: "No pairing requests"))
    |> assert_has(
      css("#requests-empty",
        text:
          "When a Mac requests to pair, its code will appear here for you to approve. Nothing to do right now."
      )
    )
    |> assert_gone(css("[id^=approve-]"))
    |> assert_has(css("#devices-empty", text: "No devices paired yet"))
    |> assert_has(
      css("#devices-empty",
        text: "Pair a Mac from its Settings screen, then approve the request here."
      )
    )
  end

  feature "E3 error: an expired request is inert, and approving one that expired mid-flight is refused",
          %{
            session: session
          } do
    {session, %{pending: pending, expired: expired}} = BrowserScreens.open(session, :devices)

    session
    |> assert_has(css("#pairing-request-#{expired.id}-expired", text: "Expired"))
    |> assert_has(
      css("#pairing-request-#{expired.id}-expired-copy",
        text: "This request expired before it was approved. Ask the Mac to request pairing again."
      )
    )
    |> assert_gone(css("#approve-#{expired.id}"))
    |> assert_gone(css("#deny-#{expired.id}"))

    # The owner is looking at a live card; it expires server-side before the click lands.
    BrowserScreens.expire!(pending)

    session
    |> click(css("#approve-#{pending.id}"))
    |> assert_has(
      css("#flash-error",
        text: "This request expired before it was approved. Ask the Mac to request pairing again."
      )
    )
    |> assert_has(css("#pairing-request-#{pending.id}-expired"))

    assert {:ok, %{status: status}} = Pairing.get_request_status(pending.id)
    assert status != "approved"
  end

  feature "E3 partial: a request that reported no claims shows muted 'Not reported' fields", %{
    session: session
  } do
    user = owner_fixture()

    {request, _} =
      pairing_request_fixture(%{"device_name" => nil, "platform" => nil, "app_version" => nil})

    session
    |> log_in_via_cookie(user)
    |> visit_live("/devices")
    |> assert_has(css("#pairing-request-#{request.id}-claimed-name", text: "Not reported"))
    |> assert_has(css("#pairing-request-#{request.id}-claimed-platform", text: "Not reported"))
    |> assert_has(css("#pairing-request-#{request.id}-claimed-app-version", text: "Not reported"))

    assert same_color?(
             computed_style(session, "#pairing-request-#{request.id}-claimed-name", "color"),
             "#94A3B8"
           )

    assert same_color?(
             computed_style(session, "#pairing-request-#{request.id}-requesting-from", "color"),
             "#F1F5F9"
           )
  end

  feature "E3 overflow/long-text: a long claimed name truncates with an ellipsis and never touches the display code",
          %{
            session: session
          } do
    user = owner_fixture()
    long = String.duplicate("Very Long MacBook Name ", 4) |> String.trim()
    {request, _} = pairing_request_fixture(%{"device_name" => long})

    session
    |> log_in_via_cookie(user)
    |> visit_live("/devices")
    |> assert_has(css("#pairing-request-#{request.id}-claimed-name"))

    sel = "#pairing-request-#{request.id}-claimed-name"
    assert computed_style(session, sel, "textOverflow") == "ellipsis"

    assert js(
             session,
             "const e = document.querySelector(arguments[0]); return e.scrollWidth > e.clientWidth;",
             [sel]
           )

    assert attr(session, css(sel), "title") == long

    code = bbox(session, "#display-code-#{request.id}")
    claimed = bbox(session, sel)

    assert claimed["y"] >= code["y"] + code["h"],
           "claimed name must sit below the display code, never beside it"

    assert_no_horizontal_scroll(session)
  end

  feature "E3 zero-one-many: at the cap the queue-full notice shows and the 21st request evicts the oldest",
          %{
            session: session
          } do
    user = owner_fixture()
    cap = Pairing.pending_queue_cap()

    requests =
      for i <- 1..cap, do: elem(pairing_request_fixture(%{"device_name" => "Mac #{i}"}), 0)

    oldest = hd(requests)

    session =
      session
      |> log_in_via_cookie(user)
      |> visit_live("/devices")
      |> assert_has(
        css("#queue-full-notice",
          text: "#{cap} pending — queue full — oldest request will be evicted."
        )
      )
      |> assert_has(css("[id^=display-code-]", count: cap))

    {newest, _} = pairing_request_fixture(%{"device_name" => "Mac #{cap + 1}"})

    session
    |> visit_live("/devices")
    |> assert_has(css("#display-code-#{newest.id}"))
    |> assert_gone(css("#display-code-#{oldest.id}"))
    |> assert_has(css("[id^=display-code-]", count: cap))
  end

  # --- E4 device list ---------------------------------------------------------

  feature "E4 partial + zero-one-many: never-seen devices say 'Never', tombstones sit below with no controls",
          %{
            session: session
          } do
    {session, %{active: active, never_seen: never_seen, revoked: revoked}} =
      BrowserScreens.open(session, :devices)

    session
    |> assert_has(css("#device-#{never_seen.id}-last-seen", text: "Never"))
    |> assert_has(css("#device-#{never_seen.id}-claims", text: "Not reported"))
    |> assert_has(css("#active-devices #device-#{active.id}"))
    |> assert_has(css("#active-devices #device-#{never_seen.id}"))
    |> assert_has(css("#revoked-devices #device-#{revoked.id}"))
    |> assert_has(css("#device-#{revoked.id}-revoked-at", text: "Revoked"))
    |> assert_gone(css("#device-#{revoked.id}-revoke"))
    |> assert_gone(css("#device-#{revoked.id}-rename"))
    |> assert_gone(css("#device-#{revoked.id}-fingerprint"))

    # One device and many devices share the exact row shape.
    one =
      js(session, "return document.querySelector('#device-' + arguments[0]).children.length;", [
        active.id
      ])

    many =
      js(session, "return document.querySelector('#device-' + arguments[0]).children.length;", [
        never_seen.id
      ])

    assert one == many

    active_bottom = bbox(session, "#active-devices")
    revoked_top = bbox(session, "#revoked-devices")
    assert revoked_top["y"] > active_bottom["y"] + active_bottom["h"]
  end

  feature "E4 overflow: the rename field enforces the device name limit in the browser", %{
    session: session
  } do
    {session, %{active: active}} = BrowserScreens.open(session, :devices)
    max = Playstead.Pairing.Device.max_name_length()

    session
    |> click(css("#device-#{active.id}-rename"))
    |> assert_has(css("#device-#{active.id}-rename-input"))
    |> fill_in(css("#device-#{active.id}-rename-input"), with: String.duplicate("x", max + 40))

    typed = attr(session, css("#device-#{active.id}-rename-input"), "value")
    assert String.length(typed) == max
  end

  feature "E4 error: revoking without a fresh sudo confirmation redirects to /sudo with return_to",
          %{
            session: session
          } do
    user = owner_fixture()
    scope = Accounts.Scope.for_user(user)
    %{device: device} = device_fixture(scope)
    stale = DateTime.utc_now(:second) |> DateTime.add(-30, :minute)

    session
    |> log_in_via_cookie(user, token_authenticated_at: stale)
    |> visit_live("/devices")
    |> click(css("#device-#{device.id}-revoke"))
    |> assert_has(css("#sudo_form"))

    assert current_url(session) =~ "/sudo?return_to=%2Fdevices"
    assert is_nil(Playstead.Repo.reload!(device).revoked_at)
  end

  # --- E5 sessions --------------------------------------------------------------

  feature "E5: the current session is always present and unrevokable; others are labelled and revokable",
          %{
            session: session
          } do
    {session, %{other_token: other}} = BrowserScreens.open(session, :sessions)

    rows =
      js(
        session,
        "return Array.from(document.querySelectorAll('#sessions [id^=session-][data-current]')).map(e => [e.dataset.current, !!e.querySelector('[id$=-revoke]'), e.querySelector('[id$=-label]').innerText.trim()]);"
      )

    assert length(rows) == 3
    assert Enum.count(rows, &(hd(&1) == "true")) == 1

    for ["true", revokable, label] <- rows do
      refute revokable
      assert label =~ "(this device)"
    end

    for ["false", revokable, _] <- rows, do: assert(revokable)
    assert Enum.any?(rows, &match?(["false", true, "Browser session"], &1))
    assert Enum.any?(rows, &match?(["false", true, "Safari on another Mac"], &1))

    other_id = Playstead.Repo.get_by!(Accounts.UserToken, token: other).id

    assert_has(
      session,
      css("#session-#{other_id}-revoke[aria-label='Revoke Safari on another Mac']")
    )
  end

  feature "E5 long-text: a long session label truncates with the full value on hover", %{
    session: session
  } do
    user = owner_fixture()
    long = String.duplicate("Chrome on a machine with a very long hostname ", 3) |> String.trim()
    token = Accounts.generate_user_session_token(user, long)
    id = Playstead.Repo.get_by!(Accounts.UserToken, token: token).id

    session
    |> log_in_via_cookie(user, token_authenticated_at: DateTime.utc_now(:second))
    |> visit_live("/settings/sessions")
    |> assert_has(css("#session-#{id}-label"))

    sel = "#session-#{id}-label"
    assert computed_style(session, sel, "textOverflow") == "ellipsis"
    assert attr(session, css(sel), "title") == long
    assert_no_horizontal_scroll(session)
  end

  # --- E6 sudo ------------------------------------------------------------------

  feature "E6 error: a wrong password on /sudo renders the inline error", %{session: session} do
    user = owner_fixture()

    session
    |> log_in_via_cookie(user)
    |> visit_live("/sudo")
    |> fill_in(css("#sudo_form_password"), with: "wrong")
    |> click(css("#sudo_submit"))
    |> assert_has(css("#sudo_error", text: "That password didn't match."))
    |> assert_no_clip("#sudo_error")
  end

  feature "E6 backstop: a very long validation message is fully visible on the sudo card", %{
    session: session
  } do
    user = owner_fixture()
    long = String.duplicate("That password didn't match. ", 22) |> String.trim()

    session
    |> log_in_via_cookie(user, session: %{"phoenix_flash" => %{"error" => long}})
    |> visit_live("/sudo")
    |> assert_has(css("#sudo_error", text: "That password didn't match."))
    |> assert_no_clip("#sudo_error")
    |> assert_no_horizontal_scroll()

    assert Wallaby.Browser.text(session, css("#sudo_error")) == long
    card = bbox(session, "#sudo_form")
    assert card["w"] <= 1280
  end

  # --- E7 generic error / flash surface -------------------------------------

  feature "E7: a server-side failure shows the generic copy with a correlation id, and dismisses",
          %{
            session: session
          } do
    {session, %{active: active}} = BrowserScreens.open(session, :devices)

    # A rename whose device id no longer belongs to this owner (the hidden
    # id is tampered in the browser) is the console's generic-failure path.
    session =
      session
      |> click(css("#device-#{active.id}-rename"))
      |> assert_has(css("#device-#{active.id}-rename-form"))

    js(
      session,
      "document.querySelector(arguments[0] + ' input[name=device_id]').value = arguments[1]; return true;",
      ["#device-#{active.id}-rename-form", Ecto.UUID.generate()]
    )

    session
    |> click(css("#device-#{active.id}-rename-save"))
    |> assert_has(
      css("#flash-error",
        text: "Something went wrong on the server. Your data is safe — nothing was changed."
      )
    )

    assert Wallaby.Browser.text(session, css("#flash-error-message")) =~
             ~r/Correlation ID: [A-Za-z0-9_-]{8,}/

    session
    |> click(css("#flash-error button[aria-label=Dismiss]"))
    |> assert_gone(css("#flash-error"))
  end

  feature "E7 backstop: an 800-character error message wraps inside the flash without clipping",
          %{
            session: session
          } do
    user = owner_fixture()
    long = String.duplicate("remedy detail ", 57) |> String.trim()
    assert String.length(long) >= 790

    session
    |> log_in_via_cookie(user, session: %{"phoenix_flash" => %{"error" => long}})
    |> visit_live("/devices")
    |> assert_has(css("#flash-error-message"))
    |> assert_no_clip("#flash-error-message")
    |> assert_no_clip("#flash-error")
    |> assert_no_horizontal_scroll()

    assert Wallaby.Browser.text(session, css("#flash-error-message")) == long

    assert computed_style(session, "#flash-error-message", "overflowWrap") in [
             "break-word",
             "anywhere"
           ]
  end

  # --- helpers ---------------------------------------------------------------

  defp complete_credentials(session, token) do
    session
    |> fill_in(css("#setup_token"), with: token)
    |> click(css("#setup_token_submit"))
    |> assert_has(css("#setup-step-2"))
    |> fill_in(css("#owner_email"), with: "owner@example.com")
    |> fill_in(css("#owner_password"), with: "a very long password")
    |> fill_in(css("#owner_password_confirmation"), with: "a very long password")
    |> click(css("#owner_submit"))
    |> assert_has(css("#setup-step-3"))
  end

  # Unlike assert_no_clip/2 this insists the text really fits — a `truncate`
  # cell that is *actually* truncating fails.
  defp assert_fits(session, selector) do
    r =
      js(
        session,
        "const e = document.querySelector(arguments[0]); return [e.scrollWidth, e.clientWidth];",
        [selector]
      )

    [sw, cw] = r
    assert sw <= cw + 1, "#{selector} is clipped: scrollWidth=#{sw} clientWidth=#{cw}"
    session
  end
end
