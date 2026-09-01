import XCTest

@MainActor
final class UITestHarness {
    /// XCUITest is a separate target and cannot link the app target's
    /// `DeterministicProfile` type. Keep this mirror finite and pin its raw
    /// values against `UITestBootstrap` in the static source contract.
    enum Profile: String, CaseIterable {
        case emptyLibrary = "empty-library"
        case populatedCurationReorder = "populated-curation-reorder"
        case pausedActiveQueue = "paused-active-queue"
        case quotaBlockReclaim = "quota-block-reclaim"
        case storage = "storage"
    }

    struct AuditTarget {
        let identifier: String
        let elementType: XCUIElement.ElementType
        let requiresLabel: Bool
        let requiresValue: Bool

        init(
            _ identifier: String,
            type: XCUIElement.ElementType,
            requiresLabel: Bool = true,
            requiresValue: Bool = false
        ) {
            self.identifier = identifier
            self.elementType = type
            self.requiresLabel = requiresLabel
            self.requiresValue = requiresValue
        }
    }

    struct AuditExclusion {
        let identifier: String
        let fingerprint: String
        let rationale: String
    }

    enum AuditCategory: String, CaseIterable {
        case contrast
        case elementDetection
        case hitRegion
        case sufficientElementDescription
        case action
        case parentChild

        var xcuiType: XCUIAccessibilityAuditType {
            switch self {
            case .contrast: .contrast
            case .elementDetection: .elementDetection
            case .hitRegion: .hitRegion
            case .sufficientElementDescription: .sufficientElementDescription
            case .action: .action
            case .parentChild: .parentChild
            }
        }
    }

    let app: XCUIApplication
    private(set) var identifierTrace: [String] = []

    init(profile: Profile) {
        app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        // These literals intentionally mirror `UITestBootstrap.modeKey` and
        // `.profileKey`: the UI-test target cannot link app-internal constants.
        // Both are required. A profile name alone must never fall through to
        // `ProductionRootView` and its login-Keychain composition.
        app.launchEnvironment["PLAYSTEAD_UI_TESTING"] = "1"
        app.launchEnvironment["PLAYSTEAD_UI_TEST_PROFILE"] = profile.rawValue
    }

    func launch(settledAt identifier: String, timeout: TimeInterval = 15) {
        app.launch()
        let sentinel = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(sentinel.waitForExistence(timeout: timeout), "settled sentinel was not reached: \(identifier)")
        XCTAssertEqual(app.state, .runningForeground)
        identifierTrace.append(identifier)
    }

    func element(_ identifier: String, type: XCUIElement.ElementType = .any) -> XCUIElement {
        app.descendants(matching: type)[identifier]
    }

    func require(_ identifiers: [String]) {
        XCTAssertFalse(identifiers.isEmpty, "surface inventory must be independently nonempty")
        for identifier in identifiers {
            XCTAssertTrue(element(identifier).waitForExistence(timeout: 5), "missing production identifier: \(identifier)")
            identifierTrace.append(identifier)
        }
    }

