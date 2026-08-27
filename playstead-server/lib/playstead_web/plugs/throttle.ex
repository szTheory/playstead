defmodule PlaysteadWeb.Plugs.Throttle do
  @moduledoc """
  Fixed per-IP and per-account throttling for login, sudo, and
  recovery-code submission (D-06, T-01-16). Uses `hammer` (chosen in plan
  01-01 — the only rate-limiting library in the application). Fixed
  limits, deliberately not adaptive: D-06 explicitly excludes adaptive
  lockout, and the host-side release reset command
  (`Playstead.Release.reset_owner_password/0`) remains an out-of-band path
  no network attacker can throttle (T-01-20, accepted risk).

  Usage:

      plug PlaysteadWeb.Plugs.Throttle, action: :login
  """

  import Plug.Conn

  alias Playstead.RateLimiter
  alias PlaysteadWeb.Problem

  @behaviour Plug

  @per_ip_scale :timer.minutes(1)
  @per_account_scale :timer.minutes(1)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    action = Keyword.fetch!(opts, :action)
    per_ip_limit = Keyword.get(opts, :per_ip_limit, config_limit(:per_ip_limit, 20))

    per_account_limit =
      Keyword.get(opts, :per_account_limit, config_limit(:per_account_limit, 10))

    with {:allow, _} <- hit_ip(conn, action, per_ip_limit),
         {:allow, _} <- hit_account(conn, action, per_account_limit) do
      conn
    else
      {:deny, _retry_after} ->
        conn
        |> Problem.send_problem(
          429,
          :rate_limited,
          "Too many attempts. Please wait a moment and try again."
        )
        |> halt()
    end
  end

  # Production defaults are overridable per-call (used directly by the
  # unit tests below) and via `config :playstead, PlaysteadWeb.Plugs.Throttle`
  # — overridden much higher in `config/test.exs` so the full test suite's
  # real `POST /log-in` traffic (many tests, one shared 127.0.0.1) never
  # accidentally throttles itself; the fixed-limit behavior this module
  # exists to prove is exercised directly, with small explicit limits, by
  # this module's own test file.
  defp config_limit(key, default) do
    Application.get_env(:playstead, __MODULE__, []) |> Keyword.get(key, default)
  end

  defp hit_ip(conn, action, limit) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    RateLimiter.hit("throttle:#{action}:ip:#{ip}", @per_ip_scale, limit)
  end

  defp hit_account(conn, action, limit) do
    case account_key(conn) do
      nil -> {:allow, 0}
      key -> RateLimiter.hit("throttle:#{action}:account:#{key}", @per_account_scale, limit)
    end
  end

  defp account_key(conn) do
    case conn.body_params do
      %{"user" => %{"email" => email}} when is_binary(email) -> String.downcase(email)
      %{"recovery" => %{"code" => code}} when is_binary(code) -> code
      _ -> nil
    end
  end
end
