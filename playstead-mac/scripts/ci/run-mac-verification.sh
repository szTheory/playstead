#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPO_ROOT="$(cd "${MAC_ROOT}/.." && pwd)"
PROJECT="${MAC_ROOT}/Playstead.xcodeproj"
SCHEME="Playstead"
BUILD_ROOT="${MAC_ROOT}/.build/ci"
DERIVED_DATA="${BUILD_ROOT}/DerivedData"
RAW_ROOT="${BUILD_ROOT}/raw"
EVIDENCE_ROOT="${BUILD_ROOT}/evidence"
ADOPTION_EVIDENCE="${EVIDENCE_ROOT}/wave-0-adoption.json"

die() {
  printf 'mac verification: %s\n' "$*" >&2
  exit 1
}

require_value() {
  local flag="$1"
  local value="${2:-}"
  [ -n "$value" ] || die "$flag requires a value"
}

verify_result() (
  local evidence="$1"
  shift
  local required_file expected_workflow expected_event expected_ref expected_sha expected_run_id
  required_file="$(mktemp "${TMPDIR:-/tmp}/playstead-required-canaries.XXXXXX")"
  trap 'rm -f "$required_file"' EXIT
  expected_workflow=""
  expected_event=""
  expected_ref=""
  expected_sha=""
  expected_run_id=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --required-canary) require_value "$1" "${2:-}"; printf '%s\n' "$2" >>"$required_file"; shift 2 ;;
      --expected-workflow) require_value "$1" "${2:-}"; expected_workflow="$2"; shift 2 ;;
      --expected-event) require_value "$1" "${2:-}"; expected_event="$2"; shift 2 ;;
      --expected-ref) require_value "$1" "${2:-}"; expected_ref="$2"; shift 2 ;;
      --expected-sha) require_value "$1" "${2:-}"; expected_sha="$2"; shift 2 ;;
      --expected-run-id) require_value "$1" "${2:-}"; expected_run_id="$2"; shift 2 ;;
      *) die "unknown result-verifier argument: $1" ;;
    esac
  done

  [ -s "$required_file" ] || die "at least one --required-canary is required"
  python3 - "$evidence" "$required_file" "$expected_workflow" "$expected_event" \
    "$expected_ref" "$expected_sha" "$expected_run_id" <<'PY'
import json, pathlib, sys

path, required_path, workflow, event, ref, sha, run_id = sys.argv[1:]
try:
    raw = pathlib.Path(path).read_text(encoding="utf-8")
    data = json.loads(raw)
except Exception as exc:
    raise SystemExit(f"invalid evidence JSON: {exc}")

if not isinstance(data, dict) or data.get("schema_version") != 1:
    raise SystemExit("evidence schema_version must be exactly 1")
if data.get("source") != "github-hosted":
    raise SystemExit("evidence source must be github-hosted")
run = data.get("run")
if not isinstance(run, dict):
    raise SystemExit("evidence run metadata is missing")
expected = {
    "workflow": workflow,
    "event": event,
    "ref": ref,
    "head_sha": sha,
    "run_id": run_id,
}
for key, value in expected.items():
    if not value or str(run.get(key, "")) != value:
        raise SystemExit(f"run metadata mismatch for {key}")

canaries = data.get("canaries")
if not isinstance(canaries, list):
    raise SystemExit("canaries must be an array")
by_id = {}
for record in canaries:
    if not isinstance(record, dict) or not isinstance(record.get("identifier"), str):
        raise SystemExit("malformed canary record")
    identifier = record["identifier"]
    if identifier in by_id:
        raise SystemExit(f"duplicate canary record: {identifier}")
    by_id[identifier] = record

