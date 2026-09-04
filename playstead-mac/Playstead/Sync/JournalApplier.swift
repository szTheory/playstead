import Foundation

/// Payload shapes matching `Playstead.Sync.CurationPayload.build/1`'s six
/// `type` clauses. Optional date-like fields decode as plain strings
/// (Phoenix's default JSON encoding of a `DateTime`) — this client never
/// parses or compares them, only stores and re-renders them.
private struct FavoritePayload: Decodable {
    let assetSetID: String
    let createdAt: String?
    private enum CodingKeys: String, CodingKey { case assetSetID = "asset_set_id", createdAt = "created_at" }
}

private struct CollectionPayload: Decodable {
    let name: String
    let createdAt: String?
    let updatedAt: String?
    private enum CodingKeys: String, CodingKey {
        case name, createdAt = "created_at", updatedAt = "updated_at"
    }
}

private struct CollectionMemberPayload: Decodable {
    let collectionID: String
    let assetSetID: String
    let position: String
    let addedAt: String?
    private enum CodingKeys: String, CodingKey {
        case collectionID = "collection_id", assetSetID = "asset_set_id", position, addedAt = "added_at"
    }
}

private struct QueueItemPayload: Decodable {
    let assetSetID: String
    let position: String
    let addedAt: String?
    private enum CodingKeys: String, CodingKey {
        case assetSetID = "asset_set_id", position, addedAt = "added_at"
    }
}

private struct ContinueDismissalPayload: Decodable {
    let assetSetID: String
    private enum CodingKeys: String, CodingKey { case assetSetID = "asset_set_id" }
}

private struct RecentPayload: Decodable {
    let assetSetID: String
    let lastPlayedAt: String?
    private enum CodingKeys: String, CodingKey {
        case assetSetID = "asset_set_id", lastPlayedAt = "last_played_at"
    }
}

/// Matches `Playstead.Sync.SavePayload.build/2`'s frozen key set (D-17).
/// Lineage (`saveLineID`/`parentRevisionID`) lives here, not derived --
/// this is the only place a resuming client learns a line's own
/// identity tuple, since the line row itself is never journaled under
/// its own entity id.
private struct SavePayload: Decodable {
    let revisionID: String
    let saveLineID: String
    let contentKey: String
    let saveKind: String
    let slot: String
    let parentRevisionID: String?
    let blobSHA256: String
    let sizeBytes: Int
    let originDeviceID: String?
    let deviceCapturedAt: String?
    let recordedAt: String?
    let captureMethod: String?
    let adapterID: String?
    let adapterVersion: String?
    let saveFormat: String?
    let formatConfidence: String?
    let playSessionID: String?

    private enum CodingKeys: String, CodingKey {
        case revisionID = "revision_id"
        case saveLineID = "save_line_id"
        case contentKey = "content_key"
        case saveKind = "save_kind"
        case slot
        case parentRevisionID = "parent_revision_id"
        case blobSHA256 = "blob_sha256"
        case sizeBytes = "size_bytes"
        case originDeviceID = "origin_device_id"
        case deviceCapturedAt = "device_captured_at"
        case recordedAt = "recorded_at"
        case captureMethod = "capture_method"
        case adapterID = "adapter_id"
        case adapterVersion = "adapter_version"
        case saveFormat = "save_format"
        case formatConfidence = "format_confidence"
        case playSessionID = "play_session_id"
    }
}

/// Consulted by `JournalApplier`'s `save` case to decide whether to
/// unconditionally prefetch a revision's bytes (D-43): "present
/// locally" means the ROM's own cache object -- keyed by its own
/// sha256, which is exactly what `content_key` is (D-10) -- is already
/// verified-local. At 32 KB, prefetching is cheaper than the code that
/// would decide whether to; this is what makes a clean-Mac restore
/// zero-network at Play time (SAVE-03).
protocol SaveBytesPrefetcher {
    func isContentPresentLocally(contentKey: String) -> Bool
    func prefetch(blobSHA256: String, sizeBytes: Int)
}

/// The production presence check: a plain row-existence query against
/// `cache_objects`, the same table `AvailabilityState.derive(_:)` reads.
/// The actual byte transfer (`onPrefetchNeeded`) is injected because it
/// is a downloads-lane concern (an authenticated HTTP GET through the
/// paired `APIClient`) outside this plan's declared files -- wiring the
/// real transfer is a later plan's job; this type's own responsibility
/// is making the *decision* correct and unconditional.
struct CacheObjectsSaveBytesPrefetcher: SaveBytesPrefetcher {
    let localStore: LocalStore
    var onPrefetchNeeded: (String, Int) -> Void = { _, _ in }

