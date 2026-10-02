#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

die() {
  printf 'evidence sanitizer: %s\n' "$*" >&2
  exit 1
}

[ "$#" -eq 4 ] || die "usage: sanitize-evidence.sh --input ROOT --output DIRECTORY"
[ "$1" = "--input" ] || die "first argument must be --input"
INPUT_ROOT="$2"
[ "$3" = "--output" ] || die "third argument must be --output"
OUTPUT_ROOT="$4"

[ -d "$INPUT_ROOT/evidence" ] || die "input evidence directory is missing"
[ -n "$OUTPUT_ROOT" ] && [ "$OUTPUT_ROOT" != "/" ] || die "unsafe output directory"
[ "$INPUT_ROOT" != "$OUTPUT_ROOT" ] || die "input and output directories must differ"

rm -rf "$OUTPUT_ROOT"
mkdir -p "$OUTPUT_ROOT"

python3 - "$INPUT_ROOT/evidence" "$OUTPUT_ROOT" "$MAC_ROOT" <<'PY'
import json, pathlib, re, shutil, sys
import math

source = pathlib.Path(sys.argv[1]).resolve()
output = pathlib.Path(sys.argv[2]).resolve()
mac_root = pathlib.Path(sys.argv[3]).resolve()
max_files = 40
max_total = 12 * 1024 * 1024
max_text = 256 * 1024
max_image = 2 * 1024 * 1024
max_storage_candidate = 8 * 1024 * 1024

allowed = []
recovery_candidate = source / "recovery-e2e.json"
recovery_failure_candidate = source / "recovery-failure.json"
if recovery_candidate.is_file() and recovery_failure_candidate.is_file():
    raise SystemExit("both passing and failed recovery receipts are present")
if recovery_candidate.is_file():
    allowed.append(recovery_candidate)
if recovery_failure_candidate.is_file():
    allowed.append(recovery_failure_candidate)
continuation_candidate = source / "continuation.json"
if continuation_candidate.is_file():
    allowed.append(continuation_candidate)
save_reliability_candidate = source / "save-reliability.json"
if save_reliability_candidate.is_file():
    allowed.append(save_reliability_candidate)
for name in ("environment-fingerprint.json", "layers.json"):
    candidate = source / name
    if candidate.is_file():
        allowed.append(candidate)
virtual_gamepad_status = source / "entitled-gamepad.json"
if virtual_gamepad_status.is_file():
    allowed.append(virtual_gamepad_status)
allowed.extend(sorted(source.glob("*-tests.json")))
for name in ("reference.png", "actual.png", "diff.png"):
    candidate = source / "snapshot-triplet" / name
    if candidate.is_file():
        allowed.append(candidate)
storage_candidate = source / "storage-candidate" / "storage-surfaces.actual.png"
if storage_candidate.is_file():
    allowed.append(storage_candidate)
allowed.extend(sorted((source / "screenshots").glob("synthetic-*.png")) if (source / "screenshots").is_dir() else [])
if (source / "accessibility").is_dir():
    allowed.extend(sorted((source / "accessibility").glob("*.tree.txt")))
    allowed.extend(sorted((source / "accessibility").glob("*.focus.txt")))
if (source / "logs").is_dir():
    for name in ("app.log", "server.log"):
        candidate = source / "logs" / name
        if candidate.is_file():
            allowed.append(candidate)
notarization_log = source / "notarization.log"
if notarization_log.is_file():
    allowed.append(notarization_log)

allowed = list(dict.fromkeys(allowed))
if not allowed:
    raise SystemExit("no allowlisted evidence files were found")
if len(allowed) > max_files:
    raise SystemExit(f"evidence file count exceeds {max_files}")

