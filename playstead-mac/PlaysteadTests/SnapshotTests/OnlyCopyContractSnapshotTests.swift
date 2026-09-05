import SwiftUI
import XCTest
@testable import Playstead

@MainActor
final class OnlyCopyContractSnapshotTests: XCTestCase {
    // MARK: - The escalated panel

    func testEscalatedPanelVisualContract() throws {
        let result = OnlyCopyEscalation.evaluate(
            OnlyCopyEscalationInput(onlyOnThisMacCount: 3, title: "Metroid Fusion", failureClassification: .revokedAuth)
        )!
        try PlaysteadSnapshot.assertContactSheet(
            OnlyCopyEscalationPanel(escalation: result),
            named: "only-copy-escalation-panel",
            pointSize: CGSize(width: 520, height: 220),
            suite: "OnlyCopyContractSnapshotTests"
        )
    }

    /// This panel has no motion-dependent branch at all -- no
    /// `.animation` modifier -- so under reduced motion it substitutes
    /// to the exact same static rendering `PlaysteadSnapshot`'s harness
    /// already forces globally (animations disabled for every
    /// snapshot). Same precedent as `SaveHistoryContractSnapshotTests`
    /// and `ConflictComparisonContractSnapshotTests`.
    func testReducedMotionSubstitutionVisualContract() throws {
        let result = OnlyCopyEscalation.evaluate(
            OnlyCopyEscalationInput(onlyOnThisMacCount: 1, title: "Metroid Fusion", failureClassification: .serverRefusal)
        )!
        try PlaysteadSnapshot.assertContactSheet(
            OnlyCopyEscalationPanel(escalation: result),
            named: "only-copy-escalation-panel-reduced-motion",
            pointSize: CGSize(width: 520, height: 220),
            suite: "OnlyCopyContractSnapshotTests"
        )
    }

    // MARK: - The non-escalating states (semantic: there is nothing to render)

    func testOfflineQueueNeverProducesAPanelToRender() {
        XCTAssertNil(OnlyCopyEscalation.evaluate(
            OnlyCopyEscalationInput(onlyOnThisMacCount: 5, title: "Metroid Fusion", failureClassification: .offlineQueue)
        ))
    }

    func testSlowUploadNeverProducesAPanelToRender() {
        XCTAssertNil(OnlyCopyEscalation.evaluate(
            OnlyCopyEscalationInput(onlyOnThisMacCount: 5, title: "Metroid Fusion", failureClassification: .slowUpload)
        ))
    }

    func testOldLocalOnlyWithReachableServerNeverProducesAPanelToRender() {
        XCTAssertNil(OnlyCopyEscalation.evaluate(
            OnlyCopyEscalationInput(onlyOnThisMacCount: 1, title: "Metroid Fusion", failureClassification: .none)
        ))
    }

    // MARK: - Source-level contract

    func testNoColourLiteralInSource() throws {
        let source = try sourceText()
        XCTAssertFalse(source.range(of: #"#[0-9a-fA-F]{6}"#, options: .regularExpression) != nil)
        XCTAssertFalse(source.contains("Color(red:"))
        XCTAssertFalse(source.contains(".green"))
    }

    func testNoDurationOrCountThresholdDrivenLogicInSource() throws {
        let source = try sourceText()
        XCTAssertNil(source.range(of: #"daysSince|elapsed|olderThan|threshold"#, options: [.regularExpression, .caseInsensitive]))
    }

    private func sourceText() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SnapshotTests
            .deletingLastPathComponent() // PlaysteadTests
            .deletingLastPathComponent() // playstead-mac
            .appendingPathComponent("Playstead/Saves/OnlyCopyEscalation.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
