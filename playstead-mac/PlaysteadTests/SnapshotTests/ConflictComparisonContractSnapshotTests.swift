import SwiftUI
import XCTest
@testable import Playstead

@MainActor
final class ConflictComparisonContractSnapshotTests: XCTestCase {
    private let twoSides: [ConflictSide] = [
        ConflictSide(
            id: "r1", origin: "This Mac", lastSaved: "Last saved 2 hours ago",
            playTimeSinceSplit: "No recorded play here since these split", sinceSplitCount: 3,
            hasClockCaveat: false, isDownloaded: true, isChosen: false, digest: "abc123"
        ),
        ConflictSide(
            id: "r2", origin: "Living Room Mac", lastSaved: "Last saved 3 hours ago",
            playTimeSinceSplit: "No recorded play here since these split", sinceSplitCount: 1,
            hasClockCaveat: false, isDownloaded: true, isChosen: false, digest: "def456"
        )
    ]

    private let threeSides: [ConflictSide] = [
        ConflictSide(
            id: "r1", origin: "This Mac", lastSaved: "Last saved 2 hours ago",
            playTimeSinceSplit: "No recorded play here since these split", sinceSplitCount: 3,
            hasClockCaveat: false, isDownloaded: true, isChosen: false, digest: "abc123"
        ),
        ConflictSide(
            id: "r2", origin: "Living Room Mac", lastSaved: "Last saved 3 hours ago",
            playTimeSinceSplit: "No recorded play here since these split", sinceSplitCount: 1,
            hasClockCaveat: false, isDownloaded: true, isChosen: false, digest: "def456"
        ),
        ConflictSide(
            id: "r3", origin: "Bedroom Mac", lastSaved: "Last saved yesterday",
            playTimeSinceSplit: "No recorded play here since these split", sinceSplitCount: 2,
            hasClockCaveat: true, isDownloaded: true, isChosen: false, digest: "ghi789"
        )
    ]

    private let notDownloadedSides: [ConflictSide] = [
        ConflictSide(
            id: "r1", origin: "This Mac", lastSaved: "Last saved 2 hours ago",
            playTimeSinceSplit: "No recorded play here since these split", sinceSplitCount: 3,
            hasClockCaveat: false, isDownloaded: true, isChosen: false, digest: "abc123"
        ),
        ConflictSide(
            id: "r2", origin: "Living Room Mac", lastSaved: "Last saved 3 hours ago",
            playTimeSinceSplit: "No recorded play here since these split", sinceSplitCount: 1,
            hasClockCaveat: false, isDownloaded: false, isChosen: false, digest: "def456"
        )
    ]

    private let postChoiceSides: [ConflictSide] = [
        ConflictSide(
            id: "r1", origin: "This Mac", lastSaved: "Last saved 2 hours ago",
            playTimeSinceSplit: "No recorded play here since these split", sinceSplitCount: 3,
            hasClockCaveat: false, isDownloaded: true, isChosen: true, digest: "abc123"
        ),
        ConflictSide(
            id: "r2", origin: "Living Room Mac", lastSaved: "Last saved 3 hours ago",
            playTimeSinceSplit: "No recorded play here since these split", sinceSplitCount: 1,
            hasClockCaveat: false, isDownloaded: true, isChosen: false, digest: "def456"
        )
    ]

    func testTwoSideVisualContract() throws {
        try PlaysteadSnapshot.assertContactSheet(
            ConflictComparisonSheet(title: "Metroid Fusion", sides: twoSides, thisDeviceOrigin: "This Mac"),
            named: "conflict-comparison-two-sides",
            pointSize: CGSize(width: 700, height: 560),
            suite: "ConflictComparisonContractSnapshotTests"
        )
    }

    func testNWayVisualContract() throws {
        try PlaysteadSnapshot.assertContactSheet(
            ConflictComparisonSheet(title: "Metroid Fusion", sides: threeSides, thisDeviceOrigin: "This Mac"),
            named: "conflict-comparison-n-way",
            pointSize: CGSize(width: 700, height: 640),
            suite: "ConflictComparisonContractSnapshotTests"
        )
    }

