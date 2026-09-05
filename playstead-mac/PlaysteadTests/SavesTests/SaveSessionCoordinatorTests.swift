import XCTest
import CryptoKit
@testable import Playstead

/// Covers plan 04-19 task 1: the per-play capture lifecycle
/// (`SaveSessionCoordinator`) that the shipped Play path drives.
///
/// WINDOWS #45 recorded the defect this closes: `SaveCapturePoller` was
/// fully built and fully unit-tested, and nothing in the shipped binary
/// ever constructed one during play. These tests drive the coordinator
/// itself; `PlayPathSaveWiringTests` proves `play()` actually calls it.
final class SaveSessionCoordinatorTests: XCTestCase {
    private var tempRoot: URL!
    private var localStore: LocalStore!
    private var saveStore: SaveStore!
    private var captureDir: URL!
    private var saveDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppPaths(root: tempRoot)
        localStore = try LocalStore(paths: paths)
        saveStore = SaveStore(localStore: localStore)
        captureDir = tempRoot.appendingPathComponent("save-captures/asset-1", isDirectory: true)
        saveDir = tempRoot.appendingPathComponent("saves/asset-1", isDirectory: true)
        try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func makeLine() throws -> String {
        try saveStore.resolveLine(
            contentKey: UUID().uuidString, saveKind: "battery", slot: "0", placeholderID: UUID().uuidString
        ).id
    }

    private var targetURL: URL { saveDir.appendingPathComponent("game.sav") }

    private func write(_ data: Data) throws {
        try data.write(to: targetURL)
    }

    @discardableResult
    private func recordHead(lineID: String, digest headDigest: String, sizeBytes: Int) throws -> SaveRevisionRow {
        let row = SaveRevisionRow(
            id: UUID().uuidString, saveLineID: lineID, parentRevisionID: nil, blobSHA256: headDigest,
            sizeBytes: sizeBytes, originDeviceID: nil, deviceCapturedAt: nil, recordedAt: "2026-01-01T00:00:00Z",
            captureMethod: "session", adapterID: nil, adapterVersion: nil, saveFormat: nil, formatConfidence: nil,
            playSessionID: nil, durability: SaveDurability.uploaded.rawValue, localPath: nil,
            tier: SaveCaptureTier.promoted.rawValue, origin: SaveCaptureOrigin.session.rawValue
        )
        try saveStore.insertRevision(row)
        return row
    }

    /// A coordinator whose poll loop never fires inside a test's
    /// lifetime -- every assertion here is about `begin()`'s baseline
    /// pass and `end()`'s settle-then-promote pass, never about the 1 Hz
    /// loop (`SaveCaptureTierTests` already covers `observe()`).
    private func makeCoordinator(
        blockedState: SaveCaptureBlockedState? = nil,
        onPromoted: (@Sendable () -> Void)? = nil
    ) -> SaveSessionCoordinator {
        SaveSessionCoordinator(
            saveStore: saveStore, blockedState: blockedState, pollInterval: 3600, onPromoted: onPromoted
        )
    }

    private func begin(_ coordinator: SaveSessionCoordinator, lineID: String) async {
        await coordinator.begin(
            saveLineID: lineID,
            targetURL: targetURL,
            destinationDirectory: captureDir,
            artifactRelativePath: "game.sav"
        )
    }

    // MARK: - D-04 session-start baseline

    /// The out-of-band case: bytes on disk at session start differ from
    /// the line's recorded head, because something outside Playstead
    /// changed them. That must become a durable `baseline`/`external`
    /// revision before the session's own writes bury it.
    func testAnOutOfBandChangeAtSessionStartIsRecordedAsAnExternalBaselineRevision() async throws {
        let lineID = try makeLine()
        try recordHead(lineID: lineID, digest: digest(Data(repeating: 0x11, count: 64)), sizeBytes: 64)

        let outOfBand = Data(repeating: 0x22, count: 64)
        try write(outOfBand)

        let coordinator = makeCoordinator()
        await begin(coordinator, lineID: lineID)
        await coordinator.end()

        let baselines = saveStore.fetchRevisions(saveLineID: lineID)
            .filter { $0.tier == SaveCaptureTier.baseline.rawValue }
        XCTAssertEqual(baselines.count, 1, "an out-of-band change must produce exactly one baseline revision")
        XCTAssertEqual(baselines.first?.blobSHA256, digest(outOfBand))
        XCTAssertEqual(baselines.first?.origin, SaveCaptureOrigin.external.rawValue)
        XCTAssertEqual(baselines.first?.captureMethod, "baseline")
        XCTAssertEqual(baselines.first?.durability, SaveDurability.localOnly.rawValue)
        XCTAssertNotNil(baselines.first?.localPath)
    }

