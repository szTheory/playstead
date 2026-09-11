import XCTest
@testable import Playstead

/// Proves the production BIOS reference set is real, well-formed, and
/// wired all the way through to the digest comparison — closing Gap A
/// from `03-VERIFICATION.md`. Before this task, `PlaysteadApp`'s
/// composition root supplied `BiosStore` an empty reference array, so
/// every real dropped BIOS file was refused for having "no known
/// reference for this system yet" rather than for its actual contents.
final class BiosProductionReferenceTests: XCTestCase {
    // MARK: - The production reference set itself is real and well-formed

    func testProductionReferenceSetIsNonEmptyAndWellFormed() throws {
        let references = BiosReferences.production
        XCTAssertFalse(references.isEmpty)

        guard let gba = references.first(where: { $0.system == "gba" }) else {
            return XCTFail("expected a gba entry in BiosReferences.production")
        }
        XCTAssertGreaterThan(gba.expectedByteLength, 0)
        XCTAssertFalse(gba.knownSHA256Digests.isEmpty)

        let hexPattern = try NSRegularExpression(pattern: "^[0-9a-f]{64}$")
        for digest in gba.knownSHA256Digests {
            let range = NSRange(digest.startIndex..., in: digest)
            XCTAssertNotNil(
                hexPattern.firstMatch(in: digest, range: range),
                "\(digest) is not 64 lowercase hex characters"
            )
        }
    }

    // MARK: - The Swift literals mirror the pin file exactly (parity assertion)

    func testProductionLiteralsMatchThePinFile() throws {
        let pinURL = try Self.resolvePinFileURL()
        let data = try Data(contentsOf: pinURL)
        let pin = try JSONDecoder().decode(BiosPinFixture.self, from: data)

        guard let gba = BiosReferences.production.first(where: { $0.system == pin.system }) else {
            return XCTFail("expected a \(pin.system) entry in BiosReferences.production")
        }

        XCTAssertEqual(gba.expectedByteLength, pin.expectedByteLength)
        XCTAssertEqual(gba.knownSHA256Digests, Set(pin.knownSHA256Digests))
    }

    // MARK: - A store built the way the composition root builds it reaches the digest comparison

    func testStoreBuiltFromProductionReferencesReachesTheDigestComparison() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let managedDirectory = tempRoot.appendingPathComponent("bios", isDirectory: true)
        let paths = AppPaths(root: tempRoot.appendingPathComponent("appsupport", isDirectory: true))
        let localStore = try LocalStore(paths: paths)
        let store = BiosStore(localStore: localStore, managedDirectory: managedDirectory, references: BiosReferences.production)

        guard let gba = BiosReferences.production.first(where: { $0.system == "gba" }) else {
            return XCTFail("expected a gba entry in BiosReferences.production")
        }

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let candidateURL = tempRoot.appendingPathComponent("candidate.bin")
        // A correctly-sized candidate whose contents cannot be the real
        // reference — every byte is 0x00, which is not a valid BIOS.
        try Data(repeating: 0x00, count: gba.expectedByteLength).write(to: candidateURL)

        XCTAssertThrowsError(try store.validateAndAccept(candidateURL: candidateURL, system: "gba")) { error in
            guard case BiosStoreError.invalidCandidate(let reason) = error else {
                return XCTFail("expected invalidCandidate, got \(error)")
            }
            XCTAssertEqual(reason, "this file's contents don't match a known reference")
        }
    }

    // MARK: - Helpers

    private static func resolvePinFileURL() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fm = FileManager.default
        let relativePath = ".planning/phases/03-mac-offline-play-vertical-slice/03-BIOS-PIN.json"
        // Walk up from this test file toward the repository root, which
        // is the ancestor directory that contains `.planning/`.
        while directory.path != "/" {
            let candidate = directory.appendingPathComponent(relativePath)
            if fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(
            domain: "BiosProductionReferenceTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "could not locate 03-BIOS-PIN.json by walking up from #filePath"]
        )
    }
}

/// Decode shape for `03-BIOS-PIN.json`, kept private to this test file —
/// this is a test-only mirror of the pin file's JSON shape, not a
/// production type.
private struct BiosPinFixture: Decodable {
    let system: String
    let expectedByteLength: Int
    let knownSHA256Digests: [String]

    private enum CodingKeys: String, CodingKey {
        case system
        case expectedByteLength = "expected_byte_length"
        case knownSHA256Digests = "known_sha256_digests"
    }
}
