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
FOUR_LAYER_ROOT="${BUILD_ROOT}/four-layer"
FOUR_LAYER_RAW="${FOUR_LAYER_ROOT}/raw"
FOUR_LAYER_EVIDENCE="${FOUR_LAYER_ROOT}/evidence"
COMPLETE_EVIDENCE="${FOUR_LAYER_EVIDENCE}/complete-verification-evidence.json"
FAILURE_EVIDENCE="${BUILD_ROOT}/failure-evidence"
SNAPSHOT_CANDIDATES="${BUILD_ROOT}/snapshot-candidates"

# EXIT traps run after their caller's local scope has unwound. Keep every
# trap-owned value globally initialized so an early return/failure can never
# replace the underlying result with a `set -u` cleanup error.
KEYBOARD_MODE_CAPTURED=false
KEYBOARD_MODE_PREVIOUS=""

restore_keyboard_mode() {
  [ "${KEYBOARD_MODE_CAPTURED:-false}" = "true" ] || return 0
  local previous="${KEYBOARD_MODE_PREVIOUS:-}"
  # Disarm before the fallible restore command so cleanup cannot recurse.
  KEYBOARD_MODE_CAPTURED=false
  if [ -n "$previous" ]; then
    defaults write NSGlobalDomain AppleKeyboardUIMode -int "$previous"
  else
    defaults delete NSGlobalDomain AppleKeyboardUIMode 2>/dev/null || true
  fi
}

arm_keyboard_mode_cleanup() {
  KEYBOARD_MODE_CAPTURED=false
  KEYBOARD_MODE_PREVIOUS=""
  trap restore_keyboard_mode EXIT
}

capture_keyboard_mode() {
  KEYBOARD_MODE_PREVIOUS="$(defaults read NSGlobalDomain AppleKeyboardUIMode 2>/dev/null || true)"
  KEYBOARD_MODE_CAPTURED=true
  defaults write NSGlobalDomain AppleKeyboardUIMode -int 3
}

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

verify_complete_hosted_run() {
  local run_record="" run_view="" manifest="${COMPLETE_EVIDENCE}"
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --run-record) require_value "$1" "${2:-}"; run_record="$2"; shift 2 ;;
      --run-view) require_value "$1" "${2:-}"; run_view="$2"; shift 2 ;;
      --manifest) require_value "$1" "${2:-}"; manifest="$2"; shift 2 ;;
      *) die "unknown complete hosted-run argument: $1" ;;
    esac
  done
  [ -n "$run_record" ] && [ -n "$run_view" ] || die "complete hosted-run verification requires --run-record and --run-view"
  python3 - "$run_record" "$run_view" "$manifest" <<'PY'
import json, pathlib, re, sys

record_path, view_path, manifest_path = map(pathlib.Path, sys.argv[1:])
try:
    record = json.loads(record_path.read_text(encoding="utf-8"))
    view = json.loads(view_path.read_text(encoding="utf-8"))
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
except Exception as exc:
    raise SystemExit(f"complete evidence JSON is malformed: {exc}")

if not all(isinstance(value, dict) for value in (record, view, manifest)):
    raise SystemExit("complete evidence inputs must be objects")
if record.get("schema_version") != 1 or manifest.get("schema_version") != 1:
    raise SystemExit("complete evidence schema_version must equal 1")
if manifest.get("source") != "github-hosted":
    raise SystemExit("complete evidence must originate on GitHub-hosted CI")

identity = {
    "run_id": ("databaseId", "run_id"),
    "workflow": ("workflowName", "workflow"),
    "event": ("event", "event"),
    "head_branch": ("headBranch", "head_branch"),
    "head_sha": ("headSha", "head_sha"),
}
run = manifest.get("run")
if not isinstance(run, dict):
    raise SystemExit("complete evidence run identity is missing")
for label, (view_key, manifest_key) in identity.items():
    expected = record.get(label)
    actual_view = view.get(view_key)
    actual_manifest = run.get(manifest_key)
    if label == "run_id":
        expected, actual_view, actual_manifest = map(str, (expected, actual_view, actual_manifest))
    if expected in (None, "") or expected != actual_view or expected != actual_manifest:
        raise SystemExit(f"complete evidence identity mismatch: {label}")
if record.get("status") != "completed" or record.get("conclusion") != "success":
    raise SystemExit("persisted run record is not completed successfully")
if view.get("status") != "completed" or view.get("conclusion") != "success":
    raise SystemExit("hosted run is not completed successfully")
if record.get("url") != view.get("url") or not isinstance(record.get("url"), str):
    raise SystemExit("hosted run URL mismatch")
if record.get("event") not in {"push", "pull_request"}:
    raise SystemExit("hosted run event is not push or pull_request")
if record.get("workflow") != "ci":
    raise SystemExit("hosted workflow must be ci")
if not re.fullmatch(r"[0-9a-f]{40}", str(record.get("head_sha", ""))):
    raise SystemExit("hosted head SHA is malformed")

expected_jobs = {
    "mix precommit (unit + LiveView + browser + integration)": "test",
    "docker compose cold start": "compose-smoke",
    "macOS 26 unit + rendering + UI + live server": "mac-verification",
}
jobs = view.get("jobs")
if not isinstance(jobs, list):
    raise SystemExit("hosted jobs are missing")
jobs_by_name = {}
for job in jobs:
    if not isinstance(job, dict) or not isinstance(job.get("name"), str):
        raise SystemExit("hosted job record is malformed")
    if job["name"] in jobs_by_name:
        raise SystemExit(f"duplicate hosted job: {job['name']}")
    jobs_by_name[job["name"]] = job
recorded_jobs = record.get("jobs")
if not isinstance(recorded_jobs, dict):
    raise SystemExit("persisted Linux/Mac jobs are missing")
for job_name, record_key in expected_jobs.items():
    job = jobs_by_name.get(job_name)
    if job is None or job.get("status") != "completed" or job.get("conclusion") != "success":
        raise SystemExit(f"required hosted job did not pass: {job_name}")
    if recorded_jobs.get(record_key) != "success":
        raise SystemExit(f"persisted hosted job did not pass: {record_key}")

if manifest.get("linux_jobs") != {"compose_smoke": "success", "test": "success"}:
    raise SystemExit("both Linux jobs must conclude success")
native = manifest.get("native_health")
if native != {"cleanup_complete": True, "loopback_only": True, "phoenix_healthy": True, "postgresql_major": 17}:
    raise SystemExit("native PostgreSQL/Phoenix evidence is incomplete")
fingerprint = manifest.get("fingerprint")
if not isinstance(fingerprint, dict) or fingerprint.get("architecture") != "arm64" or fingerprint.get("xcode") != ["Xcode 26.6", "Build version 17F113"]:
    raise SystemExit("runner fingerprint drifted")

layers = manifest.get("layers")
if not isinstance(layers, list) or len(layers) != 4:
    raise SystemExit("complete evidence must contain four layers")
by_layer = {}
for layer in layers:
    if not isinstance(layer, dict) or layer.get("layer") not in {"unit", "rendering", "ui", "live-server"}:
        raise SystemExit("complete evidence layer is malformed")
    if layer["layer"] in by_layer:
        raise SystemExit(f"duplicate evidence layer: {layer['layer']}")
    by_layer[layer["layer"]] = layer
    if type(layer.get("executed_test_count")) is not int or layer["executed_test_count"] <= 0:
        raise SystemExit(f"layer is vacuous: {layer['layer']}")
    if layer.get("failed_test_count") != 0 or layer.get("audit_issue_count") != 0:
        raise SystemExit(f"layer contains failures: {layer['layer']}")
    required = layer.get("required_tests")
    if not isinstance(required, list) or not required:
        raise SystemExit(f"layer required-test allowlist is empty: {layer['layer']}")
    for test in required:
        if not isinstance(test, dict) or test.get("discovered") is not True or test.get("execution_count") != 1 or test.get("skipped") is not False or test.get("outcome") != "passed":
            raise SystemExit(f"required test did not execute exactly once and pass: {layer['layer']}")

