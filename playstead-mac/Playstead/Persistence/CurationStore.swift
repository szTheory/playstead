import Foundation

/// One row from any of the six `curation_*` tables, in the shape
/// `JournalApplier` decodes from a `curation` journal entry's payload
/// (`Playstead.Sync.CurationPayload.build/1`'s six `type` clauses).
struct CurationFavoriteRow: Equatable {
    let id: String
    let assetSetID: String
    let createdAt: String?
}

struct CurationCollectionRow: Equatable {
    let id: String
    let name: String
    let createdAt: String?
    let updatedAt: String?
}

struct CurationCollectionMemberRow: Equatable {
    let id: String
    let collectionID: String
    let assetSetID: String
    let position: String
    let addedAt: String?
}

struct CurationQueueItemRow: Equatable {
    let id: String
    let assetSetID: String
    let position: String
    let addedAt: String?
}

struct CurationContinueDismissalRow: Equatable {
    let id: String
    let assetSetID: String
}

struct CurationRecentRow: Equatable {
    let assetSetID: String
    let lastPlayedAt: String?
}

/// Reads and writes the six `curation_*` tables. Mirrors `CatalogueStore`'s
/// shape: one upsert/tombstone pair per row kind, keyed by the journal
/// entry's `entity_id` (the row's own server id — except `recent`, whose
/// entity_id is the game's `asset_set_id` itself, per
/// `Playstead.Sync.CurationPayload`'s doc comment). Every write is a
/// caller-wrapped statement; `SyncEngine`/`JournalApplier` wrap a whole
/// applied page in one `LocalStore.transaction(_:)`.
final class CurationStore {
    private let localStore: LocalStore

    init(localStore: LocalStore) {
        self.localStore = localStore
    }

    // MARK: - Favorite

    func upsertFavorite(id: String, assetSetID: String, createdAt: String?) throws {
        try localStore.connection.execute(
            """
            INSERT INTO curation_favorites (id, asset_set_id, created_at)
            VALUES (?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                asset_set_id = excluded.asset_set_id,
                created_at = excluded.created_at;
            """,
            params: [id, assetSetID, createdAt]
        )
    }

    func tombstoneFavorite(id: String) throws {
        try localStore.connection.execute("DELETE FROM curation_favorites WHERE id = ?;", params: [id])
    }

    func fetchFavorites() -> [CurationFavoriteRow] {
        (try? localStore.connection.query(
            "SELECT id, asset_set_id, created_at FROM curation_favorites ORDER BY id ASC;"
        ) { row in
            CurationFavoriteRow(id: row.string(0) ?? "", assetSetID: row.string(1) ?? "", createdAt: row.string(2))
        }) ?? []
    }

    // MARK: - Collection

    func upsertCollection(id: String, name: String, createdAt: String?, updatedAt: String?) throws {
        try localStore.connection.execute(
            """
            INSERT INTO curation_collections (id, name, created_at, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at;
            """,
            params: [id, name, createdAt, updatedAt]
        )
    }

    func tombstoneCollection(id: String) throws {
        try localStore.connection.execute("DELETE FROM curation_collections WHERE id = ?;", params: [id])
    }

    /// A targeted UPDATE (plan 03-08 task 2) rather than a full upsert —
    /// a plain re-`upsertCollection` would clobber `created_at` since
    /// the caller applying an optimistic rename never knows the row's
    /// original creation timestamp.
    func renameCollection(id: String, name: String, updatedAt: String?) throws {
        try localStore.connection.execute(
            "UPDATE curation_collections SET name = ?, updated_at = ? WHERE id = ?;",
            params: [name, updatedAt, id]
        )
    }

    func fetchCollections() -> [CurationCollectionRow] {
        (try? localStore.connection.query(
            "SELECT id, name, created_at, updated_at FROM curation_collections ORDER BY id ASC;"
        ) { row in
            CurationCollectionRow(
                id: row.string(0) ?? "",
                name: row.string(1) ?? "",
                createdAt: row.string(2),
                updatedAt: row.string(3)
            )
        }) ?? []
    }

    // MARK: - Collection member

    func upsertCollectionMember(id: String, collectionID: String, assetSetID: String, position: String, addedAt: String?) throws {
        try localStore.connection.execute(
            """
            INSERT INTO curation_collection_members (id, collection_id, asset_set_id, position, added_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                collection_id = excluded.collection_id,
                asset_set_id = excluded.asset_set_id,
                position = excluded.position,
                added_at = excluded.added_at;
            """,
            params: [id, collectionID, assetSetID, position, addedAt]
        )
    }

    func tombstoneCollectionMember(id: String) throws {
        try localStore.connection.execute("DELETE FROM curation_collection_members WHERE id = ?;", params: [id])
    }

    /// Deletes every member of `collectionID` — used as part of a
    /// collection's optimistic local delete (its members have no
    /// meaning once the collection itself is gone locally).
    func tombstoneCollectionMembersByCollection(_ collectionID: String) throws {
        try localStore.connection.execute(
            "DELETE FROM curation_collection_members WHERE collection_id = ?;", params: [collectionID]
        )
    }

    /// A targeted UPDATE for a move-shaped intent's optimistic
    /// reposition — never touches `collection_id`/`asset_set_id`.
    func updateCollectionMemberPosition(id: String, position: String) throws {
        try localStore.connection.execute(
            "UPDATE curation_collection_members SET position = ? WHERE id = ?;", params: [position, id]
        )
    }

