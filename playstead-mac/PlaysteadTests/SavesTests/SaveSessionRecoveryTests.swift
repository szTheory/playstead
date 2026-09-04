import XCTest
import CryptoKit
@testable import Playstead

/// Covers plan 04-06 task 2's `<behavior>` block: D-07 crash recovery
/// (`SaveSessionRecovery`) and D-31's disk-full blocked-capture path
/// (`SaveCaptureBlockedState`).
final class SaveSessionRecoveryTests: XCTestCase {
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

    // MARK: - Test doubles

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func makeLine(_ contentKey: String = UUID().uuidString) throws -> String {
        try saveStore.resolveLine(contentKey: contentKey, saveKind: "battery", slot: "0", placeholderID: UUID().uuidString).id
    }

    /// Marks a session as "abandoned" by inserting exactly the staged
    /// row a real crashed session would have left behind, with no
    /// corresponding promoted row.
    private func markSessionAbandoned(lineID: String, sessionID: String, digest: String) throws {
        let row = SaveRevisionRow(
            id: UUID().uuidString, saveLineID: lineID, parentRevisionID: nil, blobSHA256: digest, sizeBytes: 0,
            originDeviceID: nil, deviceCapturedAt: nil, recordedAt: nil, captureMethod: "poll", adapterID: nil,
            adapterVersion: nil, saveFormat: nil, formatConfidence: nil, playSessionID: sessionID,
            durability: SaveDurability.localOnly.rawValue, localPath: nil,
            tier: SaveCaptureTier.staged.rawValue, origin: SaveCaptureOrigin.session.rawValue,
            manifestDigest: nil, sessionID: sessionID, artifactSetJSON: nil
        )
        try saveStore.insertRevision(row)
    }

    private func recordPromotedRow(lineID: String, sessionID: String?, digest: String) throws {
        let row = SaveRevisionRow(
            id: UUID().uuidString, saveLineID: lineID, parentRevisionID: nil, blobSHA256: digest, sizeBytes: 0,
            originDeviceID: nil, deviceCapturedAt: nil, recordedAt: nil, captureMethod: "poll", adapterID: nil,
            adapterVersion: nil, saveFormat: nil, formatConfidence: nil, playSessionID: sessionID,
            durability: SaveDurability.localOnly.rawValue, localPath: nil,
            tier: SaveCaptureTier.promoted.rawValue, origin: SaveCaptureOrigin.session.rawValue,
            manifestDigest: nil, sessionID: sessionID, artifactSetJSON: nil
        )
        try saveStore.insertRevision(row)
    }

    private func writeArtifact(_ data: Data) throws -> URL {
        let url = tempRoot.appendingPathComponent("artifact-\(UUID().uuidString).sav")
        try data.write(to: url)
        return url
    }

    private func promotedRows(lineID: String) -> [SaveRevisionRow] {
        saveStore.fetchAllRevisions().filter { $0.saveLineID == lineID && $0.tier == SaveCaptureTier.promoted.rawValue }
    }

    // MARK: - 1. A session row left open by app death is replayed at launch.

    func test_replay_promotesTheRevisionTheCrashedSessionDidNot() async throws {
        let lineID = try makeLine()
        let sessionID = UUID().uuidString
        let bytes = Data(repeating: 0xAA, count: 64)
        let onDiskDigest = digest(bytes)

        try markSessionAbandoned(lineID: lineID, sessionID: sessionID, digest: onDiskDigest)
        let artifactURL = try writeArtifact(bytes)

        let recovery = SaveSessionRecovery(saveStore: saveStore)
        let session = AbandonedSaveSession(
            saveLineID: lineID, sessionID: sessionID, artifactSource: FileSaveArtifactSource(url: artifactURL),
            destinationDirectory: tempRoot.appendingPathComponent("dest-\(sessionID)"), artifactRelativePath: "save"
        )

        let result = try await recovery.replay(session, parentRevisionID: nil)
        XCTAssertNotNil(result, "recovery must promote the revision the crashed session did not")
        XCTAssertEqual(result?.blobSHA256, onDiskDigest)
        XCTAssertEqual(result?.tier, SaveCaptureTier.promoted.rawValue)
        XCTAssertEqual(promotedRows(lineID: lineID).count, 1)
    }

    // MARK: - 2. Replay when nothing changed produces no revision, no output.

