import XCTest

/// "The BIOS drop surface renders the store's exact no-blame rejection
/// reason as explanatory copy, never a blank pane and never a generic
/// failure string" (03-UAT.md checkpoint 45, plan 03-11 deliverable D7).
///
/// 03-11 flagged this as unverified in its own `planner_assumptions`:
/// `BiosDropTargetView.statusView` renders `BiosDropResult.rejected(reason:)`
/// as visible text *by code inspection*, but nothing drove the surface, so
/// "renders the exact reason" and "renders some string" were
/// indistinguishable. A blank pane and a generic "Something went wrong."
/// both pass code inspection.
///
/// This drives the real surface in the packaged app: the production
/// readiness route to the production BIOS view, the production
/// "Choose File…" control, the production `BiosStore` (built with
/// `BiosReferences.production` at the composition root), and reads the
/// rendered copy back off the accessibility tree.
///
/// The candidate file arrives through `UITestBiosCandidate`, a
/// `#if UI_TESTING` seam, because a headless XCUITest can drive neither a
/// drag session nor an `NSOpenPanel`.
@MainActor
final class BiosRejectionCopyTests: XCTestCase {
    private var harness: UITestHarness!
    private var candidateRoot: URL!

    /// The deterministic profiles seed `synthetic-system`, for which
    /// `BiosReferences.production` deliberately holds no reference — this
    /// product never fabricates one. So the store's honest reason for any
    /// candidate here is its missing-reference reason, and that exact
    /// sentence is what the surface must show.
    ///
    /// Mirrors `BiosStoreError.invalidCandidate(reason:)`'s literal and
    /// `BiosDropTarget.rejectionMessage(for:)`'s frame. The UI-test target
    /// cannot link app-internal types, so — like `UITestHarness.Profile`'s
    /// raw values — this is a pinned mirror, and
    /// `BiosTests.testRejectionMessageQuotesTheStoreReasonVerbatim` is the
    /// unit-level assertion that keeps the two from drifting.
    private let expectedCopy =
        "This file could not be validated — no known reference for this system yet."

    private let statusIdentifier = "playstead.readout.bios-status"

    override func setUpWithError() throws {
        continueAfterFailure = false
        candidateRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("playstead-bios-candidate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: candidateRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        harness?.app.terminate()
        harness = nil
        if let candidateRoot {
            try? FileManager.default.removeItem(at: candidateRoot)
        }
    }

    func testRejectedDropRendersTheStoresExactReasonAsVisibleCopy() throws {
        let candidate = candidateRoot.appendingPathComponent("candidate.bin")
        try Data(repeating: 0x5A, count: 2048).write(to: candidate)

        openBiosSurface(candidate: candidate)

        // Before any candidate is handled the surface is in `.idle` and
        // renders no status at all. Asserting that first is what makes the
        // assertion below a real state change rather than a string that was
        // always on screen.
        XCTAssertFalse(
            harness.app.descendants(matching: .any)[statusIdentifier].exists,
            "a status readout was present before any file was chosen"
        )

        harness.element(AccessibilityIdentifiers.chooseBios, type: .button).click()

        let status = harness.app.descendants(matching: .any)[statusIdentifier]
        XCTAssertTrue(
            status.waitForExistence(timeout: 5),
            "the BIOS surface rendered no status at all after a rejected candidate — a blank pane"
        )

        let rendered = status.readableText

        // Each clause on its own line: CI keeps file:line, not assertion
        // messages, so a single compound assertion would not say which half
        // of this checkpoint regressed.
        XCTAssertFalse(rendered.isEmpty, "the rejection copy is empty")
        XCTAssertEqual(rendered, expectedCopy)
        XCTAssertTrue(rendered.contains("no known reference for this system yet"))

        // Not a generic failure string. `rejectionMessage(for:)` falls back
        // to exactly this sentence for any non-`BiosStoreError`, so its
        // presence would mean the store's own reason was discarded.
        XCTAssertNotEqual(rendered, "This file could not be validated.")
    }

    func testAnUnusableCandidatePathLeavesTheSurfaceUntouchedRatherThanShowingAGenericFailure() throws {
        // A path outside the temporary root: `UITestBiosCandidate` refuses
        // it, so the view sees exactly what a cancelled `NSOpenPanel`
        // returns. A cancel must not fabricate a rejection.
        openBiosSurface(candidate: URL(fileURLWithPath: "/etc/hosts"))

        harness.element(AccessibilityIdentifiers.chooseBios, type: .button).click()

        let status = harness.app.descendants(matching: .any)[statusIdentifier]
        XCTAssertFalse(
            status.waitForExistence(timeout: 2),
            "cancelling the chooser produced a status readout: \(status.readableText)"
        )
    }

    // MARK: - Routing

    private func openBiosSurface(candidate: URL) {
        harness = UITestHarness(
            profile: .storage,
            extraEnvironment: ["PLAYSTEAD_UI_TEST_BIOS_CANDIDATE": candidate.path]
        )
        harness.launch(settledAt: AccessibilityIdentifiers.library)

        harness.element(AccessibilityIdentifiers.openReadiness, type: .button).click()
        harness.require([AccessibilityIdentifiers.readinessSurface])

        harness.element(AccessibilityIdentifiers.openBios, type: .button).click()
        harness.require([AccessibilityIdentifiers.biosSurface])
    }
}

/// The UI-test target cannot link the app target's
/// `AccessibilityIdentifiers`, so these mirror it, exactly as
/// `UITestHarness.Profile` mirrors `DeterministicProfile`.
private enum AccessibilityIdentifiers {
    static let library = "playstead.surface.library"
    static let readinessSurface = "playstead.surface.readiness"
    static let biosSurface = "playstead.surface.bios"
    static let openReadiness = "playstead.control.open-readiness"
    static let openBios = "playstead.control.open-bios"
    static let chooseBios = "playstead.control.choose-bios"
}
