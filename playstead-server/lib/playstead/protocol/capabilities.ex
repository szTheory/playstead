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

  # D-19: `protocol` is the only namespace whose overlap is mandatory —
  # it is the versioning contract itself. A mismatch on any other
  # namespace degrades to `compatible_with_limits`, never a hard
  # incompatibility. This required/optional split is server-side
  # negotiation logic, never part of the frozen public envelope shape
  # (`envelope/0`'s `supported_client_ranges` keeps exactly `min`/`max`
  # per namespace — see the capabilities_controller contract test).
  @required_namespaces [:protocol]

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

  @doc "The six namespaces this server negotiates over (D-19)."
  @spec namespaces() :: [atom()]
  def namespaces, do: @capability_namespaces

  @doc "Whether `namespace` requires overlap for a `compatible` verdict (D-19)."
  @spec required?(atom()) :: boolean()
  def required?(namespace), do: namespace in @required_namespaces

  @doc "The server's supported client ranges, keyed by namespace atom. Same values `envelope/0` publishes, exposed directly for negotiation."
  @spec supported_client_ranges() :: %{atom() => %{min: String.t(), max: String.t()}}
  def supported_client_ranges do
    Map.new(@capability_namespaces, fn namespace ->
      {namespace, %{min: "1.0.0", max: "1.0.0"}}
    end)
  end

  defp server_build do
    Application.spec(:playstead, :vsn) |> to_string()
  end
end
