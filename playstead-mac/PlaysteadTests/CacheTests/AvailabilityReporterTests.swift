import XCTest
import CryptoKit
@testable import Playstead

/// Plan 03-14 (LIBR-02 gap closure, Task 1)'s `<behavior>`: a Mac client
/// that has cached, pinned, or is downloading content actually reports
/// those facts, as a full-replacement, after-the-fact outbox producer
/// that never touches a launch path.
final class AvailabilityReporterTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!
    private var localStore: LocalStore!
    private var cas: CASManager!
    private var pinStore: PinStore!
    private var downloadQueue: DownloadQueue!
    private var catalogueStore: CatalogueStore!
    private var curationStore: CurationStore!
    private var outbox: Outbox!
    private var apiClient: APIClient!
    private var reporter: AvailabilityReporter!

    private let credential = PairingCredential(
        deviceID: "device-1", baseURL: URL(string: "https://sync.test")!, token: "test-token"
    )

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths(root: tempRoot)
        localStore = try LocalStore(paths: paths)
        cas = CASManager(paths: paths)
        pinStore = PinStore(localStore: localStore)
        downloadQueue = DownloadQueue(localStore: localStore)
        catalogueStore = CatalogueStore(localStore: localStore)
        curationStore = CurationStore(localStore: localStore)
        outbox = Outbox(localStore: localStore, curationStore: curationStore)
        apiClient = APIClient(keychain: KeychainStore(), session: StubURLProtocol.makeSession(), credential: credential)
        reporter = AvailabilityReporter(
            localStore: localStore, downloadQueue: downloadQueue, cas: cas, pinStore: pinStore, outbox: outbox
        )
        StubURLProtocol.reset()
    }

    override func tearDownWithError() throws {
        StubURLProtocol.reset()
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    @discardableResult
    private func seedCachedObject(seed: String, bytes: Int = 256) throws -> String {
        var raw = [UInt8](repeating: 0, count: bytes)
        for i in 0..<bytes { raw[i] = UInt8((Int(seed.utf8.first ?? 1) &+ i * 7) & 0xFF) }
        let data = Data(raw)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        try FileManager.default.createDirectory(at: paths.partials, withIntermediateDirectories: true)
        let partial = try paths.partialURL(for: digest)
        try data.write(to: partial)
        try cas.commit(partialAt: partial, sha256: digest)

        try localStore.connection.execute(
            """
            INSERT OR REPLACE INTO cache_objects (sha256, size, committed_at, last_used_at, verify_size, verify_inode, verify_mtime_ms)
            VALUES (?, ?, ?, ?, ?, 0, 0);
            """,
            params: [digest, bytes, "2026-01-01T00:00:00Z", "2026-01-01T00:00:00Z", bytes]
        )
        return digest
    }

    private func catalogueEntry(id: String, requiredSHA: String) -> CatalogueEntry {
        CatalogueEntry(
            id: id, system: "gba", displayTitle: "Test Game \(id)", tags: [:],
            members: [AssetMember(ordinal: 0, role: "rom", required: true, sha256: requiredSHA, size: 256, name: "game.gba")]
        )
    }

    /// Multi-member variant: one `CatalogueEntry` with `requiredSHAs.count`
    /// required members, each a distinct manifest position — used by the
    /// missing-dependency predicate tests (plan 03-15), which need to
    /// distinguish "this member is orphaned" from "that member is
    /// orphaned" within the same game.
    private func catalogueEntry(id: String, requiredSHAs: [String]) -> CatalogueEntry {
        CatalogueEntry(
            id: id, system: "gba", displayTitle: "Test Game \(id)", tags: [:],
            members: requiredSHAs.enumerated().map { ordinal, sha in
                AssetMember(ordinal: ordinal, role: "rom", required: true, sha256: sha, size: 256, name: "game-\(ordinal).gba")
            }
        )
    }


    // MARK: - Fully cached and pinned -> verified true, pinned true

    func test_allRequiredMembersCachedAndPinned_emitsVerifiedAndPinnedTrue() async throws {
        let digest = try seedCachedObject(seed: "a")
        let entry = catalogueEntry(id: "game-1", requiredSHA: digest)
        try catalogueStore.upsert(entry)
        try pinStore.pin(assetSetID: "game-1")

        let entries = await reporter.buildEntries(catalogue: [entry])
        XCTAssertEqual(entries.count, 1)
        let report = try XCTUnwrap(entries.first)
        XCTAssertEqual(report.assetSetID, "game-1")
        XCTAssertTrue(report.verified)
        XCTAssertTrue(report.pinned)
        XCTAssertFalse(report.downloading)
    }

    // MARK: - Active transfer -> downloading true, percent 0...100

    func test_activeTransfer_emitsDownloadingTrueWithPercentInRange() async throws {
        let digest = "b" + String(repeating: "0", count: 63)
        let entry = catalogueEntry(id: "game-2", requiredSHA: digest)
        try catalogueStore.upsert(entry)
        try downloadQueue.enqueueGame(entry)
        let item = try XCTUnwrap(downloadQueue.itemsForAssetSet("game-2").first)
        try downloadQueue.markActive(id: item.id)

        let entries = await reporter.buildEntries(catalogue: [entry])
        let report = try XCTUnwrap(entries.first)
        XCTAssertTrue(report.downloading)
        XCTAssertFalse(report.verified)
        XCTAssertGreaterThanOrEqual(report.downloadPercent, 0)
        XCTAssertLessThanOrEqual(report.downloadPercent, 100)
    }

    func test_activeTransfer_reportsInjectedLivePercent() async throws {
        let digest = "c" + String(repeating: "0", count: 63)
        let entry = catalogueEntry(id: "game-live", requiredSHA: digest)
        try catalogueStore.upsert(entry)
        try downloadQueue.enqueueGame(entry)
        let item = try XCTUnwrap(downloadQueue.itemsForAssetSet("game-live").first)
        try downloadQueue.markActive(id: item.id)

        let liveReporter = AvailabilityReporter(
            localStore: localStore, downloadQueue: downloadQueue, cas: cas, pinStore: pinStore, outbox: outbox,
            activeTransferPercent: { assetSetID in assetSetID == "game-live" ? 42 : nil }
        )
        let entries = await liveReporter.buildEntries(catalogue: [entry])
        let report = try XCTUnwrap(entries.first)
        XCTAssertTrue(report.downloading)
        XCTAssertEqual(report.downloadPercent, 42)
    }

    // MARK: - No local bytes, no queue row -> every fact false, never omitted

    func test_noLocalBytesAndNoQueueRow_emitsAllFactsFalseNeverOmitted() async throws {
        let digest = "d" + String(repeating: "0", count: 63)
        let entry = catalogueEntry(id: "game-3", requiredSHA: digest)
        try catalogueStore.upsert(entry)

        let entries = await reporter.buildEntries(catalogue: [entry])
        XCTAssertEqual(entries.count, 1, "the game must still get an entry, not be omitted")
        let report = try XCTUnwrap(entries.first)
        XCTAssertFalse(report.downloading)
        XCTAssertFalse(report.verified)
        XCTAssertFalse(report.pinned)
        XCTAssertFalse(report.missingDependency)
        XCTAssertEqual(report.downloadPercent, 0)
    }

    // MARK: - The encoded request body decodes into exactly the field
    // names the server controller accepts.

    func test_encodedBodyDecodesIntoExactServerFieldNames() throws {
        let entryPayload = AvailabilityReportEntry(
            assetSetID: "asset-1", downloading: true, verified: false, pinned: true,
            missingDependency: false, downloadPercent: 55
        )
        let intent = CurationIntent.availabilityReport(id: "report-1", entries: [entryPayload])
        let body = try XCTUnwrap(intent.wireBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let entries = try XCTUnwrap(json["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 1)
        let first = entries[0]
        XCTAssertEqual(first["asset_set_id"] as? String, "asset-1")
        XCTAssertEqual(first["downloading"] as? Bool, true)
        XCTAssertEqual(first["verified"] as? Bool, false)
        XCTAssertEqual(first["pinned"] as? Bool, true)
        XCTAssertEqual(first["missing_dependency"] as? Bool, false)
        XCTAssertEqual(first["download_percent"] as? Int, 55)
        // No stray field names — a field renamed on either side would
        // introduce or remove a key here.
        XCTAssertEqual(Set(first.keys), ["asset_set_id", "downloading", "verified", "pinned", "missing_dependency", "download_percent"])
    }

    // MARK: - The same report enqueued twice (a retry) carries the same
    // idempotency key and results in one server-side effect.

    func test_sameReportRetried_carriesSameIdempotencyKeyAndOneServerEffect() async throws {
        let entry = catalogueEntry(id: "game-4", requiredSHA: "e" + String(repeating: "0", count: 63))
        try catalogueStore.upsert(entry)

        _ = await reporter.reportAll()
        let outboxEntry = try XCTUnwrap(outbox.listAll().first(where: { $0.kind == .availabilityReport }))

        // First attempt: transport failure — never observed by the client.
        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data()) }
        let worker = OutboxWorker(apiClient: apiClient, outbox: outbox)
        _ = await worker.drainOnce()

        var effects = Set<String>()
        StubURLProtocol.responder = { request in
            if let key = request.value(forHTTPHeaderField: "Idempotency-Key") {
                effects.insert(key)
            }
            return StubURLProtocol.Stub(statusCode: 200, headers: [:], body: Data("{}".utf8))
        }
        _ = await worker.drainOnce(at: Date().addingTimeInterval(Outbox.retryDelay(forAttempt: 1) + 1))

        XCTAssertEqual(StubURLProtocol.requestLog.count, 2, "the client sent two requests (the retry)")
        XCTAssertEqual(effects.count, 1, "both attempts carried the same idempotency key")
        XCTAssertEqual(effects.first, outboxEntry.idempotencyKey)
    }

    // MARK: - With the server unreachable, the report is enqueued and
    // drained later; no error surfaces and nothing is launch-affecting.

    func test_offlineReport_isEnqueuedAndDrainedLaterWithNoSurfacedError() async throws {
        let entry = catalogueEntry(id: "game-5", requiredSHA: "f" + String(repeating: "0", count: 63))
        try catalogueStore.upsert(entry)

        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data()) }

        // `reportAll()` is not `throws` at the Swift level -- reaching
        // the assertions below at all is the proof no error surfaced.
        _ = await reporter.reportAll()
        XCTAssertEqual(outbox.listAll().filter { $0.kind == .availabilityReport }.count, 1)

        let worker = OutboxWorker(apiClient: apiClient, outbox: outbox)
        let offlineResult = await worker.drainOnce()
        XCTAssertTrue(offlineResult.stoppedForRetry)
        XCTAssertEqual(outbox.listAll().filter { $0.kind == .availabilityReport }.count, 1, "still queued, not lost")

        StubURLProtocol.responder = { _ in StubURLProtocol.Stub(statusCode: 200, headers: [:], body: Data("{}".utf8)) }
        let onlineResult = await worker.drainOnce(at: Date().addingTimeInterval(Outbox.retryDelay(forAttempt: 1) + 1))
        XCTAssertEqual(onlineResult.sent, 1)
        XCTAssertEqual(outbox.listAll().filter { $0.kind == .availabilityReport }.count, 0, "delivered and removed")
    }

    // MARK: - Full-replacement: every catalogue game gets an entry, not
    // just the ones with a non-trivial fact.

    func test_reportAll_includesEveryCatalogueGameInOneFullReplacementBody() async throws {
        let cachedDigest = try seedCachedObject(seed: "g")
        let cachedEntry = catalogueEntry(id: "game-cached", requiredSHA: cachedDigest)
        let plainEntry = catalogueEntry(id: "game-plain", requiredSHA: "1" + String(repeating: "0", count: 63))
        try catalogueStore.upsert(cachedEntry)
        try catalogueStore.upsert(plainEntry)

        _ = await reporter.reportAll()
        let outboxEntry = try XCTUnwrap(outbox.listAll().first(where: { $0.kind == .availabilityReport }))
        guard case .availabilityReport(_, let entries) = outboxEntry.intent else {
            return XCTFail("expected an availabilityReport intent")
        }
        XCTAssertEqual(Set(entries.map(\.assetSetID)), ["game-cached", "game-plain"])
    }

    // MARK: - Plan 03-15: missing_dependency as a computed fact, not a
    // constant. Two required members per game so "this member is
    // orphaned" and "that member is not" can be distinguished within one
    // entry.

    func test_requiredMemberAbsentWithNoQueueRow_reportsMissingDependencyTrue() async throws {
        let cachedDigest = try seedCachedObject(seed: "h1")
        let orphanedDigest = "a2" + String(repeating: "0", count: 62)
        let entry = catalogueEntry(id: "game-orphan-1", requiredSHAs: [cachedDigest, orphanedDigest])
        try catalogueStore.upsert(entry)

        let entries = await reporter.buildEntries(catalogue: [entry])
        let report = try XCTUnwrap(entries.first)
        XCTAssertTrue(report.missingDependency, "one required member is absent with no queue row of any kind")
        XCTAssertFalse(report.verified, "not every required member is cached")
    }

    func test_pinnedGameWithEvictedRequiredMember_reportsMissingDependencyTrue() async throws {
        let evictedDigest = "a3" + String(repeating: "0", count: 62)
        let entry = catalogueEntry(id: "game-pinned-evicted", requiredSHAs: [evictedDigest])
        try catalogueStore.upsert(entry)
        try pinStore.pin(assetSetID: "game-pinned-evicted")

        let entries = await reporter.buildEntries(catalogue: [entry])
        let report = try XCTUnwrap(entries.first)
        XCTAssertTrue(report.pinned)
        XCTAssertTrue(report.missingDependency, "the pin itself is engagement; the required member is gone and unqueued")
    }

    func test_absentMemberWithWaitingQueueRow_reportsMissingDependencyFalse() async throws {
        let cachedDigest = try seedCachedObject(seed: "h4")
        let waitingDigest = "a5" + String(repeating: "0", count: 62)
        let entry = catalogueEntry(id: "game-waiting", requiredSHAs: [cachedDigest, waitingDigest])
        try catalogueStore.upsert(entry)
        try downloadQueue.enqueueGame(entry)
        // enqueueGame enqueues every required member; the cached one's
        // row is harmless to leave present -- only the waiting member's
        // queue state matters to this predicate.

        let entries = await reporter.buildEntries(catalogue: [entry])
        let report = try XCTUnwrap(entries.first)
        XCTAssertFalse(report.missingDependency, "a waiting queue row means the member is coming, not missing")
    }

    func test_absentMemberWithPausedQueueRow_reportsMissingDependencyFalse() async throws {
        let cachedDigest = try seedCachedObject(seed: "h6")
        let pausedDigest = "a7" + String(repeating: "0", count: 62)
        let entry = catalogueEntry(id: "game-paused", requiredSHAs: [cachedDigest, pausedDigest])
        try catalogueStore.upsert(entry)
        try downloadQueue.enqueueGame(entry)
        let pausedItem = try XCTUnwrap(downloadQueue.itemsForAssetSet("game-paused").first { $0.sha256 == pausedDigest })
        try downloadQueue.pause(id: pausedItem.id)

        let entries = await reporter.buildEntries(catalogue: [entry])
        let report = try XCTUnwrap(entries.first)
        XCTAssertFalse(report.missingDependency, "a paused row is still in the queue")
    }

    func test_absentMemberWithOnlyCancelledQueueRow_reportsMissingDependencyTrue() async throws {
        let cachedDigest = try seedCachedObject(seed: "h8")
        let cancelledDigest = "a9" + String(repeating: "0", count: 62)
        let entry = catalogueEntry(id: "game-cancelled", requiredSHAs: [cachedDigest, cancelledDigest])
        try catalogueStore.upsert(entry)
        try downloadQueue.enqueueGame(entry)
        let cancelledItem = try XCTUnwrap(downloadQueue.itemsForAssetSet("game-cancelled").first { $0.sha256 == cancelledDigest })
        try downloadQueue.cancel(id: cancelledItem.id)

        let entries = await reporter.buildEntries(catalogue: [entry])
        let report = try XCTUnwrap(entries.first)
        XCTAssertTrue(report.missingDependency, "a cancelled row is not in the queue")
    }

    func test_untouchedGame_reportsMissingDependencyFalseSoServerOnlyStaysReachable() async throws {
        let digest = "aa" + String(repeating: "0", count: 62)
        let entry = catalogueEntry(id: "game-untouched", requiredSHAs: [digest])
        try catalogueStore.upsert(entry)

        let entries = await reporter.buildEntries(catalogue: [entry])
        let report = try XCTUnwrap(entries.first)
        XCTAssertFalse(report.missingDependency, "an untouched game is on the server, not broken -- server_only must stay reachable")
        XCTAssertFalse(report.verified)
        XCTAssertFalse(report.downloading)
        XCTAssertFalse(report.pinned)
    }

    func test_emptyRequiredMemberList_reportsMissingDependencyFalse() async throws {
        let entry = CatalogueEntry(id: "game-no-members", system: "gba", displayTitle: "No Members", tags: [:], members: [])
        try catalogueStore.upsert(entry)

        let entries = await reporter.buildEntries(catalogue: [entry])
        let report = try XCTUnwrap(entries.first)
        XCTAssertFalse(report.missingDependency, "a manifest with no required members is an upstream defect, not a claim this client makes")
    }

    func test_orphanedMemberDuringActiveTransfer_reportsBothMissingDependencyAndDownloadingTrue() async throws {
        let cachedDigest = try seedCachedObject(seed: "hb")
        let activeDigest = "ac" + String(repeating: "0", count: 62)
        let orphanedDigest = "ad" + String(repeating: "0", count: 62)
        let entry = catalogueEntry(id: "game-active-and-orphaned", requiredSHAs: [cachedDigest, activeDigest, orphanedDigest])
        try catalogueStore.upsert(entry)
        try downloadQueue.enqueueGame(entry)
        let activeItem = try XCTUnwrap(downloadQueue.itemsForAssetSet("game-active-and-orphaned").first { $0.sha256 == activeDigest })
        try downloadQueue.markActive(id: activeItem.id)
        // enqueueGame enqueues every required member, including the
        // one meant to be truly orphaned -- cancel its row so it is
        // genuinely "absent with no queue row", not merely waiting.
        let orphanedItem = try XCTUnwrap(downloadQueue.itemsForAssetSet("game-active-and-orphaned").first { $0.sha256 == orphanedDigest })
        try downloadQueue.cancel(id: orphanedItem.id)

        let entries = await reporter.buildEntries(catalogue: [entry])
        let report = try XCTUnwrap(entries.first)
        XCTAssertTrue(report.downloading, "the active member's transfer is in flight")
        XCTAssertTrue(report.missingDependency, "the third member is orphaned; the client sends both facts and never picks a winner")
    }

}
