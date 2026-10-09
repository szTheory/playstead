#!/usr/bin/env python3
"""Fail-closed validator for allowlisted, digest-bound release evidence."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

HEX64 = re.compile(r"^[0-9a-f]{64}$")
FORBIDDEN = re.compile(r"rom|save|owner|credential|token|secret|password|local.?path|filename|raw.?log|private", re.I)


def fail(message: str) -> None:
    raise ValueError(message)


def load(path: str | Path) -> dict:
    try:
        value = json.loads(Path(path).read_text())
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"invalid or missing JSON: {path}: {exc}")
    if not isinstance(value, dict):
        fail(f"expected object: {path}")
    return value


def clean(value, key=""):
    if FORBIDDEN.search(key):
        fail(f"forbidden evidence field: {key}")
    if isinstance(value, dict):
        return {k: clean(v, k) for k, v in value.items()}
    if isinstance(value, list):
        return [clean(item, key) for item in value]
    if isinstance(value, str):
        if value.startswith(("/Users/", "/home/", "C:\\")) or "PRIVATE_EVIDENCE_SENTINEL" in value:
            fail("private path or sentinel in evidence")
    return value


def validate(data: dict) -> dict:
    allowed = {"schema_version", "mode", "subject", "scans", "sbom", "parser_inventory", "attestations", "handoff"}
    if set(data) != allowed:
        fail(f"evidence fields must be exactly {sorted(allowed)}")
    clean(data)
    if data["schema_version"] != 1:
        fail("unsupported schema_version")
    subject = data["subject"]
    if not isinstance(subject, dict) or set(subject) != {"archive_sha256", "image_id"}:
        fail("invalid subject")
    digest = subject["archive_sha256"]
    if not isinstance(digest, str) or not HEX64.fullmatch(digest):
        fail("invalid archive SHA-256")
    if not isinstance(subject["image_id"], str) or not subject["image_id"].startswith("sha256:"):
        fail("invalid image identity")
    if not isinstance(data["scans"], dict) or set(data["scans"]) != {"source", "image"}:
        fail("source and image scans are required")
    for name, report in data["scans"].items():
        if set(report) != {"status", "subject_sha256", "high_critical", "license_policy", "prohibited_licenses"}:
            fail(f"invalid {name} scan")
        if report["status"] != "passed" or report["subject_sha256"] != digest:
            fail(f"{name} scan failed or subject digest differs")
        if report["license_policy"] != "passed" or report["prohibited_licenses"] != 0:
            fail(f"{name} license policy failed")
        if not isinstance(report["high_critical"], int) or report["high_critical"] < 0:
            fail(f"invalid {name} vulnerability count")
    sbom = data["sbom"]
    if not isinstance(sbom, dict) or set(sbom) != {"format", "status", "subject_sha256", "components"}:
        fail("invalid SBOM record")
    if sbom["format"] != "CycloneDX" or sbom["status"] != "passed" or sbom["subject_sha256"] != digest or not isinstance(sbom["components"], int) or sbom["components"] < 1:
        fail("missing, empty, or mismatched CycloneDX SBOM")
    inventory = data["parser_inventory"]
    if not isinstance(inventory, dict) or set(inventory) != {"status", "subject_sha256", "discovered", "mapped", "tests_discovered", "tests_passed"}:
        fail("invalid parser inventory")
    if inventory["status"] != "passed" or inventory["subject_sha256"] != digest or inventory["discovered"] < 1 or inventory["discovered"] != inventory["mapped"] or inventory["tests_discovered"] < 1 or inventory["tests_discovered"] != inventory["tests_passed"]:
        fail("parser inventory incomplete or not digest-bound")
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
    digest = evidence.get("subject", {}).get("archive_sha256")
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
            result = record.get("verificationResult", {}) if isinstance(record, dict) else {}
            statement = result.get("statement", {})
            if statement.get("predicateType") != predicate:
                continue
            subjects = statement.get("subject")
            if isinstance(subjects, list) and any(
                isinstance(item, dict) and item.get("digest", {}).get("sha256") == digest
                for item in subjects
            ):
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
