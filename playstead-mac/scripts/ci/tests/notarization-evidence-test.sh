#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
CAPTURE="${MAC_ROOT}/scripts/ci/capture-notarization-evidence.sh"
VERIFY_SCRIPT="${MAC_ROOT}/scripts/verify-notarized-release.sh"
SANITIZER="${MAC_ROOT}/scripts/ci/sanitize-evidence.sh"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/playstead-notarization-evidence.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

ASSERTION_COUNT=0

fail() {
  printf 'notarization-evidence-test: FAIL: %s\n' "$*" >&2
  exit 1
}

expect_capture_failure() {
  local name="$1"
  local expected_status="$2"
  local output="$3"
  shift 3

  rm -f "$output"
  set +e
  "$CAPTURE" --output "$output" -- "$@" >"$WORK_DIR/${name}.stdout" 2>"$WORK_DIR/${name}.stderr"
  local status=$?
  set -e

  [ "$status" -eq "$expected_status" ] || fail "$name returned $status, expected $expected_status"
  [ ! -e "$output" ] || fail "$name left a durable destination"
  ASSERTION_COUNT=$((ASSERTION_COUNT + 2))
}

[ -x "$CAPTURE" ] || fail "capture-notarization-evidence.sh is missing or not executable"
ASSERTION_COUNT=$((ASSERTION_COUNT + 1))

python3 - "$VERIFY_SCRIPT" <<'PY'
import pathlib
import re
import sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
required = (
    "--evidence-output",
    "capture-notarization-evidence.sh",
    "PLAYSTEAD_EVIDENCE_CAPTURE_CAPABILITY_FILE",
    "PLAYSTEAD_EVIDENCE_CAPTURE_CAPABILITY_TOKEN",
    "INVALID_EVIDENCE_CAPTURE_CAPABILITY",
)
missing = [token for token in required if token not in source]
if missing:
    raise SystemExit(f"production verifier is missing sanitized-capture wiring: {', '.join(missing)}")

for pattern in (
    r">{1,2}\s*\"?\$\{?EVIDENCE_OUTPUT",
    r"\btee\b[^\n]*\$\{?EVIDENCE_OUTPUT",
    r"\b(?:cp|mv)\b[^\n]*\$\{?EVIDENCE_OUTPUT",
):
    if re.search(pattern, source):
        raise SystemExit(f"production verifier writes directly to evidence destination: {pattern}")
PY
ASSERTION_COUNT=$((ASSERTION_COUNT + 1))

SUCCESS_OUTPUT="$WORK_DIR/success.log"
"$CAPTURE" --output "$SUCCESS_OUTPUT" -- bash -c \
  'printf "Accepted notarization for /Users/example/Build/Playstead.app\nAuthorization: Bearer synthetic-secret\n"'

[ -s "$SUCCESS_OUTPUT" ] || fail "successful capture did not publish a non-empty transcript"
grep -F 'Accepted notarization for [PATH]' "$SUCCESS_OUTPUT" >/dev/null || fail "local path was not redacted"
grep -F '[REDACTED SECRET-BEARING LINE]' "$SUCCESS_OUTPUT" >/dev/null || fail "secret-bearing line was not redacted"
if grep -F 'synthetic-secret' "$SUCCESS_OUTPUT" >/dev/null; then
  fail "raw secret reached the durable transcript"
fi
ASSERTION_COUNT=$((ASSERTION_COUNT + 4))

CAPABILITY_OUTPUT="$WORK_DIR/capability.log"
"$CAPTURE" --output "$CAPABILITY_OUTPUT" -- bash -c '
  [ -n "${PLAYSTEAD_EVIDENCE_CAPTURE_CAPABILITY_FILE:-}" ]
  [ -n "${PLAYSTEAD_EVIDENCE_CAPTURE_CAPABILITY_TOKEN:-}" ]
  [ "$(cat "$PLAYSTEAD_EVIDENCE_CAPTURE_CAPABILITY_FILE")" = "$PLAYSTEAD_EVIDENCE_CAPTURE_CAPABILITY_TOKEN" ]
  printf "helper-issued capability observed\n"