    func fetchCollectionMember(id: String) -> CurationCollectionMemberRow? {
        (try? localStore.connection.query(
            "SELECT id, collection_id, asset_set_id, position, added_at FROM curation_collection_members WHERE id = ?;",
            params: [id]
        ) { row in
            CurationCollectionMemberRow(
                id: row.string(0) ?? "",
                collectionID: row.string(1) ?? "",
                assetSetID: row.string(2) ?? "",
                position: row.string(3) ?? "",
                addedAt: row.string(4)
            )
        })?.first
    }

    func fetchCollectionMembers() -> [CurationCollectionMemberRow] {
        (try? localStore.connection.query(
            "SELECT id, collection_id, asset_set_id, position, added_at FROM curation_collection_members ORDER BY position ASC;"
        ) { row in
            CurationCollectionMemberRow(
                id: row.string(0) ?? "",
                collectionID: row.string(1) ?? "",
                assetSetID: row.string(2) ?? "",
                position: row.string(3) ?? "",
                addedAt: row.string(4)
            )
        }) ?? []
    }

    // MARK: - Queue item

    func upsertQueueItem(id: String, assetSetID: String, position: String, addedAt: String?) throws {
        try localStore.connection.execute(
            """
            INSERT INTO curation_queue_items (id, asset_set_id, position, added_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                asset_set_id = excluded.asset_set_id,
                position = excluded.position,
                added_at = excluded.added_at;
            """,
            params: [id, assetSetID, position, addedAt]
        )
    }

    func tombstoneQueueItem(id: String) throws {
        try localStore.connection.execute("DELETE FROM curation_queue_items WHERE id = ?;", params: [id])
    }

    func updateQueueItemPosition(id: String, position: String) throws {
        try localStore.connection.execute(
            "UPDATE curation_queue_items SET position = ? WHERE id = ?;", params: [position, id]
        )
    }

    func fetchQueueItem(id: String) -> CurationQueueItemRow? {
        (try? localStore.connection.query(
            "SELECT id, asset_set_id, position, added_at FROM curation_queue_items WHERE id = ?;", params: [id]
        ) { row in
            CurationQueueItemRow(
                id: row.string(0) ?? "", assetSetID: row.string(1) ?? "", position: row.string(2) ?? "", addedAt: row.string(3)
            )
        })?.first
    }

    func fetchQueueItems() -> [CurationQueueItemRow] {
        (try? localStore.connection.query(
            "SELECT id, asset_set_id, position, added_at FROM curation_queue_items ORDER BY position ASC;"
        ) { row in
            CurationQueueItemRow(
                id: row.string(0) ?? "",
                assetSetID: row.string(1) ?? "",
                position: row.string(2) ?? "",
                addedAt: row.string(3)
            )
        }) ?? []
    }

    // MARK: - Continue dismissal

    func upsertContinueDismissal(id: String, assetSetID: String) throws {
        try localStore.connection.execute(
            """
            INSERT INTO curation_continue_dismissals (id, asset_set_id)
            VALUES (?, ?)
            ON CONFLICT(id) DO UPDATE SET asset_set_id = excluded.asset_set_id;
            """,
            params: [id, assetSetID]
        )
    }

    func tombstoneContinueDismissal(id: String) throws {
        try localStore.connection.execute("DELETE FROM curation_continue_dismissals WHERE id = ?;", params: [id])
    }

    func fetchContinueDismissals() -> [CurationContinueDismissalRow] {
        (try? localStore.connection.query(
            "SELECT id, asset_set_id FROM curation_continue_dismissals ORDER BY id ASC;"
        ) { row in
            CurationContinueDismissalRow(id: row.string(0) ?? "", assetSetID: row.string(1) ?? "")
        }) ?? []
    }

    // MARK: - Recent

    /// `recent`'s journal entity_id is the game's own `asset_set_id`
    /// (there is no separate row id — see `Playstead.Sync.CurationPayload`'s
    /// doc comment), so upsert/tombstone key directly on it.
    func upsertRecent(assetSetID: String, lastPlayedAt: String?) throws {
        try localStore.connection.execute(
            """
            INSERT INTO curation_recent (asset_set_id, last_played_at)
            VALUES (?, ?)
            ON CONFLICT(asset_set_id) DO UPDATE SET last_played_at = excluded.last_played_at;
            """,
            params: [assetSetID, lastPlayedAt]
        )
    }

    func tombstoneRecent(assetSetID: String) throws {
        try localStore.connection.execute("DELETE FROM curation_recent WHERE asset_set_id = ?;", params: [assetSetID])
    }

    func fetchRecent() -> [CurationRecentRow] {
        (try? localStore.connection.query(
            "SELECT asset_set_id, last_played_at FROM curation_recent ORDER BY last_played_at DESC;"
        ) { row in
            CurationRecentRow(assetSetID: row.string(0) ?? "", lastPlayedAt: row.string(1))
        }) ?? []
    }

    // MARK: - Reset

    /// Deletes every curation row across all six tables. Used as part of
    /// a cursor-expired reset, always inside the caller's transaction
    /// alongside `CatalogueStore.clearAll()`.
    func clearAll() throws {
        try localStore.connection.execute("DELETE FROM curation_favorites;")
        try localStore.connection.execute("DELETE FROM curation_collections;")
        try localStore.connection.execute("DELETE FROM curation_collection_members;")
        try localStore.connection.execute("DELETE FROM curation_queue_items;")
        try localStore.connection.execute("DELETE FROM curation_continue_dismissals;")
        try localStore.connection.execute("DELETE FROM curation_recent;")
    }

    /// Total row count across all six tables — used by tests to assert
    /// replay-safety.
    func totalCount() -> Int {
        fetchFavorites().count
            + fetchCollections().count
            + fetchCollectionMembers().count
            + fetchQueueItems().count
            + fetchContinueDismissals().count
            + fetchRecent().count
    }
}
