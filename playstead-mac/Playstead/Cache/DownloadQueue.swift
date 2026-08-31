import Foundation

/// A transfer state for one `download_queue_items` row. This is the
/// ONLY availability-shaped column anywhere in the schema — see
/// `Migrations.swift`'s doc comment. It describes transfer progress, not
/// one of `AvailabilityState`'s six read-time-derived names.
enum QueueItemState: String, Equatable {
    case waiting
    case active
    case paused
    case cancelled
}

/// One row of the persistent download queue: one manifest member of one
/// game (or collection member), at a stable fractional position.
struct QueueItem: Equatable {
    let id: String
    let assetSetID: String
    let sha256: String
    let size: Int
    let position: String
    let state: QueueItemState
    let attemptCount: Int
}

/// A minimal fractional-indexing (a.k.a. LexoRank-style) key generator
/// over a base-62 alphabet, so `DownloadQueue.reorder` can move one row
/// to a new position between two existing rows without renumbering any
/// other row. Positions compare correctly with plain string `<`.
enum FractionalIndex {
    static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    static let base = alphabet.count

    /// Returns a key that sorts strictly after `after` and strictly
    /// before `before`. Either bound may be `nil` for an open end (append
    /// to the tail, or insert before the current head).
    static func key(after: String?, before: String?) -> String {
        let a = Array(after ?? "")
        let b = before.map(Array.init)

        var result: [Character] = []
        var i = 0
        // A depth guard is defensive only: the loop provably terminates
        // within a handful of iterations for well-formed inputs (any two
        // distinct base-62 strings diverge quickly), but a malformed
        // `before`/`after` pair (e.g. equal strings) must never hang the
        // queue actor.
        while result.count < 64 {
            let aChar = i < a.count ? index(of: a[i]) : 0
            let bChar: Int
            if let b, i < b.count {
                bChar = index(of: b[i])
            } else {
                bChar = base
            }

            if aChar == bChar {
                result.append(alphabet[aChar])
                i += 1
                continue
            }

            if bChar - aChar > 1 {
                let mid = aChar + (bChar - aChar) / 2
                result.append(alphabet[mid])
                return String(result)
            } else {
                result.append(alphabet[aChar])
                i += 1
                continue
            }
        }
        // Depth guard tripped (pathological/equal input) — append a
        // disambiguating tail character so the result still sorts
        // somewhere reasonable rather than colliding.
        result.append(alphabet[base / 2])
        return String(result)
    }

    private static func index(of char: Character) -> Int {
        alphabet.firstIndex(of: char) ?? 0
    }
}

enum DownloadQueueError: Error, Equatable {
    case itemNotFound
}

/// Wraps `download_queue_items` with enqueue/dequeue/pause/resume/cancel/
/// reorder/list, all inside transactions. Enqueue is idempotent per
/// member via the table's `UNIQUE(asset_set_id, sha256)` index — a
/// repeated enqueue converges onto the existing row (a no-op) rather than
/// duplicating it.
final class DownloadQueue {
    private let localStore: LocalStore
    private let idGenerator: () -> String
    private let now: () -> Date

    init(
        localStore: LocalStore,
        idGenerator: @escaping () -> String = { UUID().uuidString },
        now: @escaping () -> Date = Date.init
    ) {
        self.localStore = localStore
        self.idGenerator = idGenerator
        self.now = now
    }

    /// Enqueues every manifest member of `entry`, in manifest order, each
    /// at a distinct trailing position. A member already present with a
    /// non-cancelled row is left untouched — no duplicate row, no state
    /// change. A previously-cancelled row is revived to `waiting` at a
    /// fresh trailing position rather than creating a second row for the
    /// same member (the unique index would reject a straight duplicate
    /// insert; this makes "enqueue again after cancel" behave the way a
    /// user expects).
    func enqueueGame(_ entry: CatalogueEntry) throws {
        try localStore.transaction {
            for member in entry.members where member.required {
                guard let sha256 = member.sha256 else { continue }
                try self.enqueueMemberUnlocked(assetSetID: entry.id, sha256: sha256, size: member.size ?? 0)
            }
        }
    }

    /// Enqueues every member of every game in `collection`, in the
    /// collection's order — a single-game enqueue is the degenerate
    /// (one-game) case of this same call.
    func enqueueCollection(_ games: [CatalogueEntry]) throws {
        try localStore.transaction {
            for game in games {
                for member in game.members where member.required {
                    guard let sha256 = member.sha256 else { continue }
                    try self.enqueueMemberUnlocked(assetSetID: game.id, sha256: sha256, size: member.size ?? 0)
                }
            }
        }
    }

    private func enqueueMemberUnlocked(assetSetID: String, sha256: String, size: Int) throws {
        let existing = try localStore.connection.query(
            "SELECT id, state FROM download_queue_items WHERE asset_set_id = ? AND sha256 = ?;",
            params: [assetSetID, sha256]
        ) { row -> (id: String, state: String) in
            (row.string(0) ?? "", row.string(1) ?? "")
        }

        if let row = existing.first {
            if row.state == QueueItemState.cancelled.rawValue {
                let position = try nextTrailingPositionUnlocked()
                let timestamp = ISO8601DateFormatter().string(from: now())
                try localStore.connection.execute(
                    """
                    UPDATE download_queue_items
                    SET state = ?, position = ?, attempt_count = 0, updated_at = ?
                    WHERE id = ?;
                    """,
                    params: [QueueItemState.waiting.rawValue, position, timestamp, row.id]
                )
            }
            return // already queued (or already fully cached and left as a completed row elsewhere) — no duplicate
        }

        let position = try nextTrailingPositionUnlocked()
        let timestamp = ISO8601DateFormatter().string(from: now())
        try localStore.connection.execute(
            """
            INSERT INTO download_queue_items
                (id, asset_set_id, sha256, size, position, state, attempt_count, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?);
            """,
            params: [idGenerator(), assetSetID, sha256, size, position, QueueItemState.waiting.rawValue, timestamp, timestamp]
        )
    }

