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
    "durationInSeconds": 1.5,
}
non_required_failure = {
    "nodeType": "Test Case",
    "nodeIdentifier": "SurfaceAccessibilityTests/testSyntheticFailure()",
    "name": "testSyntheticFailure()",
    "result": "Failed",
    "durationInSeconds": 4.25,
    "children": [
        {
            "nodeType": "Failure Message",
            "name": "SurfaceAccessibilityTests.swift:137: XCTAssertTrue failed: private runtime values are deliberately discarded - PLAYSTEAD_A11Y_ISSUES[parentChild]=playstead.surface.library@role-3,unidentified@role-64 save-e2e-diagnostic=drain:sent_without_target_upload,classification:none,status:unavailable,api:unavailable,route:unavailable - PLAYSTEAD_LAYOUT_V1 kind=moveUp hittable=false element=(12,34,56,78) pane=(1,2,300,400) window=(0,0,1200,900) host=private-machine",
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
  local input="$1"
  shift
  "$VERIFIER" --verify-layer-result "$input" unit "$TMP_ROOT/summary.json" \
    --required-test PlaysteadTests.KeychainScopingTests/testScopedMatchQueryRestrictsSearchWithoutSelectingAnAddDestination "$@"
}

write_recovery_fixture() {
  local path="$1"
  local mode="${2:-passed}"
  python3 - "$path" "$mode" <<'PY'
import json, sys
path, mode = sys.argv[1:]
identifier = "ControllerNoHIDIntegrationTests/testSimulatedDetachShowsNonModalRecoveryAndPreservesFallback()"
nodes = []
if mode != "zero-discovery":
    if mode == "missing":
        nodes.append({"nodeType": "Test Case", "nodeIdentifier": "SurfaceAccessibilityTests/testUnrelatedContract()", "result": "Passed"})
    else:
        result = "Skipped" if mode == "skipped" else "Passed"
        nodes.append({"nodeType": "Test Case", "nodeIdentifier": identifier, "result": result})
        nodes.append({"nodeType": "Test Case", "nodeIdentifier": "SurfaceAccessibilityTests/testUnrelatedContract()", "result": "Passed"})
data = {"testNodes": [{"nodeType": "Test Plan", "children": nodes}]}
with open(path, "w", encoding="utf-8") as fixture:
    json.dump(data, fixture)
PY
}

verify_recovery_fixture() {
  "$VERIFIER" --verify-layer-result "$1" ui "$TMP_ROOT/recovery-summary.json" \
    --required-test PlaysteadUITests.ControllerNoHIDIntegrationTests/testSimulatedDetachShowsNonModalRecoveryAndPreservesFallback
}

write_mapping_lifecycle_fixture() {
  local path="$1"
  local mode="${2:-passed}"
  python3 - "$path" "$mode" <<'PY'
import json, sys
path, mode = sys.argv[1:]
identifier = "ControllerNoHIDIntegrationTests/testSimulatedControllerMappingLifecyclePersistsAndResets()"
nodes = []
if mode != "zero-discovery":
    if mode == "missing":
        nodes.append({"nodeType": "Test Case", "nodeIdentifier": "SurfaceAccessibilityTests/testUnrelatedContract()", "result": "Passed"})
    else:
        result = "Skipped" if mode == "skipped" else "Passed"
        nodes.append({"nodeType": "Test Case", "nodeIdentifier": identifier, "result": result})
data = {"testNodes": [{"nodeType": "Test Plan", "children": nodes}]}
with open(path, "w", encoding="utf-8") as fixture:
    json.dump(data, fixture)
PY
}

verify_mapping_lifecycle_fixture() {
  "$VERIFIER" --verify-layer-result "$1" ui "$TMP_ROOT/mapping-lifecycle-summary.json" \
    --required-test PlaysteadUITests.ControllerNoHIDIntegrationTests/testSimulatedControllerMappingLifecyclePersistsAndResets
}

write_zero_network_fixture() {
  local path="$1"
  local marker=missing
  if [ "$#" -gt 1 ]; then marker="$2"; fi
  python3 - "$path" "$marker" "$MAC_ROOT" <<'PY'
import json, pathlib, sys
path, marker, root = sys.argv[1:]
suffix = "" if marker == "missing" else " " + marker
message = (
    "ZeroNetworkPlayFlowTests.swift:57: XCTAssertNil failed: private exception "
    "/Users/private/Secret.gba Bearer synthetic-secret" + suffix
)
test_case = {
    "nodeType": "Test Case",
    "nodeIdentifier": "ZeroNetworkPlayFlowTests/testWholePlayFlowRecordsZeroHTTPRequests()",
    "name": "testWholePlayFlowRecordsZeroHTTPRequests()",
    "result": "Failed",
    "failureSummaries": [{
        "message": message,
        "filePath": str(pathlib.Path(root) / "PlaysteadUITests" / "ZeroNetworkPlayFlowTests.swift"),
        "lineNumber": 57,
    }],
}
data = {"testNodes": [{"nodeType": "Test Plan", "children": [test_case]}]}
pathlib.Path(path).write_text(json.dumps(data), encoding="utf-8")
PY
}

verify_zero_network_fixture() {
  local result="$1"
  "$VERIFIER" --verify-layer-result "$result" ui "$result.summary.json" \
    --required-test PlaysteadUITests.ZeroNetworkPlayFlowTests/testWholePlayFlowRecordsZeroHTTPRequests
}

valid="$TMP_ROOT/valid.json"
write_fixture "$valid"
expect_pass valid verify_fixture "$valid"

recovery_valid="$TMP_ROOT/recovery-valid.json"
write_recovery_fixture "$recovery_valid"
expect_pass recovery_valid verify_recovery_fixture "$recovery_valid"
mapping_lifecycle_valid="$TMP_ROOT/mapping-lifecycle-valid.json"
write_mapping_lifecycle_fixture "$mapping_lifecycle_valid"
expect_pass mapping_lifecycle_valid verify_mapping_lifecycle_fixture "$mapping_lifecycle_valid"
mapping_lifecycle_missing="$TMP_ROOT/mapping-lifecycle-missing.json"
write_mapping_lifecycle_fixture "$mapping_lifecycle_missing" missing
expect_fail mapping_lifecycle_missing verify_mapping_lifecycle_fixture "$mapping_lifecycle_missing"
mapping_lifecycle_skipped="$TMP_ROOT/mapping-lifecycle-skipped.json"
write_mapping_lifecycle_fixture "$mapping_lifecycle_skipped" skipped
expect_fail mapping_lifecycle_skipped verify_mapping_lifecycle_fixture "$mapping_lifecycle_skipped"
mapping_lifecycle_zero="$TMP_ROOT/mapping-lifecycle-zero-discovery.json"
write_mapping_lifecycle_fixture "$mapping_lifecycle_zero" zero-discovery
expect_fail mapping_lifecycle_zero verify_mapping_lifecycle_fixture "$mapping_lifecycle_zero"
recovery_missing="$TMP_ROOT/recovery-missing.json"
write_recovery_fixture "$recovery_missing" missing
expect_fail recovery_missing verify_recovery_fixture "$recovery_missing"
recovery_skipped="$TMP_ROOT/recovery-skipped.json"
write_recovery_fixture "$recovery_skipped" skipped
expect_fail recovery_skipped verify_recovery_fixture "$recovery_skipped"
recovery_zero="$TMP_ROOT/recovery-zero-discovery.json"
write_recovery_fixture "$recovery_zero" zero-discovery
expect_fail recovery_zero verify_recovery_fixture "$recovery_zero"

python3 - "$TMP_ROOT/summary.json" <<'PY'
import json, pathlib, sys
summary = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert summary["required_tests"][0]["identifier"] == "KeychainScopingTests/testScopedMatchQueryRestrictsSearchWithoutSelectingAnAddDestination()"
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
assert summary["save_upload_diagnostic_count"] == 1
assert summary["save_upload_diagnostics"] == [{
    "test_identifier": "SurfaceAccessibilityTests/testSyntheticFailure()",
    "drain_outcome": "sent_without_target_upload",
    "classification": "none",
    "http_status": None,
    "api_code": None,
    "server_route_status": "unavailable",
}]
assert summary["audit_issue_count"] == 2
assert summary["audit_issues_truncated"] is False
assert summary["audit_issues"] == [
    {"test_identifier": "SurfaceAccessibilityTests/testSyntheticFailure()", "category": "parentChild", "element_identifier": "playstead.surface.library", "element_role": "role-3"},
    {"test_identifier": "SurfaceAccessibilityTests/testSyntheticFailure()", "category": "parentChild", "element_identifier": "unidentified", "element_role": "role-64"},
]
assert summary["layout_diagnostic_count"] == 1
assert summary["layout_diagnostics_truncated"] is False
assert summary["layout_diagnostics"] == [{"kind":"moveUp","hittable":False,"element":[12,34,56,78],"pane":[1,2,300,400],"window":[0,0,1200,900]}]
# Per-test timings. Asserted by value, not merely by presence: a profiling
# field that silently reads 0 is worse than none, because the next person
# optimises against it. The fixture's two cases are 1.5s and 4.25s.
assert summary["timed_test_count"] == 2
assert summary["in_test_seconds_total"] == 5.8  # 5.75, rounded to one place
assert summary["slowest_tests"] == [
    {"identifier": "SurfaceAccessibilityTests/testSyntheticFailure()", "seconds": 4.25},
    {"identifier": "KeychainScopingTests/testScopedMatchQueryRestrictsSearchWithoutSelectingAnAddDestination()", "seconds": 1.5},
]
assert set(summary) == {"schema_version", "layer", "executed_test_count", "required_tests", "failed_test_count", "failed_tests_truncated", "failed_tests", "failure_diagnostic_count", "failure_diagnostics_truncated", "failure_diagnostics", "save_upload_diagnostic_count", "save_upload_diagnostics", "audit_issue_count", "audit_issues_truncated", "audit_issues", "in_test_seconds_total", "timed_test_count", "slowest_tests", "runner_process_error_count", "layout_diagnostic_count", "layout_diagnostics_truncated", "layout_diagnostics"}
PY
PASS_COUNT=$((PASS_COUNT + 1))

python3 - "$MAC_ROOT/Playstead/UITesting/UITestBootstrap.swift" \
  "$MAC_ROOT/PlaysteadUITests/ZeroNetworkPlayFlowTests.swift" <<'PY'
import pathlib, sys
bootstrap, test = (pathlib.Path(path).read_text() for path in sys.argv[1:])
test_section = test[test.index("func testWholePlayFlowRecordsZeroHTTPRequests"):test.index("\n    private enum ZeroNetworkPlayFlowStage")]
assert 'Set(result.keys) == Set(["recorded_request_count", "failure_stage"])' in test_section
assert "failure_reason" not in test_section and "failureReason" not in test_section
assert "failure_reason" not in bootstrap and "failureReason" not in bootstrap
assert "String(describing: error)" not in bootstrap
assert '"recorded_request_count": requestCount' in bootstrap
assert '"failure_stage": stageValue' in bootstrap
PY
PASS_COUNT=$((PASS_COUNT + 1))

zero_network_stages="unknown stand-in-installation adapter-selection adapter-host-acquisition synthetic-cas-catalogue-readiness materialization-save-setup adapter-launch bounded-exit unexpected-http-request"
for stage in $zero_network_stages; do
  fixture="$TMP_ROOT/zero-network-$stage.json"
  write_zero_network_fixture "$fixture" "zero-network-play-flow-stage=$stage"
  expect_fail "zero_network_$stage" verify_zero_network_fixture "$fixture"
  python3 - "$fixture.summary.json" "$stage" <<'PY'
import json, pathlib, sys
summary = json.loads(pathlib.Path(sys.argv[1]).read_text())
expected = sys.argv[2]
records = summary["failure_diagnostics"]
assert len(records) == 1
assert records[0] == {
    "test_identifier": "ZeroNetworkPlayFlowTests/testWholePlayFlowRecordsZeroHTTPRequests()",
    "assertion": "XCTAssertNil",
    "source_file": "PlaysteadUITests/ZeroNetworkPlayFlowTests.swift",
    "source_line": 57,
    "failure_stage": expected,
}
assert "/Users/private" not in json.dumps(summary)
assert "Bearer" not in json.dumps(summary)
assert "Secret.gba" not in json.dumps(summary)
PY
  expect_pass "zero_network_diagnostic_$stage" "$VERIFIER" --print-failure-diagnostics "$fixture.summary.json" ui
  grep -F "failure_stage=$stage" "$TMP_ROOT/zero_network_diagnostic_$stage.out" >/dev/null
  if grep -E 'Bearer|Secret\.gba|/Users/private|private exception' "$TMP_ROOT/zero_network_diagnostic_$stage.out" >/dev/null; then
    printf 'FAIL: zero-network stage diagnostic leaked private content\n' >&2
    exit 1
  fi
done
PASS_COUNT=$((PASS_COUNT + 1))

for marker_case in missing unknown duplicate malformed; do
  case "$marker_case" in
    missing) marker=missing ;;
    unknown) marker=zero-network-play-flow-stage=unlisted-stage ;;
    duplicate) marker='zero-network-play-flow-stage=adapter-launch zero-network-play-flow-stage=bounded-exit' ;;
    malformed) marker='zero-network-play-flow-stage=adapter-launch/Users/private/Bearer-secret' ;;
  esac
  fixture="$TMP_ROOT/zero-network-$marker_case.json"
  write_zero_network_fixture "$fixture" "$marker"
  expect_fail "zero_network_$marker_case" verify_zero_network_fixture "$fixture"
  python3 - "$fixture.summary.json" <<'PY'
