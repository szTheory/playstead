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

    private func gameBoyBuilder(
        targetROM: URL,
        digest: String,
        systemID: String = "gb",
        declarations: [CartridgeSupportDeclaration] = [CartridgeQualification.mbc1Declaration]
    ) throws -> LaunchSaveContextBuilder {
        LaunchSaveContextBuilder(
            saveStore: saveStore,
            casManager: cas,
            saveContract: contract,
            systemID: systemID,
            targetROMURL: targetROM,
            targetROMExpectedSHA256: digest,
            declaredCartridges: declarations
        )
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

    func testTargetBindingIgnoresCandidateMetadata() throws {
        var romBytes = Data(repeating: 0, count: 32 * 1024)
        romBytes[0x143] = 0x00
        romBytes[0x147] = 0x03
        romBytes[0x149] = 0x02
        romBytes[0x14D] = (0x134...0x14C).reduce(UInt8(0)) { $0 &- romBytes[$1] &- 1 }
        let rom = tempRoot.appendingPathComponent("verified-target.gb")
        try romBytes.write(to: rom)
        let digest = hex(of: romBytes)
        let line = try saveStore.resolveLine(contentKey: digest, saveKind: "battery", slot: "0", placeholderID: "gb-target")
        try saveStore.insertRevision(SaveRevisionRow(
            id: "gb-revision", saveLineID: line.id, parentRevisionID: nil,
            blobSHA256: "revision-digest", sizeBytes: 8_192,
            originDeviceID: "another-device", deviceCapturedAt: nil, recordedAt: "2026-01-01T00:00:00Z",
            captureMethod: "emulator", adapterID: "candidate-only-adapter", adapterVersion: "candidate-only-version",
            saveFormat: CartridgeQualification.mbc1Declaration.saveFormat, formatConfidence: "exact",
            playSessionID: nil, durability: SaveDurability.uploaded.rawValue, localPath: nil
        ))
        let target = tempRoot.appendingPathComponent("saves/gb-game/game.sav")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

        let context = try gameBoyBuilder(targetROM: rom, digest: digest).buildContext(contentKey: digest, targetURL: target)
        XCTAssertEqual(context.compatibilityVerdict, .exact)

        let wrongDigestContext = try gameBoyBuilder(targetROM: rom, digest: String(repeating: "0", count: 64))
            .buildContext(contentKey: digest, targetURL: target)
        if case .incompatible(reason: "target_cartridge_unqualified") = wrongDigestContext.compatibilityVerdict {} else {
            XCTFail("candidate metadata must not certify a target whose ROM digest fails qualification")
        }
    }

    func testThreeQualifiedTargetBindings() throws {
        let declarations = [
            CartridgeQualification.mbc1Declaration,
            CartridgeSupportDeclaration(
                systemID: "gbc", cartridgeID: "mbc5", cgbFlag: 0xC0,
                cartridgeType: 0x1B, ramSizeCode: 0x03, mediumID: "gbc_sram_32k",
                artifactBytes: 32_768, saveFormat: "mgba-0.10.5-gbc-mbc5-sram-32k"
            ),
            CartridgeSupportDeclaration(
                systemID: "gbc", cartridgeID: "mbc3-rtc", cgbFlag: 0xC0,
                cartridgeType: 0x10, ramSizeCode: 0x03, mediumID: "gbc_sram_32k_rtc",
                artifactBytes: 32_816, saveFormat: "mgba-0.10.5-gbc-mbc3-rtc-sram-32k-v1"
            )
        ]
        let cases: [(UInt8, UInt8, UInt8, String, Int, String)] = [
            (0x00, 0x03, 0x02, "gb", 8_192, declarations[0].saveFormat),
            (0xC0, 0x1B, 0x03, "gbc", 32_768, declarations[1].saveFormat),
            (0xC0, 0x10, 0x03, "gbc", 32_816, declarations[2].saveFormat)
        ]

        for (cgbFlag, cartridgeType, ramCode, systemID, artifactBytes, format) in cases {
            var romBytes = Data(repeating: 0, count: 32 * 1024)
            romBytes[0x143] = cgbFlag
            romBytes[0x147] = cartridgeType
            romBytes[0x149] = ramCode
            romBytes[0x14D] = (0x134...0x14C).reduce(UInt8(0)) { $0 &- romBytes[$1] &- 1 }
            let rom = tempRoot.appendingPathComponent("target-\(UUID().uuidString).gbc")
            try romBytes.write(to: rom)
            defer { try? FileManager.default.removeItem(at: rom) }
            let romDigest = hex(of: romBytes)
            let line = try saveStore.resolveLine(
                contentKey: romDigest, saveKind: "battery", slot: "0", placeholderID: UUID().uuidString
            )
            let artifact = Data((0..<artifactBytes).map { UInt8(truncatingIfNeeded: $0 * 17 + 3) })
            let artifactDigest = hex(of: artifact)
            let localArtifact = tempRoot.appendingPathComponent("artifact-\(UUID().uuidString).sav")
            try artifact.write(to: localArtifact)
            try saveStore.insertRevision(SaveRevisionRow(
                id: UUID().uuidString, saveLineID: line.id, parentRevisionID: nil,
                blobSHA256: artifactDigest, sizeBytes: artifactBytes,
                originDeviceID: "source-device", deviceCapturedAt: nil, recordedAt: "2026-01-01T00:00:00Z",
                captureMethod: "session", adapterID: "mgba", adapterVersion: "0.10.5",
                saveFormat: format, formatConfidence: "exact", playSessionID: "source-session",
                durability: SaveDurability.uploaded.rawValue, localPath: localArtifact.path
            ))
            let target = tempRoot.appendingPathComponent("saves/\(UUID().uuidString)/game.sav")
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let originalTarget = Data(repeating: 0xD7, count: 23)
            try originalTarget.write(to: target)

            let builder = try gameBoyBuilder(
                targetROM: rom, digest: romDigest, systemID: systemID, declarations: declarations
            )
            let context = builder.buildContext(contentKey: romDigest, targetURL: target)
            XCTAssertEqual(context.compatibilityVerdict, .exact, "the exact declared target tuple must bind")

            XCTAssertEqual(try Data(contentsOf: target), originalTarget, "qualification must not mutate a target")
            XCTAssertEqual(saveStore.fetchRevisions(saveLineID: line.id).count, 1, "qualification must retain revision history")
        }
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