    private func nextTrailingPositionUnlocked() throws -> String {
        let rows = try localStore.connection.query(
            "SELECT position FROM download_queue_items ORDER BY position DESC LIMIT 1;"
        ) { row -> String in row.string(0) ?? "" }
        return FractionalIndex.key(after: rows.first, before: nil)
    }

    /// Every non-cancelled row, ordered by position — the queue's stable
    /// total order.
    func list() -> [QueueItem] {
        (try? localStore.connection.query(
            """
            SELECT id, asset_set_id, sha256, size, position, state, attempt_count
            FROM download_queue_items
            WHERE state != ?
            ORDER BY position ASC;
            """,
            params: [QueueItemState.cancelled.rawValue]
        ) { row -> QueueItem in
            QueueItem(
                id: row.string(0) ?? "",
                assetSetID: row.string(1) ?? "",
                sha256: row.string(2) ?? "",
                size: row.int(3) ?? 0,
                position: row.string(4) ?? "",
                state: QueueItemState(rawValue: row.string(5) ?? "") ?? .waiting,
                attemptCount: row.int(6) ?? 0
            )
        }) ?? []
    }

    /// Every row (including cancelled) for one asset set — used by
    /// `AvailabilityState` derivation, which needs to know about
    /// non-cancelled queue rows specifically.
    func itemsForAssetSet(_ assetSetID: String) -> [QueueItem] {
        (try? localStore.connection.query(
            """
            SELECT id, asset_set_id, sha256, size, position, state, attempt_count
            FROM download_queue_items WHERE asset_set_id = ?;
            """,
            params: [assetSetID]
        ) { row -> QueueItem in
            QueueItem(
                id: row.string(0) ?? "",
                assetSetID: row.string(1) ?? "",
                sha256: row.string(2) ?? "",
                size: row.int(3) ?? 0,
                position: row.string(4) ?? "",
                state: QueueItemState(rawValue: row.string(5) ?? "") ?? .waiting,
                attemptCount: row.int(6) ?? 0
            )
        }) ?? []
    }

    func dequeue(id: String) throws {
        try localStore.connection.execute("DELETE FROM download_queue_items WHERE id = ?;", params: [id])
    }

    func pause(id: String) throws {
        try setState(id: id, state: .paused)
    }

    func resume(id: String) throws {
        try setState(id: id, state: .waiting)
    }

    func cancel(id: String) throws {
        try setState(id: id, state: .cancelled)
    }

    /// Moves active items to `.waiting` (the queue's own scheduler will
    /// re-select on next tick) — called when reachability drops, so an
    /// interrupted transfer's row reads as "waiting to resume," never a
    /// hard failure.
    func pauseAllActive() throws {
        try localStore.transaction {
            try self.localStore.connection.execute(
                "UPDATE download_queue_items SET state = ?, updated_at = ? WHERE state = ?;",
                params: [QueueItemState.waiting.rawValue, ISO8601DateFormatter().string(from: self.now()), QueueItemState.active.rawValue]
            )
        }
    }

    func markActive(id: String) throws {
        try setState(id: id, state: .active)
    }

    func incrementAttempt(id: String) throws {
        try localStore.connection.execute(
            "UPDATE download_queue_items SET attempt_count = attempt_count + 1, updated_at = ? WHERE id = ?;",
            params: [ISO8601DateFormatter().string(from: now()), id]
        )
    }

    private func setState(id: String, state: QueueItemState) throws {
        try localStore.connection.execute(
            "UPDATE download_queue_items SET state = ?, updated_at = ? WHERE id = ?;",
            params: [state.rawValue, ISO8601DateFormatter().string(from: now()), id]
        )
    }

    /// Reorders `id` to sit between `beforeID`'s and `afterID`'s current
    /// positions (either may be `nil` for "move to the very front/back").
    /// Only `id`'s own row is written — every other row's position is
    /// untouched.
    func reorder(id: String, afterID: String?, beforeID: String?) throws {
        try localStore.transaction {
            let afterPosition = try afterID.flatMap { try self.position(of: $0) }
            let beforePosition = try beforeID.flatMap { try self.position(of: $0) }
            let newPosition = FractionalIndex.key(after: afterPosition, before: beforePosition)
            try self.localStore.connection.execute(
                "UPDATE download_queue_items SET position = ?, updated_at = ? WHERE id = ?;",
                params: [newPosition, ISO8601DateFormatter().string(from: self.now()), id]
            )
        }
    }

    private func position(of id: String) throws -> String? {
        let rows = try localStore.connection.query(
            "SELECT position FROM download_queue_items WHERE id = ?;", params: [id]
        ) { row -> String in row.string(0) ?? "" }
        return rows.first
    }
}
