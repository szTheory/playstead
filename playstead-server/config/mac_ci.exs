import Config

# A real, standalone native server for the hosted Mac acceptance spine.
# It deliberately does not inherit the test transaction owner, endpoint
# isolation plug, or Oban's manual test engine: XCUITest is an external client
# and must observe ordinary transaction and process ownership.
native_root = System.get_env("PLAYSTEAD_MAC_CI_ROOT", Path.join(System.tmp_dir!(), "playstead-mac-ci"))
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

config :playstead, Playstead.Repo,
  url: database_url,
  pool_size: 10,
  queue_target: 1_000,
  queue_interval: 5_000

config :playstead, PlaysteadWeb.Endpoint,
  url: [host: "127.0.0.1", port: port, scheme: "http"],
  http: [ip: {127, 0, 0, 1}, port: port],
  secret_key_base: "wave0-native-phoenix-only-not-a-production-secret-key-base-0000000000000000",
  server: true,
  check_origin: false

config :playstead, :sql_sandbox, false
config :playstead, :trust_proxy_headers, false
config :playstead, Playstead.Sync.Snapshot, set_isolation: true
config :bcrypt_elixir, :log_rounds, 1
config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
