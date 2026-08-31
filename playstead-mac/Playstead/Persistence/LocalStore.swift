import Foundation

/// The local SQLite mirror of server-canonical state. This tracer plan
/// only mirrors the catalogue branch of `/api/v1/snapshot`: the app
/// renders the library shell from this store, never from a live query,
/// so `LibraryShellView` shows content immediately on every launch and
/// only refreshes it from the network in the background.
final class LocalStore {
    /// Exposed (module-internal) so table-owning stores added in plan
    /// 03-06 (`CatalogueStore`, `CurationStore`, `CursorStore`) can read
    /// and write their own tables directly, and wrap multi-row writes in
    /// `transaction(_:)` below, without `LocalStore` growing a method per
    /// table. `LocalStore` itself owns only migrations and this shared
    /// connection.
    let connection: SQLiteConnection

    init(paths: AppPaths) throws {
        self.connection = try SQLiteConnection(path: paths.databaseURL.path)
        try Migrations.run(on: connection)
    }

    private init(connection: SQLiteConnection) {
        self.connection = connection
    }

    /// Runs `body` inside one `BEGIN`/`COMMIT` transaction, rolling back
    /// on error. `SyncEngine`/`JournalApplier` wrap every page apply in
    /// this so a partially applied page can never be observed (T-03-17).
    func transaction(_ body: () throws -> Void) throws {
        try connection.transaction(body)
    }

    /// An in-memory store used only if the on-disk store somehow fails to
    /// open (e.g. an unwritable Application Support directory) — the app
    /// still launches and shows an empty library rather than crashing.
    static func inMemoryFallback() -> LocalStore {
        let connection = (try? SQLiteConnection(path: ":memory:"))!
        try? Migrations.run(on: connection)
        return LocalStore(connection: connection)
    }

    /// Replaces the entire catalogue mirror with `entries`, inside one
    /// transaction. A full replace (rather than a diff) is correct here
    /// because `/api/v1/snapshot`'s `catalogue` branch is itself a full
    /// as-of-cursor snapshot, not an incremental delta.
    func replaceCatalogue(_ entries: [CatalogueEntry]) throws {
        try connection.transaction {
            try connection.execute("DELETE FROM catalogue_members;")
            try connection.execute("DELETE FROM catalogue_entries;")

            for entry in entries {
                let tagsData = (try? JSONEncoder().encode(entry.tags)) ?? Data("{}".utf8)
                let tagsJSON = String(data: tagsData, encoding: .utf8) ?? "{}"

                try connection.execute(
                    "INSERT INTO catalogue_entries (id, system, display_title, tags_json) VALUES (?, ?, ?, ?);",
                    params: [entry.id, entry.system, entry.displayTitle, tagsJSON]
                )

                for member in entry.members {
                    try connection.execute(
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
        }
    }

    /// Reads every persisted catalogue entry, joined with its members,
    /// ordered by display title.
    func fetchCatalogue() -> [CatalogueEntry] {
        let entryRows = (try? connection.query(
            "SELECT id, system, display_title, tags_json FROM catalogue_entries ORDER BY display_title ASC;"
        ) { row -> (id: String, system: String, title: String, tagsJSON: String) in
            (row.string(0) ?? "", row.string(1) ?? "", row.string(2) ?? "", row.string(3) ?? "{}")
        }) ?? []

        return entryRows.map { row in
            let members = fetchMembers(forAssetSetID: row.id)
            let tags = (try? JSONDecoder().decode([String: String].self, from: Data(row.tagsJSON.utf8))) ?? [:]
            return CatalogueEntry(id: row.id, system: row.system, displayTitle: row.title, tags: tags, members: members)
        }
    }

    private func fetchMembers(forAssetSetID id: String) -> [AssetMember] {
        (try? connection.query(
            """
            SELECT ordinal, role, required, sha256, size, name
            FROM catalogue_members WHERE asset_set_id = ? ORDER BY ordinal ASC;
            """,
            params: [id]
        ) { row -> AssetMember in
            AssetMember(
                ordinal: row.int(0) ?? 0,
                role: row.string(1) ?? "",
                required: (row.int(2) ?? 0) != 0,
                sha256: row.string(3),
                size: row.int(4),
                name: row.string(5)
            )
        }) ?? []
    }
}
