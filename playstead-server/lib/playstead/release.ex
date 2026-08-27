defmodule Playstead.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.

  Also owns the three boot-time safety gates (D-15, D-17), invoked from
  `Playstead.Application.start/2` before the endpoint starts serving:

    * `assert_no_placeholder_secrets!/0` — refuse to boot with a
      placeholder `SECRET_KEY_BASE` or `POSTGRES_PASSWORD`.
    * `assert_minimum_upgradable_version!/0` — refuse to boot against a
      schema older than this release can safely migrate.
    * `migrate/0` — run pending migrations, failing loudly rather than
      entering a silent crash loop.
  """
  @app :playstead

  # The exact placeholder strings written into .env.example. Kept in
  # sync deliberately — .env.example documents these as "replace me"
  # values, and this module refuses to boot with either of them.
  @placeholder_secret_key_base "REPLACE_WITH_GENERATED_SECRET_KEY_BASE"
  @placeholder_postgres_password "REPLACE_WITH_STRONG_PASSWORD"

  # This is the phase's initial migration version. Set from day one so
  # the minimum-upgradable-version gate is live and testable rather
  # than added retroactively (D-17). Raise this only when a later
  # release intentionally drops support for upgrading from schemas
  # older than a given migration.
  @minimum_upgradable_version 20_260_827_155_420

  def migrate do
    load_app()

    for repo <- repos() do
      case Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true)) do
        {:ok, _migrated, _apps} ->
          :ok

        {:error, reason} ->
          IO.puts(:stderr, """
          ============================================================
          Migration failed for #{inspect(repo)}:

          #{inspect(reason)}

          Refusing to start with an incompletely migrated schema.
          ============================================================
          """)

          raise "migration failed for #{inspect(repo)}: #{inspect(reason)}"
      end
    end
  rescue
    e in [Ecto.MigrationError] ->
      IO.puts(:stderr, """
      ============================================================
      Migration failed: #{Exception.message(e)}

      Refusing to start with an incompletely migrated schema.
      ============================================================
      """)

      reraise e, __STACKTRACE__
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Email-free credential recovery, path (a) (D-05a). Runnable as:

      docker compose exec app bin/playstead eval 'Playstead.Release.reset_owner_password()'

  Mints a single-use, short-expiry `:password_reset` token (hash stored;
  the plaintext token is embedded once in the printed URL and never
  persisted), deletes every existing session token for the owner so a
  stolen session cannot survive alongside the reset, and records a
  `password_reset_issued` audit entry — all inside one transaction. Prints
  the full reset URL to stdout exactly once. Host access is the
  documented root of trust for both bootstrap and recovery — the same
  principle that governs the setup token.
  """
  @spec reset_owner_password() :: :ok | :error
  def reset_owner_password do
    load_app()

    {:ok, result, _apps} =
      Ecto.Migrator.with_repo(Playstead.Repo, fn _repo -> do_reset_owner_password() end)

    case result do
      {:ok, url} ->
        IO.puts("""
        ============================================================
        Password reset link (single-use, expires in 1 hour):

        #{url}

        This also ended every existing session for the owner account.
        ============================================================
        """)

        :ok

      :no_owner ->
        IO.puts(:stderr, "No owner account exists yet — run the setup wizard first.")
        :error
    end
  end

  defp do_reset_owner_password do
    case Playstead.Accounts.get_owner() do
      nil ->
        :no_owner

      user ->
        {url_token, user_token} =
          Playstead.Accounts.UserToken.build_hashed_token(user, "password_reset")

        {:ok, :done} =
          Playstead.Repo.transact(fn ->
            Playstead.Repo.insert!(user_token)
            Playstead.Accounts.delete_all_sessions(Playstead.Accounts.Scope.for_user(user))
            Playstead.AuditLog.record(user.id, :password_reset_issued, %{})
            {:ok, :done}
          end)

        {:ok, reset_url(url_token)}
    end
  end

  defp reset_url(token) do
    endpoint_conf = Application.get_env(@app, PlaysteadWeb.Endpoint, [])
    url_conf = Keyword.get(endpoint_conf, :url, [])
    scheme = Keyword.get(url_conf, :scheme, "https")
    host = Keyword.get(url_conf, :host, "localhost")
    port = Keyword.get(url_conf, :port)

    port_suffix =
      case {scheme, port} do
        {_, nil} -> ""
        {"https", 443} -> ""
        {"http", 80} -> ""
        {_, p} -> ":#{p}"
      end

    "#{scheme}://#{host}#{port_suffix}/reset/#{token}"
  end

  @doc """
  Refuses to boot when `SECRET_KEY_BASE` or `POSTGRES_PASSWORD` still
  hold their `.env.example` placeholder values (D-15). Raises with an
  actionable message naming the variable and a one-line generator
  command; never substitutes a default.
  """
  @spec assert_no_placeholder_secrets!() :: :ok
  def assert_no_placeholder_secrets! do
    check_placeholder!(
      "SECRET_KEY_BASE",
      System.get_env("SECRET_KEY_BASE"),
      @placeholder_secret_key_base,
      "mix phx.gen.secret"
    )

    check_placeholder!(
      "POSTGRES_PASSWORD",
      System.get_env("POSTGRES_PASSWORD"),
      @placeholder_postgres_password,
      "openssl rand -base64 32"
    )

    :ok
  end

  defp check_placeholder!(_var_name, nil, _placeholder, _generator), do: :ok

  defp check_placeholder!(var_name, value, placeholder, generator) do
    if value == placeholder do
      raise """
      #{var_name} is still set to its .env.example placeholder value.

      Generate a real value with:

          #{generator}

      Then set #{var_name} in your .env file and restart.
      """
    else
      :ok
    end
  end

  @doc """
  Refuses to boot when the highest applied migration version in the
  database is older than #{@minimum_upgradable_version}, naming the
  intermediate release the operator must run first (D-17 — Immich's
  "no half-migrating ancient schemas" lesson). A fresh database with
  no applied migrations is not gated — this checks upgrades, not
  first-time installs.
  """
  @spec assert_minimum_upgradable_version!() :: :ok
  def assert_minimum_upgradable_version! do
    load_app()

    for repo <- repos() do
      {:ok, versions, _apps} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.migrated_versions/1)

      case versions do
        [] ->
          :ok

        applied ->
          highest = Enum.max(applied)

          if highest < @minimum_upgradable_version do
            raise """
            This database's schema (highest applied migration #{highest}) is older
            than the minimum this release can upgrade from (#{@minimum_upgradable_version}).

            Run an intermediate release first — one built from a version at or
            after migration #{@minimum_upgradable_version} — then upgrade to this
            release.
            """
          end
      end
    end

    :ok
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
