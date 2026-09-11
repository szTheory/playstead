import Foundation

enum OutboxError: Error, Equatable {
    /// `JSONEncoder`'s output was somehow not valid UTF-8 (never actually
    /// observed — `JSONEncoder` always produces valid UTF-8 — but a
    /// silent `"{}"` substitution here would durably persist a payload
    /// that can never decode back into the real intent, becoming an
    /// unrecoverable poison entry with no path to recovery (P4-WR-007).
    /// Failing `enqueue` loudly instead means the optimistic local write
    /// never happens for a payload that could not be durably recorded.
    case payloadEncodingFailed
}

enum OutboxEntryState: String, Equatable {
    case pending
    case inFlight = "in_flight"
    case rejected
    /// Retried `Outbox.maxAttempts` times with no success and no
    /// permanent rejection either — a poison message (P4-CR-003).
    /// Excluded from `listPending()` so it stops being retried
    /// automatically; the local optimistic row is left alone (unlike
    /// `.rejected`, this is not a confirmed refusal, just persistent
    /// failure to find out) and it stays visible via `listQuarantined()`/
    /// `listAll()` for the user or a future retry-quarantined action.
    case quarantined
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
    /// Set by `markPendingForRetry` to an exponential-backoff delay from
    /// the retry attempt (P4-CR-003) — `listPending()` excludes any
    /// entry whose `next_retry_at` is still in the future, so a
    /// permanently-failing entry no longer hammers the server at
    /// whatever cadence the caller invokes `drainOnce()` at.
    var nextRetryAt: String?
}

/// The durable outbox for offline curation intents (plan 03-08 task 1).
/// `enqueue` applies the intent's optimistic local write and durably
/// records the entry inside one transaction, so a crash between the
/// local write and the network send can never lose the entry — it
/// survives on disk and `OutboxWorker` drains whatever is `pending` on
/// the next launch (satisfying "the favorite persists across an
/// application restart while still unsent" with no special-cased
/// persistence path; this is on-disk SQLite, not an in-memory queue).
class Outbox {
    /// After this many attempts with no success and no permanent
    /// rejection, an entry is quarantined rather than retried again
    /// (P4-CR-003's poison-message handling).
    static let maxAttempts = 8
    private static let baseRetryDelaySeconds: TimeInterval = 5
    private static let maxRetryDelaySeconds: TimeInterval = 300

    private let localStore: LocalStore
    private let curationStore: CurationStore

    /// Invoked (on the caller's thread) immediately after a successful
    /// `enqueue` commits. The composition root (`AppEnvironment`) wires
    /// this to `OutboxWorker.drainOnce()` so a curation mutation made
    /// anywhere in the UI attempts its send right away, without every
    /// individual view model having to know the worker exists. Kept as a
    /// hook here rather than a call-site convention precisely because a
    /// call-site convention is what left the outbox unreachable from the
    /// shipped app in the first place.
    var onEnqueue: (@Sendable () -> Void)?

    init(localStore: LocalStore, curationStore: CurationStore) {
        self.localStore = localStore
        self.curationStore = curationStore
    }

    /// Exponential backoff for the `attempt`th retry (1-indexed), capped
    /// at `maxRetryDelaySeconds` — `Outbox.markPendingForRetry`'s actual
    /// documented "retry with backoff" (P4-CR-003; previously
    /// `attempt_count` was incremented but never read anywhere).
    static func retryDelay(forAttempt attempt: Int) -> TimeInterval {
        min(pow(2, Double(attempt)) * baseRetryDelaySeconds, maxRetryDelaySeconds)
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
        guard let payloadJSON = String(data: payloadData, encoding: .utf8) else {
            throw OutboxError.payloadEncodingFailed
        }

        try localStore.transaction {
            try intent.applyOptimistically(to: self.curationStore, at: now)

            // WR-05 (plan 03-16 gap closure): for a kind whose
            // `supersedesPending` is true, any row of that same kind
            // still `pending` — including one backed off by
            // `markPendingForRetry` with a future `next_retry_at` — can
            // no longer be delivered after this newer one, so it is
            // deleted here inside the same transaction that inserts the
            // new row. Scoped by kind AND by `state = 'pending'` only:
            // an `in_flight` row is a request already on the wire that
            // cannot be recalled, and every other intent kind still
            // drains in creation order with no entry dropped.
            if intent.kind.supersedesPending {
                try self.localStore.connection.execute(
                    "DELETE FROM outbox_entries WHERE kind = ? AND state = 'pending';",
                    params: [intent.kind.rawValue]
                )
            }

            try self.localStore.connection.execute(
                """
                INSERT INTO outbox_entries
                    (id, kind, payload_json, idempotency_key, state, attempt_count, created_at, last_error_code, next_retry_at)
                VALUES (?, ?, ?, ?, 'pending', 0, ?, NULL, NULL);
                """,
                params: [entryID, intent.kind.rawValue, payloadJSON, idempotencyKey, createdAt]
            )
        }

        onEnqueue?()

        return OutboxEntry(
            id: entryID, kind: intent.kind, intent: intent, idempotencyKey: idempotencyKey,
            state: .pending, attemptCount: 0, createdAt: createdAt, lastErrorCode: nil, nextRetryAt: nil
        )
    }

