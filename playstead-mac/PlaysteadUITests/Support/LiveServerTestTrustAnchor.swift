import XCTest
import CryptoKit
import Security

/// Copies the LiveServer runner's public CA into a private per-test profile
/// so a prepaired test client can exercise the same pinned-TLS path as a user.
/// The test process never changes System Keychain trust.
struct LiveServerTestTrustAnchor {
    let fileURL: URL
    let sha256: String

    init(sourcePath: String, expectedSHA256: String, runRoot: URL) throws {
        let source = URL(fileURLWithPath: sourcePath)
        let sourceAttributes = try FileManager.default.attributesOfItem(atPath: source.path)
        guard (sourceAttributes[.type] as? FileAttributeType) == .typeRegular,
              let sourceSize = (sourceAttributes[.size] as? NSNumber)?.intValue,
              sourceSize > 0, sourceSize <= 16_384 else {
            throw LiveServerTestTrustAnchorError.invalidSource
        }
        let bytes = try Data(contentsOf: source, options: [.mappedIfSafe])
        guard bytes.count == sourceSize,
              SecCertificateCreateWithData(nil, bytes as CFData) != nil else {
            throw LiveServerTestTrustAnchorError.invalidCertificate
        }
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard expectedSHA256.count == 64,
              expectedSHA256.allSatisfy({ $0.isHexDigit }),
              digest == expectedSHA256.lowercased() else {
            throw LiveServerTestTrustAnchorError.digestMismatch
        }

        let destination = runRoot.appendingPathComponent("live-server-ca.der")
        try bytes.write(to: destination, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        self.fileURL = destination
        self.sha256 = digest
    }

    @MainActor
    func install(on app: XCUIApplication) {
        app.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_SERVER_CA_DER"] = fileURL.path
        app.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_SERVER_CA_SHA256"] = sha256
        app.launchEnvironment["PLAYSTEAD_UI_TEST_LIVE_SERVER_PAIRING_TARGET"] = "https://127.0.0.1:4010"
    }
}

private enum LiveServerTestTrustAnchorError: Error {
    case invalidSource
    case invalidCertificate
    case digestMismatch
}
