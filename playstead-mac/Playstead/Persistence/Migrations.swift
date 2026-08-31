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
    }
}
