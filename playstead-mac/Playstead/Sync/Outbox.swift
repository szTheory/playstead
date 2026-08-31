import Foundation

enum OutboxEntryState: String, Equatable {
    case pending
    case inFlight = "in_flight"
    case rejected
}

/// One durable outbox row. `intent` is `nil` only if a future client
/// version wrote a `kind` this build doesn't recognise (forward
/// compatibility, matching `JournalApplier`'s skip-and-count posture) —
/// `Outbox` itself never produces such a row.
struct OutboxEntry: Equatable {
    let id: String
    let kind: CurationIntentKind
    let intent: CurationIntent?
    let idempotencyKey: String
    var state: OutboxEntryState
    var attemptCount: Int
    let createdAt: String
    var lastErrorCode: String?
}

/// The durable outbox for offline curation intents (plan 03-08 task 1).
/// `enqueue` applies the intent's optimistic local write and durably
/// records the entry inside one transaction, so a crash between the
/// local write and the network send can never lose the entry — it
/// survives on disk and `OutboxWorker` drains whatever is `pending` on
/// the next launch (satisfying "the favorite persists across an
/// application restart while still unsent" with no special-cased
/// persistence path; this is on-disk SQLite, not an in-memory queue).
final class Outbox {
    private let localStore: LocalStore
    private let curationStore: CurationStore

    init(localStore: LocalStore, curationStore: CurationStore) {
        self.localStore = localStore
        self.curationStore = curationStore
    }

    /// Applies `intent`'s optimistic local write and enqueues it,
    /// atomically. Returns the durable entry `OutboxWorker` will later
    /// drain.
    ///
    /// The `Idempotency-Key` sent on the wire (P1 D-20's idempotency
    /// mechanism) is anchored on this newly generated `entryID`, not on
    /// the intent's own semantic target-row id: `OutboxWorker` sends this
    /// same stored value on the first attempt and on every retry *of this
    /// entry*, so a request that succeeded but whose response was never
    /// observed replays the original effect instead of duplicating it —
    /// while two *distinct* intents enqueued against the same row (e.g.
    /// two successive renames before the first is acknowledged) each get
    /// their own entry, and therefore their own key, so the second
    /// mutation is never mistaken by the server for a replay of the first
    /// (P4-CR-001).
    @discardableResult
    func enqueue(_ intent: CurationIntent, at now: Date = Date()) throws -> OutboxEntry {
        let entryID = UUID().uuidString
        let createdAt = ISO8601DateFormatter().string(from: now)
        let idempotencyKey = "\(intent.kind.rawValue):\(entryID)"
        let payloadData = try JSONEncoder().encode(intent.envelope)
        let payloadJSON = String(data: payloadData, encoding: .utf8) ?? "{}"

        try localStore.transaction {
            try intent.applyOptimistically(to: self.curationStore, at: now)
            try self.localStore.connection.execute(
                """
                INSERT INTO outbox_entries
                    (id, kind, payload_json, idempotency_key, state, attempt_count, created_at, last_error_code)
                VALUES (?, ?, ?, ?, 'pending', 0, ?, NULL);
                """,
                params: [entryID, intent.kind.rawValue, payloadJSON, idempotencyKey, createdAt]
            )
        }

        return OutboxEntry(
            id: entryID, kind: intent.kind, intent: intent, idempotencyKey: idempotencyKey,
            state: .pending, attemptCount: 0, createdAt: createdAt, lastErrorCode: nil
        )
    }

    /// Every `pending` entry, oldest-created first — `OutboxWorker`
    /// drains in this exact order so entries send in the order they were
    /// created (this task's `<behavior>` requirement).
    func listPending() -> [OutboxEntry] {
        rows(where: "state = 'pending'", orderBy: "created_at ASC, rowid ASC")
    }

    /// Every entry regardless of state — used by tests and by
    /// `RejectedIntentsView` (rejected entries stay visible until the
    /// user dismisses them or the underlying intent is retried).
    func listAll() -> [OutboxEntry] {
        rows(where: "1 = 1", orderBy: "created_at ASC, rowid ASC")
    }

    func listRejected() -> [OutboxEntry] {
        rows(where: "state = 'rejected'", orderBy: "created_at ASC, rowid ASC")
    }

    func markInFlight(_ entryID: String) throws {
        try localStore.connection.execute(
            "UPDATE outbox_entries SET state = 'in_flight' WHERE id = ?;", params: [entryID]
        )
    }

    /// A successful send — the entry's job is done, so the row is
    /// deleted. Nothing about the local read model or the server's
    /// eventual journal entry depends on this row continuing to exist;
    /// keeping it around would only grow the table unboundedly.
    func markDone(_ entryID: String) throws {
        try localStore.connection.execute("DELETE FROM outbox_entries WHERE id = ?;", params: [entryID])
    }

    /// A transport failure or 5xx response — the mutation may well have
    /// succeeded, so the local row is left alone (never reverted) and
    /// the entry returns to `pending` for a later retry, with its
    /// attempt count incremented for the worker's backoff decision.
    func markPendingForRetry(_ entryID: String) throws {
        try localStore.connection.execute(
            "UPDATE outbox_entries SET state = 'pending', attempt_count = attempt_count + 1 WHERE id = ?;",
            params: [entryID]
        )
    }

    /// A permanent (4xx, non-idempotency-conflict) rejection — reverts
    /// the intent's optimistic local write (inside the same transaction)
    /// and marks the entry rejected with the server's problem code, so
    /// it can be surfaced to the user rather than silently discarded.
    func markRejected(_ entryID: String, intent: CurationIntent, code: String) throws {
        try localStore.transaction {
            try intent.revertOptimistic(from: self.curationStore)
            try self.localStore.connection.execute(
                "UPDATE outbox_entries SET state = 'rejected', last_error_code = ? WHERE id = ?;",
                params: [code, entryID]
            )
        }
    }

    private func rows(where clause: String, orderBy: String) -> [OutboxEntry] {
        (try? localStore.connection.query(
            """
            SELECT id, kind, payload_json, idempotency_key, state, attempt_count, created_at, last_error_code
            FROM outbox_entries WHERE \(clause) ORDER BY \(orderBy);
            """
        ) { row in
            let kindRaw = row.string(1) ?? ""
            let kind = CurationIntentKind(rawValue: kindRaw)
            let payloadJSON = row.string(2) ?? "{}"
            let intent: CurationIntent? = {
                guard
                    let data = payloadJSON.data(using: .utf8),
                    let envelope = try? JSONDecoder().decode(CurationIntentEnvelope.self, from: data)
                else { return nil }
                return CurationIntent.from(envelope)
            }()

            return OutboxEntry(
                id: row.string(0) ?? "",
                kind: kind ?? .favoriteAdd,
                intent: intent,
                idempotencyKey: row.string(3) ?? "",
                state: OutboxEntryState(rawValue: row.string(4) ?? "pending") ?? .pending,
                attemptCount: row.int(5) ?? 0,
                createdAt: row.string(6) ?? "",
                lastErrorCode: row.string(7)
            )
        }) ?? []
    }
}
