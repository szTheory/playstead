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
