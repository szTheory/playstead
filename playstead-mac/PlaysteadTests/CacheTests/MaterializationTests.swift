import XCTest
import CryptoKit
@testable import Playstead

final class MaterializationTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!
    private var cas: CASManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        paths = AppPaths(root: tempRoot)
        cas = CASManager(paths: paths)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try super.tearDownWithError()
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Commits a fixture object directly into the CAS (bypassing
    /// `DownloadEngine`, since these tests are about materialization,
    /// not transfer).
    @discardableResult
    private func seedCommittedObject(bytes: Int = 4096) throws -> (sha256: String, url: URL) {
        var raw = [UInt8](repeating: 0, count: bytes)
        for i in 0..<bytes { raw[i] = UInt8((i * 17) & 0xFF) }
        let data = Data(raw)
        let digest = sha256Hex(data)

        let partial = try paths.partialURL(for: digest)
        try FileManager.default.createDirectory(at: paths.partials, withIntermediateDirectories: true)
        try data.write(to: partial)
        try cas.commit(partialAt: partial, sha256: digest)
        return (digest, try cas.objectURL(for: digest))
    }

    func testMaterializedFileHasDistinctInodeFromCacheObject() throws {
        let (digest, sourceURL) = try seedCommittedObject()
        let materializer = LaunchMaterializer(paths: paths, cas: cas)

        let result = try materializer.materialize(
            assetSetID: "asset-set-1",
            members: [(sha256: digest, declaredName: "game.gba")]
        )

        XCTAssertEqual(result.files.count, 1)
        let materializedURL = result.files[0]

        let sourceInode = try FileManager.default.attributesOfItem(atPath: sourceURL.path)[.systemFileNumber] as? UInt64
        let materializedInode = try FileManager.default.attributesOfItem(atPath: materializedURL.path)[.systemFileNumber] as? UInt64

        XCTAssertNotNil(sourceInode)
        XCTAssertNotNil(materializedInode)
        XCTAssertNotEqual(sourceInode, materializedInode, "materialized file must not be a hard link to the cache object")
    }

    func testWritingToMaterializedFileLeavesSourceObjectDigestUnchanged() throws {
        let (digest, sourceURL) = try seedCommittedObject()
        let materializer = LaunchMaterializer(paths: paths, cas: cas)

        let result = try materializer.materialize(
            assetSetID: "asset-set-2",
            members: [(sha256: digest, declaredName: "game.gba")]
        )
        let materializedURL = result.files[0]

        // Simulate an emulator writing a save/patch into its working copy.
        let handle = try FileHandle(forWritingTo: materializedURL)
        handle.seekToEndOfFile()
        handle.write(Data("SRAM-WRITE-BY-EMULATOR".utf8))
        try handle.close()

        let sourceData = try Data(contentsOf: sourceURL)
        let sourceDigestAfter = sha256Hex(sourceData)
        XCTAssertEqual(sourceDigestAfter, digest, "writing into the materialized copy must not alter the verified cache object")
    }

    func testMaterializeRejectsMissingSourceObject() {
        let materializer = LaunchMaterializer(paths: paths, cas: cas)
        XCTAssertThrowsError(
            try materializer.materialize(assetSetID: "asset-set-3", members: [(sha256: String(repeating: "0", count: 64), declaredName: "missing.gba")])
        ) { error in
            guard case MaterializationError.sourceObjectMissing = error else {
                return XCTFail("expected sourceObjectMissing, got \(error)")
            }
        }
    }

    // MARK: - Preflight: zero network calls

    func testPreflightSucceedsWithEveryNetworkRequestStubbedToFail() throws {
        let (digest, _) = try seedCommittedObject()

        // Installed to prove the preflight path never touches the
        // network: if it did, this stub would fail every request.
        StubURLProtocol.responder = { _ in .init(statusCode: 599, headers: [:], body: Data()) }
        defer { StubURLProtocol.reset() }
        URLProtocol.registerClass(StubURLProtocol.self)
        defer { URLProtocol.unregisterClass(StubURLProtocol.self) }

        let checker = PreflightChecker(cas: cas)
        let result = checker.check(requiredMembers: [(sha256: digest, size: 4096)])

        XCTAssertEqual(result, .ready)
    }

    func testPreflightBlocksOnMissingMember() {
        let checker = PreflightChecker(cas: cas)
        let missingDigest = String(repeating: "a", count: 64)
        let result = checker.check(requiredMembers: [(sha256: missingDigest, size: 100)])

        guard case .blocked(let blockers) = result else {
            return XCTFail("expected .blocked, got \(result)")
        }
        XCTAssertEqual(blockers.first?.sha256, missingDigest)
    }

    func testPreflightFallsBackToRehashAndDetectsCorruption() throws {
        let (digest, sourceURL) = try seedCommittedObject()

        // Corrupt the committed object directly, invalidating the cheap
        // check's stored verify record (size/mtime will no longer match
        // — or even if they coincidentally did, the re-hash catches it).
        try Data("corrupted".utf8).write(to: sourceURL)

        let checker = PreflightChecker(cas: cas)
        let result = checker.check(requiredMembers: [(sha256: digest, size: 4096)])

        guard case .blocked(let blockers) = result else {
            return XCTFail("expected .blocked after corruption, got \(result)")
        }
        XCTAssertEqual(blockers.first?.reason, "corrupted")
    }

    // MARK: - Emulator-authored files survive re-materialization (WINDOWS #78)

    /// The regression gate for WINDOWS #78. mGBA writes save states,
    /// screenshots and cheat files next to the ROM, i.e. inside the
    /// launch directory; the materializer used to delete that whole
    /// directory on every launch, so every Play silently destroyed the
    /// player's save states.
    ///
    /// The sentinel is deliberately a name the members list never
    /// mentions — that is exactly the class of file the old code could
    /// not distinguish from its own leftovers.
    func testMaterializeTwiceLeavesAnEmulatorAuthoredFileUntouched() throws {
        let (digest, _) = try seedCommittedObject()
        let materializer = LaunchMaterializer(paths: paths, cas: cas)
        let members = [(sha256: digest, declaredName: "game.gba")]

        let first = try materializer.materialize(assetSetID: "asset-set-78", members: members)
        let saveState = first.directory.appendingPathComponent("game.ss1")
        let stateBytes = Data("MGBA-SAVE-STATE".utf8)
        try stateBytes.write(to: saveState)

        let second = try materializer.materialize(assetSetID: "asset-set-78", members: members)

        XCTAssertEqual(second.directory, first.directory)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: saveState.path),
            "re-materializing must not delete an emulator-authored file"
        )
        XCTAssertEqual(try Data(contentsOf: saveState), stateBytes, "the save state's bytes must be untouched")
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.files[0].path))
    }

    /// The other half of the same contract: the materializer still owns
    /// cache-derived files, so a member that is no longer part of the
    /// asset set does not linger. Without this, "stop deleting things"
    /// would have been satisfied by deleting nothing at all.
    func testMaterializeRemovesAMemberFileThatIsNoLongerPartOfTheAssetSet() throws {
        let (digestA, _) = try seedCommittedObject(bytes: 4096)
        let (digestB, _) = try seedCommittedObject(bytes: 2048)
        let materializer = LaunchMaterializer(paths: paths, cas: cas)

        let first = try materializer.materialize(
            assetSetID: "asset-set-78b",
            members: [(sha256: digestA, declaredName: "disc1.gba"), (sha256: digestB, declaredName: "patch.ips")]
        )
        let dropped = first.directory.appendingPathComponent("patch.ips")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dropped.path))

        _ = try materializer.materialize(
            assetSetID: "asset-set-78b",
            members: [(sha256: digestA, declaredName: "disc1.gba")]
        )

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: dropped.path),
            "a file this materializer wrote, and no longer owns, must be removed"
        )
    }

    /// A member whose bytes changed must be replaced, not skipped —
    /// `copyItem` refuses an existing destination, so the old copy is
    /// removed explicitly first.
    func testMaterializeReplacesAMemberFileWhoseContentChanged() throws {
        let (digestA, _) = try seedCommittedObject(bytes: 4096)
        let (digestB, _) = try seedCommittedObject(bytes: 2048)
        let materializer = LaunchMaterializer(paths: paths, cas: cas)

        _ = try materializer.materialize(assetSetID: "asset-set-78c", members: [(sha256: digestA, declaredName: "game.gba")])
        let result = try materializer.materialize(assetSetID: "asset-set-78c", members: [(sha256: digestB, declaredName: "game.gba")])

        XCTAssertEqual(try Data(contentsOf: result.files[0]).count, 2048)
    }

    /// A member declaring the manifest's own name is refused: a server
    /// that could overwrite the manifest could name arbitrary files in
    /// the directory for deletion on the next materialization.
    func testMaterializeRejectsAMemberNamedLikeTheManifest() throws {
        let (digest, _) = try seedCommittedObject()
        let materializer = LaunchMaterializer(paths: paths, cas: cas)

        XCTAssertThrowsError(
            try materializer.materialize(
                assetSetID: "asset-set-78d",
                members: [(sha256: digest, declaredName: LaunchMaterializer.manifestFilename)]
            )
        ) { error in
            guard case MaterializationError.reservedMemberName = error else {
                return XCTFail("expected reservedMemberName, got \(error)")
            }
        }
    }

    /// Validation happens before any mutation, so a refused member
    /// leaves a previously materialized directory exactly as it was
    /// rather than half-rebuilt.
    func testARefusedMemberLeavesTheExistingLaunchDirectoryIntact() throws {
        let (digest, _) = try seedCommittedObject()
        let materializer = LaunchMaterializer(paths: paths, cas: cas)

        let first = try materializer.materialize(assetSetID: "asset-set-78e", members: [(sha256: digest, declaredName: "game.gba")])
        let saveState = first.directory.appendingPathComponent("game.ss1")
        try Data("MGBA-SAVE-STATE".utf8).write(to: saveState)

        XCTAssertThrowsError(
            try materializer.materialize(
                assetSetID: "asset-set-78e",
                members: [
                    (sha256: digest, declaredName: "game.gba"),
                    (sha256: String(repeating: "0", count: 64), declaredName: "missing.gba"),
                ]
            )
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: first.files[0].path), "the ROM must still be there")
        XCTAssertTrue(FileManager.default.fileExists(atPath: saveState.path), "the save state must still be there")
    }
}
