import XCTest
@testable import Playstead

/// Covers D-42's widened `saveDirectory` check: from "directory is
/// writable" to "a file can be atomically placed here". The immutable-
/// target case is the one the old `isWritableFile` check could not see
/// — a directory reports writable while an existing immutable file at
/// the check's own target name blocks replacement, exactly the failure
/// mode the emulator hit at spawn.
final class SaveDirectoryAtomicPlacementTests: XCTestCase {

    /// The engine's own fixed target name for the atomic-placement
    /// probe — mirrored here so this test can pre-occupy it with an
    /// immutable fixture and force the replace to fail.
    private static let probeTargetName = ".playstead-readiness-write-probe-target"

    private var tempRoot: URL!
    private var saveDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SaveDirectoryAtomicPlacementTests-\(UUID().uuidString)", isDirectory: true)
        saveDir = tempRoot.appendingPathComponent("saves", isDirectory: true)
        try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Clear the immutable flag before cleanup, in case a test left
        // an immutable fixture behind.
        let fixtureURL = saveDir.appendingPathComponent(Self.probeTargetName, isDirectory: false)
        try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: fixtureURL.path)
        try? FileManager.default.removeItem(at: tempRoot)
        try super.tearDownWithError()
    }

    private func makeEngine(saveDirectoryURL: URL) -> ReadinessEngine {
        let paths = AppPaths(root: tempRoot)
        let cas = CASManager(paths: paths)
        let downloadQueue = DownloadQueue(localStore: try! LocalStore(paths: paths))
        return ReadinessEngine(
            cas: cas, downloadQueue: downloadQueue,
            adapterInstallState: { .installed(executablePath: "/usr/bin/true", verified: true) },
            biosRequired: false, hasManagedBIOS: { true },
            hasController: { false }, hasKeyboard: { true },
            saveDirectoryURL: saveDirectoryURL
        )
    }

    private func evaluateSaveCheck(saveDirectoryURL: URL) -> ReadinessCheck {
        let engine = makeEngine(saveDirectoryURL: saveDirectoryURL)
        let report = engine.evaluate(assetSetID: "g1", requiredMembers: [])
        guard let check = report.checks.first(where: { $0.kind == .saveDirectory }) else {
            XCTFail("expected a .saveDirectory check in the report")
            return ReadinessCheck(kind: .saveDirectory, outcome: .ready, finding: "", remedy: nil)
        }
        return check
    }

    // MARK: - Behaviours

    func testWritableEmptyDirectoryEvaluatesReady() {
        let check = evaluateSaveCheck(saveDirectoryURL: saveDir)
        XCTAssertFalse(check.outcome.isBlocking)
    }

    func testNonExistentDirectoryEvaluatesBlocked() {
        let missing = tempRoot.appendingPathComponent("does-not-exist", isDirectory: true)
        let check = evaluateSaveCheck(saveDirectoryURL: missing)
        XCTAssertTrue(check.outcome.isBlocking)
    }

    /// The case the old `isWritableFile` check could not see: the
    /// directory itself is writable, but the exact name the atomic
    /// replace targets is already occupied by an immutable file, so the
    /// replace operation itself fails.
    func testWritableDirectoryWithImmutableTargetNameEvaluatesBlocked() throws {
        let targetURL = saveDir.appendingPathComponent(Self.probeTargetName, isDirectory: false)
        try Data().write(to: targetURL)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: targetURL.path)

        let check = evaluateSaveCheck(saveDirectoryURL: saveDir)

        XCTAssertTrue(check.outcome.isBlocking, "an immutable file occupying the replace target must block, not pass")
    }

    func testBlockedResultCarriesTheLockedRemedy() {
        let missing = tempRoot.appendingPathComponent("does-not-exist", isDirectory: true)
        let check = evaluateSaveCheck(saveDirectoryURL: missing)

        XCTAssertEqual(check.remedy?.action, .repairSaveDirectory)
        XCTAssertEqual(check.remedy?.title, "Repair save folder")
    }

    /// Evaluation must leave no residue: the immutable fixture from the
    /// blocked case survives untouched, and a successful evaluation
    /// leaves the directory exactly as empty as it started.
    func testEvaluationLeavesNoResidue() throws {
        // Ready case: directory starts empty, must end empty.
        _ = evaluateSaveCheck(saveDirectoryURL: saveDir)
        let contentsAfterReady = try FileManager.default.contentsOfDirectory(atPath: saveDir.path)
        XCTAssertEqual(contentsAfterReady, [], "a ready evaluation must leave the save directory empty")

        // Blocked case: the immutable fixture is the only file present
        // before and after.
        let targetURL = saveDir.appendingPathComponent(Self.probeTargetName, isDirectory: false)
        try Data().write(to: targetURL)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: targetURL.path)

        _ = evaluateSaveCheck(saveDirectoryURL: saveDir)

        let contentsAfterBlocked = try FileManager.default.contentsOfDirectory(atPath: saveDir.path)
        XCTAssertEqual(contentsAfterBlocked, [Self.probeTargetName], "the fixture must be the only surviving file, unchanged")
    }
}