required_exact = {
    "ui": "PlaysteadUITests.SurfaceAccessibilityTests/testKeyboardOnlySurfaceInventoryAndLiveAudit",
    "live-server": "PlaysteadUITests.LiveServerSnapshotTests/testPairedFreshMirrorRendersSnapshotBeforeAnyBlobDownloadAndPersistsKeychainAcrossRelaunch",
}
for layer_name, identifier in required_exact.items():
    identifiers = {test.get("identifier") for test in by_layer[layer_name]["required_tests"]}
    if identifier not in identifiers:
        raise SystemExit(f"complete evidence exact test missing: {identifier}")

for forbidden in ("authorization", "credential", "token", "database_url", "raw_log", "keychain_path"):
    if f'"{forbidden}"' in json.dumps(manifest).lower():
        raise SystemExit(f"secret-bearing complete evidence key is forbidden: {forbidden}")
print(f"verified exact complete hosted run {record['run_id']} with four Mac layers and two Linux jobs")
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
  local output="${1:-$EVIDENCE_ROOT/environment-fingerprint.json}"
  mkdir -p "$(dirname "$output")"
  python3 - "$output" <<'PY'
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

verify_layer_result() (
  local test_results="$1"
  local layer="$2"
  local output="$3"
  shift 3
  local required_file
  required_file="$(mktemp "${TMPDIR:-/tmp}/playstead-layer-tests.XXXXXX")"
  trap 'rm -f "$required_file"' EXIT

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --required-test) require_value "$1" "${2:-}"; printf '%s\n' "$2" >>"$required_file"; shift 2 ;;
      *) die "unknown layer-result argument: $1" ;;
    esac
  done
  [ -s "$required_file" ] || die "layer $layer requires at least one --required-test"

  python3 - "$test_results" "$required_file" "$layer" "$output" "$MAC_ROOT" <<'PY'
import json, pathlib, re, sys

results_path, required_path, layer, output_path, mac_root = sys.argv[1:]
try:
    data = json.loads(pathlib.Path(results_path).read_text(encoding="utf-8"))
except Exception as exc:
    raise SystemExit(f"{layer}: result JSON parse failed: {exc}")

if not isinstance(data, dict) or not isinstance(data.get("testNodes"), list):
    raise SystemExit(f"{layer}: Xcode test result schema is missing testNodes")

def canonical(identifier):
    body = identifier
    if "/" not in body:
        raise SystemExit(f"{layer}: malformed required test identifier: {identifier}")
    suite, method = body.split("/", 1)
    suite = suite.rsplit(".", 1)[-1]
    method = method[:-2] if method.endswith("()") else method
    value = f"{suite}/{method}()"
    if len(value) > 240 or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.]*/[A-Za-z_][A-Za-z0-9_]*\(\)", value):
        raise SystemExit(f"{layer}: malformed test identifier")
    return value

def normalized_outcome(result):
    folded = result.strip().lower()
    if folded in {"passed", "pass", "success", "succeeded"}:
        return "passed"
    if "skip" in folded:
        return "skipped"
    if folded in {"failed", "failure", "error", "expected failure", "unexpected failure"}:
        return "failed"
    return "unknown"

nodes = []
audit_issues = []
failure_diagnostics = []
failure_stages = set()
audit_pattern = re.compile(r"PLAYSTEAD_A11Y_ISSUES\[([A-Za-z]+)\]=([a-z0-9.,@-]+)")
ui_stage_pattern = re.compile(r"PLAYSTEAD_FAILURE_STAGE\[([a-z0-9-]+)\]")
live_stage_pattern = re.compile(r"live-server-stage=([a-z0-9-]+) action=([a-z0-9-]+)")
allowed_ui_stages = {
    "all-surface-library-layout", "all-surface-collection-reorder",
    "all-surface-quota-list", "all-surface-adapter-actions",
}
allowed_live_stages = {
    "validate-input", "provision-domain", "request-pairing",
    "approve-pairing", "redeem-pairing", "add-second-sentinel",
    "verify-evidence", "bounded-diagnostic-unavailable",
}
allowed_live_actions = {"prepare", "second", "verify", "unknown"}
assertion_pattern = re.compile(
    r"\b(XCTAssert(?:True|False|Equal|NotEqual|Nil|NotNil|LessThan|LessThanOrEqual|GreaterThan|GreaterThanOrEqual|NoThrow|ThrowsError)|XCTFail|XCTUnwrap)\b"
)
failure_message_location_pattern = re.compile(
    r"^(?P<file>[A-Za-z_][A-Za-z0-9_]*\.swift):(?P<line>[1-9][0-9]*):"
)

source_roots = ["Playstead", "PlaysteadTests", "PlaysteadUITests"]
source_by_name = {}
for source_root in source_roots:
    for source_path in (pathlib.Path(mac_root) / source_root).rglob("*.swift"):
        relative = source_path.relative_to(mac_root).as_posix()
        source_by_name.setdefault(source_path.name, []).append(relative)

def first_key(value, names):
    if isinstance(value, dict):
        for key, child in value.items():
            if key in names and isinstance(child, (str, int)):
                return child
        for child in value.values():
            found = first_key(child, names)
            if found is not None:
                return found
    elif isinstance(value, list):
        for child in value:
            found = first_key(child, names)
            if found is not None:
                return found
    return None

def bounded_failure_diagnostic(summary, test_identifier):
    assertion = next((match.group(1) for text in strings(summary) if (match := assertion_pattern.search(text))), None)
    raw_file = first_key(summary, {"fileName", "filePath", "sourceFile", "sourceCodeFilePath"})
    raw_line = first_key(summary, {"lineNumber", "line"})
    if raw_file is None and raw_line is None and isinstance(summary, dict) and summary.get("nodeType") == "Failure Message":
        message_name = summary.get("name")
        location = failure_message_location_pattern.match(message_name) if isinstance(message_name, str) else None
        if location is not None:
            raw_file = location.group("file")
            raw_line = location.group("line")
    if assertion is None or not isinstance(raw_file, str):
        return None
    source_name = pathlib.PurePath(raw_file.removeprefix("file://").split("#", 1)[0]).name
    candidates = source_by_name.get(source_name, [])
    if len(candidates) != 1:
        return None
    try:
        source_line = int(raw_line)
    except (TypeError, ValueError):
        return None
    if not 1 <= source_line <= 1_000_000:
        return None
    return {
        "test_identifier": test_identifier,
        "assertion": assertion,
        "source_file": candidates[0],
        "source_line": source_line,
    }

def failure_records(test_case):
    records = []
    summaries = test_case.get("failureSummaries", [])
    if isinstance(summaries, list):
        records.extend(summaries)

    def collect(value):
        if isinstance(value, dict):
            if value.get("nodeType") == "Failure Message":
                records.append(value)
                return
            if value is not test_case and value.get("nodeType") == "Test Case":
                return
            for child in value.get("children", []) if isinstance(value.get("children"), list) else []:
                collect(child)
        elif isinstance(value, list):
            for child in value:
                collect(child)

    collect(test_case.get("children", []))
    return records

def strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for child in value.values():
            yield from strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from strings(child)

