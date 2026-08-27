defmodule PlaysteadWeb.Plugs.SudoMode do
  @moduledoc """
  Re-authentication gate for dangerous actions with a bounded freshness
  window (D-06, T-01-15): session revocation, recovery-code regeneration
  now, and device revocation/credential rotation in plan 01-05.

  A request or LiveView mount without a fresh sudo confirmation is
  redirected to `PlaysteadWeb.SudoLive` (`/sudo`) and the intended action
  does not execute. Successful re-entry (`PlaysteadWeb.SudoLive` posting
  through `PlaysteadWeb.UserSessionController.create/2`) records a
  `sudo_confirmed` audit entry and returns the user to the pending action.

  Two entry points are provided because Phoenix LiveView navigation
  (`navigate`/`push_navigate`) does not re-run the router's plug pipeline:

    * `require_sudo/2` (also `call/2`, so this module is itself a
      router-pipeline plug) — for controller actions and the initial
      (disconnected) render of a `live` route.
    * `on_mount/4` — for `live_session`/`on_mount` gating, which also
      covers LiveView-to-LiveView navigation.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2, current_path: 1]

  alias Playstead.Accounts

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts), do: require_sudo(conn, opts)

  @doc """
  Router-pipeline plug. Halts and redirects to `/sudo` (storing the
  current path as the post-confirmation return target) unless the
  currently authenticated user has a fresh sudo confirmation.
  """
  def require_sudo(conn, _opts) do
    user = conn.assigns[:current_scope] && conn.assigns.current_scope.user

    if user && Accounts.sudo_mode?(user) do
      conn
    else
      conn
      |> put_session(:user_return_to, current_path(conn))
      |> redirect(to: "/sudo")
      |> halt()
    end
  end

  @doc """
  LiveView `on_mount` hook mirroring `require_sudo/2` for routes reached
  via LiveView `navigate`, which bypasses the router's plug pipeline.

      live_session :sessions,
        on_mount: [
          {PlaysteadWeb.UserAuth, :require_authenticated},
          {PlaysteadWeb.Plugs.SudoMode, :require_sudo}
        ] do
        live "/settings/sessions", SessionsLive
      end
  """
  def on_mount(:require_sudo, _params, _session, socket) do
    user = socket.assigns[:current_scope] && socket.assigns.current_scope.user

    if user && Accounts.sudo_mode?(user) do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(
          :error,
          "Confirm it's you — enter your password to continue."
        )
        |> Phoenix.LiveView.redirect(to: "/sudo")

      {:halt, socket}
    end
  end
end
