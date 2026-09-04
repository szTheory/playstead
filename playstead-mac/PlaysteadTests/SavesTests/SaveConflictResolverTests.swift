import XCTest
@testable import Playstead

// MARK: - Task 1: SaveAttentionSource (D-38, D-53, D-66)

final class SaveAttentionSourceTests: XCTestCase {
    private func candidate(
        line: String = "line-1", assetSetID: String = "asset-1", title: String = "Metroid Fusion",
        heads: [String] = ["r1", "r2"], origins: [String] = ["This Mac", "Living Room Mac"]
    ) -> SaveAttentionCandidate {
        SaveAttentionCandidate(saveLineID: line, assetSetID: assetSetID, title: title, headRevisionIDs: heads, originNames: origins)
    }

    // MARK: hasUnacknowledgedDivergence

    func testSingleHeadIsNeverDivergent() {
        XCTAssertFalse(SaveAttentionSource.hasUnacknowledgedDivergence(headRevisionIDs: ["r1"], disposedHeadIDs: nil))
    }

    func testTwoHeadsWithNoDispositionIsUnacknowledgedDivergence() {
        XCTAssertTrue(SaveAttentionSource.hasUnacknowledgedDivergence(headRevisionIDs: ["r1", "r2"], disposedHeadIDs: nil))
    }

    func testExactlyMatchingDispositionSuppressesDivergence() {
        XCTAssertFalse(SaveAttentionSource.hasUnacknowledgedDivergence(headRevisionIDs: ["r1", "r2"], disposedHeadIDs: ["r2", "r1"]))
    }

    func testANewHeadSetAfterAPriorDispositionReRaises() {
        XCTAssertTrue(SaveAttentionSource.hasUnacknowledgedDivergence(headRevisionIDs: ["r1", "r3"], disposedHeadIDs: ["r1", "r2"]))
    }

    // MARK: divergenceItems

    func testDivergenceProducesOneAttentionItemWithLockedCopy() {
        let items = SaveAttentionSource.divergenceItems(candidates: [candidate()], disposedHeadIDs: { _ in nil })
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Two versions of your progress in Metroid Fusion")
        XCTAssertEqual(
            items[0].body,
            "You played Metroid Fusion on This Mac and Living Room Mac without them syncing in between. Both versions are saved. Nothing has been overwritten."
        )
        XCTAssertEqual(items[0].primaryAction, "Compare versions")
    }

    func testThreeOrMoreHeadsUsesTheNVariantCopy() {
        let items = SaveAttentionSource.divergenceItems(
            candidates: [candidate(heads: ["r1", "r2", "r3"], origins: ["A", "B", "C"])],
            disposedHeadIDs: { _ in nil }
        )
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "3 versions of your progress in Metroid Fusion")
        XCTAssertTrue(items[0].body.contains("3 devices"))
        XCTAssertTrue(items[0].body.contains("All 3 versions are saved"))
    }

    func testADisposedForkProducesNoAttentionItem() {
        let items = SaveAttentionSource.divergenceItems(
            candidates: [candidate()], disposedHeadIDs: { _ in ["r1", "r2"] }
        )
        XCTAssertTrue(items.isEmpty, "acknowledging (or resolving) a fork must clear its item and it must not be re-raised")
    }

    func testAcknowledgedForkThenNewDivergenceReRaises() {
        // The stored disposition covers an *earlier* head set; the
        // candidate's current heads have moved on -- this is a fresh
        // fork, not the disposed one.
        let items = SaveAttentionSource.divergenceItems(
            candidates: [candidate(heads: ["r1", "r3"])], disposedHeadIDs: { _ in ["r1", "r2"] }
        )
        XCTAssertEqual(items.count, 1)
    }

    // MARK: blockedCaptureItems (carried through from plan 04-06)

    func testAnOpenBlockageRaisesThroughTheSameSource() {
        let row = SaveCaptureBlockedRow(
            id: "b1", saveLineID: "line-1", sessionID: nil, digest: nil, reason: "disk_full",
            firstFailedAt: "t1", lastFailedAt: "t1", failureCount: 1, alerted: true, resolvedAt: nil
        )
        let items = SaveAttentionSource.blockedCaptureItems(
            blockages: [(saveLineID: "line-1", assetSetID: "asset-1", title: "Metroid Fusion", row: row)]
        )
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, SaveVocabulary.blockerSaveDirectoryTitle)
        if case .captureBlocked(let saveLineID) = items[0].reason {
            XCTAssertEqual(saveLineID, "line-1")
        } else {
            XCTFail("expected .captureBlocked reason")
        }
    }

    func testAResolvedBlockageProducesNoAttentionItem() {
        let row = SaveCaptureBlockedRow(
            id: "b1", saveLineID: "line-1", sessionID: nil, digest: nil, reason: "disk_full",
            firstFailedAt: "t1", lastFailedAt: "t1", failureCount: 1, alerted: true, resolvedAt: "t2"
        )
        let items = SaveAttentionSource.blockedCaptureItems(
            blockages: [(saveLineID: "line-1", assetSetID: "asset-1", title: "Metroid Fusion", row: row)]
        )
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: grouped header/action (two or more diverged games)

    func testTwoDivergedGamesProduceTheGroupedHeaderAndSecondaryAction() {
        let items = SaveAttentionSource.divergenceItems(
            candidates: [
                candidate(line: "line-1", assetSetID: "asset-1", title: "Metroid Fusion"),
                candidate(line: "line-2", assetSetID: "asset-2", title: "Pokemon Emerald")
            ],
            disposedHeadIDs: { _ in nil }
        )
        guard let grouped = SaveAttentionSource.groupedDivergenceSummary(items: items) else {
            return XCTFail("expected a grouped summary for two diverged games")
        }
        XCTAssertEqual(grouped.header, "Two versions of your progress in 2 games")
        XCTAssertEqual(grouped.secondaryAction, "Keep both in all 2")
    }

    func testOneDivergedGameProducesNoGroupedSummary() {
        let items = SaveAttentionSource.divergenceItems(candidates: [candidate()], disposedHeadIDs: { _ in nil })
        XCTAssertNil(SaveAttentionSource.groupedDivergenceSummary(items: items))
    }

    // MARK: never a modal/notification/launch prompt (source-scan proof)

    func testSourceNeverReferencesAModalNotificationOrLaunchPromptAPI() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SavesTests
            .deletingLastPathComponent() // PlaysteadTests
            .deletingLastPathComponent() // playstead-mac
            .appendingPathComponent("Playstead/Saves/SaveAttentionSource.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertNil(source.range(of: #"NSAlert|\.alert\(|UNNotification|sheet\(isPresented.*conflict"#, options: [.regularExpression, .caseInsensitive]))
    }

    // MARK: card union (D-38's rank-1 rung, no rebaseline)

    func testUnacknowledgedDivergenceFeedsTheExistingRank1Rung() {
        XCTAssertEqual(LibraryStatus.forSaveState(conflicted: true), .needsAttention)
    }

    func testADisposedForkFeedsNoAttentionOntoTheCard() {
        let disposed = SaveAttentionSource.hasUnacknowledgedDivergence(headRevisionIDs: ["r1", "r2"], disposedHeadIDs: ["r1", "r2"])
        XCTAssertNil(LibraryStatus.forSaveState(conflicted: disposed))
    }
}