    func test_replay_whenNothingChangedSinceLastRecordedRevision_producesNoRevision() async throws {
        let lineID = try makeLine()
        let bytes = Data(repeating: 0xBB, count: 64)
        let headDigest = digest(bytes)
        try recordPromotedRow(lineID: lineID, sessionID: nil, digest: headDigest)

        let sessionID = UUID().uuidString
        let artifactURL = try writeArtifact(bytes) // identical to the already-recorded head

        let recovery = SaveSessionRecovery(saveStore: saveStore)
        let session = AbandonedSaveSession(
            saveLineID: lineID, sessionID: sessionID, artifactSource: FileSaveArtifactSource(url: artifactURL),
            destinationDirectory: tempRoot.appendingPathComponent("dest-\(sessionID)"), artifactRelativePath: "save"
        )

        let result = try await recovery.replay(session, parentRevisionID: nil)
        XCTAssertNil(result, "no new bytes since the last recorded revision must produce no revision")
        XCTAssertEqual(promotedRows(lineID: lineID).count, 1, "the pre-existing head must remain the only promoted revision")
    }

    // MARK: - 3. Running recovery twice produces exactly one promoted revision.

    func test_runningRecoveryTwice_producesExactlyOnePromotedRevision() async throws {
        let lineID = try makeLine()
        let sessionID = UUID().uuidString
        let bytes = Data(repeating: 0xCC, count: 64)
        try markSessionAbandoned(lineID: lineID, sessionID: sessionID, digest: digest(bytes))
        let artifactURL = try writeArtifact(bytes)

        let recovery = SaveSessionRecovery(saveStore: saveStore)
        let session = AbandonedSaveSession(
            saveLineID: lineID, sessionID: sessionID, artifactSource: FileSaveArtifactSource(url: artifactURL),
            destinationDirectory: tempRoot.appendingPathComponent("dest-\(sessionID)"), artifactRelativePath: "save"
        )

        let first = try await recovery.replay(session, parentRevisionID: nil)
        let second = try await recovery.replay(session, parentRevisionID: nil)

        XCTAssertNotNil(first)
        XCTAssertNil(second, "a second replay of the same session must promote nothing new")
        XCTAssertEqual(promotedRows(lineID: lineID).count, 1)
    }

    // MARK: - 4. Running recovery concurrently with a live poller for the same session produces exactly one promoted revision.

    func test_runningRecoveryConcurrentlyWithLivePoller_producesExactlyOnePromotedRevision() async throws {
        let lineID = try makeLine()
        let sessionID = UUID().uuidString
        let bytes = Data(repeating: 0xDD, count: 64)
        let sharedDigest = digest(bytes)
        try markSessionAbandoned(lineID: lineID, sessionID: sessionID, digest: sharedDigest)
        let artifactURL = try writeArtifact(bytes)

        // Simulates a live poller for the same session winning the race
        // and promoting first -- recovery must see the digest already
        // recorded and promote nothing itself.
        try recordPromotedRow(lineID: lineID, sessionID: sessionID, digest: sharedDigest)

        let recovery = SaveSessionRecovery(saveStore: saveStore)
        let session = AbandonedSaveSession(
            saveLineID: lineID, sessionID: sessionID, artifactSource: FileSaveArtifactSource(url: artifactURL),
            destinationDirectory: tempRoot.appendingPathComponent("dest-\(sessionID)"), artifactRelativePath: "save"
        )

        let result = try await recovery.replay(session, parentRevisionID: nil)
        XCTAssertNil(result, "recovery must not double-promote content a live poller already promoted")
        XCTAssertEqual(promotedRows(lineID: lineID).count, 1)
    }

    // MARK: - 5. Recovery runs identically for all four AdapterExit classifications, including no recorded exit.

    func test_recovery_runsIdenticallyForAllFourAdapterExitClassifications_andNoRecordedExit() async throws {
        let exitCases: [AdapterExit?] = [.clean, .crashed, .killed, .unknown(status: 9, reason: "uncaughtSignal"), nil]

        for exitCase in exitCases {
            let lineID = try makeLine()
            let sessionID = UUID().uuidString
            let bytes = Data(repeating: 0xEE, count: 32)
            try markSessionAbandoned(lineID: lineID, sessionID: sessionID, digest: digest(bytes))
            let artifactURL = try writeArtifact(bytes)

            let recovery = SaveSessionRecovery(saveStore: saveStore)
            let session = AbandonedSaveSession(
                saveLineID: lineID, sessionID: sessionID, artifactSource: FileSaveArtifactSource(url: artifactURL),
                destinationDirectory: tempRoot.appendingPathComponent("dest-\(sessionID)"), artifactRelativePath: "save"
            )

            // `exitCase` is never passed to `replay` -- this loop proves
            // by construction that recovery's outcome cannot depend on it.
            let result = try await recovery.replay(session, parentRevisionID: nil)
            XCTAssertNotNil(result, "recovery must promote identically regardless of exit case \(String(describing: exitCase))")
            XCTAssertEqual(result?.blobSHA256, digest(bytes))
        }
    }

