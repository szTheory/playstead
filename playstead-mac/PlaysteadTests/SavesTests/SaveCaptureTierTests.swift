import XCTest
import CryptoKit
@testable import Playstead

/// Covers plan 04-06 task 1's `<behavior>` block: D-04's two capture
/// tiers plus session-start baseline, and D-08's artifact-set identity.
final class SaveCaptureTierTests: XCTestCase {
    private var tempRoot: URL!
    private var localStore: LocalStore!
    private var saveStore: SaveStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppPaths(root: tempRoot)
        localStore = try LocalStore(paths: paths)
        saveStore = SaveStore(localStore: localStore)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    // MARK: - Test doubles (mirrors SaveUploadLaneTests' conventions)

    private final class ScriptedArtifactSource: SaveArtifactSource, @unchecked Sendable {
        var next: Data?
        func readArtifact() -> Data? { next }
    }

    private struct FixedClock: SaveCaptureClock {
        let fixed: Date
        func now() -> Date { fixed }
    }

    private func makePoller(
        source: ScriptedArtifactSource = ScriptedArtifactSource(),
        sessionID: String = UUID().uuidString,
        knownHeadDigest: String? = nil
    ) -> (SaveCapturePoller, URL) {
        let dir = tempRoot.appendingPathComponent("saves-\(UUID().uuidString)", isDirectory: true)
        let poller = SaveCapturePoller(
            source: source,
            clock: FixedClock(fixed: Date(timeIntervalSince1970: 1_700_000_000)),
            destinationDirectory: dir,
            pollInterval: 1.0,
            sessionID: sessionID,
            knownHeadDigest: knownHeadDigest
        )
        return (poller, dir)
    }

