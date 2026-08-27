defmodule PlaysteadWeb.Router do
  use PlaysteadWeb, :router

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
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  get "/healthz", PlaysteadWeb.HealthController, :show

  scope "/", PlaysteadWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/setup", SetupLive
  end

  scope "/api/v1", PlaysteadWeb.Api.V1 do
    pipe_through :api

    get "/capabilities", CapabilitiesController, :show
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

  # Enable LiveDashboard and Swoosh mailbox preview in development
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
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
