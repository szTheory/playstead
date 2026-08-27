defmodule Playstead.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  # Evaluated at compile time — Mix is not available in a compiled
  # release at runtime, but the resulting atom is embedded as a
  # literal, so this check works fine in a release.
  @env Mix.env()

  @impl true
  def start(_type, _args) do
    # Boot-time safety gates (D-15, D-17), production releases only.
    # Order matters: refuse placeholder secrets before touching the
    # database; check the schema floor against the pre-migration state
    # before running migrations that could otherwise silently skip an
    # operator through an unsupported upgrade path.
    if @env == :prod do
      Playstead.Release.assert_no_placeholder_secrets!()
      Playstead.Release.assert_minimum_upgradable_version!()
      Playstead.Release.migrate()
    end

    children = [
      PlaysteadWeb.Telemetry,
      Playstead.Repo,
      {DNSCluster, query: Application.get_env(:playstead, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Playstead.PubSub},
      {Oban, Application.fetch_env!(:playstead, Oban)},
      # D-06: fixed per-IP/per-account throttling for login, sudo, and
      # recovery-code submission (PlaysteadWeb.Plugs.Throttle).
      Playstead.RateLimiter,
      # Start to serve requests, typically the last entry
      PlaysteadWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Playstead.Supervisor]

    with {:ok, pid} <- Supervisor.start_link(children, opts) do
      # D-03's setup-token bootstrap needs the Repo running, hence after
      # the supervisor starts rather than before. Skipped in :test — the
      # Ecto Sandbox pool requires an explicit per-process checkout that
      # this boot-time call (running outside any test's owner process)
      # does not have; tests exercise `Playstead.Setup` directly instead.
      if @env != :test, do: Playstead.Setup.mint_token()

      {:ok, pid}
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PlaysteadWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
