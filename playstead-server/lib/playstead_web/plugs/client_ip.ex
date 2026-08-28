defmodule PlaysteadWeb.Plugs.ClientIp do
  @moduledoc """
  Derives the requesting IP from the trusted proxy hop only (D-09).

  Per D-15, only the Caddy container publishes host ports; the app binds
  exclusively to the compose network, so `conn.remote_ip` is always
  Caddy's own hop and never an arbitrary internet peer. That structural
  guarantee is what makes it safe to trust Caddy's `x-forwarded-for`
  header here — an external client cannot reach this plug directly to
  forge the header, only Caddy can set it.

  WR-02 (01-REVIEW.md): that guarantee is external to this module and not
  verified at runtime, so trusting `x-forwarded-for` is gated behind the
  `:playstead, :trust_proxy_headers` config flag (`PLAYSTEAD_PROXY` env
  var in production, defaults to `true`). Operators who run this app with
  its port directly published, or without Caddy in front of it, must set
  `PLAYSTEAD_PROXY=false` so this plug falls back to `conn.remote_ip`
  instead of trusting a client-controllable header.

  Assigns `:client_ip` onto the conn as a string.
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    assign(conn, :client_ip, trusted_ip(conn))
  end

  defp trusted_ip(conn) do
    if trust_proxy_headers?() do
      case get_req_header(conn, "x-forwarded-for") do
        [value | _] when is_binary(value) and value != "" ->
          value
          |> String.split(",")
          |> List.first()
          |> String.trim()

        _ ->
          remote_ip_string(conn)
      end
    else
      remote_ip_string(conn)
    end
  end

  defp trust_proxy_headers? do
    Application.get_env(:playstead, :trust_proxy_headers, true)
  end

  defp remote_ip_string(conn) do
    conn.remote_ip
    |> :inet.ntoa()
    |> to_string()
  end
end
