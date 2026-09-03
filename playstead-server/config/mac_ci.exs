import Config

# WARNING: this file must never be reused as a starting point for a config
# that binds beyond loopback or persists beyond a single CI job. It is
# deliberately loopback-only (`ip: {127, 0, 0, 1}`) and its Postgres cluster
# is ephemeral and torn down every run — the `--auth=trust` Postgres
# invocation in `scripts/ci/run-mac-verification.sh` and the generated
# `secret_key_base` below are only "no real secret to protect" in that exact
# context. Copy-pasting either pattern into a longer-lived or
# externally-reachable environment would be a real security regression.
#
# A real, standalone native server for the hosted Mac acceptance spine.
# It deliberately does not inherit the test transaction owner, endpoint
# isolation plug, or Oban's manual test engine: XCUITest is an external client
# and must observe ordinary transaction and process ownership.
native_root =
  System.get_env("PLAYSTEAD_MAC_CI_ROOT", Path.join(System.tmp_dir!(), "playstead-mac-ci"))

System.put_env("PLAYSTEAD_INBOX_PATH", Path.join(native_root, "inbox"))
System.put_env("PLAYSTEAD_BLOB_PATH", Path.join(native_root, "blobs"))
System.put_env("PLAYSTEAD_EXPORT_PATH", Path.join(native_root, "exports"))
System.put_env("PLAYSTEAD_MAX_UPLOAD_BYTES", "1048576")
System.put_env("PLAYSTEAD_MAX_BROWSER_UPLOAD_BYTES", "1048576")

database_url =
  System.get_env(
    "MAC_CI_DATABASE_URL",
    "ecto://#{System.get_env("USER", "postgres")}@127.0.0.1:55432/playstead_mac_ci"
  )

port = String.to_integer(System.get_env("PORT", "4010"))

# Generated at boot rather than committed as a literal: this process is
# single-run and ephemeral (the whole native root is discarded at the end
# of the CI job), so there is no need for the value to be stable across
# boots. An env var override is honored first for callers that need a
# fixed value within one hosted run (e.g. multiple cooperating processes).
secret_key_base =
  System.get_env("PLAYSTEAD_MAC_CI_SECRET_KEY_BASE") ||
    :crypto.strong_rand_bytes(48) |> Base.encode64()

config :playstead, Playstead.Repo,
  url: database_url,
  pool_size: 10,
  queue_target: 1_000,
  queue_interval: 5_000

config :playstead, PlaysteadWeb.Endpoint,
  url: [host: "127.0.0.1", port: port, scheme: "http"],
  http: [ip: {127, 0, 0, 1}, port: port],
  secret_key_base: secret_key_base,
  # The long-lived Phoenix process owns the loopback listener. Fixture Mix
  # tasks still start Repo/domain services, but must not contend for the port.
  server: System.get_env("PLAYSTEAD_MAC_CI_TASK") != "1",
  check_origin: false

config :playstead, :sql_sandbox, false
config :playstead, :trust_proxy_headers, false
config :playstead, Playstead.Sync.Snapshot, set_isolation: true
config :bcrypt_elixir, :log_rounds, 1
# Request-path logs remain in the run-owned native root and are never attached.
# The hosted harness reduces them to exact route counters before evidence crosses
# the CI artifact boundary (D-10/D-11).
config :logger, level: :info
config :phoenix, :plug_init_mode, :runtime
