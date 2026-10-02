#!/usr/bin/env bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPO_ROOT="$(cd "${MAC_ROOT}/.." && pwd)"
HELPER="${SCRIPT_DIR}/reliability-load.py"
EVIDENCE_DIR="${MAC_ROOT}/.build/phase06-reliability"
RUN_RESULT="${EVIDENCE_DIR}/apfs.json"
TEST_ID="PlaysteadTests/AppPathsBackupExclusionTests/testExistingInstallWithStaleRootFlagIsRepairedAtInit"
RUNS=20
DEADLINE_SECONDS=1800

usage() {
  printf '%s\n' 'Usage: repeat-apfs-reliability.sh --runs 20 --deadline-seconds 1800' >&2
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

[ "$RUNS" = 20 ] && [ "$DEADLINE_SECONDS" = 1800 ] || { usage; exit 2; }
if [ -L "${MAC_ROOT}/.build" ] || { [ -e "${MAC_ROOT}/.build" ] && [ ! -d "${MAC_ROOT}/.build" ]; }; then
  printf '%s\n' 'APFS reliability: ignored evidence parent identity is invalid' >&2
  exit 77
fi
mkdir -p "${MAC_ROOT}/.build"
if [ -L "$EVIDENCE_DIR" ] || { [ -e "$EVIDENCE_DIR" ] && [ ! -d "$EVIDENCE_DIR" ]; }; then
  printf '%s\n' 'APFS reliability: ignored evidence directory identity is invalid' >&2
  exit 77
fi
mkdir -p "$EVIDENCE_DIR"
chmod 700 "$EVIDENCE_DIR"
if [ -e "$RUN_RESULT" ] || [ -L "$RUN_RESULT" ]; then
  [ ! -L "$RUN_RESULT" ] && [ -f "$RUN_RESULT" ] || {
    printf '%s\n' 'APFS reliability: prior result identity is invalid' >&2
    exit 77
  }
  rm "$RUN_RESULT"
fi
[ -x "$(xcode-select -p)/usr/bin/xcodebuild" ] || { printf '%s\n' 'APFS reliability: xcodebuild is unavailable' >&2; exit 77; }
[ -f "$HELPER" ] && [ -f "${MAC_ROOT}/Playstead.xcodeproj/project.pbxproj" ] && \
  [ -f "${MAC_ROOT}/PlaysteadUITests/PlaysteadUITests.no-hid.entitlements" ] || {
  printf '%s\n' 'APFS reliability: project inputs are unavailable' >&2
  exit 77
}

fingerprint_json="$(python3 "$HELPER" fingerprint --repo-root "$REPO_ROOT")" || {
  printf '%s\n' 'APFS reliability: source fingerprint could not be computed' >&2
  exit 77
}
SOURCE_HEAD="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["source_head"])' <<<"$fingerprint_json")"
SOURCE_FINGERPRINT="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["source_fingerprint"])' <<<"$fingerprint_json")"

OWNER="$(/usr/bin/uuidgen | tr '[:upper:]' '[:lower:]')"
RUN_ROOT="$(mktemp -d /private/tmp/playstead-apfs-reliability.XXXXXX)"
chmod 700 "$RUN_ROOT"
printf '%s' "$OWNER" >"${RUN_ROOT}/.owner"
chmod 600 "${RUN_ROOT}/.owner"
mkdir -m 700 "${RUN_ROOT}/raw" "${RUN_ROOT}/evidence" "${RUN_ROOT}/DerivedData"
mkdir -m 700 "${RUN_ROOT}/UserHome" "${RUN_ROOT}/ModuleCache.noindex"
started_at="$(date +%s)"

LOAD_PID=""
cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if [ -n "$LOAD_PID" ]; then
    kill -TERM "$LOAD_PID" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "$LOAD_PID" 2>/dev/null || break
      sleep 0.2
    done
    if kill -0 "$LOAD_PID" 2>/dev/null; then
      kill -KILL "$LOAD_PID" 2>/dev/null || true
    fi
    wait "$LOAD_PID" 2>/dev/null || true
    LOAD_PID=""
  fi
  if [ -d "$RUN_ROOT" ] && [ ! -L "$RUN_ROOT" ] && [ -f "${RUN_ROOT}/.owner" ] && [ "$(cat "${RUN_ROOT}/.owner")" = "$OWNER" ]; then
    rm -rf "${RUN_ROOT}/scratch-load"
  else
    printf '%s\n' 'APFS reliability: run-root ownership changed; private artifacts were left untouched' >&2
    status=77
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

verify_root() {
  python3 - "$RUN_ROOT" "$OWNER" <<'PY'
import pathlib, stat, sys
root = pathlib.Path(sys.argv[1])
marker = root / ".owner"
if root.is_symlink() or not root.is_dir() or stat.S_IMODE(root.stat().st_mode) & 0o077:
    raise SystemExit(77)
if marker.is_symlink() or not marker.is_file() or marker.read_text(encoding="ascii") != sys.argv[2]:
    raise SystemExit(77)
PY
}

verify_root
mkdir -m 700 "${RUN_ROOT}/scratch-load"
python3 "$HELPER" scratch --root "$RUN_ROOT" --owner "$OWNER" --max-bytes 67108864 \
  >"${RUN_ROOT}/raw/load.log" 2>&1 &
LOAD_PID=$!
load_ready=false
for _ in $(seq 1 100); do
  verify_root || { printf '%s\n' 'APFS reliability: run-root ownership mismatch' >&2; exit 77; }
  if grep -Fxq 'reliability-load-ready scheduler_workers=2 io_workers=2 cap_bytes=67108864' "${RUN_ROOT}/raw/load.log"; then
    load_ready=true
    break
  fi
  if ! kill -0 "$LOAD_PID" 2>/dev/null; then
    printf '%s\n' 'APFS reliability: bounded scratch workers failed to start' >&2
    exit 77
  fi
  sleep 0.1
done
[ "$load_ready" = true ] || { printf '%s\n' 'APFS reliability: bounded scratch workers did not become ready' >&2; exit 77; }

PACKAGE_SOURCE="${PLAYSTEAD_RELIABILITY_PACKAGE_SOURCE:-}"
PACKAGE_CACHE_SOURCE="${PLAYSTEAD_RELIABILITY_PACKAGE_CACHE:-}"
if [ -n "$PACKAGE_SOURCE" ]; then
  [ -d "$PACKAGE_SOURCE/checkouts" ] && [ ! -L "$PACKAGE_SOURCE" ] || { printf '%s\n' 'APFS reliability: package source cache identity is invalid' >&2; exit 77; }
  ditto "$PACKAGE_SOURCE" "${RUN_ROOT}/SourcePackages"
fi
if [ -n "$PACKAGE_CACHE_SOURCE" ]; then
  [ -d "$PACKAGE_CACHE_SOURCE" ] && [ ! -L "$PACKAGE_CACHE_SOURCE" ] || { printf '%s\n' 'APFS reliability: package cache identity is invalid' >&2; exit 77; }
  ditto "$PACKAGE_CACHE_SOURCE" "${RUN_ROOT}/PackageCache"
fi

if [ -n "${PLAYSTEAD_TEAM_ID:-}" ]; then
  [[ "$PLAYSTEAD_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || {
    printf '%s\n' 'APFS reliability: configured development team identity is invalid' >&2
    exit 77
  }
  matching_identities="$(python3 - "$PLAYSTEAD_TEAM_ID" <<'PY'
import re, subprocess, sys
team = sys.argv[1]
identities = subprocess.run(
    ["security", "find-identity", "-v", "-p", "codesigning"],
    check=True, capture_output=True, text=True, timeout=15,
).stdout
names = re.findall(r'^\s*\d+\)\s+[0-9A-F]+\s+"(Apple Development:[^"]+)"', identities, re.M)
matches = 0
for name in names:
    certificate = subprocess.run(
        ["security", "find-certificate", "-c", name, "-p"],
        check=False, capture_output=True, text=True, timeout=10,
    )
    if certificate.returncode:
        continue
    subject = subprocess.run(
        ["openssl", "x509", "-inform", "pem", "-noout", "-subject", "-nameopt", "RFC2253"],
        input=certificate.stdout, check=False, capture_output=True, text=True, timeout=10,
    ).stdout.strip()
    match = re.search(r'(?:^|,)OU=([^,]+)', subject)
    if match and match.group(1) == team:
        matches += 1
print(matches)
PY
)" || {
    printf '%s\n' 'APFS reliability: Apple Development identity lookup failed' >&2
    exit 77
  }
  [ "$matching_identities" -gt 0 ] || {
    printf '%s\n' 'APFS reliability: no Apple Development identity matches the configured team' >&2
    exit 77
  }
  SIGNING_SETTINGS=(CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY='Apple Development' "DEVELOPMENT_TEAM=$PLAYSTEAD_TEAM_ID" PROVISIONING_PROFILE_SPECIFIER=)
