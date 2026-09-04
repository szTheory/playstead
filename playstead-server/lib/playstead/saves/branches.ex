defmodule Playstead.Saves.Branches do
  @moduledoc """
  Derives branch heads for a save line (D-14): revisions with no
  children. There is no stored "head" pointer anywhere -- a head is
  computed, every time, from the DAG itself, which is exactly what
  makes D-14's rule -- no side is ever chosen for the user by any
  server rule, deterministic or heuristic -- true by construction
  rather than by convention.

  A child reference comes from either `Revision.parent_revision_id`
  (the ordinary single-parent case) or a `role: "chosen"` `RevisionParent`
  row -- a head is a revision named as a parent by neither. A
  `role: "acknowledged"` row (D-48, D-52) is deliberately excluded from
  this retirement: it is audit trail for a resolution's *other*
  divergent heads, which stay heads (a live "Continue from this one"
  affordance, D-49) precisely because a resolution only truly extends
  its one chosen parent, the same way any ordinary child revision
  retires only its own single parent.

  Every query here reads through `Playstead.Repo`, so when a caller
  already has an open transaction (e.g. `Saves.commit_revision/3`'s
  `Repo.transaction/1` block), these reads participate in that same
  transaction and are never a torn mix of before and after a
  concurrent commit.
  """

  import Ecto.Query, warn: false

  alias Playstead.Repo
  alias Playstead.Saves.{Revision, RevisionParent}

  @doc """
  The revisions on `save_line_id` (scoped to `user_id`) that have no
  children, ordered by server `recorded_at` -- never `:id` or
  `inserted_at`, and never a device-claimed time (D-15). A line with
  no revisions returns an empty list.
  """
  @spec heads(pos_integer(), binary()) :: [Revision.t()]
  def heads(user_id, save_line_id) do
    child_ids = referenced_parent_ids(user_id, save_line_id)

    base_query =
      from(r in Revision,
        where: r.user_id == ^user_id and r.save_line_id == ^save_line_id,
        order_by: [asc: r.recorded_at]
      )

    query =
      if child_ids == [] do
        base_query
      else
        from(r in base_query, where: r.id not in ^child_ids)
      end

    Repo.all(query)
  end

  @doc "Whether `save_line_id` currently has more than one head."
  @spec diverged?(pos_integer(), binary()) :: boolean()
  def diverged?(user_id, save_line_id) do
    length(heads(user_id, save_line_id)) > 1
  end

  # Every revision id referenced as *someone's* parent on this line,
  # from either the single-parent column or the multi-parent join
  # table -- the complement of this set (within the line's revisions)
  # is exactly the head set.
  defp referenced_parent_ids(user_id, save_line_id) do
    from_column =
      from(r in Revision,
        where:
          r.user_id == ^user_id and r.save_line_id == ^save_line_id and
            not is_nil(r.parent_revision_id),
        select: r.parent_revision_id
      )
      |> Repo.all()

    from_join =
      from(rp in RevisionParent,
        join: r in Revision,
        on: r.id == rp.revision_id,
        where:
          r.user_id == ^user_id and r.save_line_id == ^save_line_id and rp.role == "chosen",
        select: rp.parent_revision_id
      )
      |> Repo.all()

    Enum.uniq(from_column ++ from_join)
  end
end
