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

  ## transfer 1.1.0 (D-19)

  `transfer` advertises range-resume support by version rather than by
  adding a key to the frozen envelope shape: max `"1.1.0"` means
  single-range resumable blob GET — `Range`, `If-Range`, `206`, `416`,
  and `HEAD` on `/api/v1/blobs/:sha256`, per D-19. `transfer` is not in
  `@required_namespaces`, so a client declaring a transfer max below
  `1.1.0` negotiates `compatible_with_limits` (never `incompatible`)
  and must fall back to whole-file downloads — the intended
  version-skew behaviour.
  """

  @protocol_major 1
  @protocol_minor 0

  # Only the namespaces REQUIREMENTS.md names (D-19). Do not add keys
  # for unbuilt features.
  @capability_namespaces [:protocol, :app, :cache, :transfer, :adapter, :save]

  # D-19: per-namespace {min, max} overrides. Any namespace not listed
  # here defaults to {"1.0.0", "1.0.0"} — this is additive-only capacity
  # to advertise a newer feature version within an existing namespace,
  # never a change to envelope/0's frozen key shape.
  @namespace_ranges %{
    transfer: {"1.0.0", "1.1.0"}
  }

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
      {min, max} = Map.get(@namespace_ranges, namespace, {"1.0.0", "1.0.0"})
      {namespace, %{min: min, max: max}}
    end)
  end

  defp server_build do
    Application.spec(:playstead, :vsn) |> to_string()
  end
end
