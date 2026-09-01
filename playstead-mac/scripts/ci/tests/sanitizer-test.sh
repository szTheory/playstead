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
  mkdir -p "$root/evidence/snapshot-triplet" "$root/evidence/logs" "$root/raw/Unit.xcresult" "$root/DerivedData"
  printf '%s\n' '{"schema_version":1,"architecture":"arm64","xcode":["Xcode 26.6","Build version 17F113"]}' >"$root/evidence/environment-fingerprint.json"
  printf '%s\n' '{"schema_version":1,"build_count":1,"automatic_retries":0,"aggregate_outcome":"failed","layers":[]}' >"$root/evidence/layers.json"
  printf '%s\n' '{"schema_version":1,"layer":"ui","executed_test_count":1,"required_tests":[{"identifier":"PlaysteadUITests.HostedRunnerCanaryTests/testScopedFileKeychainStoresLoadsAndDeletesTwice","discovered":true,"execution_count":1,"skipped":false,"outcome":"passed"}]}' >"$root/evidence/ui-tests.json"
  printf 'safe app event at /Users/example/private/location\n' >"$root/evidence/logs/app.log"
  printf 'server health passed\n' >"$root/evidence/logs/server.log"
  printf '\211PNG\r\n\032\nreference' >"$root/evidence/snapshot-triplet/reference.png"
  printf '\211PNG\r\n\032\nactual' >"$root/evidence/snapshot-triplet/actual.png"
  printf '\211PNG\r\n\032\ndiff' >"$root/evidence/snapshot-triplet/diff.png"
  printf 'raw result must stay outside upload' >"$root/raw/Unit.xcresult/raw"
}

valid="$TMP_ROOT/valid"
make_valid "$valid"
expect_pass valid "$SANITIZER" --input "$valid" --output "$TMP_ROOT/output"
grep -F '[PATH]' "$TMP_ROOT/output/logs/app.log" >/dev/null || { printf 'FAIL: local path was not redacted\n' >&2; exit 1; }
[ ! -e "$TMP_ROOT/output/raw" ]
[ ! -e "$TMP_ROOT/output/DerivedData" ]
PASS_COUNT=$((PASS_COUNT + 3))

secret_json="$TMP_ROOT/secret-json"
make_valid "$secret_json"
printf '%s\n' '{"schema_version":1,"authorization":"Bearer secret"}' >"$secret_json/evidence/layers.json"
expect_fail secret_json "$SANITIZER" --input "$secret_json" --output "$TMP_ROOT/secret-json-output"

content_id="$TMP_ROOT/content-id"
make_valid "$content_id"
printf '%s\n' '{"schema_version":1,"name":"private-game.nes"}' >"$content_id/evidence/layers.json"
expect_fail content_identifier "$SANITIZER" --input "$content_id" --output "$TMP_ROOT/content-id-output"

oversized="$TMP_ROOT/oversized"
make_valid "$oversized"
dd if=/dev/zero of="$oversized/evidence/snapshot-triplet/actual.png" bs=1048576 count=3 2>/dev/null
expect_fail oversized "$SANITIZER" --input "$oversized" --output "$TMP_ROOT/oversized-output"

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