    func traverseExactFocusSequence(_ identifiers: [String], activate identifier: String) {
        XCTAssertFalse(identifiers.isEmpty, "focus order must be test-owned and nonempty")
        let expected = identifiers.map { element($0, type: .button) }
        for target in expected { XCTAssertTrue(target.waitForExistence(timeout: 5)) }

        var foundStart = false
        for _ in 0..<24 {
            app.typeKey(.tab, modifierFlags: [])
            if hasKeyboardFocus(expected[0]) { foundStart = true; break }
        }
        XCTAssertTrue(foundStart, "Tab never reached the independently declared first control")
        assertExactlyOneFocusedAction(expected: expected[0])

        for next in expected.dropFirst() {
            app.typeKey(.tab, modifierFlags: [])
            assertExactlyOneFocusedAction(expected: next)
        }
        var wrappedForward = false
        for _ in 0..<24 {
            app.typeKey(.tab, modifierFlags: [])
            if hasKeyboardFocus(expected[0]) { wrappedForward = true; break }
            XCTAssertFalse(expected.dropFirst().contains(where: hasKeyboardFocus), "focus sequence wrapped to the wrong declared control")
        }
        XCTAssertTrue(wrappedForward, "focus sequence did not wrap to its first declared control")
        assertExactlyOneFocusedAction(expected: expected[0])

        var wrappedReverse = false
        for _ in 0..<24 {
            app.typeKey(.tab, modifierFlags: [.shift])
            if hasKeyboardFocus(expected[expected.count - 1]) { wrappedReverse = true; break }
            XCTAssertFalse(expected.dropLast().contains(where: hasKeyboardFocus), "reverse focus sequence reached the wrong declared control")
        }
        XCTAssertTrue(wrappedReverse, "reverse focus sequence did not wrap to its last declared control")
        assertExactlyOneFocusedAction(expected: expected[expected.count - 1])

        let activationTarget = element(identifier, type: .button)
        guard let activationIndex = identifiers.firstIndex(of: identifier) else {
            return XCTFail("activation target is not part of the test-owned focus sequence")
        }
        var foundActivationTarget = hasKeyboardFocus(activationTarget)
        var nextDeclaredIndex = 0
        for _ in 0..<24 where !foundActivationTarget {
            app.typeKey(.tab, modifierFlags: [])
            let focusedDeclared = expected.indices.filter { hasKeyboardFocus(expected[$0]) }
            if !focusedDeclared.isEmpty {
                XCTAssertEqual(
                    focusedDeclared,
                    [nextDeclaredIndex],
                    "activation search crossed declared controls out of cyclic order"
                )
                if focusedDeclared[0] == activationIndex {
                    foundActivationTarget = true
                    break
                }
                nextDeclaredIndex = (nextDeclaredIndex + 1) % expected.count
            }
        }
        XCTAssertTrue(foundActivationTarget, "activation target was absent from the exact focus sequence")
        assertExactlyOneFocusedAction(expected: activationTarget)
        XCTAssertTrue(hasKeyboardFocus(activationTarget), "activation target did not own focus")
        app.typeKey(.space, modifierFlags: [])
        identifierTrace.append(identifier)
    }

    func validateSemanticTargets(_ targets: [AuditTarget]) {
        XCTAssertFalse(targets.isEmpty, "live audit inventory must be independently nonempty")
        for target in targets {
            let element = element(target.identifier, type: target.elementType)
            XCTAssertTrue(element.waitForExistence(timeout: 5), "audit target missing: \(target.identifier)")
            XCTAssertEqual(element.elementType, target.elementType, "role drift: \(target.identifier)")
            if target.requiresLabel { XCTAssertFalse(element.label.isEmpty, "empty label: \(target.identifier)") }
            if target.requiresValue { XCTAssertFalse((element.value as? String ?? "").isEmpty, "empty value: \(target.identifier)") }
            let frame = element.frame
            XCTAssertTrue(frame.width > 0 && frame.height > 0 && frame.isFinite, "invalid frame: \(target.identifier)")
            identifierTrace.append(target.identifier)
        }
    }

    func audit(_ category: AuditCategory, exclusions: [AuditExclusion] = []) throws {
        let exclusionsByFingerprint = Dictionary(uniqueKeysWithValues: exclusions.map { ($0.fingerprint, $0) })
        var matched = Set<String>()
        var issueIdentifiers = Set<String>()
        try app.performAccessibilityAudit(for: category.xcuiType) { issue in
            let fingerprint = "\(issue.auditType.rawValue)|\(issue.element?.identifier ?? "")"
            if let exclusion = exclusionsByFingerprint[fingerprint],
               issue.element?.identifier == exclusion.identifier,
               !exclusion.rationale.isEmpty {
                matched.insert(fingerprint)
                return true
            }
            let rawIdentifier = issue.element?.identifier ?? ""
            let allowedIdentifierCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
            let hasSourceControlledPrefix = rawIdentifier.hasPrefix("playstead.") || rawIdentifier.hasPrefix("library.")
            let hasOnlyAllowedCharacters = rawIdentifier.unicodeScalars.allSatisfy(allowedIdentifierCharacters.contains)
            let boundedIdentifier = hasSourceControlledPrefix && hasOnlyAllowedCharacters
                ? rawIdentifier
                : "unidentified"
            let boundedRole = "role-\(issue.element?.elementType.rawValue ?? 0)"
            if issueIdentifiers.count < 50 {
                issueIdentifiers.insert("\(boundedIdentifier)@\(boundedRole)")
            }
            // Collect only bounded source-controlled identity, then fail below.
            // Returning true here suppresses XCTest's raw issue text/attachments,
            // never the acceptance assertion that the issue set is empty.
            return true
        }
        XCTAssertEqual(matched, Set(exclusionsByFingerprint.keys), "stale or over-broad audit exclusion")
        XCTAssertTrue(
            issueIdentifiers.isEmpty,
            "PLAYSTEAD_A11Y_ISSUES[\(category.rawValue)]=\(issueIdentifiers.sorted().joined(separator: ","))"
        )
    }

