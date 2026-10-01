#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANITIZER="${SCRIPT_DIR}/../sanitize-evidence.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/playstead-sanitizer.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

PASS_COUNT=0
FAIL_COUNT=0
ZERO_NETWORK_STAGES=(stand-in-signing adapter-selection synthetic-cas catalogue-readiness materialization-save-setup adapter-launch adapter-exit unclassified)

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

expect_zero_network_sanitizer_stage() {
  local stage="$1" root="$TMP_ROOT/zero-stage-$1" output="$TMP_ROOT/zero-stage-$1-output"
  make_valid "$root"
  python3 - "$root/evidence/ui-tests.json" "$stage" <<'PY'
import json, pathlib, sys
path=pathlib.Path(sys.argv[1]); stage=sys.argv[2]; data=json.loads(path.read_text())
data["failure_diagnostics"].append({"test_identifier":"ZeroNetworkPlayFlowTests/testWholePlayFlowRecordsZeroHTTPRequests()","assertion":"XCTAssertNil","source_file":"PlaysteadUITests/ZeroNetworkPlayFlowTests.swift","source_line":53,"failure_stage":stage})
data["failure_diagnostic_count"] += 1
path.write_text(json.dumps(data))
PY
  expect_pass "zero_stage_$stage" "$SANITIZER" --input "$root" --output "$output"
  python3 - "$output/ui-tests.json" "$stage" <<'PY'
import json, pathlib, sys
d=json.loads(pathlib.Path(sys.argv[1]).read_text())
r=[x for x in d["failure_diagnostics"] if x["test_identifier"].startswith("ZeroNetworkPlayFlowTests/")]
assert len(r)==1 and r[0]["failure_stage"]==sys.argv[2]
PY
}

python3 - "$SCRIPT_DIR/../../../Playstead/UITesting/UITestBootstrap.swift" "$SCRIPT_DIR/../../../PlaysteadUITests/ZeroNetworkPlayFlowTests.swift" <<'PY'
import pathlib, re, sys
bootstrap=pathlib.Path(sys.argv[1]).read_text(); test=pathlib.Path(sys.argv[2]).read_text()
enum=re.search(r"private enum ZeroNetworkPlayFlowStage: String \{(.*?)\n    \}", bootstrap, re.S)
assert enum, "zero-network diagnostic stage enum missing"
declared=set(re.findall(r'= "([a-z-]+)"', enum.group(1)))
expected={"stand-in-signing","adapter-selection","synthetic-cas","catalogue-readiness","materialization-save-setup","adapter-launch","adapter-exit","unclassified"}
assert declared == expected, f"unexpected Mac stage enum: {declared}"
assert "failureStage = .unclassified" in bootstrap
assert "failureStage = .adapterExit" not in bootstrap
pin=bootstrap.index("pin = try AdapterPin.load()")
assert ".adapterSelection" in bootstrap[pin:pin+220], "adapter pin load must map to adapter-selection"
flow=bootstrap[bootstrap.index("private static func runZeroNetworkPlayFlow"):bootstrap.index("/// A tiny async-friendly exit latch")]
assert flow.count("ZeroNetworkPlayFlowFailure(stage: .adapterExit)") == 1
assert "try await exited.wait(timeoutSeconds: 20)" in flow
assert "ZeroNetworkPlayFlowFailure(stage: .adapterLaunch)" in flow
assert "CFGetTypeID(countNumber) != CFBooleanGetTypeID()" in test
assert 'countEncoding != "f", countEncoding != "d"' in test
assert "countText.utf8.allSatisfy" in test and "Int(countText)" in test
print("zero-network stage mapping and strict integer source contracts passed")
PY

