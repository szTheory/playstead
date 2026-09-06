import XCTest
@testable import Playstead

/// Covers `SaveHistorySessionBuilder` (plan 04-22 task 2): a pure,
/// store-free grouping/reading of committed `SaveRevisionRow`s into
/// `SaveHistorySession` values -- one test per `<behavior>` bullet.
final class SaveHistorySessionBuilderTests: XCTestCase {
    private func row(
        id: String, sessionID: String? = nil, originDeviceID: String? = nil,
        recordedAt: String?, durability: SaveDurability = .localOnly,
        restoredHereAt: String? = nil
    ) -> SaveRevisionRow {
        SaveRevisionRow(
            id: id, saveLineID: "line-1", parentRevisionID: nil, blobSHA256: "digest-\(id)", sizeBytes: 32_768,
            originDeviceID: originDeviceID, deviceCapturedAt: nil, recordedAt: recordedAt,
            captureMethod: nil, adapterID: nil, adapterVersion: nil, saveFormat: nil, formatConfidence: nil,
            playSessionID: nil, durability: durability.rawValue, localPath: nil,
            sessionID: sessionID, restoredHereAt: restoredHereAt
        )
    }

    // MARK: - Empty / basic cases

    func testALineWithZeroRevisionsProducesAnEmptyArray() {
        let sessions = SaveHistorySessionBuilder.build(revisions: [], headIDs: [], thisDeviceName: "This Mac")
        XCTAssertTrue(sessions.isEmpty)
    }

