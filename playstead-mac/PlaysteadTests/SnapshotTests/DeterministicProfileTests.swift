import XCTest
@testable import Playstead

#if UI_TESTING
import CryptoKit
@MainActor
final class DeterministicProfileTests: XCTestCase {
    private var roots: [URL] = []
    // Public, test-only X.509 CA certificate. Its private key is not retained;
    // these bootstrap tests need only exercise the scoped-anchor validation.
    private static let unpairedLiveServerTestCA = "MIIBpzCCAU2gAwIBAgIUfHfctQ4ZAsjxb3rvArLi/iS5ZGowCgYIKoZIzj0EAwIwITEfMB0GA1UEAwwWUGxheXN0ZWFkIFVuaXQgVGVzdCBDQTAeFw0yNjA5MzAwMjE2MjdaFw0zNjA5MjcwMjE2MjdaMCExHzAdBgNVBAMMFlBsYXlzdGVhZCBVbml0IFRlc3QgQ0EwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAAR+9q3UmV+V9f+bU/o7X04Wdk/k7cQEN4YXgIjv6loOVm874IzAXQ9KAB44BflkCcoyUgERx5W1VB16HHDuxaiqo2MwYTAdBgNVHQ4EFgQUruL/spAjUdo2Z3CQEt4NI+LRoQwwHwYDVR0jBBgwFoAUruL/spAjUdo2Z3CQEt4NI+LRoQwwDwYDVR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYwCgYIKoZIzj0EAwIDSAAwRQIhAJl4kqVNa8810lauqyXNWq5vmtv61RQrCqZjtiOToB/CAiBZhhQ1AzJfGLgtktQ5LiLH42fcfYmKb89Z5yV3Yg2YRg=="

    override func tearDownWithError() throws {
        for root in roots {
            try? FileManager.default.removeItem(at: root)
        }
        roots.removeAll()
        try super.tearDownWithError()
    }

    func testProfileVocabularyIsFiniteAndExact() {
        XCTAssertEqual(
            DeterministicProfile.allCases.map(\.rawValue),
            [
                "empty-library",
                "populated-curation-reorder",
                "paused-active-queue",
                "quota-block-reclaim",
                "storage",
                "bios-acceptance",
                "bios-no-reference",
                "save-restorable",
                "save-only-copy",
                "save-diverged"
            ]
        )
    }

    func testBiosProfilesKeepSyntheticReferenceAndNoReferenceCasesDistinct() throws {
        let referenceProfile = DeterministicProfile.biosAcceptance
        XCTAssertTrue(referenceProfile.requiresBIOSForUITesting)
        XCTAssertEqual(referenceProfile.uiTestingBiosReferences.count, 1)
        let reference = try XCTUnwrap(referenceProfile.uiTestingBiosReferences.first)
        XCTAssertEqual(reference.system, DeterministicProfile.syntheticBIOSSystem)
        XCTAssertEqual(reference.expectedByteLength, DeterministicProfile.syntheticBIOSCandidateBytes.count)
        XCTAssertEqual(
            reference.knownSHA256Digests,
            [Self.digest(DeterministicProfile.syntheticBIOSCandidateBytes)]
        )

        let noReferenceProfile = DeterministicProfile.biosNoReference
        XCTAssertTrue(noReferenceProfile.requiresBIOSForUITesting)
        XCTAssertTrue(noReferenceProfile.uiTestingBiosReferences.isEmpty)
    }

    func testBiosAcceptanceSessionCanBeReopenedWithoutReseeding() throws {
        let sessionID = UUID().uuidString.lowercased()
        let seeded = try DeterministicProfile.biosAcceptance.makeFixture(sessionID: sessionID)
        roots.append(seeded.root)
        XCTAssertEqual(seeded.catalogueStore.count(), 1)
        XCTAssertEqual(seeded.pinStore.allPinned(), seeded.expected.pinnedAssetSetIDs)

        let reopened = try DeterministicProfile.biosAcceptance.makeFixture(sessionID: sessionID)
        XCTAssertEqual(reopened.root, seeded.root)
        XCTAssertEqual(reopened.catalogueStore.count(), 1)
        XCTAssertEqual(reopened.pinStore.allPinned(), seeded.pinStore.allPinned())
        try reopened.assertExactState()
    }

