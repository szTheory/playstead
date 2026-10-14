import XCTest
@testable import Playstead

/// WINDOWS #89: a row left `in_flight` when the process dies.
///
/// `markInFlight` is the only writer of that state, and every way out of
/// it -- `markDone`, `markRejected`, `markPendingForRetry` -- is reached
/// only from `OutboxWorker.drainOnce`'s in-process handling of a response.
/// Nothing ran at startup. `listPending` selects `state = 'pending'`
/// exclusively, so the row was invisible to every later drain, and
/// `listQuarantined` never saw it either because quarantine is reached
/// only through the attempt counter. Meanwhile `applyOptimistically` had
/// already written the change locally: the local model and the server
/// diverged, permanently, with nothing left to reconcile them.
///
/// These tests own the sweep that ends that. They are deliberately
/// written against a SECOND `Outbox` built on the same `LocalStore`,
/// because that is what a relaunch actually is -- the previous process's
/// in-memory state is gone and only the database survives.
final class OutboxStrandedInFlightTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!
    private var localStore: LocalStore!
    private var curationStore: CurationStore!
    private var outbox: Outbox!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths(root: tempRoot)
        localStore = try LocalStore(paths: paths)
        curationStore = CurationStore(localStore: localStore)
        outbox = Outbox(localStore: localStore, curationStore: curationStore)
    }

    override func tearDownWithError() throws {
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
        try super.tearDownWithError()
    }

    /// A fresh `Outbox` over the same database — the next launch.
    private func relaunchedOutbox() -> Outbox {
        Outbox(localStore: localStore, curationStore: curationStore)
    }

    private func makeReport(assetSetID: String, id: String) -> CurationIntent {
        .availabilityReport(id: id, entries: [AvailabilityReportEntry(assetSetID: assetSetID)])
    }

    /// The window itself. Without the sweep this row is stranded forever.
    func test_aRowStrandedInFlightByTheLastRunIsDrainableAgainAfterRelaunch() throws {
        let entry = try outbox.enqueue(.favoriteAdd(id: "fav-1", assetSetID: "asset-1"))
        try outbox.markInFlight(entry.id)

        // The state the previous process left behind: invisible to every
        // list a drain or the UI consults, but still present and still
        // backed by an optimistic local write.
        XCTAssertTrue(outbox.listPending().isEmpty, "precondition: an in_flight row is not pending")
        XCTAssertTrue(outbox.listQuarantined().isEmpty, "precondition: nor is it quarantined")
        XCTAssertEqual(outbox.listAll().count, 1, "precondition: yet the row is still there")

        let next = relaunchedOutbox()
        XCTAssertEqual(try next.recoverStrandedInFlight(), 1, "the sweep must find the stranded row")

        // One clause per fact: CI keeps file:line and drops assertion text.
        let pending = next.listPending(at: Date().addingTimeInterval(3600))
        XCTAssertEqual(pending.count, 1, "the recovered row must be drainable again")
        XCTAssertEqual(pending.first?.id, entry.id, "and it must be the same row, not a new one")
    }

    /// The replay-safety premise, pinned in storage rather than argued in
    /// a comment. Reverting a request that may already have been applied
    /// is only safe because the server absorbs it as a replay, and that
    /// holds only if the key is byte-identical after a restart.
    func test_aRecoveredRowKeepsTheIdempotencyKeyTheServerWillDedupeOn() throws {
        let entry = try outbox.enqueue(.favoriteAdd(id: "fav-1", assetSetID: "asset-1"))
        try outbox.markInFlight(entry.id)

        let next = relaunchedOutbox()
        try next.recoverStrandedInFlight()

        let recovered = next.listPending(at: Date().addingTimeInterval(3600)).first
        XCTAssertEqual(recovered?.idempotencyKey, entry.idempotencyKey, "a changed key would apply the effect twice")
        XCTAssertEqual(recovered?.idempotencyKey, "favorite_add:\(entry.id)", "and it is the persisted kind:entryID form")
    }

    /// The sweep must not become an infinite replay. A row that strands on
    /// every launch has to terminate somewhere, and `markPendingForRetry`
    /// is what supplies that -- which is the reason the sweep goes through
    /// it rather than issuing a bare `UPDATE ... SET state = 'pending'`.
    func test_aRowThatStrandsEveryLaunchEventuallyQuarantinesRatherThanReplayingForever() throws {
        let entry = try outbox.enqueue(.favoriteAdd(id: "fav-1", assetSetID: "asset-1"))

        for _ in 0..<Outbox.maxAttempts {
            let live = outbox.listAll().first
            XCTAssertNotNil(live, "the row must survive until it quarantines")
            try outbox.markInFlight(live!.id)
            try relaunchedOutbox().recoverStrandedInFlight()
        }

        XCTAssertEqual(outbox.listQuarantined().count, 1, "it must end quarantined, not looping")
        XCTAssertEqual(outbox.listQuarantined().first?.id, entry.id, "and it is the row that kept stranding")
        XCTAssertTrue(
            outbox.listPending(at: Date().addingTimeInterval(86_400)).isEmpty,
            "no backoff window may later revive a quarantined row"
        )
    }

    /// The coupling this window was filed for. The sweep is what makes
    /// WR-07's cross-restart case REACHABLE: before it, an `in_flight` row
    /// at quit could never revert, so the delivered-watermark's protection
    /// was latent. Now it is live, and this is the test that proves it --
    /// a stale report recovered after a newer one already succeeded must
    /// be dropped, not re-sent.
    func test_aStrandedReportIsDroppedRatherThanRevivedBehindANewerDeliveredOne() throws {
        let stale = try outbox.enqueue(
            makeReport(assetSetID: "asset-1", id: "report-1"),
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try outbox.markInFlight(stale.id)

        let newer = try outbox.enqueue(
            makeReport(assetSetID: "asset-2", id: "report-2"),
            at: Date(timeIntervalSince1970: 1_700_000_060)
        )
        // The newer one is delivered; `markDone` deletes its row, so only
        // the watermark remembers it ever existed.
        try outbox.markDone(newer.id)
        XCTAssertEqual(outbox.listAll().count, 1, "precondition: only the stranded row remains")

        try relaunchedOutbox().recoverStrandedInFlight(at: Date(timeIntervalSince1970: 1_700_000_120))

        XCTAssertTrue(outbox.listAll().isEmpty, "the stale report must be dropped, not re-sent after the newer one")
        XCTAssertTrue(
            outbox.listPending(at: Date(timeIntervalSince1970: 1_800_000_000)).isEmpty,
            "and no backoff window may deliver it later either"
        )
    }

    /// The other half of that coupling: the sweep must not become an
    /// excuse to drop ordinary work. Only kinds that declare
    /// `supersedesPending` are ever dropped, and only behind something
    /// strictly newer.
    func test_aStrandedRowWithNothingNewerBehindItIsRecoveredRatherThanDropped() throws {
        let first = try outbox.enqueue(.favoriteAdd(id: "fav-1", assetSetID: "asset-1"))
        let second = try outbox.enqueue(.favoriteAdd(id: "fav-2", assetSetID: "asset-2"))
        try outbox.markInFlight(first.id)
        try outbox.markDone(second.id)

        try relaunchedOutbox().recoverStrandedInFlight()

        let pending = outbox.listPending(at: Date().addingTimeInterval(3600))
        XCTAssertEqual(pending.count, 1, "a non-superseding kind is never dropped by the sweep")
        XCTAssertEqual(pending.first?.id, first.id, "and it is the stranded favourite, recovered")
    }

    /// A sweep with nothing to do must be inert — no counter advanced, no
    /// backoff imposed on rows that were simply waiting their turn.
    func test_aSweepWithNoStrandedRowsLeavesOrdinaryPendingWorkUntouched() throws {
        let entry = try outbox.enqueue(.favoriteAdd(id: "fav-1", assetSetID: "asset-1"))

        XCTAssertEqual(try relaunchedOutbox().recoverStrandedInFlight(), 0, "nothing was stranded")

        let pending = outbox.listPending()
        XCTAssertEqual(pending.count, 1, "the waiting row is still immediately drainable")
        XCTAssertEqual(pending.first?.id, entry.id, "and it is the row that was enqueued")
        XCTAssertEqual(pending.first?.attemptCount, 0, "a no-op sweep must not consume an attempt")
    }
}