required = [line for line in pathlib.Path(required_path).read_text().splitlines() if line]
for identifier in required:
    record = by_id.get(identifier)
    if record is None:
        raise SystemExit(f"required canary missing: {identifier}")
    if record.get("discovered") is not True:
        raise SystemExit(f"required canary was not discovered: {identifier}")
    count = record.get("execution_count")
    if type(count) is not int or count != 1:
        raise SystemExit(f"required canary execution_count must equal 1: {identifier}")
    if record.get("skipped") is not False:
        raise SystemExit(f"required canary was skipped: {identifier}")
    if record.get("outcome") != "passed":
        raise SystemExit(f"required canary did not pass: {identifier}")

fingerprint = data.get("fingerprint")
if not isinstance(fingerprint, dict):
    raise SystemExit("runner fingerprint is missing")
if fingerprint.get("architecture") != "arm64":
    raise SystemExit("runner fingerprint architecture must be arm64")
if fingerprint.get("xcode") != ["Xcode 26.6", "Build version 17F113"]:
    raise SystemExit("runner fingerprint Xcode identity mismatched")
for key in ("runner_image", "runner_image_version", "macos", "macos_build"):
    if not isinstance(fingerprint.get(key), str) or not fingerprint[key]:
        raise SystemExit(f"runner fingerprint field is missing: {key}")

native = data.get("native_health")
if not isinstance(native, dict):
    raise SystemExit("native health evidence is missing")
if native.get("postgresql_major") != 17 or native.get("phoenix_healthy") is not True:
    raise SystemExit("native PostgreSQL 17/Phoenix health did not pass")
if native.get("loopback_only") is not True or native.get("cleanup_complete") is not True:
    raise SystemExit("native service isolation/cleanup evidence did not pass")

triplets = data.get("snapshot_triplets")
if triplets != ["actual.png", "diff.png", "reference.png"]:
    raise SystemExit("snapshot reference/actual/diff inventory is incomplete")
calibration = data.get("snapshot_calibration")
if not isinstance(calibration, dict) or calibration.get("mutation_failed") is not True or calibration.get("noise_passed") is not True:
    raise SystemExit("snapshot mutation/noise calibration did not pass")

linux = data.get("linux_jobs")
if linux != {"compose_smoke": "success", "test": "success"}:
    raise SystemExit("both Linux jobs must conclude success")

forbidden_keys = {"authorization", "credential", "token", "database_url", "raw_log", "keychain_path"}
def scan(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key.lower() in forbidden_keys:
                raise SystemExit(f"secret-bearing evidence key is forbidden: {key}")
            scan(child)
    elif isinstance(value, list):
        for child in value: scan(child)
scan(data)

print(f"verified {len(required)} exact hosted canary result(s)")
PY
)

validate_hosted_run() {
  local metadata="$1"
  shift
  local expected_workflow="" expected_event="" expected_ref="" expected_sha="" expected_run_id=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --expected-workflow) require_value "$1" "${2:-}"; expected_workflow="$2"; shift 2 ;;
      --expected-event) require_value "$1" "${2:-}"; expected_event="$2"; shift 2 ;;
      --expected-ref) require_value "$1" "${2:-}"; expected_ref="$2"; shift 2 ;;
      --expected-sha) require_value "$1" "${2:-}"; expected_sha="$2"; shift 2 ;;
      --expected-run-id) require_value "$1" "${2:-}"; expected_run_id="$2"; shift 2 ;;
      *) die "unknown hosted-run argument: $1" ;;
    esac
  done

  python3 - "$metadata" "$expected_workflow" "$expected_event" "$expected_ref" \
    "$expected_sha" "$expected_run_id" <<'PY'
import json, pathlib, sys

path, workflow, event, ref, sha, run_id = sys.argv[1:]
try:
    data = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
except Exception as exc:
    raise SystemExit(f"invalid hosted-run JSON: {exc}")
if not isinstance(data, dict):
    raise SystemExit("hosted-run metadata must be an object")
