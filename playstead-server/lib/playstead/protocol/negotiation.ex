defmodule Playstead.Protocol.Negotiation do
  @moduledoc """
  Range-check verdict logic for capability negotiation (D-19, PROT-03).

  A hello is compared to the server's `Playstead.Protocol.Capabilities`
  envelope by comparing ranges, never by comparing versions for
  equality — a newer client and an older pinned server remain
  compatible while their advertised ranges overlap. Both a client and a
  server run this exact same comparison over the same exchanged data,
  which is what makes the mutual "you're the one who must upgrade"
  deadlock structurally impossible: the verdict is a pure function of
  the two ranges, so both sides always agree on which side is older.
  """

  import Ecto.Query, warn: false

  alias Playstead.Repo
  alias Playstead.Protocol.{Capabilities, CapabilityDeclaration, Remedy}

  @type verdict :: :compatible | :compatible_with_limits | :incompatible

  @doc """
  Computes the negotiation verdict for a client's declared capability
  ranges against the server's supported ranges (defaults to
  `Capabilities.supported_client_ranges/0`).

  Returns one of:
  - `%{verdict: :compatible}`
  - `%{verdict: :compatible_with_limits, ignored: [String.t()]}`
  - `%{verdict: :incompatible, remedy: map()}`

  Unknown capability keys in `client_ranges` are dropped before any
  comparison runs — a hello with an unrecognized key produces the same
  verdict as the same hello without it.
  """
  @spec verdict(map(), map()) :: map()
  def verdict(client_ranges, server_ranges \\ Capabilities.supported_client_ranges()) do
    normalized_client = normalize(client_ranges)

    Capabilities.namespaces()
    |> Enum.reduce_while(%{ignored: []}, fn namespace, acc ->
      evaluate_namespace(namespace, normalized_client, server_ranges, acc)
    end)
    |> finalize()
  end

  defp evaluate_namespace(namespace, client_ranges, server_ranges, acc) do
    with {:ok, client_range} <- Map.fetch(client_ranges, namespace),
         {:ok, server_range} <- Map.fetch(server_ranges, namespace),
         false <- overlaps?(client_range, server_range) do
      if Capabilities.required?(namespace) do
        {:halt, {:incompatible, remedy_for(namespace, client_range, server_range)}}
      else
        {:cont, %{acc | ignored: [Atom.to_string(namespace) | acc.ignored]}}
      end
    else
      # Overlap holds, or the client/server simply didn't declare this
      # namespace at all — neither case affects the verdict.
      true -> {:cont, acc}
      :error -> {:cont, acc}
    end
  end

  defp finalize({:incompatible, remedy}), do: %{verdict: :incompatible, remedy: remedy}
  defp finalize(%{ignored: []}), do: %{verdict: :compatible}

  defp finalize(%{ignored: ignored}),
    do: %{verdict: :compatible_with_limits, ignored: Enum.reverse(ignored)}

  defp overlaps?(%{min: client_min, max: client_max}, %{min: server_min, max: server_max}) do
    with {:ok, cmin} <- parse(client_min),
         {:ok, cmax} <- parse(client_max),
         {:ok, smin} <- parse(server_min),
         {:ok, smax} <- parse(server_max) do
      Version.compare(cmin, smax) != :gt and Version.compare(smin, cmax) != :gt
    else
      # A malformed version on the client side can never overlap.
      :error -> false
    end
  end

  defp overlaps?(_client_range, _server_range), do: false

  defp remedy_for(_namespace, client_range, server_range) do
    {side, minimum_required} = older_side(client_range, server_range)
    Remedy.build(side, minimum_required)
  end

  defp older_side(%{min: client_min, max: client_max}, %{min: server_min}) do
    case parse(client_max) do
      {:ok, cmax} ->
        {:ok, smin} = parse(server_min)

        if Version.compare(cmax, smin) == :lt do
          # The client's whole range sits below the server's supported
          # range — the client is older and must reach server_min.
          {:client, server_min}
        else
          # Otherwise the server's whole range sits below the client's
          # declared range — the server is older and must reach
          # client_min.
          {:server, client_min}
        end

      :error ->
        {:client, server_min}
    end
  end

  defp parse(version) when is_binary(version) do
    case Version.parse(version) do
      {:ok, parsed} -> {:ok, parsed}
      :error -> :error
    end
  end

  defp parse(_), do: :error

  # Drops unrecognized namespace keys and coerces string keys/nested
  # maps (as they arrive from JSON) into the atom-keyed shape the rest
  # of this module works with. Never dynamically creates atoms from
  # client input — only namespaces already known via
  # `Capabilities.namespaces/0` are considered.
  defp normalize(client_ranges) when is_map(client_ranges) do
    Capabilities.namespaces()
    |> Enum.reduce(%{}, fn namespace, acc ->
      case fetch_range(client_ranges, namespace) do
        {:ok, range} -> Map.put(acc, namespace, range)
        :error -> acc
      end
    end)
  end

  defp normalize(_), do: %{}

  defp fetch_range(client_ranges, namespace) do
    case Map.get(client_ranges, namespace) || Map.get(client_ranges, Atom.to_string(namespace)) do
      %{} = range -> {:ok, %{min: fetch_str(range, :min), max: fetch_str(range, :max)}}
      _ -> :error
    end
  end

  defp fetch_str(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  @doc """
  Stores or refreshes `device_id`'s capability declaration. Unique on
  `device_id`, upserted via `on_conflict` so a repeat or concurrent
  hello converges to exactly one row rather than accumulating history.
  """
  @spec store_declaration(binary(), map()) :: {:ok, CapabilityDeclaration.t()} | {:error, term()}
  def store_declaration(device_id, capabilities) do
    %CapabilityDeclaration{}
    |> CapabilityDeclaration.changeset(%{device_id: device_id, capabilities: capabilities})
    |> Repo.insert(
      on_conflict: {:replace, [:capabilities, :updated_at]},
      conflict_target: [:device_id]
    )
  end
end