    func isContentPresentLocally(contentKey: String) -> Bool {
        (try? localStore.connection.query(
            "SELECT 1 FROM cache_objects WHERE sha256 = ? LIMIT 1;", params: [contentKey]
        ) { _ in true }).map { !$0.isEmpty } ?? false
    }

    func prefetch(blobSHA256: String, sizeBytes: Int) {
        onPrefetchNeeded(blobSHA256, sizeBytes)
    }
}

/// The outcome of applying a page of `JournalEntry`s: how many were
/// applied versus skipped (an unrecognised entity kind or curation
/// payload `type` — not an error, per this task's `<action>`).
struct JournalApplyResult: Equatable {
    var appliedCount = 0
    var skippedCount = 0
}

/// Dispatches each `JournalEntry` in a page to `CatalogueStore` or
/// `CurationStore` by `entityKind`, and (for `curation`) further by the
/// payload's `type` field. Every apply is an idempotent upsert or delete
/// keyed on `entityID`, so replaying a page — which the client does after
/// any interrupted apply, per `SyncEngine`'s commit-after-apply discipline
/// — is always safe.
struct JournalApplier {
    let catalogueStore: CatalogueStore
    let curationStore: CurationStore
    /// `nil` for every call site that predates plan 04-04 -- a `save`
    /// entry is then simply skipped-and-counted like any other
    /// unrecognised kind, keeping every existing two-argument call site
    /// unchanged.
    let saveStore: SaveStore?
    let saveBytesPrefetcher: SaveBytesPrefetcher?

    init(
        catalogueStore: CatalogueStore,
        curationStore: CurationStore,
        saveStore: SaveStore? = nil,
        saveBytesPrefetcher: SaveBytesPrefetcher? = nil
    ) {
        self.catalogueStore = catalogueStore
        self.curationStore = curationStore
        self.saveStore = saveStore
        self.saveBytesPrefetcher = saveBytesPrefetcher
    }

    @discardableResult
    func apply(_ entries: [JournalEntry]) -> JournalApplyResult {
        var result = JournalApplyResult()
        for entry in entries {
            if applyOne(entry) {
                result.appliedCount += 1
            } else {
                result.skippedCount += 1
            }
        }
        return result
    }

    private func applyOne(_ entry: JournalEntry) -> Bool {
        switch entry.entityKind {
        case "catalogue":
            return applyCatalogue(entry)
        case "curation":
            return applyCuration(entry)
        case "save":
            return applySave(entry)
        default:
            // An entity kind this client version doesn't recognise —
            // skipped and counted, never a hard failure, so an older
            // client stays functional against a newer server.
            return false
        }
    }

    private func applyCatalogue(_ entry: JournalEntry) -> Bool {
        if entry.operation == "tombstone" {
            return (try? catalogueStore.tombstone(id: entry.entityID)) != nil
        }
        guard let decoded = try? entry.payload.decoded(as: CatalogueEntry.self) else { return false }
        return (try? catalogueStore.upsert(decoded)) != nil
    }

    private func applyCuration(_ entry: JournalEntry) -> Bool {
        if entry.operation == "tombstone" {
            return applyCurationTombstone(entry)
        }

        guard case .object(let object) = entry.payload, let type = object["type"]?.stringValue else {
            return false
        }

        switch type {
        case "favorite":
            guard let payload = try? entry.payload.decoded(as: FavoritePayload.self) else { return false }
            return (try? curationStore.upsertFavorite(
                id: entry.entityID, assetSetID: payload.assetSetID, createdAt: payload.createdAt
            )) != nil

        case "collection":
            guard let payload = try? entry.payload.decoded(as: CollectionPayload.self) else { return false }
            return (try? curationStore.upsertCollection(
                id: entry.entityID, name: payload.name, createdAt: payload.createdAt, updatedAt: payload.updatedAt
            )) != nil

        case "collection_member":
            guard let payload = try? entry.payload.decoded(as: CollectionMemberPayload.self) else { return false }
            return (try? curationStore.upsertCollectionMember(
                id: entry.entityID,
                collectionID: payload.collectionID,
                assetSetID: payload.assetSetID,
                position: payload.position,
                addedAt: payload.addedAt
            )) != nil

        case "queue_item":
            guard let payload = try? entry.payload.decoded(as: QueueItemPayload.self) else { return false }
            return (try? curationStore.upsertQueueItem(
                id: entry.entityID, assetSetID: payload.assetSetID, position: payload.position, addedAt: payload.addedAt
            )) != nil

        case "continue_dismissal":
            guard let payload = try? entry.payload.decoded(as: ContinueDismissalPayload.self) else { return false }
            return (try? curationStore.upsertContinueDismissal(
                id: entry.entityID, assetSetID: payload.assetSetID
            )) != nil

        case "recent":
            guard let payload = try? entry.payload.decoded(as: RecentPayload.self) else { return false }
            return (try? curationStore.upsertRecent(
                assetSetID: payload.assetSetID, lastPlayedAt: payload.lastPlayedAt
            )) != nil

        default:
            // An unrecognised curation payload type — skipped and counted.
            return false
        }
    }

