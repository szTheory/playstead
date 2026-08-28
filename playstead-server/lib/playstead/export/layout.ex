defmodule Playstead.Export.Layout do
  @moduledoc """
  The deterministic, fully sorted, collision-resolving folder layout
  for an export (D-34, D-35). `plan/2` produces the complete file plan
  for an export scope before a single byte is written, so the plan can
  be checked, sorted, and resumed.

  Set folders are the sanitized display title under a system slug
  folder, disambiguated by a short identifier suffix only when two
  titles collide after normalization and case folding within that
  system. Member filenames are the recorded original basenames unless
  genuinely unsafe, in which case both the original and the exported
  form are recorded. Everything is fully sorted and carries no
  timestamps, so planning the same library twice yields identical
  output.
  """

  alias Playstead.Export.Sanitize

  @unsorted_folder "unsorted"
  @quarantine_folder "quarantine"

  @type member_input :: %{
          required(:ordinal) => integer(),
          required(:role) => String.t(),
          required(:required) => boolean(),
          required(:declared_name) => String.t() | nil,
          required(:sha256) => String.t() | nil,
          required(:size_bytes) => non_neg_integer() | nil
        }

  @type set_input :: %{
          required(:id) => String.t(),
          required(:system_id) => String.t() | nil,
          required(:display_title) => String.t(),
          required(:status) => String.t(),
          required(:member_fingerprint) => String.t(),
          optional(:excluded) => boolean(),
          required(:members) => [member_input()]
        }

  @doc """
  Plans a whole export scope. `sets` is the list of asset sets to
  include; `opts[:quarantined]` is the list of quarantined blobs
  (`%{sha256:, size_bytes:}`) to place under the quarantine folder.
  `opts[:include_excluded]` (default `false`) controls whether sets
  carrying `excluded: true` are included — only opt-in inclusion, never
  the default.
  """
  @spec plan([set_input()], keyword()) :: map()
  def plan(sets, opts \\ []) when is_list(sets) do
    include_excluded? = Keyword.get(opts, :include_excluded, false)
    quarantined = Keyword.get(opts, :quarantined, [])

    included_sets =
      sets
      |> Enum.reject(fn s -> Map.get(s, :excluded, false) and not include_excluded? end)

    set_plans =
      included_sets
      |> Enum.group_by(&system_folder/1)
      |> Enum.flat_map(fn {system_folder, sets_in_system} ->
        plan_system(system_folder, sets_in_system)
      end)
      |> Enum.sort_by(& &1.relative_dir)

    quarantine_plans =
      quarantined
      |> Enum.map(&plan_quarantine_entry/1)
      |> Enum.sort_by(& &1.relative)

    %{sets: set_plans, quarantine: quarantine_plans}
  end

  defp system_folder(%{system_id: nil}), do: @unsorted_folder
  defp system_folder(%{system_id: system_id}), do: to_string(system_id)

  defp plan_system(system_folder, sets_in_system) do
    keyed =
      Enum.map(sets_in_system, fn set ->
        {sanitized_title, _changed?} = Sanitize.component(set.display_title)
        {set, sanitized_title, Sanitize.collision_key(sanitized_title)}
      end)

    collision_counts =
      keyed
      |> Enum.frequencies_by(fn {_set, _title, key} -> key end)

    keyed
    |> Enum.map(fn {set, sanitized_title, key} ->
      folder_name =
        if Map.get(collision_counts, key, 0) > 1 do
          suffix = short_id_suffix(set.id)
          "#{sanitized_title}-#{suffix}"
        else
          sanitized_title
        end

      relative_dir = Path.join(system_folder, folder_name)
      plan_set(set, relative_dir)
    end)
  end

  defp short_id_suffix(id) when is_binary(id) do
    id |> String.replace("-", "") |> String.slice(0, 8)
  end

  defp plan_set(set, relative_dir) do
    members =
      set.members
      |> Enum.sort_by(& &1.ordinal)
      |> Enum.map(&plan_member(relative_dir, &1))

    %{
      set_id: set.id,
      relative_dir: relative_dir,
      system_id: Map.get(set, :system_id),
      display_title: set.display_title,
      status: set.status,
      member_fingerprint: set.member_fingerprint,
      provenance: Map.get(set, :provenance, %{}),
      sidecar_path: Path.join(relative_dir, "playstead-set.json"),
      saves_path: Path.join(relative_dir, "saves"),
      members: members
    }
  end

  defp plan_member(relative_dir, member) do
    candidate = member.declared_name || "member-#{member.ordinal}"
    {sanitized, changed?} = Sanitize.component(candidate)

    {exported_name, changed?} =
      if Sanitize.reserved_saves_name?(sanitized) do
        {"#{sanitized}-member-#{member.ordinal}", true}
      else
        {sanitized, changed?}
      end

    %{
      relative: Path.join(relative_dir, exported_name),
      original_name: candidate,
      exported_name: exported_name,
      name_changed?: changed?,
      sha256: member.sha256,
      size_bytes: member.size_bytes,
      role: member.role,
      ordinal: member.ordinal,
      required: member.required
    }
  end

  defp plan_quarantine_entry(%{sha256: sha256} = entry) do
    %{
      relative: Path.join(@quarantine_folder, sha256),
      sha256: sha256,
      size_bytes: Map.get(entry, :size_bytes),
      reason: Map.get(entry, :reason)
    }
  end
end
