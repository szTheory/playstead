import Foundation

/// Owns the local SQLite schema. Originally just the flat catalogue
/// mirror; plan 03-06 adds the sync cursor and the six curation tables
/// mirroring the server's `curation` journal payload shapes
/// (`Playstead.Sync.CurationPayload`) so `SyncEngine`/`JournalApplier`
/// have somewhere to converge curation entries. Later plans extend this
/// further without touching this file's shape beyond appending new
/// `CREATE TABLE IF NOT EXISTS` statements.
enum Migrations {
    static func run(on connection: SQLiteConnection) throws {
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS catalogue_entries (
                id TEXT PRIMARY KEY,
                system TEXT NOT NULL,
                display_title TEXT NOT NULL,
                tags_json TEXT NOT NULL,
                search_blob TEXT NOT NULL DEFAULT '',
                availability TEXT NOT NULL DEFAULT 'server_only'
            );
            """
        )
        // Defensive column adds for a pre-03-06 dev database that already
        // has `catalogue_entries` without these columns — `CREATE TABLE
        // IF NOT EXISTS` above is a no-op against an existing table, so
        // these idempotent-via-try? ALTERs are what actually upgrades it.
        // A brand new database already has both columns from the CREATE
        // TABLE above; these simply no-op (duplicate-column error,
        // swallowed) in that case.
        try? connection.execute("ALTER TABLE catalogue_entries ADD COLUMN search_blob TEXT NOT NULL DEFAULT '';")
        try? connection.execute("ALTER TABLE catalogue_entries ADD COLUMN availability TEXT NOT NULL DEFAULT 'server_only';")
        try connection.execute("CREATE INDEX IF NOT EXISTS idx_catalogue_entries_search_blob ON catalogue_entries(search_blob);")
        try connection.execute("CREATE INDEX IF NOT EXISTS idx_catalogue_entries_system ON catalogue_entries(system);")
        try connection.execute("CREATE INDEX IF NOT EXISTS idx_catalogue_entries_availability ON catalogue_entries(availability);")
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS catalogue_members (
                asset_set_id TEXT NOT NULL,
                ordinal INTEGER NOT NULL,
                role TEXT NOT NULL,
                required INTEGER NOT NULL,
                sha256 TEXT,
                size INTEGER,
                name TEXT,
                PRIMARY KEY (asset_set_id, ordinal),
                FOREIGN KEY (asset_set_id) REFERENCES catalogue_entries(id) ON DELETE CASCADE
            );
            """
        )

