import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :playstead, Playstead.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "playstead_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# The test endpoint runs a real HTTP server so the Wallaby browser suite
# (test/playstead_web/browser/) can drive headless Chrome against it. The
# port is offset by MIX_TEST_PARTITION so partitioned CI runs don't collide.
config :playstead, PlaysteadWeb.Endpoint,
  http: [
    ip: {127, 0, 0, 1},
    port: 4002 + String.to_integer(System.get_env("MIX_TEST_PARTITION", "0"))
  ],
  secret_key_base: "64CRN9kJz6+vSE1TtjV3XAwR1vnhNP8+wQcreYNJSKSHIJu9/MWBKAd4LbntFdrL",
  server: true

# Browser requests carry the Ecto sandbox owner in their User-Agent so
# `Phoenix.Ecto.SQL.Sandbox` (endpoint plug + LiveView on_mount hook) can
# route them onto the test's own connection. Compile-time gated in
# `PlaysteadWeb.Endpoint` / `PlaysteadWeb.SandboxHook` — never in prod.
config :playstead, :sql_sandbox, true

config :wallaby,
  otp_app: :playstead,
  driver: Wallaby.Chrome,
  screenshot_on_failure: true,
  screenshot_dir: "tmp/wallaby_screenshots",
  max_wait_time: 5_000,
  # JS exceptions fail the test; routine console output (LiveView debug
  # diffs on localhost) is not echoed into the ExUnit log.
  js_errors: true,
  js_logger: nil,
  chromedriver:
    [headless: true] ++
      (case System.get_env("WALLABY_CHROME_BINARY") do
         nil -> []
         binary -> [binary: binary]
       end)

# Sandboxed tests run inside one already-started transaction, where Postgres
# refuses SET TRANSACTION. Playstead.Sync.SnapshotConcurrencyTest re-enables
# it for its own real transactions. See Playstead.Sync.Snapshot's moduledoc.
config :playstead, Playstead.Sync.Snapshot, set_isolation: false

# Every Wallaby request comes from 127.0.0.1; don't let the wizard's per-IP
# defense-in-depth limits throttle the browser suite itself.
config :playstead, PlaysteadWeb.SetupLive,
  verify_token_limit: 100_000,
  create_owner_limit: 100_000

# Oban jobs run manually in tests, never on a background schedule
config :playstead, Oban, testing: :manual

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# D-06: the full test suite exercises real POST /log-in traffic across
# many test files, all sharing ConnTest's default 127.0.0.1 remote_ip
# within the same 1-minute fixed window. A production-realistic limit
# here would throttle the test suite itself, not the feature under test.
# PlaysteadWeb.Plugs.Throttle's own test file passes small explicit
# per-call limits to exercise the actual fixed-limit behavior directly.
config :playstead, PlaysteadWeb.Plugs.Throttle,
  per_ip_limit: 100_000,
  per_account_limit: 100_000
