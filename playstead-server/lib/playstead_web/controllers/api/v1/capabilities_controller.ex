defmodule PlaysteadWeb.Api.V1.CapabilitiesController do
  @moduledoc """
  `GET /api/v1/capabilities` — deliberately unauthenticated (D-19): a
  client that cannot negotiate must never be locked out of the
  capabilities surface. Renders the domain-owned envelope directly.
  """

  use PlaysteadWeb, :controller

  def show(conn, _params) do
    json(conn, Playstead.Protocol.Capabilities.envelope())
  end
end
