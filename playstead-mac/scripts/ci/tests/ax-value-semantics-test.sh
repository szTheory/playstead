#!/usr/bin/env bash
# On macOS an AXStaticText carries its content in AXValue -- XCUITest's
# `.value`, and what VoiceOver speaks. `.label` maps to AXTitle/AXDescription,
# which a SwiftUI `Text` leaves EMPTY, and `.accessibilityLabel` on a `Text`
# does not change that (proved under G-04-2). A UI test written to iOS
# semantics therefore reads `.label` and silently compares against "".
#
# That cost three wrong diagnoses and three CI round trips in phase 04. This
# guard makes it a build-time error instead: read static text through
# `readableText` (UITestHarness.swift), and any predicate matched against a
# staticTexts query that mentions `label` must also mention `value`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

detector="${SCRIPT_DIR}/ax-value-detector.py"

python3 "$detector" "${MAC_ROOT}/PlaysteadUITests" || exit 1

# Negative control: the detector must reject the exact shape that shipped
# broken, or its clean verdict above means nothing.
fixture="$(mktemp -d "${TMPDIR:-/tmp}/playstead-ax-value.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
cat >"$fixture/BadTests.swift" <<'SWIFT'
import XCTest
final class BadTests: XCTestCase {
    func testReadsLabelOnStaticText() {
        let app = XCUIApplication()
        let result = app.staticTexts["playstead.some.result"]
        XCTAssertTrue(result.label.contains("Keeping both"))
    }
}
SWIFT
if python3 "$detector" "$fixture" >/dev/null 2>&1; then
  printf 'ax-value detector accepted a known-bad staticText .label read\n' >&2
  exit 1
fi

cat >"$fixture/BadPredicateTests.swift" <<'SWIFT'
import XCTest
final class BadPredicateTests: XCTestCase {
    func testMatchesOnLabelOnly() {
        let app = XCUIApplication()
        let p = NSPredicate(format: "label BEGINSWITH %@", "Ready")
        _ = app.staticTexts.matching(p)
    }
}
SWIFT
rm "$fixture/BadTests.swift"
if python3 "$detector" "$fixture" >/dev/null 2>&1; then
  printf 'ax-value detector accepted a label-only staticTexts predicate\n' >&2
  exit 1
fi

printf 'macOS AX value semantics in UI tests: passed\n'
