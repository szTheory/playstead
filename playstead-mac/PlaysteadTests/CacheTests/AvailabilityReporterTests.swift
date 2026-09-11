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

    // MARK: - Plan 03-15 Task 2: the same fixture the Elixir end-to-end
    // test PUTs verbatim is proven, on this side, to be exactly what
    // `buildEntries` produces -- one fixture, asserted by both languages,
    // never a hand-written guess about the other side's output.

    private struct FixtureReportBody: Decodable {
        let entries: [AvailabilityReportEntry]
    }

    /// Loads `shared/availability-report-fixture.json` from disk.
    /// `#filePath` for this file is
    /// `playstead-mac/PlaysteadTests/CacheTests/AvailabilityReporterTests.swift`;
    /// four `deleteLastPathComponent()` calls (CacheTests ->
    /// PlaysteadTests -> playstead-mac -> repo root) land at the repo
    /// root, mirroring `AvailabilityVocabularyContractTests`'
    /// `loadJSONVocabulary()` exactly.
    private func loadReportFixture(file: StaticString = #filePath) throws -> FixtureReportBody {
        var url = URL(fileURLWithPath: "\(file)")
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        url.appendPathComponent("shared/availability-report-fixture.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(FixtureReportBody.self, from: data)
    }

    func test_buildEntriesOutputEncodesByteIdenticallyToSharedReportFixture() async throws {
        let fixture = try loadReportFixture()
        XCTAssertEqual(fixture.entries.count, 4, "the fixture is expected to carry exactly four states: missing-dependency, downloading, verified, all-false")

        // Build store state matching each fixture entry by its
        // asset_set_id, exactly as the fixture's facts describe.

        // missing-dependency-asset-set: one cached member (engagement),
        // one absent member with no queue row of any kind (orphaned).
        let mdCached = try seedCachedObject(seed: "fx1")
        let mdOrphaned = "b1" + String(repeating: "0", count: 62)
        let missingDependencyEntry = catalogueEntry(id: "missing-dependency-asset-set", requiredSHAs: [mdCached, mdOrphaned])
        try catalogueStore.upsert(missingDependencyEntry)

        // downloading-asset-set: one required member with an active
        // queue row; live percent injected as 42 to match the fixture.
        let downloadingDigest = "b2" + String(repeating: "0", count: 62)
        let downloadingEntry = catalogueEntry(id: "downloading-asset-set", requiredSHA: downloadingDigest)
        try catalogueStore.upsert(downloadingEntry)
        try downloadQueue.enqueueGame(downloadingEntry)
        let downloadingItem = try XCTUnwrap(downloadQueue.itemsForAssetSet("downloading-asset-set").first)
        try downloadQueue.markActive(id: downloadingItem.id)

        // verified-asset-set: its one required member is fully cached.
        let verifiedDigest = try seedCachedObject(seed: "fx3")
        let verifiedEntry = catalogueEntry(id: "verified-asset-set", requiredSHA: verifiedDigest)
        try catalogueStore.upsert(verifiedEntry)

        // all-false-asset-set: untouched -- no cached member, no queue
        // row, no pin.
        let allFalseDigest = "b4" + String(repeating: "0", count: 62)
        let allFalseEntry = catalogueEntry(id: "all-false-asset-set", requiredSHA: allFalseDigest)
        try catalogueStore.upsert(allFalseEntry)

        let liveReporter = AvailabilityReporter(
            localStore: localStore, downloadQueue: downloadQueue, cas: cas, pinStore: pinStore, outbox: outbox,
            activeTransferPercent: { assetSetID in assetSetID == "downloading-asset-set" ? 42 : nil }
        )

        let built = await liveReporter.buildEntries(catalogue: [
            missingDependencyEntry, downloadingEntry, verifiedEntry, allFalseEntry
        ])

        // Assert the full key set in both directions -- an entry added
        // on one side and missing from the other fails here, not just
        // a per-field mismatch on entries both sides happen to share.
        XCTAssertEqual(Set(built.map(\.assetSetID)), Set(fixture.entries.map(\.assetSetID)))

        let builtByID = Dictionary(uniqueKeysWithValues: built.map { ($0.assetSetID, $0) })
        for fixtureEntry in fixture.entries {
            let builtEntry = try XCTUnwrap(builtByID[fixtureEntry.assetSetID], "fixture entry \(fixtureEntry.assetSetID) has no corresponding built entry")
            XCTAssertEqual(builtEntry, fixtureEntry, "built entry for \(fixtureEntry.assetSetID) does not match the committed fixture")
        }
    }


    // MARK: - 03-UAT.md checkpoint 49 (plan 03-15 deliverable D7): a
    // report whose entry list is unchanged since the last pass still
    // encodes and enqueues.
    //
    // 03-15 left this unclassified ("coverage not determined at
    // authoring time -- verifier should classify") because the existing
    // retry test proves one intent re-sent, not two passes enqueued.
    // The distinction matters now that 03-16 added newest-wins
    // supersede: a second report REPLACES a pending predecessor, and a
    // supersede that dropped the newer report instead of the older one
    // would look identical from the outbox count alone. These pin the
    // direction as well as the count.

    func test_secondPassOverUnchangedState_enqueuesAgainRatherThanShortCircuiting() async throws {
        let digest = try seedCachedObject(seed: "u")
        let entry = catalogueEntry(id: "game-unchanged", requiredSHA: digest)
        try catalogueStore.upsert(entry)

        var issued = 0
        let counting = AvailabilityReporter(
            localStore: localStore, downloadQueue: downloadQueue, cas: cas, pinStore: pinStore,
            outbox: outbox,
            idGenerator: { issued += 1; return "report-pass-\(issued)" }
        )

        let first = await counting.reportAll()
        let firstPending = try XCTUnwrap(outbox.listAll().first(where: { $0.kind == .availabilityReport }))

        // Nothing about the world changes between the two passes.
        let second = await counting.reportAll()

        XCTAssertEqual(first, second, "an unchanged world must produce an identical entry list")
        XCTAssertEqual(issued, 2, "the second pass built and enqueued its own intent")

        let pending = outbox.listAll().filter { $0.kind == .availabilityReport }
        XCTAssertEqual(pending.count, 1, "newest-wins supersede leaves exactly one report queued")

        let survivor = try XCTUnwrap(pending.first)
        XCTAssertNotEqual(
            survivor.idempotencyKey, firstPending.idempotencyKey,
            "the SECOND pass's report survived -- supersede dropped the older one, not the newer"
        )
    }

    func test_unchangedSecondPassEncodesToTheSamePayloadAsTheFirst() async throws {
        let digest = try seedCachedObject(seed: "v")
        let entry = catalogueEntry(id: "game-stable", requiredSHA: digest)
        try catalogueStore.upsert(entry)
        try pinStore.pin(assetSetID: "game-stable")

        let first = await reporter.buildEntries(catalogue: [entry])
        let second = await reporter.buildEntries(catalogue: [entry])

        // Non-vacuity first: a real, populated report, not two equal empty
        // ones.
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.count, 1)
        let a = try XCTUnwrap(first.first)
        let b = try XCTUnwrap(second.first)
        XCTAssertTrue(a.verified)
        XCTAssertTrue(a.pinned)

        // Field by field, each on its own line. `Data`'s description is only
        // a byte count, so comparing the encoded bodies directly reports
        // `("142 bytes") is not equal to ("142 bytes")` and names nothing --
        // and CI keeps file:line, not assertion messages, so the diagnosis
        // has to live in WHICH line failed.
        XCTAssertEqual(a.assetSetID, b.assetSetID)
        XCTAssertEqual(a.downloading, b.downloading)
        XCTAssertEqual(a.verified, b.verified)
        XCTAssertEqual(a.pinned, b.pinned)
        XCTAssertEqual(a.missingDependency, b.missingDependency)
        XCTAssertEqual(a.downloadPercent, b.downloadPercent)

        // Then the payload the server actually reads. Compared as DECODED
        // JSON, not as bytes: `JSONEncoder` gives no guarantee that two
        // encodings of equal values emit their keys in the same order, so a
        // byte comparison asserts something Foundation does not promise. An
        // earlier draft of this test did exactly that and failed once in a
        // full-suite run with the uninformative
        // `("142 bytes") is not equal to ("142 bytes")` -- both bodies
        // carried identical values in a different key order. The neighbouring
        // `test_buildEntriesOutputEncodesByteIdenticallyToSharedReportFixture`
        // already compares decoded values despite its name, for the same
        // reason.
        //
        // The intent id differs by construction and `wireBody` ignores it for
        // this kind, which is itself part of what this asserts. Idempotency
        // does not depend on body bytes either -- `Outbox` derives its key
        // from `kind` plus the entry id.
        let firstBody = try XCTUnwrap(CurationIntent.availabilityReport(id: "a", entries: first).wireBody)
        let secondBody = try XCTUnwrap(CurationIntent.availabilityReport(id: "b", entries: second).wireBody)
        let firstJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: firstBody) as? NSDictionary)
        let secondJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: secondBody) as? NSDictionary)
        XCTAssertEqual(firstJSON, secondJSON)
    }
}
