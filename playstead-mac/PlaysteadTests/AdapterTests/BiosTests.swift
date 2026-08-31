import XCTest
import CryptoKit
@testable import Playstead

final class BiosTests: XCTestCase {
    private var tempRoot: URL!
    private var managedDirectory: URL!
    private var localStore: LocalStore!
    private var store: BiosStore!

    /// A stand-in "official" reference: 16 bytes long (a nice round
    /// number, not a claim about any real system's real BIOS size), with
    /// exactly one known-good digest — deliberately synthetic, since this
    /// client has no empirically confirmed real reference digest to
    /// embed (see `BiosStore`'s own doc comment).
    private static let referenceLength = 16
    private static let referenceBytes = Data(repeating: 0xAB, count: referenceLength)

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        managedDirectory = tempRoot.appendingPathComponent("bios", isDirectory: true)
        let paths = AppPaths(root: tempRoot.appendingPathComponent("appsupport", isDirectory: true))
        localStore = try LocalStore(paths: paths)
        let reference = BiosStore.Reference(
            system: "gba", expectedByteLength: Self.referenceLength, knownSHA256Digests: [sha256Hex(Self.referenceBytes)]
        )
        store = BiosStore(localStore: localStore, managedDirectory: managedDirectory, references: [reference])
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func writeFile(named name: String, contents: Data) throws -> URL {
        let url = tempRoot.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }

    // MARK: - Accept a genuinely matching candidate

