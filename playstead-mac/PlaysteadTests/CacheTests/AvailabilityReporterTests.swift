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

}