else
  SIGNING_SETTINGS=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=)
fi

passed=0
assertion_failures=0
infrastructure_failures=0
for iteration in $(seq 1 "$RUNS"); do
  verify_root || { printf '%s\n' 'APFS reliability: run-root ownership mismatch' >&2; exit 77; }
  now="$(date +%s)"
  elapsed=$((now - started_at))
  remaining=$((DEADLINE_SECONDS - elapsed))
  if [ "$remaining" -le 0 ]; then
    printf '%s\n' 'APFS reliability: 30-minute deadline reached' >&2
    exit 124
  fi

  result_bundle="${RUN_ROOT}/raw/iteration-${iteration}.xcresult"
  result_json="${RUN_ROOT}/raw/iteration-${iteration}-tests.json"
  result_log="${RUN_ROOT}/raw/iteration-${iteration}.log"
  command_status=0
  (
    cd "$MAC_ROOT"
    CFFIXED_USER_HOME="${RUN_ROOT}/UserHome" \
      SWIFTPM_MODULECACHE_OVERRIDE="${RUN_ROOT}/ModuleCache.noindex" \
      SWIFTPM_TESTS_PACKAGECACHE="${RUN_ROOT}/PackageCache" \
      python3 "$HELPER" command --timeout-seconds "$remaining" --log-path "$result_log" -- \
      xcodebuild test -project "${MAC_ROOT}/Playstead.xcodeproj" -scheme Playstead -testPlan Unit \
      -clonedSourcePackagesDirPath "${RUN_ROOT}/SourcePackages" \
      -packageCachePath "${RUN_ROOT}/PackageCache" -disableAutomaticPackageResolution \
      -destination 'platform=macOS' -derivedDataPath "${RUN_ROOT}/DerivedData" \
      -resultBundlePath "$result_bundle" \
      "${SIGNING_SETTINGS[@]}" \
      PLAYSTEAD_UI_TEST_ENTITLEMENTS=PlaysteadUITests/PlaysteadUITests.no-hid.entitlements \
      "-only-testing:${TEST_ID}"
  ) || command_status=$?
  if [ "$command_status" -eq 124 ]; then
    printf '%s\n' 'APFS reliability: 30-minute deadline reached during XCTest' >&2
    exit 124
  fi

  parse_status=0
  xcrun xcresulttool get test-results tests --path "$result_bundle" --compact \
    >"$result_json" 2>"${RUN_ROOT}/raw/iteration-${iteration}-xcresulttool.log" || parse_status=$?
  classification="infrastructure"
  iteration_outcome="failed"
  if [ "$parse_status" -eq 0 ]; then
    if python3 - "$result_json" "$TEST_ID" >"${RUN_ROOT}/raw/iteration-${iteration}-class.txt" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
