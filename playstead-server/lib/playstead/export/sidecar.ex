defmodule Playstead.Export.Sidecar do
  @moduledoc """
  The versioned root and per-set sidecars (D-34, D-35, D-39). The root
  sidecar carries the schema identifier and no timestamps — volatile
  facts belong in the bag information file, so this canonical file
  stays byte-stable. Fields are additive within a major version; a
  reader encountering an unknown major version ignores the sidecar
  entirely rather than guessing at its shape.

  Entries carry a `kind` marker and both the root and each set sidecar
  reserve an (empty, in this phase) `saves` collection for Phase 4.
  """

  @schema_name "playstead-bag"
  @major_version 1
  @schema_id "#{@schema_name}/#{@major_version}.0"

  @doc "The current schema identifier this module writes."
  @spec schema_id() :: String.t()
  def schema_id, do: @schema_id

  @doc """
  Builds the canonical root sidecar map. Carries no timestamp field —
  the schema identifier and the reserved (empty) saves collection are
  the only content.
  """
  @spec root(keyword()) :: map()
  def root(opts \\ []) do
    %{
      "kind" => "root",
      "schema" => @schema_id,
      "saves" => %{"kind" => "reserved", "entries" => []},
      "generator" => Keyword.get(opts, :generator, "playstead")
    }
  end

  @doc "Builds the canonical per-set sidecar map from a `Playstead.Export.Layout` set plan."
  @spec set(map()) :: map()
  def set(set_plan) do
    %{
      "kind" => "asset_set",
      "schema" => @schema_id,
      "id" => set_plan.set_id,
      "member_fingerprint" => set_plan.member_fingerprint,
      "system_id" => set_plan.system_id,
      "title" => set_plan.display_title,
      "status" => set_plan.status,
      "provenance" => Map.get(set_plan, :provenance, %{}),
      "recognition" => Map.get(set_plan, :recognition, %{}),
      "saves" => %{"kind" => "reserved", "entries" => []},
      "members" =>
        Enum.map(set_plan.members, fn m ->
          %{
            "path" => Path.join("data", m.relative),
            "original_name" => m.original_name,
            "exported_name" => m.exported_name,
            "sha256" => m.sha256,
            "size_bytes" => m.size_bytes,
            "role" => m.role,
            "ordinal" => m.ordinal,
            "required" => m.required
          }
        end)
    }
  end

  @doc """
  Encodes `map` as canonical JSON: keys sorted at every level, no
  whitespace variance across runs, newline-terminated. Two calls with
  the same logical content always produce byte-identical output,
  regardless of Elixir map iteration order.
  """
  @spec encode(map()) :: String.t()
  def encode(map) when is_map(map) do
    encode_value(map) <> "\n"
  end

  defp encode_value(map) when is_map(map) do
    inner =
      map
      |> Enum.sort_by(fn {k, _v} -> to_string(k) end)
      |> Enum.map_join(",", fn {k, v} -> "#{encode_value(to_string(k))}:#{encode_value(v)}" end)

    "{#{inner}}"
  end

  defp encode_value(list) when is_list(list) do
    "[" <> Enum.map_join(list, ",", &encode_value/1) <> "]"
  end

  defp encode_value(bin) when is_binary(bin), do: Jason.encode!(bin)
  defp encode_value(other), do: Jason.encode!(other)

  @doc """
  Parses a sidecar JSON string. Returns `{:ok, map}` only when the
  schema's major version is known and matches this module's; returns
  `:ignore` for any unknown major version, a missing/malformed schema
  field, or invalid JSON — a reader must never misinterpret a sidecar
  it cannot understand, and must never raise trying.
  """
  @spec parse(String.t()) :: {:ok, map()} | :ignore
  def parse(content) when is_binary(content) do
    with {:ok, %{"schema" => schema} = decoded} <- Jason.decode(content),
         {:ok, major} <- parse_major(schema) do
      if major == @major_version, do: {:ok, decoded}, else: :ignore
    else
      _ -> :ignore
    end
  end

  def parse(_content), do: :ignore

  defp parse_major(schema) when is_binary(schema) do
    with [@schema_name, version] <- String.split(schema, "/", parts: 2),
         [major_str | _] <- String.split(version, "."),
         {major, ""} <- Integer.parse(major_str) do
      {:ok, major}
    else
      _ -> :error
    end
  end

  defp parse_major(_schema), do: :error
end
