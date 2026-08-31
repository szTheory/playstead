import XCTest
import CryptoKit
@testable import Playstead

final class ReadinessEngineTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!
    private var cas: CASManager!
    private var localStore: LocalStore!
    private var downloadQueue: DownloadQueue!
    private var saveDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths(root: tempRoot)
        cas = CASManager(paths: paths)
        localStore = try LocalStore(paths: paths)
        downloadQueue = DownloadQueue(localStore: localStore)
        saveDir = tempRoot.appendingPathComponent("saves", isDirectory: true)
        try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        StubURLProtocol.reset()
    }

    override func tearDownWithError() throws {
        StubURLProtocol.reset()
        // Restore write permission before cleanup, in case a test made
        // the save directory read-only.
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: saveDir.path)
        try? FileManager.default.removeItem(at: tempRoot)
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    private func seedVerifiedObject(seed: String, bytes: Int = 256) throws -> RequiredMember {
        let seedByte = Int(seed.utf8.first ?? 0)
        var raw = [UInt8](repeating: 0, count: bytes)
        for i in 0..<bytes { raw[i] = UInt8((i + seedByte) & 0xFF) }
        let data = Data(raw)
        let digest = sha256Hex(data)

        let partial = paths.partialURL(for: digest)
        try FileManager.default.createDirectory(at: paths.partials, withIntermediateDirectories: true)
        try data.write(to: partial)
        try cas.commit(partialAt: partial, sha256: digest)
        return RequiredMember(sha256: digest, size: bytes)
    }

    private func makeEngine(
        adapterInstallState: @escaping () -> AdapterInstallState = { .installed(executablePath: "/usr/bin/true", verified: true) },
        biosRequired: Bool = false,
        hasManagedBIOS: @escaping () -> Bool = { true },
        hasController: @escaping () -> Bool = { false },
        hasKeyboard: @escaping () -> Bool = { true },
        saveDirectoryURL: URL? = nil
    ) -> ReadinessEngine {
        ReadinessEngine(
            cas: cas, downloadQueue: downloadQueue,
            adapterInstallState: adapterInstallState,
            biosRequired: biosRequired, hasManagedBIOS: hasManagedBIOS,
            hasController: hasController, hasKeyboard: hasKeyboard,
            saveDirectoryURL: saveDirectoryURL ?? saveDir
        )
    }

    private func check(_ report: ReadinessReport, _ kind: ReadinessCheckKind) -> ReadinessCheck? {
        report.checks.first { $0.kind == kind }
    }

    // MARK: - Fully ready

    func testEverythingSatisfiedReturnsReady() throws {
        let member = try seedVerifiedObject(seed: "a")
        let engine = makeEngine()

        let report = engine.evaluate(assetSetID: "g1", requiredMembers: [member])

        XCTAssertTrue(report.isReady)
        XCTAssertTrue(report.checks.allSatisfy { $0.outcome == .ready })
    }

    // MARK: - Missing required member

    func testMissingRequiredMemberBlocksNamesItAndOffersDownloadRemedy() throws {
        let missingSHA = String(repeating: "9", count: 64)
        let engine = makeEngine()

        let report = engine.evaluate(assetSetID: "g1", requiredMembers: [RequiredMember(sha256: missingSHA, size: 100)])

        guard let assetsCheck = check(report, .gameAssets) else { return XCTFail("expected .gameAssets check") }
        XCTAssertTrue(assetsCheck.outcome.isBlocking)
        guard case .blocked(let text) = assetsCheck.outcome else { return XCTFail("expected blocked") }
        XCTAssertTrue(text.contains(missingSHA))
        XCTAssertNotNil(assetsCheck.remedy)
        XCTAssertEqual(assetsCheck.remedy?.action, .downloadMember(sha256: missingSHA))
        XCTAssertFalse(report.isReady)
    }

    // MARK: - Zero and one required member behave the same shape

    func testZeroRequiredMembersEvaluatesWithoutErrorAndReportsReady() throws {
        let engine = makeEngine()
        let report = engine.evaluate(assetSetID: "g1", requiredMembers: [])

        XCTAssertEqual(check(report, .gameAssets)?.outcome, .ready)
        XCTAssertEqual(check(report, .cacheVerification)?.outcome, .ready)
    }

    func testOneRequiredMemberBehavesLikeMultiple() throws {
        let one = try seedVerifiedObject(seed: "a")
        let many = [try seedVerifiedObject(seed: "b"), try seedVerifiedObject(seed: "c"), try seedVerifiedObject(seed: "d")]
        let engine = makeEngine()

        let oneReport = engine.evaluate(assetSetID: "g1", requiredMembers: [one])
        let manyReport = engine.evaluate(assetSetID: "g2", requiredMembers: many)

        XCTAssertTrue(oneReport.isReady)
        XCTAssertTrue(manyReport.isReady)
    }

    // MARK: - Missing adapter

    func testMissingAdapterBlocksWithInstallRemedy() throws {
        let member = try seedVerifiedObject(seed: "a")
        let engine = makeEngine(adapterInstallState: { .notInstalled })

        let report = engine.evaluate(assetSetID: "g1", requiredMembers: [member])

        guard let emulatorCheck = check(report, .emulator) else { return XCTFail("expected .emulator check") }
        XCTAssertTrue(emulatorCheck.outcome.isBlocking)
        XCTAssertEqual(emulatorCheck.remedy?.action, .installAdapter)
        XCTAssertFalse(report.isReady)
    }

    // MARK: - Required-but-absent BIOS

    func testRequiredButAbsentBiosBlocksWithDropInRemedyAndNoAcquisitionSuggestion() throws {
        let member = try seedVerifiedObject(seed: "a")
        let engine = makeEngine(biosRequired: true, hasManagedBIOS: { false })

        let report = engine.evaluate(assetSetID: "g1", requiredMembers: [member])

        guard let biosCheck = check(report, .bios) else { return XCTFail("expected .bios check") }
        XCTAssertTrue(biosCheck.outcome.isBlocking)
        XCTAssertEqual(biosCheck.remedy?.action, .openBiosDropTarget)
        let combinedCopy = (biosCheck.finding + (biosCheck.remedy?.title ?? "")).lowercased()
        XCTAssertFalse(combinedCopy.contains("http"))
        XCTAssertFalse(combinedCopy.contains("download"))
    }

    func testBiosNotRequiredAndAbsentIsNotBlocking() throws {
        let member = try seedVerifiedObject(seed: "a")
        let engine = makeEngine(biosRequired: false, hasManagedBIOS: { false })

        let report = engine.evaluate(assetSetID: "g1", requiredMembers: [member])

        XCTAssertEqual(check(report, .bios)?.outcome, .ready)
    }

    // MARK: - Controller / keyboard input

    func testNoControllerIsNotBlockingWhenKeyboardIsAvailable() throws {
        let member = try seedVerifiedObject(seed: "a")
        let engine = makeEngine(hasController: { false }, hasKeyboard: { true })

        let report = engine.evaluate(assetSetID: "g1", requiredMembers: [member])

        XCTAssertEqual(check(report, .controllerAndInput)?.outcome, .ready)
    }

    func testNoControllerAndNoKeyboardBlocksWithInputSettingsRemedy() throws {
        let member = try seedVerifiedObject(seed: "a")
        let engine = makeEngine(hasController: { false }, hasKeyboard: { false })

        let report = engine.evaluate(assetSetID: "g1", requiredMembers: [member])

        guard let inputCheck = check(report, .controllerAndInput) else { return XCTFail("expected .controllerAndInput check") }
        XCTAssertTrue(inputCheck.outcome.isBlocking)
        XCTAssertEqual(inputCheck.remedy?.action, .openInputSettings)
    }

    // MARK: - Save directory

    func testUnwritableSaveDirectoryBlocksWithRepairRemedy() throws {
        let member = try seedVerifiedObject(seed: "a")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: saveDir.path)
        let engine = makeEngine()

        let report = engine.evaluate(assetSetID: "g1", requiredMembers: [member])

        guard let saveCheck = check(report, .saveDirectory) else { return XCTFail("expected .saveDirectory check") }
        XCTAssertTrue(saveCheck.outcome.isBlocking)
        XCTAssertEqual(saveCheck.remedy?.action, .repairSaveDirectory)
    }

    // MARK: - Ordering, stability, and idempotence

    func testEveryBlockingOutcomeCarriesANonNilRemedyWithNonEmptyTitle() throws {
        let engine = makeEngine(
            adapterInstallState: { .notInstalled }, biosRequired: true, hasManagedBIOS: { false },
            hasController: { false }, hasKeyboard: { false }
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: saveDir.path)
        let missingSHA = String(repeating: "1", count: 64)

        let report = engine.evaluate(assetSetID: "g1", requiredMembers: [RequiredMember(sha256: missingSHA, size: 10)])

        for kind in ReadinessCheckKind.allCases {
            guard let result = check(report, kind), result.outcome.isBlocking else { continue }
            XCTAssertNotNil(result.remedy, "\(kind) is blocking but has no remedy")
            XCTAssertFalse(result.remedy?.title.isEmpty ?? true, "\(kind)'s remedy has an empty title")
        }
        // Every kind above was deliberately forced blocking except cacheVerification (nothing to verify without a present object).
        XCTAssertTrue(ReadinessCheckKind.allCases.compactMap { check(report, $0) }.filter(\.outcome.isBlocking).count >= 4)
    }

    func testOrderingIsIdenticalAcrossTenRepeatedEvaluations() throws {
        let member = try seedVerifiedObject(seed: "a")
        let engine = makeEngine(adapterInstallState: { .notInstalled })

        let reports = (0..<10).map { _ in engine.evaluate(assetSetID: "g1", requiredMembers: [member]) }
        let orders = reports.map { $0.checks.map(\.kind) }

        XCTAssertTrue(orders.allSatisfy { $0 == orders[0] })
    }

    func testTwoConsecutiveEvaluationsOnUnchangedInputsProduceEqualReportsAndUnchangedDisk() throws {
        let member = try seedVerifiedObject(seed: "a")
        let engine = makeEngine()

        let objectPath = cas.objectURL(for: member.sha256).path
        let attrsBefore = try FileManager.default.attributesOfItem(atPath: objectPath)

        let first = engine.evaluate(assetSetID: "g1", requiredMembers: [member])
        let second = engine.evaluate(assetSetID: "g1", requiredMembers: [member])

        XCTAssertEqual(first, second)
        let attrsAfter = try FileManager.default.attributesOfItem(atPath: objectPath)
        XCTAssertEqual(attrsBefore[.modificationDate] as? Date, attrsAfter[.modificationDate] as? Date)
    }

    // MARK: - Corruption: re-hash, quarantine, requeue, no-blame

    func testCorruptedCacheObjectIsQuarantinedRedownloadEnqueuedAndReportedWithoutBlame() throws {
        let member = try seedVerifiedObject(seed: "a")
        // Corrupt the committed bytes directly — the cheap check will
        // still disagree with the recorded verify record's size (since
        // we overwrite in place, mtime/inode may or may not change, but
        // content no longer hashes to `member.sha256`), forcing a full
        // re-hash that also fails, per `PreflightChecker`'s fallback.
        let objectURL = cas.objectURL(for: member.sha256)
        try Data("corrupted-bytes-not-matching-digest".utf8).write(to: objectURL)

        let engine = makeEngine()
        let report = engine.evaluate(assetSetID: "g1", requiredMembers: [member])

        guard let cacheCheck = check(report, .cacheVerification) else { return XCTFail("expected .cacheVerification check") }
        XCTAssertTrue(cacheCheck.outcome.isBlocking)
        // No-blame: the finding must not suggest the user caused this —
        // it may reassuringly say the opposite ("wasn't caused by
        // anything you did"), just never phrase it as the user's fault.
        XCTAssertFalse(cacheCheck.finding.lowercased().contains("your fault"))
        XCTAssertFalse(cacheCheck.finding.lowercased().contains("you did something"))
        XCTAssertTrue(cacheCheck.finding.lowercased().contains("automatically") || cacheCheck.finding.lowercased().contains("replac"))

        // Quarantined: the original object path is gone.
        XCTAssertFalse(FileManager.default.fileExists(atPath: objectURL.path))
        // A quarantine copy exists somewhere under partials/quarantine/.
        let quarantineDir = paths.partials.appendingPathComponent("quarantine")
        let quarantined = (try? FileManager.default.contentsOfDirectory(atPath: quarantineDir.path)) ?? []
        XCTAssertFalse(quarantined.isEmpty)

        // Redownload enqueued.
        let queued = downloadQueue.itemsForAssetSet("g1")
        XCTAssertTrue(queued.contains { $0.sha256 == member.sha256 })
    }

    // MARK: - Zero network calls

    func testEvaluationMakesNoNetworkRequestsEvenWhenAllRequestsWouldFail() throws {
        let member = try seedVerifiedObject(seed: "a")
        StubURLProtocol.responder = { _ in
            XCTFail("ReadinessEngine.evaluate must never attempt a network request")
            return StubURLProtocol.Stub(statusCode: 500, headers: [:], body: Data())
        }

        let engine = makeEngine()
        let report = engine.evaluate(assetSetID: "g1", requiredMembers: [member])

        XCTAssertTrue(report.isReady)
        XCTAssertTrue(StubURLProtocol.requestLog.isEmpty)
    }

    // MARK: - Play control availability

    func testPlayControlAvailabilityMatchesReportReadiness() throws {
        let member = try seedVerifiedObject(seed: "a")
        let readyEngine = makeEngine()
        let readyReport = readyEngine.evaluate(assetSetID: "g1", requiredMembers: [member])
        XCTAssertTrue(readyReport.isReady)

        let blockedEngine = makeEngine(adapterInstallState: { .notInstalled })
        let blockedReport = blockedEngine.evaluate(assetSetID: "g1", requiredMembers: [member])
        XCTAssertFalse(blockedReport.isReady)
    }
}