target = sys.argv[2].rsplit("/", 1)[-1]
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    raise SystemExit(2)
statuses = []
def walk(value):
    if isinstance(value, dict):
        ids = [value.get(key) for key in ("testIdentifier", "nodeIdentifier", "identifier", "name")]
        identity_match = any(
            isinstance(item, str) and (
                item.removesuffix("()") == target or
                item.removesuffix("()").endswith("/" + target) or
                item.removesuffix("()").endswith("." + target)
            )
            for item in ids
        )
        if identity_match:
            for key in ("testStatus", "result", "status"):
                item = value.get(key)
                if isinstance(item, str):
                    statuses.append(item.strip().lower())
                    break
        for child in value.values():
            walk(child)
    elif isinstance(value, list):
        for child in value:
            walk(child)
walk(data)
normalized = {"passed" if value in {"passed", "pass", "success", "succeeded"} else
              "failed" if value in {"failed", "failure", "error", "unexpected failure"} else
              "skipped" if "skip" in value else "unknown" for value in statuses}
if normalized == {"passed"}:
    print("passed")
elif normalized == {"failed"}:
    print("assertion")
elif normalized == {"skipped"}:
    print("skipped")
else:
    raise SystemExit(2)
PY
    then
      parsed_class="$(cat "${RUN_ROOT}/raw/iteration-${iteration}-class.txt")"
      if [ "$parsed_class" = passed ] && [ "$command_status" -eq 0 ]; then
        classification="passed"
        iteration_outcome="passed"
        passed=$((passed + 1))
      elif [ "$parsed_class" = assertion ]; then
        classification="assertion"
        assertion_failures=$((assertion_failures + 1))
      fi
    fi
  fi

  python3 - "$RUN_ROOT" "$OWNER" "$iteration" "$iteration_outcome" "$classification" <<'PY'
import json, os, pathlib, stat, sys
root = pathlib.Path(sys.argv[1])
if root.is_symlink() or not root.is_dir() or stat.S_IMODE(root.stat().st_mode) & 0o077:
    raise SystemExit(77)
if (root / ".owner").read_text(encoding="ascii") != sys.argv[2]:
    raise SystemExit(77)
iteration = int(sys.argv[3])
outcome, failure_class = sys.argv[4:]
if outcome not in {"passed", "failed"} or failure_class not in {"passed", "assertion", "infrastructure"}:
    raise SystemExit(77)
