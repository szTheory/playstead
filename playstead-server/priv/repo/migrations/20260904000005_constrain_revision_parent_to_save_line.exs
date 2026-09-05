defmodule Playstead.Repo.Migrations.ConstrainRevisionParentToSaveLine do
  use Ecto.Migration

  # CR-01 (04-REVIEW-server.md): `resolve_parent/2` now scopes a
  # submitted `parent_revision_id` to the save line being committed to,
  # not merely to the calling user -- but application code is not a
  # backstop, it is a single point of failure the next call site can
  # forget. This migration makes a cross-save-line parent link
  # unrepresentable in the schema itself:
  #
  #   1. A unique index on `save_revisions (id, save_line_id)` --
  #      redundant on its own (`id` is already the primary key), but it
  #      makes the pair a referenceable composite key.
  #   2. The plain single-column FK on `parent_revision_id` is replaced
  #      with a composite FK on `(parent_revision_id, save_line_id)`
  #      referencing `save_revisions (id, save_line_id)`. Postgres's
  #      default MATCH SIMPLE semantics mean a NULL `parent_revision_id`
  #      (a line's first/root revision) still satisfies the constraint
  #      trivially, exactly as today.
  #
  # `ON DELETE` intentionally changes from the original single-column
  # `nilify_all` to the default `NO ACTION`: a composite FK with
  # `SET NULL` would null out *every* local column on delete, including
  # `save_line_id`, which is `NOT NULL` -- that combination cannot work.
  # This is safe because nothing in this codebase deletes an individual
  # revision; the only delete path is `save_lines`' own
  # `on_delete: :delete_all` cascade, which removes every revision on a
  # line -- parent and child -- in the same statement, so by the time
  # FK constraints are checked at the end of that statement no dangling
  # reference exists to trip NO ACTION.
  #
  # History is append-only (D-09/D-11): this migration never rewrites
  # or drops an existing revision row. If any pre-existing row already
  # violates the rule this migration is about to enforce, that is
  # reported loudly and the migration aborts -- a human decides, this
  # migration does not silently repair or drop.
  def up do
    violations =
      repo().query!("""
      SELECT r.id, r.save_line_id, r.parent_revision_id, p.save_line_id AS parent_save_line_id
      FROM save_revisions r
      JOIN save_revisions p ON p.id = r.parent_revision_id
      WHERE r.save_line_id <> p.save_line_id
      """).rows

    if violations != [] do
      raise """
      Refusing to add the same-save-line parent constraint: #{length(violations)} \
      existing save_revisions row(s) already have a parent_revision_id pointing at a \
      different save line. History is append-only -- these rows cannot be silently \
      repaired or dropped by a migration. Investigate and resolve manually before \
      re-running this migration.

      Violating rows (revision_id, revision_save_line_id, parent_revision_id, parent_save_line_id):
      #{Enum.map_join(violations, "\n", &inspect/1)}
      """
    end

    create unique_index(:save_revisions, [:id, :save_line_id])

    execute "ALTER TABLE save_revisions DROP CONSTRAINT save_revisions_parent_revision_id_fkey"

    execute """
    ALTER TABLE save_revisions
    ADD CONSTRAINT save_revisions_parent_revision_id_save_line_id_fkey
    FOREIGN KEY (parent_revision_id, save_line_id)
    REFERENCES save_revisions (id, save_line_id)
    """
  end

  def down do
    execute "ALTER TABLE save_revisions DROP CONSTRAINT save_revisions_parent_revision_id_save_line_id_fkey"

    execute """
    ALTER TABLE save_revisions
    ADD CONSTRAINT save_revisions_parent_revision_id_fkey
    FOREIGN KEY (parent_revision_id) REFERENCES save_revisions (id) ON DELETE SET NULL
    """

    drop_if_exists unique_index(:save_revisions, [:id, :save_line_id])
  end
end