    /// Every `pending` entry that is actually due to send — oldest-created
    /// first among those — so `OutboxWorker` drains in creation order
    /// (this task's `<behavior>` requirement) while still honoring the
    /// backoff delay `markPendingForRetry` schedules for an entry that
    /// keeps failing (P4-CR-003).
    func listPending(at now: Date = Date()) -> [OutboxEntry] {
        let nowString = ISO8601DateFormatter().string(from: now)
        return rows(
            where: "state = 'pending' AND (next_retry_at IS NULL OR next_retry_at <= ?)",
            orderBy: "created_at ASC, rowid ASC",
            params: [nowString]
        )
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

    /// Entries that hit `Outbox.maxAttempts` with no success and no
    /// permanent rejection — poison messages needing manual attention
    /// (P4-CR-003).
    func listQuarantined() -> [OutboxEntry] {
        rows(where: "state = 'quarantined'", orderBy: "created_at ASC, rowid ASC")
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
    /// succeeded, so the local row is left alone (never reverted). The
    /// attempt count is incremented and, while it stays under
    /// `Outbox.maxAttempts`, the entry returns to `pending` with
    /// `next_retry_at` set to an exponential backoff delay from `now`
    /// (P4-CR-003) so `listPending()` skips it until then rather than
    /// retrying at whatever cadence the caller invokes `drainOnce()` at.
    /// Once `maxAttempts` is reached, the entry is quarantined instead —
    /// a poison message that needs manual attention, not indefinite
    /// silent retries.
    func markPendingForRetry(_ entry: OutboxEntry, at now: Date = Date()) throws {
        let newAttemptCount = entry.attemptCount + 1
        if newAttemptCount >= Self.maxAttempts {
            try localStore.connection.execute(
                "UPDATE outbox_entries SET state = 'quarantined', attempt_count = ?, next_retry_at = NULL WHERE id = ?;",
                params: [newAttemptCount, entry.id]
            )
        } else {
            let delay = Self.retryDelay(forAttempt: newAttemptCount)
            let nextRetryAt = ISO8601DateFormatter().string(from: now.addingTimeInterval(delay))
            try localStore.connection.execute(
                "UPDATE outbox_entries SET state = 'pending', attempt_count = ?, next_retry_at = ? WHERE id = ?;",
                params: [newAttemptCount, nextRetryAt, entry.id]
            )
        }
    }

    /// A permanent (4xx, non-idempotency-conflict) rejection — reverts
    /// the intent's optimistic local write (inside the same transaction)
    /// and marks the entry rejected with the server's problem code, so
    /// it can be surfaced to the user rather than silently discarded.
    func markRejected(_ entryID: String, intent: CurationIntent, code: String) throws {
        try localStore.transaction {
            try intent.revertOptimistic(from: self.curationStore)
            try self.localStore.connection.execute(
                "UPDATE outbox_entries SET state = 'rejected', last_error_code = ?, next_retry_at = NULL WHERE id = ?;",
                params: [code, entryID]
            )
        }
    }

    /// The generic transactional shape `enqueue` above hard-codes for
    /// `CurationIntent`: apply a caller-supplied local mutation and
    /// durably record a row in one transaction, so a crash between them
    /// can never lose the entry. `SaveOutbox` below reuses this exact
    /// discipline against its own table for save-resolution intents
    /// (plan 04-11) -- a distinct kind vocabulary and envelope shape
    /// from `CurationIntent`'s, so it is its own small class rather than
    /// a new `CurationIntentKind` case.
    private func rows(where clause: String, orderBy: String, params: [SQLiteBindable] = []) -> [OutboxEntry] {
        (try? localStore.connection.query(
            """
            SELECT id, kind, payload_json, idempotency_key, state, attempt_count, created_at, last_error_code, next_retry_at
            FROM outbox_entries WHERE \(clause) ORDER BY \(orderBy);
            """,
            params: params
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
                kind: kind ?? .unknown,
                intent: intent,
                idempotencyKey: row.string(3) ?? "",
                state: OutboxEntryState(rawValue: row.string(4) ?? "pending") ?? .pending,
                attemptCount: row.int(5) ?? 0,
                createdAt: row.string(6) ?? "",
                lastErrorCode: row.string(7),
                nextRetryAt: row.string(8)
            )
        }) ?? []
    }
}

// MARK: - SaveOutbox (plan 04-11 task 3)

/// One durable `save_outbox_entries` row.
struct SaveOutboxEntry: Equatable {
    let id: String
    let kind: SaveIntentKind
    let intent: SaveIntent?
    let idempotencyKey: String
    var attemptCount: Int
    let createdAt: String
}

/// The durable outbox for save-fork resolution intents
/// (choose-side/acknowledge-fork). `enqueue` applies a caller-supplied
/// local mutation and durably records the entry inside one transaction
/// -- the identical crash-safety discipline `Outbox.enqueue` documents
/// above, against its own table, since `SaveIntent`'s kind vocabulary
/// and envelope shape are distinct from `CurationIntent`'s. This is what
/// makes the whole choose/keep-both flow work with no server reachable:
/// the local write and the durable row both happen before any network
/// attempt, and a crash between them cannot lose the entry.
final class SaveOutbox {
    private let localStore: LocalStore

