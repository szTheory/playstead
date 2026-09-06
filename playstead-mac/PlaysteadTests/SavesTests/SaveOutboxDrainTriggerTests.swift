import XCTest
@testable import Playstead

/// Covers plan 04-23 task 1's `<behavior>` block: `SaveOutbox` is
/// constructed and drained by real production triggers, closing WINDOWS
/// #42 (a resolved divergence recorded locally but never sent).
final class SaveOutboxDrainTriggerTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!
    private var localStore: LocalStore!
    private var saveStore: SaveStore!
    private var saveOutbox: SaveOutbox!
    private var resolver: SaveConflictResolver!
    private var apiClient: APIClient!

    private let credential = PairingCredential(
        deviceID: "device-1", baseURL: URL(string: "https://sync.test")!, token: "test-token"
    )

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths(root: tempRoot)
        localStore = try LocalStore(paths: paths)
        saveStore = SaveStore(localStore: localStore)
        saveOutbox = SaveOutbox(localStore: localStore)
        resolver = SaveConflictResolver(saveStore: saveStore, saveOutbox: saveOutbox)
        apiClient = APIClient(keychain: KeychainStore(), session: StubURLProtocol.makeSession(), credential: credential)
        StubURLProtocol.reset()
        try seedDivergedLine()
    }

    override func tearDownWithError() throws {
        StubURLProtocol.reset()
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    /// Two heads on one line -- `r1` and `r2`, both roots, mirroring
    /// `SaveConflictResolverTests`'s fixture exactly.
    private func seedDivergedLine() throws {
        try saveStore.resolveLine(contentKey: "content-1", saveKind: "battery", slot: "0", placeholderID: "line-1")
        try saveStore.insertRevision(SaveRevisionRow(
            id: "r1", saveLineID: "line-1", parentRevisionID: nil, blobSHA256: "sha-r1", sizeBytes: 32_768,
            originDeviceID: "device-a", deviceCapturedAt: nil, recordedAt: "2026-01-01T00:00:00Z",
            captureMethod: nil, adapterID: nil, adapterVersion: nil, saveFormat: nil, formatConfidence: nil,
            playSessionID: nil, durability: SaveDurability.uploaded.rawValue, localPath: nil
        ))
        try saveStore.insertRevision(SaveRevisionRow(
            id: "r2", saveLineID: "line-1", parentRevisionID: nil, blobSHA256: "sha-r2", sizeBytes: 32_768,
            originDeviceID: "device-b", deviceCapturedAt: nil, recordedAt: "2026-01-01T01:00:00Z",
            captureMethod: nil, adapterID: nil, adapterVersion: nil, saveFormat: nil, formatConfidence: nil,
            playSessionID: nil, durability: SaveDurability.uploaded.rawValue, localPath: nil
        ))
    }

    private func origin(for revisionID: String) -> String {
        revisionID == "r1" ? "This Mac" : "Living Room Mac"
    }

    // MARK: - Enqueuing a choose-side intent starts exactly one drain pass.

    func testEnqueuingAChooseSideIntentStartsExactlyOneDrainPass() throws {
        let trigger = SaveOutboxDrainTrigger(saveOutbox: saveOutbox, apiClient: apiClient)
        saveOutbox.onEnqueue = { trigger.fire() }
        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 201, headers: [:], body: Data("{}".utf8)) }

        XCTAssertEqual(trigger.drainCount, 0)
        _ = try resolver.chooseSide(saveLineID: "line-1", chosenRevisionID: "r1", headRevisionIDs: ["r1", "r2"], originName: origin)
        XCTAssertEqual(trigger.drainCount, 1)

        await_(trigger)
        XCTAssertEqual(saveOutbox.count(), 0, "the drain the enqueue started should have delivered the entry")
    }

    /// A local mutation that throws must never fire the trigger — a
    /// drain over an entry that was never committed is meaningless.
    func testAFailingLocalMutationNeverFiresTheTrigger() {
        let trigger = SaveOutboxDrainTrigger(saveOutbox: saveOutbox, apiClient: apiClient)
        saveOutbox.onEnqueue = { trigger.fire() }
        struct Boom: Error {}

        XCTAssertThrowsError(try saveOutbox.enqueue(.chooseSide(saveLineID: "line-1", chosenRevisionID: "r1")) { throw Boom() })
        XCTAssertEqual(trigger.drainCount, 0)
    }

    // MARK: - Reachability transitioning online/offline

    func testReachabilityOnlineStartsADrainPassAndOfflineStartsNone() throws {
        let trigger = SaveOutboxDrainTrigger(saveOutbox: saveOutbox, apiClient: apiClient)
        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 201, headers: [:], body: Data("{}".utf8)) }
        try resolver.chooseSide(saveLineID: "line-1", chosenRevisionID: "r1", headRevisionIDs: ["r1", "r2"], originName: origin)

        // Simulate what `AppEnvironment.init`'s `reachability.onChange`
        // closure does: fire only on `isOnline == true`.
        func onReachabilityChange(isOnline: Bool) {
            guard isOnline else { return }
            trigger.fire()
        }

        onReachabilityChange(isOnline: false)
        XCTAssertEqual(trigger.drainCount, 0, "a transition to offline must start no drain pass")

        onReachabilityChange(isOnline: true)
        XCTAssertEqual(trigger.drainCount, 1)
        await_(trigger)
        XCTAssertEqual(saveOutbox.count(), 0)
    }

    // MARK: - applicationDidBecomeActive() starts a drain pass (via AppEnvironment).

    @MainActor
    func testApplicationDidBecomeActiveStartsADrainPassOnTheRealAppEnvironment() async throws {
        // A fresh root, distinct from `tempRoot`/`paths` above (which
        // `setUpWithError` already seeded via `seedDivergedLine()` --
        // reusing it here would collide on `line-1`'s primary key).
        let environmentRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: environmentRoot) }
        let environment = AppEnvironment(
            paths: AppPaths(root: environmentRoot), apiClient: apiClient,
            reachability: Reachability(startOnline: true, monitorAutomatically: false)
        )
        try seedCatalogueAndForkOnEnvironment(environment)
        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 201, headers: [:], body: Data("{}".utf8)) }

        _ = environment.resolveSaveDivergence(assetSetID: "asset-1", chosenRevisionID: "r1")
        // The post-enqueue trigger already started one pass -- await it,
        // then reset the requestLog to isolate the scene-active trigger's
        // own send below.
        await environment.saveOutboxDrainTrigger.awaitPending()

        let countBefore = environment.saveOutboxDrainTrigger.drainCount
        environment.applicationDidBecomeActive()
        await environment.saveOutboxDrainTrigger.awaitPending()
        XCTAssertGreaterThan(environment.saveOutboxDrainTrigger.drainCount, countBefore)
    }

    // MARK: - A drain whose send succeeds deletes the entry; a second drain sends nothing.

    func testASuccessfulDrainDeletesTheEntryAndASecondDrainSendsNothing() async throws {
        try resolver.chooseSide(saveLineID: "line-1", chosenRevisionID: "r1", headRevisionIDs: ["r1", "r2"], originName: origin)
        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 201, headers: [:], body: Data("{}".utf8)) }

        let trigger = SaveOutboxDrainTrigger(saveOutbox: saveOutbox, apiClient: apiClient)
        _ = await trigger.fire().value
        XCTAssertTrue(saveOutbox.listPending().isEmpty)

        let sentAgain = await trigger.fire().value
        XCTAssertEqual(sentAgain, 0, "a second drain over an already-delivered entry must send nothing")
    }

    // MARK: - A rejected send leaves the entry queued and increments attempt_count, leaving disposition untouched.

    func testARejectedSendLeavesTheEntryQueuedAndDispositionUntouched() async throws {
        try resolver.chooseSide(saveLineID: "line-1", chosenRevisionID: "r1", headRevisionIDs: ["r1", "r2"], originName: origin)
        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data()) }

        let trigger = SaveOutboxDrainTrigger(saveOutbox: saveOutbox, apiClient: apiClient)
        _ = await trigger.fire().value

        let pending = saveOutbox.listPending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.attemptCount, 1)

        let disposition = saveStore.fetchForkDisposition(saveLineID: "line-1")
        XCTAssertEqual(disposition?.chosenRevisionID, "r1")
        XCTAssertEqual(Set(saveStore.fetchHeads(saveLineID: "line-1").map(\.id)), ["r1", "r2"], "every head must still stand after a rejected send")
    }

    // MARK: - Two overlapping drain passes over one entry produce at most one successful send.

    func testTwoOverlappingDrainPassesProduceAtMostOneSuccessfulSend() async throws {
        try resolver.chooseSide(saveLineID: "line-1", chosenRevisionID: "r1", headRevisionIDs: ["r1", "r2"], originName: origin)
        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 201, headers: [:], body: Data("{}".utf8)) }

        let trigger = SaveOutboxDrainTrigger(saveOutbox: saveOutbox, apiClient: apiClient)
        let first = trigger.fire()
        let second = trigger.fire()

        let firstSent = await first.value
        let secondSent = await second.value
        XCTAssertEqual(firstSent + secondSent, 1, "exactly one send must have succeeded across both overlapping passes")
        XCTAssertTrue(saveOutbox.listPending().isEmpty)
    }

    // MARK: - Every send carries the entry's own Idempotency-Key; a retry replays the same key.

    func testEverySendCarriesTheEntrysIdempotencyKeyAndARetryReplaysTheSameKey() async throws {
        try resolver.chooseSide(saveLineID: "line-1", chosenRevisionID: "r1", headRevisionIDs: ["r1", "r2"], originName: origin)
        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data()) }

        let trigger = SaveOutboxDrainTrigger(saveOutbox: saveOutbox, apiClient: apiClient)
        _ = await trigger.fire().value
        _ = await trigger.fire().value

        let keys = StubURLProtocol.requestLog.compactMap { $0.value(forHTTPHeaderField: "Idempotency-Key") }
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(keys[0], keys[1], "a retry of the same entry must always replay with the same idempotency key")
    }

    // MARK: - A test resolves a real divergence through the production entry point and asserts the wire request.

    @MainActor
    func testResolvingThroughTheProductionEntryPointReachesTheWireWithTheRightPathAndKey() async throws {
        // A fresh root, distinct from `tempRoot`/`paths` above -- see the
        // comment in the scene-active test.
        let environmentRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: environmentRoot) }
        let environment = AppEnvironment(
            paths: AppPaths(root: environmentRoot), apiClient: apiClient,
            reachability: Reachability(startOnline: true, monitorAutomatically: false)
        )
        try seedCatalogueAndForkOnEnvironment(environment)
        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 201, headers: [:], body: Data("{}".utf8)) }

        _ = environment.resolveSaveDivergence(assetSetID: "asset-1", chosenRevisionID: "r1")
        await environment.saveOutboxDrainTrigger.awaitPending()

        guard let request = StubURLProtocol.requestLog.first else {
            return XCTFail("expected the resolution to reach the wire")
        }
        XCTAssertEqual(request.url?.path, "/api/v1/saves/lines/line-1/resolve")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "Idempotency-Key"))
        XCTAssertTrue(environment.saveOutbox.listPending().isEmpty)
    }

    // MARK: - Helpers

    /// A syntactically valid 64-character lowercase hex digest --
    /// `PathSafety` rejects a server-supplied member `sha256` that isn't
    /// one, so a placeholder like `"content-1"` is not usable here the
    /// way it is in `seedDivergedLine()` (which never routes through
    /// `catalogueStore.upsert`).
    private static let validContentKey = String(repeating: "a1", count: 32)

    /// Seeds an `AppEnvironment`'s own `catalogueStore`/`saveStore` with
    /// one catalogue entry and a diverged line matching that entry's
    /// content key, so `resolveSaveDivergence`'s production lookup
    /// (`catalogueEntry` -> `saveLine`) resolves to `line-1` exactly like
    /// `seedDivergedLine()` above.
    @MainActor
    private func seedCatalogueAndForkOnEnvironment(_ environment: AppEnvironment) throws {
        try environment.catalogueStore.upsert(CatalogueEntry(
            id: "asset-1", system: "gba", displayTitle: "Test Game", tags: [:],
            members: [AssetMember(ordinal: 0, role: "rom", required: true, sha256: Self.validContentKey, size: 32_768, name: "game.gba")]
        ))
        try environment.saveStore.resolveLine(contentKey: Self.validContentKey, saveKind: "battery", slot: "0", placeholderID: "line-1")
        try environment.saveStore.insertRevision(SaveRevisionRow(
            id: "r1", saveLineID: "line-1", parentRevisionID: nil, blobSHA256: "sha-r1", sizeBytes: 32_768,
            originDeviceID: "device-a", deviceCapturedAt: nil, recordedAt: "2026-01-01T00:00:00Z",
            captureMethod: nil, adapterID: nil, adapterVersion: nil, saveFormat: nil, formatConfidence: nil,
            playSessionID: nil, durability: SaveDurability.uploaded.rawValue, localPath: nil
        ))
        try environment.saveStore.insertRevision(SaveRevisionRow(
            id: "r2", saveLineID: "line-1", parentRevisionID: nil, blobSHA256: "sha-r2", sizeBytes: 32_768,
            originDeviceID: "device-b", deviceCapturedAt: nil, recordedAt: "2026-01-01T01:00:00Z",
            captureMethod: nil, adapterID: nil, adapterVersion: nil, saveFormat: nil, formatConfidence: nil,
            playSessionID: nil, durability: SaveDurability.uploaded.rawValue, localPath: nil
        ))
    }

    private func await_(_ trigger: SaveOutboxDrainTrigger) {
        let expectation = expectation(description: "drain pass completes")
        Task {
            await trigger.awaitPending()
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }
}