    /// Feeds three identical reads (D-03 quiescence) so a staged capture
    /// is produced deterministically.
    @discardableResult
    private func stageQuiescently(_ poller: SaveCapturePoller, bytes: Data) async throws -> CapturedSave? {
        _ = try await poller.observe(bytes)
        _ = try await poller.observe(bytes)
        return try await poller.observe(bytes)
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Test-level stand-in for a future session orchestrator: takes a
    /// `CapturedSave` and persists it as a `SaveRevisionRow`, honoring
    /// D-04's parent rule (baseline when one exists this session, else
    /// the line's prior head).
    @discardableResult
    private func insertRow(
        _ capture: CapturedSave, lineID: String, parentRevisionID: String?
    ) throws -> SaveRevisionRow {
        let row = SaveRevisionRow(
            id: UUID().uuidString,
            saveLineID: lineID,
            parentRevisionID: parentRevisionID,
            blobSHA256: capture.sha256,
            sizeBytes: capture.sizeBytes,
            originDeviceID: "device-1",
            deviceCapturedAt: nil,
            recordedAt: nil,
            captureMethod: "poll",
            adapterID: "mgba",
            adapterVersion: "1.0",
            saveFormat: "sram",
            formatConfidence: "exact",
            playSessionID: capture.sessionID,
            durability: SaveDurability.localOnly.rawValue,
            localPath: capture.localPath,
            tier: capture.tier.rawValue,
            origin: capture.origin.rawValue,
            manifestDigest: capture.artifactSet.manifestDigest,
            sessionID: capture.sessionID,
            artifactSetJSON: nil
        )
        try saveStore.insertRevision(row)
        return row
    }

    // MARK: - 1. Five quiescent changes -> five staged captures, one promoted revision.

    func test_fiveQuiescentChanges_produceFiveStagedCaptures_andExactlyOnePromotedRevision() async throws {
        let source = ScriptedArtifactSource()
        let sessionID = UUID().uuidString
        let (poller, _) = makePoller(source: source, sessionID: sessionID)
        let lineID = try saveStore.resolveLine(contentKey: "content-1", saveKind: "battery", slot: "0", placeholderID: UUID().uuidString).id

        var stagedCaptures: [CapturedSave] = []
        for i in 0..<5 {
            let bytes = Data(repeating: UInt8(i), count: 64)
            guard let staged = try await stageQuiescently(poller, bytes: bytes) else {
                return XCTFail("expected a staged capture for change \(i)")
            }
            stagedCaptures.append(staged)
            try insertRow(staged, lineID: lineID, parentRevisionID: nil)
        }
        XCTAssertEqual(stagedCaptures.count, 5, "five distinct quiescent changes must produce five staged captures")

        guard let promoted = try await poller.promote() else {
            return XCTFail("expected exactly one promoted revision at session end")
        }
        try insertRow(promoted, lineID: lineID, parentRevisionID: nil)

        let sessionRows = saveStore.fetchRevisions(sessionID: sessionID)
        let promotedRows = sessionRows.filter { $0.tier == SaveCaptureTier.promoted.rawValue }
        XCTAssertEqual(promotedRows.count, 1, "exactly one promoted revision must exist for the session")
        XCTAssertEqual(promotedRows.first?.blobSHA256, stagedCaptures.last?.sha256, "the promoted revision must carry the newest staged bytes")

        let stagedRows = sessionRows.filter { $0.tier == SaveCaptureTier.staged.rawValue }
        XCTAssertEqual(stagedRows.count, 5, "all five staged captures must be individually recorded")
    }

    // MARK: - 2. The promoted revision's parent is the session's baseline when one was created.

    func test_promotedRevisionParent_isSessionBaseline_whenBaselineWasCreated() async throws {
        let priorBytes = Data(repeating: 0x01, count: 32)
        let priorDigest = digest(priorBytes)
        let externalBytes = Data(repeating: 0x02, count: 32) // differs -> triggers a baseline

        let source = ScriptedArtifactSource()
        source.next = externalBytes
        let (poller, _) = makePoller(source: source, knownHeadDigest: priorDigest)
        let lineID = try saveStore.resolveLine(contentKey: "content-2", saveKind: "battery", slot: "0", placeholderID: UUID().uuidString).id
        let priorHeadID = UUID().uuidString

        guard let baseline = try await poller.startSession() else {
            return XCTFail("expected a baseline revision when on-disk bytes differ from the last recorded revision")
        }
        XCTAssertEqual(baseline.tier, .baseline)
        XCTAssertEqual(baseline.origin, .external)
        try insertRow(baseline, lineID: lineID, parentRevisionID: priorHeadID)

        let newBytes = Data(repeating: 0x03, count: 32)
        guard let staged = try await stageQuiescently(poller, bytes: newBytes) else {
            return XCTFail("expected a staged capture after the baseline")
        }
        try insertRow(staged, lineID: lineID, parentRevisionID: baseline.sha256)

        guard let promoted = try await poller.promote() else {
            return XCTFail("expected a promoted revision at session end")
        }
        let promotedRow = try insertRow(promoted, lineID: lineID, parentRevisionID: baseline.sha256)

        XCTAssertEqual(promotedRow.parentRevisionID, baseline.sha256, "the promoted revision's parent must be the session's baseline, not the line's prior head")
    }

    func test_promotedRevisionParent_isLinePriorHead_whenNoBaselineWasCreated() async throws {
        let priorBytes = Data(repeating: 0x10, count: 32)
        let priorDigest = digest(priorBytes)

        let source = ScriptedArtifactSource()
        source.next = priorBytes // matches the known head -> no baseline
        let (poller, _) = makePoller(source: source, knownHeadDigest: priorDigest)
        let lineID = try saveStore.resolveLine(contentKey: "content-3", saveKind: "battery", slot: "0", placeholderID: UUID().uuidString).id
        let priorHeadID = UUID().uuidString

        let baseline = try await poller.startSession()
        XCTAssertNil(baseline, "on-disk bytes matching the last recorded revision must create no baseline")

        let newBytes = Data(repeating: 0x11, count: 32)
        guard let staged = try await stageQuiescently(poller, bytes: newBytes) else {
            return XCTFail("expected a staged capture")
        }
        try insertRow(staged, lineID: lineID, parentRevisionID: priorHeadID)

        guard let promoted = try await poller.promote() else {
            return XCTFail("expected a promoted revision at session end")
        }
        let promotedRow = try insertRow(promoted, lineID: lineID, parentRevisionID: priorHeadID)

        XCTAssertEqual(promotedRow.parentRevisionID, priorHeadID, "with no baseline, the promoted revision's parent must be the line's prior head")
    }

    // MARK: - 3. Session start with differing on-disk bytes creates a baseline (origin: external).

    func test_sessionStart_bytesDifferFromLastRecordedRevision_createsBaselineRevision_originExternal() async throws {
        let priorBytes = Data(repeating: 0x44, count: 32)
        let priorDigest = digest(priorBytes)
        let externalBytes = Data(repeating: 0x45, count: 32)

        let source = ScriptedArtifactSource()
        source.next = externalBytes
        let (poller, dir) = makePoller(source: source, knownHeadDigest: priorDigest)

        guard let baseline = try await poller.startSession() else {
            return XCTFail("expected a baseline revision for an out-of-band change")
        }
        XCTAssertEqual(baseline.tier, .baseline)
        XCTAssertEqual(baseline.origin, .external)
        XCTAssertEqual(baseline.sha256, digest(externalBytes))
        XCTAssertTrue(FileManager.default.fileExists(atPath: baseline.localPath))
        XCTAssertTrue(baseline.localPath.hasPrefix(dir.path))
    }

    // MARK: - 4. Session start with matching on-disk bytes creates no baseline.

    func test_sessionStart_bytesMatchLastRecordedRevision_createsNoBaseline() async throws {
        let bytes = Data(repeating: 0x55, count: 32)
        let matchingDigest = digest(bytes)

        let source = ScriptedArtifactSource()
        source.next = bytes
        let (poller, _) = makePoller(source: source, knownHeadDigest: matchingDigest)

        let baseline = try await poller.startSession()
        XCTAssertNil(baseline, "identical on-disk bytes must never produce a baseline revision")
    }

    // A brand new line has nothing to diverge from -- no known head means no baseline either.
    func test_sessionStart_noKnownHead_createsNoBaseline() async throws {
        let source = ScriptedArtifactSource()
        source.next = Data(repeating: 0x66, count: 32)
        let (poller, _) = makePoller(source: source, knownHeadDigest: nil)

        let baseline = try await poller.startSession()
        XCTAssertNil(baseline, "a brand new line with no recorded revision yet must never produce a baseline")
    }

    // MARK: - 5. SaveArtifactSet: sorted, timestamp-free; two runs over identical files are byte-identical.

    func test_artifactSet_isSortedAndTimestampFree_twoRunsOverIdenticalFilesAreByteIdentical() {
        let bytes = Data(repeating: 0x77, count: 128)
        let first = SaveArtifactSet.single(data: bytes, path: "save")
        let second = SaveArtifactSet.single(data: bytes, path: "save")

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.manifestDigest, second.manifestDigest, "two manifest computations over identical files must be byte-identical")

        let unsorted = SaveArtifactSet(entries: [
            SaveArtifactEntry(path: "b", size: 1, sha256: "bb"),
            SaveArtifactEntry(path: "a", size: 1, sha256: "aa")
        ])
        XCTAssertEqual(unsorted.entries.map(\.path), ["a", "b"], "entries must always be sorted by path")
    }