    /// Fired after a successful `enqueue` -- never when the transaction
    /// throws, since a drain over an entry that was never committed is
    /// meaningless. Mirrors `Outbox.onEnqueue` exactly; wired to a
    /// `SaveOutboxDrainTrigger.fire()` closure in `AppEnvironment.init`.
    var onEnqueue: (@Sendable () -> Void)?

    init(localStore: LocalStore) {
        self.localStore = localStore
    }

    /// Applies `localMutation` and enqueues `intent`, atomically. The
    /// `Idempotency-Key` sent on the wire is anchored on the newly
    /// generated `entryID` (never on `saveLineID` alone), matching
    /// `Outbox.enqueue`'s reasoning: a retry of *this* entry always
    /// replays with the same key, while a distinct later intent against
    /// the same line gets its own key and is never mistaken for a
    /// replay of this one.
    @discardableResult
    func enqueue(_ intent: SaveIntent, at now: Date = Date(), localMutation: () throws -> Void) throws -> SaveOutboxEntry {
        let entryID = UUID().uuidString
        let createdAt = ISO8601DateFormatter().string(from: now)
        let idempotencyKey = "\(intent.kind.rawValue):\(entryID)"
        let payloadData = try JSONEncoder().encode(intent.envelope)
        guard let payloadJSON = String(data: payloadData, encoding: .utf8) else {
            throw OutboxError.payloadEncodingFailed
        }

        try localStore.transaction {
            try localMutation()
            try self.localStore.connection.execute(
                """
                INSERT INTO save_outbox_entries (id, kind, payload_json, idempotency_key, attempt_count, created_at)
                VALUES (?, ?, ?, ?, 0, ?);
                """,
                params: [entryID, intent.kind.rawValue, payloadJSON, idempotencyKey, createdAt]
            )
        }

        onEnqueue?()

        return SaveOutboxEntry(
            id: entryID, kind: intent.kind, intent: intent, idempotencyKey: idempotencyKey,
            attemptCount: 0, createdAt: createdAt
        )
    }

    func listPending() -> [SaveOutboxEntry] {
        (try? localStore.connection.query(
            """
            SELECT id, kind, payload_json, idempotency_key, attempt_count, created_at
            FROM save_outbox_entries ORDER BY created_at ASC, rowid ASC;
            """
        ) { row in
            let kind = SaveIntentKind(rawValue: row.string(1) ?? "") ?? .unknown
            let payloadJSON = row.string(2) ?? "{}"
            let intent: SaveIntent? = {
                guard
                    let data = payloadJSON.data(using: .utf8),
                    let envelope = try? JSONDecoder().decode(SaveIntentEnvelope.self, from: data)
                else { return nil }
                return SaveIntent.from(envelope)
            }()
            return SaveOutboxEntry(
                id: row.string(0) ?? "", kind: kind, intent: intent,
                idempotencyKey: row.string(3) ?? "", attemptCount: row.int(4) ?? 0, createdAt: row.string(5) ?? ""
            )
        }) ?? []
    }

    func count() -> Int {
        ((try? localStore.connection.query("SELECT COUNT(*) FROM save_outbox_entries;") { row in row.int(0) ?? 0 }) ?? [0]).first ?? 0
    }

    /// A successful send -- the entry's job is done, exactly like
    /// `Outbox.markDone`.
    func markDone(_ entryID: String) throws {
        try localStore.connection.execute("DELETE FROM save_outbox_entries WHERE id = ?;", params: [entryID])
    }

    /// A failed send (transport failure or non-2xx) -- the local row is
    /// left alone (never reverted; nothing about a resolution/
    /// acknowledgement is destructive to revert) and the attempt count
    /// is incremented so a later drain retries it.
    func markFailed(_ entryID: String) throws {
        try localStore.connection.execute(
            "UPDATE save_outbox_entries SET attempt_count = attempt_count + 1 WHERE id = ?;", params: [entryID]
        )
    }

    /// Attempts to send every pending entry once. A transport failure or
    /// server error leaves the entry queued -- never deleted, never
    /// touching the local mutation `enqueue` already committed -- so a
    /// later attempt can complete it. This is the only step in the whole
    /// choose/keep-both flow that needs the network at all.
    @discardableResult
    func drainOnce(apiClient: APIClient) async -> Int {
        var sent = 0
        for entry in listPending() {
            guard let intent = entry.intent else { continue }
            do {
                _ = try await apiClient.send(
                    method: intent.httpMethod, path: intent.path, body: intent.wireBody,
                    headers: ["Idempotency-Key": entry.idempotencyKey]
                )
                try? markDone(entry.id)
                sent += 1
            } catch {
                try? markFailed(entry.id)
            }
        }
        return sent
    }
}
