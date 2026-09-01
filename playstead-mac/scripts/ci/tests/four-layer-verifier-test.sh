#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFIER="${SCRIPT_DIR}/../run-mac-verification.sh"
MAC_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/playstead-layer-verifier.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

PASS_COUNT=0
FAIL_COUNT=0

expect_pass() {
  local name="$1"
  shift
  if "$@" >"$TMP_ROOT/${name}.out" 2>"$TMP_ROOT/${name}.err"; then
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    printf 'FAIL: %s unexpectedly failed\n' "$name" >&2
    cat "$TMP_ROOT/${name}.err" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

expect_fail() {
  local name="$1"
  shift
  if "$@" >"$TMP_ROOT/${name}.out" 2>"$TMP_ROOT/${name}.err"; then
    printf 'FAIL: %s unexpectedly passed\n' "$name" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    PASS_COUNT=$((PASS_COUNT + 1))
  fi
}

write_fixture() {
  local path="$1"
  local result="${2:-Passed}"
  local duplicates="${3:-1}"
  python3 - "$path" "$result" "$duplicates" <<'PY'
import json, sys
path, result, duplicates = sys.argv[1:]
case = {
    "nodeType": "Test Case",
    "nodeIdentifier": "KeychainScopingTests/testScopedMatchQueryRestrictsSearchWithoutSelectingAnAddDestination()",
    "name": "testScopedMatchQueryRestrictsSearchWithoutSelectingAnAddDestination()",
    "result": result,
}
non_required_failure = {
    "nodeType": "Test Case",
    "nodeIdentifier": "SurfaceAccessibilityTests/testSyntheticFailure()",
    "name": "testSyntheticFailure()",
    "result": "Failed",
    "children": [
        {
            "nodeType": "Failure Message",
            "name": "SurfaceAccessibilityTests.swift:137: XCTAssertTrue failed: private runtime values are deliberately discarded - PLAYSTEAD_A11Y_ISSUES[parentChild]=playstead.surface.library@role-3,unidentified@role-64",
            "result": "Failed",
        }
    ],
}
data = {
    "testPlanConfigurations": [],
    "devices": [],
    "testNodes": [{"nodeType": "Test Plan", "name": "Unit", "children": [case] * int(duplicates) + [non_required_failure]}],
}
json.dump(data, open(path, "w"))
PY
}

verify_fixture() {
  "$VERIFIER" --verify-layer-result "$1" unit "$TMP_ROOT/summary.json" \
    --required-test PlaysteadTests.KeychainScopingTests/testScopedMatchQueryRestrictsSearchWithoutSelectingAnAddDestination
}

valid="$TMP_ROOT/valid.json"
write_fixture "$valid"
expect_pass valid verify_fixture "$valid"
python3 - "$TMP_ROOT/summary.json" <<'PY'
import json, pathlib, sys
summary = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert summary["failed_test_count"] == 1
assert summary["failed_tests_truncated"] is False
assert summary["failed_tests"] == [{"identifier": "SurfaceAccessibilityTests/testSyntheticFailure()", "outcome": "failed"}]
assert summary["failure_diagnostic_count"] == 1
assert summary["failure_diagnostics_truncated"] is False
assert summary["failure_diagnostics"] == [{
    "test_identifier": "SurfaceAccessibilityTests/testSyntheticFailure()",
    "assertion": "XCTAssertTrue",
    "source_file": "PlaysteadUITests/SurfaceAccessibilityTests.swift",
    "source_line": 137,
}]
assert summary["audit_issue_count"] == 2
assert summary["audit_issues_truncated"] is False
assert summary["audit_issues"] == [
    {"test_identifier": "SurfaceAccessibilityTests/testSyntheticFailure()", "category": "parentChild", "element_identifier": "playstead.surface.library", "element_role": "role-3"},
    {"test_identifier": "SurfaceAccessibilityTests/testSyntheticFailure()", "category": "parentChild", "element_identifier": "unidentified", "element_role": "role-64"},
]
assert set(summary) == {"schema_version", "layer", "executed_test_count", "required_tests", "failed_test_count", "failed_tests_truncated", "failed_tests", "failure_diagnostic_count", "failure_diagnostics_truncated", "failure_diagnostics", "audit_issue_count", "audit_issues_truncated", "audit_issues"}
PY
PASS_COUNT=$((PASS_COUNT + 1))

build_log="$TMP_ROOT/build.log"
printf '%s:137:9: error: Bearer private-token /Users/private/game.rom must remain raw only\n' \
  "$MAC_ROOT/PlaysteadUITests/SurfaceAccessibilityTests.swift" >"$build_log"
printf '%s\n' '/Users/private/Secret.swift:4:2: error: arbitrary path must be omitted' >>"$build_log"
expect_pass build_stdout "$VERIFIER" --print-build-diagnostics "$build_log" build
grep -Fx 'build: COMPILER_DIAGNOSTIC error PlaysteadUITests/SurfaceAccessibilityTests.swift:137' "$TMP_ROOT/build_stdout.out" >/dev/null || {
  printf 'FAIL: bounded compiler diagnostic was not printed exactly\n' >&2
  exit 1
}
if grep -E 'Bearer|private-token|/Users/|game\.rom|must remain raw' "$TMP_ROOT/build_stdout.out" >/dev/null; then
  printf 'FAIL: compiler diagnostic leaked raw message, value, or path\n' >&2
  exit 1
fi
PASS_COUNT=$((PASS_COUNT + 2))

bounded_build_log="$TMP_ROOT/bounded-build.log"
for line in $(seq 1 55); do
  printf '%s:%s:1: warning: token-%s /Users/private/%s.rom\n' \
    "$MAC_ROOT/PlaysteadUITests/SurfaceAccessibilityTests.swift" "$line" "$line" "$line" >>"$bounded_build_log"
done
expect_pass bounded_build_stdout "$VERIFIER" --print-build-diagnostics "$bounded_build_log" build
[ "$(grep -c '^build: COMPILER_DIAGNOSTIC ' "$TMP_ROOT/bounded_build_stdout.out")" -eq 50 ] || {
  printf 'FAIL: compiler diagnostic stdout exceeded its bound\n' >&2
  exit 1
}
grep -Fx 'build: COMPILER_DIAGNOSTICS_TRUNCATED shown=50 total=55' "$TMP_ROOT/bounded_build_stdout.out" >/dev/null || {
  printf 'FAIL: compiler diagnostic truncation was not explicit\n' >&2
  exit 1
}
if grep -E 'token-|/Users/|\.rom' "$TMP_ROOT/bounded_build_stdout.out" >/dev/null; then
  printf 'FAIL: bounded compiler summary leaked raw content\n' >&2
  exit 1
fi
PASS_COUNT=$((PASS_COUNT + 3))

diagnostic_stdout="$TMP_ROOT/diagnostic-stdout"
expect_pass diagnostic_stdout "$VERIFIER" --print-failure-diagnostics "$TMP_ROOT/summary.json" ui
grep -Fx 'ui: FAILURE_DIAGNOSTIC SurfaceAccessibilityTests/testSyntheticFailure() XCTAssertTrue PlaysteadUITests/SurfaceAccessibilityTests.swift:137' "$TMP_ROOT/diagnostic_stdout.out" >/dev/null || {
  printf 'FAIL: bounded hosted diagnostic was not printed exactly\n' >&2
  exit 1
}
if grep -E 'private runtime|/Users/|PLAYSTEAD_A11Y_ISSUES|message' "$TMP_ROOT/diagnostic_stdout.out" >/dev/null; then
  printf 'FAIL: hosted diagnostic leaked a raw message or path\n' >&2
  exit 1
fi
PASS_COUNT=$((PASS_COUNT + 2))

unsafe_stdout="$TMP_ROOT/unsafe-stdout.json"
python3 - "$TMP_ROOT/summary.json" "$unsafe_stdout" <<'PY'
import json, pathlib, sys
source, target = map(pathlib.Path, sys.argv[1:])
data = json.loads(source.read_text())
data["failure_diagnostics"][0]["message"] = "Bearer should-never-print"
target.write_text(json.dumps(data))
PY
expect_fail unsafe_stdout "$VERIFIER" --print-failure-diagnostics "$unsafe_stdout" ui
[ ! -s "$TMP_ROOT/unsafe_stdout.out" ] || { printf 'FAIL: malformed diagnostic produced stdout\n' >&2; exit 1; }
PASS_COUNT=$((PASS_COUNT + 1))

bounded_diagnostics="$TMP_ROOT/bounded-diagnostics.json"
python3 - "$bounded_diagnostics" <<'PY'
import json, sys
required = {"nodeType":"Test Case","nodeIdentifier":"KeychainScopingTests/testScopedMatchQueryRestrictsSearchWithoutSelectingAnAddDestination()","result":"Passed"}
failed = [{
    "nodeType":"Test Case", "nodeIdentifier":f"SyntheticSuite/testFailure{index}()", "result":"Failed",
    "failureSummaries":[{
        "message":"XCTAssertEqual failed: runtime payload discarded",
        "filePath":"/private/checkout/playstead-mac/PlaysteadUITests/SurfaceAccessibilityTests.swift",
        "line":index + 1,
    }],
} for index in range(55)]
json.dump({"testNodes":[{"nodeType":"Test Plan","children":[required, *failed]}]}, open(sys.argv[1], "w"))
PY
expect_pass bounded_diagnostics verify_fixture "$bounded_diagnostics"
python3 - "$TMP_ROOT/summary.json" <<'PY'
import json, pathlib, sys
summary = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert summary["failure_diagnostic_count"] == 55
assert summary["failure_diagnostics_truncated"] is True
assert len(summary["failure_diagnostics"]) == 50
assert all(set(record) == {"test_identifier", "assertion", "source_file", "source_line"} for record in summary["failure_diagnostics"])
PY
PASS_COUNT=$((PASS_COUNT + 1))

unsafe_diagnostic="$TMP_ROOT/unsafe-diagnostic.json"
python3 - "$unsafe_diagnostic" <<'PY'
import json, sys
required = {"nodeType":"Test Case","nodeIdentifier":"KeychainScopingTests/testScopedMatchQueryRestrictsSearchWithoutSelectingAnAddDestination()","result":"Passed"}
failed = {
    "nodeType":"Test Case", "nodeIdentifier":"SyntheticSuite/testUnsafeDiagnostic()", "result":"Failed",
    "failureSummaries":[{
        "message":"private filename.rom bearer token must never survive",
        "filePath":"/Users/private/Secret.swift", "lineNumber":9,
    }],
}
json.dump({"testNodes":[{"nodeType":"Test Plan","children":[required, failed]}]}, open(sys.argv[1], "w"))
PY
expect_pass unsafe_diagnostic verify_fixture "$unsafe_diagnostic"
python3 - "$TMP_ROOT/summary.json" <<'PY'
import json, pathlib, sys
summary = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert summary["failure_diagnostic_count"] == 0
assert summary["failure_diagnostics"] == []
PY
PASS_COUNT=$((PASS_COUNT + 1))

unsafe_failure_message="$TMP_ROOT/unsafe-failure-message.json"
python3 - "$unsafe_failure_message" <<'PY'
import json, sys
required = {"nodeType":"Test Case","nodeIdentifier":"KeychainScopingTests/testScopedMatchQueryRestrictsSearchWithoutSelectingAnAddDestination()","result":"Passed"}
failed = {
    "nodeType":"Test Case", "nodeIdentifier":"SyntheticSuite/testUnsafeFailureMessage()", "result":"Failed",
    "children":[{
        "nodeType":"Failure Message",
        "name":"/Users/private/SurfaceAccessibilityTests.swift:137: XCTAssertTrue failed: Bearer secret-token private.rom",
        "result":"Failed",
    }],
}
json.dump({"testNodes":[{"nodeType":"Test Plan","children":[required, failed]}]}, open(sys.argv[1], "w"))
PY
expect_pass unsafe_failure_message verify_fixture "$unsafe_failure_message"
python3 - "$TMP_ROOT/summary.json" <<'PY'
import json, pathlib, sys
summary = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert summary["failure_diagnostic_count"] == 0
assert summary["failure_diagnostics"] == []
PY
PASS_COUNT=$((PASS_COUNT + 1))

for result in Failed Skipped unknown; do
  fixture="$TMP_ROOT/${result}.json"
  write_fixture "$fixture" "$result"
  expect_fail "result_${result}" verify_fixture "$fixture"
  [ -s "$TMP_ROOT/summary.json" ] || { printf 'FAIL: failing required test did not emit evidence\n' >&2; exit 1; }
done

bounded="$TMP_ROOT/bounded.json"
python3 - "$bounded" <<'PY'
import json, sys
required = {"nodeType":"Test Case","nodeIdentifier":"KeychainScopingTests/testScopedMatchQueryRestrictsSearchWithoutSelectingAnAddDestination()","result":"Passed"}
failed = [{"nodeType":"Test Case","nodeIdentifier":f"SyntheticSuite/testFailure{index}()","result":"Failed"} for index in range(55)]
json.dump({"testNodes":[{"nodeType":"Test Plan","children":[required, *failed]}]}, open(sys.argv[1], "w"))
PY
expect_pass bounded verify_fixture "$bounded"
python3 - "$TMP_ROOT/summary.json" <<'PY'
import json, pathlib, sys
summary = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert summary["failed_test_count"] == 55
assert summary["failed_tests_truncated"] is True
assert len(summary["failed_tests"]) == 50
PY
PASS_COUNT=$((PASS_COUNT + 1))

unsafe_identifier="$TMP_ROOT/unsafe-identifier.json"
python3 - "$unsafe_identifier" <<'PY'
import json, sys
json.dump({"testNodes":[{"nodeType":"Test Case","nodeIdentifier":"/Users/example/secret/testFailure()","result":"Failed"}]}, open(sys.argv[1], "w"))
PY
expect_fail unsafe_identifier verify_fixture "$unsafe_identifier"

duplicate="$TMP_ROOT/duplicate.json"
write_fixture "$duplicate" Passed 2
expect_fail duplicate verify_fixture "$duplicate"

zero="$TMP_ROOT/zero.json"
printf '%s\n' '{"testPlanConfigurations":[],"devices":[],"testNodes":[]}' >"$zero"
expect_fail zero verify_fixture "$zero"

missing="$TMP_ROOT/missing.json"
printf '%s\n' '{"testPlanConfigurations":[],"devices":[],"testNodes":[{"nodeType":"Test Plan","name":"Unit"}]}' >"$missing"
expect_fail missing verify_fixture "$missing"
expect_fail malformed verify_fixture /dev/null
expect_fail no_allowlist "$VERIFIER" --verify-layer-result "$valid" unit "$TMP_ROOT/no-allowlist.json"

if [ "$FAIL_COUNT" -ne 0 ]; then
  printf 'four-layer result verifier: %d check(s) failed\n' "$FAIL_COUNT" >&2
  exit 1
fi
printf 'four-layer result verifier: %d positive/negative checks passed\n' "$PASS_COUNT"