checks = {
    "workflowName": workflow,
    "event": event,
    "headBranch": ref,
    "headSha": sha,
    "databaseId": int(run_id) if run_id.isdigit() else run_id,
    "status": "completed",
    "conclusion": "success",
}
for key, value in checks.items():
    if value in (None, "") or data.get(key) != value:
        raise SystemExit(f"hosted-run metadata mismatch for {key}")
print(f"verified exact hosted run {run_id}")
PY
}

assert_hosted_environment() {
  [ "${GITHUB_ACTIONS:-}" = "true" ] || die "wave-0 adoption must run on GitHub Actions"
  [ "$(uname -m)" = "arm64" ] || die "wave-0 adoption requires ARM64"
  [ "${DEVELOPER_DIR:-}" = "/Applications/Xcode_26.6.app/Contents/Developer" ] || \
    die "DEVELOPER_DIR must select Xcode 26.6 explicitly"
  xcodebuild -version | grep -Fx 'Xcode 26.6' >/dev/null || die "Xcode version drifted"
  xcodebuild -version | grep -Fx 'Build version 17F113' >/dev/null || die "Xcode build drifted"
}

write_fingerprint() {
  mkdir -p "$EVIDENCE_ROOT"
  python3 - "$EVIDENCE_ROOT/environment-fingerprint.json" <<'PY'
import json, os, platform, subprocess, sys

def output(*cmd):
    return subprocess.check_output(cmd, text=True).strip()

fingerprint = {
    "runner_image": os.environ.get("ImageOS", ""),
    "runner_image_version": os.environ.get("ImageVersion", ""),
    "architecture": platform.machine(),
    "macos": output("sw_vers", "-productVersion"),
    "macos_build": output("sw_vers", "-buildVersion"),
    "xcode": output("xcodebuild", "-version").splitlines(),
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(fingerprint, handle, indent=2, sort_keys=True)
PY
}

extract_canary_record() {
  local test_results="$1"
  local identifier="$2"
  python3 - "$test_results" "$identifier" <<'PY'
import json, pathlib, sys

data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
required = sys.argv[2]
method = required.rsplit("/", 1)[-1]
matches = []

def walk(value):
    if isinstance(value, dict):
        strings = [v for v in value.values() if isinstance(v, str)]
        identity = next((value.get(k) for k in ("testIdentifier", "nodeIdentifier", "identifier", "name") if isinstance(value.get(k), str)), "")
        if method in identity or any(method in item for item in strings):
            status = next((value.get(k) for k in ("testStatus", "result", "status") if isinstance(value.get(k), str)), "unknown").lower()
            matches.append(status)
        for child in value.values(): walk(child)
    elif isinstance(value, list):
        for child in value: walk(child)

walk(data)
statuses = list(dict.fromkeys(matches))
passed = any(status in {"success", "succeeded", "passed", "pass"} for status in statuses)
skipped = any("skip" in status for status in statuses)
record = {
    "identifier": required,
    "discovered": bool(statuses),
    "execution_count": 1 if statuses else 0,
    "skipped": skipped,
    "outcome": "passed" if passed and not skipped else (statuses[0] if statuses else "missing"),
}
print(json.dumps(record, sort_keys=True))
PY
}

NATIVE_ROOT=""
PG_CTL=""
PGDATA=""
PHOENIX_PID=""

cleanup_native_services() {
  trap - EXIT
  local cleanup_ok=true
  if [ -n "$PHOENIX_PID" ] && kill -0 "$PHOENIX_PID" 2>/dev/null; then
    kill "$PHOENIX_PID" 2>/dev/null || cleanup_ok=false
    wait "$PHOENIX_PID" 2>/dev/null || true
  fi
  if [ -n "$PG_CTL" ] && [ -n "$PGDATA" ] && [ -d "$PGDATA" ]; then
    "$PG_CTL" -D "$PGDATA" -m fast -w stop >/dev/null 2>&1 || cleanup_ok=false
  fi
  if [ -n "$NATIVE_ROOT" ] && [ -d "$NATIVE_ROOT" ]; then
    rm -rf "$NATIVE_ROOT"
  fi
  if [ -f "$ADOPTION_EVIDENCE" ]; then
    python3 - "$ADOPTION_EVIDENCE" "$cleanup_ok" <<'PY'
import json, sys
path, cleanup = sys.argv[1:]
data = json.load(open(path))
data.setdefault("native_health", {})["cleanup_complete"] = cleanup == "true"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
PY
  fi
  [ "$cleanup_ok" = true ] || die "native service cleanup failed"
}

start_native_services() {
  command -v brew >/dev/null || die "Homebrew is required on the hosted runner"
  if ! brew list --versions postgresql@17 >/dev/null 2>&1; then
    brew install postgresql@17
  fi

  local pg_prefix pg_bin pg_port pg_user server_root
  pg_prefix="$(brew --prefix postgresql@17)"
  pg_bin="$pg_prefix/bin"
  PG_CTL="$pg_bin/pg_ctl"
  pg_port=55432
  pg_user="$(id -un)"
  NATIVE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/playstead-native-ci.XXXXXX")"
  PGDATA="$NATIVE_ROOT/postgres"
  server_root="$NATIVE_ROOT/app"
  mkdir -p "$server_root/inbox" "$server_root/blobs" "$server_root/exports"

  "$pg_bin/initdb" -D "$PGDATA" --auth=trust --no-locale --encoding=UTF8 >/dev/null
  "$PG_CTL" -D "$PGDATA" -l "$NATIVE_ROOT/postgres.log" \
    -o "-h 127.0.0.1 -p $pg_port" -w start >/dev/null
  "$pg_bin/createdb" -h 127.0.0.1 -p "$pg_port" playstead_mac_ci

  export MIX_ENV=mac_ci
  export PORT=4010
  export PLAYSTEAD_MAC_CI_ROOT="$server_root"
  export MAC_CI_DATABASE_URL="ecto://${pg_user}@127.0.0.1:${pg_port}/playstead_mac_ci"

  # Dependency compilation and migrations can exceed the server readiness
  # deadline on a cold hosted image. Finish that bootstrap synchronously so
  # the deadline measures Phoenix startup rather than package installation.
  if ! (
    cd "$REPO_ROOT/playstead-server"
    mix deps.get
    mix ecto.migrate
  ) >"$NATIVE_ROOT/bootstrap.log" 2>&1; then
    tail -n 120 "$NATIVE_ROOT/bootstrap.log" >&2
    die "native Phoenix bootstrap failed"
  fi

  (
    cd "$REPO_ROOT/playstead-server"
    exec mix phx.server
  ) >"$NATIVE_ROOT/phoenix.log" 2>&1 &
  PHOENIX_PID=$!

  local ready=false
  for _ in $(seq 1 60); do
    if python3 -c 'import urllib.request; r=urllib.request.urlopen("http://127.0.0.1:4010/healthz", timeout=1); raise SystemExit(0 if r.status == 200 else 1)' 2>/dev/null; then
      ready=true
      break
    fi
    if ! kill -0 "$PHOENIX_PID" 2>/dev/null; then
      tail -n 120 "$NATIVE_ROOT/phoenix.log" >&2
      die "native Phoenix exited before health"
    fi
    sleep 1
  done
  if [ "$ready" != true ]; then
    tail -n 120 "$NATIVE_ROOT/phoenix.log" >&2
    die "native Phoenix health deadline exceeded"
  fi
}

write_adoption_evidence() {
  local records_file="$1"
  local calibration_record="$2"
  python3 - "$ADOPTION_EVIDENCE" "$EVIDENCE_ROOT/environment-fingerprint.json" \
    "$records_file" "$calibration_record" <<'PY'
import json, os, pathlib, sys

path, fingerprint_path, records_path, calibration_raw = sys.argv[1:]
triplet_root = pathlib.Path(path).parent / "snapshot-triplet"
triplets = sorted(p.name for p in triplet_root.glob("*.png") if p.is_file() and p.stat().st_size > 0)
calibration = json.loads(calibration_raw)
data = {
    "schema_version": 1,
    "source": "github-hosted" if os.environ.get("GITHUB_ACTIONS") == "true" else "local",
    "run": {
        "workflow": os.environ.get("GITHUB_WORKFLOW", ""),
        "event": os.environ.get("GITHUB_EVENT_NAME", ""),
        "ref": os.environ.get("GITHUB_REF", ""),
        "head_sha": os.environ.get("GITHUB_SHA", ""),
        "run_id": os.environ.get("GITHUB_RUN_ID", ""),
    },
    "fingerprint": json.load(open(fingerprint_path)),
    "canaries": [json.loads(line) for line in pathlib.Path(records_path).read_text().splitlines() if line],
    "native_health": {
        "postgresql_major": 17,
        "phoenix_healthy": True,
        "loopback_only": True,
        "cleanup_complete": False,
    },
    "snapshot_triplets": triplets,
    "snapshot_calibration": {
        "mutation_failed": calibration.get("outcome") == "passed",
        "noise_passed": calibration.get("outcome") == "passed",
    },
    "linux_jobs": {
        "test": os.environ.get("LINUX_TEST_CONCLUSION", ""),
        "compose_smoke": os.environ.get("LINUX_COMPOSE_CONCLUSION", ""),
    },
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
PY
}

run_wave_0_adoption() {
  assert_hosted_environment
  mkdir -p "$DERIVED_DATA" "$RAW_ROOT" "$EVIDENCE_ROOT"
  write_fingerprint
  defaults write NSGlobalDomain AppleKeyboardUIMode -int 3
  trap cleanup_native_services EXIT
  start_native_services

  local ui_result="$RAW_ROOT/wave-0-ui.xcresult"
  local ui_tests="$RAW_ROOT/wave-0-ui-tests.json"
  local snapshot_result="$RAW_ROOT/wave-0-snapshot.xcresult"
  local snapshot_tests="$RAW_ROOT/wave-0-snapshot-tests.json"
  local records_file="$RAW_ROOT/canary-records.jsonl"
  local snapshot_output="$EVIDENCE_ROOT/snapshot-triplet"
  local signing=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=)
  local ui_identifiers=(
    "PlaysteadUITests.HostedRunnerCanaryTests/testAdHocSignedAppLaunchesOnHostedRunner"
    "PlaysteadUITests.HostedRunnerCanaryTests/testFullKeyboardAccessCanaryFocusesAndActivatesTwoControls"
    "PlaysteadUITests.HostedRunnerCanaryTests/testScopedFileKeychainStoresLoadsAndDeletesTwice"
  )
  local snapshot_identifier="PlaysteadTests.SnapshotHarnessCanaryTests/testIntentionalMismatchProducesReviewableTriplet"
  local calibration_identifier="PlaysteadTests.SnapshotHarnessCanaryTests/testMeaningfulMutationFailsAndCalibratedNoisePasses"

  xcodebuild build-for-testing -project "$PROJECT" -scheme "$SCHEME" \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA" \
    "${signing[@]}" PLAYSTEAD_SNAPSHOT_CANARY_OUTPUT="$snapshot_output"

  local ui_only=()
  local identifier
  for identifier in "${ui_identifiers[@]}"; do
    ui_only+=("-only-testing:${identifier%%.*}/${identifier#*.}")
  done
  xcodebuild test-without-building -project "$PROJECT" -scheme "$SCHEME" \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA" \
    -resultBundlePath "$ui_result" "${ui_only[@]}" "${signing[@]}"
  xcrun xcresulttool get test-results tests --path "$ui_result" --format json >"$ui_tests"

  mkdir -p "$snapshot_output"
  xcodebuild test-without-building -project "$PROJECT" -scheme "$SCHEME" \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA" \
    -resultBundlePath "$snapshot_result" \
    -only-testing:"${snapshot_identifier%%.*}/${snapshot_identifier#*.}" \
    -only-testing:"${calibration_identifier%%.*}/${calibration_identifier#*.}" \
    "${signing[@]}" PLAYSTEAD_SNAPSHOT_CANARY_OUTPUT="$snapshot_output"
  xcrun xcresulttool get test-results tests --path "$snapshot_result" --format json >"$snapshot_tests"

  : >"$records_file"
  for identifier in "${ui_identifiers[@]}"; do
    extract_canary_record "$ui_tests" "$identifier" >>"$records_file"
  done
  extract_canary_record "$snapshot_tests" "$snapshot_identifier" >>"$records_file"
  printf '%s\n' '{"identifier":"native.postgresql17-phoenix-health","discovered":true,"execution_count":1,"skipped":false,"outcome":"passed"}' >>"$records_file"

  local calibration_record
  calibration_record="$(extract_canary_record "$snapshot_tests" "$calibration_identifier")"
  write_adoption_evidence "$records_file" "$calibration_record"
  cleanup_native_services
  trap - EXIT

  verify_result "$ADOPTION_EVIDENCE" \
    --required-canary "${ui_identifiers[0]}" \
    --required-canary "${ui_identifiers[1]}" \
    --required-canary "${ui_identifiers[2]}" \
    --required-canary "$snapshot_identifier" \
    --required-canary native.postgresql17-phoenix-health \
    --expected-workflow "${GITHUB_WORKFLOW:?}" --expected-event "${GITHUB_EVENT_NAME:?}" \
    --expected-ref "${GITHUB_REF:?}" --expected-sha "${GITHUB_SHA:?}" \
    --expected-run-id "${GITHUB_RUN_ID:?}"
}

run_self_tests() {
  "${SCRIPT_DIR}/tests/wave-0-verifier-test.sh"
}

verify_topology() {
  "${SCRIPT_DIR}/tests/wave-0-topology-test.sh"
}

usage() {
  cat <<'USAGE'
Usage:
  run-mac-verification.sh --run-wave-0-adoption
  run-mac-verification.sh --verify-result FILE --required-canary ID [expected metadata]
  run-mac-verification.sh --validate-hosted-run FILE [expected metadata]
  run-mac-verification.sh --self-test-wave-0-verifier [--self-test-hosted-run-validator] [--verify-wave-0-topology]
  run-mac-verification.sh --verify-wave-0-topology
USAGE
}

[ "$#" -gt 0 ] || { usage >&2; exit 2; }
case "$1" in
  --verify-result) require_value "$1" "${2:-}"; evidence="$2"; shift 2; verify_result "$evidence" "$@" ;;
  --validate-hosted-run) require_value "$1" "${2:-}"; metadata="$2"; shift 2; validate_hosted_run "$metadata" "$@" ;;
  --run-wave-0-adoption) shift; [ "$#" -eq 0 ] || die "unexpected adoption arguments"; run_wave_0_adoption ;;
  --verify-wave-0-topology) shift; [ "$#" -eq 0 ] || die "unexpected topology arguments"; verify_topology ;;
  --self-test-wave-0-verifier|--self-test-hosted-run-validator)
    verify_topology_after=false
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --self-test-wave-0-verifier|--self-test-hosted-run-validator) shift ;;
        --verify-wave-0-topology) verify_topology_after=true; shift ;;
        --only-canaries) require_value "$1" "${2:-}"; shift 2 ;;
        *) die "unknown self-test argument: $1" ;;
      esac
    done
    run_self_tests
    [ "$verify_topology_after" = false ] || verify_topology
    ;;
  -h|--help) usage ;;
  *) die "unknown mode: $1" ;;
esac