make_valid() {
  local root="$1"
  mkdir -p "$root/evidence/snapshot-triplet" "$root/evidence/storage-candidate" "$root/evidence/logs" "$root/raw/Unit.xcresult" "$root/DerivedData"
  printf '%s\n' '{"schema_version":1,"architecture":"arm64","xcode":["Xcode 26.6","Build version 17F113"]}' >"$root/evidence/environment-fingerprint.json"
  printf '%s\n' '{"schema_version":1,"build_count":1,"automatic_retries":0,"aggregate_outcome":"failed","layers":[]}' >"$root/evidence/layers.json"
  printf '%s\n' '{"schema_version":1,"run_id":"123e4567-e89b-42d3-a456-426614174000","lane":"linux_restore_fixture","stages":["chain","preflight","database","cas","manifest","api"],"outcome":"passed"}' >"$root/evidence/recovery-e2e.json"
  printf '%s\n' '{"schema_version":1,"layer":"ui","executed_test_count":2,"runner_process_error_count":0,"required_tests":[{"identifier":"PlaysteadUITests.HostedRunnerCanaryTests/testScopedFileKeychainStoresLoadsAndDeletesTwice","discovered":true,"execution_count":1,"skipped":false,"outcome":"passed"}],"failed_test_count":1,"failed_tests_truncated":false,"failed_tests":[{"identifier":"SurfaceAccessibilityTests/testSyntheticFailure()","outcome":"failed"}],"failure_diagnostic_count":1,"failure_diagnostics_truncated":false,"failure_diagnostics":[{"test_identifier":"SurfaceAccessibilityTests/testSyntheticFailure()","assertion":"XCTAssertTrue","source_file":"PlaysteadUITests/SurfaceAccessibilityTests.swift","source_line":137}],"layout_diagnostic_count":0,"layout_diagnostics_truncated":false,"layout_diagnostics":[],"audit_issue_count":1,"audit_issues_truncated":false,"audit_issues":[{"test_identifier":"SurfaceAccessibilityTests/testSyntheticFailure()","category":"parentChild","element_identifier":"playstead.surface.library","element_role":"role-3"}],"in_test_seconds_total":42.2,"timed_test_count":2,"slowest_tests":[{"identifier":"SurfaceAccessibilityTests/testSyntheticFailure()","seconds":1.5}]}' >"$root/evidence/ui-tests.json"
printf 'safe app event at /Users/example/private/location\n' >"$root/evidence/logs/app.log"
  printf 'server health passed\n' >"$root/evidence/logs/server.log"
  printf '\211PNG\r\n\032\nreference' >"$root/evidence/snapshot-triplet/reference.png"
  printf '\211PNG\r\n\032\nactual' >"$root/evidence/snapshot-triplet/actual.png"
  printf '\211PNG\r\n\032\ndiff' >"$root/evidence/snapshot-triplet/diff.png"
  python3 - "$root/evidence/storage-candidate/storage-surfaces.actual.png" 5760 3040 <<'PY'
import pathlib, struct, sys
path, width, height = sys.argv[1:]
payload = b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", int(width), int(height)) + b"synthetic-candidate"
pathlib.Path(path).write_bytes(payload)
PY
  printf 'raw result must stay outside upload' >"$root/raw/Unit.xcresult/raw"
}

valid="$TMP_ROOT/valid"
make_valid "$valid"
expect_pass valid "$SANITIZER" --input "$valid" --output "$TMP_ROOT/output"
grep -F '[PATH]' "$TMP_ROOT/output/logs/app.log" >/dev/null || { printf 'FAIL: local path was not redacted\n' >&2; exit 1; }
[ ! -e "$TMP_ROOT/output/raw" ]
[ ! -e "$TMP_ROOT/output/DerivedData" ]
[ -s "$TMP_ROOT/output/storage-candidate/storage-surfaces.actual.png" ]
PASS_COUNT=$((PASS_COUNT + 4))

for stage in "${ZERO_NETWORK_STAGES[@]}"; do
  input="$TMP_ROOT/verifier-zero-$stage.json"; summary="$TMP_ROOT/verifier-zero-$stage-summary.json"
  python3 - "$input" "$stage" <<'PY'
import json,pathlib,sys
path=pathlib.Path(sys.argv[1]); stage=sys.argv[2]
case={"nodeType":"Test Case","nodeIdentifier":"ZeroNetworkPlayFlowTests/testWholePlayFlowRecordsZeroHTTPRequests()","name":"testWholePlayFlowRecordsZeroHTTPRequests()","result":"Failed","children":[{"nodeType":"Failure Message","name":f"ZeroNetworkPlayFlowTests.swift:53: XCTAssertNil failed: PLAYSTEAD_ZERO_NETWORK_FAILURE_STAGE[{stage}]","result":"Failed"}]}
path.write_text(json.dumps({"testNodes":[{"nodeType":"Test Plan","children":[case]}]}))
PY
  expect_fail "verifier_zero_$stage" "$SCRIPT_DIR/../run-mac-verification.sh" --verify-layer-result "$input" ui "$summary" --required-test PlaysteadUITests.ZeroNetworkPlayFlowTests/testWholePlayFlowRecordsZeroHTTPRequests
  python3 - "$summary" "$stage" <<'PY'
import json,pathlib,sys
d=json.loads(pathlib.Path(sys.argv[1]).read_text()); r=d["failure_diagnostics"]
assert len(r)==1 and r[0]["failure_stage"]==sys.argv[2]
PY
  "$SCRIPT_DIR/../run-mac-verification.sh" --print-failure-diagnostics "$summary" ui >"$TMP_ROOT/verifier-zero-$stage-diagnostic.out"
  grep -F "failure_stage=$stage" "$TMP_ROOT/verifier-zero-$stage-diagnostic.out" >/dev/null
done

for marker in 'unknown' 'adapter-exit] PLAYSTEAD_ZERO_NETWORK_FAILURE_STAGE[adapter-launch' '/Users/private/token'; do
  input="$TMP_ROOT/verifier-zero-invalid-$PASS_COUNT.json"; summary="$TMP_ROOT/verifier-zero-invalid-$PASS_COUNT-summary.json"
  python3 - "$input" "$marker" <<'PY'
