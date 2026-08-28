defmodule PlaysteadWeb.Router do
  use PlaysteadWeb, :router

  import PlaysteadWeb.UserAuth

  # Wraps the router's own call/2 in a try/rescue (same mechanism as
  # Plug.ErrorHandler), so this fires before an exception can reach
  # the endpoint's default render_errors HTML/JSON rendering (D-22;
  # RESEARCH.md Pitfall 2).
  use PlaysteadWeb.Plugs.ApiProblemHandler

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PlaysteadWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug PlaysteadWeb.Plugs.ClientIp
  end

  # D-12: per-IP rate limit on pairing-request creation.
  pipeline :throttle_pairing_request do
    plug PlaysteadWeb.Plugs.Throttle, action: :pairing_request
  end

  # WR-01 (01-REVIEW.md): defense-in-depth per-IP rate limit on
  # unauthenticated redemption. device_code is a 256-bit value so brute
  # force isn't practical, but this keeps redemption consistent with the
  # throttling discipline applied everywhere else a credential is
  # checked (login, sudo, recovery). Distinct action name from
  # :pairing_request so the two buckets don't share a limit.
  pipeline :throttle_pairing_redeem do
    plug PlaysteadWeb.Plugs.Throttle, action: :pairing_redeem
  end

  # D-10: header-only device credential authentication for paired
  # clients. Plans 01-06/01-07 attach their endpoints to this pipeline.
  pipeline :device_auth do
    plug PlaysteadWeb.Plugs.DeviceAuth
  end

  # D-20a: required Idempotency-Key on mutating /api/v1 routes. Must
  # come after :device_auth — it scopes receipts per authenticated
  # device.
  pipeline :idempotency do
    plug PlaysteadWeb.Plugs.Idempotency
  end

  # D-02: header-only digest/length verification for the upload route.
  # Must run before :idempotency -- it overwrites conn.params with a
  # small synthetic map (digest + declared length) that Idempotency's
  # generic fingerprint calculation consumes unchanged.
  pipeline :repr_digest do
    plug PlaysteadWeb.Plugs.ReprDigest
  end

  # D-10: at most two simultaneous uploads per device. Must run after
  # :idempotency so a replayed request never consumes a slot.
  pipeline :upload_concurrency do
    plug PlaysteadWeb.Plugs.UploadConcurrency
  end

  # D-03: `/setup` renders only while no owner exists, and 404s
  # permanently — never a redirect — the moment one does.
  pipeline :setup_open do
    plug PlaysteadWeb.Plugs.RequireSetupOpen
  end

  pipeline :require_authenticated do
    plug :require_authenticated_user
  end

  # D-06, T-01-15: dangerous actions require a fresh sudo confirmation.
  pipeline :require_sudo do
    plug PlaysteadWeb.Plugs.SudoMode
  end

  # D-06, T-01-16: fixed per-IP/per-account throttling, distinct buckets
  # per action.
  pipeline :throttle_login do
    plug PlaysteadWeb.Plugs.Throttle, action: :login
  end

  pipeline :throttle_recovery do
    plug PlaysteadWeb.Plugs.Throttle, action: :recovery
  end

  # WR-05 (01-REVIEW.md): the reset token is high-entropy and single-use,
  # but its failure path re-renders the form with the same token still
  # valid, so an attacker holding a leaked token could otherwise try many
  # password payloads unthrottled.
  pipeline :throttle_reset do
    plug PlaysteadWeb.Plugs.Throttle, action: :reset
  end

  get "/healthz", PlaysteadWeb.HealthController, :show

  scope "/", PlaysteadWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/", PlaysteadWeb do
    pipe_through [:browser, :setup_open]

    live "/setup", SetupLive
  end

  scope "/api/v1", PlaysteadWeb.Api.V1 do
    pipe_through :api

    get "/capabilities", CapabilitiesController, :show
  end

  # D-07, D-08: unauthenticated pairing-ceremony endpoints. The client has
  # no credential yet, only its self-generated device_code.
  scope "/api/v1/device-pairing", PlaysteadWeb.Api.V1 do
    pipe_through [:api, :throttle_pairing_request]

    post "/requests", PairingController, :create
  end

  scope "/api/v1/device-pairing", PlaysteadWeb.Api.V1 do
    pipe_through :api

    # WR-01: the poll endpoint already has its own request-scoped rate
    # limit (Pairing.check_poll_rate/1), so it is deliberately not
    # wrapped in :throttle_pairing_redeem here.
    get "/requests/:id", PairingController, :show
  end

  scope "/api/v1/device-pairing", PlaysteadWeb.Api.V1 do
    pipe_through [:api, :throttle_pairing_redeem]

    # D-08: the client has no credential yet at redemption time, only
    # its self-generated device_code — this stays unauthenticated.
    post "/requests/:id/redeem", PairingController, :redeem
  end

  # D-10: authenticated device endpoints, header-only credential auth.
  scope "/api/v1/devices", PlaysteadWeb.Api.V1 do
    pipe_through [:api, :device_auth]

    get "/me", DevicesController, :me
  end

  # D-20a: mutating device endpoints additionally require an
  # Idempotency-Key.
  scope "/api/v1/devices", PlaysteadWeb.Api.V1 do
    pipe_through [:api, :device_auth, :idempotency]

    patch "/me", DevicesController, :update
    post "/me/rotate", DevicesController, :rotate
  end

  # D-19: per-session capability negotiation. Not itself mutating in the
  # idempotency-receipt sense (a repeat hello just refreshes the
  # declaration row), so it stays on the plain device_auth pipeline.
  scope "/api/v1", PlaysteadWeb.Api.V1 do
    pipe_through [:api, :device_auth]

    post "/hello", HelloController, :create
  end

  # D-01c, D-02, D-10: single-file upload, digest-verified, dedup'd
  # within the calling user, at most two concurrent uploads per device.
  scope "/api/v1/imports", PlaysteadWeb.Api.V1 do
    pipe_through [:api, :device_auth, :repr_digest, :idempotency, :upload_concurrency]

    put "/uploads/:command_id", ImportsController, :create
  end

  # D-10: read-only precheck, scoped strictly to the calling user (D-13)
  # -- not itself mutating, so no Idempotency-Key is required.
  scope "/api/v1/imports", PlaysteadWeb.Api.V1 do
    pipe_through [:api, :device_auth]

    post "/precheck", ImportsController, :precheck
  end

  # D-10: byte-serving, authorised by the caller's own source_file
  # rather than by hash alone (D-13).
  scope "/api/v1/blobs", PlaysteadWeb.Api.V1 do
    pipe_through [:api, :device_auth]

    get "/:sha256", BlobsController, :show
  end

  # D-21, PROT-05: the resumable change feed and its transactional
  # snapshot counterpart. Both are read-only — never mutating, never
  # Idempotency-Key gated — so they stay on the plain device_auth
  # pipeline.
  scope "/api/v1", PlaysteadWeb.Api.V1 do
    pipe_through [:api, :device_auth]

    get "/changes", ChangesController, :index
    get "/snapshot", SnapshotController, :show
  end

  # Dev/test-only target for the forced-500 problem+json contract test
  # (D-22). Gated at compile time so it never ships in a production
  # release.
  if Mix.env() in [:dev, :test] do
    scope "/api/v1", PlaysteadWeb.Api.V1 do
      pipe_through :api

      get "/debug/boom", DebugController, :boom
    end
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:playstead, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PlaysteadWeb.Telemetry
    end
  end

  ## Authentication routes (D-02: password-only, no magic link, no
  ## self-registration — the owner account is created exclusively through
  ## the /setup wizard in Playstead.Setup)

  scope "/", PlaysteadWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{PlaysteadWeb.UserAuth, :mount_current_scope}] do
      live "/log-in", LoginLive, :new
      live "/log-in/recovery", RecoveryLoginLive, :new
    end
  end

  scope "/", PlaysteadWeb do
    pipe_through [:browser, :throttle_login]

    post "/log-in", UserSessionController, :create
  end

  scope "/", PlaysteadWeb do
    pipe_through [:browser, :throttle_recovery]

    post "/log-in/recovery", UserSessionController, :create_via_recovery
  end

  scope "/", PlaysteadWeb do
    pipe_through [:browser]

    delete "/log-out", UserSessionController, :delete
  end

  ## Sessions and sudo mode (D-06)

  scope "/", PlaysteadWeb do
    pipe_through [:browser, :require_authenticated]

    live_session :sudo,
      on_mount: [{PlaysteadWeb.UserAuth, :mount_current_scope}] do
      live "/sudo", SudoLive, :new
    end
  end

  ## Device pairing and lifecycle console (D-07, D-09, D-11, D-13). Viewing
  ## the page never requires sudo — the approval queue and device list are
  ## routine reads — but DevicesLive itself gates revoke/rotate on a fresh
  ## sudo confirmation before executing, exactly like /settings/sessions.
  scope "/", PlaysteadWeb do
    pipe_through [:browser, :require_authenticated]

    live_session :devices,
      on_mount: [{PlaysteadWeb.UserAuth, :mount_current_scope}] do
      live "/devices", DevicesLive, :index
    end
  end

  ## Import console: the browser single-file upload surface (IMPT-01,
  ## D-01a, D-04). Requires only routine authentication — the same
  ## posture as the device list.
  scope "/", PlaysteadWeb do
    pipe_through [:browser, :require_authenticated]

    live_session :import,
      on_mount: [{PlaysteadWeb.UserAuth, :mount_current_scope}] do
      live "/import", ImportLive, :index
    end
  end

  ## Library console: asset sets and the IMPT-02 evidence detail view.
  scope "/", PlaysteadWeb do
    pipe_through [:browser, :require_authenticated]

    live_session :library,
      on_mount: [{PlaysteadWeb.UserAuth, :mount_current_scope}] do
      live "/library", LibraryLive, :index
      live "/library/:id", LibraryLive, :show
    end
  end

  scope "/", PlaysteadWeb do
    pipe_through [:browser, :require_authenticated, :require_sudo]

    live_session :require_sudo,
      on_mount: [
        {PlaysteadWeb.UserAuth, :mount_current_scope},
        {PlaysteadWeb.Plugs.SudoMode, :require_sudo}
      ] do
      live "/settings/sessions", SessionsLive, :index
    end

    post "/settings/recovery-codes/regenerate", RecoveryCodesController, :regenerate
  end

  ## Email-free credential recovery (D-05)

  scope "/", PlaysteadWeb do
    pipe_through [:browser]

    get "/reset/:token", ResetPasswordController, :edit
    get "/docs/recovery", RecoveryDocsController, :show
  end

  scope "/", PlaysteadWeb do
    pipe_through [:browser, :throttle_reset]

    post "/reset/:token", ResetPasswordController, :update
  end
end
