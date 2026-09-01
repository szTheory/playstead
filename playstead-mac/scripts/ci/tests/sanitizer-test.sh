#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANITIZER="${SCRIPT_DIR}/../sanitize-evidence.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/playstead-sanitizer.XXXXXX")"
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

make_valid() {
  local root="$1"
  mkdir -p "$root/evidence/snapshot-triplet" "$root/evidence/storage-candidate" "$root/evidence/logs" "$root/raw/Unit.xcresult" "$root/DerivedData"
  printf '%s\n' '{"schema_version":1,"architecture":"arm64","xcode":["Xcode 26.6","Build version 17F113"]}' >"$root/evidence/environment-fingerprint.json"
  printf '%s\n' '{"schema_version":1,"build_count":1,"automatic_retries":0,"aggregate_outcome":"failed","layers":[]}' >"$root/evidence/layers.json"
  printf '%s\n' '{"schema_version":1,"layer":"ui","executed_test_count":2,"required_tests":[{"identifier":"PlaysteadUITests.HostedRunnerCanaryTests/testScopedFileKeychainStoresLoadsAndDeletesTwice","discovered":true,"execution_count":1,"skipped":false,"outcome":"passed"}],"failed_test_count":1,"failed_tests_truncated":false,"failed_tests":[{"identifier":"SurfaceAccessibilityTests/testSyntheticFailure()","outcome":"failed"}],"failure_diagnostic_count":1,"failure_diagnostics_truncated":false,"failure_diagnostics":[{"test_identifier":"SurfaceAccessibilityTests/testSyntheticFailure()","assertion":"XCTAssertTrue","source_file":"PlaysteadUITests/SurfaceAccessibilityTests.swift","source_line":137}],"audit_issue_count":1,"audit_issues_truncated":false,"audit_issues":[{"test_identifier":"SurfaceAccessibilityTests/testSyntheticFailure()","category":"parentChild","element_identifier":"playstead.surface.library","element_role":"role-3"}]}' >"$root/evidence/ui-tests.json"
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

if [ "$FAIL_COUNT" -ne 0 ]; then
  printf 'evidence sanitizer: %d check(s) failed\n' "$FAIL_COUNT" >&2
  exit 1
fi
printf 'evidence sanitizer: %d positive/negative checks passed\n' "$PASS_COUNT"