import json,pathlib,sys
path=pathlib.Path(sys.argv[1]); marker=sys.argv[2]
case={"nodeType":"Test Case","nodeIdentifier":"ZeroNetworkPlayFlowTests/testWholePlayFlowRecordsZeroHTTPRequests()","result":"Failed","children":[{"nodeType":"Failure Message","name":f"ZeroNetworkPlayFlowTests.swift:53: XCTAssertNil failed: PLAYSTEAD_ZERO_NETWORK_FAILURE_STAGE[{marker}]","result":"Failed"}]}
path.write_text(json.dumps({"testNodes":[{"nodeType":"Test Plan","children":[case]}]}))
PY
  expect_fail "verifier_zero_invalid_$PASS_COUNT" "$SCRIPT_DIR/../run-mac-verification.sh" --verify-layer-result "$input" ui "$summary" --required-test PlaysteadUITests.ZeroNetworkPlayFlowTests/testWholePlayFlowRecordsZeroHTTPRequests
  [ ! -s "$summary" ] || { printf 'FAIL: invalid zero-network stage produced a summary\n' >&2; exit 1; }
done

for stage in "${ZERO_NETWORK_STAGES[@]}"; do
  expect_zero_network_sanitizer_stage "$stage"
done

for bad_stage in unknown '' null '/Users/private/game.gba' 'token=synthetic-secret'; do
  name="zero-stage-invalid-${bad_stage:-missing}"
  root="$TMP_ROOT/$name"; make_valid "$root"
  python3 - "$root/evidence/ui-tests.json" "$bad_stage" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); value=sys.argv[2]
d["failure_diagnostics"].append({"test_identifier":"ZeroNetworkPlayFlowTests/testWholePlayFlowRecordsZeroHTTPRequests()","assertion":"XCTAssertNil","source_file":"PlaysteadUITests/ZeroNetworkPlayFlowTests.swift","source_line":53,"failure_stage":None if value == "null" else value})
d["failure_diagnostic_count"] += 1; p.write_text(json.dumps(d))
PY
  expect_fail "$name" "$SANITIZER" --input "$root" --output "$TMP_ROOT/$name-output"
done

zero_stage_extra_key="$TMP_ROOT/zero-stage-extra-key"; make_valid "$zero_stage_extra_key"
python3 - "$zero_stage_extra_key/evidence/ui-tests.json" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d["failure_diagnostics"].append({"test_identifier":"ZeroNetworkPlayFlowTests/testWholePlayFlowRecordsZeroHTTPRequests()","assertion":"XCTAssertNil","source_file":"PlaysteadUITests/ZeroNetworkPlayFlowTests.swift","source_line":53,"failure_stage":"adapter-exit","raw":"/Users/private/token"}); d["failure_diagnostic_count"]+=1; p.write_text(json.dumps(d))
PY
expect_fail zero_stage_extra_key "$SANITIZER" --input "$zero_stage_extra_key" --output "$TMP_ROOT/zero-stage-extra-key-output"

virtual_gamepad_blocked="$TMP_ROOT/virtual-gamepad-blocked"
make_valid "$virtual_gamepad_blocked"
printf '%s\n' '{"schema_version":1,"lane":"virtual_gamepad","test_identifier":"PlaysteadUITests.ControllerHardwareIntegrationTests/testEntitledVirtualGamepadEnumeratesDetachesAndReconnectsWithoutRelaunch","status":"blocked/not-configured","gate_passed":false}' >"$virtual_gamepad_blocked/evidence/entitled-gamepad.json"
expect_pass virtual_gamepad_blocked "$SANITIZER" --input "$virtual_gamepad_blocked" --output "$TMP_ROOT/virtual-gamepad-blocked-output"
grep -F '"status": "blocked/not-configured"' "$TMP_ROOT/virtual-gamepad-blocked-output/entitled-gamepad.json" >/dev/null
PASS_COUNT=$((PASS_COUNT + 1))

virtual_gamepad_false_pass="$TMP_ROOT/virtual-gamepad-false-pass"
make_valid "$virtual_gamepad_false_pass"
printf '%s\n' '{"schema_version":1,"lane":"virtual_gamepad","test_identifier":"PlaysteadUITests.ControllerHardwareIntegrationTests/testEntitledVirtualGamepadEnumeratesDetachesAndReconnectsWithoutRelaunch","status":"blocked/not-configured","gate_passed":true}' >"$virtual_gamepad_false_pass/evidence/entitled-gamepad.json"
expect_fail virtual_gamepad_false_pass "$SANITIZER" --input "$virtual_gamepad_false_pass" --output "$TMP_ROOT/virtual-gamepad-false-pass-output"

runner_process_error_overflow="$TMP_ROOT/runner-process-error-overflow"
make_valid "$runner_process_error_overflow"
python3 - "$runner_process_error_overflow/evidence/ui-tests.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
data["runner_process_error_count"] = 51
path.write_text(json.dumps(data))
PY
expect_fail runner_process_error_overflow "$SANITIZER" --input "$runner_process_error_overflow" --output "$TMP_ROOT/runner-process-error-overflow-output"

