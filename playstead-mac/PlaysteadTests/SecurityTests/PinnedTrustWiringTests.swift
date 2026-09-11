import XCTest
import Security
@testable import Playstead

/// Closes the gap `04.5-VERIFICATION.md` found: `PairingCoordinator.redeem()`
/// writes the pairing-time trust anchor to `AppPaths.root/pinned-ca.der`,
/// but until plan 04.5-06 no `APIClient` construction site ever read it
/// back, so `PinningDelegate` fell through to default platform trust on
/// every request forever. These tests assert the write target and the
/// request-client read target are the *same URL*, by live-object equality
/// against the real production composition root — not by reading a
/// comment or a source string.
@MainActor
final class PinnedTrustWiringTests: XCTestCase {
    private var tempRoot: URL!
    private var keychainPath: URL!
    private var scopedKeychain: SecKeychain?
    private var store: KeychainStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        keychainPath = tempRoot.appendingPathComponent("scoped.keychain-db")
        let password = Data("pinned-trust-wiring-test-\(UUID().uuidString)".utf8)
        var created: SecKeychain?
        let status = keychainPath.path.withCString { path in
            password.withUnsafeBytes { bytes in
                SecKeychainCreate(path, UInt32(password.count), bytes.baseAddress, false, nil, &created)
            }
        }
        XCTAssertEqual(status, errSecSuccess)
        scopedKeychain = created
        store = try KeychainStore.uiTestingStore(
            service: "dev.playstead.mac.test.\(UUID().uuidString.lowercased())", fileURL: keychainPath
        )
    }

    override func tearDownWithError() throws {
        if let scopedKeychain { SecKeychainDelete(scopedKeychain) }
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
        try super.tearDownWithError()
    }

    /// The production composition root's `APIClient` must carry the exact
    /// URL `PairingCoordinator` writes on a successful redeem — not `nil`,
    /// not some other path.
    func testProductionEnvironmentGivesItsAPIClientThePairingWriteTarget() throws {
        let paths = AppPaths(root: tempRoot.appendingPathComponent("app-support", isDirectory: true))
        let environment = AppEnvironment(paths: paths, pairingKeychain: store)

        let pinnedURL = environment.apiClient?.pinnedCertificateURL
        XCTAssertNotNil(pinnedURL, "the production APIClient must carry a non-nil pinned-certificate URL")
        XCTAssertEqual(pinnedURL, paths.pinnedCertificate)
        XCTAssertTrue(
            pinnedURL?.path.hasPrefix(paths.root.path) ?? false,
            "the pinned URL must live under the scoped temp root, never the real Application Support directory"
        )
    }

    /// The key link the prior verification found broken: the write target
    /// `PairingCoordinator` uses and the read target `APIClient` uses must
    /// be the same URL, compared as live objects on the same environment
    /// instance — not two independently-constructed paths that merely
    /// look alike.
    func testPairingWriteTargetAndRequestReadTargetAreTheSameURL() throws {
        let paths = AppPaths(root: tempRoot.appendingPathComponent("app-support", isDirectory: true))
        let environment = AppEnvironment(paths: paths, pairingKeychain: store)

        let coordinator = environment.makePairingCoordinator()
        XCTAssertNotNil(coordinator, "a real pairingKeychain was supplied, so a coordinator must be produced")
        XCTAssertEqual(coordinator?.pinnedCertificateURL, environment.apiClient?.pinnedCertificateURL)
    }

    /// `UITestBootstrap` is `#if UI_TESTING`-gated and lives in the app
    /// target, not the Unit test target — it cannot be exercised directly
    /// here. Assert its live-server session construction at source level,
    /// following the `readSource(_:)` convention already established by
    /// `PairingReachabilityTests`.
    func testLiveServerUITestSessionPassesTheScopedPinnedCertificateURL() throws {
        let source = try readSource("Playstead/UITesting/UITestBootstrap.swift")
        let nonCommentLines = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertTrue(
            nonCommentLines.contains("pinnedCertificateURL:"),
            "the live-server UI test session's APIClient construction must pass an explicit pinnedCertificateURL:"
        )
    }

    private func readSource(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SecurityTests
            .deletingLastPathComponent() // PlaysteadTests
            .deletingLastPathComponent() // playstead-mac
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