    func testMissingAndUnknownSelectorsFailClosed() {
        XCTAssertThrowsError(try DeterministicProfile.parse(nil)) { error in
            XCTAssertEqual(error as? DeterministicProfileError, .missingProfile)
        }
        XCTAssertThrowsError(try DeterministicProfile.parse("../../owner.sqlite3")) { error in
            XCTAssertEqual(error as? DeterministicProfileError, .unknownProfile("../../owner.sqlite3"))
        }
    }

    func testEmptyOneAndThreeItemBoundariesAreExactAndNonVacuous() throws {
        let empty = try makeFixture(.emptyLibrary)
        XCTAssertEqual(empty.catalogueStore.count(), 0)
        try empty.assertExactState()

        let one = try makeFixture(.storage)
        XCTAssertEqual(one.catalogueStore.count(), 1)
        XCTAssertEqual(one.expected.cachedObjectCount, 1)
        try one.assertExactState()

        let three = try makeFixture(.populatedCurationReorder)
        XCTAssertEqual(three.catalogueStore.count(), 3)
        XCTAssertEqual(three.curationStore.fetchCollectionMembers().map(\.position), ["6", "i", "u"])
        try three.assertExactState()
    }

    func testEveryProfileHasItsExactProductionStoreStateSet() throws {
        for profile in DeterministicProfile.allCases {
            let fixture = try makeFixture(profile)
            try fixture.assertExactState()

            XCTAssertEqual(Set(fixture.downloadQueue.list().map(\.state)), fixture.expected.queueStates)
            XCTAssertEqual(fixture.pinStore.allPinned(), fixture.expected.pinnedAssetSetIDs)
            XCTAssertEqual(fixture.quotaManager.policy(), fixture.expected.quotaPolicy)
        }
    }

    func testQuotaBlockReclaimProfileComputesExactProductionDecisionBeforeExternalIO() async throws {
        let session = try UITestBootstrap.makeSession(environment: [
            UITestBootstrap.modeKey: "1",
            UITestBootstrap.profileKey: DeterministicProfile.quotaBlockReclaim.rawValue
        ])
        roots.append(session.fixture.root)

        let environment = session.environment
        let target = try XCTUnwrap(
            environment.catalogueStore.fetchAll().first { $0.displayTitle == "Synthetic Quota Download" }
        )
        XCTAssertTrue(environment.uiTestingBlocksExternalIO)
        XCTAssertEqual(environment.quotaManager.usedBytes(), 32)
        XCTAssertEqual(environment.quotaManager.policy().quotaBytes, 16)
        XCTAssertEqual(environment.pendingDownloadBytes(for: target), 32)

        let expected = QuotaVerdict(allowed: false, limitHit: .quota, shortfallBytes: 48)
        XCTAssertEqual(environment.quotaVerdict(forDownloading: target), expected)
        let attempt = await environment.attemptDownload(for: target)
        XCTAssertEqual(attempt, .blocked(expected))
        XCTAssertEqual(environment.reclaimCandidateRows().map(\.bytes), [32])
    }

    func testEveryFixtureUsesAUniqueRootAndCleanupRemovesOnlyThatRoot() throws {
        let first = try makeFixture(.emptyLibrary)
        let second = try makeFixture(.emptyLibrary)
        XCTAssertNotEqual(first.root, second.root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.paths.databaseURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.paths.databaseURL.path))

