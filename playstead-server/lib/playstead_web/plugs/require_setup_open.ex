defmodule PlaysteadWeb.Plugs.RequireSetupOpen do
  @moduledoc """
  D-03's "never an unauthenticated first-visit claim window" property,
  enforced at the router layer: `/setup` renders while no owner exists
  and 404s — permanently, not a redirect — the moment one does.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if Playstead.Accounts.owner_exists?() do
      conn
      |> send_resp(404, "Not Found")
      |> halt()
    else
      conn
    end
  end
end
