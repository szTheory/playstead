defmodule PlaysteadWeb.SandboxHook do
  @moduledoc """
  Test-only LiveView `on_mount` hook: when a browser test (Wallaby) opens a
  LiveView, the connecting socket's User-Agent carries the Ecto sandbox
  metadata the test stamped into it, and this hook grants the LiveView
  process access to that test's database connection.

  Attached only when `config :playstead, :sql_sandbox` is true (see
  `PlaysteadWeb.live_view/0`), so it is compiled out of dev and prod. It is
  a no-op on the disconnected (dead) render and whenever no sandbox
  metadata is present (plain LiveViewTest requests).
  """

  import Phoenix.LiveView, only: [connected?: 1, get_connect_info: 2]

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      socket
      |> get_connect_info(:user_agent)
      |> allow_sandbox()
    end

    {:cont, socket}
  end

  defp allow_sandbox(user_agent) when is_binary(user_agent) do
    Phoenix.Ecto.SQL.Sandbox.allow(user_agent, Ecto.Adapters.SQL.Sandbox)
  end

  defp allow_sandbox(_), do: :ok
end