        try first.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.root.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.root.path))
        roots.removeAll { $0 == first.root }
    }

    func testLiveServerProfileStartsEmpty() throws {
        let fixture = try makeFixture(.emptyLibrary)
        XCTAssertEqual(fixture.catalogueStore.count(), 0)
        XCTAssertTrue(fixture.downloadQueue.list().isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.paths.objects.path).isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.paths.partials.path).isEmpty)
    }

    func testUnpairedLiveServerBootstrapCreatesAndOpensAMissingScopedKeychain() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("playstead-fresh-unpaired-\(UUID().uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        roots.append(root)
        let keychainURL = root.appendingPathComponent("fresh.keychain-db")

        let session = try UITestBootstrap.makeSession(
            environment: unpairedLiveServerEnvironment(root: root, keychainURL: keychainURL)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: keychainURL.path))
        let credential = await session.environment.apiClient?.credential
        XCTAssertNil(credential)
    }

    func testUnpairedLiveServerBootstrapAcceptsEquivalentPrivateTemporaryKeychainSpelling() async throws {
        // `/private/tmp` is a symlink on macOS. The root may arrive from a
        // framework as its resolved spelling while the recovery launcher
        // supplies its child Keychain with the original `/private/tmp` path.
        let privateRoot = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("playstead-private-spelling-\(UUID().uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(
            at: privateRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        roots.append(privateRoot)

        let resolvedRoot = privateRoot.resolvingSymlinksInPath().standardizedFileURL
        XCTAssertNotEqual(privateRoot.path, resolvedRoot.path, "test requires /private/tmp to resolve through its symlink")
        let privateKeychainURL = privateRoot.appendingPathComponent("fresh.keychain-db")

        let session = try UITestBootstrap.makeSession(
            environment: unpairedLiveServerEnvironment(root: resolvedRoot, keychainURL: privateKeychainURL)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: privateKeychainURL.path))
        let credential = await session.environment.apiClient?.credential
        XCTAssertNil(credential)
    }

    func testUnpairedLiveServerBootstrapRejectsKeychainOutsideItsCanonicalRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("playstead-contained-root-\(UUID().uuidString.lowercased())", isDirectory: true)
        let escapedKeychain = FileManager.default.temporaryDirectory
            .appendingPathComponent("playstead-escaped-keychain-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        roots.append(root)

        XCTAssertThrowsError(try UITestBootstrap.makeSession(environment: [
            UITestBootstrap.modeKey: "1",
            UITestBootstrap.liveServerKey: "1",
            UITestBootstrap.unpairedKey: "1",
            UITestBootstrap.liveRootKey: root.path,
            UITestBootstrap.keychainKey: escapedKeychain.path,
            UITestBootstrap.keychainServiceKey: "dev.playstead.mac.live.\(UUID().uuidString.lowercased())"
        ])) { error in
            XCTAssertEqual(
                error as? DeterministicProfileError,
                .stateMismatch("recovery direct launch Keychain escaped its run root")
            )
        }
    }

    private func makeFixture(_ profile: DeterministicProfile) throws -> DeterministicProfileFixture {
        let fixture = try profile.makeFixture()
        roots.append(fixture.root)
        return fixture
    }

    private func unpairedLiveServerEnvironment(root: URL, keychainURL: URL) throws -> [String: String] {
        let certificate = try XCTUnwrap(Data(base64Encoded: Self.unpairedLiveServerTestCA))
        let certificateURL = root.appendingPathComponent("unit-test-live-server-ca.der")
        try certificate.write(to: certificateURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: certificateURL.path)

        return [
            UITestBootstrap.modeKey: "1",
            UITestBootstrap.liveServerKey: "1",
            UITestBootstrap.unpairedKey: "1",
            UITestBootstrap.liveRootKey: root.path,
            UITestBootstrap.keychainKey: keychainURL.path,
            UITestBootstrap.keychainServiceKey: "dev.playstead.mac.live.\(UUID().uuidString.lowercased())",
            UITestBootstrap.liveServerTrustAnchorKey: certificateURL.path,
            UITestBootstrap.liveServerTrustAnchorDigestKey: Self.digest(certificate),
            UITestBootstrap.liveServerPairingTargetKey: "https://127.0.0.1:4010"
        ]
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
#endif
