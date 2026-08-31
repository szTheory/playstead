import XCTest
import CryptoKit
@testable import Playstead

final class QueueTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!
    private var localStore: LocalStore!
    private var queue: DownloadQueue!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths(root: tempRoot)
        localStore = try LocalStore(paths: paths)
        queue = DownloadQueue(localStore: localStore)
        StubURLProtocol.reset()
    }

    override func tearDownWithError() throws {
        StubURLProtocol.reset()
        try? FileManager.default.removeItem(at: tempRoot)
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    private func makeGame(id: String, memberSHAs: [String], size: Int = 1024) -> CatalogueEntry {
        let members = memberSHAs.enumerated().map { idx, sha in
            AssetMember(ordinal: idx, role: "rom", required: true, sha256: sha, size: size, name: "member-\(idx)")
        }
        return CatalogueEntry(id: id, system: "gba", displayTitle: "Game \(id)", tags: [:], members: members)
    }

    private func sha(_ seed: String) -> String {
        SHA256.hash(data: Data(seed.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Enqueue behavior

    func testEnqueueingGameCreatesOneRowPerManifestMemberInManifestOrderAtDistinctPositions() throws {
        let shas = [sha("m1"), sha("m2"), sha("m3")]
        let game = makeGame(id: "g1", memberSHAs: shas)

        try queue.enqueueGame(game)

        let items = queue.itemsForAssetSet("g1")
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(Set(items.map(\.sha256)), Set(shas))

        // Manifest order is preserved as position order.
        let orderedByPosition = items.sorted { $0.position < $1.position }
        XCTAssertEqual(orderedByPosition.map(\.sha256), shas)

        // Every position is distinct.
        XCTAssertEqual(Set(items.map(\.position)).count, 3)
    }

    func testEnqueueingSameGameAgainAddsNoRowsAndReturnsSuccess() throws {
        let game = makeGame(id: "g1", memberSHAs: [sha("m1"), sha("m2")])
        try queue.enqueueGame(game)
        XCTAssertEqual(queue.itemsForAssetSet("g1").count, 2)

        try queue.enqueueGame(game) // must not throw — "returns success"
        XCTAssertEqual(queue.itemsForAssetSet("g1").count, 2, "a repeated enqueue must not duplicate rows")
    }

    func testEnqueueingCollectionAddsEveryMemberOfEveryGameInCollectionOrder() throws {
        let g1 = makeGame(id: "g1", memberSHAs: [sha("a")])
        let g2 = makeGame(id: "g2", memberSHAs: [sha("b"), sha("c")])

        try queue.enqueueCollection([g1, g2])

        let all = queue.list()
        XCTAssertEqual(all.count, 3)
        let orderedByPosition = all.sorted { $0.position < $1.position }
        // g1's member(s) precede g2's — the collection's own order.
        XCTAssertEqual(orderedByPosition.map(\.assetSetID), ["g1", "g2", "g2"])
    }

    func testSingleMemberGameEnqueuesIdenticallyToManyMemberGame() throws {
        let single = makeGame(id: "solo", memberSHAs: [sha("only")])
        let many = makeGame(id: "multi", memberSHAs: [sha("x"), sha("y"), sha("z")])

        try queue.enqueueGame(single)
        try queue.enqueueGame(many)

        XCTAssertEqual(queue.itemsForAssetSet("solo").count, 1)
        XCTAssertEqual(queue.itemsForAssetSet("multi").count, 3)
        // Every row across both games starts `.waiting` — no special
        // casing for a single-member game.
        XCTAssertTrue((queue.itemsForAssetSet("solo") + queue.itemsForAssetSet("multi")).allSatisfy { $0.state == .waiting })
    }

    // MARK: - Idempotent unique index

    func testUniqueIndexConvergesConcurrentEnqueuesOfSameMemberToOneRow() throws {
        let memberSHA = sha("concurrent")
        let game = makeGame(id: "g1", memberSHAs: [memberSHA])

        // Two "concurrent" enqueue requests for the same game — modeled
        // sequentially here (the unique index is what guarantees
        // convergence regardless of ordering/timing).
        try queue.enqueueGame(game)
        try queue.enqueueGame(game)

        XCTAssertEqual(queue.itemsForAssetSet("g1").count, 1)
    }

    // MARK: - Pause/resume/cancel/reorder

    func testPauseResumeCancelAndReorderEachActOnExactlyOneRow() throws {
        let shas = [sha("a"), sha("b"), sha("c")]
        try queue.enqueueGame(makeGame(id: "g1", memberSHAs: shas))
        let items = queue.list().sorted { $0.position < $1.position }
        XCTAssertEqual(items.count, 3)

        let target = items[1]
        try queue.pause(id: target.id)
        var refreshed = queue.list()
        XCTAssertEqual(refreshed.first { $0.id == target.id }?.state, .paused)
        // The other two rows are untouched.
        XCTAssertTrue(refreshed.filter { $0.id != target.id }.allSatisfy { $0.state == .waiting })

        try queue.resume(id: target.id)
        refreshed = queue.list()
        XCTAssertEqual(refreshed.first { $0.id == target.id }?.state, .waiting)

        try queue.cancel(id: items[2].id)
        refreshed = queue.list()
        XCTAssertEqual(refreshed.count, 2, "a cancelled row drops out of list()")

        // Reorder: move items[0] to sit after target (items[1]).
        try queue.reorder(id: items[0].id, afterID: target.id, beforeID: nil)
        let reordered = queue.list().sorted { $0.position < $1.position }
        XCTAssertEqual(reordered.map(\.id), [target.id, items[0].id])
    }

    // MARK: - Persistence across relaunch

    func testPausedItemStaysPausedAcrossSimulatedRelaunch() throws {
        let game = makeGame(id: "g1", memberSHAs: [sha("m1")])
        try queue.enqueueGame(game)
        let item = queue.list()[0]
        try queue.pause(id: item.id)

        // Simulate an app relaunch: close nothing explicitly (SQLite has
        // no explicit close in this wrapper), but open a FRESH
        // `LocalStore`/`DownloadQueue` pair against the same on-disk
        // database file, exactly as a new process launch would.
        let relaunchedStore = try LocalStore(paths: paths)
        let relaunchedQueue = DownloadQueue(localStore: relaunchedStore)

        let reloaded = relaunchedQueue.itemsForAssetSet("g1").first
        XCTAssertEqual(reloaded?.state, .paused)
    }

    // MARK: - Reachability / offline handling

    private func chunked(_ data: Data, into count: Int) -> [Data] {
        let size = max(1, data.count / count)
        var chunks: [Data] = []
        var offset = 0
        while offset < data.count {
            let end = min(offset + size, data.count)
            chunks.append(data.subdata(in: offset..<end))
            offset = end
        }
        return chunks
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

    func testOfflineMovesActiveItemToWaitingWithNoErrorStateAndOnlineResumesIt() async throws {
        let cas = CASManager(paths: paths)
        let engine = DownloadEngine(session: StubURLProtocol.makeSession(), paths: paths, cas: cas, sleeper: { _ in })
        let reachability = Reachability(startOnline: true, monitorAutomatically: false)

        let data = Data(repeating: 0x42, count: 400_000)
        let digest = sha256HexOfData(data)
        StubURLProtocol.responder = { [self] _ in .init(statusCode: 200, headers: [:], bodyChunks: chunked(data, into: 10), failAfter: false) }

        let game = makeGame(id: "g1", memberSHAs: [digest], size: data.count)
        try queue.enqueueGame(game)

        let coordinator = DownloadCoordinator(
            queue: queue, engine: engine, cas: cas, localStore: localStore, reachability: reachability,
            blobURL: { URL(string: "https://blobs.test/api/v1/blobs/\($0)")! }
        )

        var sawCancelledState = false
        var sawErrorLikeEvent = false
        let eventTask = Task {
            for await event in coordinator.events {
                if case .digestMismatchRequeued = event { sawErrorLikeEvent = true }
            }
        }

        await coordinator.start()
        await waitUntil { self.queue.itemsForAssetSet("g1").first?.state == .active }

        reachability.simulate(online: false)
        await waitUntil { self.queue.itemsForAssetSet("g1").first?.state == .waiting }
        if queue.itemsForAssetSet("g1").first?.state == .cancelled { sawCancelledState = true }
        XCTAssertFalse(sawCancelledState, "an offline transfer must move to waiting, never a cancelled/error state")

        reachability.simulate(online: true)
        await waitUntil { self.queue.itemsForAssetSet("g1").first?.state == .active }
        // Reachability's return resumed the transfer with no further
        // user action — the item is active again.
        XCTAssertEqual(queue.itemsForAssetSet("g1").first?.state, .active)

        eventTask.cancel()
        XCTAssertFalse(sawErrorLikeEvent)
    }

    private func sha256HexOfData(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
