#!/usr/bin/env python3
"""Fail-closed validator for allowlisted, digest-bound release evidence."""
from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import date
from pathlib import Path

HEX64 = re.compile(r"^[0-9a-f]{64}$")
FORBIDDEN = re.compile(r"rom|save|owner|credential|token|secret|password|local.?path|filename|raw.?log|private", re.I)
# Approved exceptions are deliberately empty. Entries added here must match
# one exact package@version and finding, explain the review decision, and expire.
APPROVED_EXCEPTIONS: list[dict[str, str]] = []
URL_VALUE = re.compile(r"https?://[^\s\"'<>]+", re.I)
DIAGNOSTIC_KEYS = {
    "$schema", "bomFormat", "specVersion", "version", "metadata", "component",
    "components", "dependencies", "vulnerabilities", "properties", "name", "value",
    "type", "group", "purl", "bom-ref", "scope", "hashes", "externalReferences",
    "url", "reference", "licenses", "license", "id", "expression", "copyright",
    "manufacturer", "supplier", "publisher", "description", "authors", "tools",
    "timestamp", "serialNumber", "evidence", "occurrences", "location", "field",
}
EMBEDDED_LOCAL_PATH = re.compile(
    r"(?:"
    r"(?<![A-Za-z0-9])[A-Za-z]:[\\/][^\s\"'<>]*|"  # Windows drive path
    r"(?<!\S)(?:\\\\|//)[^\\/\s]+[\\/][^\s\"'<>]*|"  # UNC path
    r"(?<![A-Za-z0-9])/(?:[^\s/\\<>\"']+/)*[^\s/\\<>\"']+|"  # POSIX absolute path
    r"(?<![A-Za-z0-9])\.\.(?:[/\\]|$)"  # parent traversal component
    r")"
)


def fail(message: str) -> None:
    raise ValueError(message)


def is_json_integer(value) -> bool:
    """Accept JSON integers while excluding Python's bool subclass."""
    return type(value) is int


def load(path: str | Path) -> dict:
    try:
        value = json.loads(Path(path).read_text())
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"invalid or missing JSON: {path}: {exc}")
    if not isinstance(value, dict):
        fail(f"expected object: {path}")
    return value


def clean(value, key="", path=()):
    location = "$" + "".join(
        f".{part}" if isinstance(part, str) else f"[{part}]"
        for part in path
    )
    if FORBIDDEN.search(key):
        fail(f"forbidden evidence field at {location}")
    if re.search(r"(?:^|[_-])(?:file)?path$|filename", key, re.I):
        fail(f"path-bearing evidence field at {location}")
    if isinstance(value, dict):
        if key == "properties" and isinstance(value.get("name"), str):
            property_name = value["name"]
            if FORBIDDEN.search(property_name) or re.search(
                r"(?:^|[_-])(?:file)?path$|filename", property_name, re.I
            ):
                fail(f"forbidden CycloneDX property at {location}.name")
        return {
            k: clean(v, k, (*path, k if k in DIAGNOSTIC_KEYS else "<field>"))
            for k, v in value.items()
        }
    if isinstance(value, list):
        return [clean(item, key, (*path, index)) for index, item in enumerate(value)]
    if isinstance(value, str):
        without_urls = URL_VALUE.sub("", value)
        if EMBEDDED_LOCAL_PATH.search(without_urls) or "PRIVATE_EVIDENCE_SENTINEL" in value:
            fail(f"private path or sentinel in evidence at {location}")
    return value


def validate_cyclonedx(document: dict) -> int:
    if not isinstance(document, dict):
        fail("CycloneDX SBOM must be a JSON object")
    clean(document)
    components = document.get("components")
    if document.get("bomFormat") != "CycloneDX" or document.get("specVersion") not in {"1.4", "1.5", "1.6", "1.7"}:
        fail("malformed or unsupported CycloneDX document")
    if not is_json_integer(document.get("version")) or document["version"] < 1:
        fail("CycloneDX document version is missing")
    if not isinstance(components, list) or not components:
        fail("missing or empty CycloneDX components")
    for component in components:
        if not isinstance(component, dict) or not isinstance(component.get("type"), str) or not isinstance(component.get("name"), str) or not component["name"]:
            fail("malformed CycloneDX component")
    return len(components)