import json, pathlib, sys
summary = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert len(summary["failure_diagnostics"]) == 1
assert "failure_stage" not in summary["failure_diagnostics"][0]
assert "/Users/private" not in json.dumps(summary)
assert "Bearer" not in json.dumps(summary)
assert "Secret.gba" not in json.dumps(summary)
PY
  expect_pass "zero_network_diagnostic_$marker_case" "$VERIFIER" --print-failure-diagnostics "$fixture.summary.json" ui
  if grep -E 'zero-network-play-flow-stage|Bearer|Secret\.gba|/Users/private|private exception' "$TMP_ROOT/zero_network_diagnostic_$marker_case.out" >/dev/null; then
    printf 'FAIL: malformed zero-network stage diagnostic leaked data\n' >&2
    exit 1
  fi
done
PASS_COUNT=$((PASS_COUNT + 1))

# Xcode's class selector has no slash, while result nodes always identify an
# individual method. A class-level requirement means at least one case from
# that class was selected and every reported case passed; method selectors
# below retain the exact-one contract.
class_selector="$TMP_ROOT/class-selector.json"
python3 - "$class_selector" <<'PY'
import json, sys
cases = [
    {"nodeType":"Test Case", "nodeIdentifier":f"CurationInteractionTests/testCase{index}()", "result":"Passed"}
    for index in range(2)
]
cases.append({"nodeType":"Test Case", "nodeIdentifier":"OtherTests/testUnselected()", "result":"Passed"})
json.dump({"testNodes":[{"nodeType":"Test Plan", "children":cases}]}, open(sys.argv[1], "w"))
PY
expect_pass class_selector "$VERIFIER" --verify-layer-result "$class_selector" ui "$TMP_ROOT/class-summary.json" \
  --required-test PlaysteadUITests.CurationInteractionTests
