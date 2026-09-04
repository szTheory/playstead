import XCTest
@testable import Playstead

// MARK: - Task 1: SaveAttentionSource (D-38, D-53, D-66)

final class SaveAttentionSourceTests: XCTestCase {
    private func candidate(
        line: String = "line-1", assetSetID: String = "asset-1", title: String = "Metroid Fusion",
        heads: [String] = ["r1", "r2"], origins: [String] = ["This Mac", "Living Room Mac"]
    ) -> SaveAttentionCandidate {
        SaveAttentionCandidate(saveLineID: line, assetSetID: assetSetID, title: title, headRevisionIDs: heads, originNames: origins)
    }

    // MARK: hasUnacknowledgedDivergence

    func testSingleHeadIsNeverDivergent() {
        XCTAssertFalse(SaveAttentionSource.hasUnacknowledgedDivergence(headRevisionIDs: ["r1"], disposedHeadIDs: nil))
    }

    func testTwoHeadsWithNoDispositionIsUnacknowledgedDivergence() {
        XCTAssertTrue(SaveAttentionSource.hasUnacknowledgedDivergence(headRevisionIDs: ["r1", "r2"], disposedHeadIDs: nil))
    }

    func testExactlyMatchingDispositionSuppressesDivergence() {
        XCTAssertFalse(SaveAttentionSource.hasUnacknowledgedDivergence(headRevisionIDs: ["r1", "r2"], disposedHeadIDs: ["r2", "r1"]))
    }

    func testANewHeadSetAfterAPriorDispositionReRaises() {
        XCTAssertTrue(SaveAttentionSource.hasUnacknowledgedDivergence(headRevisionIDs: ["r1", "r3"], disposedHeadIDs: ["r1", "r2"]))
    }

    // MARK: divergenceItems

    func testDivergenceProducesOneAttentionItemWithLockedCopy() {
        let items = SaveAttentionSource.divergenceItems(candidates: [candidate()], disposedHeadIDs: { _ in nil })
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Two versions of your progress in Metroid Fusion")
        XCTAssertEqual(
            items[0].body,
            "You played Metroid Fusion on This Mac and Living Room Mac without them syncing in between. Both versions are saved. Nothing has been overwritten."
        )
        XCTAssertEqual(items[0].primaryAction, "Compare versions")
    }