recovery_unknown="$TMP_ROOT/recovery-unknown"
make_valid "$recovery_unknown"
python3 - "$recovery_unknown/evidence/recovery-e2e.json" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d["fixture_path"]="/Users/private/game.gba"; p.write_text(json.dumps(d))
PY
expect_fail recovery_unknown "$SANITIZER" --input "$recovery_unknown" --output "$TMP_ROOT/recovery-unknown-output"

recovery_stage="$TMP_ROOT/recovery-stage"
make_valid "$recovery_stage"
python3 - "$recovery_stage/evidence/recovery-e2e.json" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d["stages"].pop(); p.write_text(json.dumps(d))
PY
expect_fail recovery_stage "$SANITIZER" --input "$recovery_stage" --output "$TMP_ROOT/recovery-stage-output"

# Same-host Mac recovery receipts use a separate compact schema. Keep their
# stage/outcome pair strict without changing the Linux fixture receipt above.
local_recovery_blocked="$TMP_ROOT/local-recovery-blocked"
make_valid "$local_recovery_blocked"
printf '%s\n' '{"schema":"playstead.recovery-e2e-local.v1","run_id":"123e4567-e89b-42d3-a456-426614174000","lane":"same_host_restored_target","stage":"cache_preflight","outcome":"blocked"}' >"$local_recovery_blocked/evidence/recovery-e2e.json"
expect_pass local_recovery_blocked "$SANITIZER" --input "$local_recovery_blocked" --output "$TMP_ROOT/local-recovery-blocked-output"
python3 - "$TMP_ROOT/local-recovery-blocked-output/recovery-e2e.json" <<'PY'
import json, pathlib, sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert set(data) == {"schema", "run_id", "lane", "stage", "outcome"}
assert data["stage"] == "cache_preflight" and data["outcome"] == "blocked"
PY
PASS_COUNT=$((PASS_COUNT + 1))

local_recovery_complete="$TMP_ROOT/local-recovery-complete"
make_valid "$local_recovery_complete"
printf '%s\n' '{"schema":"playstead.recovery-e2e-local.v1","run_id":"123e4567-e89b-42d3-a456-426614174000","lane":"same_host_restored_target","stage":"complete","outcome":"passed"}' >"$local_recovery_complete/evidence/recovery-e2e.json"
expect_pass local_recovery_complete "$SANITIZER" --input "$local_recovery_complete" --output "$TMP_ROOT/local-recovery-complete-output"
PASS_COUNT=$((PASS_COUNT + 1))

local_recovery_bad_stage="$TMP_ROOT/local-recovery-bad-stage"
make_valid "$local_recovery_bad_stage"
printf '%s\n' '{"schema":"playstead.recovery-e2e-local.v1","run_id":"123e4567-e89b-42d3-a456-426614174000","lane":"same_host_restored_target","stage":"private-path","outcome":"blocked"}' >"$local_recovery_bad_stage/evidence/recovery-e2e.json"
expect_fail local_recovery_bad_stage "$SANITIZER" --input "$local_recovery_bad_stage" --output "$TMP_ROOT/local-recovery-bad-stage-output"

local_recovery_extra_field="$TMP_ROOT/local-recovery-extra-field"
make_valid "$local_recovery_extra_field"
printf '%s\n' '{"schema":"playstead.recovery-e2e-local.v1","run_id":"123e4567-e89b-42d3-a456-426614174000","lane":"same_host_restored_target","stage":"cache_preflight","outcome":"blocked","private_field":"forbidden"}' >"$local_recovery_extra_field/evidence/recovery-e2e.json"
expect_fail local_recovery_extra_field "$SANITIZER" --input "$local_recovery_extra_field" --output "$TMP_ROOT/local-recovery-extra-field-output"

local_recovery_inconsistent="$TMP_ROOT/local-recovery-inconsistent"
make_valid "$local_recovery_inconsistent"
printf '%s\n' '{"schema":"playstead.recovery-e2e-local.v1","run_id":"123e4567-e89b-42d3-a456-426614174000","lane":"same_host_restored_target","stage":"complete","outcome":"blocked"}' >"$local_recovery_inconsistent/evidence/recovery-e2e.json"
expect_fail local_recovery_inconsistent "$SANITIZER" --input "$local_recovery_inconsistent" --output "$TMP_ROOT/local-recovery-inconsistent-output"
python3 - "$TMP_ROOT/output/ui-tests.json" <<'PY'
import json, pathlib, sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert data["failed_tests"] == [{"identifier": "SurfaceAccessibilityTests/testSyntheticFailure()", "outcome": "failed"}]
assert all(set(record) == {"identifier", "outcome"} for record in data["failed_tests"])
assert data["failure_diagnostics"] == [{"test_identifier":"SurfaceAccessibilityTests/testSyntheticFailure()","assertion":"XCTAssertTrue","source_file":"PlaysteadUITests/SurfaceAccessibilityTests.swift","source_line":137}]
assert data["audit_issues"] == [{"test_identifier": "SurfaceAccessibilityTests/testSyntheticFailure()", "category": "parentChild", "element_identifier": "playstead.surface.library", "element_role": "role-3"}]
PY
PASS_COUNT=$((PASS_COUNT + 1))

