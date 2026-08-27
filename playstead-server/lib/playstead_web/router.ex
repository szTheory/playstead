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

    get "/requests/:id", PairingController, :show
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
    post "/reset/:token", ResetPasswordController, :update
    get "/docs/recovery", RecoveryDocsController, :show
  end
end
