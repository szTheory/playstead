import Foundation

/// The state `LibraryViewModel` (plan 03-06 task 2/3) observes. Being
/// offline is a normal state, not a failure — it must read as one, so
/// there is no bare `.failed` case; a transport error during `syncNow()`
/// simply leaves the state at `.offline` (or `.neverSynced` if nothing
/// has ever succeeded).
enum SyncState: Equatable {
    case neverSynced
    case syncing
    case synced(at: Date)
    case offline(since: Date)
}

/// The full decoded `GET /api/v1/snapshot` envelope, as `SyncEngine`
/// needs it: the catalogue branch, the raw `curation` branch (each
/// element is one `Playstead.Sync.CurationPayload.build/1` map with no
/// surrounding entity-id wrapper — see `synthesizedCurationEntry(from:)`
/// below), the as-of cursor, and the device-page continuation markers.
///
/// This is deliberately a separate type from `SnapshotClient`'s narrow
/// `SnapshotResponse` (which only ever decodes `catalogue`/`cursor`/
/// `has_more` for its one full-replace bootstrap call from plan 03-03) —
/// `SyncEngine` owns the full sync spine end to end, including curation
/// convergence and multi-page continuation, so it reads the wire shape
/// itself rather than widening that tracer-scoped type.
private struct SnapshotEnvelope: Decodable {
    let catalogue: [CatalogueEntry]
    let curation: [JSONValue]
    let cursor: String
    let hasMore: Bool
    let nextAfterID: String?

    private enum CodingKeys: String, CodingKey {
        case catalogue, curation, cursor
        case hasMore = "has_more"
        case nextAfterID = "next_after_id"
    }
}

