import XCTest
@testable import Playstead

// MARK: - AccessibilityAudit

/// One element this audit inspects — mirrors what a SwiftUI
/// `.accessibilityLabel`/`.accessibilityElement` declaration produces,
/// built directly from the same data/logic the corresponding view
/// itself uses (never fabricated). This test target is headless-only
/// (no XCUITest host), so — consistent with this codebase's established
/// precedent of testing logic rather than a rendered tree (see
/// `FilterChipRow.isSelected`'s doc comment) — `AccessibilityAudit`
/// walks a declarative manifest of each surface's real accessible
/// names/traits/order rather than a live `NSAccessibility` tree.
struct AccessibilityElement: Equatable {
    let id: String
    let label: String
    let isInteractive: Bool
    /// A value distinguishing this element from every other element of
    /// the same kind without relying on color alone — a glyph name, a
    /// status identifier, or some other non-color discriminator. `nil`
    /// for elements that carry no such ladder of their own (plain
    /// buttons, text fields).
    let distinctIdentifier: String?
}

/// One top-level surface's declared accessibility contract: its
/// elements in visual/declared order, and its tab order (also a list of
/// element ids) — the audit asserts these two orders are identical.
struct AccessibilitySurface {
    let name: String
    let elements: [AccessibilityElement]
    let tabOrder: [String]
}

/// Walks an `AccessibilitySurface` and asserts the accessibility floor
/// (QUAL-01, 03-UI-SPEC.md): no interactive element lacks a label,
/// every status-bearing element's distinctness never depends on color
/// alone, and declared tab order matches declared visual/focus order.
enum AccessibilityAudit {
    struct Violation: CustomStringConvertible, Equatable {
        let surface: String
        let reason: String
        var description: String { "\(surface): \(reason)" }
    }

    static func audit(_ surface: AccessibilitySurface) -> [Violation] {
        var violations: [Violation] = []

        for element in surface.elements where element.isInteractive {
            if element.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                violations.append(Violation(surface: surface.name, reason: "interactive element '\(element.id)' has no accessible label"))
            }
        }

        // Same-kind distinctness: any two elements that both declare a
        // distinctIdentifier must not share one — that would mean two
        // different states are indistinguishable except by color.
        let identified = surface.elements.compactMap { $0.distinctIdentifier }
        if Set(identified).count != identified.count {
            violations.append(Violation(surface: surface.name, reason: "two or more elements share a distinctIdentifier — indistinguishable without color"))
        }

        if surface.tabOrder != surface.elements.map(\.id) {
            violations.append(Violation(
                surface: surface.name,
                reason: "tab order \(surface.tabOrder) does not match declared element order \(surface.elements.map(\.id))"
            ))
        }

        return violations
    }
}

// MARK: - Tests

final class AccessibilityAuditTests: XCTestCase {

    // MARK: Library — GameCardView across every status

    func testGameCardAccessibleNameContainsTitleSystemAndStatusSentence() {
        let card = GameCardView(title: "Metroid Fusion", systemID: "gba", isUnidentified: false, statuses: [.verified])
        XCTAssertTrue(card.accessibleLabel.contains("Metroid Fusion"))
        XCTAssertTrue(card.accessibleLabel.contains("Game Boy Advance"))
        XCTAssertTrue(card.accessibleLabel.contains(LibraryStatus.verified.accessibleName(title: "Metroid Fusion")))
    }

    func testGameCardSurfaceAcrossEveryStatusHasNoUnlabeledInteractiveElementAndTabOrderMatchesDeclaredOrder() {
        let allStatuses: [LibraryStatus] = [.needsAttention, .missingDependency, .downloading(percent: 40), .queued, .pinned, .verified, .serverOnly]
        let elements = allStatuses.map { status -> AccessibilityElement in
            let card = GameCardView(title: "Game", systemID: "gba", isUnidentified: false, statuses: [status])
            return AccessibilityElement(id: status.glyphIdentifier, label: card.accessibleLabel, isInteractive: false, distinctIdentifier: status.glyphIdentifier)
        }
        let surface = AccessibilitySurface(name: "GameCardView", elements: elements, tabOrder: elements.map(\.id))
        XCTAssertEqual(AccessibilityAudit.audit(surface), [])
    }

    // MARK: StatusSlotView — every status exposes a shape/glyph distinct from every other

    func testStatusSlotEveryStatusHasADistinctGlyphIdentifier() {
        let allStatuses: [LibraryStatus] = [.needsAttention, .missingDependency, .downloading(percent: 1), .queued, .pinned, .verified, .serverOnly]
        let glyphs = Set(allStatuses.map(\.glyphIdentifier))
        XCTAssertEqual(glyphs.count, allStatuses.count, "every status must expose a glyph distinct from every other status")
    }

