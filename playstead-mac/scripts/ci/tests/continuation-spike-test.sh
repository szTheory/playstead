#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIKE="$SCRIPT_DIR/../continuation-spike.sh"
RUNNER="$SCRIPT_DIR/../continuation-isolation-runner.sh"
SANITIZER="$SCRIPT_DIR/../sanitize-evidence.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/playstead-continuation-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

bash -n "$SPIKE" "$RUNNER"

# Unknown/missing selectors must refuse before even opening contract or receipt
# inputs. Sentinel paths are deliberately invalid and must never be surfaced.
if env -u PLAYSTEAD_CONTINUATION_ISOLATION_MECHANISM \
  PLAYSTEAD_CONTINUATION_CONTRACT="$TMP_ROOT/private-contract-sentinel" \
  PLAYSTEAD_RECOVERY_E2E_RECEIPT="$TMP_ROOT/private-receipt-sentinel" \
  PLAYSTEAD_CONTINUATION_ADAPTER="$TMP_ROOT/private-adapter-sentinel" \
  "$SPIKE" >"$TMP_ROOT/result.json" 2>"$TMP_ROOT/error.log"; then
  printf '%s\n' 'FAIL: continuation passed without an isolation selector' >&2; exit 1
fi
python3 - "$TMP_ROOT/result.json" <<'PY'
import json,pathlib,sys
d=json.loads(pathlib.Path(sys.argv[1]).read_text())
assert set(d)=={"schema","run_id","stage","outcome"}
assert d["schema"]=="playstead.continuation-local.v1" and d["stage"]=="preflight" and d["outcome"]=="blocked-capability"
PY
! rg -q 'private-contract-sentinel|private-receipt-sentinel|private-adapter-sentinel|CONTINUATION_FIXTURE|fixture_id' "$TMP_ROOT/result.json" "$TMP_ROOT/error.log"

# Selector substitution is rejected by the parent runner before adapter lookup.
for selector in arbitrary-command 'macos-seatbelt-v1;id' linux-bwrap-v1; do
  if PLAYSTEAD_CONTINUATION_ISOLATION_MECHANISM="$selector" \
      "$RUNNER" probe >"$TMP_ROOT/probe.out" 2>"$TMP_ROOT/probe.err"; then
    if [ "$selector" != linux-bwrap-v1 ] || [ "$(uname -s)" != Linux ]; then
      printf 'FAIL: unsupported selector %s qualified\n' "$selector" >&2; exit 1
    fi
  fi
  ! rg -q 'adapter|fixture|contract|private|qualified' "$TMP_ROOT/probe.out" "$TMP_ROOT/probe.err"
done

# Standalone child actions are intentionally unavailable; only the spike can
# prepare a checked root and invoke fixture-bearing actions in-process.
for action in qualify initial-run continue; do
  if PLAYSTEAD_CONTINUATION_ISOLATION_MECHANISM=macos-seatbelt-v1 \
      PLAYSTEAD_CONTINUATION_ADAPTER="$TMP_ROOT/private-adapter-sentinel" \
      PLAYSTEAD_CONTINUATION_PRIVATE_ROOT="$TMP_ROOT/private-root-sentinel" \
      "$RUNNER" "$action" >"$TMP_ROOT/standalone-action.out" 2>"$TMP_ROOT/standalone-action.err"; then
    printf 'FAIL: standalone %s action was accepted\n' "$action" >&2; exit 1
  fi
  ! rg -q 'private-adapter-sentinel|private-root-sentinel|CONTINUATION_RESULT' "$TMP_ROOT/standalone-action.out" "$TMP_ROOT/standalone-action.err"
done

# Sanitizer recognizes only the reduced local continuation vocabulary.
mkdir -m 700 -p "$TMP_ROOT/evidence"
printf '%s\n' '{"schema":"playstead.continuation-local.v1","run_id":"123e4567-e89b-42d3-a456-426614174000","stage":"preflight","outcome":"blocked-capability"}' >"$TMP_ROOT/evidence/continuation.json"
"$SANITIZER" --input "$TMP_ROOT" --output "$TMP_ROOT/sanitized" >/dev/null
python3 - "$TMP_ROOT/sanitized/continuation.json" <<'PY'
import json,pathlib,sys
d=json.loads(pathlib.Path(sys.argv[1]).read_text())
assert set(d)=={"schema","run_id","stage","outcome"} and d["outcome"]=="blocked-capability"
PY

for bad in \
  '{"schema":"playstead.continuation-local.v1","run_id":"123e4567-e89b-42d3-a456-426614174000","stage":"preflight","outcome":"passed"}' \
  '{"schema":"playstead.continuation-local.v1","run_id":"123e4567-e89b-42d3-a456-426614174000","stage":"oracle","outcome":"blocked-capability","fixture_path":"/private/sentinel"}' \
  '{"schema":"playstead.continuation-local.v1","run_id":"not-a-uuid","stage":"oracle","outcome":"passed"}'; do
  printf '%s\n' "$bad" >"$TMP_ROOT/evidence/continuation.json"
  if "$SANITIZER" --input "$TMP_ROOT" --output "$TMP_ROOT/sanitized" >/dev/null 2>&1; then
    printf '%s\n' 'FAIL: malformed continuation evidence was sanitized' >&2; exit 1
  fi
done

printf '%s\n' '{"schema":"playstead.continuation-local.v1","run_id":"123e4567-e89b-42d3-a456-426614174000","stage":"oracle","outcome":"passed"}' >"$TMP_ROOT/evidence/continuation.json"
"$SANITIZER" --input "$TMP_ROOT" --output "$TMP_ROOT/sanitized" >/dev/null
python3 - "$TMP_ROOT/sanitized/continuation.json" <<'PY'
import json,pathlib,sys
d=json.loads(pathlib.Path(sys.argv[1]).read_text())
assert d["stage"]=="oracle" and d["outcome"]=="passed" and set(d)=={"schema","run_id","stage","outcome"}
PY

python3 "$SCRIPT_DIR/continuation-process-double-test.py"

printf '%s\n' 'continuation spike blocked-first protocol tests passed'