python3 - "$TMP_ROOT/class-summary.json" <<'PY'
import json, pathlib, sys
record = json.loads(pathlib.Path(sys.argv[1]).read_text())["required_tests"][0]
assert record["identifier"] == "CurationInteractionTests/*"
assert record["discovered"] is True and record["execution_count"] == 2
assert record["skipped"] is False and record["outcome"] == "passed"
PY
PASS_COUNT=$((PASS_COUNT + 1))

class_failure="$TMP_ROOT/class-failure.json"
python3 - "$class_failure" <<'PY'
import json, sys
cases = [
    {"nodeType":"Test Case", "nodeIdentifier":"CurationInteractionTests/testPass()", "result":"Passed"},
    {"nodeType":"Test Case", "nodeIdentifier":"CurationInteractionTests/testFail()", "result":"Failed"},
]
json.dump({"testNodes":[{"nodeType":"Test Plan", "children":cases}]}, open(sys.argv[1], "w"))
PY
expect_fail class_failure "$VERIFIER" --verify-layer-result "$class_failure" ui "$TMP_ROOT/class-failure-summary.json" \
  --required-test PlaysteadUITests.CurationInteractionTests
expect_fail malformed_class "$VERIFIER" --verify-layer-result "$class_selector" ui "$TMP_ROOT/malformed-summary.json" \
  --required-test CurationInteractionTests
