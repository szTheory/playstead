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
    /// A second, distinct valid reference pattern — used only by the
    /// concurrency tests, which need two genuinely different accepted
    /// digests to prove distinct concurrent drops don't interfere.
    private static let referenceBytesAlt = Data(repeating: 0xCC, count: referenceLength)

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        managedDirectory = tempRoot.appendingPathComponent("bios", isDirectory: true)
        let paths = AppPaths(root: tempRoot.appendingPathComponent("appsupport", isDirectory: true))
        localStore = try LocalStore(paths: paths)
        let reference = BiosStore.Reference(
            system: "gba",
            expectedByteLength: Self.referenceLength,
            knownSHA256Digests: [sha256Hex(Self.referenceBytes), sha256Hex(Self.referenceBytesAlt)]
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

    // MARK: - Discriminator guard: empty reference set vs. a real, non-matching one

    func testEmptyReferenceSetRejectsWithTheNoKnownReferenceReason() throws {
        let emptyStore = BiosStore(localStore: localStore, managedDirectory: managedDirectory, references: [])
        let candidate = try writeFile(named: "candidate.bin", contents: Self.referenceBytes)

        XCTAssertThrowsError(try emptyStore.validateAndAccept(candidateURL: candidate, system: "gba")) { error in
            guard case BiosStoreError.invalidCandidate(let reason) = error else {
                return XCTFail("expected invalidCandidate, got \(error)")
            }
            XCTAssertEqual(reason, "no known reference for this system yet")
        }
    }

    // MARK: - Wrong length is rejected before any digest comparison, naming both lengths

    func testWrongLengthCandidateIsRejectedBeforeAnyDigestComparison() throws {
        let shortContents = Data(repeating: 0xAB, count: Self.referenceLength - 1)
        let candidate = try writeFile(named: "candidate.bin", contents: shortContents)

        XCTAssertThrowsError(try store.validateAndAccept(candidateURL: candidate, system: "gba")) { error in
            guard case BiosStoreError.invalidCandidate(let reason) = error else {
                return XCTFail("expected invalidCandidate, got \(error)")
            }
            XCTAssertEqual(
                reason,
                "wrong size (expected \(Self.referenceLength) bytes, got \(Self.referenceLength - 1))"
            )
        }
    }

    // MARK: - A symlink to a valid candidate, and a directory, are both refused with their own reasons

    func testSymbolicLinkAndDirectoryAreBothRefused() throws {
        let validCandidate = try writeFile(named: "valid-candidate.bin", contents: Self.referenceBytes)
        let linkURL = tempRoot.appendingPathComponent("link-to-valid-candidate")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: validCandidate)

        XCTAssertThrowsError(try store.validateAndAccept(candidateURL: linkURL, system: "gba")) { error in
            guard case BiosStoreError.invalidCandidate(let reason) = error else {
                return XCTFail("expected invalidCandidate, got \(error)")
            }
            XCTAssertEqual(reason, "symbolic links are not accepted")
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: managedDirectory.path).isEmpty)

        let dirURL = tempRoot.appendingPathComponent("a-refused-directory", isDirectory: true)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(try store.validateAndAccept(candidateURL: dirURL, system: "gba")) { error in
            guard case BiosStoreError.invalidCandidate(let reason) = error else {
                return XCTFail("expected invalidCandidate, got \(error)")
            }
            XCTAssertEqual(reason, "only a single regular file is accepted")
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: managedDirectory.path).isEmpty)
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

    // MARK: - Concurrency: identical accepted bytes converge on one file and one row

    func testConcurrentIdenticalDropsYieldOneManagedFileAndOneRow() throws {
        let candidateA = try writeFile(named: "candidate-a.bin", contents: Self.referenceBytes)
        let candidateB = try writeFile(named: "candidate-b.bin", contents: Self.referenceBytes)
        let candidates = [candidateA, candidateB]

        var thrownErrors: [Error] = []
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            do {
                _ = try store.validateAndAccept(candidateURL: candidates[index], system: "gba")
            } catch {
                lock.lock()
                thrownErrors.append(error)
                lock.unlock()
            }
        }

        XCTAssertTrue(thrownErrors.isEmpty, "expected both concurrent identical drops to succeed, got \(thrownErrors)")
        let managedFiles = try FileManager.default.contentsOfDirectory(atPath: managedDirectory.path)
        XCTAssertEqual(managedFiles.count, 1)
        let rowCount = (try? localStore.connection.query("SELECT COUNT(*) FROM bios_files;") { $0.int(0) ?? 0 })?.first ?? -1
        XCTAssertEqual(rowCount, 1)
    }

    // MARK: - Concurrency: distinct accepted candidates don't interfere

    func testConcurrentDistinctDropsBothSucceed() throws {
        let candidateA = try writeFile(named: "candidate-a.bin", contents: Self.referenceBytes)
        let candidateB = try writeFile(named: "candidate-b.bin", contents: Self.referenceBytesAlt)
        let candidates = [candidateA, candidateB]

        var thrownErrors: [Error] = []
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            do {
                _ = try store.validateAndAccept(candidateURL: candidates[index], system: "gba")
            } catch {
                lock.lock()
                thrownErrors.append(error)
                lock.unlock()
            }
        }

        XCTAssertTrue(thrownErrors.isEmpty, "expected both concurrent distinct drops to succeed, got \(thrownErrors)")
        let managedFiles = try FileManager.default.contentsOfDirectory(atPath: managedDirectory.path)
        XCTAssertEqual(Set(managedFiles), [sha256Hex(Self.referenceBytes), sha256Hex(Self.referenceBytesAlt)])
        let rowCount = (try? localStore.connection.query("SELECT COUNT(*) FROM bios_files;") { $0.int(0) ?? 0 })?.first ?? -1
        XCTAssertEqual(rowCount, 2)
    }

    // MARK: - A stale incoming temp file is swept on the next init; managed files survive

    func testStaleIncomingTempIsSweptOnNextInitAndManagedFilesSurvive() throws {
        // Plant a leftover temp file (as if a previous run was
        // interrupted mid-`validateAndAccept`) and a genuine managed
        // (64-hex-named) file directly in the managed directory.
        let staleTempName = ".incoming-\(UUID().uuidString)"
        let staleTempURL = managedDirectory.appendingPathComponent(staleTempName)
        try Data("stale-partial-write".utf8).write(to: staleTempURL)

        let managedDigest = sha256Hex(Self.referenceBytes)
        let managedURL = managedDirectory.appendingPathComponent(managedDigest)
        try Self.referenceBytes.write(to: managedURL)

        // Constructing a new BiosStore over the same managed directory
        // runs the init-time sweep.
        _ = BiosStore(localStore: localStore, managedDirectory: managedDirectory, references: [])

        let remaining = try FileManager.default.contentsOfDirectory(atPath: managedDirectory.path)
        XCTAssertFalse(remaining.contains(staleTempName), "stale incoming temp file should have been swept")
        XCTAssertTrue(remaining.contains(managedDigest), "the managed file must survive the sweep")
    }

    // MARK: - A rejected candidate leaves the managed directory byte-identical to before

    func testRejectedCandidateLeavesManagedDirectoryUnchanged() throws {
        // Seed one genuinely accepted file so the "before" snapshot is
        // non-empty, making an accidental sweep or deletion observable.
        let accepted = try writeFile(named: "accepted.bin", contents: Self.referenceBytes)
        _ = try store.validateAndAccept(candidateURL: accepted, system: "gba")
        let before = try FileManager.default.contentsOfDirectory(atPath: managedDirectory.path).sorted()

        let wrongContents = Data(repeating: 0xEF, count: Self.referenceLength)
        let rejectedCandidate = try writeFile(named: "rejected.bin", contents: wrongContents)
        XCTAssertThrowsError(try store.validateAndAccept(candidateURL: rejectedCandidate, system: "gba"))

        let after = try FileManager.default.contentsOfDirectory(atPath: managedDirectory.path).sorted()
        XCTAssertEqual(before, after)
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

    // MARK: - 03-UAT.md checkpoint 45: the reason the surface renders is
    // the store's own, verbatim — never a generic failure string.
    //
    // `testBiosDropTargetRejectsANonMatchingDroppedFileWithAReason` only
    // asserts the reason is non-empty, which the generic fallback also
    // satisfies. These pin the exact copy, one store error per line, and
    // anchor the literal `BiosRejectionCopyTests` mirrors in the UI-test
    // target (which cannot link these types).

    func testRejectionMessageQuotesTheStoreReasonVerbatim() throws {
        let gba = BiosDropTarget(store: store, system: "gba")

        let wrongContents = try writeFile(
            named: "wrong-contents.bin", contents: Data(repeating: 0x11, count: Self.referenceLength)
        )
        XCTAssertEqual(
            reason(from: gba.handle(droppedFileURL: wrongContents)),
            "This file could not be validated — this file's contents don't match a known reference."
        )

        let wrongSize = try writeFile(named: "wrong-size.bin", contents: Data(repeating: 0x11, count: 3))
        XCTAssertEqual(
            reason(from: gba.handle(droppedFileURL: wrongSize)),
            "This file could not be validated — wrong size (expected \(Self.referenceLength) bytes, got 3)."
        )

        // The literal `BiosRejectionCopyTests` drives the real surface to,
        // via the deterministic profiles' `synthetic-system`.
        let unknownSystem = BiosDropTarget(store: store, system: "synthetic-system")
        let anyFile = try writeFile(named: "any.bin", contents: Data(repeating: 0x5A, count: 2048))
        XCTAssertEqual(
            reason(from: unknownSystem.handle(droppedFileURL: anyFile)),
            "This file could not be validated — no known reference for this system yet."
        )
    }

    func testEveryRejectionIsDistinguishableAndNoneIsTheGenericFallback() throws {
        let gba = BiosDropTarget(store: store, system: "gba")
        let generic = "This file could not be validated."

        let candidates = [
            try writeFile(named: "d1.bin", contents: Data(repeating: 0x11, count: Self.referenceLength)),
            try writeFile(named: "d2.bin", contents: Data(repeating: 0x11, count: 3)),
            try writeFile(named: "d3.bin", contents: Data())
        ]

        let reasons = candidates.map { reason(from: gba.handle(droppedFileURL: $0)) }

        XCTAssertFalse(reasons.contains(generic), "a store error fell through to the generic fallback")
        XCTAssertFalse(reasons.contains(where: \.isEmpty))
        XCTAssertEqual(Set(reasons).count, reasons.count, "two distinct failures rendered identical copy")
    }

    private func reason(from result: BiosDropResult) -> String {
        guard case .rejected(let reason) = result else {
            XCTFail("expected .rejected, got \(result)")
            return ""
        }
        return reason
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

    /// UAT item 13 says no acquisition path is offered anywhere in *the UI*.
    /// The grep above proves that for two files. Eight shipped files carry
    /// user-facing BIOS copy, and the six it never looked at include
    /// `ReadinessEngine.swift`, whose remedy text ("Drop in a BIOS file") is
    /// the single most tempting place to add "...you can get one here" — so
    /// the claim was broad and the proof was narrow.
    ///
    /// This sweeps every shipped Swift file. It reads string literals rather
    /// than raw source because that is what the requirement is actually
    /// about: `BiosReferences.swift` cites three URLs in a doc comment as
    /// provenance for the pinned digest, which is scholarship, not an offer,
    /// and a raw-source grep cannot tell the two apart.
    func testNoShippedBiosCopyAnywhereOffersAnAcquisitionPath() throws {
        let acquisition = try NSRegularExpression(
            pattern: #"https?://|\bdownload\b|\bobtain\b|where to (get|find)|\bdump\b|torrent|\bacquire\b"#,
            options: [.caseInsensitive]
        )

        var offending: [String] = []
        var biosLiteralCount = 0
        var filesWithBiosCopy: Set<String> = []

        for url in try shippedSwiftSources() {
            let source = try String(contentsOf: url, encoding: .utf8)
            for literal in stringLiterals(in: source) {
                guard literal.range(of: "bios", options: .caseInsensitive) != nil else { continue }
                biosLiteralCount += 1
                filesWithBiosCopy.insert(url.lastPathComponent)
                let range = NSRange(literal.startIndex..., in: literal)
                if acquisition.firstMatch(in: literal, range: range) != nil {
                    offending.append("\(url.lastPathComponent): \(literal)")
                }
            }
        }

        // Each clause on its own line: CI keeps file:line, not assertion text.
        XCTAssertEqual(offending, [], "shipped BIOS copy offers an acquisition path")

        // Non-vacuity. A sweep that silently stops finding anything -- a
        // refactor into resources, a renamed directory, a broken literal
        // scanner -- would otherwise pass while proving nothing at all.
        XCTAssertGreaterThanOrEqual(biosLiteralCount, 20, "the literal sweep found almost nothing; it is no longer reading shipped copy")
        XCTAssertTrue(filesWithBiosCopy.contains("ReadinessEngine.swift"), "the remedy copy is no longer being swept")
        XCTAssertTrue(filesWithBiosCopy.contains("AdapterCapabilityCard.swift"), "the capability-card copy is no longer being swept")
        XCTAssertTrue(filesWithBiosCopy.contains("BiosDropTarget.swift"), "the drop-surface copy is no longer being swept")
    }

    // MARK: - Helpers

    /// Every shipped Swift file. `Playstead/` only: test targets are not
    /// shipped, and UI copy never lives there.
    private func shippedSwiftSources() throws -> [URL] {
        let root = playsteadMacRoot().appendingPathComponent("Playstead", isDirectory: true)
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            throw XCTSkip("could not walk \(root.path)")
        }
        var found: [URL] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            found.append(url)
        }
        XCTAssertGreaterThan(found.count, 40, "walked \(root.path) and found almost no Swift files")
        return found.sorted { $0.path < $1.path }
    }

    /// String literals, with comment lines removed first so a doc-comment
    /// citation is not mistaken for user-facing copy.
    private func stringLiterals(in source: String) -> [String] {
        let code = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        guard let literal = try? NSRegularExpression(pattern: #""((?:[^"\\\n]|\\.)*)""#) else { return [] }
        let range = NSRange(code.startIndex..., in: code)
        return literal.matches(in: code, range: range).compactMap { match in
            Range(match.range(at: 1), in: code).map { String(code[$0]) }
        }
    }

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

    private func playsteadMacRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // BiosTests.swift -> AdapterTests/
            .deletingLastPathComponent() // AdapterTests/ -> PlaysteadTests/
            .deletingLastPathComponent() // PlaysteadTests/ -> playstead-mac/
    }

    private func adapterSourcePaths(named names: [String]) -> [String] {
        let adapterDir = playsteadMacRoot().appendingPathComponent("Playstead/Adapter")
        return names.map { adapterDir.appendingPathComponent($0).path }
    }
}
