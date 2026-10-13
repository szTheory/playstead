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
    try do
      run_setup_wizard_journey(session)
    after
      mark_reliability_journey_complete()
    end
  end

  defp run_setup_wizard_journey(session) do
    token = BrowserScreens.minted_token()

    session =
      session
      |> visit_live("/setup")
      |> await_reliability_probes()
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

  defp await_reliability_probes(session) do
    case System.get_env("PLAYSTEAD_RELIABILITY_ROOT") do
      nil ->
        session

      root ->
        owner = System.fetch_env!("PLAYSTEAD_RELIABILITY_OWNER")
        prefix = "/private/tmp/playstead-setup-wizard-reliability."

        unless String.starts_with?(Path.expand(root), prefix) do
          flunk("reliability run root is outside private temporary storage")
        end

        verify_reliability_root!(root, owner)
        journey_marker = Path.join(root, "journey-started")
        write_reliability_marker!(journey_marker, owner)

        wait_until(
          session,
          fn _ -> valid_reliability_marker?(Path.join(root, "probes-ready"), root, owner) end,
          "the four bounded read-only health probes",
          800
        )
    end
  end

  defp verify_reliability_root!(root, owner) do
    with {:ok, %{type: :directory, mode: root_mode}} <- File.lstat(root),
         {:ok, %{type: :regular, mode: owner_mode}} <- File.lstat(Path.join(root, ".owner")),
         true <- Bitwise.band(root_mode, 0o077) == 0,
         true <- Bitwise.band(owner_mode, 0o077) == 0,
         {:ok, ^owner} <- File.read(Path.join(root, ".owner")) do
      :ok
    else
      _ -> flunk("reliability run root ownership check failed")
    end
  end

  defp write_reliability_marker!(path, owner) do
    temporary = path <> ".tmp"
    {:ok, file} = File.open(temporary, [:write, :exclusive])
    :ok = IO.binwrite(file, owner)
    :ok = File.close(file)
    :ok = File.chmod(temporary, 0o600)
    :ok = File.rename(temporary, path)
  end

  defp mark_reliability_journey_complete do
    case System.get_env("PLAYSTEAD_RELIABILITY_ROOT") do
      nil ->
        :ok

      root ->
        owner = System.fetch_env!("PLAYSTEAD_RELIABILITY_OWNER")
        verify_reliability_root!(root, owner)
        journey_marker = Path.join(root, "journey-started")

        if valid_reliability_marker?(journey_marker, root, owner) do
          write_reliability_marker!(Path.join(root, "journey-complete"), owner)
          await_reliability_marker!(Path.join(root, "probes-stopped"), root, owner)
        end
    end
  end

  defp await_reliability_marker!(path, root, owner) do
    deadline = System.monotonic_time(:millisecond) + 30_000
    await_reliability_marker(path, root, owner, deadline)
  end

  defp await_reliability_marker(path, root, owner, deadline) do
    cond do
      valid_reliability_marker?(path, root, owner) ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("timed out waiting for reliability probes to stop")

      true ->
        # This short, bounded file handshake keeps the test server alive until
        # the runner has reaped its probes. It does not synchronize UI state.
        :timer.sleep(10)
        await_reliability_marker(path, root, owner, deadline)
    end
  end

  defp valid_reliability_marker?(path, root, owner) do
    verify_reliability_root!(root, owner)

    case File.lstat(path) do
      {:ok, %{type: :regular, mode: mode}} ->
        Bitwise.band(mode, 0o077) == 0 and File.read!(path) == owner

      _ ->
        false
    end
  end
end
