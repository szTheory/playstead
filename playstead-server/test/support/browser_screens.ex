defmodule PlaysteadWeb.BrowserScreens do
  @moduledoc """
  The registry of every console screen, each with a fixture that lands a
  Wallaby session on it in a representative *populated* state.

  The UI-SPEC contract suites (palette, typography, coherence) iterate this
  list, and `PlaysteadWeb.Browser.CoherenceTest` asserts it matches the
  router — so a new console screen cannot ship without joining the walks.
  """

  import PlaysteadWeb.BrowserCase
  import Playstead.AccountsFixtures
  import Playstead.PairingFixtures
  import Playstead.TlsFixtures

  alias Playstead.{Accounts, Import, Pairing, Repo, Setup}

  @screens [
    :login,
    :recovery_login,
    :setup,
    :sudo,
    :devices,
    :sessions,
    :import,
    :import_sessions,
    :library,
    :library_detail
  ]

  def screens, do: @screens

  def path(:login), do: "/log-in"
  def path(:recovery_login), do: "/log-in/recovery"
  def path(:setup), do: "/setup"
  def path(:sudo), do: "/sudo"
  def path(:devices), do: "/devices"
  def path(:sessions), do: "/settings/sessions"
  def path(:import), do: "/import"
  def path(:import_sessions), do: "/import/sessions"
  def path(:library), do: "/library"
  def path(:library_detail), do: "/library/:id"

  @doc "Console routes that are deliberately NOT screens (no UI-SPEC element)."
  def excluded_paths,
    do: [
      "/",
      "/healthz",
      "/docs/recovery",
      "/reset/:token",
      "/settings/recovery-codes/regenerate"
    ]

  @doc "Which screens render code-role (JetBrains Mono) text when populated."
  def uses_mono?(:devices), do: true
  def uses_mono?(_), do: false

  @doc "The element that must own initial focus on each screen, or nil."
  def initial_focus(:login), do: "login_form_password"
  def initial_focus(:sudo), do: "sudo_form_password"
  def initial_focus(:recovery_login), do: "recovery_login_form_code"
  def initial_focus(:setup), do: "setup_token"
  def initial_focus(_), do: nil

  @doc "Land `session` on `screen`, populated. Returns `{session, context}`."
  def open(session, :login), do: {visit_live(session, path(:login)), %{}}
  def open(session, :recovery_login), do: {visit_live(session, path(:recovery_login)), %{}}

  def open(session, :setup) do
    token = minted_token()
    {visit_live(session, path(:setup)), %{token: token}}
  end

  def open(session, :sudo) do
    user = owner_fixture()
    session = session |> log_in_via_cookie(user) |> visit_live(path(:sudo))
    {session, %{user: user}}
  end

  def open(session, :devices) do
    user = owner_fixture()
    scope = Accounts.Scope.for_user(user)

    # Internal-CA transport so the fingerprint panel renders the mono fingerprint.
    put_env_overrides!(%{"PLAYSTEAD_CADDY_CA_PATH" => write_fixture_cert!("browser_screens")})

    {pending, _} = pairing_request_fixture(%{"device_name" => "Owner's MacBook Pro"})
    {expired, _} = expired_pairing_request_fixture(%{"device_name" => "Old request"})

    %{device: active} = device_fixture(scope, %{"device_name" => "Studio Mac"})
    %{device: never_seen} = device_fixture(scope, %{"device_name" => nil, "platform" => nil})
    %{device: revoked} = device_fixture(scope, %{"device_name" => "Retired Mac"})
    {:ok, revoked} = Pairing.revoke_device(scope, revoked.id)

    session =
      session
      |> log_in_via_cookie(user, token_authenticated_at: DateTime.utc_now(:second))
      |> visit_live(path(:devices))

    {session,
     %{
       user: user,
       scope: scope,
       pending: pending,
       expired: expired,
       active: active,
       never_seen: never_seen,
       revoked: revoked
     }}
  end

  def open(session, :import) do
    user = owner_fixture()

    session =
      session
      |> log_in_via_cookie(user, token_authenticated_at: DateTime.utc_now(:second))
      |> visit_live(path(:import))

    {session, %{user: user}}
  end

  def open(session, :import_sessions) do
    user = owner_fixture()

    root =
      Path.join(
        System.tmp_dir!(),
        "playstead-browser-screens-inbox-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    File.write!(Path.join(root, "game.bin"), :crypto.strong_rand_bytes(64))
    previous_inbox = Application.get_env(:playstead, :inbox_path)
    Application.put_env(:playstead, :inbox_path, root)

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(:playstead, :inbox_path, previous_inbox)
    end)

    {:ok, import_session} = Import.Staging.stage(user.id, root, Ecto.UUID.generate())

    session =
      session
      |> log_in_via_cookie(user, token_authenticated_at: DateTime.utc_now(:second))
      |> visit_live(path(:import_sessions))

    {session, %{user: user, import_session: import_session}}
  end

  def open(session, :library) do
    {user, _receipt} = seed_library_asset()

    session =
      session
      |> log_in_via_cookie(user, token_authenticated_at: DateTime.utc_now(:second))
      |> visit_live(path(:library))

    {session, %{user: user}}
  end

  def open(session, :library_detail) do
    {user, receipt} = seed_library_asset()

    session =
      session
      |> log_in_via_cookie(user, token_authenticated_at: DateTime.utc_now(:second))
      |> visit_live("/library/#{receipt.asset_set_id}")

    {session, %{user: user, receipt: receipt}}
  end

  def open(session, :sessions) do
    user = owner_fixture()
    other = Accounts.generate_user_session_token(user, "Safari on another Mac")
    _unlabelled = Accounts.generate_user_session_token(user, nil)

    session =
      session
      |> log_in_via_cookie(user, token_authenticated_at: DateTime.utc_now(:second))
      |> visit_live(path(:sessions))

    {session, %{user: user, other_token: other}}
  end

  defp seed_library_asset do
    user = owner_fixture()
    File.mkdir_p!(Playstead.Blobs.Store.LocalDisk.blob_path())

    bytes = :crypto.strong_rand_bytes(64)
    {:ok, status, meta} = Playstead.Blobs.put_stream([bytes], byte_size(bytes))

    {:ok, receipt} =
      Import.import_single(
        user.id,
        %{original_name: "game.bin", origin: "upload", size_bytes: byte_size(bytes)},
        {status, meta}
      )

    {user, receipt}
  end

  @doc "Mint a setup token and return the plaintext (same banner parse the wizard test uses)."
  def minted_token do
    ExUnit.CaptureIO.capture_io(fn -> Setup.mint_token() end)
    |> then(fn banner ->
      [_, token] = Regex.run(~r/wizard at \/setup\):\n\n(\S+)\n/, banner)
      token
    end)
  end

  @doc "Force a pairing request into the past so it renders/behaves as expired."
  def expire!(request) do
    expired_at = DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:second)
    Repo.update!(Ecto.Changeset.change(request, expires_at: expired_at))
  end
end
