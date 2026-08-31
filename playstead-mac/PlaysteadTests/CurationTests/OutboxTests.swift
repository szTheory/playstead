import XCTest
@testable import Playstead

/// Covers every bullet of plan 03-08 task 1's `<behavior>` block — the
/// durable outbox, applied optimistically, replayed idempotently, and
/// reconciled through the journal without duplicating. Reuses
/// `StubURLProtocol` (from `CacheTests`, already shared by
/// `SyncEngineTests`) so no live server is needed.
final class OutboxTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!
    private var localStore: LocalStore!
    private var curationStore: CurationStore!
    private var apiClient: APIClient!
    private var outbox: Outbox!

    private let credential = PairingCredential(
        deviceID: "device-1",
        baseURL: URL(string: "https://sync.test")!,
        token: "test-token"
    )

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths(root: tempRoot)
        localStore = try LocalStore(paths: paths)
        curationStore = CurationStore(localStore: localStore)
        apiClient = APIClient(keychain: KeychainStore(), session: StubURLProtocol.makeSession(), credential: credential)
        outbox = Outbox(localStore: localStore, curationStore: curationStore)
        StubURLProtocol.reset()
    }

    override func tearDownWithError() throws {
        StubURLProtocol.reset()
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    private func makeWorker() -> OutboxWorker {
        OutboxWorker(apiClient: apiClient, outbox: outbox)
    }

    private func problemJSON(code: String) -> Data {
        Data("{\"code\": \"\(code)\", \"title\": \"Problem\"}".utf8)
    }

    // MARK: - Favoriting while offline writes an outbox entry and updates
    // the local read model immediately; the favorite persists across a
    // restart while still unsent.

    func test_favoritingOffline_appliesLocallyAndPersistsAcrossRestart() throws {
        // Every network request stubbed to fail — `enqueue` must never
        // make one in the first place.
        StubURLProtocol.responder = { request in
            XCTFail("no request should be needed to prove the local write — unexpected request to \(request.url?.absoluteString ?? "?")")
            return StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data())
        }

        try outbox.enqueue(.favoriteAdd(id: "fav-1", assetSetID: "asset-1"))

        XCTAssertEqual(curationStore.fetchFavorites().map(\.assetSetID), ["asset-1"])
        let pending = outbox.listPending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.state, .pending)

        // Reopen the store from the same on-disk path — a fresh process
        // would do exactly this on the next launch.
        let reopenedStore = try LocalStore(paths: paths)
        let reopenedCurationStore = CurationStore(localStore: reopenedStore)
        let reopenedOutbox = Outbox(localStore: reopenedStore, curationStore: reopenedCurationStore)

        XCTAssertEqual(reopenedCurationStore.fetchFavorites().map(\.assetSetID), ["asset-1"])
        XCTAssertEqual(reopenedOutbox.listPending().count, 1)
        XCTAssertEqual(reopenedOutbox.listPending().first?.state, .pending)
    }

    // MARK: - When the server becomes reachable, the entry sends once,
    // receives success, and is marked done.

    func test_reachableServer_sendsOnceAndMarksDone() async throws {
        try outbox.enqueue(.favoriteAdd(id: "fav-1", assetSetID: "asset-1"))

        StubURLProtocol.responder = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.path, "/api/v1/curation/favorites/asset-1")
            return StubURLProtocol.Stub(
                statusCode: 200, headers: ["Content-Type": "application/json"],
                body: Data("{\"id\":\"fav-1\",\"asset_set_id\":\"asset-1\"}".utf8)
            )
        }

        let result = await makeWorker().drainOnce()

        XCTAssertEqual(result.sent, 1)
        XCTAssertEqual(result.rejected, 0)
        XCTAssertFalse(result.stoppedForRetry)
        XCTAssertEqual(outbox.listPending().count, 0)
        XCTAssertEqual(outbox.listAll().count, 0, "a successfully sent entry is deleted, not merely marked done")
        XCTAssertEqual(StubURLProtocol.requestLog.count, 1)
    }

    // MARK: - Replaying an entry whose response was never observed
    // produces no second row on the server (same idempotency key value
    // sent on a retry as on the first attempt).

    func test_retry_sendsTheSameIdempotencyKeyAsTheFirstAttempt() async throws {
        try outbox.enqueue(.favoriteAdd(id: "fav-1", assetSetID: "asset-1"))

        // First attempt: transport failure (the response was never
        // observed — the request may or may not have reached the server).
        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data()) }
        let first = await makeWorker().drainOnce()
        XCTAssertTrue(first.stoppedForRetry)
        XCTAssertEqual(outbox.listPending().count, 1, "a 5xx leaves the entry pending for retry")

        // Second attempt (the retry): server now succeeds.
        StubURLProtocol.responder = { request in
            StubURLProtocol.Stub(statusCode: 200, headers: [:], body: Data("{}".utf8))
        }
        _ = await makeWorker().drainOnce()

        XCTAssertEqual(StubURLProtocol.requestLog.count, 2)
        let keys = StubURLProtocol.requestLog.map { $0.value(forHTTPHeaderField: "Idempotency-Key") }
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(keys[0], keys[1], "the same idempotency key must be sent on every attempt of the same intent")
        XCTAssertNotNil(keys[0])
    }

    // MARK: - A permanent rejection reverts the local row and surfaces
    // the server's problem code to the user.

    func test_permanentRejection_revertsLocalRowAndSurfacesProblemCode() async throws {
        try outbox.enqueue(.favoriteAdd(id: "fav-1", assetSetID: "asset-1"))
        XCTAssertEqual(curationStore.fetchFavorites().count, 1)

        StubURLProtocol.responder = { _ in
            StubURLProtocol.Stub(statusCode: 404, headers: [:], body: self.problemJSON(code: "not_found"))
        }

        let result = await makeWorker().drainOnce()

        XCTAssertEqual(result.rejected, 1)
        XCTAssertEqual(curationStore.fetchFavorites().count, 0, "the optimistic local row must be reverted")
        let rejected = outbox.listRejected()
        XCTAssertEqual(rejected.count, 1)
        XCTAssertEqual(rejected.first?.lastErrorCode, "not_found")
    }

    // MARK: - A transient failure retries with backoff and does not
    // revert the local row.

    func test_transientFailure_leavesLocalRowPresentAndEntryPending() async throws {
        try outbox.enqueue(.favoriteAdd(id: "fav-1", assetSetID: "asset-1"))

        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 503, headers: [:], body: Data()) }
        let result = await makeWorker().drainOnce()

        XCTAssertTrue(result.stoppedForRetry)
        XCTAssertEqual(curationStore.fetchFavorites().count, 1, "a 5xx must never revert the optimistic local row")
        let pending = outbox.listPending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.state, .pending)
        XCTAssertEqual(pending.first?.attemptCount, 1)
    }

    // MARK: - Applying the journal entry for an already-optimistically-
    // applied favorite leaves exactly one local row (no duplicate).

    func test_journalApplyAfterOptimisticApply_leavesExactlyOneRow() throws {
        try outbox.enqueue(.favoriteAdd(id: "fav-1", assetSetID: "asset-1"))
        XCTAssertEqual(curationStore.fetchFavorites().count, 1)

        // The authoritative journal entry arrives later, keyed on the
        // same client-generated id — the applier's upsert is a no-op,
        // not a duplicate.
        let entry = JournalEntry(
            entityKind: "curation",
            entityID: "fav-1",
            operation: "upsert",
            payload: .object([
                "type": .string("favorite"),
                "asset_set_id": .string("asset-1"),
                "created_at": .string("2026-08-30T00:00:00Z")
            ])
        )
        let applier = JournalApplier(catalogueStore: CatalogueStore(localStore: localStore), curationStore: curationStore)
        applier.apply([entry])

        XCTAssertEqual(curationStore.fetchFavorites().count, 1)
    }

    // MARK: - A favorite created on the console arrives through the
    // journal without any outbox entry existing.

    func test_journalDeliveredFavorite_requiresNoOutboxEntry() throws {
        XCTAssertEqual(outbox.listAll().count, 0)

        let entry = JournalEntry(
            entityKind: "curation",
            entityID: "console-fav-1",
            operation: "upsert",
            payload: .object([
                "type": .string("favorite"),
                "asset_set_id": .string("asset-2"),
                "created_at": .string("2026-08-30T00:00:00Z")
            ])
        )
        let applier = JournalApplier(catalogueStore: CatalogueStore(localStore: localStore), curationStore: curationStore)
        applier.apply([entry])

        XCTAssertEqual(curationStore.fetchFavorites().map(\.assetSetID), ["asset-2"])
        XCTAssertEqual(outbox.listAll().count, 0)
    }

    // MARK: - Entries send in the order they were created.

    func test_entriesSendInCreationOrder() async throws {
        try outbox.enqueue(.favoriteAdd(id: "fav-1", assetSetID: "asset-1"))
        try outbox.enqueue(.favoriteAdd(id: "fav-2", assetSetID: "asset-2"))
        try outbox.enqueue(.favoriteAdd(id: "fav-3", assetSetID: "asset-3"))

        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 200, headers: [:], body: Data("{}".utf8)) }
        let result = await makeWorker().drainOnce()

        XCTAssertEqual(result.sent, 3)
        let paths = StubURLProtocol.requestLog.map { $0.url?.path }
        XCTAssertEqual(paths, [
            "/api/v1/curation/favorites/asset-1",
            "/api/v1/curation/favorites/asset-2",
            "/api/v1/curation/favorites/asset-3"
        ])
    }

    // MARK: - FavoritesViewModel wiring

    func test_favoritesViewModel_addAndRemoveRoundTripThroughOutbox() throws {
        let viewModel = FavoritesViewModel(curationStore: curationStore, outbox: outbox)
        XCTAssertTrue(viewModel.isEmpty)

        XCTAssertTrue(viewModel.addFavorite(assetSetID: "asset-1"))
        XCTAssertFalse(viewModel.isEmpty)
        XCTAssertTrue(viewModel.isFavorited(assetSetID: "asset-1"))
        XCTAssertFalse(viewModel.addFavorite(assetSetID: "asset-1"), "re-favoriting an already-favorited game is a no-op")
        XCTAssertEqual(outbox.listAll().count, 1)

        XCTAssertTrue(viewModel.removeFavorite(assetSetID: "asset-1"))
        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertEqual(outbox.listAll().count, 2)
    }
}
