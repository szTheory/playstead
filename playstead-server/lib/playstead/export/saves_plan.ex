defmodule Playstead.Export.SavesPlan do
  @moduledoc """
  The pure planner that fills Phase 2's reserved `saves/` export slot
  (D-56, D-58, D-59, D-62). Turns a flat list of already-loaded save
  revisions into the deterministic file plan for one save slot:
  sequence numbers in a total order over server `recorded_at` then
  `id`, a device-independent branch letter for a revision that belongs
  to a fork, and -- for a linear `system_save` slot only -- a drop-in
  convenience copy named from the set's primary member's original
  basename.

  Performs no `Repo` call, no filesystem read or write, and reads no
  clock -- the caller loads the data (revision digests, branch keys,
  and sequencing input) and hands it in as plain maps. `Export ->
  Saves` coupling exists at the context boundary only: this module
  never mentions the saves bounded context by name, and `Playstead.Export.Layout`
  never aliases it either.

  Filenames follow `{seq:06}[-{branch}]-{digest8}.{ext}`. `seq` is
  allocated once, in `{recorded_at, id}` order, and is stable under
  append -- a previously assigned sequence number is never reused or
  shifted when a new revision arrives later, because that total order
  is itself stable under insertion. `recorded_at` remains the only
  ordering SEMANTICS (D-15); `id` is a fixed immutable tiebreaker that
  makes the order reproducible regardless of the caller's input order,
  not a claim about causal order. The optional
  branch letter comes from each revision's `branch_key` -- a stable,
  fork-inherited string the caller already computed -- sorted
  ascending and never derived from a device name, so renaming a Mac
  between two planning runs changes nothing about a past export.

  A diverged slot (more than one current head) never gets a drop-in
  copy: silently picking a side would be last-write-wins performed by
  the export tool. A drop-in copy is defined only for `save_kind:
  "system_save"` -- a save state can never earn one, because a
  drop-in name is a portability claim a save state cannot make.
  """

  alias Playstead.Export.Sanitize

  @digest8_length 8
  @system_save_kind "system_save"

  @type revision_input :: %{
          required(:id) => String.t(),
          required(:sha256) => String.t(),
          required(:size_bytes) => non_neg_integer() | nil,
          required(:recorded_at) => DateTime.t(),
          required(:save_kind) => String.t(),
          required(:is_head) => boolean(),
          optional(:branch_key) => String.t() | nil,
          optional(:bytes) => :present | :missing
        }

  @doc """
  Plans one save slot from `revisions`. Returns
  `%{entries:, branches:, drop_in:, diverged?:}`; `entries` and every
  branch's `revisions` are ordered by sequence. `branches` is always
  present -- even a fully linear slot serialises as a single-element
  list (`branch: nil`) -- so a diverged slot can never collapse into a
  flat list that implies one history.

  `opts[:primary_basename]` names the set's primary member's recorded
  original basename (used for the drop-in copy's stem, never the
  display title); `opts[:ext]` is the artifact extension (default
  `"sav"`).
  """
  @spec plan([revision_input()], keyword()) :: map()
  def plan(revisions, opts \\ []) when is_list(revisions) do
    primary_basename = Keyword.get(opts, :primary_basename)
    ext = Keyword.get(opts, :ext, "sav")

    ordered =
      revisions
      |> Enum.sort(&order_key_lte?/2)
      |> Enum.with_index(1)
      |> Enum.map(fn {revision, seq} -> Map.put(revision, :seq, seq) end)

    branch_letters = assign_branch_letters(ordered)
    entries = Enum.map(ordered, &plan_entry(&1, branch_letters, ext))
    heads = Enum.filter(ordered, & &1.is_head)
    diverged? = length(heads) > 1

    %{
      entries: entries,
      branches: build_branches(entries),
      drop_in: plan_drop_in(heads, diverged?, primary_basename, ext),
      diverged?: diverged?
    }
  end

  # Total order over `recorded_at` then `.id`: `recorded_at` is the
  # only ordering SEMANTICS (D-15); `.id` is a fixed immutable
  # tiebreaker that makes the sort's result independent of the order
  # `revisions` arrived in, rather than depending on `Enum.sort_by/3`'s
  # stability (which merely preserves whatever order a tied pair
  # already had). A comparator over the pair, not a second sort pass,
  # so a single traversal produces the total order.
  defp order_key_lte?(%{recorded_at: a_at, id: a_id}, %{recorded_at: b_at, id: b_id}) do
    case DateTime.compare(a_at, b_at) do
      :lt -> true
      :gt -> false
      :eq -> a_id <= b_id
    end
  end

  defp assign_branch_letters(ordered) do
    ordered
    |> Enum.map(&Map.get(&1, :branch_key))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.with_index()
    |> Map.new(fn {key, index} -> {key, letter_for(index)} end)
  end

  # a, b, c, ... z, then aa, ab, ... -- 32 branch heads is the loud cap
  # (Saves.max_branch_heads/0), so this never has to think hard about
  # wraparound in practice, but it degrades gracefully rather than
  # crashing past 26.
  defp letter_for(index) when index < 26, do: <<index + ?a>>

  defp letter_for(index) do
    letter_for(div(index, 26) - 1) <> letter_for(rem(index, 26))
  end

  defp plan_entry(revision, branch_letters, ext) do
    branch = branch_letters[Map.get(revision, :branch_key)]
    digest8 = String.slice(revision.sha256, 0, @digest8_length)
    filename = filename_for(revision.seq, branch, digest8, ext)
    bytes = Map.get(revision, :bytes, :present)

    %{
      relative: Path.join("saves/revisions", filename),
      seq: revision.seq,
      branch: branch,
      sha256: revision.sha256,
      size_bytes: revision.size_bytes,
      save_kind: revision.save_kind,
      revision_id: revision.id,
      bytes: bytes
    }
  end

  defp filename_for(seq, nil, digest8, ext), do: "#{pad(seq)}-#{digest8}.#{ext}"
  defp filename_for(seq, branch, digest8, ext), do: "#{pad(seq)}-#{branch}-#{digest8}.#{ext}"

  defp pad(seq), do: seq |> Integer.to_string() |> String.pad_leading(6, "0")

  # Grouped by branch letter, in ascending order, with the shared
  # (unlettered) history first when it exists -- "branches" is always
  # present, even for a fully linear slot, which is precisely what
  # makes a diverged slot structurally incapable of serialising as a
  # flat list (D-60).
  defp build_branches(entries) do
    letters =
      entries
      |> Enum.map(& &1.branch)
      |> Enum.uniq()
      |> Enum.sort_by(fn
        nil -> {0, ""}
        letter -> {1, letter}
      end)

    case letters do
      [] ->
        [%{branch: nil, revisions: []}]

      _ ->
        Enum.map(letters, fn branch ->
          %{branch: branch, revisions: Enum.filter(entries, &(&1.branch == branch))}
        end)
    end
  end

  defp plan_drop_in([], _diverged?, _primary_basename, _ext), do: nil
  defp plan_drop_in(_heads, true, _primary_basename, _ext), do: nil
  defp plan_drop_in(_heads, false, nil, _ext), do: nil

  defp plan_drop_in([head], false, primary_basename, ext) do
    if head.save_kind == @system_save_kind and Map.get(head, :bytes, :present) == :present do
      stem = drop_in_stem(primary_basename)

      %{
        relative: Path.join("saves", "#{stem}.#{ext}"),
        sha256: head.sha256,
        size_bytes: head.size_bytes,
        bytes: :present
      }
    else
      nil
    end
  end

  defp drop_in_stem(primary_basename) do
    {sanitized, _changed?} = primary_basename |> Path.rootname() |> Sanitize.component()

    if Sanitize.reserved_saves_name?(sanitized) do
      "#{sanitized}-save"
    else
      sanitized
    end
  end
end
