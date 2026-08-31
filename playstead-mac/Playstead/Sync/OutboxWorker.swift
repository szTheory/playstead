import Foundation

/// Counts from one `OutboxWorker.drainOnce()` pass — used by tests and,
/// later, by a status indicator.
struct OutboxDrainResult: Equatable {
    var sent = 0
    var rejected = 0
    /// `true` once this pass hit a transport/5xx/409 failure and stopped
    /// rather than racing ahead of that entry — entries must always send
    /// in the creation order they were enqueued in.
    var stoppedForRetry = false
}

/// Drains `Outbox`'s pending entries one at a time, in creation order,
/// while the server is reachable (plan 03-08 task 1's `<action>`). A
/// transport failure or five-hundred-class response retries with
/// exponential backoff (`Outbox.markPendingForRetry`/`retryDelay`) and
/// leaves the local row alone — the mutation may well have succeeded.
/// After `Outbox.maxAttempts` such failures with no success and no
/// permanent rejection, the entry is quarantined instead of retried
/// again (P4-CR-003's poison-message handling). A four-hundred-class
/// rejection other than the idempotency conflict is permanent:
/// `Outbox.markRejected` reverts the optimistic local row and surfaces
/// the server's problem code, because discarding a rejected intent
/// silently would mean the user's library quietly differs from what
/// they asked for.
///
/// An actor because draining must be serialized — two concurrent
/// `drainOnce()` calls racing the same entry could otherwise send it
/// twice concurrently before either transitions its state.
actor OutboxWorker {
    private let apiClient: APIClient
    private let outbox: Outbox
    /// Called after a successful send, before the entry is deleted —
    /// `PlaySessionRecorder` (plan 03-08 task 3) uses this to mark its
    /// own `play_sessions_pending` row delivered, since that table is
    /// distinct from `outbox_entries` (the user must see and delete
    /// already-delivered sessions too, which a plain outbox row cannot
    /// represent once it is gone).
    private let onEntryDelivered: (@Sendable (CurationIntent) -> Void)?
    /// Called when a delete/remove-shaped intent is permanently rejected
    /// (`CurationIntent.leavesUncorrectableTombstoneOnRejection`) —
    /// intended to be wired to `SyncEngine.forceFullResync()` so the row
    /// the server never actually deleted is re-pulled and restored
    /// locally rather than left as a silent, uncorrectable tombstone
    /// (P4-CR-002). No-op by default.
    private let onDestructiveRejection: (@Sendable () -> Void)?

    init(
        apiClient: APIClient,
        outbox: Outbox,
        onEntryDelivered: (@Sendable (CurationIntent) -> Void)? = nil,
        onDestructiveRejection: (@Sendable () -> Void)? = nil
    ) {
        self.apiClient = apiClient
        self.outbox = outbox
        self.onEntryDelivered = onEntryDelivered
        self.onDestructiveRejection = onDestructiveRejection
    }

    /// Sends every currently-`pending` entry once, in creation order,
    /// stopping at the first entry that must retry (rather than sending
    /// a later entry out of order while an earlier one is still
    /// outstanding). Safe to call repeatedly — e.g. from a periodic timer
    /// or right after `SyncEngine.syncNow()` confirms reachability.
    @discardableResult
    func drainOnce(at now: Date = Date()) async -> OutboxDrainResult {
        var result = OutboxDrainResult()

        for entry in outbox.listPending(at: now) {
            guard let intent = entry.intent else {
                // A kind this build doesn't recognise — nothing this
                // worker can send; leave it for a newer build.
                continue
            }

            do {
                try outbox.markInFlight(entry.id)
            } catch {
                // A local persistence failure marking this entry
                // in-flight. Skipping to the next entry here would send a
                // *later* curation intent ahead of this still-pending
                // earlier one, silently violating this module's own
                // creation-order guarantee (03-VERIFICATION.md WR-01).
                // Stop the pass instead: the entry stays `pending` and the
                // next `drainOnce()` retries it from the front of the
                // queue, in order.
                result.stoppedForRetry = true
                return result
            }

            do {
                _ = try await apiClient.send(
                    method: intent.httpMethod,
                    path: intent.path,
                    body: intent.wireBody,
                    headers: ["Idempotency-Key": entry.idempotencyKey]
                )
                onEntryDelivered?(intent)
                try outbox.markDone(entry.id)
                result.sent += 1
            } catch let error as APIClientError {
                if case .server(let apiError) = error, isPermanentRejection(apiError) {
                    try? outbox.markRejected(entry.id, intent: intent, code: apiError.code)
                    result.rejected += 1
                    if intent.leavesUncorrectableTombstoneOnRejection {
                        onDestructiveRejection?()
                    }
                } else {
                    // Transport failure, 5xx, or a 409 idempotency
                    // conflict (another attempt is already in flight
                    // elsewhere) — all transient. Leave the local row
                    // alone and stop draining so a later entry never
                    // sends ahead of this still-outstanding one.
                    try? outbox.markPendingForRetry(entry, at: now)
                    result.stoppedForRetry = true
                    return result
                }
            } catch {
                try? outbox.markPendingForRetry(entry, at: now)
                result.stoppedForRetry = true
                return result
            }
        }

        return result
    }

    /// A four-hundred-class response other than `409` (idempotency
    /// conflict — another attempt is racing this one, not a rejection of
    /// the mutation itself) is permanent: the server has definitively
    /// refused the intent as submitted, and retrying it verbatim would
    /// only produce the identical refusal forever.
    private func isPermanentRejection(_ error: APIError) -> Bool {
        (400..<500).contains(error.status) && error.status != 409
    }
}
