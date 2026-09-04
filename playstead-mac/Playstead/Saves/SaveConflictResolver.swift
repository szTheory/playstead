import Foundation

/// The rendered outcome of a resolution -- what a caller (the
/// comparison sheet's action handlers) turns into one of the locked
/// `result.*` strings. `.noOp` means this exact fork, with this exact
/// action, was already disposed -- nothing was written, nothing was
/// enqueued.
enum SaveConflictResolution: Equatable {
    case chose(origin: String, otherOrigins: [String])
    case switchedBack(origin: String, otherOrigin: String)
    case keptBoth(origin: String)
    case noOp
}

/// Performs a save fork's local mutation and the outbox enqueue in one
/// transaction (via `SaveOutbox.enqueue`), mirroring `Outbox.enqueue`'s
/// documented crash-safety discipline: a crash between the local write
/// and the network send can never lose the entry, because the network
/// send never happens inside this call at all -- `SaveOutbox.drainOnce`
/// is the only thing that touches the network, and it runs later,
/// independently. This is what makes the whole flow work with no server
/// reachable: comparing and choosing are local operations start to
/// finish.
///
/// Resolution appends rather than moves anything: nothing here ever
/// deletes a revision, removes a head, or sets a head pointer -- both
/// original heads remain exactly as `SaveStore.fetchHeads` already
/// tracks them (D-48, D-49). The only thing this type writes is
/// `save_fork_dispositions`' own disposition row.
final class SaveConflictResolver {
    private let saveStore: SaveStore
    private let saveOutbox: SaveOutbox
    private let clock: () -> Date

    init(saveStore: SaveStore, saveOutbox: SaveOutbox, clock: @escaping () -> Date = Date.init) {
        self.saveStore = saveStore
        self.saveOutbox = saveOutbox
        self.clock = clock
    }

    /// Choosing a side. `originName` resolves a revision id to its
    /// display origin -- caller-supplied, same decoupling precedent as
    /// `SaveAttentionCandidate.originNames` and `SaveHistorySession
    /// .deviceName`. Resolving the exact same fork with the exact same
    /// chosen side again is a no-op: no new local write, no new outbox
    /// entry (idempotent by construction, not merely by the outbox's own
    /// per-entry `Idempotency-Key`). Choosing a *different* side than
    /// last time -- "switching back" -- is a legitimate new resolution.
    @discardableResult
    func chooseSide(
        saveLineID: String, chosenRevisionID: String, headRevisionIDs: [String],
        originName: (String) -> String
    ) throws -> SaveConflictResolution {
        let existing = saveStore.fetchForkDisposition(saveLineID: saveLineID)
        if existing?.action == .choose, existing?.chosenRevisionID == chosenRevisionID,
           Set(existing?.headRevisionIDs ?? []) == Set(headRevisionIDs) {
            return .noOp
        }

        let wasASwitchBack = existing?.action == .choose && existing?.chosenRevisionID != chosenRevisionID
        let now = clock()
        try saveOutbox.enqueue(.chooseSide(saveLineID: saveLineID, chosenRevisionID: chosenRevisionID), at: now) {
            try self.saveStore.upsertForkDisposition(
                saveLineID: saveLineID, headRevisionIDs: headRevisionIDs, action: .choose,
                chosenRevisionID: chosenRevisionID, disposedAt: Self.iso8601.string(from: now)
            )
        }

        let otherOrigins = headRevisionIDs.filter { $0 != chosenRevisionID }.map(originName)
        if wasASwitchBack {
            return .switchedBack(origin: originName(chosenRevisionID), otherOrigin: otherOrigins.first ?? "")
        }
        return .chose(origin: originName(chosenRevisionID), otherOrigins: otherOrigins)
    }

    /// "Keep both": enqueues one acknowledgement entry, leaves every
    /// head standing (this function never touches `save_revision` at
    /// all), and marks the fork disposed so `SaveAttentionSource` never
    /// re-raises it for this exact head set (D-52).
    @discardableResult
    func keepBoth(saveLineID: String, headRevisionIDs: [String], thisDeviceOrigin: String) throws -> SaveConflictResolution {
        let existing = saveStore.fetchForkDisposition(saveLineID: saveLineID)
        if existing?.action == .keepBoth, Set(existing?.headRevisionIDs ?? []) == Set(headRevisionIDs) {
            return .noOp
        }

        let now = clock()
        try saveOutbox.enqueue(.acknowledgeFork(saveLineID: saveLineID), at: now) {
            try self.saveStore.upsertForkDisposition(
                saveLineID: saveLineID, headRevisionIDs: headRevisionIDs, action: .keepBoth,
                chosenRevisionID: nil, disposedAt: Self.iso8601.string(from: now)
            )
        }
        return .keptBoth(origin: thisDeviceOrigin)
    }

    private static let iso8601 = ISO8601DateFormatter()
}
