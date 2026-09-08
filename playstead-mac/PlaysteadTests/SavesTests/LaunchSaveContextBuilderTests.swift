import XCTest
import CryptoKit
@testable import Playstead

/// Covers `LaunchSaveContextBuilder` (WINDOWS #37): assembling a
/// `LaunchSaveContext` from already-local `SaveStore`/`CASManager`
/// facts only, with no query ever reaching for the network.
final class LaunchSaveContextBuilderTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!
    private var localStore: LocalStore!
    private var saveStore: SaveStore!
    private var cas: CASManager!
    private var contract: AdapterSaveContract!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths(root: tempRoot)
        localStore = try LocalStore(paths: paths)
        saveStore = SaveStore(localStore: localStore)
        cas = CASManager(paths: paths)
        contract = try AdapterPin.load().saveContract
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try super.tearDownWithError()
    }

    private func hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func builder() -> LaunchSaveContextBuilder {
        LaunchSaveContextBuilder(saveStore: saveStore, casManager: cas, saveContract: contract, systemID: "gba")
    }

    @discardableResult
    private func commitIntoCAS(_ data: Data) throws -> String {
        let digest = hex(of: data)
        try FileManager.default.createDirectory(at: paths.partials, withIntermediateDirectories: true)
        let partial = try paths.partialURL(for: digest)
        try data.write(to: partial)
        try cas.commit(partialAt: partial, sha256: digest)
        return digest
    }

    private func insertHead(
        id: String, lineID: String, parentID: String? = nil, digest: String, sizeBytes: Int = 32_768,
        originDeviceID: String? = "another-mac", recordedAt: String? = "2026-01-01T00:00:00Z"
    ) throws {
        try saveStore.insertRevision(SaveRevisionRow(
            id: id, saveLineID: lineID, parentRevisionID: parentID, blobSHA256: digest, sizeBytes: sizeBytes,
            originDeviceID: originDeviceID, deviceCapturedAt: nil, recordedAt: recordedAt,
            captureMethod: nil, adapterID: nil, adapterVersion: nil, saveFormat: nil, formatConfidence: nil,
            playSessionID: nil, durability: SaveDurability.uploaded.rawValue, localPath: nil
        ))
    }

    // MARK: - No save line exists yet

    func testMissingSaveLineYieldsANoOpPlanWithEmptyTargetFile() throws {
        let target = tempRoot.appendingPathComponent("saves/game-1/game.sav")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

        let context = builder().buildContext(contentKey: "rom-never-seen", targetURL: target)
        XCTAssertTrue(context.heads.isEmpty)
        XCTAssertNil(context.onDiskDigest)

        let plan = LaunchSavePlanner.plan(context: context)
        XCTAssertNoThrow(try SavePlanExecutor(environment: NeverCalledEnvironment()).execute(plan, targetURL: target))
        if case .fresh = plan {} else { XCTFail("expected .fresh for a first-ever launch, got \(plan)") }
    }

    func testMissingSaveLineWithUncapturedOnDiskBytesStillYieldsANoOpPlan() throws {
        let target = tempRoot.appendingPathComponent("saves/game-1/game.sav")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x5, count: 100).write(to: target)

        let context = builder().buildContext(contentKey: "rom-never-seen", targetURL: target)
        let plan = LaunchSavePlanner.plan(context: context)

        // .keep is a no-op for the executor exactly like .fresh -- see
        // SavePlanExecutor.execute's `case .fresh, .keep: return`.
        XCTAssertNoThrow(try SavePlanExecutor(environment: NeverCalledEnvironment()).execute(plan, targetURL: target))
    }

    // MARK: - WINDOWS #49: a save this Mac captured is really local

    /// The assertion the whole gap-closure exists for, made at the
    /// surface that actually had the defect.
    ///
    /// Nothing here inserts a revision by hand or pre-seeds the CAS: a
    /// real `SaveSessionCoordinator` session captures bytes off disk,
    /// and then the real `LaunchSaveContextBuilder` is asked what it
    /// makes of the result. Before the coordinator committed capture
    /// bytes into the CAS, this reported `bytesLocal: false` for a save
    /// the user had just made on this very machine -- restorable only
    /// after a server round-trip. No network is involved on either half.
    func testASaveCapturedOnThisMacIsReportedAsBytesLocalWithNoServerInvolvement() async throws {
        let contentKey = "rom-captured-here"
        let line = try saveStore.resolveLine(
            contentKey: contentKey, saveKind: "battery", slot: "0", placeholderID: "line-captured-here"
        )

        let target = tempRoot.appendingPathComponent("saves/asset-1/game.sav")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

        let coordinator = SaveSessionCoordinator(
            saveStore: saveStore,
            casManager: cas,
            provenance: .unknown,
            pollInterval: 3600 // the 1 Hz loop never fires inside this test
        )
        await coordinator.begin(
            saveLineID: line.id,
            targetURL: target,
            destinationDirectory: tempRoot.appendingPathComponent("save-captures/asset-1", isDirectory: true),
            artifactRelativePath: "game.sav"
        )

        let saveBytes = Data(repeating: 0x7E, count: 32_768)
        try saveBytes.write(to: target)
        await coordinator.end()

        let context = builder().buildContext(contentKey: contentKey, targetURL: target)
        let head = try XCTUnwrap(
            context.heads.first { $0.digest == hex(of: saveBytes) },
            "the session's promoted capture must be a head on this line"
        )
        XCTAssertTrue(
            head.bytesLocal,
            "a save captured on this Mac must be restorable from history without a server round-trip"
        )
    }

    // MARK: - bytesLocal

    func testHeadAbsentFromCASIsReportedAsNotLocalRatherThanOmitted() throws {
        try saveStore.resolveLine(contentKey: "rom-x", saveKind: "battery", slot: "0", placeholderID: "line-x")
        try insertHead(id: "r1", lineID: "line-x", digest: "digest-not-in-cas")

        let target = tempRoot.appendingPathComponent("saves/game-1/game.sav")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

        let context = builder().buildContext(contentKey: "rom-x", targetURL: target)

        XCTAssertEqual(context.heads.count, 1)
        XCTAssertEqual(context.heads.first?.digest, "digest-not-in-cas")
        XCTAssertEqual(context.heads.first?.bytesLocal, false)
    }

    func testHeadPresentInCASIsReportedAsLocal() throws {
        let bytes = Data(repeating: 0x7, count: 32_768)
        let digest = try commitIntoCAS(bytes)
        try saveStore.resolveLine(contentKey: "rom-y", saveKind: "battery", slot: "0", placeholderID: "line-y")
        try insertHead(id: "r1", lineID: "line-y", digest: digest)

        let target = tempRoot.appendingPathComponent("saves/game-1/game.sav")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

        let context = builder().buildContext(contentKey: "rom-y", targetURL: target)

        XCTAssertEqual(context.heads.first?.bytesLocal, true)
    }

    // MARK: - onDiskDigest

    func testZeroByteOnDiskArtifactYieldsNilOnDiskDigest() throws {
        let target = tempRoot.appendingPathComponent("saves/game-1/game.sav")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: target)

        let context = builder().buildContext(contentKey: "rom-z", targetURL: target)
        XCTAssertNil(context.onDiskDigest)
    }

    func testMissingOnDiskArtifactYieldsNilOnDiskDigest() throws {
        let target = tempRoot.appendingPathComponent("saves/game-1/game.sav")
        let context = builder().buildContext(contentKey: "rom-z", targetURL: target)
        XCTAssertNil(context.onDiskDigest)
    }

    func testNonEmptyOnDiskArtifactYieldsItsSHA256() throws {
        let target = tempRoot.appendingPathComponent("saves/game-1/game.sav")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = Data(repeating: 0xAB, count: 200)
        try bytes.write(to: target)

        let context = builder().buildContext(contentKey: "rom-z", targetURL: target)
        XCTAssertEqual(context.onDiskDigest, hex(of: bytes))
    }

    // MARK: - knownDigests / ancestorDigests

    func testKnownDigestsPopulatedFromEveryRevisionRecordedForTheLine() throws {
        try saveStore.resolveLine(contentKey: "rom-w", saveKind: "battery", slot: "0", placeholderID: "line-w")
        try insertHead(id: "r1", lineID: "line-w", digest: "digest-1")
        try insertHead(id: "r2", lineID: "line-w", parentID: "r1", digest: "digest-2")

        let target = tempRoot.appendingPathComponent("saves/game-1/game.sav")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

        let context = builder().buildContext(contentKey: "rom-w", targetURL: target)
        XCTAssertEqual(context.knownDigests, ["digest-1", "digest-2"])
        // r2 is the only head (r1 has a child) -- its ancestor set
        // includes r1's digest.
        XCTAssertEqual(context.ancestorDigests, ["digest-1"])
    }

    // MARK: - compatibilityVerdict

    func testSingleHeadWithABoundArtifactSizeAttachesAnExactVerdict() throws {
        try saveStore.resolveLine(contentKey: "rom-u", saveKind: "battery", slot: "0", placeholderID: "line-u")
        try insertHead(id: "r1", lineID: "line-u", digest: "digest-1", sizeBytes: 32_768)

        let target = tempRoot.appendingPathComponent("saves/game-1/game.sav")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

        let context = builder().buildContext(contentKey: "rom-u", targetURL: target)
        XCTAssertEqual(context.compatibilityVerdict, .exact)
    }

    func testSingleHeadWhoseSizeMatchesNoDeclaredMediumIsIncompatible() throws {
        try saveStore.resolveLine(contentKey: "rom-t", saveKind: "battery", slot: "0", placeholderID: "line-t")
        try insertHead(id: "r1", lineID: "line-t", digest: "digest-1", sizeBytes: 999)

        let target = tempRoot.appendingPathComponent("saves/game-1/game.sav")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

        let context = builder().buildContext(contentKey: "rom-t", targetURL: target)
        if case .incompatible = context.compatibilityVerdict {} else {
            XCTFail("expected .incompatible for an unbound artifact size, got \(String(describing: context.compatibilityVerdict))")
        }
    }

    func testDivergedLineNeverAttachesAncestorDigestsOrAVerdict() throws {
        try saveStore.resolveLine(contentKey: "rom-v", saveKind: "battery", slot: "0", placeholderID: "line-v")
        try insertHead(id: "r1", lineID: "line-v", digest: "digest-1")
        try insertHead(id: "r2", lineID: "line-v", digest: "digest-2")

        let target = tempRoot.appendingPathComponent("saves/game-1/game.sav")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

        let context = builder().buildContext(contentKey: "rom-v", targetURL: target)
        XCTAssertEqual(context.heads.count, 2)
        XCTAssertTrue(context.ancestorDigests.isEmpty)
        XCTAssertNil(context.compatibilityVerdict)
    }
}

/// A `SavePlanExecutorEnvironment` that fails the test if any of its
/// methods are ever called -- used to prove a `.fresh`/`.keep` plan is
/// executed as a literal no-op.
private struct NeverCalledEnvironment: SavePlanExecutorEnvironment {
    func revisionBytes(forDigest digest: String) throws -> Data {
        XCTFail("revisionBytes must never be called for a no-op plan")
        throw SavePlanExecutorError.digestMismatch(expected: digest, actual: "unexpected-call")
    }
    func captureExistingFile(at targetURL: URL) throws {
        XCTFail("captureExistingFile must never be called for a no-op plan")
    }
    func quarantineCorruptRevision(digest: String, actualDigest: String) {
        XCTFail("quarantineCorruptRevision must never be called for a no-op plan")
    }
}