'
grep -Fx 'helper-issued capability observed' "$CAPABILITY_OUTPUT" >/dev/null || \
  fail "capture helper did not issue its child a matching private capability"
ASSERTION_COUNT=$((ASSERTION_COUNT + 1))

FAILURE_OUTPUT="$WORK_DIR/failure.log"
set +e
"$CAPTURE" --output "$FAILURE_OUTPUT" -- bash -c \
  'printf "failure at /private/tmp/release-build\n" >&2; exit 23'
FAILURE_STATUS=$?
set -e
[ "$FAILURE_STATUS" -eq 23 ] || fail "wrapped status was $FAILURE_STATUS, expected 23"
[ -s "$FAILURE_OUTPUT" ] || fail "failed command diagnostic was not published"
grep -F 'failure at [PATH]' "$FAILURE_OUTPUT" >/dev/null || fail "failed command diagnostic was not sanitized"
ASSERTION_COUNT=$((ASSERTION_COUNT + 3))

expect_capture_failure empty 1 "$WORK_DIR/empty.log" bash -c ':'

expect_capture_failure oversized 1 "$WORK_DIR/oversized.log" bash -c \
  'python3 -c '\''import sys; sys.stdout.write("x" * (256 * 1024 + 1))'\'''

expect_capture_failure binary 1 "$WORK_DIR/binary.log" bash -c \
  'printf "\\377\\376\\000"'

expect_capture_failure nul_byte 1 "$WORK_DIR/nul-byte.log" bash -c \
  'printf "valid-prefix\\000valid-suffix\\n"'

SYMLINKED_INPUT="$WORK_DIR/symlinked-input"
mkdir -p "$SYMLINKED_INPUT/evidence"
printf 'safe-looking transcript\n' >"$SYMLINKED_INPUT/target.log"
ln -s "$SYMLINKED_INPUT/target.log" "$SYMLINKED_INPUT/evidence/notarization.log"
set +e
"$SANITIZER" --input "$SYMLINKED_INPUT" --output "$WORK_DIR/symlinked-sanitized" \
  >"$WORK_DIR/symlinked-input.stdout" 2>"$WORK_DIR/symlinked-input.stderr"
SYMLINKED_INPUT_STATUS=$?
set -e
[ "$SYMLINKED_INPUT_STATUS" -ne 0 ] || fail "symlinked notarization transcript was accepted"
[ ! -e "$WORK_DIR/symlinked-sanitized/notarization.log" ] || fail "symlinked transcript reached sanitizer output"
ASSERTION_COUNT=$((ASSERTION_COUNT + 2))

SYMLINK_OUTPUT="$WORK_DIR/symlink.log"
SYMLINK_TARGET="$WORK_DIR/symlink-target.log"
printf 'must remain unchanged\n' >"$SYMLINK_TARGET"
ln -s "$SYMLINK_TARGET" "$SYMLINK_OUTPUT"
set +e
"$CAPTURE" --output "$SYMLINK_OUTPUT" -- printf 'safe\n' >"$WORK_DIR/symlink.stdout" 2>"$WORK_DIR/symlink.stderr"
SYMLINK_STATUS=$?
set -e
[ "$SYMLINK_STATUS" -ne 0 ] || fail "symlink destination was accepted"
grep -Fx 'must remain unchanged' "$SYMLINK_TARGET" >/dev/null || fail "symlink target was modified"
ASSERTION_COUNT=$((ASSERTION_COUNT + 2))

set +e
"$CAPTURE" --output / -- printf 'safe\n' >"$WORK_DIR/root.stdout" 2>"$WORK_DIR/root.stderr"
ROOT_STATUS=$?
set -e
[ "$ROOT_STATUS" -ne 0 ] || fail "root output target was accepted"
ASSERTION_COUNT=$((ASSERTION_COUNT + 1))

[ "$ASSERTION_COUNT" -gt 0 ] || fail "0 assertions ran — fail-open"
printf 'notarization-evidence-test: %s assertions ran\n' "$ASSERTION_COUNT"
printf 'PASS: notarization evidence is sanitized before durable publication\n'
