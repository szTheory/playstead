defmodule Playstead.Recovery.Verifier do
  @moduledoc "Re-reads every manifest member before a backup receipt may be published."

  @spec verify(String.t()) :: {:ok, map()} | {:error, term()}
  def verify(root) do
    with {:ok, manifest_bytes} <- File.read(Path.join(root, "manifest.json")),
         {:ok, manifest} <- Jason.decode(manifest_bytes),
         "playstead.backup-set.v1" <- manifest["schema"],
         %{"entries" => entries} <- manifest["coverage"],
         true <- is_list(entries) and entries != [] do
      mismatches = entries |> Enum.reject(&matches?(root, &1)) |> Enum.map(& &1["relative"])

      if mismatches == [],
        do: {:ok, %{checked: length(entries) + 1}},
        else: {:error, {:mismatches, mismatches}}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_manifest}
    end
  end

  @doc "Verifies an in-memory ordered full/incremental chain before any destination write."
  @spec verify_chain([map()]) :: :ok | {:error, :missing_parent | :parent_cycle | :invalid_chain}
  def verify_chain(records) when is_list(records) do
    by_id = Map.new(records, &{&1["id"], &1})

    records
    |> Enum.reduce_while(:ok, fn record, :ok ->
      case resolve_parent(record, by_id, MapSet.new()) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  def verify_chain(_), do: {:error, :invalid_chain}

  @doc "Checks that an incremental coverage inventory is complete and only omits chain-held blobs."
  @spec verify_incremental_coverage([map()], [map()], [String.t()]) ::
          :ok | {:error, :incomplete_inventory}
  def verify_incremental_coverage(complete_inventory, copied_members, parent_hashes)
      when is_list(complete_inventory) and is_list(copied_members) and is_list(parent_hashes) do
    inventory = complete_inventory |> Enum.map(& &1["sha256"]) |> Enum.sort()
    copied = copied_members |> Enum.map(& &1["sha256"]) |> Enum.sort()
    expected = inventory |> Enum.reject(&(&1 in parent_hashes)) |> Enum.sort()

    if inventory == Enum.uniq(inventory) and copied == expected,
      do: :ok,
      else: {:error, :incomplete_inventory}
  end

  defp matches?(root, %{"relative" => relative, "sha256" => sha256, "size_bytes" => size}) do
    path = Path.join(root, relative)

    contained?(path, root) and
      case File.read(path) do
        {:ok, bytes} -> byte_size(bytes) == size and digest(bytes) == sha256
        _ -> false
      end
  end

  defp matches?(_, _), do: false

  defp resolve_parent(%{"kind" => "full", "parent" => nil}, _by_id, _seen), do: :ok

  defp resolve_parent(%{"id" => id, "parent" => %{"receipt_id" => parent_id}}, by_id, seen) do
    cond do
      MapSet.member?(seen, id) -> {:error, :parent_cycle}
      is_nil(by_id[parent_id]) -> {:error, :missing_parent}
      true -> resolve_parent(by_id[parent_id], by_id, MapSet.put(seen, id))
    end
  end

  defp resolve_parent(_, _by_id, _seen), do: {:error, :invalid_chain}
  defp digest(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp contained?(path, root),
    do: Path.expand(path) |> String.starts_with?(Path.expand(root) <> "/")
end
