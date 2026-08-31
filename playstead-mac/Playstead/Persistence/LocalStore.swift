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
    ///
    /// This is the app's last-resort safety net, so an in-memory open
    /// failure (e.g. under extreme memory pressure — the exact condition
    /// most likely to be present if we've already fallen back here) must
    /// never surface as a silent, unexplained force-unwrap trap
    /// (P1-WR-003). If SQLite genuinely cannot even open `:memory:`, the
    /// app has no viable persistence path left; `fatalError` at least
    /// crashes with a clear, diagnosable message instead of an opaque
    /// `Fatal error: Unexpectedly found nil`.
    static func inMemoryFallback() -> LocalStore {
        guard let connection = try? SQLiteConnection(path: ":memory:") else {
            fatalError("LocalStore.inMemoryFallback: SQLite could not open an in-memory database; no persistence path is available.")
        }
        try? Migrations.run(on: connection)
        return LocalStore(connection: connection)
    }

    /// Replaces the entire catalogue mirror with `entries`, inside one
    /// transaction. A full replace (rather than a diff) is correct here
    /// because `/api/v1/snapshot`'s `catalogue` branch is itself a full
    /// as-of-cursor snapshot, not an incremental delta.
    ///
    /// Delegates to `CatalogueStore.replaceAll`, which populates
    /// `search_blob` via `upsert` — this used to be a second, divergent
    /// insert implementation that never touched `search_blob`, leaving it
    /// at its column-default `''` for every snapshot-bootstrapped entry
    /// and silently breaking `CatalogueStore.filteredQuery`'s search until
    /// the next real `upsert` (P1-IN-002).
    func replaceCatalogue(_ entries: [CatalogueEntry]) throws {
        try CatalogueStore(localStore: self).replaceAll(entries)
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