sensitive_keys = {
    "authorization", "credential", "credentials", "token", "database_url",
    "raw_log", "keychain_path", "handoff", "environment", "env",
    "password", "secret", "secret_key_base", "api_key",
}
# Sensitive-key vocabulary matched regardless of separator (`:` or `=`), so
# `KEY: value` (colon-separated, e.g. a Postgres/Phoenix structured log line
# like `DATABASE_URL: ecto://...`) is caught alongside the historical
# `KEY=value` shape. This is a structural check on the key name, not a fixed
# list of literal `key<sep>` strings, so it also fails closed for shapes not
# explicitly enumerated below.
sensitive_key_vocabulary = (
    r"authorization|bearer|token|database_url|secret_key_base|password|"
    r"api[-_]?key|secret"
)
# A connection string / URL with embedded `user:pass@` credentials, in any
# scheme (ecto://, postgres://, https://, etc.), anywhere in the line —
# including mid-sentence in a stack trace or exception message.
credential_url = r"[A-Za-z][A-Za-z0-9+.-]*://[^\s\"'/@]+:[^\s\"'/@]+@"
sensitive_text = re.compile(
    r"(?i)("
    rf"\b(?:{sensitive_key_vocabulary})\b\s*[:=]\s*\S+|"
    r"bearer\s+[A-Za-z0-9._~+/=-]+|"
    r"\.keychain(?:-db)?\b|"
    r"(?:^|[/\\])\.env(?:\b|[/\\])|credential[-_ ]?handoff|"
    r"(?:^|[/\\])(?:objects|partials)(?:[/\\]|$)|"
    rf"{credential_url}|"
    r"\b[0-9a-f]{64}\b|\.(?:rom|nes|sfc|smc|gba|gbc|iso|chd|cue|bios)\b)"
)
path_text = re.compile(r"(?:file://)?/(?:Users|private|var/folders|tmp)/[^\s\"']+")