    func assertSheetFocusContained(rootIdentifier: String) {
        let root = element(rootIdentifier)
        XCTAssertTrue(root.waitForExistence(timeout: 5))
        let descendantIDs = Set(
            root.descendants(matching: .button).allElementsBoundByIndex
                .map(\.identifier)
                .filter { !$0.isEmpty }
        )
        XCTAssertFalse(descendantIDs.isEmpty, "sheet must expose at least one identified action")

        for _ in 0..<24 {
            let focused = app.buttons.matching(NSPredicate(format: "hasKeyboardFocus == true")).allElementsBoundByIndex
            if focused.count == 1, descendantIDs.contains(focused[0].identifier) {
                identifierTrace.append(rootIdentifier)
                return
            }
            app.typeKey(.tab, modifierFlags: [])
        }
        XCTFail("keyboard focus escaped the presented sheet: \(rootIdentifier)")
    }

    /// Moves focus to one independently named action without assuming that a
    /// prior containment assertion happened to land on it. `typeKey` sends to
    /// the currently focused control on macOS; querying a different element
    /// does not transfer keyboard focus to that element.
    func focusContainedAction(_ identifier: String, rootIdentifier: String) {
        let root = element(rootIdentifier)
        let target = element(identifier, type: .button)
        XCTAssertTrue(root.waitForExistence(timeout: 5))
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        let descendantIDs = Set(
            root.descendants(matching: .button).allElementsBoundByIndex
                .map(\.identifier)
                .filter { !$0.isEmpty }
        )
        XCTAssertTrue(descendantIDs.contains(identifier), "requested action is outside the presented sheet")

        for _ in 0..<24 {
            let focused = app.buttons.matching(NSPredicate(format: "hasKeyboardFocus == true")).allElementsBoundByIndex
            XCTAssertLessThanOrEqual(focused.count, 1, "multiple sheet actions report keyboard focus")
            if focused.count == 1, focused[0].identifier == identifier {
                identifierTrace.append(identifier)
                return
            }
            if focused.count == 1 {
                XCTAssertTrue(descendantIDs.contains(focused[0].identifier), "keyboard focus escaped the presented sheet")
            }
            app.typeKey(.tab, modifierFlags: [])
        }
        XCTFail("Tab never reached the requested sheet action: \(identifier)")
    }

    func sanitizedTrace() -> String {
        identifierTrace.joined(separator: " -> ")
    }

    private func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
        element.value(forKey: "hasKeyboardFocus") as? Bool == true
    }

    private func assertExactlyOneFocusedAction(expected: XCUIElement) {
        let focused = app.buttons.matching(NSPredicate(format: "hasKeyboardFocus == true")).allElementsBoundByIndex
        XCTAssertEqual(focused.count, 1, "exactly one actionable element must own focus")
        XCTAssertTrue(hasKeyboardFocus(expected), "focus order diverged from the test-owned sequence")
    }
}

private extension CGRect {
    var isFinite: Bool {
        [origin.x, origin.y, width, height].allSatisfy(\.isFinite)
    }
}
