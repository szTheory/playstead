#!/usr/bin/env bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPO_ROOT="$(cd "${MAC_ROOT}/.." && pwd)"
HELPER="${SCRIPT_DIR}/reliability-load.py"
EVIDENCE_DIR="${MAC_ROOT}/.build/phase06-reliability"
APFS_RESULT="${EVIDENCE_DIR}/apfs.json"
SETUP_RESULT="${EVIDENCE_DIR}/setup-wizard.json"
SAVE_RESULT="${EVIDENCE_DIR}/save-e2e.json"
RUNS=10
DEADLINE_SECONDS=1800
TEST_ID="PlaysteadUITests/SaveEndToEndTests/testOneSaveRoundTripsCaptureUploadAndJournalReturn"

usage() {
  printf '%s\n' 'Usage: repeat-save-e2e-reliability.sh --runs 10 --deadline-seconds 1800' >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --runs)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      RUNS="$2"
      shift 2
      ;;
    --deadline-seconds)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      DEADLINE_SECONDS="$2"
      shift 2
      ;;
    *) usage; exit 2 ;;
  esac
done

[ "$RUNS" = 10 ] && [ "$DEADLINE_SECONDS" = 1800 ] || { usage; exit 2; }
if [ -L "${MAC_ROOT}/.build" ] || { [ -e "${MAC_ROOT}/.build" ] && [ ! -d "${MAC_ROOT}/.build" ]; }; then
  printf '%s\n' 'save-e2e reliability: ignored evidence parent identity is invalid' >&2
  exit 77
fi
mkdir -p "${MAC_ROOT}/.build"
if [ -L "$EVIDENCE_DIR" ] || { [ -e "$EVIDENCE_DIR" ] && [ ! -d "$EVIDENCE_DIR" ]; }; then
  printf '%s\n' 'save-e2e reliability: ignored evidence directory identity is invalid' >&2
  exit 77
fi
mkdir -p "$EVIDENCE_DIR"
chmod 700 "$EVIDENCE_DIR"
if [ -e "$SAVE_RESULT" ] || [ -L "$SAVE_RESULT" ]; then
  [ ! -L "$SAVE_RESULT" ] && [ -f "$SAVE_RESULT" ] || {
    printf '%s\n' 'save-e2e reliability: prior result identity is invalid' >&2
    exit 77
  }
  rm "$SAVE_RESULT"
fi
[ -x "$(xcode-select -p)/usr/bin/xcodebuild" ] || { printf '%s\n' 'save-e2e reliability: xcodebuild is unavailable' >&2; exit 77; }
[ -f "$HELPER" ] && [ -x "${SCRIPT_DIR}/run-mac-verification.sh" ] || {
  printf '%s\n' 'save-e2e reliability: project runner inputs are unavailable' >&2
  exit 77
}

upstream_json="$(python3 "$HELPER" validate-upstream --repo-root "$REPO_ROOT" \
  --apfs-manifest "$APFS_RESULT" --setup-manifest "$SETUP_RESULT")" || {
  printf '%s\n' 'save-e2e reliability: APFS and setup-wizard evidence is missing, incomplete, or from another source snapshot' >&2
  exit 77
}
SOURCE_HEAD="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["source_head"])' <<<"$upstream_json")"
SOURCE_FINGERPRINT="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["source_fingerprint"])' <<<"$upstream_json")"

# Local UI-test app launches use the installed Apple Development identity when
# the owner has configured a team. Hosted CI and machines without that local
# identity keep the ordinary ad-hoc lane. The verification runner uses manual
# signing with an empty profile specifier, so this never creates or downloads
# a provisioning profile.
SIGNING_MODE="${PLAYSTEAD_MAC_CI_SIGNING_MODE:-}"
if [ -z "$SIGNING_MODE" ]; then
  if [ "${GITHUB_ACTIONS:-}" != "true" ] && [ -n "${PLAYSTEAD_TEAM_ID:-}" ]; then
    SIGNING_MODE="development"
  else
    SIGNING_MODE="adhoc"
  fi
fi
case "$SIGNING_MODE" in
  adhoc|development) ;;
  *) printf '%s\n' 'save-e2e reliability: signing mode must be adhoc or development' >&2; exit 77 ;;
esac

OWNER="$(/usr/bin/uuidgen | tr '[:upper:]' '[:lower:]')"
RUN_ROOT="$(mktemp -d /private/tmp/playstead-save-e2e-reliability.XXXXXX)"
chmod 700 "$RUN_ROOT"
printf '%s' "$OWNER" >"${RUN_ROOT}/.owner"
chmod 600 "${RUN_ROOT}/.owner"
mkdir -m 700 "${RUN_ROOT}/raw" "${RUN_ROOT}/evidence" "${RUN_ROOT}/build"
BUILD_ROOT="${RUN_ROOT}/build"
started_at="$(date +%s)"

