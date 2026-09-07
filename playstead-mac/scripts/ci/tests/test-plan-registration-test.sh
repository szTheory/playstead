#!/usr/bin/env bash
# A test no plan runs is a test that does not exist.
#
# The UI and Rendering plans enumerate `selectedTests` by name, so a newly added
# suite is invisible by default -- it compiles, it reads as registered, and it
# never executes. Phase 04 is the cautionary case: the whole UI layer sat
# deferred behind 583 green unit tests, and its first real execution found five
# production defects across three suites at once.
#
# This guard makes that impossible to repeat quietly: every `func test...` on
# disk must be selected by some plan, or be listed with a reason in
# TestPlans/unregistered-allowlist.txt.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
detector="${SCRIPT_DIR}/test-plan-registration-detector.py"

python3 "$detector" "$MAC_ROOT" || exit 1

fixture="$(mktemp -d "${TMPDIR:-/tmp}/playstead-plan-reg.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/TestPlans" "$fixture/PlaysteadTests" "$fixture/PlaysteadUITests"
cat >"$fixture/TestPlans/UI.xctestplan" <<'JSON'
{ "configurations": [], "defaultOptions": {}, "testTargets": [
  { "selectedTests": ["RegisteredTests"],
    "target": { "containerPath": "container:X.xcodeproj", "identifier": "1", "name": "PlaysteadUITests" } },
  { "target": { "containerPath": "container:X.xcodeproj", "identifier": "2", "name": "PlaysteadTests" } }
], "version": 1 }
JSON
cat >"$fixture/PlaysteadTests/RegisteredUnitTests.swift" <<'SWIFT'
import XCTest
final class RegisteredUnitTests: XCTestCase {
    func testSomething() {}
}
SWIFT
cat >"$fixture/PlaysteadUITests/RegisteredTests.swift" <<'SWIFT'
import XCTest
final class RegisteredTests: XCTestCase {
    func testRegistered() {}
}
SWIFT

# Baseline: a fully registered fixture must pass, or the guard is unsatisfiable.
python3 "$detector" "$fixture" >/dev/null || {
  printf 'registration detector rejected a fully registered fixture\n' >&2
  exit 1
}

# Negative control 1: a suite no plan names must be rejected.
cat >"$fixture/PlaysteadUITests/OrphanTests.swift" <<'SWIFT'
import XCTest
final class OrphanTests: XCTestCase {
    func testNobodyRunsMe() {}
}
SWIFT
if python3 "$detector" "$fixture" >/dev/null 2>&1; then
  printf 'registration detector accepted a suite no plan runs\n' >&2
  exit 1
fi

# ...and the allowlist must be the only way to silence it.
printf 'PlaysteadUITests/OrphanTests/testNobodyRunsMe()  # deliberate\n' \
  >"$fixture/TestPlans/unregistered-allowlist.txt"
python3 "$detector" "$fixture" >/dev/null || {
  printf 'registration detector ignored its own allowlist\n' >&2
  exit 1
}

# Negative control 2: an empty sweep must fail rather than report clean.
rm -rf "$fixture/PlaysteadUITests" && mkdir -p "$fixture/PlaysteadUITests"
if python3 "$detector" "$fixture" >/dev/null 2>&1; then
  printf 'registration detector reported clean on an empty target\n' >&2
  exit 1
fi

printf 'test plan registration contract: passed\n'
