import Foundation

/// Every curation mutation this client can enqueue. Values mirror the
/// server's `/api/v1/curation/*` route table
/// (`PlaysteadWeb.Api.V1.CurationController`) one-for-one — this task
/// (03-08 task 1) adds only the favorite pair; task 2 extends this list
/// with the remaining nine kinds.
enum CurationIntentKind: String, Codable, Equatable {
    case favoriteAdd = "favorite_add"
    case favoriteRemove = "favorite_remove"
}

/// The wire-and-storage envelope for one `CurationIntent` — every field
/// every kind might need, most left `nil` for a given kind. This is what
/// actually gets persisted as `outbox_entries.payload_json`: not just
/// the HTTP body (which is empty for a DELETE-shaped intent), but enough
/// to reconstruct the whole `CurationIntent` — method, path, and the
/// local row it applies to — after an app restart.
struct CurationIntentEnvelope: Codable, Equatable {
    let kind: CurationIntentKind
    var id: String?
    var rowID: String?
    var assetSetID: String?

    private enum CodingKeys: String, CodingKey {
        case kind, id
        case rowID = "row_id"
        case assetSetID = "asset_set_id"
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
enum CurationIntent: Equatable {
    /// Favorites `assetSetID`, creating a new local+server row keyed by
    /// the client-generated `id`.
    case favoriteAdd(id: String, assetSetID: String)
    /// Un-favorites `assetSetID`. `rowID` is the local row's own id
    /// (already known to the caller from `CurationStore.fetchFavorites()`)
    /// — the server itself keys the delete on `(user_id, asset_set_id)`
    /// and does not need it, but the local optimistic tombstone does.
    case favoriteRemove(rowID: String, assetSetID: String)

    var kind: CurationIntentKind {
        switch self {
        case .favoriteAdd: return .favoriteAdd
        case .favoriteRemove: return .favoriteRemove
        }
    }

    /// The value this intent's idempotency key is seeded from: the new
    /// row's own client-generated id for a create-shaped intent, or the
    /// target's own local row id for a remove-shaped one (there is no
    /// new row to name, so the target itself anchors the key — sending
    /// the identical remove intent twice must produce the identical key
    /// both times).
    private var anchorID: String {
        switch self {
        case .favoriteAdd(let id, _): return id
        case .favoriteRemove(let rowID, _): return rowID
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
        }
    }

    var httpMethod: String {
        switch self {
        case .favoriteAdd: return "PUT"
        case .favoriteRemove: return "DELETE"
        }
    }

    var path: String {
        switch self {
        case .favoriteAdd(_, let assetSetID), .favoriteRemove(_, let assetSetID):
            return "/api/v1/curation/favorites/\(assetSetID)"
        }
    }

    /// The JSON body sent to the server — matches
    /// `CurationController.create_favorite/2`'s `params["id"]` exactly;
    /// a remove-shaped intent has no body (the server keys the delete on
    /// the URL's `asset_set_id` alone).
    var wireBody: Data? {
        switch self {
        case .favoriteAdd(let id, _):
            return try? JSONEncoder().encode(["id": id])
        case .favoriteRemove:
            return nil
        }
    }

    var envelope: CurationIntentEnvelope {
        switch self {
        case .favoriteAdd(let id, let assetSetID):
            return CurationIntentEnvelope(kind: kind, id: id, rowID: nil, assetSetID: assetSetID)
        case .favoriteRemove(let rowID, let assetSetID):
            return CurationIntentEnvelope(kind: kind, id: nil, rowID: rowID, assetSetID: assetSetID)
        }
    }

    /// Reconstructs a `CurationIntent` from a persisted envelope —
    /// `nil` if the envelope is missing a field this kind requires
    /// (never expected from an envelope this same enum produced, but
    /// guarded rather than force-unwrapped since it round-trips through
    /// SQLite text storage).
    static func from(_ envelope: CurationIntentEnvelope) -> CurationIntent? {
        switch envelope.kind {
        case .favoriteAdd:
            guard let id = envelope.id, let assetSetID = envelope.assetSetID else { return nil }
            return .favoriteAdd(id: id, assetSetID: assetSetID)
        case .favoriteRemove:
            guard let rowID = envelope.rowID, let assetSetID = envelope.assetSetID else { return nil }
            return .favoriteRemove(rowID: rowID, assetSetID: assetSetID)
        }
    }

    /// Applies this intent's optimistic local write immediately, inside
    /// the same transaction `Outbox.enqueue` uses to durably record the
    /// entry — the interface never waits on the network for a favorite.
    /// The authoritative row still arrives later as a journal entry
    /// through `JournalApplier`; because both this write and the journal
    /// apply are upserts keyed on the same `localRowID`, that later apply
    /// is a no-op, not a duplicate.
    func applyOptimistically(to curationStore: CurationStore, at now: Date) throws {
        switch self {
        case .favoriteAdd(let id, let assetSetID):
            try curationStore.upsertFavorite(id: id, assetSetID: assetSetID, createdAt: ISO8601DateFormatter().string(from: now))
        case .favoriteRemove(let rowID, _):
            try curationStore.tombstoneFavorite(id: rowID)
        }
    }

    /// Reverts this intent's optimistic local write after a permanent
    /// (4xx, non-idempotency-conflict) rejection — the user's library
    /// must actually match what the server accepted, never silently
    /// drift from what they asked for. A create-shaped intent's revert
    /// is a plain delete of the row it optimistically inserted. A
    /// remove-shaped intent's rejection is not reverted (there is no
    /// captured prior state to restore from) — flagged as a known,
    /// bounded limitation in this plan's SUMMARY; no acceptance
    /// criterion in this plan exercises a remove-shaped rejection.
    func revertOptimistic(from curationStore: CurationStore) throws {
        switch self {
        case .favoriteAdd(let id, _):
            try curationStore.tombstoneFavorite(id: id)
        case .favoriteRemove:
            break
        }
    }
}
