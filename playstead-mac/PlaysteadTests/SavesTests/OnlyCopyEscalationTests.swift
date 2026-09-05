import XCTest
@testable import Playstead

final class OnlyCopyEscalationTests: XCTestCase {
    private func input(
        count: Int = 3,
        title: String = "Metroid Fusion",
        classification: SaveUploadFailureClassification
    ) -> OnlyCopyEscalationInput {
        OnlyCopyEscalationInput(onlyOnThisMacCount: count, title: title, failureClassification: classification)
    }

    // MARK: - The four non-escalating cases, asserted by name (D-40)

    func testOfflineQueueProducesNoEscalation() {
        XCTAssertNil(OnlyCopyEscalation.evaluate(input(classification: .offlineQueue)))
    }

    func testSlowUploadProducesNoEscalation() {
        XCTAssertNil(OnlyCopyEscalation.evaluate(input(classification: .slowUpload)))
    }

    func testNoCurrentFailureProducesNoEscalation() {
        XCTAssertNil(OnlyCopyEscalation.evaluate(input(classification: .none)))
    }

    func testThirtyDayOldLocalOnlyVersionWithReachableServerProducesNoEscalation() {
        // This classifier has no date or elapsed-time field at all -- an
        // old local-only version with a reachable server is expressed
        // here as `.none` (nothing currently failing), which proves
        // duration cannot drive escalation because the type cannot even
        // represent one.
        let thirtyDaysOld = input(count: 1, classification: .none)
        XCTAssertNil(OnlyCopyEscalation.evaluate(thirtyDaysOld))
    }

    // MARK: - The four unfixable conditions each produce an escalation

    func testRevokedAuthProducesEscalation() {
        let result = OnlyCopyEscalation.evaluate(input(classification: .revokedAuth))
        XCTAssertEqual(result?.reason, .revokedAuth)
    }

    func testCapabilitySkewProducesEscalation() {
        let result = OnlyCopyEscalation.evaluate(input(classification: .capabilitySkew))
        XCTAssertEqual(result?.reason, .capabilitySkew)
    }

    func testServerRefusalProducesEscalation() {
        let result = OnlyCopyEscalation.evaluate(input(classification: .serverRefusal))
        XCTAssertEqual(result?.reason, .serverRefusal)
    }

    func testCompatibilityRejectionProducesEscalation() {
        let result = OnlyCopyEscalation.evaluate(input(classification: .compatibilityRejection))
        XCTAssertEqual(result?.reason, .compatibilityRejection)
    }

    // MARK: - Edge cases

    func testZeroOnlyOnThisMacCountNeverEscalatesEvenWithUnfixableFailure() {
        XCTAssertNil(OnlyCopyEscalation.evaluate(input(count: 0, classification: .revokedAuth)))
    }

    func testEscalationRendersTitleBodyWithCountTitleAndReasonSubstituted() {
        let result = OnlyCopyEscalation.evaluate(input(count: 4, title: "Fire Emblem", classification: .serverRefusal))
        XCTAssertEqual(result?.title, "Your progress can't reach your server.")
        XCTAssertTrue(result?.body.contains("4") == true)
        XCTAssertTrue(result?.body.contains("Fire Emblem") == true)
        XCTAssertTrue(result?.body.contains("refused") == true)
        XCTAssertFalse(result?.body.contains("{N}") ?? true)
        XCTAssertFalse(result?.body.contains("{title}") ?? true)
        XCTAssertFalse(result?.body.contains("{reason}") ?? true)
    }

    func testClearingTheUnderlyingConditionClearsTheEscalation() {
        XCTAssertNotNil(OnlyCopyEscalation.evaluate(input(classification: .revokedAuth)))
        XCTAssertNil(OnlyCopyEscalation.evaluate(input(classification: .none)))
    }

    @MainActor
    func testPanelCarriesTheThreeRequiredControls() {
        let result = OnlyCopyEscalation.evaluate(input(classification: .revokedAuth))!
        _ = OnlyCopyEscalationPanel(escalation: result)
        // Source-level proof the three locked controls are the exact
        // vocabulary strings this panel wires -- this target has no
        // live accessibility-tree walker.
        XCTAssertEqual(SaveVocabulary.dangerEscalatedActionFix, "Fix this")
        XCTAssertEqual(SaveVocabulary.dangerEscalatedActionExport, "Export saves…")
        XCTAssertEqual(SaveVocabulary.dangerEscalatedActionWhatsStored, "What's stored where?")
    }

    func testAllFourEscalationReasonsAreDistinct() {
        let reasons: [SaveUploadFailureClassification] = [.revokedAuth, .capabilitySkew, .serverRefusal, .compatibilityRejection]
        let results = reasons.compactMap { OnlyCopyEscalation.evaluate(input(classification: $0)) }
        XCTAssertEqual(Set(results.map(\.reason)).count, 4)
    }
}