    // Tombstone entries always carry an empty payload (T-01-47 — a
    // deletion must reveal nothing about the deleted content), so there
    // is no `type` field to dispatch on. Attempt the delete against every
    // curation table keyed on `entityID`; at most one ever matches,
    // because `entityID` is one server row's own id (or, for `recent`,
    // its asset_set_id — see `CurationStore`'s doc comment) and ids never
    // collide across these tables. Deleting a non-existent id is a no-op,
    // which is exactly what makes replaying a tombstone safe.
    private func applyCurationTombstone(_ entry: JournalEntry) -> Bool {
        _ = try? curationStore.tombstoneFavorite(id: entry.entityID)
        _ = try? curationStore.tombstoneCollection(id: entry.entityID)
        _ = try? curationStore.tombstoneCollectionMember(id: entry.entityID)
        _ = try? curationStore.tombstoneQueueItem(id: entry.entityID)
        _ = try? curationStore.tombstoneContinueDismissal(id: entry.entityID)
        _ = try? curationStore.tombstoneRecent(assetSetID: entry.entityID)
        return true
    }

    // D-17/D-43: applies one `save` journal entry -- upserts the
    // revision (and its line, resolved-or-created) locally with
    // durability `uploaded` (it arrived through the server, so it is
    // already there by construction), then unconditionally prefetches
    // the revision bytes when the line's content is present locally.
    // Idempotent by revision id (`SaveStore.insertRevision`'s `ON
    // CONFLICT(id) DO UPDATE`), so replaying a page is always safe.
    private func applySave(_ entry: JournalEntry) -> Bool {
        guard let saveStore else { return false }

        if entry.operation == "tombstone" {
            // No save-removal path exists in this phase (D-27/D-28); a
            // tombstone entry is accepted as a no-op rather than a hard
            // failure, so a later phase can introduce one additively.
            return true
        }

        guard let payload = try? entry.payload.decoded(as: SavePayload.self) else { return false }

        guard let line = try? saveStore.resolveLine(
            contentKey: payload.contentKey,
            saveKind: payload.saveKind,
            slot: payload.slot,
            placeholderID: payload.saveLineID
        ) else { return false }

        // A line already present locally under a different (e.g.
        // locally-generated) id is re-keyed to the server-canonical one
        // -- a no-op when they already match.
        try? saveStore.adoptCanonicalLineID(payload.saveLineID, forLocalID: line.id)

        let existingLocalPath = saveStore.fetchRevision(id: payload.revisionID)?.localPath

        let row = SaveRevisionRow(
            id: payload.revisionID,
            saveLineID: payload.saveLineID,
            parentRevisionID: payload.parentRevisionID,
            blobSHA256: payload.blobSHA256,
            sizeBytes: payload.sizeBytes,
            originDeviceID: payload.originDeviceID,
            deviceCapturedAt: payload.deviceCapturedAt,
            recordedAt: payload.recordedAt,
            captureMethod: payload.captureMethod,
            adapterID: payload.adapterID,
            adapterVersion: payload.adapterVersion,
            saveFormat: payload.saveFormat,
            formatConfidence: payload.formatConfidence,
            playSessionID: payload.playSessionID,
            durability: SaveDurability.uploaded.rawValue,
            localPath: existingLocalPath
        )

        guard (try? saveStore.insertRevision(row)) != nil else { return false }

        if let prefetcher = saveBytesPrefetcher, prefetcher.isContentPresentLocally(contentKey: payload.contentKey) {
            prefetcher.prefetch(blobSHA256: payload.blobSHA256, sizeBytes: payload.sizeBytes)
        }

        return true
    }
}
