import XCTest
@testable import Playstead

/// Proves the curation slice is reachable **from the assembled app**, not
/// merely constructible in isolation.
///
/// Every existing curation/sync suite builds its own `Outbox`,
/// `OutboxWorker` and `SyncEngine` by hand — which is exactly why they all
/// passed while `Outbox`/`OutboxWorker`/`SyncEngine` had no production
/// call site at all (review finding P4-WR-003). This suite deliberately
/// does the opposite: it constructs the real composition root
/// (`AppEnvironment`) against a temporary directory and a stubbed
/// `URLProtocol`, then drives only the code paths the shipped UI drives.
/// If the wiring is removed, these tests fail; a test that constructed the
/// components directly would not.
@MainActor
final class ShellWiringTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!
    private var reachability: Reachability!
    private var environment: AppEnvironment!

    private let credential = PairingCredential(
        deviceID: "device-1",
        baseURL: URL(string: "https://sync.test")!,
        token: "test-token"
    )

    override func setUpWithError() throws {
        try super.setUpWithError()
        StubURLProtocol.reset()
        // Nothing reaches the network unless a test scripts a responder.
        StubURLProtocol.responder = { _ in
            StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data())
        }
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths(root: tempRoot)
        reachability = Reachability(startOnline: true, monitorAutomatically: false)
        let apiClient = APIClient(keychain: KeychainStore(), session: StubURLProtocol.makeSession(), credential: credential)
        environment = AppEnvironment(paths: paths, apiClient: apiClient, reachability: reachability)
    }

    override func tearDownWithError() throws {
        environment = nil
        StubURLProtocol.reset()
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    private func acceptEverything() {
        StubURLProtocol.responder = { _ in
            StubURLProtocol.Stub(statusCode: 200, headers: [:], body: Data("{}".utf8))
        }
    }

    private func seedCatalogue(id: String, system: String, title: String) throws {
        try environment.catalogueStore.upsert(
            CatalogueEntry(id: id, system: system, displayTitle: title, tags: [:], members: [])
        )
        environment.libraryViewModel.refresh()
    }

    // MARK: - A mutation made the way the shell makes it reaches the outbox

    func testFavoritingThroughTheShellReachesTheEnvironmentsOutbox() throws {
        try seedCatalogue(id: "asset-1", system: "gba", title: "Metroid")

        // Exactly what `GameRowView`'s Favorite button invokes.
        environment.toggleFavorite(assetSetID: "asset-1")

        let entries = environment.outbox.listAll()
        XCTAssertEqual(entries.count, 1, "the favorite must land in the app's own shared Outbox")
        XCTAssertEqual(entries.first?.kind, .favoriteAdd)
        XCTAssertTrue(environment.favoritesViewModel.isFavorited(assetSetID: "asset-1"))
    }

    func testQueueingThroughTheShellReachesTheEnvironmentsOutbox() throws {
        try seedCatalogue(id: "asset-1", system: "gba", title: "Metroid")

        XCTAssertTrue(environment.toggleQueued(assetSetID: "asset-1"))

        let entries = environment.outbox.listAll()
        XCTAssertEqual(entries.map(\.kind), [.queueEnqueue])
        XCTAssertTrue(environment.queueViewModel.isQueued(assetSetID: "asset-1"))
    }

    /// All five curation nouns must share one store and one outbox — a
    /// favorite added on Home has to be visible on the Favorites shelf,
    /// and every intent has to drain from the same queue.
    func testEveryCurationViewModelSharesOneStoreAndOneOutbox() throws {
        try seedCatalogue(id: "asset-1", system: "gba", title: "Metroid")

        environment.toggleFavorite(assetSetID: "asset-1")
        XCTAssertTrue(environment.queueViewModel.enqueue(assetSetID: "asset-1"))
        XCTAssertTrue(environment.collectionsViewModel.createCollection(name: "Shelf"))
        XCTAssertTrue(environment.continueViewModel.dismiss(assetSetID: "asset-1"))

        let kinds = environment.outbox.listAll().map(\.kind)
        XCTAssertEqual(Set(kinds), [.favoriteAdd, .queueEnqueue, .collectionCreate, .continueDismiss])

        // Same store, read back through a *different* view model than the
        // one that wrote it.
        XCTAssertEqual(environment.curationStore.fetchFavorites().count, 1)
        XCTAssertFalse(environment.favoritesViewModel.isEmpty)
    }

    // MARK: - The worker is actually running in the assembled app

    func testEnqueueTriggersTheOutboxWorker() async throws {
        acceptEverything()
        try seedCatalogue(id: "asset-1", system: "gba", title: "Metroid")

        let before = environment.drainTrigger.drainCount
        environment.toggleFavorite(assetSetID: "asset-1")
        await environment.drainTrigger.awaitPending()

        XCTAssertGreaterThan(
            environment.drainTrigger.drainCount, before,
            "enqueueing must start an OutboxWorker drain pass in the assembled app"
        )
        XCTAssertTrue(
            environment.outbox.listAll().isEmpty,
            "the worker must actually have sent the entry, not merely been constructed"
        )
        XCTAssertEqual(StubURLProtocol.requestLog.count, 1)
    }

    func testReachabilityRegainedTriggersTheOutboxWorker() async throws {
        try seedCatalogue(id: "asset-1", system: "gba", title: "Metroid")

        // Fails to send while the server is refusing.
        environment.toggleFavorite(assetSetID: "asset-1")
        await environment.drainTrigger.awaitPending()
        XCTAssertEqual(environment.outbox.listAll().count, 1)

        acceptEverything()
        let before = environment.drainTrigger.drainCount
        reachability.simulate(online: false)
        reachability.simulate(online: true)
        await environment.drainTrigger.awaitPending()

        XCTAssertGreaterThan(environment.drainTrigger.drainCount, before)
    }

    func testBecomingActiveTriggersTheOutboxWorker() async throws {
        acceptEverything()
        try seedCatalogue(id: "asset-1", system: "gba", title: "Metroid")

        // An entry left pending by a previous launch — enqueued with the
        // enqueue-time trigger detached, so this test exercises only the
        // `scenePhase == .active` trigger and nothing else.
        environment.outbox.onEnqueue = nil
        try environment.outbox.enqueue(.favoriteAdd(id: "fav-1", assetSetID: "asset-1"))
        XCTAssertEqual(environment.outbox.listAll().count, 1)

        let before = environment.drainTrigger.drainCount
        // Exactly what `PlaysteadApp`'s `scenePhase == .active` observer calls.
        environment.applicationDidBecomeActive()
        await environment.drainTrigger.awaitPending()

        XCTAssertGreaterThan(environment.drainTrigger.drainCount, before)
        XCTAssertTrue(
            environment.outbox.listAll().isEmpty,
            "becoming active must actually drain the leftover entry, not just start a pass"
        )
    }

    /// `OutboxWorker.onEntryDelivered` must be wired to
    /// `PlaySessionRecorder` in the composition root, or a delivered
    /// session would stay marked pending forever.
    func testDeliveredPlaySessionIsMarkedDeliveredThroughTheWiredCallback() async throws {
        acceptEverything()
        let sessionID = environment.playSessionRecorder.began(assetSetID: "asset-1")
        environment.playSessionRecorder.ended(sessionID)
        await environment.drainTrigger.awaitPending()

        let listing = environment.playSessionRecorder.listings().first(where: { $0.session.id == sessionID })
        XCTAssertEqual(listing?.delivered, true)
    }

    // MARK: - Navigation actually routes

    func testEverySidebarSectionRoutesToATitledSurface() throws {
        try seedCatalogue(id: "asset-1", system: "gba", title: "Metroid")
        try seedCatalogue(id: "asset-2", system: "unknown", title: "")

        let entries = SidebarView.entries(
            nonEmptySystemIDs: environment.libraryViewModel.nonEmptySystemIDs,
            hasUnidentified: environment.libraryViewModel.hasUnidentifiedEntries
        )

        // Derived from the real catalogue, not a fixture handed to the view.
        XCTAssertTrue(entries.contains { $0.section == .system("gba") })
        XCTAssertTrue(entries.contains { $0.section == .unidentified })
        XCTAssertFalse(entries.contains { $0.section == .system("psx") })

        for entry in entries {
            XCTAssertFalse(
                LibraryShellView.title(for: entry.section).isEmpty,
                "\(entry.label) must route somewhere, not to a blank pane"
            )
        }
    }

    func testSystemAndUnidentifiedSectionsFilterTheRealCatalogue() throws {
        try seedCatalogue(id: "asset-1", system: "gba", title: "Metroid")
        try seedCatalogue(id: "asset-2", system: "nes", title: "Contra")
        try seedCatalogue(id: "asset-3", system: "unknown", title: "")

        XCTAssertEqual(environment.libraryViewModel.catalogue(forSystemID: "gba").map(\.id), ["asset-1"])
        XCTAssertEqual(environment.libraryViewModel.unidentifiedCatalogue.map(\.id), ["asset-3"])
    }

    // MARK: - Sync sequencing

    /// With an empty mirror and no stored cursor, the first pass is
    /// `SnapshotClient`'s bootstrap; afterwards `SyncEngine` owns the
    /// refresh and stores a cursor. The two never run against the same
    /// stores at once.
    func testFirstSyncBootstrapsFromSnapshotThenSyncEngineTakesOver() async throws {
        XCTAssertNil(environment.cursorStore.load())
        StubURLProtocol.responder = { _ in
            StubURLProtocol.Stub(
                statusCode: 200,
                headers: [:],
                body: Data("""
                {"catalogue":[{"id":"asset-1","system":"gba","display_title":"Metroid","tags":{},"members":[]}],
                 "curation":[],"cursor":"cursor-1","has_more":false,"next_after_id":null}
                """.utf8)
            )
        }

        await environment.syncNow()
        XCTAssertEqual(environment.catalogueStore.count(), 1)
        XCTAssertNil(environment.cursorStore.load(), "the bootstrap path is SnapshotClient's, which stores no cursor")

        // Second pass: the mirror is non-empty, so SyncEngine runs and
        // commits a cursor of its own.
        await environment.syncNow()
        XCTAssertNotNil(environment.cursorStore.load())
    }
}