    func testAcceptsMatchingLengthAndDigestAndCopiesIntoManagedStorage() throws {
        let candidate = try writeFile(named: "candidate.bin", contents: Self.referenceBytes)

        let record = try store.validateAndAccept(candidateURL: candidate, system: "gba")

        XCTAssertEqual(record.sha256, sha256Hex(Self.referenceBytes))
        XCTAssertEqual(record.byteLength, Self.referenceLength)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.managedPath(forSHA256: record.sha256).path))
        XCTAssertTrue(store.hasManagedBIOS(forSystem: "gba"))
    }

    // MARK: - Correct length, wrong digest

    func testRejectsCorrectLengthWrongDigestWithoutCopying() throws {
        let wrongContents = Data(repeating: 0xCD, count: Self.referenceLength)
        let candidate = try writeFile(named: "candidate.bin", contents: wrongContents)

        XCTAssertThrowsError(try store.validateAndAccept(candidateURL: candidate, system: "gba")) { error in
            guard case BiosStoreError.invalidCandidate(let reason) = error else {
                return XCTFail("expected invalidCandidate, got \(error)")
            }
            XCTAssertTrue(reason.contains("match"))
        }
        XCTAssertFalse(store.hasManagedBIOS(forSystem: "gba"))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: managedDirectory.path).isEmpty)
    }

    // MARK: - Wrong byte length, rejected before any digest work

    func testRejectsWrongByteLengthBeforeComputingDigest() throws {
        let shortContents = Data(repeating: 0xAB, count: Self.referenceLength - 1)
        let candidate = try writeFile(named: "candidate.bin", contents: shortContents)

        XCTAssertThrowsError(try store.validateAndAccept(candidateURL: candidate, system: "gba")) { error in
            guard case BiosStoreError.invalidCandidate(let reason) = error else {
                return XCTFail("expected invalidCandidate, got \(error)")
            }
            XCTAssertTrue(reason.lowercased().contains("size"))
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: managedDirectory.path).isEmpty)
    }

    // MARK: - Directory / symlink / unreadable rejection

    func testRejectsDirectoryCandidateWithoutTraversal() throws {
        let dirURL = tempRoot.appendingPathComponent("a-directory", isDirectory: true)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(try store.validateAndAccept(candidateURL: dirURL, system: "gba"))
    }

    func testRejectsSymbolicLinkPointingOutsideDropLocationWithoutOpeningTheTarget() throws {
        // The link points at a file that does not exist at all — proving
        // the target is never opened, since opening a nonexistent file
        // would surface as a different, later failure than the
        // symlink-specific rejection this test asserts.
        let linkURL = tempRoot.appendingPathComponent("suspicious-link")
        let nonexistentTarget = tempRoot.appendingPathComponent("does-not-exist-anywhere")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: nonexistentTarget)

        XCTAssertThrowsError(try store.validateAndAccept(candidateURL: linkURL, system: "gba")) { error in
            guard case BiosStoreError.invalidCandidate(let reason) = error else {
                return XCTFail("expected invalidCandidate, got \(error)")
            }
            XCTAssertTrue(reason.contains("symbolic link"))
        }
    }

    // MARK: - Original file is never modified, on acceptance or rejection

    func testOriginalFileDigestAndModificationTimeUnchangedAfterAcceptance() throws {
        let candidate = try writeFile(named: "candidate.bin", contents: Self.referenceBytes)
        let beforeAttrs = try FileManager.default.attributesOfItem(atPath: candidate.path)
        let beforeMTime = beforeAttrs[.modificationDate] as? Date
        let beforeDigest = sha256Hex(try Data(contentsOf: candidate))

        _ = try store.validateAndAccept(candidateURL: candidate, system: "gba")

        let afterAttrs = try FileManager.default.attributesOfItem(atPath: candidate.path)
        let afterMTime = afterAttrs[.modificationDate] as? Date
        let afterDigest = sha256Hex(try Data(contentsOf: candidate))

        XCTAssertEqual(beforeMTime, afterMTime)
        XCTAssertEqual(beforeDigest, afterDigest)
    }

    func testOriginalFileUnchangedAfterRejection() throws {
        let wrongContents = Data(repeating: 0xEE, count: Self.referenceLength)
        let candidate = try writeFile(named: "candidate.bin", contents: wrongContents)
        let beforeDigest = sha256Hex(try Data(contentsOf: candidate))

        _ = try? store.validateAndAccept(candidateURL: candidate, system: "gba")

        let afterDigest = sha256Hex(try Data(contentsOf: candidate))
        XCTAssertEqual(beforeDigest, afterDigest)
    }

    // MARK: - Idempotent repeat accept

    func testDroppingSameAcceptedFileTwiceLeavesOneRowAndOneManagedFile() throws {
        let candidate = try writeFile(named: "candidate.bin", contents: Self.referenceBytes)

        _ = try store.validateAndAccept(candidateURL: candidate, system: "gba")
        _ = try store.validateAndAccept(candidateURL: candidate, system: "gba")

        let rowCount = (try? localStore.connection.query("SELECT COUNT(*) FROM bios_files;") { $0.int(0) ?? 0 })?.first ?? -1
        XCTAssertEqual(rowCount, 1)
        let managedFiles = try FileManager.default.contentsOfDirectory(atPath: managedDirectory.path)
        XCTAssertEqual(managedFiles.count, 1)
    }

    // MARK: - Managed filename derived from digest, never the dropped filename

    func testManagedFilenameIsDerivedFromDigestNotDroppedFilename() throws {
        let candidate = try writeFile(named: "totally-unrelated-name.xyz", contents: Self.referenceBytes)
        let record = try store.validateAndAccept(candidateURL: candidate, system: "gba")

        XCTAssertEqual(record.managedFilename, sha256Hex(Self.referenceBytes))
        XCTAssertNotEqual(record.managedFilename, "totally-unrelated-name.xyz")
    }

    // MARK: - Removing a managed BIOS never touches the original

    func testRemovingManagedBiosLeavesOriginalFilePresent() throws {
        let candidate = try writeFile(named: "candidate.bin", contents: Self.referenceBytes)
        let record = try store.validateAndAccept(candidateURL: candidate, system: "gba")

        try store.remove(sha256: record.sha256)

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.managedPath(forSHA256: record.sha256).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: candidate.path))
        XCTAssertFalse(store.hasManagedBIOS(forSystem: "gba"))
    }

    // MARK: - BiosDropTarget wraps the store for a plain dropped URL

    func testBiosDropTargetAcceptsAMatchingDroppedFile() throws {
        let candidate = try writeFile(named: "candidate.bin", contents: Self.referenceBytes)
        let target = BiosDropTarget(store: store, system: "gba")

        let result = target.handle(droppedFileURL: candidate)

        guard case .accepted(let record) = result else {
            return XCTFail("expected .accepted, got \(result)")
        }
        XCTAssertEqual(record.sha256, sha256Hex(Self.referenceBytes))
    }

    func testBiosDropTargetRejectsANonMatchingDroppedFileWithAReason() throws {
        let wrongContents = Data(repeating: 0x11, count: Self.referenceLength)
        let candidate = try writeFile(named: "candidate.bin", contents: wrongContents)
        let target = BiosDropTarget(store: store, system: "gba")

        let result = target.handle(droppedFileURL: candidate)

        guard case .rejected(let reason) = result else {
            return XCTFail("expected .rejected, got \(result)")
        }
        XCTAssertFalse(reason.isEmpty)
    }

    // MARK: - Capability card fidelity caveat

    func testCapabilityCardStatesFidelityCaveatWhenNoBiosIsPresent() throws {
        let pin = try JSONDecoder().decode(AdapterPin.self, from: Data(Self.pinJSON.utf8))
        let catalog = AdapterCatalog(pin: pin)
        let card = AdapterCapabilityCard(descriptor: catalog.descriptor, installState: .notInstalled, biosStore: store)

        XCTAssertFalse(store.hasManagedBIOS(forSystem: "gba"))
        XCTAssertTrue(card.renderedText.lowercased().contains("fidelity"))
    }

    func testCapabilityCardOmitsFidelityCaveatOnceABiosIsValidated() throws {
        let candidate = try writeFile(named: "candidate.bin", contents: Self.referenceBytes)
        _ = try store.validateAndAccept(candidateURL: candidate, system: "gba")

        let pin = try JSONDecoder().decode(AdapterPin.self, from: Data(Self.pinJSON.utf8))
        let catalog = AdapterCatalog(pin: pin)
        let card = AdapterCapabilityCard(descriptor: catalog.descriptor, installState: .notInstalled, biosStore: store)

        XCTAssertTrue(card.hasManagedBIOS)
        XCTAssertFalse(card.biosPostureText.lowercased().contains("fidelity may differ"))
    }

    // MARK: - No acquisition path anywhere (mirrors this task's own acceptance-criteria grep)

    func testBiosSourceFilesProvideNoAcquisitionPath() throws {
        let pattern = try NSRegularExpression(
            pattern: #"https?://|download|obtain|where to (get|find)|dump"#,
            options: [.caseInsensitive]
        )
        for path in adapterSourcePaths(named: ["BiosStore.swift", "BiosDropTarget.swift"]) {
            let source = try String(contentsOfFile: path, encoding: .utf8)
            let matches = pattern.matches(in: source, range: NSRange(source.startIndex..., in: source))
            XCTAssertTrue(matches.isEmpty, "\(path) must resolve a BIOS to no source or acquisition hint")
        }
    }

    // MARK: - Helpers

    private static let pinJSON = """
    {
      "system": "gba",
      "emulator": "mgba",
      "version": "0.10.5",
      "download_url": "https://example.invalid/archive.dmg",
      "sha256": "a435f6806bfd6c55ab979fd306a74ee2edf49308e7137a1527931249c43d31e0",
      "launch": {
        "executable_relative_path": "Contents/MacOS/mGBA",
        "argument_template": ["-C", "savegamePath={saveDir}", "{romPath}"]
      },
      "config_injection": {
        "mechanism": "cli_config_override",
        "keys": {"save_directory": "-C savegamePath={path}", "bios_path": "-b {path}", "controller_mapping": "not_probed_no_hardware_available"}
      },
      "save_contract": {
        "artifact_glob": "{saveDir}/{romBaseName}.sav",
        "directory_key": "savegamePath",
        "flush_triggers": ["periodic_during_play_observed_every_24s"],
        "on_demand_flush_supported": false,
        "worst_case_loss_seconds": 24
      },
      "exit_detection": {
        "clean": {"terminationStatus": 15, "terminationReason": "uncaughtSignal"},
        "crash": {"terminationStatus": 11, "terminationReason": "uncaughtSignal"},
        "killed": {"terminationStatus": 9, "terminationReason": "uncaughtSignal"}
      }
    }
    """

    private func adapterSourcePaths(named names: [String]) -> [String] {
        let thisFile = URL(fileURLWithPath: #filePath)
        let playsteadMacRoot = thisFile
            .deletingLastPathComponent() // BiosTests.swift -> AdapterTests/
            .deletingLastPathComponent() // AdapterTests/ -> PlaysteadTests/
            .deletingLastPathComponent() // PlaysteadTests/ -> playstead-mac/
        let adapterDir = playsteadMacRoot.appendingPathComponent("Playstead/Adapter")
        return names.map { adapterDir.appendingPathComponent($0).path }
    }
}