def summarize_trivy(report: dict, subject_sha256: str, image_id: str | None = None) -> dict:
    if not isinstance(report.get("Results"), list) or not report["Results"]:
        fail("scanner discovered zero targets")
    today = date.today()
    exceptions = {}
    for item in APPROVED_EXCEPTIONS:
        if not isinstance(item, dict) or set(item) != {"package", "finding", "reason", "expires"}:
            fail("exceptions require package, finding, reason, and expiry")
        if "@" not in item["package"] or not item["finding"] or len(item["reason"].strip()) < 12:
            fail("exception lacks exact package identity, finding, or review reason")
        try:
            expiry = date.fromisoformat(item["expires"])
        except (TypeError, ValueError):
            fail("exception expiry must be an ISO date")
        if expiry < today:
            fail(f"expired exception for {item['package']} {item['finding']}")
        exceptions[(item["package"], item["finding"])] = True
    if image_id and report.get("Metadata", {}).get("ImageID") != image_id:
        fail("Trivy scanned an image other than the smoke-tested image ID")
    high_critical = 0
    prohibited = 0
    for result in report["Results"]:
        for vulnerability in result.get("Vulnerabilities") or []:
            if vulnerability.get("Severity") not in {"HIGH", "CRITICAL"}:
                continue
            package = f"{vulnerability.get('PkgName', '')}@{vulnerability.get('InstalledVersion', '')}"
            if not exceptions.get((package, vulnerability.get("VulnerabilityID"))):
                high_critical += 1
        for license_finding in result.get("Licenses") or []:
            if license_finding.get("Severity") not in {"HIGH", "CRITICAL"}:
                continue
            package = f"{license_finding.get('PkgName', '')}@{license_finding.get('PkgVersion', '')}"
            if not exceptions.get((package, license_finding.get("Name"))):
                prohibited += 1
    return {
        "status": "passed" if high_critical == 0 and prohibited == 0 else "failed",
        "subject_sha256": subject_sha256,
        "targets_discovered": len(report["Results"]),
        "high_critical": high_critical,
        "license_policy": "passed" if prohibited == 0 else "failed",
        "prohibited_licenses": prohibited,
    }