def scan_json(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key.lower() in sensitive_keys:
                raise SystemExit(f"secret-bearing JSON key is forbidden: {key}")
            scan_json(child)
    elif isinstance(value, list):
        for child in value:
            scan_json(child)
    elif isinstance(value, str):
        if sensitive_text.search(value) or path_text.search(value):
            raise SystemExit("secret, content identifier, or local path found in structured evidence")

test_identifier = re.compile(r"^[A-Za-z_][A-Za-z0-9_.]*/[A-Za-z_][A-Za-z0-9_]*\(\)$")

# 04-18 promoted the reachability sweep to a real layer. It is a static sweep,
# not an xctest layer -- there is no xcresult to parse, so it writes a summary of
# a different shape into the same evidence directory. This validator matched it
# by filename alone and rejected it, which aborted sanitization partway and
# truncated the failure evidence for every failing run (the per-layer test
# evidence never reached the artifact). Recognise the sweep's own shape.
def validate_static_sweep_evidence(data, relative):
    allowed_keys = {"layer", "kind", "outcome", "exit_status"}
    if not isinstance(data, dict) or set(data) != allowed_keys:
        raise SystemExit(f"static sweep evidence has unexpected schema: {relative}")
    if not isinstance(data.get("layer"), str) or data.get("kind") != "static-sweep":
        raise SystemExit(f"static sweep evidence identity is malformed: {relative}")
    if data.get("outcome") not in ("passed", "failed"):
        raise SystemExit(f"static sweep evidence outcome is malformed: {relative}")
    if type(data.get("exit_status")) is not int or data["exit_status"] < 0:
        raise SystemExit(f"static sweep evidence exit status is malformed: {relative}")


def validate_recovery_evidence(data, relative):
    if isinstance(data, dict) and data.get("schema") == "playstead.continuation-local.v1":
        expected = {"schema", "run_id", "stage", "outcome"}
        if set(data) != expected:
            raise SystemExit(f"local continuation receipt has unexpected schema: {relative}")
        if not isinstance(data.get("run_id"), str) or not re.fullmatch(
            r"[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}",
            data["run_id"],
        ):
            raise SystemExit(f"local continuation run identifier is malformed: {relative}")
        if data.get("stage") not in {"preflight", "qualification", "initial-save", "safe-exit", "fresh-launch", "continue", "oracle"}:
            raise SystemExit(f"local continuation stage is not allowlisted: {relative}")
        if data.get("outcome") not in {"passed", "failed-stage", "blocked-capability"}:
            raise SystemExit(f"local continuation outcome is not allowlisted: {relative}")
        allowed_outcomes = (
            {"blocked-capability"} if data["stage"] in {"preflight", "qualification"}
            else {"passed", "failed-stage"} if data["stage"] == "oracle"
            else {"failed-stage"}
        )
        if data["outcome"] not in allowed_outcomes:
            raise SystemExit(f"local continuation stage and outcome are inconsistent: {relative}")
        return
    if isinstance(data, dict) and data.get("schema") == "playstead.recovery-e2e-local.v1":
        expected = {"schema", "run_id", "lane", "stage", "outcome"}
        if set(data) != expected:
            raise SystemExit(f"local recovery receipt has unexpected schema: {relative}")
        if data.get("lane") != "same_host_restored_target":
            raise SystemExit(f"local recovery receipt identity is malformed: {relative}")
        if not isinstance(data.get("run_id"), str) or not re.fullmatch(
            r"[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}",
            data["run_id"],
        ):
            raise SystemExit(f"local recovery run identifier is malformed: {relative}")
        stages = {
            "handoff_validation", "fixture_validation", "browser_trust", "preflight",
            "clean_mac_ui", "package_cache", "code_signing", "test_plan", "test_launch",
            "xctest", "build", "clean_launch", "local_ca_pairing_request", "owner_approval",
            "cursor_convergence", "cache_preflight", "persistent_save_transport_restore",
            "controlled_exit", "relaunch", "complete",
        }
        stage = data.get("stage")
        outcome = data.get("outcome")
        if not isinstance(stage, str) or stage not in stages or not isinstance(outcome, str) or outcome not in {"passed", "blocked"}:
            raise SystemExit(f"local recovery stage or outcome is not allowlisted: {relative}")
        if (stage == "complete") != (outcome == "passed"):
            raise SystemExit(f"local recovery stage and outcome are inconsistent: {relative}")
        return

    expected = {"schema_version", "run_id", "lane", "stages", "outcome"}
    if not isinstance(data, dict) or set(data) != expected:
        raise SystemExit(f"recovery evidence has unexpected schema: {relative}")
    if data.get("schema_version") != 1 or data.get("lane") != "linux_restore_fixture":
        raise SystemExit(f"recovery evidence identity is malformed: {relative}")
    if not isinstance(data.get("run_id"), str) or not re.fullmatch(
        r"[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}",
        data["run_id"],
    ):
        raise SystemExit(f"recovery run identifier is malformed: {relative}")
    if data.get("outcome") not in {"passed", "failed", "blocked"}:
        raise SystemExit(f"recovery outcome is malformed: {relative}")
    stages = data.get("stages")
    allowed_stages = ["chain", "preflight", "database", "cas", "manifest", "api"]
    if not isinstance(stages, list) or stages != allowed_stages:
        raise SystemExit(f"recovery stage list is malformed: {relative}")


def validate_recovery_failure_evidence(data, relative):
    expected = {"schema", "lane", "outcome", "failure_stage"}
    if not isinstance(data, dict) or set(data) != expected:
        raise SystemExit(f"recovery failure evidence has unexpected schema: {relative}")
    if data.get("schema") != "playstead.recovery-failure.v1":
        raise SystemExit(f"recovery failure schema is malformed: {relative}")
    if data.get("lane") != "linux_restore_fixture" or data.get("outcome") != "failed":
        raise SystemExit(f"recovery failure identity is malformed: {relative}")
    allowed_stages = {
        "source-compose-startup", "source-readiness", "source-fixture-filesystem-create",
        "source-fixture-database-seed",
        "source-dump", "backup-publication", "target-restore", "target-cleanup",
        "result-validation", "unknown",
    }
    failure_stage = data.get("failure_stage")
    if not isinstance(failure_stage, str) or failure_stage not in allowed_stages:
        raise SystemExit(f"recovery failure stage is not allowlisted: {relative}")


def reject_duplicate_json_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def validate_test_evidence(data, relative):
    allowed_keys = {
        "schema_version", "layer", "executed_test_count", "required_tests",
        "failed_test_count", "failed_tests_truncated", "failed_tests",
        "failure_diagnostic_count", "failure_diagnostics_truncated", "failure_diagnostics",
        "audit_issue_count", "audit_issues_truncated", "audit_issues",
        "layout_diagnostic_count", "layout_diagnostics_truncated", "layout_diagnostics",
    }
    legacy_keys = allowed_keys - {
        "failure_diagnostic_count", "failure_diagnostics_truncated", "failure_diagnostics"
    }
    legacy_keys_without_layout = legacy_keys - {
        "layout_diagnostic_count", "layout_diagnostics_truncated", "layout_diagnostics"
    }
    allowed_keys_without_layout = allowed_keys - {
        "layout_diagnostic_count", "layout_diagnostics_truncated", "layout_diagnostics"
    }
    # 04-23: the writer grew a timing block (c3f51e1) and this allowlist did not,
    # so every layer file was rejected. Nothing caught it for three days because
    # the sanitizer only runs when a layer has already failed -- the one moment
    # the evidence is needed. Timing is optional (older evidence predates it) but
    # all-or-nothing, and its values are validated like every other block.
    timing_keys = {"in_test_seconds_total", "timed_test_count", "slowest_tests"}
    actual_keys = set(data) if isinstance(data, dict) else set()
    core_keys = actual_keys - timing_keys - {"runner_process_error_count"}
    if not isinstance(data, dict) or core_keys not in (
        allowed_keys, legacy_keys, allowed_keys_without_layout, legacy_keys_without_layout
    ):
        raise SystemExit(f"test evidence has unexpected schema: {relative}")
    present_timing = actual_keys & timing_keys
    if present_timing not in (set(), timing_keys):
        raise SystemExit(f"test evidence timing block is partial: {relative}")
    if "runner_process_error_count" in actual_keys:
        runner_error_count = data.get("runner_process_error_count")
        if type(runner_error_count) is not int or not 0 <= runner_error_count <= 50:
            raise SystemExit(f"runner process error count is malformed: {relative}")
    if present_timing:
        total = data.get("in_test_seconds_total")
        if type(total) not in (int, float) or type(total) is bool or total < 0:
            raise SystemExit(f"test evidence timing total is malformed: {relative}")
        if type(data.get("timed_test_count")) is not int or data["timed_test_count"] < 0:
            raise SystemExit(f"test evidence timed test count is malformed: {relative}")
        slowest = data.get("slowest_tests")
        if not isinstance(slowest, list) or len(slowest) > 20:
            raise SystemExit(f"slowest_tests exceeds its bounded allowlist: {relative}")
        for record in slowest:
            if not isinstance(record, dict) or set(record) != {"identifier", "seconds"}:
                raise SystemExit(f"slowest test record contains non-allowlisted fields: {relative}")
            identifier = record.get("identifier")
            if not isinstance(identifier, str) or len(identifier) > 240 or not test_identifier.fullmatch(identifier):
                raise SystemExit(f"slowest test identifier is not canonical: {relative}")
            seconds = record.get("seconds")
            if type(seconds) not in (int, float) or type(seconds) is bool or seconds < 0:
                raise SystemExit(f"slowest test duration is malformed: {relative}")
    if data.get("schema_version") != 1 or not isinstance(data.get("layer"), str):
        raise SystemExit(f"test evidence identity is malformed: {relative}")
    if type(data.get("executed_test_count")) is not int or data["executed_test_count"] < 0:
        raise SystemExit(f"test evidence execution count is malformed: {relative}")
    failed = data.get("failed_tests")
    failed_count = data.get("failed_test_count")
    truncated = data.get("failed_tests_truncated")
    if not isinstance(failed, list) or len(failed) > 50:
        raise SystemExit(f"failed_tests exceeds its bounded allowlist: {relative}")
    if type(failed_count) is not int or failed_count < len(failed) or type(truncated) is not bool:
        raise SystemExit(f"failed_tests metadata is malformed: {relative}")
    if (not truncated and failed_count != len(failed)) or (truncated and (failed_count <= 50 or len(failed) != 50)):
        raise SystemExit(f"failed_tests truncation metadata is inconsistent: {relative}")
    for record in failed:
        if not isinstance(record, dict) or set(record) != {"identifier", "outcome"}:
            raise SystemExit(f"failed test record contains non-allowlisted fields: {relative}")
        identifier = record.get("identifier")
        if not isinstance(identifier, str) or len(identifier) > 240 or not test_identifier.fullmatch(identifier):
            raise SystemExit(f"failed test identifier is not canonical: {relative}")
        if record.get("outcome") not in {"failed", "skipped", "unknown"}:
            raise SystemExit(f"failed test outcome is not allowlisted: {relative}")
    diagnostics = data.get("failure_diagnostics", [])
    diagnostic_count = data.get("failure_diagnostic_count", 0)
    diagnostics_truncated = data.get("failure_diagnostics_truncated", False)
    if not isinstance(diagnostics, list) or len(diagnostics) > 50:
        raise SystemExit(f"failure_diagnostics exceeds its bounded allowlist: {relative}")
    if type(diagnostic_count) is not int or diagnostic_count < len(diagnostics) or type(diagnostics_truncated) is not bool:
        raise SystemExit(f"failure_diagnostics metadata is malformed: {relative}")
    if (not diagnostics_truncated and diagnostic_count != len(diagnostics)) or (diagnostics_truncated and (diagnostic_count <= 50 or len(diagnostics) != 50)):
        raise SystemExit(f"failure_diagnostics truncation metadata is inconsistent: {relative}")
    allowed_assertions = {
        "XCTAssertTrue", "XCTAssertFalse", "XCTAssertEqual", "XCTAssertNotEqual",
        "XCTAssertNil", "XCTAssertNotNil", "XCTAssertLessThan", "XCTAssertLessThanOrEqual",
        "XCTAssertGreaterThan", "XCTAssertGreaterThanOrEqual", "XCTAssertNoThrow",
        "XCTAssertThrowsError", "XCTFail", "XCTUnwrap",
    }
    for record in diagnostics:
        base_diagnostic_keys = {"test_identifier", "assertion", "source_file", "source_line"}
        if not isinstance(record, dict) or set(record) not in (base_diagnostic_keys, base_diagnostic_keys | {"failure_stage"}):
            raise SystemExit(f"failure diagnostic contains non-allowlisted fields: {relative}")
        if not isinstance(record.get("test_identifier"), str) or not test_identifier.fullmatch(record["test_identifier"]):
            raise SystemExit(f"failure diagnostic test identifier is not canonical: {relative}")
        if "failure_stage" in record:
            allowed_zero_network_stages = {
                "stand-in-signing", "adapter-selection", "synthetic-cas", "catalogue-readiness",
                "materialization-save-setup", "adapter-launch", "adapter-exit", "unclassified",
            }
            if record["test_identifier"] != "ZeroNetworkPlayFlowTests/testWholePlayFlowRecordsZeroHTTPRequests()":
                raise SystemExit(f"failure stage belongs to an unexpected test: {relative}")
            if record.get("failure_stage") not in allowed_zero_network_stages:
                raise SystemExit(f"failure stage is not allowlisted: {relative}")
        if record.get("assertion") not in allowed_assertions:
            raise SystemExit(f"failure diagnostic assertion is not canonical: {relative}")
        source_file = record.get("source_file")
        if not isinstance(source_file, str) or not re.fullmatch(r"(?:Playstead|PlaysteadTests|PlaysteadUITests)/(?:[A-Za-z_][A-Za-z0-9_]*/)*[A-Za-z_][A-Za-z0-9_]*\.swift", source_file):
            raise SystemExit(f"failure diagnostic source is not repository-relative Swift: {relative}")
        source_path = mac_root / source_file
        same_named_sources = [candidate for root_name in ("Playstead", "PlaysteadTests", "PlaysteadUITests") for candidate in (mac_root / root_name).rglob(source_path.name)]
        if not source_path.is_file() or len(same_named_sources) != 1 or same_named_sources[0].resolve() != source_path.resolve():
            raise SystemExit(f"failure diagnostic source is not one unique project source: {relative}")
        if type(record.get("source_line")) is not int or not 1 <= record["source_line"] <= 1_000_000:
            raise SystemExit(f"failure diagnostic line is malformed: {relative}")
    if "layout_diagnostic_count" in data:
        layout_records = data["layout_diagnostics"]
        layout_count = data["layout_diagnostic_count"]
        layout_truncated = data["layout_diagnostics_truncated"]
        if not isinstance(layout_records, list) or len(layout_records) > 50:
            raise SystemExit(f"layout_diagnostics exceeds its bounded allowlist: {relative}")
        if type(layout_count) is not int or layout_count < len(layout_records) or type(layout_truncated) is not bool:
            raise SystemExit(f"layout diagnostic metadata is malformed: {relative}")
        if (not layout_truncated and layout_count != len(layout_records)) or (layout_truncated and (layout_count <= 50 or len(layout_records) != 50)):
            raise SystemExit(f"layout diagnostic truncation metadata is inconsistent: {relative}")
        for record in layout_records:
            if not isinstance(record, dict) or set(record) not in (
                {"kind", "hittable", "element", "pane", "window"},
                {"kind", "hittable", "element", "pane", "window", "slot"},
            ):
                raise SystemExit(f"layout diagnostic contains non-allowlisted fields: {relative}")
            if record.get("kind") not in {"moveUp", "dragCell", "orderCell"} or type(record.get("hittable")) is not bool:
                raise SystemExit(f"layout diagnostic identity is malformed: {relative}")
            if ("slot" in record) != (record["kind"] == "orderCell"):
                raise SystemExit(f"layout diagnostic slot is inconsistent: {relative}")
            if "slot" in record and (type(record["slot"]) is not int or not 1 <= record["slot"] <= 100):
                raise SystemExit(f"layout diagnostic slot is malformed: {relative}")
            for field in ("element", "pane", "window"):
                frame = record.get(field)
                if not isinstance(frame, list) or len(frame) != 4:
                    raise SystemExit(f"layout diagnostic frame is malformed: {relative}")
                x, y, width, height = frame
                if any(type(value) not in (int, float) or not math.isfinite(value) or abs(value) > 100000 for value in frame):
                    raise SystemExit(f"layout diagnostic frame is non-finite or out of range: {relative}")
                if width < 0 or height < 0:
                    raise SystemExit(f"layout diagnostic frame has negative dimensions: {relative}")
    elif "layout_diagnostics" in data or "layout_diagnostics_truncated" in data:
        raise SystemExit(f"layout diagnostic block is partial: {relative}")
    audit_issues = data.get("audit_issues")
    audit_count = data.get("audit_issue_count")
    audit_truncated = data.get("audit_issues_truncated")
    if not isinstance(audit_issues, list) or len(audit_issues) > 50:
        raise SystemExit(f"audit_issues exceeds its bounded allowlist: {relative}")
    if type(audit_count) is not int or audit_count < len(audit_issues) or type(audit_truncated) is not bool:
        raise SystemExit(f"audit issue metadata is malformed: {relative}")
    if (not audit_truncated and audit_count != len(audit_issues)) or (audit_truncated and (audit_count <= 50 or len(audit_issues) != 50)):
        raise SystemExit(f"audit issue truncation metadata is inconsistent: {relative}")
    for record in audit_issues:
        if not isinstance(record, dict) or set(record) != {"test_identifier", "category", "element_identifier", "element_role"}:
            raise SystemExit(f"audit issue contains non-allowlisted fields: {relative}")
        if not isinstance(record.get("test_identifier"), str) or not test_identifier.fullmatch(record["test_identifier"]):
            raise SystemExit(f"audit issue test identifier is not canonical: {relative}")
        if record.get("category") not in {"contrast", "elementDetection", "hitRegion", "sufficientElementDescription", "action", "parentChild"}:
            raise SystemExit(f"audit issue category is not canonical: {relative}")
        element_identifier = record.get("element_identifier")
        if not isinstance(element_identifier, str) or not re.fullmatch(r"(?:playstead|library)\.[a-z0-9]+(?:[.-][a-z0-9]+)*|unidentified", element_identifier):
            raise SystemExit(f"audit issue element identifier is not allowlisted: {relative}")
        element_role = record.get("element_role")
        if not isinstance(element_role, str) or not re.fullmatch(r"role-(?:[0-9]|[1-7][0-9]|8[0-2])", element_role):
            raise SystemExit(f"audit issue element role is not allowlisted: {relative}")
    required = data.get("required_tests")
    if not isinstance(required, list):
        raise SystemExit(f"required_tests is malformed: {relative}")
    for record in required:
        if not isinstance(record, dict) or set(record) != {"identifier", "discovered", "execution_count", "skipped", "outcome"}:
            raise SystemExit(f"required test record contains non-allowlisted fields: {relative}")
        identifier = record.get("identifier")
        if not isinstance(identifier, str) or len(identifier) > 240 or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.]*/(?:[A-Za-z_][A-Za-z0-9_]*(?:\(\))?|\*)", identifier):
            raise SystemExit(f"required test identifier is not canonical: {relative}")
        if type(record.get("discovered")) is not bool or type(record.get("skipped")) is not bool:
            raise SystemExit(f"required test flags are malformed: {relative}")
        if type(record.get("execution_count")) is not int or record["execution_count"] < 0:
            raise SystemExit(f"required test execution count is malformed: {relative}")
        if record.get("outcome") not in {"passed", "failed", "skipped", "unknown", "missing"}:
            raise SystemExit(f"required test outcome is not allowlisted: {relative}")

