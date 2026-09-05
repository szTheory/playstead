import XCTest
import CryptoKit
@testable import Playstead

/// Covers the production `SavePlanExecutorEnvironment` conformance
/// (WINDOWS #37): reading revision bytes only from an already-committed
/// CAS object, never the network; preserving whatever sits at a target
/// path before it is overwritten; and routing a digest mismatch to the
/// CAS's own quarantine path.
final class LaunchSaveEnvironmentTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!
    private var cas: CASManager!
    private var environment: LaunchSaveEnvironment!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths(root: tempRoot)
        cas = CASManager(paths: paths)
        environment = LaunchSaveEnvironment(casManager: cas)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try super.tearDownWithError()
    }

    private func hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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

    // MARK: - revisionBytes(forDigest:)

    func testRevisionBytesReturnsTheExactCommittedBytes() throws {
        let bytes = Data(repeating: 0x42, count: 4096)
        let digest = try commitIntoCAS(bytes)

        let returned = try environment.revisionBytes(forDigest: digest)

        XCTAssertEqual(returned, bytes)
    }

    func testRevisionBytesThrowsForADigestAbsentFromTheCASRatherThanFetching() {
        XCTAssertThrowsError(
            try environment.revisionBytes(forDigest: String(repeating: "a", count: 64))
        ) { error in
            guard case SavePlanExecutorError.digestMismatch = error else {
                return XCTFail("expected .digestMismatch, got \(error)")
            }
        }
    }

    func testEnvironmentSourceNeverReferencesNetworkingTypes() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SavesTests
            .deletingLastPathComponent() // PlaysteadTests
            .deletingLastPathComponent() // playstead-mac
            .appendingPathComponent("Playstead/Saves/LaunchSaveEnvironment.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let forbidden = ["URLSession", "APIClient", "http://", "https://"]
        XCTAssertTrue(
            forbidden.filter(source.contains).isEmpty,
            "LaunchSaveEnvironment.swift must never reference networking machinery"
        )
    }

    // MARK: - captureExistingFile(at:)

    func testCaptureExistingFilePreservesPreExistingBytesIntoTheCAS() throws {
        let saveDir = tempRoot.appendingPathComponent("saves/game-1", isDirectory: true)
        try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        let target = saveDir.appendingPathComponent("game.sav")
        let existingBytes = Data(repeating: 0x11, count: 1024)
        try existingBytes.write(to: target)

        try environment.captureExistingFile(at: target)

        XCTAssertTrue(cas.contains(hex(of: existingBytes)), "the pre-existing bytes must now be durable in the CAS")
    }

    func testCaptureExistingFileIsANoOpWhenNothingExistsAtTarget() throws {
        let saveDir = tempRoot.appendingPathComponent("saves/game-1", isDirectory: true)
        try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        let target = saveDir.appendingPathComponent("game.sav")

        XCTAssertNoThrow(try environment.captureExistingFile(at: target))
    }

    func testCaptureExistingFileIsANoOpWhenTheExistingFileIsZeroBytes() throws {
        let saveDir = tempRoot.appendingPathComponent("saves/game-1", isDirectory: true)
        try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        let target = saveDir.appendingPathComponent("game.sav")
        try Data().write(to: target)

        XCTAssertNoThrow(try environment.captureExistingFile(at: target))
    }

    // MARK: - quarantineCorruptRevision(digest:actualDigest:)

    func testQuarantineCorruptRevisionMovesTheCommittedObjectAsideWithoutDeletingIt() throws {
        let bytes = Data(repeating: 0x99, count: 512)
        let digest = try commitIntoCAS(bytes)
        let objectURL = try cas.objectURL(for: digest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: objectURL.path))

        environment.quarantineCorruptRevision(digest: digest, actualDigest: "some-other-digest")

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: objectURL.path),
            "the corrupt object must be moved out of objects/, never left in place"
        )
        let quarantineDir = paths.partials.appendingPathComponent("quarantine", isDirectory: true)
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: quarantineDir.path)) ?? []
        XCTAssertFalse(contents.isEmpty, "quarantine must preserve the bytes somewhere on disk, never delete them")
    }

    func testQuarantineCorruptRevisionIsSafeWhenTheDigestNamesNoRealObject() {
        // A malformed or never-committed digest: quarantining must never
        // crash or throw an uncaught error out of this non-throwing
        // protocol method.
        environment.quarantineCorruptRevision(digest: "not-a-real-digest", actualDigest: "also-not-real")
    }
}
