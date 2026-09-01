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

source = pathlib.Path(sys.argv[1]).resolve()
output = pathlib.Path(sys.argv[2]).resolve()
mac_root = pathlib.Path(sys.argv[3]).resolve()
max_files = 40
max_total = 12 * 1024 * 1024
max_text = 256 * 1024
max_image = 2 * 1024 * 1024
max_storage_candidate = 8 * 1024 * 1024

allowed = []
for name in ("environment-fingerprint.json", "layers.json"):
    candidate = source / name
    if candidate.is_file():
        allowed.append(candidate)
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

allowed = list(dict.fromkeys(allowed))
if not allowed:
    raise SystemExit("no allowlisted evidence files were found")
if len(allowed) > max_files:
    raise SystemExit(f"evidence file count exceeds {max_files}")

sensitive_keys = {
    "authorization", "credential", "credentials", "token", "database_url",
    "raw_log", "keychain_path", "handoff", "environment", "env",
}
sensitive_text = re.compile(
    r"(?i)(authorization\s*[:=]|bearer\s+[A-Za-z0-9._~+/=-]+|"
    r"database_url\s*=|secret_key_base\s*=|\.keychain(?:-db)?\b|"
    r"(?:^|[/\\])\.env(?:\b|[/\\])|credential[-_ ]?handoff|"
    r"(?:^|[/\\])(?:objects|partials)(?:[/\\]|$)|"
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

def validate_test_evidence(data, relative):
    allowed_keys = {
        "schema_version", "layer", "executed_test_count", "required_tests",
        "failed_test_count", "failed_tests_truncated", "failed_tests",
        "failure_diagnostic_count", "failure_diagnostics_truncated", "failure_diagnostics",
        "audit_issue_count", "audit_issues_truncated", "audit_issues",
    }
    legacy_keys = allowed_keys - {
        "failure_diagnostic_count", "failure_diagnostics_truncated", "failure_diagnostics"
    }
    actual_keys = set(data) if isinstance(data, dict) else set()
    if not isinstance(data, dict) or (actual_keys != allowed_keys and actual_keys != legacy_keys):
        raise SystemExit(f"test evidence has unexpected schema: {relative}")
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
        if not isinstance(record, dict) or set(record) != {"test_identifier", "assertion", "source_file", "source_line"}:
            raise SystemExit(f"failure diagnostic contains non-allowlisted fields: {relative}")
        if not isinstance(record.get("test_identifier"), str) or not test_identifier.fullmatch(record["test_identifier"]):
            raise SystemExit(f"failure diagnostic test identifier is not canonical: {relative}")
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
        if not isinstance(identifier, str) or len(identifier) > 240 or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.]*/[A-Za-z_][A-Za-z0-9_]*(?:\(\))?", identifier):
            raise SystemExit(f"required test identifier is not canonical: {relative}")
        if type(record.get("discovered")) is not bool or type(record.get("skipped")) is not bool:
            raise SystemExit(f"required test flags are malformed: {relative}")
        if type(record.get("execution_count")) is not int or record["execution_count"] < 0:
            raise SystemExit(f"required test execution count is malformed: {relative}")
        if record.get("outcome") not in {"passed", "failed", "skipped", "unknown", "missing"}:
            raise SystemExit(f"required test outcome is not allowlisted: {relative}")

def sanitize_log(raw):
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
            data = json.loads(item.read_text(encoding="utf-8"))
        except Exception as exc:
            raise SystemExit(f"invalid JSON evidence {relative}: {exc}")
        if relative.name.endswith("-tests.json"):
            validate_test_evidence(data, relative)
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
