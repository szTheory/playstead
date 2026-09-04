defmodule Playstead.Export.Sidecar do
  @moduledoc """
  The versioned root and per-set sidecars (D-34, D-35, D-39). The root
  sidecar carries the schema identifier and no timestamps — volatile
  facts belong in the bag information file, so this canonical file
  stays byte-stable. Fields are additive within a major version; a
  reader encountering an unknown major version ignores the sidecar
  entirely rather than guessing at its shape.

  Entries carry a `kind` marker. Both the root and each set sidecar
  carry a `saves` object (D-56, D-60): the root's is a static,
  library-wide marker (per-set detail lives where it belongs, in the
  set sidecar); each set's `saves` object is populated from
  `Playstead.Export.SavesPlan`'s output, with `branches` always
  present -- even for a fully linear history -- so a diverged slot can
  never serialise as a flat list that implies one history.
  """

  alias Playstead.Export.SavesPlan

  @schema_name "playstead-bag"
  @major_version 1
  @schema_id "#{@schema_name}/#{@major_version}.0"

  @doc "The current schema identifier this module writes."
  @spec schema_id() :: String.t()
  def schema_id, do: @schema_id

  @doc """
  Builds the canonical root sidecar map. Carries no timestamp field —
  the schema identifier and the (structurally always-present) saves
  marker are the only content.
  """
  @spec root(keyword()) :: map()
  def root(opts \\ []) do
    %{
      "kind" => "root",
      "schema" => @schema_id,
      "saves" => %{"kind" => "saves", "branches" => []},
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
      "saves" => saves_sidecar(Map.get(set_plan, :saves_plan, SavesPlan.plan([]))),
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

  # D-60: `branches` is always present, even when the history is
  # linear (a single-element list, `"branch" => nil`) -- this is what
  # makes a diverged slot structurally incapable of serialising as a
  # flat list. A revision whose bytes never uploaded (D-61) is named
  # here with `"bytes" => "missing"` and carries no `path` -- it is
  # never placed in the payload manifest or `fetch.txt`.
  defp saves_sidecar(%{entries: []} = saves_plan) do
    %{"kind" => "saves", "branches" => [], "drop_in" => saves_revision_ref(saves_plan.drop_in)}
  end

  defp saves_sidecar(saves_plan) do
    %{
      "kind" => "saves",
      "branches" => Enum.map(saves_plan.branches, &saves_branch/1),
      "drop_in" => saves_revision_ref(saves_plan.drop_in)
    }
  end

  defp saves_branch(%{branch: branch, revisions: revisions}) do
    %{
      "branch" => branch,
      "revisions" => Enum.map(revisions, &saves_revision_ref/1)
    }
  end

  defp saves_revision_ref(nil), do: nil

  defp saves_revision_ref(entry) do
    bytes_status = to_string(Map.get(entry, :bytes, :present))

    %{
      "seq" => Map.get(entry, :seq),
      "sha256" => entry.sha256,
      "size_bytes" => entry.size_bytes,
      "bytes" => bytes_status,
      "path" => if(bytes_status == "present", do: Path.join("data", entry.relative), else: nil)
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