record = {"iteration": iteration, "outcome": outcome, "failure_class": failure_class}
with (root / "evidence" / "runs.jsonl").open("a", encoding="utf-8") as stream:
    stream.write(json.dumps(record, sort_keys=True) + "\n")
os.chmod(root / "evidence" / "runs.jsonl", 0o600)
PY

  printf 'APFS reliability: iteration=%s outcome=%s class=%s\n' "$iteration" "$iteration_outcome" "$classification"
  if [ "$classification" = infrastructure ]; then
    infrastructure_failures=$((infrastructure_failures + 1))
    printf 'APFS reliability: stopped at iteration %s with infrastructure failure\n' "$iteration" >&2
    break
  fi
  if [ "$classification" = passed ]; then
    rm -rf "$result_bundle" "$result_json" "${RUN_ROOT}/raw/iteration-${iteration}-class.txt"
  fi
done

iterations_completed=0
if [ -f "${RUN_ROOT}/evidence/runs.jsonl" ]; then
  iterations_completed="$(wc -l <"${RUN_ROOT}/evidence/runs.jsonl" | tr -d '[:space:]')"
fi
printf 'APFS reliability: iterations=%s passed=%s assertion_failures=%s infrastructure_failures=%s load=scheduler2+io2 worker_cap_mib=64\n' \
  "$iterations_completed" "$passed" "$assertion_failures" "$infrastructure_failures"
if [ "$iterations_completed" -ne 20 ] || [ "$passed" -ne 20 ] || [ "$assertion_failures" -ne 0 ] || [ "$infrastructure_failures" -ne 0 ]; then
  exit 1
fi
if [ "$(($(date +%s) - started_at))" -gt "$DEADLINE_SECONDS" ]; then
  printf '%s\n' 'APFS reliability: 30-minute deadline reached after the final iteration' >&2
  exit 124
fi

fingerprint_after="$(python3 "$HELPER" fingerprint --repo-root "$REPO_ROOT")" || {
  printf '%s\n' 'APFS reliability: final source fingerprint could not be computed' >&2
  exit 77
}
python3 - "$fingerprint_after" "$SOURCE_HEAD" "$SOURCE_FINGERPRINT" <<'PY'
import json, sys
actual = json.loads(sys.argv[1])
if actual != {"source_head": sys.argv[2], "source_fingerprint": sys.argv[3]}:
    raise SystemExit("APFS reliability: source changed during repeated run")
PY

python3 - "$RUN_ROOT" "$OWNER" "$RUN_RESULT" "$SOURCE_HEAD" "$SOURCE_FINGERPRINT" "$started_at" <<'PY'
import json, os, pathlib, stat, sys, time
root = pathlib.Path(sys.argv[1])
owner, destination = sys.argv[2], pathlib.Path(sys.argv[3])
head, fingerprint, started_at = sys.argv[4], sys.argv[5], int(sys.argv[6])
if root.is_symlink() or not root.is_dir() or stat.S_IMODE(root.stat().st_mode) != 0o700:
    raise SystemExit("APFS reliability: evidence root identity changed")
marker = root / ".owner"
if marker.is_symlink() or marker.read_text(encoding="ascii") != owner:
    raise SystemExit("APFS reliability: evidence owner changed")
records = [json.loads(line) for line in (root / "evidence" / "runs.jsonl").read_text(encoding="utf-8").splitlines()]
if len(records) != 20 or any(record != {"iteration": index, "outcome": "passed", "failure_class": "passed"} for index, record in enumerate(records, 1)):
    raise SystemExit("APFS reliability: final run records are incomplete or failed")
manifest = {
    "schema": "playstead.reliability-run.v1",
    "case": "apfs-backup-exclusion",
    "source_head": head,
    "source_fingerprint": fingerprint,
    "expected_runs": 20,
    "completed_runs": len(records),
    "passed_runs": sum(record["outcome"] == "passed" for record in records),
    "assertion_failures": 0,
    "infrastructure_failures": 0,
    "load": "scheduler2+io2",
    "worker_cap_bytes": 67108864,
    "elapsed_seconds": int(time.time()) - started_at,
}
temporary = destination.with_name(destination.name + ".tmp")
if destination.exists() or destination.is_symlink() or temporary.exists() or temporary.is_symlink():
    raise SystemExit("APFS reliability: result destination already exists")
fd = os.open(temporary, os.O_CREAT | os.O_EXCL | os.O_WRONLY | getattr(os, "O_NOFOLLOW", 0), 0o600)
with os.fdopen(fd, "w", encoding="utf-8") as stream:
    json.dump(manifest, stream, sort_keys=True)
    stream.write("\n")
    stream.flush()
    os.fsync(stream.fileno())
os.rename(temporary, destination)
PY
printf '%s\n' 'APFS reliability: sanitized manifest written under ignored local build storage'
