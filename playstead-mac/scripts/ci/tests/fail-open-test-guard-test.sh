#!/usr/bin/env bash
# See fail-open-test-guard-detector.py: a bare early return inside a test body
# makes the test report success without asserting anything.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
detector="${SCRIPT_DIR}/fail-open-test-guard-detector.py"

python3 "$detector" "${MAC_ROOT}/PlaysteadUITests" "${MAC_ROOT}/PlaysteadTests" || exit 1

fixture="$(mktemp -d "${TMPDIR:-/tmp}/playstead-fail-open.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT

# Negative control: the exact shape that hid the save-upload 404.
cat >"$fixture/BadTests.swift" <<'SWIFT'
import XCTest
final class BadTests: XCTestCase {
    func testSomethingEndToEnd() throws {
        guard try runFixture("prepare") else { return }
        XCTAssertTrue(true)
    }
}
SWIFT
if python3 "$detector" "$fixture" >/dev/null 2>&1; then
  printf 'fail-open detector accepted a bare early return in a test body\n' >&2
  exit 1
fi

# Both prescribed forms must be accepted, and a helper (non-test) is untouched.
cat >"$fixture/BadTests.swift" <<'SWIFT'
import XCTest
final class GoodTests: XCTestCase {
    func testSomethingEndToEnd() throws {
        guard try runFixture("prepare") else { return XCTFail("prepare stage failed") }
        guard hasEnvironment else { throw XCTSkip("no live fixture in this environment") }
        XCTAssertTrue(true)
    }
    private func helper(_ x: Int?) {
        guard let x else { return }
        _ = x
    }
}
SWIFT
python3 "$detector" "$fixture" >/dev/null || {
  printf 'fail-open detector rejected XCTFail/XCTSkip or a plain helper\n' >&2
  exit 1
}

printf 'fail-open test guard contract: passed\n'