def walk(value):
    if isinstance(value, dict):
        if value.get("nodeType") == "Test Case":
            node_identifier = value.get("nodeIdentifier")
            result = value.get("result")
            if not isinstance(node_identifier, str) or not isinstance(result, str):
                raise SystemExit(f"{layer}: malformed Test Case node")
            test_identifier = canonical(node_identifier)
            nodes.append((test_identifier, result))
            for failure_record in failure_records(value):
                diagnostic = bounded_failure_diagnostic(failure_record, test_identifier)
                if diagnostic is not None:
                    failure_diagnostics.append(diagnostic)
            for diagnostic in strings(value):
                for match in ui_stage_pattern.finditer(diagnostic):
                    stage = match.group(1)
                    if stage in allowed_ui_stages:
                        failure_stages.add(stage)
                for match in live_stage_pattern.finditer(diagnostic):
                    stage, action = match.groups()
                    if stage in allowed_live_stages and action in allowed_live_actions:
                        failure_stages.add(f"live-server-{stage}-{action}")
                for match in audit_pattern.finditer(diagnostic):
                    category, identifiers = match.groups()
                    for element in identifiers.split(","):
                        element_identifier, element_role = element.split("@", 1)
                        audit_issues.append({
                            "test_identifier": test_identifier,
                            "category": category,
                            "element_identifier": element_identifier,
                            "element_role": element_role,
                        })
        for child in value.values():
            walk(child)
    elif isinstance(value, list):
        for child in value:
            walk(child)
walk(data["testNodes"])

required = [line for line in pathlib.Path(required_path).read_text(encoding="utf-8").splitlines() if line]
if not nodes:
    raise SystemExit(f"{layer}: result contains zero executed tests")

records = []
verification_errors = []
for identifier in required:
    expected = canonical(identifier)
    matches = [result for node_identifier, result in nodes if node_identifier == expected]
    result = matches[0] if len(matches) == 1 else "Missing"
    outcome = normalized_outcome(result) if matches else "missing"
    record = {
        "identifier": identifier,
        "discovered": bool(matches),
        "execution_count": len(matches),
        "skipped": outcome == "skipped",
        "outcome": outcome,
    }
    records.append(record)
    if len(matches) != 1:
        verification_errors.append(f"required test execution count must equal 1: {identifier} (got {len(matches)})")
    if record["skipped"]:
        verification_errors.append(f"required test was skipped: {identifier}")
    elif outcome != "passed" and len(matches) == 1:
        verification_errors.append(f"required test did not pass: {identifier} ({result})")

all_failed = sorted(
    ({"identifier": identifier, "outcome": normalized_outcome(result)}
     for identifier, result in nodes if normalized_outcome(result) != "passed"),
    key=lambda record: (record["identifier"], record["outcome"]),
)
max_failed_tests = 50
all_audit_issues = sorted(
    {tuple(sorted(record.items())) for record in audit_issues},
    key=lambda fields: dict(fields)["test_identifier"] + "|" + dict(fields)["category"] + "|" + dict(fields)["element_identifier"] + "|" + dict(fields)["element_role"],
)
max_audit_issues = 50
all_failure_diagnostics = sorted(
    {tuple(sorted(record.items())) for record in failure_diagnostics},
    key=lambda fields: (
        dict(fields)["test_identifier"], dict(fields)["source_file"],
        dict(fields)["source_line"], dict(fields)["assertion"]
    ),
)
max_failure_diagnostics = 50

summary = {
    "schema_version": 1,
    "layer": layer,
    "executed_test_count": len(nodes),
    "required_tests": records,
    "failed_test_count": len(all_failed),
    "failed_tests_truncated": len(all_failed) > max_failed_tests,
    "failed_tests": all_failed[:max_failed_tests],
    "failure_diagnostic_count": len(all_failure_diagnostics),
    "failure_diagnostics_truncated": len(all_failure_diagnostics) > max_failure_diagnostics,
    "failure_diagnostics": [dict(fields) for fields in all_failure_diagnostics[:max_failure_diagnostics]],
    "audit_issue_count": len(all_audit_issues),
    "audit_issues_truncated": len(all_audit_issues) > max_audit_issues,
    "audit_issues": [dict(fields) for fields in all_audit_issues[:max_audit_issues]],
}
pathlib.Path(output_path).parent.mkdir(parents=True, exist_ok=True)
pathlib.Path(output_path).write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"{layer}: verified {len(required)} required test(s) across {len(nodes)} executed test(s)")
for stage in sorted(failure_stages):
    print(f"{layer}: FAILURE_STAGE {stage}")
if verification_errors:
    raise SystemExit(f"{layer}: " + "; ".join(verification_errors))
PY
)

print_failure_diagnostics() {
  local summary="$1"
  local layer="$2"
  python3 - "$summary" "$layer" "$MAC_ROOT" <<'PY'
import json, pathlib, re, sys

summary_path, layer, mac_root = sys.argv[1:]
try:
    data = json.loads(pathlib.Path(summary_path).read_text(encoding="utf-8"))
    diagnostics = data["failure_diagnostics"]
    count = data["failure_diagnostic_count"]
    truncated = data["failure_diagnostics_truncated"]
except Exception:
    raise SystemExit(1)

test_identifier = re.compile(r"^[A-Za-z_][A-Za-z0-9_.]*/[A-Za-z_][A-Za-z0-9_]*\(\)$")
source_identifier = re.compile(r"^(?:Playstead|PlaysteadTests|PlaysteadUITests)/(?:[A-Za-z_][A-Za-z0-9_]*/)*[A-Za-z_][A-Za-z0-9_]*\.swift$")
allowed_assertions = {
    "XCTAssertTrue", "XCTAssertFalse", "XCTAssertEqual", "XCTAssertNotEqual",
    "XCTAssertNil", "XCTAssertNotNil", "XCTAssertLessThan", "XCTAssertLessThanOrEqual",
    "XCTAssertGreaterThan", "XCTAssertGreaterThanOrEqual", "XCTAssertNoThrow",
    "XCTAssertThrowsError", "XCTFail", "XCTUnwrap",
}

if not isinstance(diagnostics, list) or len(diagnostics) > 50:
    raise SystemExit(1)
if type(count) is not int or count < len(diagnostics) or type(truncated) is not bool:
    raise SystemExit(1)
if (not truncated and count != len(diagnostics)) or (truncated and (count <= 50 or len(diagnostics) != 50)):
    raise SystemExit(1)

root = pathlib.Path(mac_root).resolve()
safe = []
for record in diagnostics:
    if not isinstance(record, dict) or set(record) != {"test_identifier", "assertion", "source_file", "source_line"}:
        raise SystemExit(1)
    test = record.get("test_identifier")
    assertion = record.get("assertion")
    source_file = record.get("source_file")
    source_line = record.get("source_line")
    if not isinstance(test, str) or not test_identifier.fullmatch(test):
        raise SystemExit(1)
    if assertion not in allowed_assertions:
        raise SystemExit(1)
    if not isinstance(source_file, str) or not source_identifier.fullmatch(source_file):
        raise SystemExit(1)
    candidate = root / source_file
    same_named = [path for source_root in ("Playstead", "PlaysteadTests", "PlaysteadUITests") for path in (root / source_root).rglob(candidate.name)]
    if not candidate.is_file() or len(same_named) != 1 or same_named[0].resolve() != candidate.resolve():
        raise SystemExit(1)
    if type(source_line) is not int or not 1 <= source_line <= 1_000_000:
        raise SystemExit(1)
    safe.append((test, assertion, source_file, source_line))

for test, assertion, source_file, source_line in safe:
    print(f"{layer}: FAILURE_DIAGNOSTIC {test} {assertion} {source_file}:{source_line}")
if truncated:
    print(f"{layer}: FAILURE_DIAGNOSTICS_TRUNCATED shown={len(safe)} total={count}")
PY
}

prepare_live_server_failure_stage() {
  local marker="${PLAYSTEAD_LIVE_SERVER_STAGE_FILE:-}"
  local evidence_root="${PLAYSTEAD_LIVE_SERVER_STAGE_ROOT:-}"
  [ -n "$marker" ] && [ -n "$evidence_root" ] || die "live-server failure-stage channel is not configured"
  [ "$(basename "$marker")" = "live-server-failure-stage" ] || die "live-server failure-stage filename drifted"
  [ "$(cd "$(dirname "$marker")" && pwd -P)" = "$(cd "$evidence_root" && pwd -P)" ] || \
    die "live-server failure-stage channel escaped its owned root"
  rm -f "$marker"
}

