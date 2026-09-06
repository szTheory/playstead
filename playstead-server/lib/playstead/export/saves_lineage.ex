defmodule Playstead.Export.SavesLineage do
  @moduledoc """
  Pure branch-key derivation for `Playstead.Export.SavesPlan` (D-58).
  Performs no database call, no filesystem access, and no clock read,
  and never aliases the saves bounded context -- that coupling exists
  only at the `Playstead.Export` context boundary (D-62), never here.

  A revision's branch key is the id of its **fork root**: the nearest
  ancestor-or-self (walking `parent_revision_id` upward) whose own
  parent has more than one child. That id is a fixed, immutable UUID,
  so it is stable across two planning runs and inherited by every
  descendant of the fork -- exactly what makes
  `SavesPlan.assign_branch_letters/1` assign the same letter to the
  same side forever, without ever deriving anything from a device
  name. A revision with no such ancestor sits on shared, pre-fork
  history and its branch key is `nil`.
  """

  @type revision_ref :: %{
          required(:id) => String.t(),
          required(:parent_revision_id) => String.t() | nil,
          required(:recorded_at) => DateTime.t()
        }

  @doc """
  Returns `%{revision_id => branch_key | nil}` for `revisions`. A
  cycle in `parent_revision_id` (which should never occur) is guarded
  against by capping the upward walk at the number of revisions and
  returning `nil` rather than looping.
  """
  @spec branch_keys([revision_ref()]) :: %{String.t() => String.t() | nil}
  def branch_keys(revisions) when is_list(revisions) do
    by_id = Map.new(revisions, &{&1.id, &1})

    child_counts =
      revisions
      |> Enum.reject(&is_nil(&1.parent_revision_id))
      |> Enum.frequencies_by(& &1.parent_revision_id)

    max_steps = length(revisions)

    Map.new(revisions, fn revision ->
      {revision.id, fork_root(revision, by_id, child_counts, max_steps)}
    end)
  end

  defp fork_root(_revision, _by_id, _child_counts, steps_left) when steps_left < 0, do: nil

  defp fork_root(revision, by_id, child_counts, steps_left) do
    parent_id = revision.parent_revision_id
    forked_here? = not is_nil(parent_id) and Map.get(child_counts, parent_id, 0) > 1

    cond do
      forked_here? ->
        revision.id

      is_nil(parent_id) ->
        nil

      true ->
        case Map.fetch(by_id, parent_id) do
          {:ok, parent} -> fork_root(parent, by_id, child_counts, steps_left - 1)
          :error -> nil
        end
    end
  end
end