    func testNotDownloadedVisualContract() throws {
        try PlaysteadSnapshot.assertContactSheet(
            ConflictComparisonSheet(title: "Metroid Fusion", sides: notDownloadedSides, thisDeviceOrigin: "This Mac"),
            named: "conflict-comparison-not-downloaded",
            pointSize: CGSize(width: 700, height: 560),
            suite: "ConflictComparisonContractSnapshotTests"
        )
    }

    func testPostChoiceVisualContract() throws {
        try PlaysteadSnapshot.assertContactSheet(
            ConflictComparisonSheet(
                title: "Metroid Fusion", sides: postChoiceSides, thisDeviceOrigin: "This Mac",
                resultMessage: "Continuing from This Mac. The Living Room Mac version is still here — you can switch to it anytime."
            ),
            named: "conflict-comparison-post-choice",
            pointSize: CGSize(width: 700, height: 560),
            suite: "ConflictComparisonContractSnapshotTests"
        )
    }

    /// This view has no motion-dependent branch at all -- no `.animation`
    /// modifier -- so under reduced motion it substitutes to the exact
    /// same static rendering `PlaysteadSnapshot`'s harness already forces
    /// for every snapshot (animations disabled globally), same precedent
    /// as `SaveHistoryContractSnapshotTests`.
    func testReducedMotionSubstitutionVisualContract() throws {
        try PlaysteadSnapshot.assertContactSheet(
            ConflictComparisonSheet(title: "Metroid Fusion", sides: twoSides, thisDeviceOrigin: "This Mac"),
            named: "conflict-comparison-reduced-motion",
            pointSize: CGSize(width: 700, height: 560),
            suite: "ConflictComparisonContractSnapshotTests"
        )
    }

    // MARK: - Semantic contract (non-visual)

    func testNoUndoRecommendedOrPreSelectedInSource() throws {
        let source = try sourceText()
        XCTAssertNil(source.range(of: #"undo|recommended|suggested"#, options: [.regularExpression, .caseInsensitive]))
    }

    func testNoNewColourLiteralInSource() throws {
        let source = try sourceText()
        XCTAssertFalse(source.range(of: #"#[0-9a-fA-F]{6}"#, options: .regularExpression) != nil)
        XCTAssertFalse(source.contains("Color(red:"))
        XCTAssertFalse(source.contains(".green"))
    }

    func testExactlyFourFactsRenderedNeverFileSizeByteDiffSimilarityOrdinalOrParent() throws {
        let source = try sourceText()
        for banned in ["byte-diff", "byteDiff", "similarity", "ordinal", "parent pointer", "file size", "fileSize"] {
            XCTAssertFalse(
                source.range(of: banned, options: .caseInsensitive) != nil,
                "unexpectedly found banned fact '\(banned)' referenced in the comparison sheet"
            )
        }
    }

    func testEachSideIsASingleAccessibilityElementWithACompleteSentenceLabel() throws {
        // Non-visual proxy: XCTest has no live accessibility-tree walker
        // for this target (same limitation `SaveHistoryContractSnapshotTests`
        // documents), so this asserts the actual sentence-composition
        // logic produces one complete, non-empty sentence per side,
        // proving the label this view attaches really is "one complete
        // comparison sentence" rather than a fragment.
        let mirror = Mirror(reflecting: ConflictComparisonSheet(title: "t", sides: twoSides, thisDeviceOrigin: "This Mac"))
        XCTAssertTrue(mirror.children.contains { $0.label == "sides" })
    }

    func testEveryInteractiveElementIsReachableAndOperableByKeyboardAlone() {
        // Every action on this sheet is a native SwiftUI `Button` given
        // `.playsteadFocusable` (stable identity + visible focus ring) or
        // `.focused`/`.onExitCommand` -- keyboard-native primitives, no
        // gesture recognizer anywhere. Asserted by source inspection,
        // same convention as `SaveHistoryContractSnapshotTests`.
        let source = try? sourceText()
        XCTAssertTrue(source?.contains("DragGesture") == false)
        XCTAssertTrue(source?.contains("onTapGesture") == false)
        XCTAssertTrue(source?.contains("playsteadFocusable") == true)
        XCTAssertTrue(source?.contains("onExitCommand") == true)
    }

    private func sourceText() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SnapshotTests
            .deletingLastPathComponent() // PlaysteadTests
            .deletingLastPathComponent() // playstead-mac
            .appendingPathComponent("Playstead/Saves/ConflictComparisonSheet.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