PACKAGE_SOURCE="${PLAYSTEAD_RELIABILITY_PACKAGE_SOURCE:-}"
PACKAGE_CACHE_SOURCE="${PLAYSTEAD_RELIABILITY_PACKAGE_CACHE:-}"
if [ -n "$PACKAGE_SOURCE" ]; then
  [ -d "$PACKAGE_SOURCE/checkouts" ] && [ ! -L "$PACKAGE_SOURCE" ] || {
    printf '%s\n' 'save-e2e reliability: package source cache identity is invalid' >&2
    exit 77
  }
  ditto "$PACKAGE_SOURCE" "${BUILD_ROOT}/SourcePackages"
fi
if [ -n "$PACKAGE_CACHE_SOURCE" ]; then
  [ -d "$PACKAGE_CACHE_SOURCE" ] && [ ! -L "$PACKAGE_CACHE_SOURCE" ] || {
    printf '%s\n' 'save-e2e reliability: package cache identity is invalid' >&2
    exit 77
  }
  ditto "$PACKAGE_CACHE_SOURCE" "${BUILD_ROOT}/PackageCache"
fi

verify_root() {
  python3 - "$RUN_ROOT" "$OWNER" <<'PY'
import pathlib, stat, sys
root = pathlib.Path(sys.argv[1])
marker = root / ".owner"
if root.is_symlink() or not root.is_dir() or stat.S_IMODE(root.stat().st_mode) & 0o077:
    raise SystemExit(77)
if marker.is_symlink() or not marker.is_file() or stat.S_IMODE(marker.stat().st_mode) != 0o600:
    raise SystemExit(77)
if marker.read_text(encoding="ascii") != sys.argv[2]:
    raise SystemExit(77)
PY
}

selected_roots() {
  find "$BUILD_ROOT" -maxdepth 1 -type d -name 'selected-live-server.*' -print | sort
}

verify_root
passed=0
for iteration in $(seq 1 "$RUNS"); do
  verify_root || { printf '%s\n' 'save-e2e reliability: run-root ownership mismatch' >&2; exit 77; }
  elapsed=$(($(date +%s) - started_at))
  remaining=$((DEADLINE_SECONDS - elapsed))
  if [ "$remaining" -le 0 ]; then
    printf '%s\n' 'save-e2e reliability: 30-minute deadline reached' >&2
    exit 124
  fi

  before="${RUN_ROOT}/raw/iteration-${iteration}-selected-before.txt"
  after="${RUN_ROOT}/raw/iteration-${iteration}-selected-after.txt"
  selected_roots >"$before"
  chmod 600 "$before"
  log="${RUN_ROOT}/raw/iteration-${iteration}.log"
  status=0
  (
    cd "$MAC_ROOT"
    python3 "$HELPER" command --timeout-seconds "$remaining" --log-path "$log" -- \
      /usr/bin/env \
      PLAYSTEAD_HUMAN_APPROVED_LOCAL_APP_LAUNCH=1 \
      PLAYSTEAD_MAC_CI_SIGNING_MODE="$SIGNING_MODE" \
      PLAYSTEAD_CI_BUILD_ROOT="$BUILD_ROOT" \
      "${SCRIPT_DIR}/run-mac-verification.sh" --layers live-server --only-testing "$TEST_ID"
  ) || status=$?
  selected_roots >"$after"
  chmod 600 "$after"
  if [ "$status" -ne 0 ]; then
    printf 'save-e2e reliability: iteration=%s failed exit=%s; private diagnostics retained under the owned temporary root\n' "$iteration" "$status" >&2
    exit "$status"
  fi

  new_root="$(comm -13 "$before" "$after")"
  [ -n "$new_root" ] && [ "$(printf '%s\n' "$new_root" | wc -l | tr -d ' ')" = 1 ] || {
    printf 'save-e2e reliability: iteration=%s did not produce exactly one isolated result directory\n' "$iteration" >&2
    exit 77
  }
  sanitized="${new_root}/sanitized/save-reliability.json"
  [ -f "$sanitized" ] && [ ! -L "$sanitized" ] || {
    printf 'save-e2e reliability: iteration=%s sanitized refusal evidence is missing\n' "$iteration" >&2
    exit 77
  }
  install -m 600 "$sanitized" "${RUN_ROOT}/evidence/iteration-${iteration}.json"
  passed=$((passed + 1))
  printf 'save-e2e reliability: iteration=%s/%s passed\n' "$iteration" "$RUNS"
done

[ "$passed" -eq 10 ] || { printf '%s\n' 'save-e2e reliability: fewer than ten rounds completed' >&2; exit 1; }

