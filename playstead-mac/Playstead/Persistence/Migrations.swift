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
                tags_json TEXT NOT NULL
            );
            """
        )
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
    }
}