def validate_virtual_gamepad_status(data, relative):
    expected = {"schema_version", "lane", "test_identifier", "status", "gate_passed"}
    if not isinstance(data, dict) or set(data) != expected:
        raise SystemExit(f"virtual-gamepad evidence schema is malformed: {relative}")
    if data.get("schema_version") != 1 or data.get("lane") != "virtual_gamepad":
        raise SystemExit(f"virtual-gamepad evidence identity is malformed: {relative}")
    if data.get("test_identifier") != "PlaysteadUITests.ControllerHardwareIntegrationTests/testEntitledVirtualGamepadEnumeratesDetachesAndReconnectsWithoutRelaunch":
        raise SystemExit(f"virtual-gamepad test identity is malformed: {relative}")
    status = data.get("status")
    if status not in {"blocked/not-configured", "pending/configured", "passed", "failed"}:
        raise SystemExit(f"virtual-gamepad status is not allowlisted: {relative}")
    if type(data.get("gate_passed")) is not bool or data["gate_passed"] != (status == "passed"):
        raise SystemExit(f"virtual-gamepad gate status is inconsistent: {relative}")

def validate_save_reliability(data, relative):
    expected = {"schema", "round_trip", "transient", "conflict", "probes"}
    if not isinstance(data, dict) or set(data) != expected:
        raise SystemExit(f"save reliability evidence schema is malformed: {relative}")
    if data.get("schema") != "playstead.save-reliability.v1" or data.get("round_trip") != "passed":
        raise SystemExit(f"save reliability evidence identity is malformed: {relative}")
    transient = data.get("transient")
    if not isinstance(transient, dict) or set(transient) != {
        "http_status", "problem_code", "failure_classification", "failure_cause", "escalates", "correlation_id"
    }:
        raise SystemExit(f"save transient evidence schema is malformed: {relative}")
    if transient.get("http_status") != 503 or transient.get("problem_code") != "service_unavailable":
        raise SystemExit(f"save transient response identity is malformed: {relative}")
    if transient.get("failure_classification") != "none" or transient.get("failure_cause") != "http5xx" or transient.get("escalates") is not False:
        raise SystemExit(f"save transient retry classification is inconsistent: {relative}")
    conflict = data.get("conflict")
    if not isinstance(conflict, dict) or set(conflict) != {
        "original_http_status", "duplicate_http_status", "problem_code", "failure_classification",
        "failure_cause", "escalates", "correlation_id"
    }:
        raise SystemExit(f"save conflict evidence schema is malformed: {relative}")
    if conflict.get("original_http_status") != 201 or conflict.get("duplicate_http_status") != 409:
        raise SystemExit(f"save duplicate response identity is malformed: {relative}")
    if conflict.get("problem_code") != "idempotency_key_conflict" or conflict.get("failure_classification") != "serverRefusal" or conflict.get("failure_cause") != "idempotencyConflict" or conflict.get("escalates") is not True:
        raise SystemExit(f"save conflict escalation classification is inconsistent: {relative}")
    uuid_pattern = r"[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}"
    for record in (transient, conflict):
        if not isinstance(record.get("correlation_id"), str) or not re.fullmatch(uuid_pattern, record["correlation_id"]):
            raise SystemExit(f"save response correlation identifier is malformed: {relative}")
    probes = data.get("probes")
    if not isinstance(probes, dict) or set(probes) != {
        "probe_count", "max_requests_per_second_per_probe", "successful_requests", "last_status", "failed_requests"
    }:
        raise SystemExit(f"save probe evidence schema is malformed: {relative}")
    if probes.get("probe_count") != 4 or probes.get("max_requests_per_second_per_probe") != 2:
        raise SystemExit(f"save probe shape is inconsistent: {relative}")
    for field, minimum in (("successful_requests", 1), ("last_status", 200), ("failed_requests", 0)):
        values = probes.get(field)
        if not isinstance(values, list) or len(values) != 4 or any(type(value) is not int for value in values):
            raise SystemExit(f"save probe {field} is malformed: {relative}")
        if field == "successful_requests" and any(value < minimum for value in values):
            raise SystemExit(f"save probe request counts are invalid: {relative}")
        if field == "last_status" and any(value != minimum for value in values):
            raise SystemExit(f"save probe statuses are not healthy: {relative}")
        if field == "failed_requests" and any(value != minimum for value in values):
            raise SystemExit(f"save probe failures are present: {relative}")

