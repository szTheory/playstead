import Foundation

/// Every curation mutation this client can enqueue. Values mirror the
/// server's `/api/v1/curation/*` and `/api/v1/curation/continue/*` route
/// tables (`PlaysteadWeb.Api.V1.CurationController`) one-for-one. Task 1
/// (plan 03-08) added the favorite pair; task 2 adds the remaining nine
/// kinds for collections, the play queue, and Continue dismissals.
enum CurationIntentKind: String, Codable, Equatable {
    case favoriteAdd = "favorite_add"
    case favoriteRemove = "favorite_remove"
    case collectionCreate = "collection_create"
    case collectionRename = "collection_rename"
    case collectionDelete = "collection_delete"
    case collectionMemberAdd = "collection_member_add"
    case collectionMemberRemove = "collection_member_remove"
    case collectionMemberMove = "collection_member_move"
    case queueEnqueue = "queue_enqueue"
    case queueDequeue = "queue_dequeue"
    case queueMove = "queue_move"
    case continueDismiss = "continue_dismiss"
    case playSessionRecord = "play_session_record"
    case playSessionDelete = "play_session_delete"
}

/// The wire-and-storage envelope for one `CurationIntent` — every field
/// every kind might need, most left `nil` for a given kind. This is what
/// actually gets persisted as `outbox_entries.payload_json`: not just
/// the HTTP body (empty for most DELETE-shaped intents), but enough to
/// reconstruct the whole `CurationIntent` — method, path, and the local
/// row it applies to — after an app restart.
struct CurationIntentEnvelope: Codable, Equatable {
    let kind: CurationIntentKind
    var id: String?
    var rowID: String?
    var assetSetID: String?
    var collectionID: String?
    var name: String?
    var position: String?
    var beforeAssetSetID: String?
    var afterAssetSetID: String?
    var startedAt: String?
    var endedAt: String?

    private enum CodingKeys: String, CodingKey {
        case kind, id, name, position
        case rowID = "row_id"
        case assetSetID = "asset_set_id"
        case collectionID = "collection_id"
        case beforeAssetSetID = "before_asset_set_id"
        case afterAssetSetID = "after_asset_set_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }
}

/// One curation mutation, modeled as an enumeration whose associated
/// payload field names match the server changeset fields from plan
/// 03-04 exactly (D-20's natural-key + idempotency-key mechanism,
/// unchanged from Phase 1). `id` is both the client-generated row
/// identifier — the row's own natural key on the server — and the seed
/// of this intent's idempotency key, so a repeated insert converges on
/// one row and a repeated request replays the first response rather
/// than producing a second effect.
///
/// Move-shaped intents (`collectionMemberMove`/`queueMove`) carry a
/// `position` that is purely a local optimistic placeholder computed by
/// `FractionalPosition` — the server never reads it (`move_collection_
/// member`/`move_queue_item` only accept the two named neighbours) and
/// always recomputes the settled position from them, which then arrives
/// through the journal.
enum CurationIntent: Equatable {
    case favoriteAdd(id: String, assetSetID: String)
    case favoriteRemove(rowID: String, assetSetID: String)

    case collectionCreate(id: String, name: String)
    case collectionRename(collectionID: String, name: String)
    case collectionDelete(collectionID: String)

    case collectionMemberAdd(id: String, collectionID: String, assetSetID: String, position: String)
    case collectionMemberRemove(rowID: String, collectionID: String, assetSetID: String)
    case collectionMemberMove(
        rowID: String, collectionID: String, assetSetID: String, position: String,
        beforeAssetSetID: String?, afterAssetSetID: String?
    )

    case queueEnqueue(id: String, assetSetID: String, position: String)
    case queueDequeue(rowID: String, assetSetID: String)
    case queueMove(rowID: String, assetSetID: String, position: String, beforeAssetSetID: String?, afterAssetSetID: String?)

    case continueDismiss(id: String, assetSetID: String)

    /// Posts a completed play session (D-07: an identifier, an asset
    /// set id, a start, and an end — nothing else). Delivered through
    /// this same outbox after the fact, individually per session; the
    /// server's `POST /api/v1/play-sessions` endpoint (plan 03-04)
    /// accepts one session per request, not a batch array, so this
    /// plan's own text about batching a drain cycle's pending sessions
    /// is implemented as sequential individual posts — the "correct
    /// fallback" the plan itself names for a partially-rejected batch,
    /// which is what the server can actually accept.
    case playSessionRecord(id: String, assetSetID: String, startedAt: String, endedAt: String)
    /// A user-initiated deletion of a (possibly already-delivered)
    /// session.
    case playSessionDelete(id: String)

