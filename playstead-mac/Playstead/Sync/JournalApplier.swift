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
}
