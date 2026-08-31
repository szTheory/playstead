defmodule Playstead.Repo.Migrations.AddCurationPositionUniquenessAndOwnershipChecks do
  use Ecto.Migration

  @moduledoc """
  P6-WR-002/P6-WR-003: the original curation migrations left two
  invariants entirely to application code, with no DB-level backstop:

  1. (P6-WR-003) Fractional-index `position` collisions.
     `Position.between/2` is a pure function of its two bounds, so two
     inserts racing against the same neighbour pair could produce two
     rows with an identical `position` string, with nothing in the
     schema to prevent or flag it. `Playstead.Curation` now serializes
     concurrent writers to the same collection/queue behind a
     Postgres advisory lock (see the P5-WR-001/P5-WR-005 fix), which
     should make this unreachable in practice — this migration adds
     the unique index as defense in depth in case that discipline is
     ever bypassed (a future direct-insert path, an admin script, a
     multi-node deployment).

  2. (P6-WR-002) Denormalized `user_id` ownership consistency.
     `curation_collection_members`, `curation_queue_items`,
     `curation_play_sessions`, and `curation_continue_dismissals` each
     carry both a `user_id` and a reference to a resource
     (`asset_set_id`/`collection_id`) that itself belongs to a
     `user_id`, with nothing in the schema enforcing the two agree.
     Postgres has no native composite-FK-to-a-computed-column
     primitive, so this migration adds `CHECK`-backed trigger
     functions that re-verify, on every insert/update, that the row's
     own `user_id` matches the referenced asset_set's/collection's
     owner — a direct-insert path that doesn't replicate the
     application-layer check now fails loudly at the database instead
     of silently attributing another user's asset/collection to the
     wrong owner.
  """

  def up do
    # --- P6-WR-003: unique position constraints ---------------------------
    #
    # Replace the existing non-unique `position` indexes with unique
    # constraints scoped to the same ordering domain each table already
    # uses for its `ORDER BY position` reads. These must be DEFERRABLE
    # INITIALLY DEFERRED (a plain `CREATE UNIQUE INDEX`, which Ecto's
    # `unique_index/3` produces, cannot be deferred): `rebalance_collection/2`
    # /`rebalance_queue/1` reassign every row's position one UPDATE at a
    # time inside a single transaction, and can transiently pass through
    # a state where two rows share a position mid-rebalance even though
    # the final, post-commit state never does. A plain unique index would
    # reject that valid, momentary intermediate state; a deferred
    # constraint checks only once, at commit.
    # Drop the plain (non-unique) indexes the original migrations
    # created before adding a same-named unique constraint — a unique
    # constraint implicitly backs itself with a unique index, so
    # leaving the old one in place would collide on the name.
    drop_if_exists index(:curation_collections, [:user_id, :position])

    execute """
    ALTER TABLE curation_collections
    ADD CONSTRAINT curation_collections_user_id_position_index
    UNIQUE (user_id, position)
    DEFERRABLE INITIALLY DEFERRED
    """

    drop_if_exists index(:curation_collection_members, [:collection_id, :position])

    execute """
    ALTER TABLE curation_collection_members
    ADD CONSTRAINT curation_collection_members_collection_id_position_index
    UNIQUE (collection_id, position)
    DEFERRABLE INITIALLY DEFERRED
    """

    drop_if_exists index(:curation_queue_items, [:user_id, :position])

    execute """
    ALTER TABLE curation_queue_items
    ADD CONSTRAINT curation_queue_items_user_id_position_index
    UNIQUE (user_id, position)
    DEFERRABLE INITIALLY DEFERRED
    """

    # --- P6-WR-002: denormalized user_id ownership consistency -----------
    #
    # A row's own `user_id` must always match the owner of the
    # resource it references. Implemented as `BEFORE INSERT OR UPDATE`
    # triggers (not a `CHECK` constraint, since Postgres `CHECK`
    # cannot reference other tables) that raise if the two disagree.
    execute """
    CREATE OR REPLACE FUNCTION curation_check_collection_member_owner()
    RETURNS trigger AS $$
    BEGIN
      IF NEW.user_id <> (SELECT user_id FROM curation_collections WHERE id = NEW.collection_id) THEN
        RAISE EXCEPTION
          'curation_collection_members.user_id (%) does not match curation_collections.user_id for collection_id %',
          NEW.user_id, NEW.collection_id;
      END IF;
      IF NEW.user_id <> (SELECT user_id FROM asset_sets WHERE id = NEW.asset_set_id) THEN
        RAISE EXCEPTION
          'curation_collection_members.user_id (%) does not match asset_sets.user_id for asset_set_id %',
          NEW.user_id, NEW.asset_set_id;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER curation_collection_members_owner_check
    BEFORE INSERT OR UPDATE ON curation_collection_members
    FOR EACH ROW EXECUTE FUNCTION curation_check_collection_member_owner();
    """

    execute """
    CREATE OR REPLACE FUNCTION curation_check_queue_item_owner()
    RETURNS trigger AS $$
    BEGIN
      IF NEW.user_id <> (SELECT user_id FROM asset_sets WHERE id = NEW.asset_set_id) THEN
        RAISE EXCEPTION
          'curation_queue_items.user_id (%) does not match asset_sets.user_id for asset_set_id %',
          NEW.user_id, NEW.asset_set_id;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER curation_queue_items_owner_check
    BEFORE INSERT OR UPDATE ON curation_queue_items
    FOR EACH ROW EXECUTE FUNCTION curation_check_queue_item_owner();
    """

    execute """
    CREATE OR REPLACE FUNCTION curation_check_play_session_owner()
    RETURNS trigger AS $$
    BEGIN
      IF NEW.user_id <> (SELECT user_id FROM asset_sets WHERE id = NEW.asset_set_id) THEN
        RAISE EXCEPTION
          'curation_play_sessions.user_id (%) does not match asset_sets.user_id for asset_set_id %',
          NEW.user_id, NEW.asset_set_id;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER curation_play_sessions_owner_check
    BEFORE INSERT OR UPDATE ON curation_play_sessions
    FOR EACH ROW EXECUTE FUNCTION curation_check_play_session_owner();
    """

    execute """
    CREATE OR REPLACE FUNCTION curation_check_continue_dismissal_owner()
    RETURNS trigger AS $$
    BEGIN
      IF NEW.user_id <> (SELECT user_id FROM asset_sets WHERE id = NEW.asset_set_id) THEN
        RAISE EXCEPTION
          'curation_continue_dismissals.user_id (%) does not match asset_sets.user_id for asset_set_id %',
          NEW.user_id, NEW.asset_set_id;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER curation_continue_dismissals_owner_check
    BEFORE INSERT OR UPDATE ON curation_continue_dismissals
    FOR EACH ROW EXECUTE FUNCTION curation_check_continue_dismissal_owner();
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS curation_continue_dismissals_owner_check ON curation_continue_dismissals;"
    execute "DROP FUNCTION IF EXISTS curation_check_continue_dismissal_owner();"

    execute "DROP TRIGGER IF EXISTS curation_play_sessions_owner_check ON curation_play_sessions;"
    execute "DROP FUNCTION IF EXISTS curation_check_play_session_owner();"

    execute "DROP TRIGGER IF EXISTS curation_queue_items_owner_check ON curation_queue_items;"
    execute "DROP FUNCTION IF EXISTS curation_check_queue_item_owner();"

    execute "DROP TRIGGER IF EXISTS curation_collection_members_owner_check ON curation_collection_members;"
    execute "DROP FUNCTION IF EXISTS curation_check_collection_member_owner();"

    execute "ALTER TABLE curation_queue_items DROP CONSTRAINT IF EXISTS curation_queue_items_user_id_position_index"
    create index(:curation_queue_items, [:user_id, :position])

    execute "ALTER TABLE curation_collection_members DROP CONSTRAINT IF EXISTS curation_collection_members_collection_id_position_index"
    create index(:curation_collection_members, [:collection_id, :position])

    execute "ALTER TABLE curation_collections DROP CONSTRAINT IF EXISTS curation_collections_user_id_position_index"
    create index(:curation_collections, [:user_id, :position])
  end
end