    var kind: CurationIntentKind {
        switch self {
        case .favoriteAdd: return .favoriteAdd
        case .favoriteRemove: return .favoriteRemove
        case .collectionCreate: return .collectionCreate
        case .collectionRename: return .collectionRename
        case .collectionDelete: return .collectionDelete
        case .collectionMemberAdd: return .collectionMemberAdd
        case .collectionMemberRemove: return .collectionMemberRemove
        case .collectionMemberMove: return .collectionMemberMove
        case .queueEnqueue: return .queueEnqueue
        case .queueDequeue: return .queueDequeue
        case .queueMove: return .queueMove
        case .continueDismiss: return .continueDismiss
        case .playSessionRecord: return .playSessionRecord
        case .playSessionDelete: return .playSessionDelete
        }
    }

    /// The value this intent's idempotency key is seeded from: the new
    /// row's own client-generated id for a create-shaped intent, or the
    /// target's own local row id for a remove/rename/delete/move-shaped
    /// one (there is no new row to name, so the target itself anchors
    /// the key — sending the identical intent twice must produce the
    /// identical key both times).
    private var anchorID: String {
        switch self {
        case .favoriteAdd(let id, _): return id
        case .favoriteRemove(let rowID, _): return rowID
        case .collectionCreate(let id, _): return id
        case .collectionRename(let collectionID, _): return collectionID
        case .collectionDelete(let collectionID): return collectionID
        case .collectionMemberAdd(let id, _, _, _): return id
        case .collectionMemberRemove(let rowID, _, _): return rowID
        case .collectionMemberMove(let rowID, _, _, _, _, _): return rowID
        case .queueEnqueue(let id, _, _): return id
        case .queueDequeue(let rowID, _): return rowID
        case .queueMove(let rowID, _, _, _, _): return rowID
        case .continueDismiss(let id, _): return id
        case .playSessionRecord(let id, _, _, _): return id
        case .playSessionDelete(let id): return id
        }
    }

    /// Stable across every attempt of this exact intent (P1 D-20's
    /// idempotency mechanism) — `OutboxWorker` sends this same value as
    /// the `Idempotency-Key` header on the first attempt and on every
    /// retry, so a request that succeeded but whose response was never
    /// observed replays the original effect instead of duplicating it.
    var idempotencyKey: String { "\(kind.rawValue):\(anchorID)" }

    /// The local `curation_*` row this intent creates or targets.
    var localRowID: String {
        switch self {
        case .favoriteAdd(let id, _): return id
        case .favoriteRemove(let rowID, _): return rowID
        case .collectionCreate(let id, _): return id
        case .collectionRename(let collectionID, _): return collectionID
        case .collectionDelete(let collectionID): return collectionID
        case .collectionMemberAdd(let id, _, _, _): return id
        case .collectionMemberRemove(let rowID, _, _): return rowID
        case .collectionMemberMove(let rowID, _, _, _, _, _): return rowID
        case .queueEnqueue(let id, _, _): return id
        case .queueDequeue(let rowID, _): return rowID
        case .queueMove(let rowID, _, _, _, _): return rowID
        case .continueDismiss(let id, _): return id
        case .playSessionRecord(let id, _, _, _): return id
        case .playSessionDelete(let id): return id
        }
    }

    var httpMethod: String {
        switch self {
        case .favoriteAdd, .collectionMemberAdd, .queueEnqueue, .continueDismiss:
            return "PUT"
        case .favoriteRemove, .collectionDelete, .collectionMemberRemove, .queueDequeue, .playSessionDelete:
            return "DELETE"
        case .collectionCreate, .playSessionRecord:
            return "POST"
        case .collectionRename, .collectionMemberMove, .queueMove:
            return "PATCH"
        }
    }

