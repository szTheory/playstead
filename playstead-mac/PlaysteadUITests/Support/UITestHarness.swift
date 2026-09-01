import XCTest

@MainActor
final class UITestHarness {
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

    let app: XCUIApplication
    private(set) var identifierTrace: [String] = []

    init(profile: String) {
        app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["PLAYSTEAD_UI_TEST_PROFILE"] = profile
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
        app.typeKey(.tab, modifierFlags: [])
        assertExactlyOneFocusedAction(expected: expected[0])

        for previous in expected.reversed().dropLast() {
            app.typeKey(.tab, modifierFlags: [.shift])
            assertExactlyOneFocusedAction(expected: previous)
        }

        let activationTarget = element(identifier, type: .button)
        XCTAssertTrue(hasKeyboardFocus(activationTarget), "activation target did not own focus")
        app.typeKey(.space, modifierFlags: [])
        identifierTrace.append(identifier)
    }

    func audit(_ targets: [AuditTarget], exclusions: [AuditExclusion] = []) throws {
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

        let exclusionsByFingerprint = Dictionary(uniqueKeysWithValues: exclusions.map { ($0.fingerprint, $0) })
        var matched = Set<String>()
        try app.performAccessibilityAudit(for: .all) { issue in
            let fingerprint = "\(issue.auditType.rawValue)|\(issue.element?.identifier ?? "")"
            guard let exclusion = exclusionsByFingerprint[fingerprint],
                  issue.element?.identifier == exclusion.identifier,
                  !exclusion.rationale.isEmpty else { return false }
            matched.insert(fingerprint)
            return true
        }
        XCTAssertEqual(matched, Set(exclusionsByFingerprint.keys), "stale or over-broad audit exclusion")
    }

    func assertSheetFocusContained(rootIdentifier: String) {
        let root = element(rootIdentifier)
        XCTAssertTrue(root.waitForExistence(timeout: 5))
        let focused = app.buttons.matching(NSPredicate(format: "hasKeyboardFocus == true")).allElementsBoundByIndex
        XCTAssertEqual(focused.count, 1, "a presented sheet must have exactly one focused action")
        XCTAssertTrue(root.descendants(matching: .button).allElementsBoundByIndex.contains(where: { $0 == focused[0] }))
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