    func testThreeOrMoreHeadsUsesTheNVariantCopy() {
        let items = SaveAttentionSource.divergenceItems(
            candidates: [candidate(heads: ["r1", "r2", "r3"], origins: ["A", "B", "C"])],
            disposedHeadIDs: { _ in nil }
        )
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "3 versions of your progress in Metroid Fusion")
        XCTAssertTrue(items[0].body.contains("3 devices"))
        XCTAssertTrue(items[0].body.contains("All 3 versions are saved"))
    }

    func testADisposedForkProducesNoAttentionItem() {
        let items = SaveAttentionSource.divergenceItems(
            candidates: [candidate()], disposedHeadIDs: { _ in ["r1", "r2"] }
        )
        XCTAssertTrue(items.isEmpty, "acknowledging (or resolving) a fork must clear its item and it must not be re-raised")
    }

    func testAcknowledgedForkThenNewDivergenceReRaises() {
        // The stored disposition covers an *earlier* head set; the
        // candidate's current heads have moved on -- this is a fresh
        // fork, not the disposed one.
        let items = SaveAttentionSource.divergenceItems(
            candidates: [candidate(heads: ["r1", "r3"])], disposedHeadIDs: { _ in ["r1", "r2"] }
        )
        XCTAssertEqual(items.count, 1)
    }

    // MARK: blockedCaptureItems (carried through from plan 04-06)

    func testAnOpenBlockageRaisesThroughTheSameSource() {
        let row = SaveCaptureBlockedRow(
            id: "b1", saveLineID: "line-1", sessionID: nil, digest: nil, reason: "disk_full",
            firstFailedAt: "t1", lastFailedAt: "t1", failureCount: 1, alerted: true, resolvedAt: nil
        )
        let items = SaveAttentionSource.blockedCaptureItems(
            blockages: [(saveLineID: "line-1", assetSetID: "asset-1", title: "Metroid Fusion", row: row)]
        )
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, SaveVocabulary.blockerSaveDirectoryTitle)
        if case .captureBlocked(let saveLineID) = items[0].reason {
            XCTAssertEqual(saveLineID, "line-1")
        } else {
            XCTFail("expected .captureBlocked reason")
        }
    }

    func testAResolvedBlockageProducesNoAttentionItem() {
        let row = SaveCaptureBlockedRow(
            id: "b1", saveLineID: "line-1", sessionID: nil, digest: nil, reason: "disk_full",
            firstFailedAt: "t1", lastFailedAt: "t1", failureCount: 1, alerted: true, resolvedAt: "t2"
        )
        let items = SaveAttentionSource.blockedCaptureItems(
            blockages: [(saveLineID: "line-1", assetSetID: "asset-1", title: "Metroid Fusion", row: row)]
        )
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: grouped header/action (two or more diverged games)

    func testTwoDivergedGamesProduceTheGroupedHeaderAndSecondaryAction() {
        let items = SaveAttentionSource.divergenceItems(
            candidates: [
                candidate(line: "line-1", assetSetID: "asset-1", title: "Metroid Fusion"),
                candidate(line: "line-2", assetSetID: "asset-2", title: "Pokemon Emerald")
            ],
            disposedHeadIDs: { _ in nil }
        )
        guard let grouped = SaveAttentionSource.groupedDivergenceSummary(items: items) else {
            return XCTFail("expected a grouped summary for two diverged games")
        }
        XCTAssertEqual(grouped.header, "Two versions of your progress in 2 games")
        XCTAssertEqual(grouped.secondaryAction, "Keep both in all 2")
    }

    func testOneDivergedGameProducesNoGroupedSummary() {
        let items = SaveAttentionSource.divergenceItems(candidates: [candidate()], disposedHeadIDs: { _ in nil })
        XCTAssertNil(SaveAttentionSource.groupedDivergenceSummary(items: items))
    }

    // MARK: never a modal/notification/launch prompt (source-scan proof)

    func testSourceNeverReferencesAModalNotificationOrLaunchPromptAPI() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SavesTests
            .deletingLastPathComponent() // PlaysteadTests
            .deletingLastPathComponent() // playstead-mac
            .appendingPathComponent("Playstead/Saves/SaveAttentionSource.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertNil(source.range(of: #"NSAlert|\.alert\(|UNNotification|sheet\(isPresented.*conflict"#, options: [.regularExpression, .caseInsensitive]))
    }

    // MARK: card union (D-38's rank-1 rung, no rebaseline)

    func testUnacknowledgedDivergenceFeedsTheExistingRank1Rung() {
        XCTAssertEqual(LibraryStatus.forSaveState(conflicted: true), .needsAttention)
    }

    func testADisposedForkFeedsNoAttentionOntoTheCard() {
        let disposed = SaveAttentionSource.hasUnacknowledgedDivergence(headRevisionIDs: ["r1", "r2"], disposedHeadIDs: ["r1", "r2"])
        XCTAssertNil(LibraryStatus.forSaveState(conflicted: disposed))
    }
}

// MARK: - Task 3: SaveConflictResolver + SaveIntent + SaveOutbox (D-48, D-49, D-52, D-53)

final class SaveConflictResolverTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!
    private var localStore: LocalStore!
    private var saveStore: SaveStore!
    private var saveOutbox: SaveOutbox!
    private var resolver: SaveConflictResolver!
    private var apiClient: APIClient!

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

    /// Two heads on one line -- `r1` and `r2`, both roots (no parent),
    /// so `SaveStore.fetchHeads` reports both.
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

    private func heads() -> Set<String> { Set(saveStore.fetchHeads(saveLineID: "line-1").map(\.id)) }

    private func origin(for revisionID: String) -> String {
        revisionID == "r1" ? "This Mac" : "Living Room Mac"
    }

    // MARK: Choosing writes local state + enqueues exactly one outbox entry, in one transaction

    func testChoosingWritesLocalDispositionAndEnqueuesExactlyOneOutboxEntry() throws {
        let result = try resolver.chooseSide(saveLineID: "line-1", chosenRevisionID: "r1", headRevisionIDs: ["r1", "r2"], originName: origin)
        XCTAssertEqual(result, .chose(origin: "This Mac", otherOrigins: ["Living Room Mac"]))

        let disposition = saveStore.fetchForkDisposition(saveLineID: "line-1")
        XCTAssertEqual(disposition?.action, .choose)
        XCTAssertEqual(disposition?.chosenRevisionID, "r1")
        XCTAssertEqual(saveOutbox.count(), 1)
    }

    // MARK: Works with no server; the entry drains later

    func testTheWholeChooseFlowCompletesWithTheNetworkTransportFailingEveryRequest() async throws {
        // No `StubURLProtocol.responder` configured at all -- every
        // request fails at the transport layer (`URLError(.unknown)`),
        // simulating "the server is unreachable."
        try resolver.chooseSide(saveLineID: "line-1", chosenRevisionID: "r1", headRevisionIDs: ["r1", "r2"], originName: origin)

        XCTAssertEqual(saveStore.fetchForkDisposition(saveLineID: "line-1")?.chosenRevisionID, "r1")
        XCTAssertEqual(saveOutbox.count(), 1, "the local write and the durable row must both survive an unreachable server")

        let sentWhileUnreachable = await saveOutbox.drainOnce(apiClient: apiClient)
        XCTAssertEqual(sentWhileUnreachable, 0)
        XCTAssertEqual(saveOutbox.count(), 1, "a failed send must leave the entry queued, not lose or delete it")
        XCTAssertEqual(saveStore.fetchForkDisposition(saveLineID: "line-1")?.chosenRevisionID, "r1", "local state must be unaffected by the failed send")

        // The entry drains later once the server is reachable again.
        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 201, headers: [:], body: Data("{}".utf8)) }
        let sentOnceReachable = await saveOutbox.drainOnce(apiClient: apiClient)
        XCTAssertEqual(sentOnceReachable, 1)
        XCTAssertEqual(saveOutbox.count(), 0)
    }

    // MARK: Both sides' artifacts are already local (eager fetch is a caller concern; this asserts nothing here blocks on a fetch)

    func testChoosingNeverReadsOrRequiresTheArtifactBytesThemselves() throws {
        // The resolver only ever touches `save_fork_dispositions` and
        // the outbox -- never `save_revision.local_path` or any blob
        // read. Proven structurally: choosing succeeds even though
        // neither seeded revision has a `localPath`.
        XCTAssertNil(saveStore.fetchRevision(id: "r1")?.localPath)
        XCTAssertNoThrow(try resolver.chooseSide(saveLineID: "line-1", chosenRevisionID: "r1", headRevisionIDs: ["r1", "r2"], originName: origin))
    }

    // MARK: Appends rather than moves; both original heads remain present

    func testBothOriginalHeadsAreStillPresentAfterAResolution() throws {
        let before = heads()
        try resolver.chooseSide(saveLineID: "line-1", chosenRevisionID: "r1", headRevisionIDs: ["r1", "r2"], originName: origin)
        XCTAssertEqual(heads(), before, "resolution must not delete a revision or move a head pointer")
        XCTAssertEqual(heads(), ["r1", "r2"])
    }

    func testKeepBothLeavesBothHeadsStanding() throws {
        let before = heads()
        try resolver.keepBoth(saveLineID: "line-1", headRevisionIDs: ["r1", "r2"], thisDeviceOrigin: "This Mac")
        XCTAssertEqual(heads(), before)
    }

    // MARK: Resolving the same fork twice is idempotent (no second entry, no second resolution)

    func testResolvingTheSameForkTwiceEnqueuesNoSecondEntryAndProducesNoSecondResolution() throws {
        let first = try resolver.chooseSide(saveLineID: "line-1", chosenRevisionID: "r1", headRevisionIDs: ["r1", "r2"], originName: origin)
        XCTAssertNotEqual(first, .noOp)
        XCTAssertEqual(saveOutbox.count(), 1)

        let second = try resolver.chooseSide(saveLineID: "line-1", chosenRevisionID: "r1", headRevisionIDs: ["r1", "r2"], originName: origin)
        XCTAssertEqual(second, .noOp)
        XCTAssertEqual(saveOutbox.count(), 1, "resolving the same fork twice must enqueue no second entry")
    }

    func testKeepBothTwiceEnqueuesNoSecondEntry() throws {
        _ = try resolver.keepBoth(saveLineID: "line-1", headRevisionIDs: ["r1", "r2"], thisDeviceOrigin: "This Mac")
        XCTAssertEqual(saveOutbox.count(), 1)
        let second = try resolver.keepBoth(saveLineID: "line-1", headRevisionIDs: ["r1", "r2"], thisDeviceOrigin: "This Mac")
        XCTAssertEqual(second, .noOp)
        XCTAssertEqual(saveOutbox.count(), 1)
    }

    // MARK: Switching back later appends another resolution

    func testSwitchingBackToTheOtherSideAppendsAnotherResolution() throws {
        _ = try resolver.chooseSide(saveLineID: "line-1", chosenRevisionID: "r1", headRevisionIDs: ["r1", "r2"], originName: origin)
        XCTAssertEqual(saveOutbox.count(), 1)

        let switched = try resolver.chooseSide(saveLineID: "line-1", chosenRevisionID: "r2", headRevisionIDs: ["r1", "r2"], originName: origin)
        XCTAssertEqual(switched, .switchedBack(origin: "Living Room Mac", otherOrigin: "This Mac"))
        XCTAssertEqual(saveOutbox.count(), 2, "switching back is a legitimate new resolution, not suppressed")
        XCTAssertEqual(saveStore.fetchForkDisposition(saveLineID: "line-1")?.chosenRevisionID, "r2")
    }

    // MARK: An acknowledged/resolved fork is never re-raised as an attention item

    func testAResolvedForkIsNeverReRaisedAsAnAttentionItem() throws {
        _ = try resolver.chooseSide(saveLineID: "line-1", chosenRevisionID: "r1", headRevisionIDs: ["r1", "r2"], originName: origin)
        let disposition = saveStore.fetchForkDisposition(saveLineID: "line-1")
        let stillDivergent = SaveAttentionSource.hasUnacknowledgedDivergence(
            headRevisionIDs: Array(heads()), disposedHeadIDs: disposition?.headRevisionIDs
        )
        XCTAssertFalse(stillDivergent)
    }

    func testAnAcknowledgedForkIsNeverReRaisedAsAnAttentionItem() throws {
        _ = try resolver.keepBoth(saveLineID: "line-1", headRevisionIDs: ["r1", "r2"], thisDeviceOrigin: "This Mac")
        let disposition = saveStore.fetchForkDisposition(saveLineID: "line-1")
        let stillDivergent = SaveAttentionSource.hasUnacknowledgedDivergence(
            headRevisionIDs: Array(heads()), disposedHeadIDs: disposition?.headRevisionIDs
        )
        XCTAssertFalse(stillDivergent)
    }

    // MARK: Crash safety -- a failing local mutation leaves no outbox entry

    func testAFailingLocalMutationLeavesNoOutboxEntryBehind() {
        struct Boom: Error {}
        XCTAssertThrowsError(
            try saveOutbox.enqueue(.chooseSide(saveLineID: "line-1", chosenRevisionID: "r1")) { throw Boom() }
        )
        XCTAssertEqual(saveOutbox.count(), 0, "the local write and the durable row are one transaction -- both or neither")
    }

    // MARK: Idempotent retry -- the same entry always sends the same Idempotency-Key

    func testARetryOfTheSameEntrySendsTheIdenticalIdempotencyKey() async throws {
        try resolver.chooseSide(saveLineID: "line-1", chosenRevisionID: "r1", headRevisionIDs: ["r1", "r2"], originName: origin)

        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data()) }
        _ = await saveOutbox.drainOnce(apiClient: apiClient)
        XCTAssertEqual(saveOutbox.count(), 1, "a 500 must leave the entry queued for retry")

        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data()) }
        _ = await saveOutbox.drainOnce(apiClient: apiClient)

        let keys = StubURLProtocol.requestLog.compactMap { $0.value(forHTTPHeaderField: "Idempotency-Key") }
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(keys[0], keys[1], "a retry of the same entry must always replay with the same idempotency key")
    }

    // MARK: Nothing here deletes a revision or moves a head pointer (source-scan proof)

    func testResolverSourceNeverDeletesARevisionOrMovesAHeadPointer() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SavesTests
            .deletingLastPathComponent() // PlaysteadTests
            .deletingLastPathComponent() // playstead-mac
            .appendingPathComponent("Playstead/Saves/SaveConflictResolver.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertNil(source.range(of: #"func delete|removeRevision|setHead"#, options: [.regularExpression, .caseInsensitive]))
    }
}