ledger="${REPO_ROOT}/.planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-RELIABILITY-EVIDENCE.md"
upstream_after="$(python3 "$HELPER" validate-upstream --repo-root "$REPO_ROOT" \
  --apfs-manifest "$APFS_RESULT" --setup-manifest "$SETUP_RESULT")" || {
  printf '%s\n' 'save-e2e reliability: bounded evidence no longer matches the current source snapshot' >&2
  exit 77
}
python3 - "$RUN_ROOT" "$OWNER" "$ledger" "$started_at" "$SAVE_RESULT" "$SOURCE_HEAD" "$SOURCE_FINGERPRINT" "$upstream_after" "$APFS_RESULT" "$SETUP_RESULT" <<'PY'
import json, os, pathlib, re, stat, sys, time

root = pathlib.Path(sys.argv[1])
owner = sys.argv[2]
ledger = pathlib.Path(sys.argv[3])
started_at = int(sys.argv[4])
save_result = pathlib.Path(sys.argv[5])
source_head, source_fingerprint = sys.argv[6:8]
upstream = json.loads(sys.argv[8])
apfs_path, setup_path = map(pathlib.Path, sys.argv[9:11])
marker = root / ".owner"
if root.is_symlink() or not root.is_dir() or stat.S_IMODE(root.stat().st_mode) != 0o700:
    raise SystemExit("save-e2e reliability evidence root is not private")
if marker.is_symlink() or marker.read_text(encoding="ascii") != owner:
    raise SystemExit("save-e2e reliability evidence root identity changed")
if (upstream.get("source_head"), upstream.get("source_fingerprint")) != (source_head, source_fingerprint):
    raise SystemExit("save-e2e reliability shared source snapshot changed")
if json.loads(apfs_path.read_text(encoding="utf-8")) != upstream.get("apfs") or json.loads(setup_path.read_text(encoding="utf-8")) != upstream.get("setup"):
    raise SystemExit("save-e2e reliability upstream manifests changed during the run")

pattern = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}")
records = []
for iteration in range(1, 11):
    path = root / "evidence" / f"iteration-{iteration}.json"
    if path.is_symlink() or not path.is_file() or stat.S_IMODE(path.stat().st_mode) != 0o600:
        raise SystemExit(f"save-e2e reliability iteration {iteration} evidence identity or mode is invalid")
    data = json.loads(path.read_text(encoding="utf-8"))
    if set(data) != {"schema", "round_trip", "transient", "conflict", "probes"}:
        raise SystemExit(f"save-e2e reliability iteration {iteration} schema drifted")
    if data["schema"] != "playstead.save-reliability.v1" or data["round_trip"] != "passed":
        raise SystemExit(f"save-e2e reliability iteration {iteration} round trip did not pass")
    transient, conflict, probes = data["transient"], data["conflict"], data["probes"]
    if transient != {
        "http_status": 503,
        "problem_code": "service_unavailable",
        "failure_classification": "none",
        "failure_cause": "http5xx",
        "escalates": False,
        "correlation_id": transient.get("correlation_id"),
    }:
        raise SystemExit(f"save-e2e reliability iteration {iteration} transient class drifted")
    if conflict != {
        "original_http_status": 201,
        "duplicate_http_status": 409,
        "problem_code": "idempotency_key_conflict",
        "failure_classification": "serverRefusal",
        "failure_cause": "idempotencyConflict",
        "escalates": True,
        "correlation_id": conflict.get("correlation_id"),
    }:
        raise SystemExit(f"save-e2e reliability iteration {iteration} conflict class drifted")
    ids = [transient.get("correlation_id"), conflict.get("correlation_id")]
    if any(not isinstance(value, str) or not pattern.fullmatch(value) for value in ids) or ids[0] == ids[1]:
        raise SystemExit(f"save-e2e reliability iteration {iteration} correlation identity is invalid")
    if probes != {
        "probe_count": 4,
        "max_requests_per_second_per_probe": 2,
        "successful_requests": probes.get("successful_requests"),
        "last_status": [200, 200, 200, 200],
        "failed_requests": [0, 0, 0, 0],
    }:
        raise SystemExit(f"save-e2e reliability iteration {iteration} probe result is invalid")
    requests = probes.get("successful_requests")
    if not isinstance(requests, list) or len(requests) != 4 or any(type(value) is not int or value < 1 for value in requests):
        raise SystemExit(f"save-e2e reliability iteration {iteration} probe counts are invalid")
    records.append((iteration, transient, conflict, requests))

all_ids = [record[1]["correlation_id"] for record in records] + [record[2]["correlation_id"] for record in records]
if len(set(all_ids)) != 20:
    raise SystemExit("save-e2e reliability correlation identifiers were reused")
