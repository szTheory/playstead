#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFIER="${SCRIPT_DIR}/../run-mac-verification.sh"
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
data = {
    "testPlanConfigurations": [],
    "devices": [],
    "testNodes": [{"nodeType": "Test Plan", "name": "Unit", "children": [case] * int(duplicates)}],
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

for result in Failed Skipped unknown; do
  fixture="$TMP_ROOT/${result}.json"
  write_fixture "$fixture" "$result"
  expect_fail "result_${result}" verify_fixture "$fixture"
done

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