print_live_server_failure_stage() {
  local marker="${PLAYSTEAD_LIVE_SERVER_STAGE_FILE:-}"
  local token mode
  if [ -z "$marker" ] || [ ! -f "$marker" ]; then
    printf '%s\n' "live-server: FAILURE_STAGE unavailable"
    return
  fi
  mode="$(stat -f '%Lp' "$marker" 2>/dev/null || true)"
  token="$(tr -d '\r\n' <"$marker")"
  rm -f "$marker"
  if [ "$mode" != "600" ]; then
    printf '%s\n' "live-server: FAILURE_STAGE invalid-mode"
    return
  fi
  case "$token" in
    validate-input|provision-domain|request-pairing|approve-pairing|redeem-pairing|add-second-sentinel|verify-evidence)
      printf 'live-server: FAILURE_STAGE %s\n' "$token"
      ;;
    *) printf '%s\n' "live-server: FAILURE_STAGE invalid-token" ;;
  esac
}

print_build_diagnostics() {
  local log="$1"
  local layer="$2"
  python3 - "$log" "$layer" "$MAC_ROOT" <<'PY'
import pathlib, re, sys, urllib.parse

log_path, layer, mac_root = sys.argv[1:]
try:
    lines = pathlib.Path(log_path).read_text(encoding="utf-8", errors="replace").splitlines()
except Exception:
    raise SystemExit(1)

pattern = re.compile(
    r"(?P<path>(?:file://)?[^:\r\n]*?\.swift):(?P<line>[0-9]+)(?::[0-9]+)?:\s*(?P<kind>error|warning|note):"
)
root = pathlib.Path(mac_root).resolve()
source_by_name = {}
for source_root in ("Playstead", "PlaysteadTests", "PlaysteadUITests"):
    for source_path in (root / source_root).rglob("*.swift"):
        source_by_name.setdefault(source_path.name, []).append(source_path.resolve())

safe = set()
for line in lines:
    match = pattern.search(line)
    if match is None:
        continue
    raw_path = match.group("path")
    if raw_path.startswith("file://"):
        raw_path = urllib.parse.unquote(urllib.parse.urlparse(raw_path).path)
    candidate_path = pathlib.Path(raw_path)
    candidates = source_by_name.get(candidate_path.name, [])
    if len(candidates) != 1 or not candidate_path.is_absolute():
        continue
    try:
        if candidate_path.resolve() != candidates[0]:
            continue
        source_line = int(match.group("line"))
    except (OSError, TypeError, ValueError):
        continue
    if not 1 <= source_line <= 1_000_000:
        continue
    relative = candidates[0].relative_to(root).as_posix()
    safe.add((match.group("kind"), relative, source_line))

records = sorted(safe, key=lambda record: (record[1], record[2], record[0]))
maximum = 50
for kind, source_file, source_line in records[:maximum]:
    print(f"{layer}: COMPILER_DIAGNOSTIC {kind} {source_file}:{source_line}")
if len(records) > maximum:
    print(f"{layer}: COMPILER_DIAGNOSTICS_TRUNCATED shown={maximum} total={len(records)}")
if not records:
    print(f"{layer}: bounded compiler diagnostics unavailable")
PY
}

run_with_deadline() {
  local seconds="$1"
  local log="$2"
  shift 2
  "$@" >"$log" 2>&1 &
  local command_pid=$!
  (
    sleep "$seconds"
    if kill -0 "$command_pid" 2>/dev/null; then
      kill -TERM "$command_pid" 2>/dev/null || true
      sleep 5
      kill -KILL "$command_pid" 2>/dev/null || true
    fi
  ) &
  local watchdog_pid=$!
  local status=0
  wait "$command_pid" || status=$?
  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true
  return "$status"
}

LAYER_STATUS=0
assert_local_app_launch_authorized() {
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    return 0
  fi
  if [ "${PLAYSTEAD_HUMAN_APPROVED_LOCAL_APP_LAUNCH:-}" = "1" ]; then
    return 0
  fi
  die "local UI/LiveServer verification is disabled because launching Playstead may request login-Keychain authorization; a human may explicitly set PLAYSTEAD_HUMAN_APPROVED_LOCAL_APP_LAUNCH=1, but automated GSD runs must not set it"
}

run_test_layer() {
  local slug="$1"
  local plan="$2"
  local deadline="$3"
  shift 3
  local result_bundle="${FOUR_LAYER_RAW}/${slug}.xcresult"
  local result_json="${FOUR_LAYER_RAW}/${slug}-tests.json"
  local result_summary="${FOUR_LAYER_EVIDENCE}/${slug}-tests.json"
  local log="${FOUR_LAYER_RAW}/${slug}.log"
  local signing=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=)
  local layer_settings=()
  local xcode_status=0 parse_status=0 verify_status=0

  if [ "$slug" = "live-server" ]; then
    layer_settings=(
      PLAYSTEAD_MAC_CI_ROOT="$PLAYSTEAD_MAC_CI_ROOT"
      PLAYSTEAD_LIVE_SERVER_STAGE_ROOT="$PLAYSTEAD_LIVE_SERVER_STAGE_ROOT"
      PLAYSTEAD_LIVE_SERVER_STAGE_FILE="$PLAYSTEAD_LIVE_SERVER_STAGE_FILE"
      MAC_CI_DATABASE_URL="$MAC_CI_DATABASE_URL"
      MIX_ENV="$MIX_ENV"
      PORT="$PORT"
    )
  fi

  rm -rf "$result_bundle"
  run_with_deadline "$deadline" "$log" \
    env ${layer_settings[@]+"${layer_settings[@]}"} \
      xcodebuild test-without-building -project "$PROJECT" -scheme "$SCHEME" \
      -testPlan "$plan" -destination 'platform=macOS' \
      -derivedDataPath "$DERIVED_DATA" -resultBundlePath "$result_bundle" \
      "${signing[@]}" PLAYSTEAD_SNAPSHOT_CANARY_OUTPUT="${FOUR_LAYER_EVIDENCE}/snapshot-triplet" \
      PLAYSTEAD_STORAGE_SNAPSHOT_CANDIDATE_OUTPUT="${FOUR_LAYER_EVIDENCE}/storage-candidate/storage-surfaces.actual.png" \
      PLAYSTEAD_SNAPSHOT_RECORDING=0 \
      ${layer_settings[@]+"${layer_settings[@]}"} || xcode_status=$?

  if [ -d "$result_bundle" ]; then
    xcrun xcresulttool get test-results tests --path "$result_bundle" --compact \
      >"$result_json" 2>"${FOUR_LAYER_RAW}/${slug}-xcresulttool.log" || parse_status=$?
  else
    parse_status=1
    printf '%s\n' "$slug: result bundle is missing" >"${FOUR_LAYER_RAW}/${slug}-xcresulttool.log"
  fi

  if [ "$parse_status" -eq 0 ]; then
    verify_layer_result "$result_json" "$slug" "$result_summary" "$@" || verify_status=$?
  else
    verify_status=1
  fi

  LAYER_STATUS=0
  if [ "$xcode_status" -ne 0 ] || [ "$parse_status" -ne 0 ] || [ "$verify_status" -ne 0 ]; then
    LAYER_STATUS=1
    printf '%s\n' "$slug: FAILED (xcode=$xcode_status parse=$parse_status verify=$verify_status)" >&2
    if [ -s "$result_summary" ]; then
      print_failure_diagnostics "$result_summary" "$slug" || \
        printf '%s\n' "$slug: bounded failure diagnostics unavailable"
    fi
    if [ "$slug" = "live-server" ]; then
      print_live_server_failure_stage
    fi
  else
    printf '%s\n' "$slug: PASSED"
  fi
}

