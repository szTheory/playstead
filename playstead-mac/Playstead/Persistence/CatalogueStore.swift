import Foundation

/// Reads and writes the `catalogue_entries`/`catalogue_members` tables.
///
/// This is the incremental counterpart to `LocalStore.replaceCatalogue`/
/// `fetchCatalogue` (which the plan 03-03 tracer's `SnapshotClient` still
/// calls directly for its one full-replace bootstrap): `SyncEngine` uses
/// `CatalogueStore` for the entry-at-a-time upsert/tombstone a resumed
/// `/api/v1/changes` page applies, plus a bulk `replaceAll` for the
/// snapshot-bootstrap and cursor-expired-reset paths added in plan 03-06.
/// Every write here is a caller-wrapped statement, not its own
/// transaction — `SyncEngine`/`JournalApplier` wrap a whole page in one
/// `LocalStore.transaction(_:)` so a partially applied page is never
/// observed (T-03-17).
final class CatalogueStore {
    private let localStore: LocalStore

    init(localStore: LocalStore) {
        self.localStore = localStore
    }

    /// Inserts or updates one catalogue entry, keyed by its `id`
    /// (the journal entry's `entity_id`). Replaying the same entry is a
    /// no-op on the resulting row content.
    func upsert(_ entry: CatalogueEntry) throws {
        let tagsData = (try? JSONEncoder().encode(entry.tags)) ?? Data("{}".utf8)
        let tagsJSON = String(data: tagsData, encoding: .utf8) ?? "{}"

        try localStore.connection.execute(
            """
            INSERT INTO catalogue_entries (id, system, display_title, tags_json)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                system = excluded.system,
                display_title = excluded.display_title,
                tags_json = excluded.tags_json;
            """,
            params: [entry.id, entry.system, entry.displayTitle, tagsJSON]
        )

        try localStore.connection.execute(
            "DELETE FROM catalogue_members WHERE asset_set_id = ?;",
            params: [entry.id]
        )
        for member in entry.members {
            try localStore.connection.execute(
                """
                INSERT INTO catalogue_members
                    (asset_set_id, ordinal, role, required, sha256, size, name)
                VALUES (?, ?, ?, ?, ?, ?, ?);
                """,
                params: [
                    entry.id,
                    member.ordinal,
                    member.role,
                    member.required ? 1 : 0,
                    member.sha256,
                    member.size,
                    member.name
                ]
            )
        }
    }

    /// Deletes a catalogue entry (and, via the members table's foreign
    /// key, its members) by `id`. A tombstone for a row that no longer
    /// exists locally is a no-op, not an error — replaying it must be safe.
    func tombstone(id: String) throws {
        try localStore.connection.execute(
            "DELETE FROM catalogue_entries WHERE id = ?;",
            params: [id]
        )
    }

    /// Replaces the entire catalogue mirror with `entries`, inside one
    /// transaction — used for the snapshot bootstrap and the
    /// cursor-expired reset, both of which receive the server's full
    /// current catalogue rather than a delta.
    func replaceAll(_ entries: [CatalogueEntry]) throws {
        try localStore.transaction {
            try localStore.connection.execute("DELETE FROM catalogue_members;")
            try localStore.connection.execute("DELETE FROM catalogue_entries;")
            for entry in entries {
                try self.upsert(entry)
            }
        }
    }

    /// Deletes every catalogue row. Used as part of a cursor-expired
    /// reset, always inside the caller's transaction alongside the
    /// curation tables' `clearAll()`.
    func clearAll() throws {
        try localStore.connection.execute("DELETE FROM catalogue_members;")
        try localStore.connection.execute("DELETE FROM catalogue_entries;")
    }

    /// Reads every persisted catalogue entry, joined with its members,
    /// ordered by display title.
    func fetchAll() -> [CatalogueEntry] {
        localStore.fetchCatalogue()
    }

    /// The current row count — used by tests to assert replay-safety
    /// ("applying the same entry twice leaves the row count … unchanged").
    func count() -> Int {
        let rows = (try? localStore.connection.query(
            "SELECT COUNT(*) FROM catalogue_entries;"
        ) { row -> Int in row.int(0) ?? 0 }) ?? [0]
        return rows.first ?? 0
    }
}
