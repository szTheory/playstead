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

# WR-02 (01-REVIEW.md): whether PlaysteadWeb.Plugs.ClientIp is allowed to
# trust the `x-forwarded-for` header. Safety depends entirely on the
# deployment-level guarantee that only a trusted reverse proxy (Caddy, per
# D-15) can reach this app directly — see the plug's own moduledoc.
# Defaults to `true` to preserve the documented compose topology; prod
# overrides this from `PLAYSTEAD_PROXY` in config/runtime.exs, and
# `Playstead.Release.warn_if_proxy_trust_unacknowledged!/0` logs a boot-time
# warning (not a hard refusal, to avoid breaking existing deployments) when
# this is left at its default with no explicit operator acknowledgment.
config :playstead, :trust_proxy_headers, true

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
       {"* * * * *", Playstead.Pairing.ExpireStaleRequestsWorker},
       # D-20a: daily sweep of idempotency receipts past their ~90-day
       # retention horizon.
       {"@daily", Playstead.Idempotency.PruneExpiredWorker},
       # D-21: daily sweep of change-journal entries past
       # Playstead.Sync.Compaction.horizon/0.
       {"@daily", Playstead.Sync.CompactionWorker}
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
# password filter. `code` covers the recovery-code login param
# (POST /log-in/recovery) and `token` covers the password-reset/setup
# single-use tokens (GET/POST /reset/:token, setup-token verification) —
# both are single-use authentication secrets per Playstead.AuditLog's
# "metadata must never carry credential material or a plaintext token"
# discipline (see CR-01 in 01-REVIEW.md).
config :phoenix, :filter_parameters, {:discard, ~w(password device_code credential code token)}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
