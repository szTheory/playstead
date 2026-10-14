import XCTest
@testable import Playstead

/// Drain trigger 4/4 (WINDOWS #77): time.
///
/// The other three triggers are edges — an enqueue, reachability being
/// regained, the scene becoming active — and a server that goes away and
/// comes back without this Mac's network changing produces none of them.
/// Proven by hand on 2026-09-13: two entries sat `pending` with
/// `next_retry_at` long past, minutes after the server was answering
/// again, because nothing had fired a pass.
@MainActor
final class OutboxDrainTickerTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!
    private var reachability: Reachability!
    private var environment: AppEnvironment!

    private let credential = PairingCredential(
        deviceID: "device-1", baseURL: URL(string: "https://sync.test")!, token: "test-token"
    )

    override func setUpWithError() throws {
        try super.setUpWithError()
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 200, headers: [:], body: Data("{}".utf8)) }
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths(root: tempRoot)
        reachability = Reachability(startOnline: true, monitorAutomatically: false)
        let apiClient = APIClient(keychain: KeychainStore(), session: StubURLProtocol.makeSession(), credential: credential)
        // A 50 ms interval rather than the production 60 s, so this suite
        // proves the real mechanism instead of a stand-in for it.
        environment = AppEnvironment(
            paths: paths,
            apiClient: apiClient,
            reachability: reachability,
            outboxDrainInterval: 0.05
        )
    }

    override func tearDownWithError() throws {
        environment = nil
        StubURLProtocol.reset()
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
        try super.tearDownWithError()
    }

    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 5, _ message: String) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition(), message)
    }

    // MARK: - The ticker itself

    func testTickerFiresRepeatedlyUntilStopped() async {
        let count = Counter()
        let ticker = OutboxDrainTicker(interval: 0.01) { count.increment() }
        ticker.start()
        await waitUntil({ count.value >= 3 }, "the ticker must keep firing, not fire once")
        ticker.stop()

        let afterStop = count.value
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(count.value, afterStop, "a stopped ticker must not keep firing")
    }

    func testStartIsIdempotentSoASecondStartDoesNotDoubleTheRate() async {
        let count = Counter()
        let ticker = OutboxDrainTicker(interval: 0.05) { count.increment() }
        ticker.start()
        ticker.start()
        ticker.start()
        try? await Task.sleep(nanoseconds: 120_000_000)
        ticker.stop()

        // Three loops would roughly triple this. Two ticks' worth of slack
        // keeps the bound meaningful without being timing-fragile.
        XCTAssertLessThanOrEqual(count.value, 4, "start() must not create a second loop")
    }

    func testTickerDoesNotFireBeforeTheFirstIntervalElapses() async {
        let count = Counter()
        let ticker = OutboxDrainTicker(interval: 5) { count.increment() }
        ticker.start()
        try? await Task.sleep(nanoseconds: 50_000_000)
        ticker.stop()
        XCTAssertEqual(count.value, 0, "starting the ticker must not itself be a drain")
    }

    // MARK: - Wired into the assembled app

    /// The whole point, stated as the scenario that actually happened: an
    /// entry is left `pending` and eligible, the user touches nothing, no
    /// edge fires — and it is delivered anyway.
    ///
    /// `onEnqueue` is detached first (the same technique
    /// `ShellWiringTests` uses for the scene-active trigger) so nothing but
    /// the passage of time can drain this.
    func testAnEligiblePendingEntryIsDeliveredWithNoTriggerAtAll() async throws {
        try environment.catalogueStore.upsert(
            CatalogueEntry(id: "asset-1", system: "gba", displayTitle: "Metroid", tags: [:], members: [])
        )
        environment.outbox.onEnqueue = nil
        try environment.outbox.enqueue(.favoriteAdd(id: "fav-1", assetSetID: "asset-1"))
        XCTAssertEqual(environment.outbox.listAll().count, 1)

        let requestsBefore = StubURLProtocol.requestLog.count
        await waitUntil(
            { environment.outbox.listAll().isEmpty },
            "a pending, eligible entry must drain on time alone -- no enqueue, no reachability change, no scene activation"
        )
        XCTAssertGreaterThan(StubURLProtocol.requestLog.count, requestsBefore, "it must have actually been sent")
        XCTAssertGreaterThan(environment.outboxDrainTicker.tickCount, 0)
    }

    /// The server going away and coming back, which is precisely the
    /// transition `NWPathMonitor` cannot see: the entry fails, is left
    /// pending with a backoff, and is delivered once the server answers
    /// again — without any network change or user action in between.
    func testAServerThatComesBackIsNoticedWithoutAnyNetworkChange() async throws {
        try environment.catalogueStore.upsert(
            CatalogueEntry(id: "asset-1", system: "gba", displayTitle: "Metroid", tags: [:], members: [])
        )
        // The server is down: a transport-level failure, not a rejection,
        // so the entry stays pending rather than being quarantined.
        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 503, headers: [:], body: Data()) }
        environment.outbox.onEnqueue = nil
        let entry = try environment.outbox.enqueue(.favoriteAdd(id: "fav-1", assetSetID: "asset-1"))
        await environment.drainOutbox().value
        XCTAssertEqual(environment.outbox.listAll().count, 1, "a 503 must leave the entry pending, not drop it")

        // The backoff this failure set is in the future; wind it back so
        // the entry is eligible now, exactly as it was on the owner's
        // machine (`next_retry_at` long past, still undelivered).
        try environment.localStore.connection.execute(
            "UPDATE outbox_entries SET next_retry_at = ? WHERE id = ?;",
            params: ["2020-01-01T00:00:00Z", entry.id]
        )

        // The server comes back. Nothing else changes: reachability is
        // untouched, the window is never focused, nothing is enqueued.
        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 200, headers: [:], body: Data("{}".utf8)) }
        await waitUntil(
            { environment.outbox.listAll().isEmpty },
            "a server that came back must be noticed without a reachability edge"
        )
    }
}

/// A `Sendable` tick counter — `OutboxDrainTicker`'s callback is
/// `@Sendable`, so it cannot capture an XCTestCase property directly.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func increment() {
        lock.lock()
        _value += 1
        lock.unlock()
    }
}