def validate(data: dict) -> dict:
    allowed = {"schema_version", "mode", "subject", "scans", "sbom", "parser_inventory", "attestations", "handoff"}
    if set(data) != allowed:
        fail(f"evidence fields must be exactly {sorted(allowed)}")
    clean(data)
    if not is_json_integer(data["schema_version"]) or data["schema_version"] != 1:
        fail("unsupported schema_version")
    subject = data["subject"]
    if not isinstance(subject, dict) or set(subject) != {"archive_sha256", "image_id"}:
        fail("invalid subject")
    digest = subject["archive_sha256"]
    if not isinstance(digest, str) or not HEX64.fullmatch(digest):
        fail("invalid archive SHA-256")
    if not isinstance(subject["image_id"], str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", subject["image_id"]):
        fail("invalid image identity")
    if not isinstance(data["scans"], dict) or set(data["scans"]) != {"source", "image"}:
        fail("source and image scans are required")
    for name, report in data["scans"].items():
        if set(report) != {"status", "subject_sha256", "targets_discovered", "high_critical", "license_policy", "prohibited_licenses"}:
            fail(f"invalid {name} scan")
        if report["status"] != "passed" or report["subject_sha256"] != digest or not is_json_integer(report["targets_discovered"]) or report["targets_discovered"] < 1:
            fail(f"{name} scan failed or subject digest differs")
        if report["license_policy"] != "passed" or not is_json_integer(report["prohibited_licenses"]) or report["prohibited_licenses"] != 0:
            fail(f"{name} license policy failed")
        if not is_json_integer(report["high_critical"]) or report["high_critical"] < 0:
            fail(f"invalid {name} vulnerability count")
        if report["high_critical"] != 0:
            fail(f"{name} has unresolved high or critical vulnerabilities")
    sbom = data["sbom"]
    if not isinstance(sbom, dict) or set(sbom) != {"format", "status", "subject_sha256", "components"}:
        fail("invalid SBOM record")
    if sbom["format"] != "CycloneDX" or sbom["status"] != "passed" or sbom["subject_sha256"] != digest or not is_json_integer(sbom["components"]) or sbom["components"] < 1:
        fail("missing, empty, or mismatched CycloneDX SBOM")
    inventory = data["parser_inventory"]
    if not isinstance(inventory, dict) or set(inventory) != {"status", "subject_sha256", "discovered", "mapped", "tests_discovered", "tests_passed", "parsers"}:
        fail("invalid parser inventory")
    count_fields = ("discovered", "mapped", "tests_discovered", "tests_passed")
    if any(not is_json_integer(inventory[field]) for field in count_fields):
        fail("parser inventory counts must be integers")
    if inventory["status"] != "passed" or inventory["subject_sha256"] != digest or inventory["discovered"] < 1 or inventory["discovered"] != inventory["mapped"] or inventory["tests_discovered"] < 1 or inventory["tests_discovered"] != inventory["tests_passed"]:
        fail("parser inventory incomplete or not digest-bound")
    parsers = inventory["parsers"]
    if not isinstance(parsers, list) or len(parsers) != inventory["discovered"]:
        fail("parser inventory must enumerate every discovered parser")
    parser_ids = set()
    for entry in parsers:
        if not isinstance(entry, dict) or set(entry) != {"id", "category", "test_file", "test_identity", "result"}:
            fail("invalid parser inventory entry")
        if not all(isinstance(entry[key], str) and entry[key] for key in entry):
            fail("empty parser inventory entry")
        if entry["result"] != "passed" or entry["id"] in parser_ids or entry["test_file"].startswith(("/", "..")):
            fail("failed, duplicate, or path-leaking parser inventory entry")
        parser_ids.add(entry["id"])
    attest = data["attestations"]
    if not isinstance(attest, dict) or set(attest) != {"provenance", "sbom"}:
        fail("attestation records are required")
    for name, record in attest.items():
        if not isinstance(record, dict) or set(record) != {"status", "subject_sha256"}:
            fail(f"invalid {name} attestation")
        expected = "verified" if data["mode"] == "release" else "not-issued"
        if record["status"] != expected or (expected == "verified" and record["subject_sha256"] != digest):
            fail(f"{name} attestation does not match mode and subject")
        if expected == "not-issued" and record["subject_sha256"] is not None:
            fail("PR evidence must not claim an attestation")
    if data["mode"] not in {"pull-request", "release"}:
        fail("invalid mode")
    handoff = data["handoff"]
    if handoff != {"consumer": "Phase 05 D-11", "subject_sha256": digest, "retained_gates": ["D-07", "D-13"]}:
        fail("invalid downstream handoff")
    result = dict(data)
    result["verdict"] = "release-ready" if data["mode"] == "release" else "diagnostic-only"
    return result


def verify_attestation_reports(evidence_path: str, provenance_path: str, sbom_path: str, output_path: str) -> None:
    evidence = load(evidence_path)
    subject = evidence.get("subject")
    if not isinstance(subject, dict):
        fail("invalid evidence subject before attestation verification")
    digest = subject.get("archive_sha256")
    if not isinstance(digest, str) or not HEX64.fullmatch(digest):
        fail("invalid evidence subject before attestation verification")
    for name, path, predicate in (
        ("provenance", provenance_path, "https://slsa.dev/provenance/v1"),
        ("sbom", sbom_path, "https://cyclonedx.org/bom"),
    ):
        try:
            records = json.loads(Path(path).read_text())
        except (OSError, json.JSONDecodeError) as exc:
            fail(f"invalid or missing attestation JSON: {path}: {exc}")
        if not isinstance(records, list) or not records:
            fail(f"missing verified {name} attestation")
        matching = False
        for record in records:
            if not isinstance(record, dict):
                fail(f"malformed verified {name} attestation report")
            result = record.get("verificationResult")
            if not isinstance(result, dict):
                fail(f"malformed verified {name} attestation report")
            statement = result.get("statement")
            if not isinstance(statement, dict):
                fail(f"malformed verified {name} attestation report")
            if statement.get("predicateType") != predicate:
                continue
            subjects = statement.get("subject")
            if not isinstance(subjects, list):
                fail(f"malformed verified {name} attestation report")
            for item in subjects:
                if not isinstance(item, dict) or not isinstance(item.get("digest"), dict):
                    fail(f"malformed verified {name} attestation report")
            if any(item["digest"].get("sha256") == digest for item in subjects):
                matching = True
        if not matching:
            fail(f"verified {name} attestation has no matching archive subject")
    evidence["mode"] = "release"
    evidence["attestations"] = {
        name: {"status": "verified", "subject_sha256": digest}
        for name in ("provenance", "sbom")
    }
    checked = validate(evidence)
    Path(output_path).write_text(json.dumps(checked, sort_keys=True, separators=(",", ":")) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input")
    parser.add_argument("--output")
    parser.add_argument("--provenance")
    parser.add_argument("--sbom")
    args = parser.parse_args()
    try:
        if args.provenance or args.sbom:
            if not all((args.input, args.provenance, args.sbom, args.output)):
                fail("--input, --provenance, --sbom, and --output are required together")
            verify_attestation_reports(args.input, args.provenance, args.sbom, args.output)
            return 0
        if not args.input:
            fail("--input is required")
        checked = validate(load(args.input))
        encoded = json.dumps(checked, sort_keys=True, separators=(",", ":")) + "\n"
        clean(checked)
        if args.output:
            Path(args.output).write_text(encoded)
        else:
            sys.stdout.write(encoded)
        return 0
    except (ValueError, TypeError, KeyError) as exc:
        print(f"release evidence rejected: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