legacy_schema="$TMP_ROOT/legacy-schema"
make_valid "$legacy_schema"
python3 - "$legacy_schema/evidence/ui-tests.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1]); data = json.loads(path.read_text())
for key in ("failure_diagnostic_count", "failure_diagnostics_truncated", "failure_diagnostics"):
    data.pop(key)
path.write_text(json.dumps(data))
PY
expect_pass legacy_schema "$SANITIZER" --input "$legacy_schema" --output "$TMP_ROOT/legacy-schema-output"

class_selector="$TMP_ROOT/class-selector"
make_valid "$class_selector"
python3 - "$class_selector/evidence/ui-tests.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1]); data = json.loads(path.read_text())
data["required_tests"][0]["identifier"] = "PlaysteadUITests.LibraryEmptyStateTests/*"
path.write_text(json.dumps(data))
PY
expect_pass class_selector "$SANITIZER" --input "$class_selector" --output "$TMP_ROOT/class-selector-output"
python3 - "$TMP_ROOT/class-selector-output/ui-tests.json" <<'PY'
import json, pathlib, sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert data["required_tests"][0]["identifier"] == "PlaysteadUITests.LibraryEmptyStateTests/*"
PY
PASS_COUNT=$((PASS_COUNT + 1))

secret_json="$TMP_ROOT/secret-json"
make_valid "$secret_json"
printf '%s\n' '{"schema_version":1,"authorization":"Bearer secret"}' >"$secret_json/evidence/layers.json"
expect_fail secret_json "$SANITIZER" --input "$secret_json" --output "$TMP_ROOT/secret-json-output"

content_id="$TMP_ROOT/content-id"
make_valid "$content_id"
printf '%s\n' '{"schema_version":1,"name":"private-game.nes"}' >"$content_id/evidence/layers.json"
expect_fail content_identifier "$SANITIZER" --input "$content_id" --output "$TMP_ROOT/content-id-output"

failure_message="$TMP_ROOT/failure-message"
make_valid "$failure_message"
python3 - "$failure_message/evidence/ui-tests.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1]); data = json.loads(path.read_text())
data["failed_tests"][0]["message"] = "private diagnostic"
path.write_text(json.dumps(data))
PY
expect_fail failure_message "$SANITIZER" --input "$failure_message" --output "$TMP_ROOT/failure-message-output"

unsafe_diagnostic="$TMP_ROOT/unsafe-diagnostic"
make_valid "$unsafe_diagnostic"
python3 - "$unsafe_diagnostic/evidence/ui-tests.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1]); data = json.loads(path.read_text())
data["failure_diagnostics"][0]["source_file"] = "/Users/example/private/Secret.swift"
path.write_text(json.dumps(data))
PY
expect_fail unsafe_diagnostic "$SANITIZER" --input "$unsafe_diagnostic" --output "$TMP_ROOT/unsafe-diagnostic-output"

layout_diagnostic="$TMP_ROOT/layout-diagnostic"
make_valid "$layout_diagnostic"
python3 - "$layout_diagnostic/evidence/ui-tests.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1]); data = json.loads(path.read_text())
data["layout_diagnostic_count"] = 1
data["layout_diagnostics"] = [{"kind":"moveUp","hittable":False,"element":[12,34,56,78],"pane":[1,2,300,400],"window":[0,0,1200,900]}]
path.write_text(json.dumps(data))
PY
expect_pass layout_diagnostic "$SANITIZER" --input "$layout_diagnostic" --output "$TMP_ROOT/layout-diagnostic-output"
python3 - "$TMP_ROOT/layout-diagnostic-output/ui-tests.json" <<'PY'
import json, pathlib, sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert data["layout_diagnostics"] == [{"kind":"moveUp","hittable":False,"element":[12,34,56,78],"pane":[1,2,300,400],"window":[0,0,1200,900]}]
PY
PASS_COUNT=$((PASS_COUNT + 1))

layout_diagnostic_freeform="$TMP_ROOT/layout-diagnostic-freeform"
make_valid "$layout_diagnostic_freeform"
python3 - "$layout_diagnostic_freeform/evidence/ui-tests.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1]); data = json.loads(path.read_text())
data["layout_diagnostic_count"] = 1
data["layout_diagnostics"] = [{"kind":"moveUp","hittable":False,"element":[12,34,56,78],"pane":[1,2,300,400],"window":[0,0,1200,900],"message":"private XCTest text"}]
path.write_text(json.dumps(data))
PY
expect_fail layout_diagnostic_freeform "$SANITIZER" --input "$layout_diagnostic_freeform" --output "$TMP_ROOT/layout-diagnostic-freeform-output"

