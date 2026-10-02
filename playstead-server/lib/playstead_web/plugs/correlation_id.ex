defmodule PlaysteadWeb.Plugs.CorrelationId do
  @moduledoc """
  Mints one opaque UUID at the API boundary and keeps it on the request
  connection. The value is diagnostic evidence only; no authorization or
  request-derived data participates in its construction.
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    assign(conn, :correlation_id, Ecto.UUID.generate())
  end
end
