import XCTest
@testable import Playstead

/// Source-level reachability, in the same shape this codebase already uses
/// for WINDOWS #37/#45/#46 (see `SaveSessionCoordinatorTests
/// .testTheCoordinatorReimplementsNoCaptureLogic`): a pairing surface that
/// nothing opens is that window all over again. `LibraryShellView` must
/// actually present `PairingView`, and the empty state's long-standing
/// "Pair with your Playstead server" description string and its action
/// button must live in the same view — a string naming an action that
/// exists nowhere in the app is the literal defect WINDOWS #54 recorded.
final class PairingReachabilityTests: XCTestCase {
    private func readSource(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // PairingTests
            .deletingLastPathComponent() // PlaysteadTests
            .deletingLastPathComponent() // playstead-mac
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// `LibraryShellView` must construct `PairingView` for its `.pairing`
    /// shell surface — not merely declare the case.
    func testLibraryShellViewPresentsPairingView() throws {
        let source = try readSource("Playstead/Library/LibraryShellView.swift")
        XCTAssertTrue(
            source.contains("case .pairing:") && source.contains("PairingView()"),
            "LibraryShellView must route its .pairing surface to a real PairingView()"
        )
    }

    /// The empty state's description string and the button that presents
    /// pairing must be in the same view — reachable from the exact surface
    /// that has been advertising it since Phase 3.
    func testEmptyStateDescriptionAndPairingActionAreInTheSameView() throws {
        let source = try readSource("Playstead/Library/LibraryShellView.swift")
        XCTAssertTrue(
            source.contains("Pair with your Playstead server"),
            "the long-standing empty-state copy must still be present"
        )
        XCTAssertTrue(
            source.contains("presentedSurface = .pairing"),
            "the empty state must be able to open the pairing surface directly"
        )
    }

    /// A pairing surface reachable only from the empty state would strand
    /// an already-paired user who wants to re-pair against a new server —
    /// the app menu is the second reachable call site the plan requires.
    func testPlaysteadAppExposesAPairingMenuCommand() throws {
        let source = try readSource("Playstead/App/PlaysteadApp.swift")
        XCTAssertTrue(
            source.contains(".commands") && source.contains("presentPairingSheetRequested"),
            "the app must expose a menu command that can open pairing independent of the empty state"
        )
    }

    /// `AccessibilityIdentifiers.Surface.pairing` must actually be
    /// registered in `Surface.all`, which is what the cross-layer
    /// allowlist anchors check (`IdentityAndFocusPrimitiveTests`).
    func testPairingSurfaceIdentifierIsRegistered() {
        XCTAssertEqual(AccessibilityIdentifiers.Surface.pairing, "playstead.surface.pairing")
        XCTAssertTrue(AccessibilityIdentifiers.Surface.all.contains(AccessibilityIdentifiers.Surface.pairing))
    }

    /// Falsification check for the reachability claim itself: every
    /// `ShellSurface` case (including `.pairing`) must route to a
    /// non-empty title, matching `StorageShellWiringTests
    /// .testEveryShellSurfaceRoutesToATitledSurface`'s existing discipline.
    func testEveryShellSurfaceIncludingPairingRoutesToATitledSurface() {
        for surface in LibraryShellView.ShellSurface.allCases {
            XCTAssertFalse(LibraryShellView.title(for: surface).isEmpty)
        }
        XCTAssertTrue(LibraryShellView.ShellSurface.allCases.contains(.pairing))
    }
}