PASS_COUNT=$((PASS_COUNT + 2))

runner_process_error="$TMP_ROOT/runner-process-error.json"
python3 - "$runner_process_error" <<'PY'
import json, sys
required = {
    "nodeType": "Test Case",
    "nodeIdentifier": "KeychainScopingTests/testScopedMatchQueryRestrictsSearchWithoutSelectingAnAddDestination()",
    "name": "testScopedMatchQueryRestrictsSearchWithoutSelectingAnAddDestination()",
    "result": "Passed",
}
runner = {
    "nodeType": "Test Case",
    "nodeIdentifier": "PlaysteadUITests-Runner (16205) encountered an error",
    "name": "PlaysteadUITests-Runner (16205) encountered an error",
    "result": "Failed",
}
json.dump({"testNodes": [{"nodeType": "Test Plan", "children": [required, runner]}]}, open(sys.argv[1], "w"))
PY
expect_fail runner_process_error "$VERIFIER" --verify-layer-result "$runner_process_error" ui "$TMP_ROOT/runner-process-summary.json" \
  --required-test PlaysteadUITests.HostedRunnerCanaryTests/testScopedFileKeychainStoresLoadsAndDeletesTwice
python3 - "$TMP_ROOT/runner-process-summary.json" <<'PY'
import json, pathlib, sys
summary=json.loads(pathlib.Path(sys.argv[1]).read_text())
assert summary["executed_test_count"] == 1
assert summary["runner_process_error_count"] == 1
assert summary["failed_test_count"] == 0
assert summary["required_tests"][0]["outcome"] == "missing"
PY
PASS_COUNT=$((PASS_COUNT + 1))

