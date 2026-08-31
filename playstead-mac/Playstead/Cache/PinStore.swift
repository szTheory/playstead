import Foundation

/// Pins/unpins a game (an asset set), keyed by `pins.asset_set_id`.
/// Presence in the table alone IS the pin flag — there is no boolean
/// column to drift from that presence. One flag carries two meanings by
/// design (D-21): `AvailabilityState.derive(_:)` reads it to decide
/// `.pinnedOffline` vs `.verifiedLocal`, `EvictionPlanner` reads it to
/// exclude a game from every candidate list, and `DownloadCoordinator`
/// reads it (via `isPinned`) to select a pinned item before an unpinned
/// one — because a user pins the thing they intend to rely on.
final class PinStore {
    private let localStore: LocalStore
    private let now: () -> Date

    init(localStore: LocalStore, now: @escaping () -> Date = Date.init) {
        self.localStore = localStore
        self.now = now
    }

    /// Idempotent — pinning an already-pinned game leaves the row (and
    /// its original `pinned_at`) unchanged.
    func pin(assetSetID: String) throws {
        try localStore.connection.execute(
            "INSERT OR IGNORE INTO pins (asset_set_id, pinned_at) VALUES (?, ?);",
            params: [assetSetID, ISO8601DateFormatter().string(from: now())]
        )
    }

    /// Unpinning makes the game eligible for eviction — it deletes
    /// nothing by itself (D-21: reclaiming is always a separate,
    /// explicit, user-confirmed action).
    func unpin(assetSetID: String) throws {
        try localStore.connection.execute(
            "DELETE FROM pins WHERE asset_set_id = ?;",
            params: [assetSetID]
        )
    }

    func isPinned(_ assetSetID: String) -> Bool {
        let rows = (try? localStore.connection.query(
            "SELECT 1 FROM pins WHERE asset_set_id = ?;", params: [assetSetID]
        ) { _ in true }) ?? []
        return !rows.isEmpty
    }

    /// Every currently-pinned asset set id — `EvictionPlanner` uses this
    /// to exclude the whole set from candidacy in one query rather than
    /// checking `isPinned(_:)` per candidate.
    func allPinned() -> Set<String> {
        let rows = (try? localStore.connection.query(
            "SELECT asset_set_id FROM pins;"
        ) { row -> String in row.string(0) ?? "" }) ?? []
        return Set(rows)
    }
}