    /// Bytes identical to the recorded head are not an out-of-band
    /// change -- nothing diverged, so nothing is recorded (D-30).
    func testBytesMatchingTheRecordedHeadProduceNoBaselineRevision() async throws {
        let lineID = try makeLine()
        let bytes = Data(repeating: 0x33, count: 64)
        try recordHead(lineID: lineID, digest: digest(bytes), sizeBytes: 64)
        try write(bytes)

        let coordinator = makeCoordinator()
        await begin(coordinator, lineID: lineID)
        await coordinator.end()

        XCTAssertTrue(saveStore.fetchRevisions(saveLineID: lineID).allSatisfy {
            $0.tier != SaveCaptureTier.baseline.rawValue
        })
    }

    // MARK: - D-05/D-04 session end: settle then promote

    /// The truth SAVE-01 rests on: play, write save bytes, end the
    /// session, and a promoted revision exists in `SaveStore`.
    func testWritingDuringASessionPromotesExactlyOneRevisionAtSessionEnd() async throws {
        let lineID = try makeLine()
        let coordinator = makeCoordinator()

        await begin(coordinator, lineID: lineID)
        let played = Data(repeating: 0x44, count: 128)
        try write(played)
        await coordinator.end()

        let promoted = saveStore.fetchRevisions(saveLineID: lineID)
            .filter { $0.tier == SaveCaptureTier.promoted.rawValue }
        XCTAssertEqual(promoted.count, 1, "exactly one promoted revision per session (D-04)")
        XCTAssertEqual(promoted.first?.blobSHA256, digest(played))
        XCTAssertEqual(promoted.first?.captureMethod, "session")
        XCTAssertEqual(promoted.first?.durability, SaveDurability.localOnly.rawValue)
        XCTAssertNotNil(promoted.first?.playSessionID)
        XCTAssertEqual(promoted.first?.sessionID, promoted.first?.playSessionID)

        // The promoted bytes are durably on disk at the recorded path --
        // this is what the upload lane later streams.
        let localPath = try XCTUnwrap(promoted.first?.localPath)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: localPath)), played)
    }

    /// A promoted revision parents onto the head the session began from,
    /// so the line stays a single chain rather than forking against
    /// itself.
    func testAPromotedRevisionParentsOntoTheHeadReadAtBegin() async throws {
        let lineID = try makeLine()
        let head = try recordHead(lineID: lineID, digest: digest(Data(repeating: 0x55, count: 64)), sizeBytes: 64)

        let coordinator = makeCoordinator()
        await begin(coordinator, lineID: lineID)
        try write(Data(repeating: 0x66, count: 64))
        await coordinator.end()

        // Filtered by `captureMethod` because the pre-existing head row
        // is itself a `promoted` row -- matching on tier alone would
        // assert against the head instead of the session's promotion.
        let promoted = saveStore.fetchRevisions(saveLineID: lineID)
            .first { $0.captureMethod == "session" && $0.id != head.id }
        XCTAssertEqual(promoted?.parentRevisionID, head.id)
    }

    /// A session that changed nothing promotes nothing -- no empty
    /// revision per launch.
    func testASessionThatChangesNothingPromotesNothing() async throws {
        let lineID = try makeLine()
        let bytes = Data(repeating: 0x77, count: 64)
        try recordHead(lineID: lineID, digest: digest(bytes), sizeBytes: 64)
        try write(bytes)

        let before = saveStore.fetchRevisions(saveLineID: lineID).count
        let coordinator = makeCoordinator()
        await begin(coordinator, lineID: lineID)
        await coordinator.end()

        XCTAssertEqual(saveStore.fetchRevisions(saveLineID: lineID).count, before, "no new revision for an unchanged session")
    }

    /// The promotion hook is what starts an upload drain in the shipped
    /// app -- it must fire on a real promotion and only on a real one.
    func testThePromotionHookFiresOnlyWhenARevisionIsActuallyPromoted() async throws {
        let lineID = try makeLine()
        let fired = PromotionCounter(0)

        let coordinator = makeCoordinator(onPromoted: { fired.increment() })
        await begin(coordinator, lineID: lineID)
        await coordinator.end()
        XCTAssertEqual(fired.value, 0, "no bytes changed, so nothing was promoted")

        await begin(coordinator, lineID: lineID)
        try write(Data(repeating: 0x88, count: 64))
        await coordinator.end()
        XCTAssertEqual(fired.value, 1)
    }

    // MARK: - end() is always safe

    func testEndWithoutBeginIsANoOp() async throws {
        let lineID = try makeLine()
        try write(Data(repeating: 0x99, count: 64))

        let coordinator = makeCoordinator()
        await coordinator.end()

        XCTAssertTrue(saveStore.fetchRevisions(saveLineID: lineID).isEmpty)
        let isOpen = await coordinator.isSessionOpen
        XCTAssertFalse(isOpen)
    }

    func testASecondEndPromotesNothingASecondTime() async throws {
        let lineID = try makeLine()
        let coordinator = makeCoordinator()

        await begin(coordinator, lineID: lineID)
        try write(Data(repeating: 0xAA, count: 64))
        await coordinator.end()
        await coordinator.end()

        XCTAssertEqual(
            saveStore.fetchRevisions(saveLineID: lineID).filter { $0.tier == SaveCaptureTier.promoted.rawValue }.count,
            1
        )
    }

    func testASecondBeginWhileASessionIsOpenDoesNotReplaceIt() async throws {
        let lineID = try makeLine()
        let coordinator = makeCoordinator()

        await begin(coordinator, lineID: lineID)
        let first = await coordinator.openSessionID
        await begin(coordinator, lineID: lineID)
        let second = await coordinator.openSessionID
        XCTAssertEqual(first, second)
        await coordinator.end()
    }

    // MARK: - D-31: a capture failure never becomes a launch failure

    /// A capture that cannot be written must not throw out to `play()`,
    /// which would surface a save-bookkeeping problem to the user as
    /// "Launch failed". It is recorded as a durable blockage instead.
    func testACaptureFailureDoesNotPropagateAndIsRecordedAsABlockage() async throws {
        let lineID = try makeLine()
        let blocked = SaveCaptureBlockedState(localStore: localStore)
        // `/dev/null` is a character device, so no directory can be
        // created beneath it -- every durable write the poller attempts
        // fails.
        let unwritable = URL(fileURLWithPath: "/dev/null/save-captures")

        let coordinator = SaveSessionCoordinator(
            saveStore: saveStore, blockedState: blocked, pollInterval: 3600
        )
        await coordinator.begin(
            saveLineID: lineID, targetURL: targetURL, destinationDirectory: unwritable,
            artifactRelativePath: "game.sav"
        )
        try write(Data(repeating: 0xBB, count: 64))
        await coordinator.end()

        XCTAssertTrue(
            saveStore.fetchRevisions(saveLineID: lineID).isEmpty,
            "a capture that could not be written must never record a revision claiming it was"
        )
        let blockage = await blocked.openBlockage(saveLineID: lineID)
        XCTAssertNotNil(blockage, "the failure must be visible as a durable blockage (D-31), never silent")
    }

    /// A session that captures successfully clears a blockage a previous
    /// session left open -- the row is resolved, never deleted.
    func testASuccessfulCaptureClearsAPreviouslyOpenBlockage() async throws {
        let lineID = try makeLine()
        let blocked = SaveCaptureBlockedState(localStore: localStore)
        _ = try await blocked.recordFailure(
            saveLineID: lineID, sessionID: "earlier", digest: nil, reason: "disk full"
        )

        let coordinator = makeCoordinator(blockedState: blocked)
        await begin(coordinator, lineID: lineID)
        try write(Data(repeating: 0xCC, count: 64))
        await coordinator.end()

        let blockage = await blocked.openBlockage(saveLineID: lineID)
        XCTAssertNil(blockage)
    }

    // MARK: - No reimplementation

    /// The prohibition this plan carries, asserted against the source:
    /// the coordinator calls the poller's settle/promote/quiescence
    /// methods and never spells out its own. A second settle-then-promote
    /// implementation is exactly what `SaveSessionRecovery`'s own doc
    /// comment warns against.
    func testTheCoordinatorReimplementsNoCaptureLogic() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SavesTests
            .deletingLastPathComponent() // PlaysteadTests
            .deletingLastPathComponent() // playstead-mac
            .appendingPathComponent("Playstead/Saves/SaveSessionCoordinator.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("poller.settle()"), "settle must be called on the poller")
        XCTAssertTrue(source.contains("poller.promote()"), "promote must be called on the poller")
        XCTAssertTrue(source.contains("poller.startSession()"), "the D-04 baseline check must be called on the poller")
        XCTAssertFalse(source.contains("func settle"), "settle must never be reimplemented here")
        XCTAssertFalse(source.contains("func promote"), "promote must never be reimplemented here")
        XCTAssertFalse(source.contains("SHA256.hash"), "digesting belongs to the poller, not the coordinator")
        XCTAssertFalse(source.contains("recentDigests"), "quiescence detection belongs to the poller, not the coordinator")
    }
}

/// A minimal thread-safe counter for asserting a `@Sendable` callback
/// fired -- the callback crosses an actor boundary, so a plain captured
/// `var` would not be legal.
private final class PromotionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int

    init(_ value: Int) { self._value = value }

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
