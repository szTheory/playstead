import XCTest
import Security
@testable import Playstead

/// Proves `PinningDelegate.disposition(for:)` actually diverges from
/// default platform trust — the test the CI transport cannot fake,
/// because the CI harness's own CA is separately installed as a
/// System-trusted root (`mac-ci-tls.sh`), so any transport-level check
/// would pass identically whether or not pinning is wired.
///
/// No case in this file routes through `URLSession`, `URLProtectionSpace`,
/// or any network transport. Every fixture is generated locally via
/// `/usr/bin/openssl` and evaluated directly against `SecTrust`.
final class PinnedTrustEvaluationTests: XCTestCase {
    private var tempRoot: URL!

    private var caADER: Data!
    private var caBDER: Data!
    private var leafCert: SecCertificate!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        // CA-A: self-signed root.
        try run(
            "req", "-x509", "-newkey", "rsa:2048", "-sha256", "-days", "397", "-nodes",
            "-keyout", path("caA-key.pem"), "-out", path("caA.pem"),
            "-subj", "/CN=Pinned Trust Test CA"
        )
        // CA-B: an independent key with the identical subject DN as CA-A,
        // so the mismatched-anchor case is sensitive to certificate bytes,
        // not the certificate's name.
        try run(
            "req", "-x509", "-newkey", "rsa:2048", "-sha256", "-days", "397", "-nodes",
            "-keyout", path("caB-key.pem"), "-out", path("caB.pem"),
            "-subj", "/CN=Pinned Trust Test CA"
        )
        // One leaf issued by CA-A.
        try run(
            "req", "-new", "-newkey", "rsa:2048", "-nodes",
            "-keyout", path("leaf-key.pem"), "-out", path("leaf.csr"),
            "-subj", "/CN=127.0.0.1"
        )
        try run(
            "x509", "-req", "-in", path("leaf.csr"),
            "-CA", path("caA.pem"), "-CAkey", path("caA-key.pem"), "-CAcreateserial",
            "-days", "397", "-sha256", "-out", path("leaf.pem")
        )

        try run("x509", "-in", path("caA.pem"), "-outform", "DER", "-out", path("caA.der"))
        try run("x509", "-in", path("caB.pem"), "-outform", "DER", "-out", path("caB.der"))
        try run("x509", "-in", path("leaf.pem"), "-outform", "DER", "-out", path("leaf.der"))

        caADER = try Data(contentsOf: URL(fileURLWithPath: path("caA.der")))
        caBDER = try Data(contentsOf: URL(fileURLWithPath: path("caB.der")))
        let leafDER = try Data(contentsOf: URL(fileURLWithPath: path("leaf.der")))
        guard let leafCert = SecCertificateCreateWithData(nil, leafDER as CFData) else {
            XCTFail("fixture generation produced a leaf certificate SecCertificateCreateWithData could not parse")
            return
        }
        self.leafCert = leafCert
    }

    override func tearDownWithError() throws {
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
        try super.tearDownWithError()
    }

    // MARK: - Fixture plumbing

    private func path(_ name: String) -> String {
        tempRoot.appendingPathComponent(name).path
    }

    private struct FixtureGenerationFailure: Error {}

    /// Invokes `/usr/bin/openssl` directly via `Process`. Never skips on
    /// failure — a skipped run of this test is indistinguishable from the
    /// pinning gap it exists to detect. A failure calls `XCTFail` with the
    /// captured stderr and then throws a plain error so the caller (`setUp`)
    /// stops rather than continuing to operate on missing fixture files.
    private func run(_ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: stderrData, encoding: .utf8) ?? "<no stderr>"
            XCTFail("openssl \(arguments.joined(separator: " ")) exited \(process.terminationStatus): \(stderrText)")
            throw FixtureGenerationFailure()
        }
    }

    /// A fresh `SecTrust` over the leaf alone, built with
    /// `SecPolicyCreateBasicX509()` so the assertion is about anchor
    /// identity rather than hostname matching. Built fresh per case:
    /// `SecTrustSetAnchorCertificates` mutates the trust object.
    private func makeLeafTrust() throws -> SecTrust {
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(leafCert, SecPolicyCreateBasicX509(), &trust)
        guard status == errSecSuccess, let trust else {
            XCTFail("SecTrustCreateWithCertificates failed with status \(status)")
            throw FixtureGenerationFailure()
        }
        return trust
    }

    /// Writes `bytes` (or nothing, for the absent case) to a
    /// `pinned-ca.der` file in a fresh subdirectory and constructs a
    /// `PinningDelegate` pinned at that URL.
    private func makeDelegate(pinnedBytes: Data?) throws -> PinningDelegate {
        let dir = tempRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pinnedURL = dir.appendingPathComponent("pinned-ca.der")
        if let pinnedBytes {
            try pinnedBytes.write(to: pinnedURL)
        }
        return PinningDelegate(pinnedCertificateURL: pinnedBytes == nil ? nonExistentURL(in: dir) : pinnedURL)
    }

    private func nonExistentURL(in dir: URL) -> URL {
        dir.appendingPathComponent("pinned-ca.der")
    }

    // MARK: - Divergence

    func testMatchingAnchorIsAccepted() throws {
        let delegate = try makeDelegate(pinnedBytes: caADER)
        XCTAssertEqual(delegate.disposition(for: try makeLeafTrust()), .useCredential)
    }

    func testDifferentCAWithTheSameSubjectIsRejected() throws {
        XCTAssertNotEqual(caADER, caBDER, "fixture generation must produce two distinct certificates, not the same one twice")

        let delegate = try makeDelegate(pinnedBytes: caBDER)
        XCTAssertEqual(delegate.disposition(for: try makeLeafTrust()), .cancelAuthenticationChallenge)
    }

    func testAbsentPinnedCertificateFallsBackToDefaultHandling() throws {
        let delegate = try makeDelegate(pinnedBytes: nil)
        XCTAssertEqual(delegate.disposition(for: try makeLeafTrust()), .performDefaultHandling)

        let nilURLDelegate = PinningDelegate(pinnedCertificateURL: nil)
        XCTAssertEqual(nilURLDelegate.disposition(for: try makeLeafTrust()), .performDefaultHandling)
    }

    func testEmptyAndUnparseablePinnedCertificateFallBackToDefaultHandling() throws {
        let emptyDelegate = try makeDelegate(pinnedBytes: Data())
        XCTAssertEqual(emptyDelegate.disposition(for: try makeLeafTrust()), .performDefaultHandling)

        let garbageDelegate = try makeDelegate(pinnedBytes: Data("not a certificate".utf8))
        XCTAssertEqual(garbageDelegate.disposition(for: try makeLeafTrust()), .performDefaultHandling)
    }

    func testDecisionIsStatelessAcrossRepeatedEvaluations() throws {
        let mismatchedDelegate = try makeDelegate(pinnedBytes: caBDER)
        XCTAssertEqual(mismatchedDelegate.disposition(for: try makeLeafTrust()), .cancelAuthenticationChallenge)

        let matchingDelegate = try makeDelegate(pinnedBytes: caADER)
        XCTAssertEqual(
            matchingDelegate.disposition(for: try makeLeafTrust()),
            .useCredential,
            "the matching case must return .useCredential again immediately after the mismatched case -- the decision carries no state between calls"
        )
    }
}