unbounded_diagnostics="$TMP_ROOT/unbounded-diagnostics"
make_valid "$unbounded_diagnostics"
python3 - "$unbounded_diagnostics/evidence/ui-tests.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1]); data = json.loads(path.read_text())
data["failure_diagnostics"] = [{"test_identifier":f"SyntheticSuite/testFailure{index}()","assertion":"XCTAssertEqual","source_file":"PlaysteadUITests/SurfaceAccessibilityTests.swift","source_line":index + 1} for index in range(51)]
data["failure_diagnostic_count"] = 51
path.write_text(json.dumps(data))
PY
expect_fail unbounded_diagnostics "$SANITIZER" --input "$unbounded_diagnostics" --output "$TMP_ROOT/unbounded-diagnostics-output"

unsafe_test_id="$TMP_ROOT/unsafe-test-id"
make_valid "$unsafe_test_id"
python3 - "$unsafe_test_id/evidence/ui-tests.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1]); data = json.loads(path.read_text())
data["failed_tests"][0]["identifier"] = "/Users/example/private/testFailure()"
path.write_text(json.dumps(data))
PY
expect_fail unsafe_test_id "$SANITIZER" --input "$unsafe_test_id" --output "$TMP_ROOT/unsafe-test-id-output"

unsafe_audit_id="$TMP_ROOT/unsafe-audit-id"
make_valid "$unsafe_audit_id"
python3 - "$unsafe_audit_id/evidence/ui-tests.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1]); data = json.loads(path.read_text())
data["audit_issues"][0]["element_identifier"] = "/Users/example/private"
path.write_text(json.dumps(data))
PY
expect_fail unsafe_audit_id "$SANITIZER" --input "$unsafe_audit_id" --output "$TMP_ROOT/unsafe-audit-id-output"

unsafe_audit_role="$TMP_ROOT/unsafe-audit-role"
make_valid "$unsafe_audit_role"
python3 - "$unsafe_audit_role/evidence/ui-tests.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1]); data = json.loads(path.read_text())
data["audit_issues"][0]["element_role"] = "button /Users/example/private"
path.write_text(json.dumps(data))
PY
expect_fail unsafe_audit_role "$SANITIZER" --input "$unsafe_audit_role" --output "$TMP_ROOT/unsafe-audit-role-output"

unbounded="$TMP_ROOT/unbounded"
make_valid "$unbounded"
python3 - "$unbounded/evidence/ui-tests.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1]); data = json.loads(path.read_text())
data["failed_tests"] = [{"identifier": f"SyntheticSuite/testFailure{index}()", "outcome": "failed"} for index in range(51)]
data["failed_test_count"] = 51
path.write_text(json.dumps(data))
PY
expect_fail unbounded "$SANITIZER" --input "$unbounded" --output "$TMP_ROOT/unbounded-output"

unbounded_audit="$TMP_ROOT/unbounded-audit"
make_valid "$unbounded_audit"
python3 - "$unbounded_audit/evidence/ui-tests.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1]); data = json.loads(path.read_text())
data["audit_issues"] = [
    {"test_identifier":"SurfaceAccessibilityTests/testSyntheticFailure()","category":"parentChild","element_identifier":f"playstead.surface.synthetic-{index}","element_role":"role-3"}
    for index in range(51)
]
data["audit_issue_count"] = 51
path.write_text(json.dumps(data))
PY
expect_fail unbounded_audit "$SANITIZER" --input "$unbounded_audit" --output "$TMP_ROOT/unbounded-audit-output"

oversized="$TMP_ROOT/oversized"
make_valid "$oversized"
dd if=/dev/zero of="$oversized/evidence/snapshot-triplet/actual.png" bs=1048576 count=3 2>/dev/null
expect_fail oversized "$SANITIZER" --input "$oversized" --output "$TMP_ROOT/oversized-output"

wrong_candidate_name="$TMP_ROOT/wrong-candidate-name"
make_valid "$wrong_candidate_name"
mv "$wrong_candidate_name/evidence/storage-candidate/storage-surfaces.actual.png" \
  "$wrong_candidate_name/evidence/storage-candidate/storage-surfaces.owner.png"
expect_pass wrong_candidate_name "$SANITIZER" --input "$wrong_candidate_name" --output "$TMP_ROOT/wrong-candidate-name-output"
[ ! -e "$TMP_ROOT/wrong-candidate-name-output/storage-candidate/storage-surfaces.owner.png" ]
PASS_COUNT=$((PASS_COUNT + 1))

wrong_candidate_dimensions="$TMP_ROOT/wrong-candidate-dimensions"
make_valid "$wrong_candidate_dimensions"
python3 - "$wrong_candidate_dimensions/evidence/storage-candidate/storage-surfaces.actual.png" <<'PY'
import pathlib, struct, sys
path = pathlib.Path(sys.argv[1])
raw = bytearray(path.read_bytes())
raw[16:24] = struct.pack(">II", 8, 8)
path.write_bytes(raw)
PY
expect_fail wrong_candidate_dimensions "$SANITIZER" --input "$wrong_candidate_dimensions" --output "$TMP_ROOT/wrong-candidate-dimensions-output"

