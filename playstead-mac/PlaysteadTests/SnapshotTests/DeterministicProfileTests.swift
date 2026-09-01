import XCTest
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

    func testProfileVocabularyIsFiniteAndExact() {
        XCTAssertEqual(
            DeterministicProfile.allCases.map(\.rawValue),
            [
                "empty-library",
                "populated-curation-reorder",
                "paused-active-queue",
                "quota-block-reclaim",
                "storage"
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