# Xcode 26 may put the assertion node only in `test-details`, leaving the
# compact `tests` tree with a failed Test Case and no Failure Message child.
# Exercise that path with a fake xcresulttool response that contains a secret
# in its free-text message; only the canonical source site may reach output.
details_only="$TMP_ROOT/details-only.json"
python3 - "$details_only" <<'PY'
import json, sys
case = {
    "nodeType": "Test Case",
    "nodeIdentifier": "PlaysteadUITests.SurfaceAccessibilityTests/testSyntheticFailure()",
    "name": "testSyntheticFailure()",
    "result": "Failed",
    "durationInSeconds": 4.25,
}
required = {
    "nodeType": "Test Case",
    "nodeIdentifier": "PlaysteadTests.KeychainScopingTests/testScopedMatchQueryRestrictsSearchWithoutSelectingAnAddDestination()",
    "name": "testScopedMatchQueryRestrictsSearchWithoutSelectingAnAddDestination()",
    "result": "Passed",
    "durationInSeconds": 1.5,
}
json.dump({"testPlanConfigurations": [], "devices": [], "testNodes": [
    {"nodeType": "Test Plan", "name": "Unit", "children": [required, case]}
]}, open(sys.argv[1], "w"))
PY
mkdir -p "$TMP_ROOT/fake-bin"
cat >"$TMP_ROOT/fake-bin/xcrun" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = xcresulttool ] && [ "$2" = get ] && [ "$3" = test-results ] && \
  [ "$4" = test-details ] || exit 31
cat "$FAKE_XCRESULT_DETAILS"
SH
chmod +x "$TMP_ROOT/fake-bin/xcrun"
details_json="$TMP_ROOT/test-details.json"
python3 - "$details_json" <<'PY'
import json, sys
json.dump({
    "testIdentifier": "PlaysteadUITests.SurfaceAccessibilityTests/testSyntheticFailure()",
    "testRuns": [{"nodeType": "Test Case Run", "name": "run", "children": [{
        "nodeType": "Failure Message",
        "name": "SurfaceAccessibilityTests.swift:137: XCTAssertTrue failed: Bearer private-token /Users/private/file.rom",
        "result": "Failed",
    }]}],
}, open(sys.argv[1], "w"))
PY
verify_fixture_with_details() {
  PATH="$TMP_ROOT/fake-bin:$PATH" \
    FAKE_XCRESULT_DETAILS="$details_json" \
    verify_fixture "$1" --result-bundle /synthetic/result.xcresult
  "$VERIFIER" --print-failure-diagnostics "$TMP_ROOT/summary.json" unit
}
expect_pass details_only verify_fixture_with_details "$details_only"
grep -Fx 'unit: FAILURE_DIAGNOSTIC SurfaceAccessibilityTests/testSyntheticFailure() XCTAssertTrue PlaysteadUITests/SurfaceAccessibilityTests.swift:137' "$TMP_ROOT/details_only.out" >/dev/null || {
  printf 'FAIL: bounded xcresult test-details diagnostic was not recovered\n' >&2
  exit 1
}
if grep -E 'Bearer|private-token|/Users/|file\.rom' "$TMP_ROOT/details_only.out" >/dev/null; then
  printf 'FAIL: xcresult test-details diagnostic leaked a raw message or path\n' >&2
  exit 1