def sanitize_log(raw):
    if any((ord(char) < 32 and char not in "\n\r\t") or ord(char) == 127 for char in raw):
        raise SystemExit("binary control bytes are forbidden in text evidence")
    lines = []
    for line in raw.splitlines():
        if sensitive_text.search(line):
            lines.append("[REDACTED SECRET-BEARING LINE]")
        else:
            lines.append(path_text.sub("[PATH]", line))
    return "\n".join(lines) + ("\n" if raw.endswith("\n") else "")

manifest = []
total = 0
for item in allowed:
    relative = item.relative_to(source)
    if item.is_symlink():
        raise SystemExit(f"symlinked evidence is forbidden: {relative}")
    if any(part in {"DerivedData", ".snapshot-testing"} or part.endswith(".xcresult") for part in relative.parts):
        raise SystemExit(f"raw build material is forbidden: {relative}")
    suffix = item.suffix.lower()
    is_storage_candidate = relative.as_posix() == "storage-candidate/storage-surfaces.actual.png"
    limit = max_storage_candidate if is_storage_candidate else (max_image if suffix == ".png" else max_text)
    size = item.stat().st_size
    if size <= 0 or size > limit:
        raise SystemExit(f"evidence file size is invalid: {relative} ({size} bytes)")
    total += size
    if total > max_total:
        raise SystemExit(f"evidence total exceeds {max_total} bytes")

    destination = output / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    if suffix == ".json":
        try:
            if relative.as_posix() in {"recovery-e2e.json", "recovery-failure.json"}:
                data = json.loads(
                    item.read_text(encoding="utf-8"),
                    object_pairs_hook=reject_duplicate_json_keys,
                )
            else:
                data = json.loads(item.read_text(encoding="utf-8"))
        except Exception:
            if relative.as_posix() in {"recovery-e2e.json", "recovery-failure.json"}:
                raise SystemExit("invalid JSON recovery evidence") from None
            raise SystemExit(f"invalid JSON evidence {relative}") from None
        if relative.name.endswith("-tests.json"):
            if isinstance(data, dict) and data.get("kind") == "static-sweep":
                validate_static_sweep_evidence(data, relative)
            else:
                validate_test_evidence(data, relative)
        if relative.as_posix() == "entitled-gamepad.json":
            validate_virtual_gamepad_status(data, relative)
        if relative.as_posix() == "save-reliability.json":
            validate_save_reliability(data, relative)
        if relative.as_posix() == "recovery-e2e.json":
            validate_recovery_evidence(data, relative)
        if relative.as_posix() == "recovery-failure.json":
            validate_recovery_failure_evidence(data, relative)
        if relative.as_posix() == "continuation.json":
            validate_recovery_evidence(data, relative)
        scan_json(data)
        destination.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    elif suffix == ".txt" or suffix == ".log":
        destination.write_text(sanitize_log(item.read_text(encoding="utf-8")), encoding="utf-8")
    elif suffix == ".png":
        if is_storage_candidate:
            raw = item.read_bytes()
            if raw[:8] != b"\x89PNG\r\n\x1a\n" or raw[12:16] != b"IHDR" or len(raw) < 24:
                raise SystemExit("storage snapshot candidate is not a bounded PNG")
            width = int.from_bytes(raw[16:20], "big")
            height = int.from_bytes(raw[20:24], "big")
            if (width, height) != (5760, 3040):
                raise SystemExit(f"storage snapshot candidate dimensions are invalid: {width}x{height}")
        shutil.copyfile(item, destination)
    else:
        raise SystemExit(f"evidence extension is not allowlisted: {relative}")
    manifest.append({"path": str(relative), "size_bytes": destination.stat().st_size})

for item in output.rglob("*"):
    if not item.is_file() or item.name == "manifest.json":
        continue
    if item.suffix.lower() != ".png":
        raw = item.read_text(encoding="utf-8")
        if sensitive_text.search(raw) or path_text.search(raw):
            raise SystemExit(f"post-sanitization scan failed: {item.relative_to(output)}")

(output / "manifest.json").write_text(json.dumps({
    "schema_version": 1,
    "file_count": len(manifest),
    "total_size_bytes": sum(entry["size_bytes"] for entry in manifest),
    "files": manifest,
}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"staged {len(manifest)} sanitized evidence file(s), {total} input byte(s)")
PY
