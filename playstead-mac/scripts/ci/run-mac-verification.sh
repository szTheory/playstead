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

verify_result() {
  local evidence="$1"
  shift
  local required_file expected_workflow expected_event expected_ref expected_sha expected_run_id
  required_file="$(mktemp "${TMPDIR:-/tmp}/playstead-required-canaries.XXXXXX")"
  trap 'rm -f "$required_file"' RETURN
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

print(f"verified {len(required)} exact hosted canary result(s)")
PY
}

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

run_wave_0_adoption() {
  assert_hosted_environment
  write_fingerprint
  mkdir -p "$DERIVED_DATA" "$RAW_ROOT" "$EVIDENCE_ROOT"
  defaults write NSGlobalDomain AppleKeyboardUIMode -int 3

  local result_bundle="$RAW_ROOT/wave-0-launch.xcresult"
  local test_results="$RAW_ROOT/wave-0-launch-tests.json"
  local identifier="PlaysteadUITests.HostedRunnerCanaryTests/testAdHocSignedAppLaunchesOnHostedRunner"
  local signing=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=)

  xcodebuild build-for-testing -project "$PROJECT" -scheme "$SCHEME" \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA" "${signing[@]}"
  xcodebuild test-without-building -project "$PROJECT" -scheme "$SCHEME" \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA" \
    -resultBundlePath "$result_bundle" -only-testing:"$identifier" "${signing[@]}"
  xcrun xcresulttool get test-results tests --path "$result_bundle" --format json >"$test_results"

  local record
  record="$(extract_canary_record "$test_results" "$identifier")"
  python3 - "$ADOPTION_EVIDENCE" "$record" <<'PY'
import json, os, sys

path, record = sys.argv[1:]
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
    "canaries": [json.loads(record)],
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
PY
  verify_result "$ADOPTION_EVIDENCE" --required-canary "$identifier" \
    --expected-workflow "${GITHUB_WORKFLOW:?}" --expected-event "${GITHUB_EVENT_NAME:?}" \
    --expected-ref "${GITHUB_REF:?}" --expected-sha "${GITHUB_SHA:?}" \
    --expected-run-id "${GITHUB_RUN_ID:?}"
}

run_self_tests() {
  "${SCRIPT_DIR}/tests/wave-0-verifier-test.sh"
}

usage() {
  cat <<'USAGE'
Usage:
  run-mac-verification.sh --run-wave-0-adoption
  run-mac-verification.sh --verify-result FILE --required-canary ID [expected metadata]
  run-mac-verification.sh --validate-hosted-run FILE [expected metadata]
  run-mac-verification.sh --self-test-wave-0-verifier [--self-test-hosted-run-validator]
USAGE
}

[ "$#" -gt 0 ] || { usage >&2; exit 2; }
case "$1" in
  --verify-result) require_value "$1" "${2:-}"; evidence="$2"; shift 2; verify_result "$evidence" "$@" ;;
  --validate-hosted-run) require_value "$1" "${2:-}"; metadata="$2"; shift 2; validate_hosted_run "$metadata" "$@" ;;
  --run-wave-0-adoption) shift; [ "$#" -eq 0 ] || die "unexpected adoption arguments"; run_wave_0_adoption ;;
  --self-test-wave-0-verifier|--self-test-hosted-run-validator)
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --self-test-wave-0-verifier|--self-test-hosted-run-validator) shift ;;
        --only-canaries) require_value "$1" "${2:-}"; shift 2 ;;
        *) die "unknown self-test argument: $1" ;;
      esac
    done
    run_self_tests
    ;;
  -h|--help) usage ;;
  *) die "unknown mode: $1" ;;
esac