oversized_candidate="$TMP_ROOT/oversized-candidate"
make_valid "$oversized_candidate"
truncate -s 9437184 "$oversized_candidate/evidence/storage-candidate/storage-surfaces.actual.png"
expect_fail oversized_candidate "$SANITIZER" --input "$oversized_candidate" --output "$TMP_ROOT/oversized-candidate-output"

symlinked_candidate="$TMP_ROOT/symlinked-candidate"
make_valid "$symlinked_candidate"
mv "$symlinked_candidate/evidence/storage-candidate/storage-surfaces.actual.png" "$symlinked_candidate/candidate.png"
ln -s "$symlinked_candidate/candidate.png" "$symlinked_candidate/evidence/storage-candidate/storage-surfaces.actual.png"
expect_fail symlinked_candidate "$SANITIZER" --input "$symlinked_candidate" --output "$TMP_ROOT/symlinked-candidate-output"

bad_log="$TMP_ROOT/bad-log"
make_valid "$bad_log"
printf 'Authorization: Bearer synthetic-secret\n' >"$bad_log/evidence/logs/server.log"
expect_pass redacted_log "$SANITIZER" --input "$bad_log" --output "$TMP_ROOT/bad-log-output"
grep -F '[REDACTED SECRET-BEARING LINE]' "$TMP_ROOT/bad-log-output/logs/server.log" >/dev/null || {
  printf 'FAIL: secret-bearing log line was not redacted\n' >&2
  exit 1
}
PASS_COUNT=$((PASS_COUNT + 1))

# WR-04: colon-separated `KEY: value` credential shape (not the historical
# `KEY=value` form). Exercises a realistic Phoenix/Postgres structured log line.
colon_separated_log="$TMP_ROOT/colon-separated-log"
make_valid "$colon_separated_log"
printf 'DATABASE_URL: ecto://playstead:synthetic-secret@db/playstead\n' >"$colon_separated_log/evidence/logs/server.log"
expect_pass redacted_colon_log "$SANITIZER" --input "$colon_separated_log" --output "$TMP_ROOT/colon-separated-log-output"
grep -F '[REDACTED SECRET-BEARING LINE]' "$TMP_ROOT/colon-separated-log-output/logs/server.log" >/dev/null || {
  printf 'FAIL: colon-separated secret-bearing log line was not redacted\n' >&2
  exit 1
}
PASS_COUNT=$((PASS_COUNT + 1))

# WR-04: a connection string with embedded user:pass@ credentials, appearing
# mid-sentence in an exception message rather than as a standalone KEY=value.
embedded_credential_url="$TMP_ROOT/embedded-credential-url"
make_valid "$embedded_credential_url"
printf 'connection refused while dialing postgres://playstead:synthetic-secret@127.0.0.1:5432/playstead_ci\n' >"$embedded_credential_url/evidence/logs/app.log"
expect_pass redacted_credential_url "$SANITIZER" --input "$embedded_credential_url" --output "$TMP_ROOT/embedded-credential-url-output"
grep -F '[REDACTED SECRET-BEARING LINE]' "$TMP_ROOT/embedded-credential-url-output/logs/app.log" >/dev/null || {
  printf 'FAIL: embedded user:pass@ connection string was not redacted\n' >&2
  exit 1
}
PASS_COUNT=$((PASS_COUNT + 1))

# 04-UAT G-04-9: the reachability sweep (04-18) writes a static-sweep summary
# into the evidence directory under the *-tests.json name. The validator matched
# it by filename and rejected it as malformed xctest evidence, which aborted
# sanitization partway and truncated the failure evidence for every failing run.
# Positive: the sweep's real shape is accepted and reaches the output.
reachability_ok="$TMP_ROOT/reachability-ok"
make_valid "$reachability_ok"
printf '%s\n' '{"exit_status":0,"kind":"static-sweep","layer":"reachability","outcome":"passed"}' >"$reachability_ok/evidence/reachability-tests.json"
expect_pass reachability_sweep_accepted "$SANITIZER" --input "$reachability_ok" --output "$TMP_ROOT/reachability-ok-output"
grep -F '"static-sweep"' "$TMP_ROOT/reachability-ok-output/reachability-tests.json" >/dev/null || {
  printf 'FAIL: static-sweep evidence did not reach the sanitized output\n' >&2
  exit 1
}
PASS_COUNT=$((PASS_COUNT + 1))

# Negative: claiming to be a static sweep must not become a way to smuggle an
# arbitrary shape past the validator.
reachability_bad="$TMP_ROOT/reachability-bad"
make_valid "$reachability_bad"
printf '%s\n' '{"kind":"static-sweep","layer":"reachability","outcome":"passed","exit_status":0,"extra":"unvalidated"}' >"$reachability_bad/evidence/reachability-tests.json"
expect_fail reachability_sweep_extra_key_rejected "$SANITIZER" --input "$reachability_bad" --output "$TMP_ROOT/reachability-bad-output"