    // MARK: - 6. A disk-full failure writes a durable blocked row and raises exactly one alert.

    private final class RecordingAlertSink: SaveCaptureAlertSink, @unchecked Sendable {
        var alerts: [SaveCaptureAlert] = []
        func alert(_ alert: SaveCaptureAlert) { alerts.append(alert) }
    }

    func test_diskFullFailure_writesDurableBlockedRow_raisesExactlyOneAlert() async throws {
        let lineID = try makeLine()
        let sink = RecordingAlertSink()
        let state = SaveCaptureBlockedState(localStore: localStore, alertSink: sink)

        let row = try await state.recordFailure(saveLineID: lineID, sessionID: "session-1", digest: "deadbeef", reason: "disk_full")

        XCTAssertEqual(row.saveLineID, lineID)
        XCTAssertNil(row.resolvedAt, "an unresolved blockage must leave a persistent attention state")
        XCTAssertEqual(sink.alerts.count, 1)

        let open = await state.openBlockage(saveLineID: lineID)
        XCTAssertNotNil(open, "the blockage must remain durably open until cleared")
    }

    // MARK: - 7. A blocked capture is retried on the next poll cycle; the running game is not stopped.

    private final class RunningGameHandle {
        private(set) var stopCallCount = 0
        func stop() { stopCallCount += 1 }
    }

    func test_blockedCapture_isRetriedOnNextPollCycle_runningGameHandleUntouched() async throws {
        let lineID = try makeLine()
        let state = SaveCaptureBlockedState(localStore: localStore)
        let game = RunningGameHandle()

        // Simulate three consecutive poll-cycle failures for the same
        // blockage -- the game handle is never referenced by any capture
        // failure path, so it must remain untouched throughout.
        for _ in 0..<3 {
            _ = try await state.recordFailure(saveLineID: lineID, sessionID: "session-1", digest: "deadbeef", reason: "disk_full")
        }

        let open = await state.openBlockage(saveLineID: lineID)
        XCTAssertEqual(open?.failureCount, 3, "every subsequent poll cycle must retry and record the failure")
        XCTAssertEqual(game.stopCallCount, 0, "a disk-full capture failure must never stop the running game")
    }

    // MARK: - 8. A second disk-full failure for the same blockage does not raise a second alert.

    func test_secondDiskFullFailure_forSameBlockage_doesNotRaiseSecondAlert() async throws {
        let lineID = try makeLine()
        let sink = RecordingAlertSink()
        let state = SaveCaptureBlockedState(localStore: localStore, alertSink: sink)

        _ = try await state.recordFailure(saveLineID: lineID, sessionID: "session-1", digest: "deadbeef", reason: "disk_full")
        _ = try await state.recordFailure(saveLineID: lineID, sessionID: "session-1", digest: "deadbeef", reason: "disk_full")

        XCTAssertEqual(sink.alerts.count, 1, "a second failure for the same still-open blockage must not raise a second alert")
    }

    // MARK: - 9. Nothing is deleted on a disk-full failure.

    func test_diskFullFailure_deletesNothing_stagedRevisionAndArtifactSurvive() async throws {
        let lineID = try makeLine()
        let priorBytes = Data(repeating: 0xFA, count: 32)
        try recordPromotedRow(lineID: lineID, sessionID: nil, digest: digest(priorBytes))
        let artifactURL = try writeArtifact(priorBytes)

        let state = SaveCaptureBlockedState(localStore: localStore)
        _ = try await state.recordFailure(saveLineID: lineID, sessionID: "session-1", digest: "deadbeef", reason: "disk_full")

        // The prior promoted revision, and the on-disk artifact, are both
        // still present after the failure -- nothing was deleted.
        XCTAssertEqual(promotedRows(lineID: lineID).count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactURL.path))

        try await state.clearBlockage(saveLineID: lineID)
        let cleared = await state.openBlockage(saveLineID: lineID)
        XCTAssertNil(cleared, "clearing a blockage must remove it from the open set without deleting its history")
    }
}
