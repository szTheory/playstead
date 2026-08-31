import XCTest
import CryptoKit
@testable import Playstead

/// Regression tests for CR-01 and CR-02: server-supplied `name` and
/// `sha256` values must never be able to produce a filesystem path
/// outside the cache root.
///
/// Every test here asserts on the **filesystem outcome** — that nothing
/// was created outside the directory the operation is allowed to write
/// to — not merely that a function refused. A guard that returns an error
/// but has already written the file is not a fix.
///
/// `tempRoot` deliberately contains the `AppPaths` root as a *child*
/// (`tempRoot/cache`), so a successful `../` escape has somewhere
/// observable to land: any artefact appearing directly under `tempRoot`
/// is an escape.
final class PathTraversalTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!
    private var cas: CASManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        paths = AppPaths(root: tempRoot.appendingPathComponent("cache", isDirectory: true))
        cas = CASManager(paths: paths)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try super.tearDownWithError()
    }

    // MARK: - Filesystem-outcome helpers

    /// Every path that currently exists anywhere under `tempRoot`.
    private func filesystemSnapshot() -> Set<String> {
        guard let enumerator = FileManager.default.enumerator(
            at: tempRoot, includingPropertiesForKeys: nil
        ) else { return [] }
        return Set(enumerator.compactMap { ($0 as? URL)?.resolvingSymlinksInPath().standardizedFileURL.path })
    }

    /// Asserts that nothing was created under `tempRoot` outside `allowed`.
    private func assertNothingCreatedOutside(
        _ allowed: URL,
        before: Set<String>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let allowedPrefix = allowed.resolvingSymlinksInPath().standardizedFileURL.path
        let escaped = filesystemSnapshot()
            .subtracting(before)
            .filter { !$0.hasPrefix(allowedPrefix) }
        XCTAssertTrue(
            escaped.isEmpty,
            "content escaped \(allowedPrefix): \(escaped.sorted())",
            file: file, line: line
        )
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Commits a real object into the CAS so materialization has a
    /// legitimate source to copy — the traversal must be blocked by the
    /// *destination*, not incidentally by a missing source.
    @discardableResult
    private func seedCommittedObject() throws -> String {
        let data = Data(repeating: 0xAB, count: 1024)
        let digest = sha256Hex(data)
        try FileManager.default.createDirectory(at: paths.partials, withIntermediateDirectories: true)
        let partial = try paths.partialURL(for: digest)
        try data.write(to: partial)
        try cas.commit(partialAt: partial, sha256: digest)
        return digest
    }

    // MARK: - CR-01: declared member filename

    func testMaterializeRejectsTraversalDeclaredNameAndWritesNothingOutsideLaunchDirectory() throws {
        let digest = try seedCommittedObject()
        let materializer = LaunchMaterializer(paths: paths, cas: cas)
        let before = filesystemSnapshot()

        XCTAssertThrowsError(
            try materializer.materialize(
                assetSetID: "set-1",
                members: [(sha256: digest, declaredName: "../../../../evil.txt")]
            )
        ) { error in
            guard case MaterializationError.unsafeMember(_, let reason) = error else {
                return XCTFail("expected unsafeMember, got \(error)")
            }
            XCTAssertEqual(reason, .unsafeFilename("../../../../evil.txt"))
        }

        // The write must not have happened anywhere — not in tempRoot, not
        // in the user's home, not next to the cache root.
        assertNothingCreatedOutside(paths.launch, before: before)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent("evil.txt").path),
            "traversal target was created"
        )
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(atPath: paths.launchDirectory(forAssetSet: "set-1").path).isEmpty,
            "no member may be materialized when one is unsafe"
        )
    }

    func testMaterializeRejectsDeclaredNameContainingSeparator() throws {
        let digest = try seedCommittedObject()
        let materializer = LaunchMaterializer(paths: paths, cas: cas)
        let before = filesystemSnapshot()

        XCTAssertThrowsError(
            try materializer.materialize(
                assetSetID: "set-2",
                members: [(sha256: digest, declaredName: "nested/evil.txt")]
            )
        )

        assertNothingCreatedOutside(paths.launch, before: before)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: paths.launch.appendingPathComponent("nested").path)
        )
    }

    func testMaterializeRejectsDotAndEmptyDeclaredNames() throws {
        let digest = try seedCommittedObject()
        let materializer = LaunchMaterializer(paths: paths, cas: cas)

        for name in ["", ".", "..", "a/../../b"] {
            XCTAssertThrowsError(
                try materializer.materialize(
                    assetSetID: "set-3",
                    members: [(sha256: digest, declaredName: name)]
                ),
                "declaredName \(name.debugDescription) must be rejected"
            )
        }
    }

    func testMaterializeAcceptsOrdinaryFilename() throws {
        let digest = try seedCommittedObject()
        let materializer = LaunchMaterializer(paths: paths, cas: cas)

        let result = try materializer.materialize(
            assetSetID: "set-4",
            members: [(sha256: digest, declaredName: "Legend of Something (USA).gba")]
        )

        XCTAssertEqual(result.files.count, 1)
        XCTAssertEqual(result.files[0].lastPathComponent, "Legend of Something (USA).gba")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.files[0].path))
    }

    // MARK: - CR-02: server-supplied digest as a path component

    private static let malformedDigests = [
        "../../../../evil",                                 // traversal
        "..",                                               // traversal token
        "a/b",                                              // separator
        "bad-digest",                                       // not hex
        String(repeating: "a", count: 63),                  // too short
        String(repeating: "a", count: 65),                  // too long
        String(repeating: "A", count: 64),                  // uppercase
        String(repeating: "z", count: 64),                  // non-hex letters
        "",                                                 // empty
    ]

    func testObjectAndPartialURLRejectEveryMalformedDigest() {
        for digest in Self.malformedDigests {
            XCTAssertThrowsError(try paths.objectURL(for: digest), "objectURL accepted \(digest.debugDescription)") { error in
                XCTAssertEqual(error as? PathSafetyError, .invalidDigest(digest))
            }
            XCTAssertThrowsError(try paths.partialURL(for: digest), "partialURL accepted \(digest.debugDescription)") { error in
                XCTAssertEqual(error as? PathSafetyError, .invalidDigest(digest))
            }
        }
    }

    func testObjectAndPartialURLAcceptAWellFormedDigest() throws {
        let digest = String(repeating: "0123456789abcdef", count: 4)
        let objectURL = try paths.objectURL(for: digest)
        XCTAssertEqual(
            objectURL.path,
            paths.objects.appendingPathComponent("01/23/\(digest)").path
        )
        XCTAssertEqual(try paths.partialURL(for: digest).path, paths.partials.appendingPathComponent(digest).path)
    }

    func testCommitWithTraversalDigestWritesNothingOutsideObjectsDirectory() throws {
        try FileManager.default.createDirectory(at: paths.partials, withIntermediateDirectories: true)
        let partial = paths.partials.appendingPathComponent("staged.partial")
        try Data("payload-the-server-controls".utf8).write(to: partial)
        let before = filesystemSnapshot()

        XCTAssertThrowsError(
            try cas.commit(partialAt: partial, sha256: "../../../../evil")
        ) { error in
            XCTAssertEqual(error as? PathSafetyError, .invalidDigest("../../../../evil"))
        }

        assertNothingCreatedOutside(paths.root, before: before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent("evil").path))
        // The unverified partial is still where it was — refused, not moved.
        XCTAssertTrue(FileManager.default.fileExists(atPath: partial.path))
    }

    func testCASContainsAndRemoveAreSafeForMalformedDigests() {
        for digest in Self.malformedDigests {
            XCTAssertFalse(cas.contains(digest), "contains() accepted \(digest.debugDescription)")
            XCTAssertThrowsError(try cas.remove(digest), "remove() accepted \(digest.debugDescription)")
        }
    }

    func testPreflightReportsMalformedDigestAsAnExplicitBlocker() {
        let checker = PreflightChecker(cas: cas)
        let result = checker.check(requiredMembers: [(sha256: "../../../../evil", size: 10)])

        guard case .blocked(let blockers) = result else {
            return XCTFail("expected .blocked, got \(result)")
        }
        XCTAssertEqual(blockers.first?.reason, "invalid_digest")
    }

    func testDownloadEngineRefusesAMalformedDigestBeforeTouchingDisk() async throws {
        let engine = DownloadEngine(session: .shared, paths: paths, cas: cas, maxTransportAttempts: 1)
        let before = filesystemSnapshot()

        do {
            try await engine.download(
                sha256: "../../../../evil",
                from: URL(string: "https://example.invalid/blob")!,
                headers: [:]
            )
            XCTFail("download accepted a malformed digest")
        } catch {
            XCTAssertEqual(error as? PathSafetyError, .invalidDigest("../../../../evil"))
        }

        assertNothingCreatedOutside(paths.root, before: before)
    }

    // MARK: - Ingest layer: the value never reaches the cache at all

    private func decodeEntry(memberName: String, memberDigest: String) throws -> CatalogueEntry {
        let json = """
        {
          "id": "set-ingest",
          "system": "gba",
          "display_title": "Hostile",
          "tags": {},
          "members": [
            {"ordinal": 0, "role": "rom", "required": true,
             "sha256": \(escaped(memberDigest)), "size": 1024, "name": \(escaped(memberName))}
          ]
        }
        """
        return try JSONDecoder().decode(CatalogueEntry.self, from: Data(json.utf8))
    }

    private func escaped(_ value: String) -> String {
        String(data: try! JSONEncoder().encode(value), encoding: .utf8)!
    }

    func testDecodingDropsMembersWithATraversalName() throws {
        let validDigest = String(repeating: "ab", count: 32)
        let entry = try decodeEntry(memberName: "../../../../evil.txt", memberDigest: validDigest)
        XCTAssertTrue(entry.members.isEmpty, "a traversal filename must not survive decoding")
        XCTAssertEqual(entry.id, "set-ingest", "the surrounding entry still decodes")
    }

    func testDecodingDropsMembersWithASeparatorInTheName() throws {
        let validDigest = String(repeating: "ab", count: 32)
        let entry = try decodeEntry(memberName: "nested/evil.txt", memberDigest: validDigest)
        XCTAssertTrue(entry.members.isEmpty)
    }

    func testDecodingDropsMembersWithAMalformedDigest() throws {
        for digest in Self.malformedDigests {
            let entry = try decodeEntry(memberName: "game.gba", memberDigest: digest)
            XCTAssertTrue(entry.members.isEmpty, "digest \(digest.debugDescription) survived decoding")
        }
    }

    func testDecodingKeepsWellFormedMembers() throws {
        let validDigest = String(repeating: "ab", count: 32)
        let entry = try decodeEntry(memberName: "game.gba", memberDigest: validDigest)
        XCTAssertEqual(entry.members.count, 1)
        XCTAssertEqual(entry.members[0].name, "game.gba")
        XCTAssertEqual(entry.members[0].sha256, validDigest)
    }

    func testCatalogueStoreDropsUnsafeMembersOnUpsert() throws {
        let localStore = try LocalStore(paths: paths)
        let store = CatalogueStore(localStore: localStore)

        try store.upsert(CatalogueEntry(
            id: "set-store",
            system: "gba",
            displayTitle: "Hostile",
            tags: [:],
            members: [
                AssetMember(ordinal: 0, role: "rom", required: true,
                            sha256: "../../../../evil", size: 10, name: "game.gba"),
                AssetMember(ordinal: 1, role: "rom", required: true,
                            sha256: String(repeating: "ab", count: 32), size: 10, name: "../../evil.txt"),
                AssetMember(ordinal: 2, role: "rom", required: true,
                            sha256: String(repeating: "cd", count: 32), size: 10, name: "ok.gba"),
            ]
        ))

        let stored = store.fetchAll().first { $0.id == "set-store" }
        XCTAssertEqual(stored?.members.map(\.name), ["ok.gba"])
    }

    /// End to end: a hostile catalogue page decoded from server JSON and
    /// persisted cannot produce a launch write outside the launch tree,
    /// because the hostile member never survives ingest.
    func testHostileCatalogueEntryCannotProduceAnOutOfTreeWrite() throws {
        let digest = try seedCommittedObject()
        let localStore = try LocalStore(paths: paths)
        let store = CatalogueStore(localStore: localStore)
        let entry = try decodeEntry(memberName: "../../../../evil.txt", memberDigest: digest)
        try store.upsert(entry)

        let before = filesystemSnapshot()
        let persisted = store.fetchAll().first { $0.id == "set-ingest" }
        let members = (persisted?.members ?? []).compactMap { member -> (sha256: String, declaredName: String)? in
            guard let sha256 = member.sha256, let name = member.name else { return nil }
            return (sha256, name)
        }
        XCTAssertTrue(members.isEmpty, "the hostile member must not have reached the launch path")

        let materializer = LaunchMaterializer(paths: paths, cas: cas)
        _ = try materializer.materialize(assetSetID: "set-ingest", members: members)

        assertNothingCreatedOutside(paths.launch, before: before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent("evil.txt").path))
    }
}
