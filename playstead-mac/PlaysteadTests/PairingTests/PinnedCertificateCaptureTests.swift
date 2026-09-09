import XCTest
@testable import Playstead

/// Covers plan 04.5-02 task 2: `PinnedCertificateCapture.writeCapturedCertificate(to:)`
/// exercised directly — no `PairingCoordinator`, no network, no Keychain —
/// so the capture's own honesty (returns exactly what landed on disk) is
/// falsifiable in isolation from the ceremony that gates on it.
final class PinnedCertificateCaptureTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
        try super.tearDownWithError()
    }

    func testWritingACapturedAnchorLandsTheExactBytesWith0600Permissions() throws {
        let bytes = Data("der-anchor-bytes".utf8)
        let capture = PinnedCertificateCapture(capturedCertificateData: bytes)
        let destination = tempRoot.appendingPathComponent("pinned-ca.der")

        let wrote = capture.writeCapturedCertificate(to: destination)

        XCTAssertTrue(wrote)
        XCTAssertEqual(try Data(contentsOf: destination), bytes)
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testWritingWithNothingCapturedReportsFalseAndLeavesNoFile() {
        let capture = PinnedCertificateCapture(capturedCertificateData: nil)
        let destination = tempRoot.appendingPathComponent("pinned-ca.der")

        let wrote = capture.writeCapturedCertificate(to: destination)

        XCTAssertFalse(wrote)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testWritingIntoAMissingDirectoryReportsFalseRatherThanThrowing() {
        let bytes = Data("der-anchor-bytes".utf8)
        let capture = PinnedCertificateCapture(capturedCertificateData: bytes)
        let destination = tempRoot.appendingPathComponent("does-not-exist").appendingPathComponent("pinned-ca.der")

        let wrote = capture.writeCapturedCertificate(to: destination)

        XCTAssertFalse(wrote)
    }
}