    // MARK: - 6. The stored blob digest equals the raw sha256 and differs from the manifest digest (single entry).

    func test_storedBlobDigestEqualsRawSha256_andDiffersFromManifestDigest_forSingleEntry() async throws {
        let bytes = Data(repeating: 0x88, count: 256)
        let rawDigest = digest(bytes)

        let source = ScriptedArtifactSource()
        let (poller, _) = makePoller(source: source)

        guard let staged = try await stageQuiescently(poller, bytes: bytes) else {
            return XCTFail("expected a staged capture")
        }

        XCTAssertEqual(staged.sha256, rawDigest, "the stored blob digest must be the raw artifact sha256")
        XCTAssertNotEqual(staged.sha256, staged.artifactSet.manifestDigest, "for the single-entry case, the raw digest must differ from the manifest digest")
    }

    // MARK: - 7. A zero-byte artifact does not produce a revision.

    func test_zeroByteArtifact_producesNoCapture() async throws {
        let source = ScriptedArtifactSource()
        let (poller, _) = makePoller(source: source)

        let observed = try await poller.observe(Data())
        XCTAssertNil(observed, "an empty read must never produce a capture")

        source.next = Data()
        let settled = try await poller.settle()
        XCTAssertNil(settled, "an empty settle read must never produce a capture")

        let promoted = try await poller.promote()
        XCTAssertNil(promoted, "a session with no staged captures must promote nothing")
    }
}
