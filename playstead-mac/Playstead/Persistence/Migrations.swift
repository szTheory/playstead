import Foundation

/// Owns the local SQLite schema. This tracer plan needs exactly two
/// tables: a flat mirror of the server's catalogue snapshot and its
/// members. Later plans extend this with the download queue, curation
/// mirror, and verify-record tables without touching this file's shape
/// beyond appending new `CREATE TABLE IF NOT EXISTS` statements.
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
    }
}