        // Single-row table (id is always 1) holding the opaque,
        // server-signed sync cursor verbatim plus the last successful
        // sync timestamp. Absence of a row means "never synced".
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS sync_cursor (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                cursor TEXT NOT NULL,
                last_synced_at TEXT NOT NULL
            );
            """
        )

        // The six curation tables, one per `Playstead.Sync.CurationPayload`
        // inner `type`. Each row's primary key is the row's own server id
        // (the journal entry's `entity_id`) except `curation_recent`,
        // whose entity_id (and payload) is the game's asset_set_id itself
        // (Playstead.Curation.journal_recent/2) rather than a distinct row id.
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS curation_favorites (
                id TEXT PRIMARY KEY,
                asset_set_id TEXT NOT NULL,
                created_at TEXT
            );
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS curation_collections (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                created_at TEXT,
                updated_at TEXT
            );
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS curation_collection_members (
                id TEXT PRIMARY KEY,
                collection_id TEXT NOT NULL,
                asset_set_id TEXT NOT NULL,
                position TEXT NOT NULL,
                added_at TEXT
            );
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS curation_queue_items (
                id TEXT PRIMARY KEY,
                asset_set_id TEXT NOT NULL,
                position TEXT NOT NULL,
                added_at TEXT
            );
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS curation_continue_dismissals (
                id TEXT PRIMARY KEY,
                asset_set_id TEXT NOT NULL
            );
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS curation_recent (
                asset_set_id TEXT PRIMARY KEY,
                last_played_at TEXT
            );
            """
        )

        // Plan 03-07: the persistent, user-visible download queue and the
        // committed-cache-object verify facts `AvailabilityState.derive(_:)`
        // reads at render time. `state` is the ONLY availability-shaped
        // column anywhere in this schema — its permitted values (waiting,
        // active, paused, cancelled) describe *transfer* progress, never
        // one of the six read-time-derived availability names
        // (server-only/queued/partial/verified-local/pinned-offline/
        // safe-to-evict). A unique index on (asset_set_id, sha256) is what
        // makes `DownloadQueue.enqueue` idempotent per member: a repeated
        // enqueue converges onto the existing row rather than duplicating
        // it. `position` is a fractional (lexicographically-ordered)
        // string (see `FractionalIndex`), so `DownloadQueue.reorder` can
        // move one row without renumbering its neighbors.
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS download_queue_items (
                id TEXT PRIMARY KEY,
                asset_set_id TEXT NOT NULL,
                sha256 TEXT NOT NULL,
                size INTEGER NOT NULL,
                position TEXT NOT NULL,
                state TEXT NOT NULL DEFAULT 'waiting',
                attempt_count INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                UNIQUE(asset_set_id, sha256)
            );
            """
        )
        try connection.execute("CREATE INDEX IF NOT EXISTS idx_download_queue_items_position ON download_queue_items(position);")
        try connection.execute("CREATE INDEX IF NOT EXISTS idx_download_queue_items_state ON download_queue_items(state);")
        try connection.execute("CREATE INDEX IF NOT EXISTS idx_download_queue_items_asset_set ON download_queue_items(asset_set_id);")

        // Mirrors `CASManager`'s on-disk verify index inside SQLite so
        // `AvailabilityState.derive(_:)` and `EvictionPlanner` can query
        // "which members are cached" and "when was this object last used"
        // with one indexed SQL statement instead of a filesystem walk.
        // `CASManager` remains the source of truth for the bytes
        // themselves and the cheap-verify record; this table is a queryable
        // index over that same fact set, kept in sync by
        // `DownloadCoordinator` on every commit.
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS cache_objects (
                sha256 TEXT PRIMARY KEY,
                size INTEGER NOT NULL,
                committed_at TEXT NOT NULL,
                last_used_at TEXT NOT NULL,
                verify_size INTEGER NOT NULL,
                verify_inode INTEGER NOT NULL,
                verify_mtime_ms INTEGER NOT NULL
            );
            """
        )
        try connection.execute("CREATE INDEX IF NOT EXISTS idx_cache_objects_last_used ON cache_objects(last_used_at);")

        // Plan 03-07 task 2: capacity policy. Single-row table (id is
        // always 1); absence of a row means "use the default policy"
        // (25 GiB quota, 10 GiB floor) — `QuotaManager` inserts the
        // default row lazily on first read rather than requiring a
        // migration-time default, so raising/lowering the quota is a
        // plain UPDATE with no upsert-vs-insert ambiguity.
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS quota_policy (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                quota_bytes INTEGER NOT NULL,
                floor_bytes INTEGER NOT NULL
            );
            """
        )

        // One row per pinned asset set. Presence alone is the pin flag —
        // `PinStore` never stores a boolean column; a pin is either a row
        // or it isn't.
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS pins (
                asset_set_id TEXT PRIMARY KEY,
                pinned_at TEXT NOT NULL
            );
            """
        )

        // Plan 03-08: the durable outbox for every offline curation
        // mutation (D-20's natural-key + idempotency-key mechanism,
        // unchanged from Phase 1). `payload_json` is the intent's own
        // envelope (`CurationIntentEnvelope`), not just its wire body —
        // `OutboxWorker` needs the full intent (method/path/localRowID)
        // to send and, on permanent rejection, to revert. A row survives
        // across app restarts by construction (this is on-disk SQLite,
        // not an in-memory queue) — `OutboxWorker` drains whatever is
        // `pending` on every launch, satisfying the "the favorite
        // persists across an application restart while still unsent"
        // behavior with no special-cased persistence path.
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS outbox_entries (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                idempotency_key TEXT NOT NULL,
                state TEXT NOT NULL DEFAULT 'pending',
                attempt_count INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL,
                last_error_code TEXT,
                next_retry_at TEXT
            );
            """
        )
        // Defensive column add for a pre-P4-CR-003 dev database whose
        // outbox_entries already exists without this column (see the
        // catalogue_entries precedent above) — a brand new database
        // already has it from the CREATE TABLE above.
        try? connection.execute("ALTER TABLE outbox_entries ADD COLUMN next_retry_at TEXT;")
        try connection.execute("CREATE INDEX IF NOT EXISTS idx_outbox_entries_state ON outbox_entries(state);")
        try connection.execute("CREATE INDEX IF NOT EXISTS idx_outbox_entries_created_at ON outbox_entries(created_at);")

        // Plan 03-08 task 3: coarse play sessions recorded locally by
        // `PlaySessionRecorder`, delivered through the outbox after the
        // fact. Kept in its own table (distinct from `outbox_entries`,
        // whose rows are deleted once delivered) because the user must
        // be able to see and delete BOTH pending and already-delivered
        // sessions from the Recent shelf — `delivered` is the only
        // status this table needs, never a full transfer-state ladder.
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS play_sessions_pending (
                id TEXT PRIMARY KEY,
                asset_set_id TEXT NOT NULL,
                started_at TEXT NOT NULL,
                ended_at TEXT,
                delivered INTEGER NOT NULL DEFAULT 0
            );
            """
        )
        try connection.execute("CREATE INDEX IF NOT EXISTS idx_play_sessions_pending_delivered ON play_sessions_pending(delivered);")

        // Plan 03-09 task 1: one row per (emulator, version) the app has
        // either downloaded or the user has selected. `verified`
        // (0/1) records whether `executable_path`'s own computed digest
        // matched the pin at record time — a mismatched selection is
        // still recorded (never rejected), so the interface can label it
        // honestly rather than silently accepting or refusing it.
        // `UNIQUE(emulator, version)` is what makes install idempotent:
        // a repeat or concurrent install converges onto this one row.
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS adapter_installations (
                id TEXT PRIMARY KEY,
                emulator TEXT NOT NULL,
                version TEXT NOT NULL,
                executable_path TEXT NOT NULL,
                sha256 TEXT NOT NULL,
                archive_sha256 TEXT,
                provenance TEXT NOT NULL DEFAULT 'pinnedRelease',
                verified INTEGER NOT NULL,
                installed_at TEXT NOT NULL,
                UNIQUE(emulator, version)
            );
            """
        )
        // `sha256` on this table is the *expanded executable's* digest —
        // the baseline every launch re-hashes against. `archive_sha256`
        // is the separate digest of the downloaded release archive, the
        // only value ever compared against `AdapterPin.sha256`, and it is
        // NULL for a user-selected installation that never had an
        // archive. The two are deliberately distinct columns because they
        // are different byte streams (see `AdapterInstallation`).
        // Idempotent ALTERs upgrade a pre-existing dev database; they
        // no-op (duplicate column, swallowed) on a fresh one.
        try? connection.execute("ALTER TABLE adapter_installations ADD COLUMN archive_sha256 TEXT;")
        try? connection.execute("ALTER TABLE adapter_installations ADD COLUMN provenance TEXT NOT NULL DEFAULT 'pinnedRelease';")

        // Plan 03-09 task 2: one row per accepted, digest-validated BIOS
        // file copied into managed storage. `managed_filename` is derived
        // from the digest, never the dropped filename (see
        // `BiosStore`'s doc comment) — the original dropped file is never
        // referenced from this table.
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS bios_files (
                sha256 TEXT PRIMARY KEY,
                system TEXT NOT NULL,
                byte_length INTEGER NOT NULL,
                managed_filename TEXT NOT NULL,
                accepted_at TEXT NOT NULL
            );
            """
        )
        try connection.execute("CREATE INDEX IF NOT EXISTS idx_bios_files_system ON bios_files(system);")

        // Plan 03-10 task 1: one row per controller (keyed by its own
        // stable product identifier), holding that controller's full
        // remap as a JSON array of `MappedInput`. Keying by the
        // controller rather than a single global row is what makes a
        // user's remap follow their specific controller — plugging in a
        // different controller gets its own (initially default) mapping,
        // never the first controller's remap by accident.
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS controller_mappings (
                controller_product_id TEXT PRIMARY KEY,
                mappings_json TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """
        )

        // Plan 04-04 task 1: the local mirror of the server's save-line
        // identity tuple (D-10). `id` mirrors the server's `save_lines.id`
        // once known (assigned locally as a client-generated placeholder
        // the first time a line is created, and never re-keyed once the
        // server converges it -- see `SaveStore`'s doc comment).
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS save_line (
                id TEXT PRIMARY KEY,
                content_key TEXT NOT NULL,
                save_kind TEXT NOT NULL DEFAULT 'battery',
                slot TEXT NOT NULL DEFAULT '0',
                UNIQUE(content_key, save_kind, slot)
            );
            """
        )

        // One row per captured/uploaded revision. `durability` is a
        // distinct axis from `current`/`restored`/`conflicted` (D-35) --
        // this column never grows those other states; they are handled
        // in plan 04-09. `parent_revision_id` mirrors the server's
        // parent-pointer DAG (D-09); NULL means root.
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS save_revision (
                id TEXT PRIMARY KEY,
                save_line_id TEXT NOT NULL,
                parent_revision_id TEXT,
                blob_sha256 TEXT NOT NULL,
                size_bytes INTEGER NOT NULL,
                origin_device_id TEXT,
                device_captured_at TEXT,
                recorded_at TEXT,
                capture_method TEXT,
                adapter_id TEXT,
                adapter_version TEXT,
                save_format TEXT,
                format_confidence TEXT,
                play_session_id TEXT,
                durability TEXT NOT NULL DEFAULT 'localOnly',
                local_path TEXT,
                tier TEXT NOT NULL DEFAULT 'promoted',
                origin TEXT NOT NULL DEFAULT 'session',
                manifest_digest TEXT,
                session_id TEXT,
                artifact_set_json TEXT,
                FOREIGN KEY (save_line_id) REFERENCES save_line(id) ON DELETE CASCADE
            );
            """
        )
        // Plan 04-06 task 1: D-04's tier/origin discriminator, D-08's
        // manifest digest and JSON manifest, and the session grouping key
        // -- defensive ALTERs for a pre-04-06 dev database whose
        // save_revision already exists without these columns (see the
        // catalogue_entries precedent above). A brand new database
        // already has all five from the CREATE TABLE above; these no-op
        // (duplicate column, swallowed) in that case. `tier` defaults to
        // 'promoted' and `origin` to 'session' so any row created under
        // 04-04's pre-tier semantics (every capture was, in effect, an
        // immediately promoted revision) reads as exactly that under the
        // new model, with no backfill required.
        try? connection.execute("ALTER TABLE save_revision ADD COLUMN tier TEXT NOT NULL DEFAULT 'promoted';")
        try? connection.execute("ALTER TABLE save_revision ADD COLUMN origin TEXT NOT NULL DEFAULT 'session';")
        try? connection.execute("ALTER TABLE save_revision ADD COLUMN manifest_digest TEXT;")
        // Plan 04-22 task 1: D-35's restored-here provenance column --
        // NULL means "never restored on this Mac"; once set it is never
        // cleared or overwritten (SaveStore.markRestoredHere's own
        // `WHERE restored_here_at IS NULL` guard is what makes that
        // true in storage, not just in SaveStateModel's helper).
        // Additive ALTER, same no-op-on-duplicate-column shape as the
        // columns above, so an existing install upgrades without a
        // table rebuild.
        try? connection.execute("ALTER TABLE save_revision ADD COLUMN restored_here_at TEXT;")
        try? connection.execute("ALTER TABLE save_revision ADD COLUMN session_id TEXT;")
        try? connection.execute("ALTER TABLE save_revision ADD COLUMN artifact_set_json TEXT;")
        try connection.execute("CREATE INDEX IF NOT EXISTS idx_save_revision_line ON save_revision(save_line_id, parent_revision_id);")
        try connection.execute("CREATE INDEX IF NOT EXISTS idx_save_revision_durability ON save_revision(durability);")
        try connection.execute("CREATE INDEX IF NOT EXISTS idx_save_revision_session ON save_revision(session_id);")

        // Plan 04-06 task 2: durable blocked-capture rows (D-31). One row
        // per distinct blockage; `resolved_at IS NULL` means the
        // blockage is still active (retried on every poll cycle) and is
        // what makes the "raise exactly one alert per distinct blockage"
        // rule enforceable -- a second failure for the same still-open
        // blockage updates this row's `last_failed_at`/`failure_count`
        // rather than inserting a second row or re-alerting.
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS save_capture_blocked (
                id TEXT PRIMARY KEY,
                save_line_id TEXT NOT NULL,
                session_id TEXT,
                digest TEXT,
                reason TEXT NOT NULL,
                first_failed_at TEXT NOT NULL,
                last_failed_at TEXT NOT NULL,
                failure_count INTEGER NOT NULL DEFAULT 1,
                alerted INTEGER NOT NULL DEFAULT 0,
                resolved_at TEXT
            );
            """
        )
        try connection.execute("CREATE INDEX IF NOT EXISTS idx_save_capture_blocked_line ON save_capture_blocked(save_line_id, resolved_at);")

        // Plan 04-11 task 3: the local, append-only-in-spirit record of
        // how a save line's fork was last disposed (`SaveConflictResolver`).
        // One row per line (upserted) recording the exact sorted head-id
        // set that was disposed and how -- `SaveAttentionSource` compares
        // a line's *current* head set against this row's `head_ids_json`
        // to decide whether a fork is still "needing a decision" (D-52's
        // exact-match rule, mirrored from the server's
        // `fork_acknowledged?/3`). Choosing the other side later, or a
        // fresh divergence on a *different* head set, is a legitimate new
        // disposition, never suppressed by this row.
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS save_fork_dispositions (
                save_line_id TEXT PRIMARY KEY,
                head_ids_json TEXT NOT NULL,
                action TEXT NOT NULL,
                chosen_revision_id TEXT,
                disposed_at TEXT NOT NULL
            );
            """
        )

        // Plan 04-11 task 3: the durable outbox for save-resolution
        // intents (choose-side, acknowledge-fork). A separate table from
        // `outbox_entries` -- distinct kind vocabulary
        // (`SaveIntentKind`), distinct envelope shape, and a distinct
        // consumer (`SaveOutbox.drainOnce`, never `OutboxWorker`) -- but
        // the identical durability discipline: `SaveOutbox.enqueue`
        // writes the local mutation and this row in one transaction, so
        // a crash between them can never lose the entry.
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS save_outbox_entries (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                idempotency_key TEXT NOT NULL,
                attempt_count INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL
            );
            """
        )
        try connection.execute("CREATE INDEX IF NOT EXISTS idx_save_outbox_entries_created_at ON save_outbox_entries(created_at);")
    }
}
