defmodule Playstead.Protocol.Remedy do
  @moduledoc """
  Structured remedy object for an `incompatible` capability verdict
  (D-19). Both sides of a hello derive their verdict from the same
  exchanged ranges, so `side_too_old` always agrees between client and
  server — the mutual "you upgrade" deadlock cannot occur, since there
  is exactly one older side by construction.

  Clients key their microcopy off `who_must_act`/`side_too_old`, never
  an English sentence — this module has no localized strings.
  """

  @type side :: :client | :server

  @default_detail_url "https://playstead.dev/docs/protocol-compatibility"

  @doc """
  Builds the remedy map: `who_must_act`, `side_too_old`,
  `minimum_required`, `detail_url`.

  `side_too_old` is `:client` when the client's declared range falls
  entirely below the server's supported range (the user must update
  the client), or `:server` when the server's supported range falls
  entirely below the client's declared range (the server admin must
  upgrade the server). `minimum_required` is the version the older
  side must reach to regain overlap.
  """
  @spec build(side(), String.t(), String.t()) :: map()
  def build(side_too_old, minimum_required, detail_url \\ @default_detail_url)
      when side_too_old in [:client, :server] and is_binary(minimum_required) do
    %{
      who_must_act: who_must_act(side_too_old),
      side_too_old: side_too_old,
      minimum_required: minimum_required,
      detail_url: detail_url
    }
  end

  defp who_must_act(:client), do: "user"
  defp who_must_act(:server), do: "server_admin"
end