elapsed = int(__import__("time").time() - started_at)
if elapsed > 1800:
    raise SystemExit("save-e2e reliability run exceeded the 30-minute deadline")
total_requests = sum(sum(record[3]) for record in records)
apfs, setup = upstream["apfs"], upstream["setup"]
save_manifest = {
    "schema": "playstead.reliability-run.v1",
    "case": "save-round-trip-refusal",
    "source_head": source_head,
    "source_fingerprint": source_fingerprint,
    "expected_runs": 10,
    "completed_runs": len(records),
    "passed_runs": len(records),
    "elapsed_seconds": elapsed,
    "probe_count": 4,
    "max_requests_per_second_per_probe": 2,
    "successful_probe_requests": total_requests,
    "transient_http_status": 503,
    "conflict_http_status": 409,
    "correlation_ids": all_ids,
}
temporary = save_result.with_name(save_result.name + ".tmp")
if save_result.exists() or save_result.is_symlink() or temporary.exists() or temporary.is_symlink():
    raise SystemExit("save-e2e reliability result destination already exists")
fd = os.open(temporary, os.O_CREAT | os.O_EXCL | os.O_WRONLY | getattr(os, "O_NOFOLLOW", 0), 0o600)
with os.fdopen(fd, "w", encoding="utf-8") as stream:
    json.dump(save_manifest, stream, sort_keys=True)
    stream.write("\n")
    stream.flush()
    os.fsync(stream.fileno())
os.rename(temporary, save_result)

rows = [
    "# Phase 06 bounded reliability evidence",
    "",
    f"- Shared source: `{source_head}`; non-planning worktree fingerprint `{source_fingerprint}`.",
    "",
    "## APFS backup-exclusion race",
    "",
    f"- Result: {apfs['passed_runs']}/{apfs['expected_runs']} passed in {apfs['elapsed_seconds']} seconds under two scheduler and two I/O workers, with a 64 MiB per-worker scratch cap.",
    "",
    "## Wallaby setup journey",
    "",
    f"- Result: {setup['passed_runs']}/{setup['expected_runs']} independent journeys passed in {setup['elapsed_seconds']} seconds with four bounded loopback health probes at no more than 2 requests/second per probe.",
    f"- Matched Chrome and ChromeDriver build: `{setup['browser_build']}`; successful probe requests: {setup['successful_probe_requests']}.",
    "",
    "## Live save round trip and refusal classification",
    "",
    f"- Result: {len(records)}/10 independent live rounds passed in {elapsed} seconds with four healthy probes per round; total successful probe requests: {total_requests}.",
    "- Each round captured, uploaded and synchronized the synthetic save through the app-owned upload lane after a real server 503. The lane classified it as retryable `http5xx`, retained the server correlation UUID, did not escalate, then succeeded on retry.",
    "- Each round exercised concurrent identical revision POSTs through the real idempotency plug and unique database constraint: the original response was 201 and its true duplicate was 409 `idempotency_key_conflict`. That response classified as `serverRefusal` / `idempotencyConflict` and escalated; it was not retried or converted to success.",
    "- Only fixed classes, status values, probe counts and opaque server correlation UUIDs crossed the sanitizer. No save bytes, digest, token, filename, or local path was retained.",
    "",
    "| Round | Transient response | Retry class | Transient correlation UUID | Duplicate response | Conflict class | Conflict correlation UUID | Probe requests |",
    "|---:|---|---|---|---|---|---|---:|",
]
for iteration, transient, conflict, requests in records:
    rows.append(
        f"| {iteration} | 503 `{transient['problem_code']}` | `{transient['failure_cause']}` (no escalation) | `{transient['correlation_id']}` | 409 `{conflict['problem_code']}` | `{conflict['failure_classification']}` / `{conflict['failure_cause']}` | `{conflict['correlation_id']}` | {sum(requests)} |"
    )
rows.extend([
    "",
    "The raw XCTest bundles, browser output, probe reports and transient control markers remained under private run-owned temporary storage. The rows above were copied from the allowlisted sanitizer output after each round.",
])
ledger.parent.mkdir(parents=True, exist_ok=True)
if ledger.is_symlink() or (ledger.exists() and not ledger.is_file()):
    raise SystemExit("save-e2e reliability ledger destination identity is invalid")
ledger.write_text("\n".join(rows) + "\n", encoding="utf-8")
os.chmod(ledger, 0o644)
PY

printf 'save-e2e reliability: rounds=%s passed=%s probes_per_round=4 max_rps_per_probe=2 elapsed_seconds=%s\n' \
  "$RUNS" "$passed" "$(($(date +%s) - started_at))"
