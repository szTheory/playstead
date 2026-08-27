defmodule PlaysteadWeb.Plugs.ClientIp do
  @moduledoc """
  Derives the requesting IP from the trusted proxy hop only (D-09).

  Per D-15, only the Caddy container publishes host ports; the app binds
  exclusively to the compose network, so `conn.remote_ip` is always
  Caddy's own hop and never an arbitrary internet peer. That structural
  guarantee is what makes it safe to trust Caddy's `x-forwarded-for`
  header here — an external client cannot reach this plug directly to
  forge the header, only Caddy can set it.

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
    case get_req_header(conn, "x-forwarded-for") do
      [value | _] when is_binary(value) and value != "" ->
        value
        |> String.split(",")
        |> List.first()
        |> String.trim()

      _ ->
        remote_ip_string(conn)
    end
  end

  defp remote_ip_string(conn) do
    conn.remote_ip
    |> :inet.ntoa()
    |> to_string()
  end
end