    var path: String {
        switch self {
        case .favoriteAdd(_, let assetSetID), .favoriteRemove(_, let assetSetID):
            return "/api/v1/curation/favorites/\(assetSetID)"
        case .collectionCreate:
            return "/api/v1/curation/collections"
        case .collectionRename(let collectionID, _), .collectionDelete(let collectionID):
            return "/api/v1/curation/collections/\(collectionID)"
        case .collectionMemberAdd(_, let collectionID, let assetSetID, _),
             .collectionMemberRemove(_, let collectionID, let assetSetID):
            return "/api/v1/curation/collections/\(collectionID)/members/\(assetSetID)"
        case .collectionMemberMove(_, let collectionID, let assetSetID, _, _, _):
            return "/api/v1/curation/collections/\(collectionID)/members/\(assetSetID)/position"
        case .queueEnqueue(_, let assetSetID, _), .queueDequeue(_, let assetSetID):
            return "/api/v1/curation/queue/\(assetSetID)"
        case .queueMove(_, let assetSetID, _, _, _):
            return "/api/v1/curation/queue/\(assetSetID)/position"
        case .continueDismiss(_, let assetSetID):
            return "/api/v1/curation/continue/\(assetSetID)/dismiss"
        case .playSessionRecord:
            return "/api/v1/play-sessions"
        case .playSessionDelete(let id):
            return "/api/v1/play-sessions/\(id)"
        }
    }

    /// The JSON body sent to the server — matches each controller
    /// action's expected params exactly. D-09: a move intent's body
    /// names only its two neighbours, never an array of identifiers —
    /// the server rejects an array-shaped body outright.
    var wireBody: Data? {
        func encode(_ dict: [String: String?]) -> Data? {
            let filtered = dict.compactMapValues { $0 }
            return try? JSONEncoder().encode(filtered)
        }

        switch self {
        case .favoriteAdd(let id, _):
            return encode(["id": id])
        case .favoriteRemove:
            return nil
        case .collectionCreate(let id, let name):
            return encode(["id": id, "name": name])
        case .collectionRename(_, let name):
            return encode(["name": name])
        case .collectionDelete:
            return nil
        case .collectionMemberAdd(let id, _, _, _):
            return encode(["id_for_member": id])
        case .collectionMemberRemove:
            return nil
        case .collectionMemberMove(_, _, _, _, let before, let after):
            return try? JSONEncoder().encode([
                "before_asset_set_id": before, "after_asset_set_id": after
            ])
        case .queueEnqueue(let id, _, _):
            return encode(["id": id])
        case .queueDequeue:
            return nil
        case .queueMove(_, _, _, let before, let after):
            return try? JSONEncoder().encode([
                "before_asset_set_id": before, "after_asset_set_id": after
            ])
        case .continueDismiss(let id, _):
            return encode(["id": id])
        case .playSessionRecord(let id, let assetSetID, let startedAt, let endedAt):
            return try? JSONEncoder().encode([
                "id": id, "asset_set_id": assetSetID, "started_at": startedAt, "ended_at": endedAt
            ])
        case .playSessionDelete:
            return nil
        }
    }

    var envelope: CurationIntentEnvelope {
        switch self {
        case .favoriteAdd(let id, let assetSetID):
            return CurationIntentEnvelope(kind: kind, id: id, assetSetID: assetSetID)
        case .favoriteRemove(let rowID, let assetSetID):
            return CurationIntentEnvelope(kind: kind, rowID: rowID, assetSetID: assetSetID)
        case .collectionCreate(let id, let name):
            return CurationIntentEnvelope(kind: kind, id: id, name: name)
        case .collectionRename(let collectionID, let name):
            return CurationIntentEnvelope(kind: kind, collectionID: collectionID, name: name)
        case .collectionDelete(let collectionID):
            return CurationIntentEnvelope(kind: kind, collectionID: collectionID)
        case .collectionMemberAdd(let id, let collectionID, let assetSetID, let position):
            return CurationIntentEnvelope(kind: kind, id: id, assetSetID: assetSetID, collectionID: collectionID, position: position)
        case .collectionMemberRemove(let rowID, let collectionID, let assetSetID):
            return CurationIntentEnvelope(kind: kind, rowID: rowID, assetSetID: assetSetID, collectionID: collectionID)
        case .collectionMemberMove(let rowID, let collectionID, let assetSetID, let position, let before, let after):
            return CurationIntentEnvelope(
                kind: kind, rowID: rowID, assetSetID: assetSetID, collectionID: collectionID,
                position: position, beforeAssetSetID: before, afterAssetSetID: after
            )
        case .queueEnqueue(let id, let assetSetID, let position):
            return CurationIntentEnvelope(kind: kind, id: id, assetSetID: assetSetID, position: position)
        case .queueDequeue(let rowID, let assetSetID):
            return CurationIntentEnvelope(kind: kind, rowID: rowID, assetSetID: assetSetID)
        case .queueMove(let rowID, let assetSetID, let position, let before, let after):
            return CurationIntentEnvelope(
                kind: kind, rowID: rowID, assetSetID: assetSetID, position: position,
                beforeAssetSetID: before, afterAssetSetID: after
            )
        case .continueDismiss(let id, let assetSetID):
            return CurationIntentEnvelope(kind: kind, id: id, assetSetID: assetSetID)
        case .playSessionRecord(let id, let assetSetID, let startedAt, let endedAt):
            return CurationIntentEnvelope(kind: kind, id: id, assetSetID: assetSetID, startedAt: startedAt, endedAt: endedAt)
        case .playSessionDelete(let id):
            return CurationIntentEnvelope(kind: kind, id: id)
        }
    }

