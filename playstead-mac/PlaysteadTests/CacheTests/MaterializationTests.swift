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

        let partial = paths.partialURL(for: digest)
        try FileManager.default.createDirectory(at: paths.partials, withIntermediateDirectories: true)
        try data.write(to: partial)
        try cas.commit(partialAt: partial, sha256: digest)
        return (digest, cas.objectURL(for: digest))
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
}