fi
python3 - "$TMP_ROOT/summary.json" <<'PY'
import json, pathlib, sys
summary = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert summary["failure_diagnostics"] == [{
    "test_identifier": "SurfaceAccessibilityTests/testSyntheticFailure()",
    "assertion": "XCTAssertTrue",
    "source_file": "PlaysteadUITests/SurfaceAccessibilityTests.swift",
    "source_line": 137,
}]
PY
PASS_COUNT=$((PASS_COUNT + 3))

# The real pinned Xcode detail tree can contain only a failed run and source
# symbols. The legacy issue root carries the missing file/line instead.
cp "$TMP_ROOT/summary.json" "$TMP_ROOT/details-summary.json"
cat >"$TMP_ROOT/fake-bin/xcrun" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = xcresulttool ] && [ "$2" = get ] || exit 31
if [ "$3" = test-results ] && [ "$4" = test-details ]; then
  cat "$FAKE_XCRESULT_DETAILS"
elif [ "$3" = object ] && [ "$4" = --legacy ]; then
  cat "$FAKE_XCRESULT_LEGACY"
else
  exit 31
fi
SH
legacy_json="$TMP_ROOT/legacy-issues.json"
python3 - "$details_json" "$legacy_json" <<'PY'
import json, sys
json.dump({"testRuns": [{"nodeType": "Test Case Run", "result": "Failed",
    "name": "failed - private message", "children": [
        {"nodeType": "Source Code Reference", "name": "SurfaceAccessibilityTests.testSyntheticFailure()"}
    ]}]}, open(sys.argv[1], "w"))
def issue(test, location, message):
    return {"_type": {"_name": "TestFailureIssueSummary"},
        "testCaseName": {"_value": test}, "message": {"_value": message},
        "documentLocationInCreatingWorkspace": {"url": {"_value": location}}}
base = "file:///Users/private/SurfaceAccessibilityTests.swift#EndingLineNumber=137&StartingLineNumber=137"
json.dump({"issues": {"testFailureSummaries": {"_values": [
    {"_type": [], "testCaseName": []},
    issue("SurfaceAccessibilityTests.testSyntheticFailure()", base,
          "failed - Bearer private-token /Users/private/file.rom"),
    issue("UnrelatedTests.testOtherFailure()", base, "XCTAssertTrue failed"),
    issue("SurfaceAccessibilityTests.testSyntheticFailure()", base.replace("file://", "https://"), "XCTAssertTrue failed"),
    issue("SurfaceAccessibilityTests.testSyntheticFailure()", base.replace("SurfaceAccessibilityTests.swift", "Secret.swift"), "XCTAssertTrue failed"),
    issue("SurfaceAccessibilityTests.testSyntheticFailure()", base + "&StartingLineNumber=138", "XCTAssertTrue failed"),
]}}}, open(sys.argv[2], "w"))
PY
verify_fixture_with_legacy() {
  PATH="$TMP_ROOT/fake-bin:$PATH" \
    FAKE_XCRESULT_DETAILS="$details_json" FAKE_XCRESULT_LEGACY="$legacy_json" \
    verify_fixture "$1" --result-bundle /synthetic/result.xcresult
  "$VERIFIER" --print-failure-diagnostics "$TMP_ROOT/summary.json" unit
}
expect_pass legacy_issue_only verify_fixture_with_legacy "$details_only"
grep -Fx 'unit: FAILURE_DIAGNOSTIC SurfaceAccessibilityTests/testSyntheticFailure() XCTFail PlaysteadUITests/SurfaceAccessibilityTests.swift:137' "$TMP_ROOT/legacy_issue_only.out" >/dev/null || {
  printf 'FAIL: legacy issue source site was not recovered\n' >&2
  exit 1
}
if grep -E 'Bearer|private-token|/Users/|file\.rom|Secret.swift|UnrelatedTests' "$TMP_ROOT/legacy_issue_only.out" >/dev/null; then
  printf 'FAIL: legacy issue fallback leaked private or unrelated content\n' >&2
  exit 1
fi
python3 - "$TMP_ROOT/summary.json" <<'PY'
import json, pathlib, sys
summary = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert summary["failure_diagnostics"] == [{
    "test_identifier": "SurfaceAccessibilityTests/testSyntheticFailure()",
    "assertion": "XCTFail", "source_file": "PlaysteadUITests/SurfaceAccessibilityTests.swift",
    "source_line": 137,
}]
PY
PASS_COUNT=$((PASS_COUNT + 3))
cp "$TMP_ROOT/details-summary.json" "$TMP_ROOT/summary.json"

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
