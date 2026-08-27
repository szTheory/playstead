defmodule Playstead.Protocol.Capabilities do
  @moduledoc """
  Owns the frozen `/api/v1/capabilities` envelope (D-18, D-19).

  This is the meta-contract every current and future Playstead client
  negotiates against. The shape of `envelope/0` is frozen by contract
  tests — adding, removing, or renaming a top-level or
  `supported_client_ranges` key is a breaking change to the published
  protocol and must not happen without a new path major.

  Controllers render this envelope directly; they never inline a
  literal capabilities map.
  """

  @protocol_major 1
  @protocol_minor 0

  # Only the namespaces REQUIREMENTS.md names (D-19). Do not add keys
  # for unbuilt features.
  @capability_namespaces [:protocol, :app, :cache, :transfer, :adapter, :save]

  @doc """
  The frozen capability document.

  Returns a map with exactly the keys `protocol`, `server_build`, and
  `supported_client_ranges`. `supported_client_ranges` carries exactly
  the six namespaces in `@capability_namespaces`, each with a `min`
  and `max` supported version.
  """
  @spec envelope() :: map()
  def envelope do
    %{
      protocol: %{major: @protocol_major, minor: @protocol_minor},
      server_build: server_build(),
      supported_client_ranges: supported_client_ranges()
    }
  end

  @doc "The current protocol major/minor as a map, e.g. `%{major: 1, minor: 0}`."
  @spec protocol_version() :: %{major: non_neg_integer(), minor: non_neg_integer()}
  def protocol_version, do: %{major: @protocol_major, minor: @protocol_minor}

  defp server_build do
    Application.spec(:playstead, :vsn) |> to_string()
  end

  defp supported_client_ranges do
    Map.new(@capability_namespaces, fn namespace ->
      {namespace, %{min: "1.0.0", max: "1.0.0"}}
    end)
  end
end
