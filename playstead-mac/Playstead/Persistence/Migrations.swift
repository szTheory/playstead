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
                last_error_code TEXT
            );
            """
        )
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
                verified INTEGER NOT NULL,
                installed_at TEXT NOT NULL,
                UNIQUE(emulator, version)
            );
            """
        )

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
    }
}
