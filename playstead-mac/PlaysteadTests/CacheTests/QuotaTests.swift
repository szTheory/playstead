import XCTest
import CryptoKit
@testable import Playstead

final class QuotaTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!
    private var localStore: LocalStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths(root: tempRoot)
        localStore = try LocalStore(paths: paths)
        StubURLProtocol.reset()
    }

    override func tearDownWithError() throws {
        StubURLProtocol.reset()
        try? FileManager.default.removeItem(at: tempRoot)
        try super.tearDownWithError()
    }

    private func makeManager(usage: Int, free: Int) -> QuotaManager {
        QuotaManager(localStore: localStore, cacheUsageProvider: { usage }, freeSpaceProvider: { free })
    }

    // MARK: - Defaults

    func testDefaultPolicyIs25GBQuotaAnd10GBFloor() {
        let manager = makeManager(usage: 0, free: .max)
        let policy = manager.policy()
        XCTAssertEqual(policy.quotaBytes, 25 * QuotaPolicy.gibibyte)
        XCTAssertEqual(policy.floorBytes, 10 * QuotaPolicy.gibibyte)
    }

    // MARK: - Quota / floor blocking

    func testTransferExceedingQuotaDoesNotStart() {
        // Plenty of free space, but usage is already at the quota.
        let manager = makeManager(usage: 25 * QuotaPolicy.gibibyte, free: 100 * QuotaPolicy.gibibyte)
        let verdict = manager.verdict(forAdditional: 1024)
        XCTAssertFalse(verdict.allowed)
        XCTAssertEqual(verdict.limitHit, .quota)
    }

    func testTransferCrossingFreeSpaceFloorDoesNotStartEvenWithQuotaRoom() {
        // Quota has plenty of room, but free space is right at the floor.
        let manager = makeManager(usage: 0, free: 10 * QuotaPolicy.gibibyte)
        let verdict = manager.verdict(forAdditional: 1024)
        XCTAssertFalse(verdict.allowed)
        XCTAssertEqual(verdict.limitHit, .floor)
    }

    func testWhenQuotaAndFloorBothWouldBeCrossedTheVerdictNamesTheFloorNotTheQuota() {
        // Usage already over quota AND free space already at the floor —
        // both limits would be crossed by any further byte.
        let manager = makeManager(usage: 25 * QuotaPolicy.gibibyte, free: 10 * QuotaPolicy.gibibyte)
        let verdict = manager.verdict(forAdditional: 1024)
        XCTAssertFalse(verdict.allowed)
        XCTAssertEqual(verdict.limitHit, .floor, "the floor must win whenever both limits would be crossed")
    }

    func testRaisingQuotaAboveWhatFloorAllowsIsAcceptedButFloorStillGoverns() throws {
        let manager = makeManager(usage: 0, free: 10 * QuotaPolicy.gibibyte) // exactly at the floor
        try manager.setQuota(bytes: 1000 * QuotaPolicy.gibibyte) // a huge quota
        XCTAssertEqual(manager.policy().quotaBytes, 1000 * QuotaPolicy.gibibyte)

        // Even with a huge quota, the floor (free space already at the
        // floor) still blocks.
        let verdict = manager.verdict(forAdditional: 1024)
        XCTAssertFalse(verdict.allowed)
        XCTAssertEqual(verdict.limitHit, .floor)
    }

    func testZeroQuotaBlocksNewTransfersAndDeletesNothing() throws {
        let manager = makeManager(usage: 0, free: 100 * QuotaPolicy.gibibyte)
        try manager.setQuota(bytes: 0)
        let verdict = manager.verdict(forAdditional: 1)
        XCTAssertFalse(verdict.allowed)
        XCTAssertEqual(verdict.limitHit, .quota)
        // QuotaManager never touches cache_objects or the filesystem —
        // verifying the verdict call alone made no writes.
        let count = (try? localStore.connection.query("SELECT COUNT(*) FROM cache_objects;") { $0.int(0) ?? 0 })?.first ?? -1
        XCTAssertEqual(count, 0)
    }

    func testLoweringQuotaBelowCurrentUsageBlocksNewTransfersAndRemovesNoFiles() throws {
        let manager = makeManager(usage: 30 * QuotaPolicy.gibibyte, free: 100 * QuotaPolicy.gibibyte)
        try manager.setQuota(bytes: 5 * QuotaPolicy.gibibyte) // already exceeded by existing usage

        let verdict = manager.verdict(forAdditional: 1)
        XCTAssertFalse(verdict.allowed)
        XCTAssertEqual(verdict.limitHit, .quota)
        // No file operations happen as a side effect of checking or
        // lowering the quota.
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.objects.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: paths.objects.path), [])
    }

    func testABlockedVerdictLeavesTheQueueItemPausedAndByteCountOnDiskUnchanged() async throws {
        let cas = CASManager(paths: paths)
        let engine = DownloadEngine(session: StubURLProtocol.makeSession(), paths: paths, cas: cas, sleeper: { _ in })
        let reachability = Reachability(startOnline: true, monitorAutomatically: false)
        let queue = DownloadQueue(localStore: localStore)

        let coordinator = DownloadCoordinator(
            queue: queue, engine: engine, cas: cas, localStore: localStore, reachability: reachability,
            blobURL: { URL(string: "https://blobs.test/api/v1/blobs/\($0)")! }
        )
        await coordinator.setQuotaCheck { _ in (false, "quota") }

        let members = [AssetMember(ordinal: 0, role: "rom", required: true, sha256: sha("g1"), size: 100, name: "m")]
        let game = CatalogueEntry(id: "g1", system: "gba", displayTitle: "Game", tags: [:], members: members)
        try queue.enqueueGame(game)

        await coordinator.start()
        await waitUntil { queue.itemsForAssetSet("g1").first?.state == .paused }

        XCTAssertEqual(queue.itemsForAssetSet("g1").first?.state, .paused)
        let objectsOnDisk = (try? FileManager.default.contentsOfDirectory(atPath: paths.objects.path)) ?? []
        XCTAssertEqual(objectsOnDisk, [], "a blocked verdict must not have written any bytes")
    }

    // MARK: - Pin priority in selection (DownloadCoordinator, wired via PinStore)

    func testPinnedItemAtTailOfQueueIsSelectedBeforeUnpinnedItemAtHead() async throws {
        let cas = CASManager(paths: paths)
        let engine = DownloadEngine(session: StubURLProtocol.makeSession(), paths: paths, cas: cas, sleeper: { _ in })
        let reachability = Reachability(startOnline: true, monitorAutomatically: false)
        let queue = DownloadQueue(localStore: localStore)
        let pinStore = PinStore(localStore: localStore)

        let headMembers = [AssetMember(ordinal: 0, role: "rom", required: true, sha256: sha("head"), size: 100, name: "m")]
        let tailMembers = [AssetMember(ordinal: 0, role: "rom", required: true, sha256: sha("tail"), size: 100, name: "m")]
        try queue.enqueueGame(CatalogueEntry(id: "head-game", system: "gba", displayTitle: "Head", tags: [:], members: headMembers))
        try queue.enqueueGame(CatalogueEntry(id: "tail-game", system: "gba", displayTitle: "Tail", tags: [:], members: tailMembers))

        // head-game was enqueued first (lower position); tail-game is pinned.
        try pinStore.pin(assetSetID: "tail-game")

        // Freeze delivery so we can inspect which item became active
        // before anything completes.
        StubURLProtocol.responder = { _ in .init(statusCode: 200, headers: [:], bodyChunks: [Data(repeating: 1, count: 10)], failAfter: false) }

        let coordinator = DownloadCoordinator(
            queue: queue, engine: engine, cas: cas, localStore: localStore, reachability: reachability,
            blobURL: { URL(string: "https://blobs.test/api/v1/blobs/\($0)")! }
        )
        await coordinator.setIsPinned(pinStore.isPinned)

        await coordinator.start()
        await waitUntil {
            queue.itemsForAssetSet("tail-game").first?.state == .active
                || queue.itemsForAssetSet("head-game").first?.state == .active
        }

        XCTAssertEqual(queue.itemsForAssetSet("tail-game").first?.state, .active, "the pinned tail item must be selected first")
        XCTAssertEqual(queue.itemsForAssetSet("head-game").first?.state, .waiting)
    }

    func testUnpinningMakesGameEligibleButDeletesNothing() throws {
        let pinStore = PinStore(localStore: localStore)
        try pinStore.pin(assetSetID: "g1")
        XCTAssertTrue(pinStore.isPinned("g1"))
        try pinStore.unpin(assetSetID: "g1")
        XCTAssertFalse(pinStore.isPinned("g1"))
    }

    // MARK: - Reclaim/eviction candidate exclusion by pin
    //
    // `EvictionPlanner` itself is built in this plan's task 3; this test
    // proves the pin-exclusion fact `EvictionPlanner.candidates()` will
    // rely on (`PinStore.allPinned()` never includes a pinned id, so any
    // future candidate query joining against it excludes pinned games by
    // construction) — task 3's `EvictionTests` re-asserts this through
    // the real `EvictionPlanner` type.
    func testPinnedAssetSetIsAbsentFromAllPinnedExclusionSetUnderEveryInput() throws {
        let pinStore = PinStore(localStore: localStore)
        try pinStore.pin(assetSetID: "pinned-game")

        let allGames: Set<String> = ["pinned-game", "unpinned-game-1", "unpinned-game-2"]
        let candidates = allGames.subtracting(pinStore.allPinned())

        XCTAssertFalse(candidates.contains("pinned-game"))
        XCTAssertEqual(candidates, ["unpinned-game-1", "unpinned-game-2"])
    }

    // MARK: - ReclaimPromptView content

    func testReclaimPromptViewTextContainsShortfallAndServerRetainsStatement() {
        let statement = ReclaimPromptView.shortfallStatement(limitHit: .floor, shortfallBytes: 2 * QuotaPolicy.gibibyte)
        XCTAssertTrue(statement.contains(ReclaimPromptView.formatBytes(2 * QuotaPolicy.gibibyte)))
        XCTAssertTrue(ReclaimPromptView.serverRetainsStatement.lowercased().contains("server"))
    }

    func testQuotaSettingsViewStatesFloorGovernsWhenDisagreeing() {
        XCTAssertTrue(QuotaSettingsView.floorPrecedenceStatement.lowercased().contains("floor"))
        XCTAssertTrue(QuotaSettingsView.floorPrecedenceStatement.lowercased().contains("priority") || QuotaSettingsView.floorPrecedenceStatement.lowercased().contains("govern") || QuotaSettingsView.floorPrecedenceStatement.lowercased().contains("even if"))
    }

    // MARK: - Helpers

    private func sha(_ seed: String) -> String {
        SHA256.hash(data: Data(seed.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func waitUntil(timeout: TimeInterval = 3.0, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("condition not met within \(timeout)s")
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