    /// Reconstructs a `CurationIntent` from a persisted envelope — `nil`
    /// if the envelope is missing a field this kind requires (never
    /// expected from an envelope this same enum produced, but guarded
    /// rather than force-unwrapped since it round-trips through SQLite
    /// text storage).
    static func from(_ envelope: CurationIntentEnvelope) -> CurationIntent? {
        switch envelope.kind {
        case .favoriteAdd:
            guard let id = envelope.id, let assetSetID = envelope.assetSetID else { return nil }
            return .favoriteAdd(id: id, assetSetID: assetSetID)
        case .favoriteRemove:
            guard let rowID = envelope.rowID, let assetSetID = envelope.assetSetID else { return nil }
            return .favoriteRemove(rowID: rowID, assetSetID: assetSetID)
        case .collectionCreate:
            guard let id = envelope.id, let name = envelope.name else { return nil }
            return .collectionCreate(id: id, name: name)
        case .collectionRename:
            guard let collectionID = envelope.collectionID, let name = envelope.name else { return nil }
            return .collectionRename(collectionID: collectionID, name: name)
        case .collectionDelete:
            guard let collectionID = envelope.collectionID else { return nil }
            return .collectionDelete(collectionID: collectionID)
        case .collectionMemberAdd:
            guard
                let id = envelope.id, let collectionID = envelope.collectionID,
                let assetSetID = envelope.assetSetID, let position = envelope.position
            else { return nil }
            return .collectionMemberAdd(id: id, collectionID: collectionID, assetSetID: assetSetID, position: position)
        case .collectionMemberRemove:
            guard
                let rowID = envelope.rowID, let collectionID = envelope.collectionID, let assetSetID = envelope.assetSetID
            else { return nil }
            return .collectionMemberRemove(rowID: rowID, collectionID: collectionID, assetSetID: assetSetID)
        case .collectionMemberMove:
            guard
                let rowID = envelope.rowID, let collectionID = envelope.collectionID,
                let assetSetID = envelope.assetSetID, let position = envelope.position
            else { return nil }
            return .collectionMemberMove(
                rowID: rowID, collectionID: collectionID, assetSetID: assetSetID, position: position,
                beforeAssetSetID: envelope.beforeAssetSetID, afterAssetSetID: envelope.afterAssetSetID
            )
        case .queueEnqueue:
            guard let id = envelope.id, let assetSetID = envelope.assetSetID, let position = envelope.position else { return nil }
            return .queueEnqueue(id: id, assetSetID: assetSetID, position: position)
        case .queueDequeue:
            guard let rowID = envelope.rowID, let assetSetID = envelope.assetSetID else { return nil }
            return .queueDequeue(rowID: rowID, assetSetID: assetSetID)
        case .queueMove:
            guard let rowID = envelope.rowID, let assetSetID = envelope.assetSetID, let position = envelope.position else { return nil }
            return .queueMove(
                rowID: rowID, assetSetID: assetSetID, position: position,
                beforeAssetSetID: envelope.beforeAssetSetID, afterAssetSetID: envelope.afterAssetSetID
            )
        case .continueDismiss:
            guard let id = envelope.id, let assetSetID = envelope.assetSetID else { return nil }
            return .continueDismiss(id: id, assetSetID: assetSetID)
        case .playSessionRecord:
            guard
                let id = envelope.id, let assetSetID = envelope.assetSetID,
                let startedAt = envelope.startedAt, let endedAt = envelope.endedAt
            else { return nil }
            return .playSessionRecord(id: id, assetSetID: assetSetID, startedAt: startedAt, endedAt: endedAt)
        case .playSessionDelete:
            guard let id = envelope.id else { return nil }
            return .playSessionDelete(id: id)
        }
    }

