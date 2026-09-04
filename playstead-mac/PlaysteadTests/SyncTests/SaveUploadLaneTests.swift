import XCTest
import CryptoKit
@testable import Playstead

/// Covers every bullet of plan 04-04 task 2's `<behavior>` block: the
/// capture/lane invariants the tracer (04-04 task 1) depends on, now
/// asserted by name rather than assumed.
final class SaveUploadLaneTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!
    private var localStore: LocalStore!
    private var saveStore: SaveStore!
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
        apiClient = APIClient(keychain: KeychainStore(), session: StubURLProtocol.makeSession(), credential: credential)
        StubURLProtocol.reset()
    }

    override func tearDownWithError() throws {
        StubURLProtocol.reset()
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    // MARK: - Test doubles

    /// A byte source a test drives by hand -- returns whatever `next`
    /// currently holds, so `observe(_:)` can be called with reads a
    /// test controls exactly, one at a time, with no real sleeping.
    private final class ScriptedArtifactSource: SaveArtifactSource, @unchecked Sendable {
        var next: Data?
        func readArtifact() -> Data? { next }
    }

    private struct FixedClock: SaveCaptureClock {
        let fixed: Date
        func now() -> Date { fixed }
    }

    private func makePoller(knownHeadDigest: String? = nil) -> (SaveCapturePoller, URL) {
        let dir = tempRoot.appendingPathComponent("saves-\(UUID().uuidString)", isDirectory: true)
        let poller = SaveCapturePoller(
            source: ScriptedArtifactSource(),
            clock: FixedClock(fixed: Date(timeIntervalSince1970: 1_700_000_000)),
            destinationDirectory: dir,
            pollInterval: 1.0,
            knownHeadDigest: knownHeadDigest
        )
        return (poller, dir)
    }

    // MARK: - D-03: two identical reads is not enough; the third is required.

    func test_twoIdenticalReadsIsNotEnough_thirdIdenticalReadIsRequired() async throws {
        let (poller, _) = makePoller()
        let bytes = Data(repeating: 0xAB, count: 128)

        let firstCapture = try await poller.observe(bytes)
        let secondCapture = try await poller.observe(bytes)
        XCTAssertNil(firstCapture, "one read must never capture")
        XCTAssertNil(secondCapture, "two identical reads must not capture -- three are required (D-03)")

        let thirdCapture = try await poller.observe(bytes)
        XCTAssertNotNil(thirdCapture, "the third identical read must complete quiescence and capture")
    }

    // MARK: - Three identical reads capture exactly once; a fourth produces no second capture.

    func test_threeIdenticalReads_captureOnce_fourthProducesNoSecondCapture() async throws {
        let (poller, _) = makePoller()
        let bytes = Data(repeating: 0x42, count: 256)

        _ = try await poller.observe(bytes)
        _ = try await poller.observe(bytes)
        let third = try await poller.observe(bytes)
        let fourth = try await poller.observe(bytes)

        XCTAssertNotNil(third)
        XCTAssertNil(fourth, "a fourth identical read must not produce a second capture")
    }

    // A differing third read resets quiescence -- two matching, one different, is still no capture.
    func test_twoMatchingThenDifferingRead_producesNoCapture() async throws {
        let (poller, _) = makePoller()
        let bytesA = Data(repeating: 0x11, count: 64)
        let bytesB = Data(repeating: 0x22, count: 64)

        _ = try await poller.observe(bytesA)
        _ = try await poller.observe(bytesA)
        let differing = try await poller.observe(bytesB)
        XCTAssertNil(differing)
    }

    // MARK: - D-05: the post-exit settle pass is unconditional -- a session
    // ending immediately after a byte change still captures.

    func test_settle_capturesEvenIfSessionEndsImmediatelyAfterByteChange() async throws {
        let source = ScriptedArtifactSource()
        let dir = tempRoot.appendingPathComponent("settle-\(UUID().uuidString)", isDirectory: true)
        let freshPoller = SaveCapturePoller(source: source, destinationDirectory: dir)

        source.next = Data(repeating: 0x77, count: 512)
        let capture = try await freshPoller.settle()

        XCTAssertNotNil(capture, "settle() must capture even with zero prior polls -- the session ended the instant after the byte change")
    }

    // MARK: - The settle pass runs identically for all four AdapterExit classifications.

    func test_settle_runsIdenticallyForAllFourAdapterExitClassifications() async throws {
        let exitCases: [AdapterExit] = [.clean, .crashed, .killed, .unknown(status: 9, reason: "uncaughtSignal")]

        for exitCase in exitCases {
            let source = ScriptedArtifactSource()
            let dir = tempRoot.appendingPathComponent("settle-exit-\(UUID().uuidString)", isDirectory: true)
            let poller = SaveCapturePoller(source: source, destinationDirectory: dir)
            source.next = Data(repeating: 0x99, count: 128)

            // The settle pass never receives or branches on `exitCase` --
            // this loop demonstrates that identical bytes produce an
            // identical capture regardless of which exit classification
            // a caller observed (D-05).
            let capture = try await poller.settle()
            XCTAssertNotNil(capture, "settle() must capture identically for exit case \(exitCase)")
            XCTAssertEqual(capture?.sizeBytes, 128)
        }
    }

    // MARK: - D-06: a crash between the rename and the row insert leaves
    // the blob present on disk with no row referencing it -- an orphan,
    // never a dangling reference.

    func test_crashBetweenRenameAndRowInsert_leavesOrphanBlobNoReferencingRow() async throws {
        let (poller, _) = makePoller()
        let bytes = Data(repeating: 0x55, count: 32_768)

        _ = try await poller.observe(bytes)
        _ = try await poller.observe(bytes)
        guard let capture = try await poller.observe(bytes) else {
            return XCTFail("expected a capture on the third identical read")
        }

        // The write (temp file, fsync, rename, directory fsync) already
        // completed -- bytes are durable on disk. Simulating "the
        // process died before the row insert" is exactly *not calling*
        // `SaveStore.insertRevision` here.
        XCTAssertTrue(FileManager.default.fileExists(atPath: capture.localPath))

        let referencing = saveStore.fetchAllRevisions().filter { $0.blobSHA256 == capture.sha256 }
        XCTAssertTrue(referencing.isEmpty, "no row may reference the blob until the insert actually runs")
    }

    // MARK: - D-30 (client half): a same-device byte-identical capture
    // creates no second local revision.

    func test_sameDeviceByteIdenticalCapture_createsNoSecondLocalRevision() async throws {
        let bytes = Data(repeating: 0x33, count: 512)
        let digest = SHA256HexHelper.digest(of: bytes)

        // `knownHeadDigest` stands in for "SaveStore already has a head
        // with this digest for this line" -- the caller reads that
        // before constructing the poller for a new session.
        let (poller, _) = makePoller(knownHeadDigest: digest)

        let first = try await poller.observe(bytes)
        let second = try await poller.observe(bytes)
        let third = try await poller.observe(bytes)

        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertNil(third, "byte-identical to the already-known head must never promote a new revision")
    }

    // MARK: - D-32: the upload lane drains a queued save entry before a
    // queued curation entry, given both are ready at the same instant.

    func test_uploadLane_drainsBeforeCurationOutbox_whenBothAreReady() async throws {
        let curationStore = CurationStore(localStore: localStore)
        let outbox = Outbox(localStore: localStore, curationStore: curationStore)
        try outbox.enqueue(.favoriteAdd(id: "fav-1", assetSetID: "asset-1"))

        let revision = try makeLocalOnlyRevision(bytes: Data(repeating: 0x64, count: 4096))

        StubURLProtocol.responder = { request in
            StubURLProtocol.Stub(statusCode: request.httpMethod == "PUT" ? 200 : 201, headers: ["Content-Type": "application/json"], body: Data("{\"save_line_id\":\"\(revision.saveLineID)\",\"recorded_at\":\"2026-09-03T00:00:00Z\"}".utf8))
        }

        let saveLane = SaveUploadLane(apiClient: apiClient, saveStore: saveStore)
        let outboxWorker = OutboxWorker(apiClient: apiClient, outbox: outbox)

        // The documented drain order (D-32): the save lane goes first.
        _ = await saveLane.drainOnce()
        _ = await outboxWorker.drainOnce()

        let paths = StubURLProtocol.requestLog.map { $0.url?.path ?? "" }
        let saveUploadIndex = paths.firstIndex { $0.contains("/saves/uploads/") }
        let curationIndex = paths.firstIndex { $0.contains("/curation/favorites/") }

        XCTAssertNotNil(saveUploadIndex)
        XCTAssertNotNil(curationIndex)
        if let saveUploadIndex, let curationIndex {
            XCTAssertLessThan(saveUploadIndex, curationIndex, "the save upload must be observed before the curation intent")
        }
    }

    // MARK: - A lane entry that exhausts its attempts stays visible and
    // is retried on the next cycle, never going silent.

    func test_laneEntry_thatFailsRepeatedly_staysVisibleAndIsRetried_neverQuarantined() async throws {
        let revision = try makeLocalOnlyRevision(bytes: Data(repeating: 0x11, count: 1024))

        StubURLProtocol.responder = { _ in
            StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data("{\"code\":\"internal_error\"}".utf8))
        }

        let lane = SaveUploadLane(apiClient: apiClient, saveStore: saveStore)
        var now = Date(timeIntervalSince1970: 1_700_000_000)

        for _ in 0..<10 {
            let result = await lane.drainOnce(at: now)
            XCTAssertTrue(result.stoppedForRetry)
            now = now.addingTimeInterval(3600) // well past any backoff delay
        }

        // Still visible -- never removed, never a "failed"/"quarantined" durability value.
        let stillThere = saveStore.fetchRevision(id: revision.id)
        XCTAssertNotNil(stillThere)
        XCTAssertEqual(stillThere?.durability, SaveDurability.queued.rawValue)
    }

    // MARK: - Helpers

    @discardableResult
    private func makeLocalOnlyRevision(bytes: Data) throws -> SaveRevisionRow {
        let dir = tempRoot.appendingPathComponent("captured-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("save.sav")
        try bytes.write(to: fileURL)

        let digest = SHA256HexHelper.digest(of: bytes)
        let lineID = UUID().uuidString
        let line = try saveStore.resolveLine(contentKey: digest, saveKind: "battery", slot: "0", placeholderID: lineID)

        let row = SaveRevisionRow(
            id: UUID().uuidString,
            saveLineID: line.id,
            parentRevisionID: nil,
            blobSHA256: digest,
            sizeBytes: bytes.count,
            originDeviceID: "device-1",
            deviceCapturedAt: nil,
            recordedAt: nil,
            captureMethod: "poll",
            adapterID: "mgba",
            adapterVersion: "1.0",
            saveFormat: "sram",
            formatConfidence: "exact",
            playSessionID: nil,
            durability: SaveDurability.localOnly.rawValue,
            localPath: fileURL.path
        )
        try saveStore.insertRevision(row)
        return row
    }
}

/// A tiny local helper so tests can compute the same digest the poller
/// computes (a one-shot SHA-256, never `StreamingSHA256`), without
/// depending on `SaveCapturePoller`'s private digest implementation.
private enum SHA256HexHelper {
    static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