# Negative: an outcome the aggregate cannot interpret must still be rejected.
reachability_outcome="$TMP_ROOT/reachability-outcome"
make_valid "$reachability_outcome"
printf '%s\n' '{"kind":"static-sweep","layer":"reachability","outcome":"maybe","exit_status":0}' >"$reachability_outcome/evidence/reachability-tests.json"
expect_fail reachability_sweep_bad_outcome_rejected "$SANITIZER" --input "$reachability_outcome" --output "$TMP_ROOT/reachability-outcome-output"

# Negative: real xctest evidence must NOT gain a bypass -- a layer file without
# the static-sweep marker still goes through the full test-evidence validator.
xctest_still_strict="$TMP_ROOT/xctest-still-strict"
make_valid "$xctest_still_strict"
printf '%s\n' '{"layer":"ui","outcome":"passed"}' >"$xctest_still_strict/evidence/ui-tests.json"
expect_fail xctest_evidence_still_strict "$SANITIZER" --input "$xctest_still_strict" --output "$TMP_ROOT/xctest-still-strict-output"

# WINDOWS: the real defect this file exists to prevent recurred anyway. The
# writer in run-mac-verification.sh grew a timing block (c3f51e1) and the
# validator's allowlist did not, so EVERY layer file was rejected -- yet this
# guard stayed green, because make_valid hand-writes its fixture and a test
# that decodes its own fixture cannot see a wrong shipped shape. Worse, the
# sanitizer runs only when a layer has already failed, so the breakage was
# invisible on green runs and destroyed the evidence of exactly the red runs
# that needed it.
#
# So do not assert against a fixture alone. Derive the key set from the
# SHIPPED writer and require the shipped validator to accept a file carrying
# it. A key added on either side fails this check on the next run, green or red.
writer_shape="$TMP_ROOT/writer-shape"
make_valid "$writer_shape"
python3 - "${SCRIPT_DIR}/../run-mac-verification.sh" "$writer_shape/evidence/ui-tests.json" <<'WRITERSHAPE'
import json, pathlib, re, sys

script = pathlib.Path(sys.argv[1]).read_text()
marker = "\nsummary = {\n"
if script.count(marker) != 1:
    raise SystemExit("the per-layer summary literal is not uniquely locatable")
body = script[script.index(marker) + len(marker):]
body = body[:body.index("\n}\n")]
# Keys of the summary dict literal sit at exactly four spaces of indent;
# nested dict and list entries are indented further and are not keys.
writer_keys = set(re.findall(r'^    "([a-z_]+)":', body, re.M))
if len(writer_keys) < 10:
    raise SystemExit(f"writer key extraction found only {len(writer_keys)} key(s); the literal moved")

data = json.loads(pathlib.Path(sys.argv[2]).read_text())
missing = sorted(writer_keys - set(data))
unexpected = sorted(set(data) - writer_keys)
if missing or unexpected:
    raise SystemExit(
        f"evidence fixture has drifted from the shipped writer: "
        f"missing={missing} unexpected={unexpected}"
    )
print(f"writer emits {len(writer_keys)} key(s); fixture carries all of them")
WRITERSHAPE
expect_pass writer_shape_accepted_by_validator "$SANITIZER" --input "$writer_shape" --output "$TMP_ROOT/writer-shape-output"

continuation_matrix="$TMP_ROOT/continuation-matrix"
mkdir -p "$continuation_matrix"
python3 - "$continuation_matrix" <<'PY'
import json,pathlib,sys,uuid
root=pathlib.Path(sys.argv[1])
for stage in ("preflight","qualification","initial-save","safe-exit","fresh-launch","continue","oracle"):
    for outcome in ("passed","failed-stage","blocked-capability"):
        evidence=root/(stage+"-"+outcome)/"evidence"
        evidence.mkdir(parents=True)
        (evidence/"continuation.json").write_text(json.dumps({"schema":"playstead.continuation-local.v1","run_id":str(uuid.uuid4()),"stage":stage,"outcome":outcome}))
PY
for stage in preflight qualification initial-save safe-exit fresh-launch continue oracle; do
  for outcome in passed failed-stage blocked-capability; do
    name="continuation-$stage-$outcome"
    case "$stage/$outcome" in
      preflight/blocked-capability|qualification/blocked-capability|initial-save/failed-stage|safe-exit/failed-stage|fresh-launch/failed-stage|continue/failed-stage|oracle/failed-stage|oracle/passed)
        expect_pass "$name" "$SANITIZER" --input "$continuation_matrix/$stage-$outcome" --output "$TMP_ROOT/$name-output" ;;
      *) expect_fail "$name" "$SANITIZER" --input "$continuation_matrix/$stage-$outcome" --output "$TMP_ROOT/$name-output" ;;
    esac
  done
done

if [ "$FAIL_COUNT" -ne 0 ]; then
  printf 'evidence sanitizer: %d check(s) failed\n' "$FAIL_COUNT" >&2
  exit 1
fi
printf 'evidence sanitizer: %d positive/negative checks passed\n' "$PASS_COUNT"