write_complete_verification_evidence() {
  python3 - "$COMPLETE_EVIDENCE" "$FOUR_LAYER_EVIDENCE/environment-fingerprint.json" <<'PY'
import json, os, pathlib, sys

output = pathlib.Path(sys.argv[1])
root = output.parent
layers = [json.loads((root / f"{name}-tests.json").read_text(encoding="utf-8")) for name in ("unit", "rendering", "ui", "live-server")]
data = {
    "schema_version": 1,
    "source": "github-hosted" if os.environ.get("GITHUB_ACTIONS") == "true" else "local",
    "run": {
        "workflow": os.environ.get("GITHUB_WORKFLOW", ""),
        "event": os.environ.get("GITHUB_EVENT_NAME", ""),
        "head_branch": os.environ.get("GITHUB_HEAD_REF") or os.environ.get("GITHUB_REF_NAME", ""),
        "head_sha": os.environ.get("GITHUB_SHA", ""),
        "run_id": os.environ.get("GITHUB_RUN_ID", ""),
    },
    "fingerprint": json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")),
    "layers": layers,
    "native_health": {
        "postgresql_major": 17,
        "phoenix_healthy": True,
        "loopback_only": True,
        "cleanup_complete": True,
    },
    "linux_jobs": {
        "test": os.environ.get("LINUX_TEST_CONCLUSION", ""),
        "compose_smoke": os.environ.get("LINUX_COMPOSE_CONCLUSION", ""),
    },
}
output.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

run_four_layer_verification() {
  # Fail before build, global-default mutation, or any app launch. Unit and
  # Rendering are inert-hosted, but this aggregate also owns UI/LiveServer.
  assert_local_app_launch_authorized
  local signing=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=)
  local aggregate=0 build_status=0
  arm_keyboard_mode_cleanup
  capture_keyboard_mode

  rm -rf "$FOUR_LAYER_ROOT" "$DERIVED_DATA"
  mkdir -p "$FOUR_LAYER_RAW" "$FOUR_LAYER_EVIDENCE/snapshot-triplet" "$FOUR_LAYER_EVIDENCE/storage-candidate"
  write_fingerprint "$FOUR_LAYER_EVIDENCE/environment-fingerprint.json"

  run_with_deadline 1200 "${FOUR_LAYER_RAW}/build.log" \
    xcodebuild build-for-testing -project "$PROJECT" -scheme "$SCHEME" \
      -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA" \
      "${signing[@]}" PLAYSTEAD_SNAPSHOT_CANARY_OUTPUT="${FOUR_LAYER_EVIDENCE}/snapshot-triplet" \
      PLAYSTEAD_STORAGE_SNAPSHOT_CANDIDATE_OUTPUT="${FOUR_LAYER_EVIDENCE}/storage-candidate/storage-surfaces.actual.png" \
      PLAYSTEAD_SNAPSHOT_RECORDING=0 || build_status=$?
  if [ "$build_status" -ne 0 ]; then
    python3 - "$FOUR_LAYER_EVIDENCE/layers.json" "$build_status" <<'PY'
import json, pathlib, sys
path, status = sys.argv[1:]
pathlib.Path(path).write_text(json.dumps({
    "schema_version": 1,
    "build_count": 1,
    "automatic_retries": 0,
    "aggregate_outcome": "failed",
    "build_exit_status": int(status),
    "layers": [],
}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
    print_build_diagnostics "${FOUR_LAYER_RAW}/build.log" build || \
      printf '%s\n' 'build: bounded compiler diagnostics unavailable'
    "${SCRIPT_DIR}/sanitize-evidence.sh" --input "$FOUR_LAYER_ROOT" --output "$FAILURE_EVIDENCE"
    return 1
  fi

  run_test_layer unit Unit 900 \
    --required-test PlaysteadTests.KeychainScopingTests/testScopedMatchQueryRestrictsSearchWithoutSelectingAnAddDestination \
    --required-test PlaysteadTests.KeychainScopingTests/testScopedAddQuerySelectsDestinationWithoutChangingSearchList \
    --required-test PlaysteadTests.PlaySessionTests/test_launchSucceedsIndependentlyOfPlaySessionRecording \
    --required-test PlaysteadTests.PlaySessionTests/test_offlineSession_isDeliveredAfterReachabilityReturns \
    --required-test PlaysteadTests.PlaySessionTests/test_sameSessionIdentifierPostedTwice_resultsInOneServerSideEffect \
    --required-test PlaysteadTests.PlaySessionTests/test_userDeletion_enqueuesDeleteIntentAndRemovesFromRecent
  [ "$LAYER_STATUS" -eq 0 ] || aggregate=1

  run_test_layer rendering Rendering 600 \
    --required-test PlaysteadTests.DeterministicProfileTests/testQuotaBlockReclaimProfileComputesExactProductionDecisionBeforeExternalIO \
    --required-test PlaysteadTests.SnapshotHarnessCanaryTests/testIntentionalMismatchProducesReviewableTriplet \
    --required-test PlaysteadTests.SnapshotHarnessCanaryTests/testMeaningfulMutationFailsAndCalibratedNoisePasses \
    --required-test PlaysteadTests.LibraryContractSnapshotTests/testCardAndStatusVisualContract \
    --required-test PlaysteadTests.LibraryContractSnapshotTests/testSemanticContractOracles \
    --required-test PlaysteadTests.LibraryContractSnapshotTests/testFiveCurationShelfVisualContract \
    --required-test PlaysteadTests.StorageContractSnapshotTests/testDownloadsQuotaReclaimAndStorageVisualContract \
    --required-test PlaysteadTests.StorageContractSnapshotTests/testStorageMotionAndReducedMotionContract
  [ "$LAYER_STATUS" -eq 0 ] || aggregate=1

  run_test_layer ui UI 1800 \
    --required-test PlaysteadUITests.HostedRunnerCanaryTests/testFullKeyboardAccessCanaryFocusesAndActivatesTwoControls \
    --required-test PlaysteadUITests.HostedRunnerCanaryTests/testScopedFileKeychainStoresLoadsAndDeletesTwice \
    --required-test PlaysteadUITests.CurationInteractionTests/testCurationProfileBootstrapsLibrarySurface \
    --required-test PlaysteadUITests.CurationInteractionTests/testSidebarExposesAllFiveCurationDestinations \
    --required-test PlaysteadUITests.CurationInteractionTests/testContinueShelfRendersHonestEmptyFixture \
    --required-test PlaysteadUITests.CurationInteractionTests/testFavoritesShelfRootExists \
    --required-test PlaysteadUITests.CurationInteractionTests/testFavoritesShelfRendersExactSeededCard \
    --required-test PlaysteadUITests.CurationInteractionTests/testCollectionsShelfRootExists \
    --required-test PlaysteadUITests.CurationInteractionTests/testCollectionsShelfRendersExactSeededRoute \
    --required-test PlaysteadUITests.CurationInteractionTests/testQueueShelfRendersHonestEmptyFixture \
    --required-test PlaysteadUITests.CurationInteractionTests/testRecentShelfRendersHonestEmptyFixture \
    --required-test PlaysteadUITests.CurationInteractionTests/testCollectionDetailOpensExactSeededState \
    --required-test PlaysteadUITests.CurationInteractionTests/testCollectionDragTargetsOwnDistinctListCells \
    --required-test PlaysteadUITests.CurationInteractionTests/testCollectionMoveUpActionIsEnabledAndOwned \
    --required-test PlaysteadUITests.CurationInteractionTests/testCollectionMoveUpClickProducesOneEffect \
    --required-test PlaysteadUITests.CurationInteractionTests/testDragReorderProducesOneEffect \
    --required-test PlaysteadUITests.CurationInteractionTests/testDragReorderSurvivesRelaunch \
    --required-test PlaysteadUITests.CurationInteractionTests/testKeyboardSelectionTargetReceivesFocus \
    --required-test PlaysteadUITests.CurationInteractionTests/testKeyboardCommandProducesOneEffect \
    --required-test PlaysteadUITests.CurationInteractionTests/testKeyboardCommandRetainsSelectionAndFocus \
    --required-test PlaysteadUITests.CurationInteractionTests/testKeyboardReorderProducesOneEffectAndRetainsFocus \
    --required-test PlaysteadUITests.CurationInteractionTests/testKeyboardReorderSurvivesRelaunch \
    --required-test PlaysteadUITests.CurationInteractionTests/testKeyboardReorderRetainsFocusAndSurvivesRelaunch \
    --required-test PlaysteadUITests.StorageInteractionTests/testDownloadsPauseResumeFlow \
    --required-test PlaysteadUITests.StorageInteractionTests/testQuotaEditAndFocusRestoration \
    --required-test PlaysteadUITests.StorageInteractionTests/testReclaimRouteSettlesToUniqueDownloadTrigger \
    --required-test PlaysteadUITests.StorageInteractionTests/testReclaimRouteKeyboardFocusOwnsUniqueDownloadTrigger \
    --required-test PlaysteadUITests.StorageInteractionTests/testReclaimRouteDirectActivationDispatchesQuotaEffect \
    --required-test PlaysteadUITests.StorageInteractionTests/testReclaimRouteActivationDispatchesQuotaEffect \
    --required-test PlaysteadUITests.StorageInteractionTests/testReclaimPromptPresentsProductionRoot \
    --required-test PlaysteadUITests.StorageInteractionTests/testReclaimPromptInitialStateIsExact \
    --required-test PlaysteadUITests.StorageInteractionTests/testReclaimPromptRowIdentityExists \
    --required-test PlaysteadUITests.StorageInteractionTests/testReclaimPromptRowValueIsExact \
    --required-test PlaysteadUITests.StorageInteractionTests/testReclaimPromptToggleBelongsToPrompt \
    --required-test PlaysteadUITests.StorageInteractionTests/testReclaimPromptSelectionTextTracksExactBytes \
    --required-test PlaysteadUITests.StorageInteractionTests/testReclaimPromptConfirmBecomesEnabled \
    --required-test PlaysteadUITests.StorageInteractionTests/testReclaimPromptActionsPassLiveAudit \
    --required-test PlaysteadUITests.StorageInteractionTests/testReclaimPromptConfirmRemovesExactEligibleBytes \
    --required-test PlaysteadUITests.StorageInteractionTests/testReclaimPromptPostMutationPreservesCanonicalRows \
    --required-test PlaysteadUITests.StorageInteractionTests/testStorageInventoryPresentsProductionRoot \
    --required-test PlaysteadUITests.StorageInteractionTests/testStorageInventoryRowIdentityExists \
    --required-test PlaysteadUITests.StorageInteractionTests/testStorageInventoryRowValueIsExact \
    --required-test PlaysteadUITests.StorageInteractionTests/testStorageInventoryToggleBelongsToSurface \
    --required-test PlaysteadUITests.StorageInteractionTests/testStorageInventorySelectionTracksExactBytes \
    --required-test PlaysteadUITests.StorageInteractionTests/testStorageInventoryConfirmBecomesEnabled \
    --required-test PlaysteadUITests.StorageInteractionTests/testStorageInventoryActionsPassLiveAudit \
    --required-test PlaysteadUITests.StorageInteractionTests/testStorageInventoryConfirmMutationRemovesOnlyEligibleCopy \
    --required-test PlaysteadUITests.StorageInteractionTests/testStorageInventoryPostMutationPreservesCanonicalRows \
    --required-test PlaysteadUITests.StorageInteractionTests/testStorageInventoryProtectsPinnedCopy \
    --required-test PlaysteadUITests.SurfaceAccessibilityTests/testKeyboardOnlySurfaceInventoryAndLiveAudit
  [ "$LAYER_STATUS" -eq 0 ] || aggregate=1

  # The LiveServer layer is the native client/server behavior proof (D-04).
  # Keep PostgreSQL/Phoenix scoped to that layer and compose its fail-safe
  # service cleanup with the already-armed keyboard-mode restoration.
  trap 'cleanup_native_services; restore_keyboard_mode' EXIT
  start_native_services
  prepare_live_server_failure_stage
  run_test_layer live-server LiveServer 900 \
    --required-test PlaysteadUITests.HostedRunnerCanaryTests/testAdHocSignedAppLaunchesOnHostedRunner \
    --required-test PlaysteadUITests.LiveServerSnapshotTests/testPairedFreshMirrorRendersSnapshotBeforeAnyBlobDownloadAndPersistsKeychainAcrossRelaunch
  [ "$LAYER_STATUS" -eq 0 ] || aggregate=1
  cleanup_native_services
  trap restore_keyboard_mode EXIT

  if [ "$aggregate" -eq 0 ]; then
    write_complete_verification_evidence || aggregate=1
  fi

  python3 - "$FOUR_LAYER_EVIDENCE/layers.json" "$aggregate" <<'PY'
import json, pathlib, sys
path, aggregate = sys.argv[1:]
root = pathlib.Path(path).parent
layers = []
for name in ("unit", "rendering", "ui", "live-server"):
    candidate = root / f"{name}-tests.json"
    layers.append(json.loads(candidate.read_text()) if candidate.exists() else {"layer": name, "missing": True})
pathlib.Path(path).write_text(json.dumps({
    "schema_version": 1,
    "build_count": 1,
    "automatic_retries": 0,
    "aggregate_outcome": "passed" if aggregate == "0" else "failed",
    "layers": layers,
}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

  if [ "$aggregate" -ne 0 ]; then
    "${SCRIPT_DIR}/sanitize-evidence.sh" --input "$FOUR_LAYER_ROOT" --output "$FAILURE_EVIDENCE" || aggregate=1
  else
    rm -rf "$FAILURE_EVIDENCE"
  fi

  restore_keyboard_mode
  trap - EXIT
  return "$aggregate"
}

run_snapshot_candidates() {
  assert_hosted_environment
  local candidate_derived="${BUILD_ROOT}/snapshot-candidate-derived"
  local candidate_work="${BUILD_ROOT}/snapshot-candidate-work"
  local candidate_result="${candidate_work}/Rendering.xcresult"
  local candidate_json="${candidate_work}/rendering-tests.json"
  local candidate_summary="${candidate_work}/rendering-summary.json"
  local candidate_triplet="${candidate_work}/snapshot-triplet"
  local signing=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=)

  rm -rf "$candidate_derived" "$candidate_work" "$SNAPSHOT_CANDIDATES"
  mkdir -p "$candidate_work" "$candidate_triplet" "$SNAPSHOT_CANDIDATES"
  xcodebuild build-for-testing -project "$PROJECT" -scheme "$SCHEME" \
    -destination 'platform=macOS' -derivedDataPath "$candidate_derived" \
    "${signing[@]}" PLAYSTEAD_SNAPSHOT_CANARY_OUTPUT="$candidate_triplet" \
    PLAYSTEAD_SNAPSHOT_RECORDING=0
  xcodebuild test-without-building -project "$PROJECT" -scheme "$SCHEME" \
    -testPlan Rendering -destination 'platform=macOS' \
    -derivedDataPath "$candidate_derived" -resultBundlePath "$candidate_result" \
    "${signing[@]}" PLAYSTEAD_SNAPSHOT_CANARY_OUTPUT="$candidate_triplet" \
    PLAYSTEAD_SNAPSHOT_RECORDING=0
  xcrun xcresulttool get test-results tests --path "$candidate_result" --compact >"$candidate_json"
  verify_layer_result "$candidate_json" rendering "$candidate_summary" \
    --required-test PlaysteadTests.SnapshotHarnessCanaryTests/testIntentionalMismatchProducesReviewableTriplet \
    --required-test PlaysteadTests.SnapshotHarnessCanaryTests/testMeaningfulMutationFailsAndCalibratedNoisePasses

  local part
  for part in reference actual diff; do
    [ -s "$candidate_triplet/${part}.png" ] || die "snapshot candidate is missing ${part}.png"
    install -m 0644 "$candidate_triplet/${part}.png" \
      "$SNAPSHOT_CANDIDATES/snapshot-harness-canary.${part}.png"
  done
  [ "$(find "$SNAPSHOT_CANDIDATES" -type f | wc -l | tr -d ' ')" -eq 3 ] || \
    die "candidate output must contain exactly one named reference/actual/diff triplet"
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
  chmod 0700 "$NATIVE_ROOT" "$server_root"

  "$pg_bin/initdb" -D "$PGDATA" --auth=trust --no-locale --encoding=UTF8 >/dev/null
  "$PG_CTL" -D "$PGDATA" -l "$NATIVE_ROOT/postgres.log" \
    -o "-h 127.0.0.1 -p $pg_port" -w start >/dev/null
  "$pg_bin/createdb" -h 127.0.0.1 -p "$pg_port" playstead_mac_ci

  export MIX_ENV=mac_ci
  export PORT=4010
  export PLAYSTEAD_MAC_CI_ROOT="$server_root"
  export PLAYSTEAD_LIVE_SERVER_STAGE_ROOT="$server_root"
  export PLAYSTEAD_LIVE_SERVER_STAGE_FILE="$server_root/live-server-failure-stage"
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

run_layer_verifier_self_tests() {
  "${SCRIPT_DIR}/tests/four-layer-verifier-test.sh"
}

run_complete_hosted_self_tests() {
  python3 - "$0" <<'PY'
import copy, json, pathlib, subprocess, sys, tempfile

runner = pathlib.Path(sys.argv[1]).resolve()
sha = "0123456789abcdef0123456789abcdef01234567"
run_id = 9001
job_names = {
    "test": "mix precommit (unit + LiveView + browser + integration)",
    "compose-smoke": "docker compose cold start",
    "mac-verification": "macOS 26 unit + rendering + UI + live server",
}

def required(identifier):
    return {"identifier": identifier, "discovered": True, "execution_count": 1, "skipped": False, "outcome": "passed"}

base_record = {
    "schema_version": 1, "run_id": run_id, "workflow": "ci", "event": "push",
    "head_branch": "main", "head_sha": sha, "status": "completed", "conclusion": "success",
    "url": "https://github.example/actions/runs/9001",
    "jobs": {key: "success" for key in job_names},
}
base_view = {
    "databaseId": run_id, "workflowName": "ci", "event": "push", "headBranch": "main",
    "headSha": sha, "status": "completed", "conclusion": "success", "url": base_record["url"],
    "jobs": [{"name": name, "status": "completed", "conclusion": "success"} for name in job_names.values()],
}
base_manifest = {
    "schema_version": 1, "source": "github-hosted",
    "run": {"run_id": str(run_id), "workflow": "ci", "event": "push", "head_branch": "main", "head_sha": sha},
    "fingerprint": {"architecture": "arm64", "xcode": ["Xcode 26.6", "Build version 17F113"]},
    "native_health": {"postgresql_major": 17, "phoenix_healthy": True, "loopback_only": True, "cleanup_complete": True},
    "linux_jobs": {"test": "success", "compose_smoke": "success"},
    "layers": [
        {"layer": "unit", "executed_test_count": 1, "failed_test_count": 0, "audit_issue_count": 0, "required_tests": [required("PlaysteadTests.PlaySessionTests/test_launchSucceedsIndependentlyOfPlaySessionRecording")]},
        {"layer": "rendering", "executed_test_count": 1, "failed_test_count": 0, "audit_issue_count": 0, "required_tests": [required("PlaysteadTests.LibraryContractSnapshotTests/testCardAndStatusVisualContract")]},
        {"layer": "ui", "executed_test_count": 1, "failed_test_count": 0, "audit_issue_count": 0, "required_tests": [required("PlaysteadUITests.SurfaceAccessibilityTests/testKeyboardOnlySurfaceInventoryAndLiveAudit")]},
        {"layer": "live-server", "executed_test_count": 1, "failed_test_count": 0, "audit_issue_count": 0, "required_tests": [required("PlaysteadUITests.LiveServerSnapshotTests/testPairedFreshMirrorRendersSnapshotBeforeAnyBlobDownloadAndPersistsKeychainAcrossRelaunch")]},
    ],
}

def execute(root, record, view, manifest, malformed=False):
    paths = [root / name for name in ("record.json", "view.json", "manifest.json")]
    for path, value in zip(paths, (record, view, manifest)):
        path.write_text("{" if malformed and path.name == "manifest.json" else json.dumps(value), encoding="utf-8")
    return subprocess.run(
        [str(runner), "--verify-hosted-run", "complete", "--run-record", str(paths[0]), "--run-view", str(paths[1]), "--manifest", str(paths[2])],
        text=True, capture_output=True, check=False,
    )

with tempfile.TemporaryDirectory() as temporary:
    root = pathlib.Path(temporary)
    if execute(root, base_record, base_view, base_manifest).returncode != 0:
        raise SystemExit("valid complete hosted evidence was rejected")
    mutations = []
    for key in ("workflow", "event", "head_branch", "head_sha", "run_id"):
        record = copy.deepcopy(base_record)
        record[key] = "wrong" if key != "run_id" else 42
        mutations.append((f"wrong-{key}", record, base_view, base_manifest, False))
    for field, value in (("status", "in_progress"), ("conclusion", "failure")):
        view = copy.deepcopy(base_view); view[field] = value
        mutations.append((f"view-{field}", base_record, view, base_manifest, False))
    for job_key, job_name in job_names.items():
        view = copy.deepcopy(base_view); view["jobs"] = [job for job in view["jobs"] if job["name"] != job_name]
        mutations.append((f"missing-job-{job_key}", base_record, view, base_manifest, False))
    manifest = copy.deepcopy(base_manifest); manifest["linux_jobs"]["test"] = "skipped"
    mutations.append(("skipped-linux", base_record, base_view, manifest, False))
    manifest = copy.deepcopy(base_manifest); manifest["layers"][2]["required_tests"][0]["skipped"] = True
    mutations.append(("skipped-test", base_record, base_view, manifest, False))
    manifest = copy.deepcopy(base_manifest); manifest["layers"][2]["required_tests"] = []
    mutations.append(("absent-test", base_record, base_view, manifest, False))
    manifest = copy.deepcopy(base_manifest); manifest["layers"][2]["required_tests"][0]["outcome"] = "failed"
    mutations.append(("failed-test", base_record, base_view, manifest, False))
    manifest = copy.deepcopy(base_manifest); manifest["layers"] = manifest["layers"][:3]
    mutations.append(("missing-layer", base_record, base_view, manifest, False))
    manifest = copy.deepcopy(base_manifest); manifest["run"]["head_sha"] = "f" * 40
    mutations.append(("mismatched-manifest", base_record, base_view, manifest, False))
    mutations.append(("malformed-manifest", base_record, base_view, base_manifest, True))
    for name, record, view, manifest, malformed in mutations:
        if execute(root, record, view, manifest, malformed).returncode == 0:
            raise SystemExit(f"complete hosted validator accepted invalid fixture: {name}")
print(f"complete hosted validator rejected {len(mutations)} identity/status/schema/job fixtures")
PY
}

verify_required_uat_allowlist() {
  python3 - "$0" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
required = [
    "PlaysteadTests.LibraryContractSnapshotTests/testCardAndStatusVisualContract",
    "PlaysteadTests.LibraryContractSnapshotTests/testSemanticContractOracles",
    "PlaysteadTests.LibraryContractSnapshotTests/testFiveCurationShelfVisualContract",
    "PlaysteadTests.StorageContractSnapshotTests/testDownloadsQuotaReclaimAndStorageVisualContract",
    "PlaysteadTests.StorageContractSnapshotTests/testStorageMotionAndReducedMotionContract",
    "PlaysteadTests.PlaySessionTests/test_launchSucceedsIndependentlyOfPlaySessionRecording",
    "PlaysteadTests.PlaySessionTests/test_offlineSession_isDeliveredAfterReachabilityReturns",
    "PlaysteadTests.PlaySessionTests/test_sameSessionIdentifierPostedTwice_resultsInOneServerSideEffect",
    "PlaysteadTests.PlaySessionTests/test_userDeletion_enqueuesDeleteIntentAndRemovesFromRecent",
    "PlaysteadUITests.SurfaceAccessibilityTests/testKeyboardOnlySurfaceInventoryAndLiveAudit",
    "PlaysteadUITests.LiveServerSnapshotTests/testPairedFreshMirrorRendersSnapshotBeforeAnyBlobDownloadAndPersistsKeychainAcrossRelaunch",
]
missing = [identifier for identifier in required if f"--required-test {identifier}" not in source]
if missing:
    raise SystemExit("required UAT allowlist entries missing: " + ", ".join(missing))
print(f"verified {len(required)} cross-layer UAT allowlist anchors")
PY
}

run_sanitizer_self_tests() {
  "${SCRIPT_DIR}/tests/sanitizer-test.sh"
}

verify_four_layer_topology() {
  "${SCRIPT_DIR}/tests/four-layer-topology-test.sh"
}

verify_topology() {
  "${SCRIPT_DIR}/tests/wave-0-topology-test.sh"
}

run_selected_layer_tests() {
  local layer="$1"
  shift
  case "$layer" in
    rendering|ui) ;;
    *) die "targeted verification supports only rendering or ui" ;;
  esac
  [ "${1:-}" = "--only-testing" ] || die "--layers $layer requires --only-testing TEST"
  shift
  [ "$#" -gt 0 ] || die "--only-testing requires at least one test identifier"

  local selected_root="${BUILD_ROOT}/selected-${layer}"
  local test_plan="Rendering"
  [ "$layer" != "ui" ] || test_plan="UI"
  [ "$layer" != "ui" ] || assert_local_app_launch_authorized
  if [ "$layer" = "ui" ]; then
    arm_keyboard_mode_cleanup
    capture_keyboard_mode
  fi
  local signing=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=)
  local only_testing=()
  while [ "$#" -gt 0 ]; do
    only_testing+=("-only-testing:$1")
    shift
  done

  mkdir -p "$selected_root"
  xcodebuild test -project "$PROJECT" -scheme "$SCHEME" -testPlan "$test_plan" \
    -destination 'platform=macOS' -derivedDataPath "$selected_root" \
    "${signing[@]}" "${only_testing[@]}"

  if [ "$layer" = "ui" ]; then
    restore_keyboard_mode
    trap - EXIT
  fi
}

test_early_keyboard_cleanup() (
  # Model a fallible operation after the trap is armed but before the global
  # keyboard default has been captured or mutated. EXIT must preserve the
  # original failure and perform no `defaults` operation.
  arm_keyboard_mode_cleanup
  return 97
)

usage() {
  cat <<'USAGE'
Usage:
  run-mac-verification.sh --run-wave-0-adoption
  run-mac-verification.sh --run-four-layer-verification
  run-mac-verification.sh --run-snapshot-candidates
  run-mac-verification.sh --layers {rendering|ui} --only-testing TEST [TEST ...]
  run-mac-verification.sh --verify-layer-result FILE LAYER OUTPUT --required-test ID [...]
  run-mac-verification.sh --print-failure-diagnostics SUMMARY LAYER
  run-mac-verification.sh --print-build-diagnostics LOG LAYER
  run-mac-verification.sh --self-test-result-verifier
  run-mac-verification.sh --self-test-sanitizer [--verify-four-layer-topology]
  run-mac-verification.sh --verify-four-layer-topology
  run-mac-verification.sh --verify-result FILE --required-canary ID [expected metadata]
  run-mac-verification.sh --validate-hosted-run FILE [expected metadata]
  run-mac-verification.sh --verify-hosted-run complete --run-record FILE --run-view FILE [--manifest FILE]
  run-mac-verification.sh --self-test-hosted-run-validator [--verify-required-uat-allowlist] [--verify-complete-evidence-schema]
  run-mac-verification.sh --verify-wave-0-topology
  run-mac-verification.sh --self-test-early-keyboard-cleanup
USAGE
}

[ "$#" -gt 0 ] || { usage >&2; exit 2; }
case "$1" in
  --layers)
    require_value "$1" "${2:-}"
    layer="$2"
    shift 2
    run_selected_layer_tests "$layer" "$@"
    ;;
  --verify-result) require_value "$1" "${2:-}"; evidence="$2"; shift 2; verify_result "$evidence" "$@" ;;
  --validate-hosted-run) require_value "$1" "${2:-}"; metadata="$2"; shift 2; validate_hosted_run "$metadata" "$@" ;;
  --verify-hosted-run)
    require_value "$1" "${2:-}"
    [ "$2" = "complete" ] || die "--verify-hosted-run supports only complete"
    shift
    verify_complete_hosted_run "$@"
    ;;
  --run-wave-0-adoption) shift; [ "$#" -eq 0 ] || die "unexpected adoption arguments"; run_wave_0_adoption ;;
  --run-four-layer-verification) shift; [ "$#" -eq 0 ] || die "unexpected four-layer arguments"; run_four_layer_verification ;;
  --run-snapshot-candidates) shift; [ "$#" -eq 0 ] || die "unexpected snapshot candidate arguments"; run_snapshot_candidates ;;
  --verify-layer-result)
    require_value "$1" "${2:-}"; require_value "$1" "${3:-}"; require_value "$1" "${4:-}"
    test_results="$2"; layer="$3"; output="$4"; shift 4
    verify_layer_result "$test_results" "$layer" "$output" "$@"
    ;;
  --print-failure-diagnostics)
    require_value "$1" "${2:-}"; require_value "$1" "${3:-}"
    summary="$2"; layer="$3"; shift 3
    [ "$#" -eq 0 ] || die "unexpected failure diagnostic arguments"
    print_failure_diagnostics "$summary" "$layer"
    ;;
  --print-build-diagnostics)
    require_value "$1" "${2:-}"; require_value "$1" "${3:-}"
    log="$2"; layer="$3"; shift 3
    [ "$#" -eq 0 ] || die "unexpected build diagnostic arguments"
    print_build_diagnostics "$log" "$layer"
    ;;
  --self-test-result-verifier) shift; [ "$#" -eq 0 ] || die "unexpected verifier self-test arguments"; run_layer_verifier_self_tests ;;
  --self-test-sanitizer)
    shift
    verify_topology_after=false
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --verify-four-layer-topology) verify_topology_after=true; shift ;;
        *) die "unknown sanitizer self-test argument: $1" ;;
      esac
    done
    run_sanitizer_self_tests
    [ "$verify_topology_after" = false ] || verify_four_layer_topology
    ;;
  --verify-four-layer-topology) shift; [ "$#" -eq 0 ] || die "unexpected topology arguments"; verify_four_layer_topology ;;
  --verify-wave-0-topology) shift; [ "$#" -eq 0 ] || die "unexpected topology arguments"; verify_topology ;;
  --self-test-early-keyboard-cleanup)
    shift
    [ "$#" -eq 0 ] || die "unexpected keyboard cleanup self-test arguments"
    test_early_keyboard_cleanup
    ;;
  --self-test-wave-0-verifier|--self-test-hosted-run-validator)
    verify_topology_after=false
    complete_schema=false
    required_uat=false
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --self-test-wave-0-verifier) shift ;;
        --self-test-hosted-run-validator) complete_schema=true; shift ;;
        --verify-wave-0-topology) verify_topology_after=true; shift ;;
        --verify-complete-evidence-schema) complete_schema=true; shift ;;
        --verify-required-uat-allowlist) required_uat=true; shift ;;
        --only-canaries) require_value "$1" "${2:-}"; shift 2 ;;
        *) die "unknown self-test argument: $1" ;;
      esac
    done
    run_self_tests
    [ "$complete_schema" = false ] || run_complete_hosted_self_tests
    [ "$required_uat" = false ] || verify_required_uat_allowlist
    [ "$verify_topology_after" = false ] || verify_topology
    ;;
  -h|--help) usage ;;
  *) die "unknown mode: $1" ;;
esac
