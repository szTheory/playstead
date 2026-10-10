import XCTest
import SwiftUI
@testable import Playstead

#if UI_TESTING
@MainActor
final class DeterministicProfileTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDownWithError() throws {
        for root in roots {
            try? FileManager.default.removeItem(at: root)
        }
        roots.removeAll()
        try super.tearDownWithError()
    }

    func testRootReconstructionBootstrapsOneSessionAndUploadLane() throws {
        var lanes: [ObjectIdentifier] = []
        let makeSession = {
            let session = try UITestBootstrap.makeSession(environment: [
                UITestBootstrap.modeKey: "1",
                UITestBootstrap.profileKey: DeterministicProfile.emptyLibrary.rawValue
            ])
            self.roots.append(session.fixture.root)
            lanes.append(ObjectIdentifier(session.environment.saveUploadLane))
            return session
        }
        let host = NSHostingView(rootView: UITestProfileRootView(makeSession: makeSession))
        host.frame = CGRect(x: 0, y: 0, width: 960, height: 560)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(lanes.count, 1, "the mounted root must actually bootstrap")

        // SwiftUI retains the same root identity while reconstructing its
        // value. Session creation starts tasks, so even a discarded session
        // would own an independent lane over the same live profile store.
        for _ in 0..<2 {
            host.rootView = UITestProfileRootView(makeSession: makeSession)
            host.layoutSubtreeIfNeeded()
        }
        XCTAssertEqual(lanes.count, 1, "root reconstruction must not start another bootstrap")
        XCTAssertEqual(Set(lanes).count, 1, "one root identity must own one upload lane")

        let secondHost = NSHostingView(rootView: UITestProfileRootView(makeSession: makeSession))
        secondHost.frame = host.frame
        secondHost.layoutSubtreeIfNeeded()
        XCTAssertEqual(lanes.count, 2, "a different root identity must own its own session")
        XCTAssertEqual(Set(lanes).count, 2, "session ownership must not become a global cache")
    }

    func testCatalogueTransitionControlRejectsInvalidSelectorsAndNonPrivateRoots() throws {
        let token = UUID().uuidString.lowercased()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("playstead-ui-catalogue-transition-\(token)")
        roots.append(root)
        for (profile, value) in [("empty-library", "../../outside"), ("storage", token),
                                 ("empty-library", token.uppercased()), ("empty-library", token)] {
            XCTAssertThrowsError(try UITestBootstrap.makeSession(environment: [
                "PLAYSTEAD_UI_TESTING": "1", "PLAYSTEAD_UI_TEST_PROFILE": profile,
                "PLAYSTEAD_UI_TEST_CATALOGUE_TRANSITION": value
            ]))
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o755])
        XCTAssertThrowsError(try UITestBootstrap.makeSession(environment: [
            "PLAYSTEAD_UI_TESTING": "1", "PLAYSTEAD_UI_TEST_PROFILE": "empty-library",
            "PLAYSTEAD_UI_TEST_CATALOGUE_TRANSITION": token
        ]))
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
                "save-restorable",
                "save-only-copy",
                "save-diverged"
            ]
        )
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

    private func makeFixture(_ profile: DeterministicProfile) throws -> DeterministicProfileFixture {
        let fixture = try profile.makeFixture()
        roots.append(fixture.root)
        return fixture
    }
}
#endif
