#!/usr/bin/env python3
"""Create and validate scan receipts for the isolated media-decoder image."""

from __future__ import annotations

import argparse
import datetime
import hashlib
import importlib.util
import json
import pathlib
import re
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
TRIVY_VERSION = "Trivy 0.75.0"
RECEIPT_FIELDS = {
    "schema_version", "source_sha256", "image_id", "scanner",
    "scan_report_sha256", "scanned_at", "scan",
}


def _release_evidence():
    spec = importlib.util.spec_from_file_location("release_evidence", ROOT / "scripts/ci/release-evidence.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def source_digest(context: pathlib.Path) -> str:
    digest = hashlib.sha256()
    ignored_roots = set()
    dockerignore = context / ".dockerignore"
    if dockerignore.is_file():
        ignored_roots = {
            line.strip().strip("/") for line in dockerignore.read_text().splitlines()
            if line.strip() and not line.lstrip().startswith("#") and not any(ch in line for ch in "*!?")
        }
    files = []
    for item in context.rglob("*"):
        relative_path = item.relative_to(context)
        if item.is_file() and relative_path.parts[0] not in ignored_roots:
            files.append((item, relative_path.as_posix()))
    for path, relative_name in sorted(files, key=lambda pair: pair[1]):
        relative = relative_name.encode()
        digest.update(relative + b"\0")
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def _read_report(path: pathlib.Path, expected_sha256: str, expected_image_id: str) -> tuple[dict, dict]:
    if not re.fullmatch(r"[0-9a-f]{64}", expected_sha256):
        raise ValueError("invalid decoder source SHA-256")
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", expected_image_id):
        raise ValueError("invalid decoder image ID")
    raw_bytes = path.read_bytes()
    report = json.loads(raw_bytes)
    summary = _release_evidence().summarize_trivy(report, expected_sha256, expected_image_id)
    # A successful target scan is not sufficient: images with no package
    # inventory can otherwise appear clean simply because the scanner saw no
    # attributable runtime components. Require identified OS package/version,
    # source lineage and license identities in Trivy's image inventory before
    # issuing or validating a receipt.
    identities = {
        (package.get("Name"), package.get("Version"))
        for result in report["Results"]
        for package in (result.get("Packages") or [])
        if isinstance(package, dict)
        and isinstance(package.get("Name"), str) and package["Name"]
        and isinstance(package.get("Version"), str) and package["Version"]
        and isinstance(package.get("SrcName"), str) and package["SrcName"]
        and isinstance(package.get("SrcVersion"), str) and package["SrcVersion"]
        and isinstance(package.get("Licenses"), list) and package["Licenses"]
    }
    if not identities:
        raise ValueError("Trivy discovered no versioned runtime package inventory with source and license identities")
    for result in report["Results"]:
        for package in (result.get("Packages") or []):
            if not isinstance(package, dict) or not package.get("Name") or not package.get("Version"):
                continue
            if not package.get("SrcName") or not package.get("SrcVersion") or not package.get("Licenses"):
                raise ValueError(f"runtime package lacks source or license evidence: {package.get('Name')}@{package.get('Version')}")
    summary["runtime_packages"] = len(identities)
    return report, {**summary, "report_sha256": hashlib.sha256(raw_bytes).hexdigest()}


def create_receipt(report_path: pathlib.Path, output_dir: pathlib.Path, source_sha256: str, image_id: str) -> dict:
    _, scan = _read_report(report_path, source_sha256, image_id)
    output_dir.mkdir(parents=True, exist_ok=True)
    report_copy = output_dir / "decoder-trivy.json"
    if report_path.resolve() != report_copy.resolve():
        shutil.copyfile(report_path, report_copy)
    scanned_at = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
    report_sha256 = scan["report_sha256"]
    scan_result = {
        "schema_version": 1,
        "source_sha256": source_sha256,
        "image_id": image_id,
        "scanner": TRIVY_VERSION,
        "scan_report_sha256": report_sha256,
        "scanned_at": scanned_at,
        "scan": {key: value for key, value in scan.items() if key != "report_sha256"},
    }
    (output_dir / "decoder-scan-result.json").write_text(json.dumps(scan_result, sort_keys=True, separators=(",", ":")) + "\n")
    if scan["status"] != "passed" or scan["license_policy"] != "passed":
        raise ValueError(f"decoder image scan failed policy: {scan}")
    receipt = dict(scan_result)
    receipt.pop("scan_report_sha256")
    receipt["scan_report_sha256"] = report_sha256
    (output_dir / "decoder-scan-receipt.json").write_text(json.dumps(receipt, sort_keys=True, separators=(",", ":")) + "\n")
    (output_dir / "decoder-compose.env").write_text(f"PLAYSTEAD_MEDIA_DECODER_IMAGE={image_id}\n")
    return receipt


def verify_receipt(receipt_path: pathlib.Path, report_path: pathlib.Path, context: pathlib.Path, actual_image_id: str) -> dict:
    receipt = json.loads(receipt_path.read_text())
    if not isinstance(receipt, dict) or set(receipt) != RECEIPT_FIELDS or receipt.get("schema_version") != 1:
        raise ValueError("decoder scan receipt has an unsupported shape")
    current_source = source_digest(context)
    if receipt["source_sha256"] != current_source:
        raise ValueError("decoder scan receipt source does not match current build context")
    if receipt["image_id"] != actual_image_id:
        raise ValueError("decoder scan receipt image ID does not match the actual local image")
    if receipt["scanner"] != TRIVY_VERSION:
        raise ValueError("decoder scan receipt uses an unapproved scanner")
    report_digest = hashlib.sha256(report_path.read_bytes()).hexdigest()
    if receipt["scan_report_sha256"] != report_digest:
        raise ValueError("decoder scan receipt does not match its exact Trivy report")
    _, scan = _read_report(report_path, receipt["source_sha256"], actual_image_id)
    expected_scan = {key: value for key, value in scan.items() if key != "report_sha256"}
    if receipt["scan_report_sha256"] != scan["report_sha256"] or receipt["scan"] != expected_scan:
        raise ValueError("decoder scan receipt does not match its exact Trivy report")
    if scan["status"] != "passed" or scan["license_policy"] != "passed":
        raise ValueError("decoder scan policy is not passing")
    return receipt


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    hash_context = subparsers.add_parser("hash")
    hash_context.add_argument("--context", type=pathlib.Path, required=True)
    create = subparsers.add_parser("create")
    create.add_argument("--report", type=pathlib.Path, required=True)
    create.add_argument("--output", type=pathlib.Path, required=True)
    create.add_argument("--source-sha256", required=True)
    create.add_argument("--image-id", required=True)
    verify = subparsers.add_parser("verify")
    verify.add_argument("--receipt", type=pathlib.Path, required=True)
    verify.add_argument("--report", type=pathlib.Path, required=True)
    verify.add_argument("--context", type=pathlib.Path, required=True)
    verify.add_argument("--image-id", required=True)
    args = parser.parse_args()
    try:
        if args.command == "hash":
            print(source_digest(args.context))
        elif args.command == "create":
            receipt = create_receipt(args.report, args.output, args.source_sha256, args.image_id)
            print(json.dumps({"image_id": receipt["image_id"], "source_sha256": receipt["source_sha256"], "scan": receipt["scan"]}, sort_keys=True))
        else:
            receipt = verify_receipt(args.receipt, args.report, args.context, args.image_id)
            print(receipt["image_id"])
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"decoder_evidence_invalid: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
