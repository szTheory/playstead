defmodule Playstead.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.

  Also owns the boot-time safety gates (D-15, D-17), invoked from
  `Playstead.Application.start/2` before the endpoint starts serving:

    * `assert_no_placeholder_secrets!/0` — refuse to boot with a
      placeholder `SECRET_KEY_BASE` or `POSTGRES_PASSWORD`.
    * `assert_minimum_upgradable_version!/0` — refuse to boot against a
      schema older than this release can safely migrate.
    * `migrate/0` — run pending migrations, failing loudly rather than
      entering a silent crash loop.
    * `warn_if_proxy_trust_unacknowledged!/0` — warn (not refuse) when
      `x-forwarded-for` trust (WR-02, 01-REVIEW.md) is left at its
      default with no explicit operator acknowledgment.
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

  @backup_wait_ms 300_000

  @doc "Strict parser for the named release backup command; no arbitrary eval is accepted."
  @spec parse_backup_args([String.t()]) :: {:ok, map()} | {:error, :invalid_backup_arguments}
  def parse_backup_args(args) when is_list(args) do
    case args do
      ["--preflight", "--full"] ->
        {:ok, %{mode: :preflight, kind: :full}}

      ["--full"] ->
        {:ok, %{mode: :run, kind: :full, wait: false}}

      ["--full", "--wait"] ->
        {:ok, %{mode: :run, kind: :full, wait: true}}

      ["--incremental", "--parent-receipt", parent] when parent != "" ->
        {:ok, %{mode: :run, kind: :incremental, parent: parent, wait: false}}

      ["--incremental", "--parent-receipt", parent, "--wait"] when parent != "" ->
        {:ok, %{mode: :run, kind: :incremental, parent: parent, wait: true}}

      _ ->
        {:error, :invalid_backup_arguments}
    end
  end

  def parse_backup_args(_), do: {:error, :invalid_backup_arguments}

  @doc "Release entry point used by `bin/backup`; terminal output is allowlisted."
  @spec backup([String.t()]) :: :ok | :error
  def backup(args) do
    result = run_backup(args)
    IO.puts(if(match?({:ok, _}, result), do: :stdio, else: :stderr), render_backup_result(result))
    if match?({:ok, _}, result), do: :ok, else: :error
  end

  @doc false
  @spec run_backup([String.t()], keyword()) :: {:ok, map()} | {:error, atom()}
  def run_backup(args, opts \\ []) do
    with {:ok, parsed} <- parse_backup_args(args),
         {:ok, destination} <- destination(opts),
         :ok <- preflight(parsed, opts) do
      case parsed do
        %{mode: :preflight} -> {:ok, %{state: "preflight_passed"}}
        %{mode: :run} -> request_and_wait(parsed, destination, opts)
      end
    end
  rescue
    _ -> {:error, :backup_unavailable}
  end

  @doc false
  def render_backup_result({:ok, %{state: "preflight_passed"}}), do: "backup_preflight_passed"

  def render_backup_result({:ok, %{state: "scheduled"}}), do: "backup_scheduled"

  def render_backup_result(
        {:ok,
         %{
           kind: kind,
           receipt_id: receipt_id,
           correlation_id: correlation_id,
           verified_at: verified_at,
           independence: independence
         }}
      ) do
    [
      "backup_published",
      "kind=#{kind}",
      "receipt_id=#{receipt_id}",
      "correlation_id=#{correlation_id}",
      "state=published",
      "verified_at=#{verified_at}",
      "independence=#{independence}"
    ]
    |> Enum.join(" ")
  end

  def render_backup_result({:ok, %{independence: _}}), do: "backup_preflight_passed"

  def render_backup_result({:error, reason}), do: "backup_#{reason}"

  defp destination(opts) do
    case Keyword.get(opts, :destination, fn ->
           case System.get_env("PLAYSTEAD_BACKUP_DESTINATION") do
             value when is_binary(value) and value != "" -> {:ok, value}
             _ -> {:error, :destination_missing}
           end
         end).() do
      {:ok, value} when is_binary(value) -> {:ok, value}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :destination_missing}
    end
  end

  defp preflight(parsed, opts) do
    fun =
      Keyword.get(opts, :preflight, fn _ -> Playstead.Recovery.preflight_backup_destination() end)

    case fun.(parsed) do
      :ok -> :ok
      {:ok, _attestation} -> :ok
      {:error, _reason} = error -> error
      _ -> {:error, :backup_preflight_failed}
    end
  end

  defp request_and_wait(parsed, destination, opts) do
    attrs =
      %{destination: destination, kind: parsed.kind}
      |> maybe_parent(parsed)

    with :ok <- start_backup_runtime(opts),
         {:ok, record_id} <-
           dependency(opts, :request, &Playstead.Recovery.request_backup/1, attrs) do
      if parsed.wait do
        wait_for_published(record_id, opts)
      else
        {:ok, %{state: "scheduled"}}
      end
    else
      {:error, _} -> {:error, :backup_request_failed}
      _ -> {:error, :backup_request_failed}
    end
  end

  # A release `eval` VM must not start `:playstead`: its application callback
  # starts the HTTP endpoint, which belongs to the already-running app
  # container. Recovery work only needs the database and its Oban worker.
  defp start_backup_runtime(opts) do
    case Keyword.get(opts, :backup_runtime_start, &start_backup_runtime_services/0).() do
      :ok -> :ok
      {:ok, _started} -> :ok
      {:error, _reason} = error -> error
      _ -> {:error, :backup_runtime_start_failed}
    end
  end

  defp start_backup_runtime_services do
    if backup_runtime_running?() do
      :ok
    else
      with :ok <- ensure_runtime_application_started(:ssl),
           :ok <- ensure_runtime_application_started(:oban),
           {:ok, _pid} <-
             Supervisor.start_link(backup_runtime_children(),
               strategy: :one_for_one,
               name: Playstead.Release.BackupRuntime
             ) do
        :ok
      else
        {:error, {:already_started, _pid}} -> :ok
        {:error, _reason} = error -> error
        _ -> {:error, :backup_runtime_start_failed}
      end
    end
  end

  defp backup_runtime_running? do
    # The normal application owns both Repo and Oban, but Oban's default
    # instance is not registered under the `Oban` atom. Repo is therefore the
    # reliable shared-runtime sentinel when this command is invoked in-process.
    is_pid(Process.whereis(Playstead.Repo))
  end

  defp ensure_runtime_application_started(app) do
    case Application.ensure_all_started(app) do
      :ok -> :ok
      {:ok, _started} -> :ok
      {:error, _reason} = error -> error
      _ -> {:error, :backup_runtime_start_failed}
    end
  end

  @doc false
  def backup_runtime_children do
    [Playstead.Repo, {Oban, Application.fetch_env!(@app, Oban)}]
  end

  defp maybe_parent(attrs, %{parent: parent}),
    do: Map.put(attrs, :parent, %{"receipt_id" => parent})

  defp maybe_parent(attrs, _), do: attrs

  defp wait_for_published(record_id, opts) do
    now = Keyword.get(opts, :monotonic_time, fn -> System.monotonic_time(:millisecond) end)
    wait_ms = Keyword.get(opts, :wait_ms, @backup_wait_ms)
    deadline = now.() + wait_ms
    poll(record_id, deadline, opts)
  end

  defp poll(record_id, deadline, opts) do
    case dependency(opts, :status, &Playstead.Recovery.backup_status/1, record_id) do
      {:ok, %{state: "published"} = record} ->
        published_projection(record)

      {:ok, %{state: state}} when state in ["failed", "planned", "staging"] ->
        if Keyword.get(opts, :monotonic_time, fn -> System.monotonic_time(:millisecond) end).() >=
             deadline do
          if state == "failed",
            do: {:error, :backup_not_published},
            else: {:error, :backup_timeout}
        else
          dependency(opts, :sleep, &Process.sleep/1, 100)
          poll(record_id, deadline, opts)
        end

      _ ->
        {:error, :backup_not_published}
    end
  end

  defp published_projection(%{kind: kind, correlation_id: correlation_id, receipt: receipt})
       when is_map(receipt) do
    with receipt_id when is_binary(receipt_id) <- receipt["receipt_id"],
         verified_at when is_binary(verified_at) <- receipt["verified_at"],
         independence when is_binary(independence) <- receipt["independence"] do
      {:ok,
       %{
         kind: kind,
         receipt_id: receipt_id,
         correlation_id: correlation_id,
         state: "published",
         verified_at: verified_at,
         independence: independence
       }}
    else
      _ -> {:error, :backup_not_published}
    end
  end

  defp published_projection(_), do: {:error, :backup_not_published}

  defp dependency(opts, key, default, arg) do
    fun = Keyword.get(opts, key, default)
    fun.(arg)
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

  @doc """
  Boot-time reminder (WR-02, 01-REVIEW.md) for `PlaysteadWeb.Plugs.ClientIp`'s
  `x-forwarded-for` trust. Warns (never refuses to boot — this is a
  defense-in-depth reminder, not a hard safety gate like the other two
  `Playstead.Release` checks) when `PLAYSTEAD_PROXY` is left unset in a
  production release, since trusting the header unconditionally is only
  safe when the deployment topology guarantees this app is unreachable
  except through Caddy (D-15).
  """
  @spec warn_if_proxy_trust_unacknowledged!() :: :ok
  def warn_if_proxy_trust_unacknowledged! do
    if is_nil(System.get_env("PLAYSTEAD_PROXY")) and
         Application.get_env(:playstead, :trust_proxy_headers, true) do
      IO.puts(:stderr, """
      ============================================================
      WARNING: PLAYSTEAD_PROXY is unset — this app trusts the
      `x-forwarded-for` header from any connection it receives.

      This is only safe if this app is unreachable except through a
      trusted reverse proxy (e.g. the Caddy container, which is the
      only service publishing host ports in docker-compose.yml).

      If this app's port is published directly, or you're running
      without Caddy in front of it, set PLAYSTEAD_PROXY=false — an
      external client can otherwise forge its own IP and evade
      per-IP throttling.
      ============================================================
      """)
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