    /// Applies this intent's optimistic local write immediately, inside
    /// the same transaction `Outbox.enqueue` uses to durably record the
    /// entry — the interface never waits on the network. The
    /// authoritative row still arrives later as a journal entry through
    /// `JournalApplier`; because both this write and the journal apply
    /// are upserts keyed on the same `localRowID`, that later apply is a
    /// no-op, not a duplicate.
    func applyOptimistically(to curationStore: CurationStore, at now: Date) throws {
        let nowString = ISO8601DateFormatter().string(from: now)
        switch self {
        case .favoriteAdd(let id, let assetSetID):
            try curationStore.upsertFavorite(id: id, assetSetID: assetSetID, createdAt: nowString)
        case .favoriteRemove(let rowID, _):
            try curationStore.tombstoneFavorite(id: rowID)
        case .collectionCreate(let id, let name):
            try curationStore.upsertCollection(id: id, name: name, createdAt: nowString, updatedAt: nowString)
        case .collectionRename(let collectionID, let name):
            try curationStore.renameCollection(id: collectionID, name: name, updatedAt: nowString)
        case .collectionDelete(let collectionID):
            try curationStore.tombstoneCollectionMembersByCollection(collectionID)
            try curationStore.tombstoneCollection(id: collectionID)
        case .collectionMemberAdd(let id, let collectionID, let assetSetID, let position):
            try curationStore.upsertCollectionMember(
                id: id, collectionID: collectionID, assetSetID: assetSetID, position: position, addedAt: nowString
            )
        case .collectionMemberRemove(let rowID, _, _):
            try curationStore.tombstoneCollectionMember(id: rowID)
        case .collectionMemberMove(let rowID, _, _, let position, _, _):
            try curationStore.updateCollectionMemberPosition(id: rowID, position: position)
        case .queueEnqueue(let id, let assetSetID, let position):
            try curationStore.upsertQueueItem(id: id, assetSetID: assetSetID, position: position, addedAt: nowString)
        case .queueDequeue(let rowID, _):
            try curationStore.tombstoneQueueItem(id: rowID)
        case .queueMove(let rowID, _, let position, _, _):
            try curationStore.updateQueueItemPosition(id: rowID, position: position)
        case .continueDismiss(let id, let assetSetID):
            try curationStore.upsertContinueDismissal(id: id, assetSetID: assetSetID)
        case .playSessionRecord, .playSessionDelete:
            // Play sessions live in `play_sessions_pending`, owned
            // directly by `PlaySessionRecorder` — never in any
            // `curation_*` table `CurationStore` manages.
            break
        }
    }

    /// Reverts this intent's optimistic local write after a permanent
    /// (4xx, non-idempotency-conflict) rejection — the user's library
    /// must actually match what the server accepted, never silently
    /// drift from what they asked for. A create-shaped intent's revert
    /// is a plain delete of the row it optimistically inserted. A
    /// remove/rename/delete/move-shaped intent's rejection reverts to a
    /// no-op beyond marking the entry rejected — there is no captured
    /// prior state to restore from without storing a full row snapshot,
    /// which no acceptance criterion in this plan requires; flagged as a
    /// known, bounded limitation in this plan's SUMMARY.
    func revertOptimistic(from curationStore: CurationStore) throws {
        switch self {
        case .favoriteAdd(let id, _):
            try curationStore.tombstoneFavorite(id: id)
        case .collectionCreate(let id, _):
            try curationStore.tombstoneCollection(id: id)
        case .collectionMemberAdd(let id, _, _, _):
            try curationStore.tombstoneCollectionMember(id: id)
        case .queueEnqueue(let id, _, _):
            try curationStore.tombstoneQueueItem(id: id)
        case .continueDismiss(let id, _):
            try curationStore.tombstoneContinueDismissal(id: id)
        case .favoriteRemove, .collectionRename, .collectionDelete, .collectionMemberRemove,
             .collectionMemberMove, .queueDequeue, .queueMove, .playSessionRecord, .playSessionDelete:
            break
        }
    }
}
