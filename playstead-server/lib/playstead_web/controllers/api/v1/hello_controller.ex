defmodule PlaysteadWeb.Api.V1.HelloController do
  @moduledoc """
  `POST /api/v1/hello` — per-session capability negotiation (D-19,
  PROT-03). Device-authenticated: `conn.assigns.current_device` is set
  by `PlaysteadWeb.Plugs.DeviceAuth`.

  Renders the domain-computed verdict directly; the controller never
  inlines a compatibility decision of its own.
  """

  use PlaysteadWeb, :controller

  alias Playstead.Protocol.{Capabilities, Negotiation}

  action_fallback PlaysteadWeb.Api.V1.FallbackController

  @doc """
  Stores/refreshes the device's declaration on every hello — regardless
  of verdict, since an `incompatible` client must still be able to
  learn why and remain revocable (D-19).
  """
  def create(conn, params) do
    device = conn.assigns.current_device
    capabilities = Map.get(params, "capabilities", %{})

    {:ok, _declaration} = Negotiation.store_declaration(device.id, capabilities)

    case Negotiation.verdict(capabilities, Capabilities.supported_client_ranges()) do
      %{verdict: :compatible} ->
        json(conn, %{verdict: "compatible"})

      %{verdict: :compatible_with_limits, ignored: ignored} ->
        json(conn, %{verdict: "compatible_with_limits", ignored_capabilities: ignored})

      %{verdict: :incompatible, remedy: remedy} ->
        PlaysteadWeb.Problem.send_problem(
          conn,
          422,
          :capability_incompatible,
          "This device's declared capabilities are incompatible with the server.",
          %{remedy: remedy}
        )
    end
  end
end