    func testALineWithOnePromotedRevisionProducesOneSessionWithOneRow() {
        let r = row(id: "r1", recordedAt: "2026-01-01T00:00:00Z")
        let sessions = SaveHistorySessionBuilder.build(revisions: [r], headIDs: ["r1"], thisDeviceName: "This Mac")
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.revisions.count, 1)
        XCTAssertEqual(sessions.first?.revisions.first?.id, "r1")
    }

    // MARK: - Grouping by sessionID

    func testTwoRevisionsSharingASessionIDProduceOneSessionWithTwoRowsOrderedOldestFirst() {
        let older = row(id: "r1", sessionID: "session-a", recordedAt: "2026-01-01T00:00:00Z")
        let newer = row(id: "r2", sessionID: "session-a", recordedAt: "2026-01-01T01:00:00Z")
        let sessions = SaveHistorySessionBuilder.build(
            revisions: [newer, older], headIDs: ["r2"], thisDeviceName: "This Mac"
        )
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.revisions.map(\.id), ["r1", "r2"], "rows must be ordered oldest first")
    }

    func testARevisionWithANilSessionIDGetsItsOwnSingleRowSessionNeverMergedWithOtherNilSessionRevisions() {
        let a = row(id: "r1", sessionID: nil, recordedAt: "2026-01-01T00:00:00Z")
        let b = row(id: "r2", sessionID: nil, recordedAt: "2026-01-02T00:00:00Z")
        let sessions = SaveHistorySessionBuilder.build(revisions: [a, b], headIDs: ["r2"], thisDeviceName: "This Mac")
        XCTAssertEqual(sessions.count, 2, "each nil-session revision must form its own singleton session")
        for session in sessions {
            XCTAssertEqual(session.revisions.count, 1)
        }
    }

    // MARK: - Durability

    func testARowsDurabilityEqualsTheRevisionsStoredDurabilityColumnValue() {
        let cases: [SaveDurability] = [.localOnly, .queued, .uploaded]
        for durability in cases {
            let r = row(id: "r-\(durability.rawValue)", recordedAt: "2026-01-01T00:00:00Z", durability: durability)
            let sessions = SaveHistorySessionBuilder.build(
                revisions: [r], headIDs: [r.id], thisDeviceName: "This Mac"
            )
            XCTAssertEqual(sessions.first?.revisions.first?.durability, durability)
        }
    }

    // MARK: - isSeparateVersion (lineage)

    func testWhenTheLineHasTwoStandingHeadsBothHeadRowsReportIsSeparateVersionTrueAndNonHeadRowsReportFalse() {
        let head1 = row(id: "h1", sessionID: nil, recordedAt: "2026-01-01T00:00:00Z")
        let head2 = row(id: "h2", sessionID: nil, recordedAt: "2026-01-02T00:00:00Z")
        let nonHead = row(id: "n1", sessionID: nil, recordedAt: "2025-12-31T00:00:00Z")
        let sessions = SaveHistorySessionBuilder.build(
            revisions: [head1, head2, nonHead], headIDs: ["h1", "h2"], thisDeviceName: "This Mac"
        )
        let rowsByID = Dictionary(uniqueKeysWithValues: sessions.flatMap(\.revisions).map { ($0.id, $0) })
        XCTAssertEqual(rowsByID["h1"]?.isSeparateVersion, true)
        XCTAssertEqual(rowsByID["h2"]?.isSeparateVersion, true)
        XCTAssertEqual(rowsByID["n1"]?.isSeparateVersion, false)
    }

    func testWhenTheLineHasExactlyOneHeadNoRowReportsIsSeparateVersion() {
        let head = row(id: "h1", sessionID: nil, recordedAt: "2026-01-01T00:00:00Z")
        let sessions = SaveHistorySessionBuilder.build(revisions: [head], headIDs: ["h1"], thisDeviceName: "This Mac")
        XCTAssertEqual(sessions.first?.revisions.first?.isSeparateVersion, false)
    }

    // MARK: - isRestoredHere (provenance)

    func testARevisionWithANonNilRestoredHereAtReportsIsRestoredHereTrue() {
        let r = row(id: "r1", recordedAt: "2026-01-01T00:00:00Z", restoredHereAt: "2026-01-02T00:00:00Z")
        let sessions = SaveHistorySessionBuilder.build(revisions: [r], headIDs: ["r1"], thisDeviceName: "This Mac")
        XCTAssertEqual(sessions.first?.revisions.first?.isRestoredHere, true)
    }

    // MARK: - isCurrent (position)

    func testExactlyOneRowReportsIsCurrentTrueTheNewestAmongLocallyCapturedOrRestoredRevisions() {
        let localOld = row(id: "local-old", originDeviceID: nil, recordedAt: "2026-01-01T00:00:00Z")
        let localNew = row(id: "local-new", originDeviceID: nil, recordedAt: "2026-01-03T00:00:00Z")
        let remote = row(id: "remote", originDeviceID: "other-mac", recordedAt: "2026-01-05T00:00:00Z")
        let sessions = SaveHistorySessionBuilder.build(
            revisions: [localOld, localNew, remote], headIDs: ["remote"], thisDeviceName: "This Mac"
        )
        let rowsByID = Dictionary(uniqueKeysWithValues: sessions.flatMap(\.revisions).map { ($0.id, $0) })
        XCTAssertEqual(rowsByID.values.filter(\.isCurrent).count, 1)
        XCTAssertEqual(rowsByID["local-new"]?.isCurrent, true)
        XCTAssertEqual(rowsByID["local-old"]?.isCurrent, false)
        XCTAssertEqual(rowsByID["remote"]?.isCurrent, false, "a remote-origin revision never restored here is never current")
    }

    func testALineWhoseOnlyRevisionsCameFromAnotherDeviceAndWereNeverRestoredHereHasNoCurrentRow() {
        let remote = row(id: "remote", originDeviceID: "other-mac", recordedAt: "2026-01-01T00:00:00Z")
        let sessions = SaveHistorySessionBuilder.build(revisions: [remote], headIDs: ["remote"], thisDeviceName: "This Mac")
        XCTAssertTrue(sessions.flatMap(\.revisions).allSatisfy { !$0.isCurrent })
    }

    func testARestoredRevisionFromAnotherDeviceCanBeCurrent() {
        let remoteRestored = row(
            id: "remote-restored", originDeviceID: "other-mac", recordedAt: "2026-01-01T00:00:00Z",
            restoredHereAt: "2026-01-02T00:00:00Z"
        )
        let sessions = SaveHistorySessionBuilder.build(
            revisions: [remoteRestored], headIDs: ["remote-restored"], thisDeviceName: "This Mac"
        )
        XCTAssertEqual(sessions.first?.revisions.first?.isCurrent, true)
    }

    // MARK: - Idempotency

    func testCallingTheBuilderTwiceOverTheSameRowsReturnsAnEqualArray() {
        let a = row(id: "r1", sessionID: "s1", recordedAt: "2026-01-01T00:00:00Z")
        let b = row(id: "r2", sessionID: "s1", recordedAt: "2026-01-01T01:00:00Z")
        let c = row(id: "r3", sessionID: nil, recordedAt: "2026-01-02T00:00:00Z")
        let first = SaveHistorySessionBuilder.build(revisions: [a, b, c], headIDs: ["r3"], thisDeviceName: "This Mac")
        let second = SaveHistorySessionBuilder.build(revisions: [a, b, c], headIDs: ["r3"], thisDeviceName: "This Mac")
        XCTAssertEqual(first, second)
    }

    // MARK: - Device name

    func testDeviceNameForAGroupIsTheFirstRowsOriginDeviceIDOrThisDeviceNameWhenNil() {
        let local = row(id: "r1", sessionID: "s1", originDeviceID: nil, recordedAt: "2026-01-01T00:00:00Z")
        let remote = row(id: "r2", sessionID: "s2", originDeviceID: "Living Room Mac", recordedAt: "2026-01-02T00:00:00Z")
        let sessions = SaveHistorySessionBuilder.build(
            revisions: [local, remote], headIDs: ["r1", "r2"], thisDeviceName: "This Mac"
        )
        let byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        XCTAssertEqual(byID["s1"]?.deviceName, "This Mac")
        XCTAssertEqual(byID["s2"]?.deviceName, "Living Room Mac")
    }

    // MARK: - Session ordering (most recent first)

    func testSessionsAreOrderedMostRecentFirst() {
        let old = row(id: "old", sessionID: nil, recordedAt: "2026-01-01T00:00:00Z")
        let recent = row(id: "recent", sessionID: nil, recordedAt: "2026-01-05T00:00:00Z")
        let sessions = SaveHistorySessionBuilder.build(
            revisions: [old, recent], headIDs: ["old", "recent"], thisDeviceName: "This Mac"
        )
        XCTAssertEqual(sessions.map(\.id), ["recent", "old"])
    }

    // MARK: - AppEnvironment-level integration

    @MainActor
    func testAnAppEnvironmentWhoseSaveStoreHoldsOneRevisionForAGameReturnsExactlyOneSessionWithOneRow() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let paths = AppPaths(root: tempRoot)
        let credential = PairingCredential(deviceID: "device-1", baseURL: URL(string: "https://sync.test")!, token: "test-token")
        let apiClient = APIClient(keychain: KeychainStore(), session: StubURLProtocol.makeSession(), credential: credential)
        let environment = AppEnvironment(
            paths: paths, apiClient: apiClient, reachability: Reachability(startOnline: true, monitorAutomatically: false)
        )
        let romSHA256 = String(repeating: "a", count: 64)
        let entry = CatalogueEntry(
            id: "asset-1", system: "gba", displayTitle: "Test Game", tags: [:],
            members: [AssetMember(ordinal: 0, role: "rom", required: true, sha256: romSHA256, size: 32_768, name: "game.gba")]
        )
        try environment.catalogueStore.upsert(entry)
        let line = try environment.saveStore.resolveLine(
            contentKey: romSHA256, saveKind: "battery", slot: "0", placeholderID: "line-1"
        )
        try environment.saveStore.insertRevision(SaveRevisionRow(
            id: "r1", saveLineID: line.id, parentRevisionID: nil, blobSHA256: "digest-1", sizeBytes: 32_768,
            originDeviceID: nil, deviceCapturedAt: nil, recordedAt: "2026-01-01T00:00:00Z",
            captureMethod: nil, adapterID: nil, adapterVersion: nil, saveFormat: nil, formatConfidence: nil,
            playSessionID: nil, durability: SaveDurability.localOnly.rawValue, localPath: nil
        ))

        let sessions = environment.saveHistorySessions(forAssetSetID: "asset-1")
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.revisions.count, 1)

        XCTAssertTrue(environment.saveHistorySessions(forAssetSetID: "no-such-game").isEmpty)
    }
}
