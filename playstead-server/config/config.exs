# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :playstead, :scopes,
  user: [
    default: true,
    module: Playstead.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Playstead.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :playstead,
  ecto_repos: [Playstead.Repo],
  generators: [timestamp_type: :utc_datetime]

config :playstead, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  repo: Playstead.Repo,
  queues: [default: 10],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    # D-12: housekeeping-only sweep of stale pending pairing requests.
    # Playstead.Pairing never depends on this having run — expiry is
    # re-derived from expires_at on every read.
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", Playstead.Pairing.ExpireStaleRequestsWorker}
     ]}
  ]

# Configure the endpoint
config :playstead, PlaysteadWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PlaysteadWeb.ErrorHTML, json: PlaysteadWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Playstead.PubSub,
  live_view: [signing_salt: "/GOTZ7Yf"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  playstead: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  playstead: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# D-10: the device_code and the issued credential must never appear in
# Phoenix's own request-parameter logging, alongside the pre-existing
# password filter.
config :phoenix, :filter_parameters, {:discard, ~w(password device_code credential)}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