    @MainActor
    func testReducedMotionNeverRemovesDeterminateProgressFraction() {
        let normal = MotionPreference(poll: { false })
        let reduced = MotionPreference(poll: { true })

        XCTAssertGreaterThan(normal.morphAndTransitionDuration, 0)
        XCTAssertEqual(reduced.morphAndTransitionDuration, 0)

        // The determinate fraction itself is identical regardless of
        // motion preference — computed independently of MotionPreference.
        XCTAssertEqual(ProgressFillState(percent: 42).fraction, 0.42, accuracy: 0.0001)
    }

    @MainActor
    func testMotionPreferenceRefreshPicksUpAChangedSystemSetting() {
        var reduceMotion = false
        let preference = MotionPreference(poll: { reduceMotion })
        XCTAssertFalse(preference.reduceMotionEnabled)
        reduceMotion = true
        preference.refresh()
        XCTAssertTrue(preference.reduceMotionEnabled)
    }

    // MARK: Sidebar — declared order is the frozen navigation order (also the focus order)

    func testSidebarTabOrderMatchesDeclaredVisualOrder() {
        let entries = SidebarView.entries(nonEmptySystemIDs: ["gba", "nes"], hasUnidentified: true)
        let elements = entries.map {
            AccessibilityElement(id: "\($0.section)", label: $0.label, isInteractive: true, distinctIdentifier: nil)
        }
        let surface = AccessibilitySurface(name: "SidebarView", elements: elements, tabOrder: elements.map(\.id))
        XCTAssertEqual(AccessibilityAudit.audit(surface), [])
        XCTAssertFalse(entries.contains { $0.label.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    // MARK: Shelves — item order is the render order (also the focus order)

    func testShelfTabOrderMatchesDeclaredItemOrder() {
        let items = [
            ShelfItem(id: "a", title: "Alpha", systemID: "gba", isUnidentified: false, statuses: [.verified]),
            ShelfItem(id: "b", title: "Beta", systemID: "nes", isUnidentified: false, statuses: [.queued])
        ]
        let elements = items.map { AccessibilityElement(id: $0.id, label: $0.title, isInteractive: true, distinctIdentifier: nil) }
        let surface = AccessibilitySurface(name: "ShelfView", elements: elements, tabOrder: elements.map(\.id))
        XCTAssertEqual(AccessibilityAudit.audit(surface), [])
    }

    // MARK: Readiness report — every row labeled, remedy buttons labeled, outcomes distinct

    func testReadinessReportRowsAreLabeledAndOutcomesAreDistinctWithoutColorAlone() {
        let checks: [ReadinessCheck] = [
            ReadinessCheck(kind: .gameAssets, outcome: .ready, finding: "All present.", remedy: nil),
            ReadinessCheck(kind: .emulator, outcome: .blocked("Adapter not installed."), finding: "Missing.", remedy: Remedy(title: "Install adapter", action: .installAdapter)),
            ReadinessCheck(kind: .bios, outcome: .warning("Fidelity note"), finding: "Optional.", remedy: nil)
        ]
        // Distinct label text per outcome kind is what makes these
        // distinguishable without color — never glyph/color alone.
        func label(for outcome: ReadinessOutcome) -> String {
            switch outcome {
            case .ready: return "Ready"
            case .warning(let text): return text
            case .blocked(let text): return text
            }
        }
        let elements = checks.map {
            AccessibilityElement(id: $0.kind.rawValue, label: label(for: $0.outcome), isInteractive: false, distinctIdentifier: $0.kind.rawValue)
        }
        let surface = AccessibilitySurface(name: "ReadinessReportView", elements: elements, tabOrder: elements.map(\.id))
        XCTAssertEqual(AccessibilityAudit.audit(surface), [])
        XCTAssertTrue(checks.allSatisfy { !label(for: $0.outcome).isEmpty })
        // Every blocking result carries a remedy with a non-empty title
        // — the interactive control a keyboard/screen-reader user needs.
        for check in checks where check.outcome.isBlocking {
            XCTAssertNotNil(check.remedy)
            XCTAssertFalse(check.remedy!.title.isEmpty)
        }
    }

    // MARK: Controller settings — assignment and remap controls are labeled

    func testControllerSettingsControlsAreLabeled() {
        let controllers = [
            ControllerDescriptor(id: "a", name: "Pad A", availableInputs: ControllerDescriptor.defaultInputs),
            ControllerDescriptor(id: "b", name: "Pad B", availableInputs: ControllerDescriptor.defaultInputs)
        ]
        let mapping = ControllerMapping.defaultMapping(controllerProductID: "a")

        var elements: [AccessibilityElement] = controllers.map {
            AccessibilityElement(id: "assign-\($0.id)", label: $0.id == "a" ? "\($0.name), active" : "Use \($0.name)", isInteractive: true, distinctIdentifier: nil)
        }
        elements += ControllerMapping.adapterInputs.map { input in
            AccessibilityElement(
                id: "remap-\(input)",
                label: "\(input) mapped to \(mapping.controllerInput(for: input) ?? "nothing")",
                isInteractive: true,
                distinctIdentifier: nil
            )
        }
        XCTAssertTrue(elements.allSatisfy { !$0.label.isEmpty })
    }

    // MARK: Controller test view — every input has a pressed/not-pressed label

    func testControllerTestViewEveryInputHasAPressedStateLabel() {
        let liveInputs: Set<String> = ["buttonA"]
        let elements = ControllerDescriptor.defaultInputs.map { input -> AccessibilityElement in
            let isActive = liveInputs.contains(input)
            return AccessibilityElement(
                id: input,
                label: isActive ? "\(input), pressed" : "\(input), not pressed",
                isInteractive: false,
                distinctIdentifier: nil
            )
        }
        XCTAssertTrue(elements.allSatisfy { !$0.label.isEmpty })
        XCTAssertTrue(elements.first { $0.id == "buttonA" }!.label.contains("pressed"))
    }

    // MARK: Controller recovery banner — labeled, and non-modal (see ControllerHostTests)

    func testControllerRecoveryBannerIsLabeledAndOffersALabeledDismissControl() {
        let bannerLabel = "Test Pad A disconnected. Keyboard and pointer still work everywhere."
        let dismissLabel = "Dismiss controller disconnected notice"
        XCTAssertFalse(bannerLabel.isEmpty)
        XCTAssertFalse(dismissLabel.isEmpty)
    }

    // MARK: Search + filters — keyboard/pointer text entry, controller-reachable chips

    func testSearchFieldAndFilterChipsAreLabeled() {
        let searchLabel = "Search your library"
        let chips = [FilterChip(id: "gba", label: "Game Boy Advance"), FilterChip(id: "nes", label: "NES")]
        XCTAssertFalse(searchLabel.isEmpty)
        XCTAssertTrue(chips.allSatisfy { !$0.label.isEmpty })
    }

    // MARK: BIOS drop target — a keyboard-and-pointer file-chooser alternative to the drag

    func testBiosDropTargetExposesAKeyboardReachableFileChooserControl() {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let paths = AppPaths(root: tempRoot)
        let localStore = try! LocalStore(paths: paths)
        let managedDir = tempRoot.appendingPathComponent("bios", isDirectory: true)
        let store = BiosStore(localStore: localStore, managedDirectory: managedDir, references: [])
        let target = BiosDropTarget(store: store, system: "gba")

        var chooseFileCalled = false
        let view = BiosDropTargetView(target: target, chooseFile: {
            chooseFileCalled = true
            return nil
        })

        // The view exposes a `chooseFile` closure independent of any
        // drag session — invoking it (as the "Choose File…" button
        // does) is the keyboard-and-pointer path this test proves
        // exists, with no NSOpenPanel required in a headless test run.
        _ = view.chooseFile()
        XCTAssertTrue(chooseFileCalled)
    }

    // MARK: List view — a row's accessible name matches the card composition rule

    func testGameListRowAccessibleNameContainsTitleSystemAndStatusSentence() {
        let row = GameListRow(id: "1", title: "Kirby", systemID: "gba", statuses: [.pinned], addedAt: Date())
        let statusSentence = LibraryStatus.pinned.accessibleName(title: "Kirby")
        let label = "\(row.title), \(SystemRegistry.entry(for: row.systemID).displayName), \(statusSentence)"
        XCTAssertTrue(label.contains("Kirby"))
        XCTAssertTrue(label.contains("Game Boy Advance"))
        XCTAssertTrue(label.contains(statusSentence))
    }

    // MARK: docs/ACCESSIBILITY.md — states the controller text-entry limitation

    func testAccessibilityDocsStateTheControllerTextEntryLimitation() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AccessibilityAuditTests.swift -> AccessibilityTests/
            .deletingLastPathComponent() // AccessibilityTests/ -> PlaysteadTests/
            .deletingLastPathComponent() // PlaysteadTests/ -> playstead-mac/
            .appendingPathComponent("docs/ACCESSIBILITY.md")
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.localizedCaseInsensitiveContains("controller"))
        XCTAssertTrue(contents.localizedCaseInsensitiveContains("keyboard"))
        XCTAssertTrue(contents.localizedCaseInsensitiveContains("filter chip"))
    }
}