/// Converges the local read model with the server through the existing
/// snapshot/journal/cursor recovery spine (D-21) alone — no other
/// reconciliation mechanism (T-03-cursor prohibition). An actor because
/// every apply must be serialized: two concurrent `syncNow()` calls
/// racing the same cursor read-modify-write could otherwise skip or
/// duplicate a page.
actor SyncEngine {
    private let apiClient: APIClient
    private let localStore: LocalStore
    private let changesClient: ChangesClient
    private let cursorStore: CursorStore
    private let catalogueStore: CatalogueStore
    private let curationStore: CurationStore
    private let journalApplier: JournalApplier

    private(set) var state: SyncState = .neverSynced

    init(apiClient: APIClient, localStore: LocalStore) {
        self.apiClient = apiClient
        self.localStore = localStore
        self.changesClient = ChangesClient(apiClient: apiClient)
        self.cursorStore = CursorStore(localStore: localStore)
        self.catalogueStore = CatalogueStore(localStore: localStore)
        self.curationStore = CurationStore(localStore: localStore)
        self.journalApplier = JournalApplier(catalogueStore: catalogueStore, curationStore: curationStore)
    }

    /// Runs one full sync pass: bootstraps from the snapshot if the
    /// client has never synced, otherwise pages `/api/v1/changes` from
    /// the stored cursor until caught up. On `SyncError.cursorExpired`,
    /// resets to a fresh snapshot. A transport or decode failure leaves
    /// the stored cursor and read model untouched — nothing is written
    /// until a fetch has actually succeeded.
    func syncNow() async {
        state = .syncing
        do {
            if let cursor = cursorStore.load() {
                try await applyChangesLoop(from: cursor)
            } else {
                try await bootstrapFromSnapshot()
            }
            state = .synced(at: Date())
        } catch SyncError.cursorExpired {
            await handleCursorExpired()
        } catch {
            state = fallbackOfflineState()
        }
    }

    private func handleCursorExpired() async {
        do {
            try await bootstrapFromSnapshot()
            state = .synced(at: Date())
        } catch {
            state = fallbackOfflineState()
        }
    }

    private func fallbackOfflineState() -> SyncState {
        if let lastSynced = cursorStore.lastSyncedAt() {
            return .offline(since: lastSynced)
        }
        return .neverSynced
    }

    // MARK: - Changes (resumed) path

    /// Pages `/api/v1/changes` from `cursor` until `has_more` is false.
    /// Every page is applied inside one transaction, and the new cursor
    /// is committed only after that transaction commits — an interrupted
    /// apply is safe to retry from the old cursor because every apply is
    /// an idempotent upsert/delete keyed on entity id (T-03-17).
    private func applyChangesLoop(from cursor: OpaqueCursor) async throws {
        var current = cursor
        while true {
            let page = try await changesClient.fetch(after: current)

            try localStore.transaction {
                self.journalApplier.apply(page.entries)
            }

            let newCursor = OpaqueCursor(rawValue: page.cursor)
            try cursorStore.store(newCursor, syncedAt: Date())
            current = newCursor

            if !page.hasMore { break }
        }
    }

    // MARK: - Snapshot (bootstrap / reset) path

    /// Fetches every page of `/api/v1/snapshot` (continuing from
    /// `next_after_id` while `has_more` is true, all pinned to the first
    /// page's own returned cursor so a slower-arriving later page can
    /// never silently include a write a faster-arriving earlier page
    /// missed), replaces the entire local catalogue and curation mirror
    /// with the accumulated result inside one transaction, then stores
    /// the final cursor. Used both for the very first sync and for a
    /// cursor-expired reset.
    private func bootstrapFromSnapshot() async throws {
        var catalogueAccum: [CatalogueEntry] = []
        var curationAccum: [JournalEntry] = []
        var pinnedCursor: String?
        var afterID: String?
        var finalCursor = ""

        while true {
            let page = try await fetchSnapshotEnvelope(cursor: pinnedCursor, afterID: afterID)
            pinnedCursor = page.cursor
            finalCursor = page.cursor

            catalogueAccum.append(contentsOf: page.catalogue)
            curationAccum.append(contentsOf: page.curation.compactMap(Self.synthesizedCurationEntry(from:)))

            if page.hasMore, let next = page.nextAfterID {
                afterID = next
            } else {
                break
            }
        }

        try localStore.transaction {
            try self.catalogueStore.clearAll()
            try self.curationStore.clearAll()
            for entry in catalogueAccum {
                try self.catalogueStore.upsert(entry)
            }
            self.journalApplier.apply(curationAccum)
        }

        try cursorStore.store(OpaqueCursor(rawValue: finalCursor), syncedAt: Date())
    }

    private func fetchSnapshotEnvelope(cursor: String?, afterID: String?) async throws -> SnapshotEnvelope {
        var queryItems: [URLQueryItem] = []
        if let cursor { queryItems.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let afterID { queryItems.append(URLQueryItem(name: "after_id", value: afterID)) }

        let response: APIResponse
        do {
            response = try await apiClient.get(path: "/api/v1/snapshot", queryItems: queryItems)
        } catch let error as APIClientError {
            throw ChangesClient.map(error)
        } catch {
            throw SyncError.transport
        }

        do {
            return try JSONDecoder().decode(SnapshotEnvelope.self, from: response.body)
        } catch {
            throw SyncError.decodeFailed
        }
    }

    /// Builds a synthetic `curation`-kind `JournalEntry` from one raw
    /// snapshot `curation` array element, so `JournalApplier` can apply
    /// snapshot-sourced curation rows through the exact same path as
    /// journal-sourced ones.
    ///
    /// **Known gap (flagged, not silently worked around):**
    /// `Playstead.Sync.CurationPayload.build/1` — used for both the
    /// journal payload AND this snapshot branch — never includes the
    /// row's own server id; only the surrounding journal entry envelope
    /// carries `entity_id`, and the snapshot's `curation` array has no
    /// such envelope. This function falls back to a locally-synthesized
    /// key derived from each type's natural unique key (matching the
    /// server's own unique index: `favorite`/`continue_dismissal`/
    /// `queue_item` on `(user_id, asset_set_id)`, `collection_member` on
    /// `(collection_id, asset_set_id)`), which keeps snapshot bootstrap
    /// idempotent and duplicate-free. `collection` has no such natural
    /// key in this payload shape and falls back to its `name`, which is
    /// not guaranteed unique — see this plan's SUMMARY "Known Stubs".
    /// A real server-issued `entity_id` from a later `/changes` upsert
    /// always wins from that point on, since it becomes that row's new
    /// primary key going forward.
    private static func synthesizedCurationEntry(from payload: JSONValue) -> JournalEntry? {
        guard case .object(let object) = payload, let type = object["type"]?.stringValue else { return nil }

        let syntheticID: String
        switch type {
        case "favorite", "continue_dismissal", "queue_item", "recent":
            guard let assetSetID = object["asset_set_id"]?.stringValue else { return nil }
            syntheticID = "\(type):\(assetSetID)"
        case "collection_member":
            guard
                let collectionID = object["collection_id"]?.stringValue,
                let assetSetID = object["asset_set_id"]?.stringValue
            else { return nil }
            syntheticID = "collection_member:\(collectionID):\(assetSetID)"
        case "collection":
            guard let name = object["name"]?.stringValue else { return nil }
            syntheticID = "collection:\(name)"
        default:
            return nil
        }

        return JournalEntry(entityKind: "curation", entityID: syntheticID, operation: "upsert", payload: payload)
    }
}
