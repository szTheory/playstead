import Foundation

/// The complete shape of a play session — exactly an identifier, an
/// asset set id, a start, and an end. Nothing else: no input capture, no
/// frame or performance data, no per-session device detail beyond what
/// the device credential already establishes (D-07). Recent and
/// Continue are the only two things this data exists to produce.
struct PlaySession: Equatable {
    let id: String
    let assetSetID: String
    let startedAt: Date
    var endedAt: Date?
}

/// A session plus its delivery status, for the Recent shelf's pending/
/// delivered list — `delivered` is deliberately not a field on
/// `PlaySession` itself, which stays exactly the four fields D-07 caps
/// it at.
struct PlaySessionListing: Equatable {
    let session: PlaySession
    let delivered: Bool
}

/// Records coarse play sessions to `play_sessions_pending`, delivered
/// later through the outbox after the fact. **Never sits between the
/// user's action and the launch**: nothing in `AdapterHost` (unmodified
/// by this plan — see its own file) reads, writes, awaits, or checks
/// anything this type owns. Every write method here swallows its own
/// failure (`try?`) and never throws to its caller — a launch that
/// failed because a usage-reporting write failed would be the least
/// defensible failure this product could have, so this type is
/// structurally incapable of causing one: even a caller that never
/// checks a return value from `began`/`ended` cannot observe a session-
/// recording failure propagate anywhere.
final class PlaySessionRecorder {
    private let localStore: LocalStore
    private let curationStore: CurationStore
    private let outbox: Outbox

    init(localStore: LocalStore, curationStore: CurationStore, outbox: Outbox) {
        self.localStore = localStore
        self.curationStore = curationStore
        self.outbox = outbox
    }

    /// Records a session start and returns its id (for a later `ended`
    /// call) — never throws. Also locally un-dismisses `assetSetID` from
    /// Continue and bumps the local `recent` mirror, so Continue/Recent
    /// reflect the new session immediately rather than waiting on sync
    /// (see `CurationStore.tombstoneContinueDismissalByAssetSet`'s doc
    /// comment for why this is explicit rather than time-derived).
    @discardableResult
    func began(assetSetID: String, at now: Date = Date()) -> String {
        let id = UUID().uuidString
        try? localStore.connection.execute(
            """
            INSERT INTO play_sessions_pending (id, asset_set_id, started_at, ended_at, delivered)
            VALUES (?, ?, ?, NULL, 0);
            """,
            params: [id, assetSetID, Self.iso(now)]
        )
        try? curationStore.tombstoneContinueDismissalByAssetSet(assetSetID)
        try? curationStore.upsertRecent(assetSetID: assetSetID, lastPlayedAt: Self.iso(now))
        return id
    }

    /// Records the session's end and enqueues its delivery through the
    /// outbox — never throws. A session with no `ended_at` is never
    /// enqueued (an in-progress or abandoned session has nothing
    /// complete to report yet).
    func ended(_ sessionID: String, at now: Date = Date()) {
        try? localStore.connection.execute(
            "UPDATE play_sessions_pending SET ended_at = ? WHERE id = ?;",
            params: [Self.iso(now), sessionID]
        )
        guard let session = fetch(sessionID), let endedAt = session.endedAt else { return }
        _ = try? outbox.enqueue(.playSessionRecord(
            id: session.id, assetSetID: session.assetSetID,
            startedAt: Self.iso(session.startedAt), endedAt: Self.iso(endedAt)
        ))
    }

    /// Marks `sessionID` delivered — called by `OutboxWorker`'s
    /// `onEntryDelivered` hook once the corresponding
    /// `.playSessionRecord` intent sends successfully.
    func markDelivered(_ sessionID: String) {
        try? localStore.connection.execute(
            "UPDATE play_sessions_pending SET delivered = 1 WHERE id = ?;", params: [sessionID]
        )
    }

    /// Every pending and delivered session, most recent first — the
    /// Recent shelf's deletable list.
    func listings() -> [PlaySessionListing] {
        (try? localStore.connection.query(
            """
            SELECT id, asset_set_id, started_at, ended_at, delivered
            FROM play_sessions_pending ORDER BY started_at DESC;
            """
        ) { row -> PlaySessionListing? in
            guard
                let id = row.string(0), let assetSetID = row.string(1),
                let startedAtString = row.string(2), let startedAt = Self.date(startedAtString)
            else { return nil }
            let endedAt = row.string(3).flatMap(Self.date)
            let delivered = (row.int(4) ?? 0) != 0
            return PlaySessionListing(
                session: PlaySession(id: id, assetSetID: assetSetID, startedAt: startedAt, endedAt: endedAt),
                delivered: delivered
            )
        })?.compactMap { $0 } ?? []
    }

    func fetch(_ sessionID: String) -> PlaySession? {
        listings().first(where: { $0.session.id == sessionID })?.session
    }

    /// A user-initiated deletion: removes the local row and enqueues the
    /// corresponding delete intent (the server is told regardless of
    /// whether the session was ever delivered — deleting an
    /// already-absent session is a no-op server-side).
    @discardableResult
    func delete(_ sessionID: String) -> Bool {
        guard fetch(sessionID) != nil else { return false }
        try? localStore.connection.execute("DELETE FROM play_sessions_pending WHERE id = ?;", params: [sessionID])
        _ = try? outbox.enqueue(.playSessionDelete(id: sessionID))
        return true
    }

    private static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private static func date(_ string: String) -> Date? { ISO8601DateFormatter().date(from: string) }
}
