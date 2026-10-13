#!/usr/bin/env python3
"""Bind only sanitizer-approved Virtual HID JSON to its GitHub Actions run."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import stat
import sys


ENVIRONMENT_FIELDS = (
    "GITHUB_REPOSITORY",
    "GITHUB_WORKFLOW",
    "GITHUB_EVENT_NAME",
    "GITHUB_REF",
    "GITHUB_SHA",
    "GITHUB_RUN_ID",
)
MAX_FILE_BYTES = 256 * 1024
MAX_TOTAL_BYTES = 512 * 1024
EXPECTED_FILES = {"entitled-gamepad.json", "ui-tests.json"}
SANITIZER_MANIFEST = "manifest.json"
ENTITLED_TEST_FULL = (
    "PlaysteadUITests.ControllerHardwareIntegrationTests/"
    "testEntitledVirtualGamepadEnumeratesDetachesAndReconnectsWithoutRelaunch"
)
ENTITLED_TEST_SELECTOR = (
    "ControllerHardwareIntegrationTests/"
    "testEntitledVirtualGamepadEnumeratesDetachesAndReconnectsWithoutRelaunch"
)
UI_KEYS = {
    "schema_version", "layer", "executed_test_count", "runner_process_error_count",
    "required_tests", "failed_test_count", "failed_tests_truncated", "failed_tests",
    "failure_diagnostic_count", "failure_diagnostics_truncated", "failure_diagnostics",
    "layout_diagnostic_count", "layout_diagnostics_truncated", "layout_diagnostics",
    "audit_issue_count", "audit_issues_truncated", "audit_issues",
    "in_test_seconds_total", "timed_test_count", "slowest_tests",
}
UI_REQUIRED_KEYS = {
    "schema_version", "layer", "executed_test_count", "required_tests",
    "failed_test_count", "failed_tests_truncated", "failed_tests",
    "failure_diagnostic_count", "failure_diagnostics_truncated", "failure_diagnostics",
    "layout_diagnostic_count", "layout_diagnostics_truncated", "layout_diagnostics",
    "audit_issue_count", "audit_issues_truncated", "audit_issues",
}
FORBIDDEN_KEYS = {"authorization", "credential", "token", "database_url", "raw_log", "keychain_path"}


def fail(message: str) -> "NoReturn":
    raise SystemExit(message)


def reject_duplicate_keys(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def read_bounded_json(path: pathlib.Path) -> tuple[bytes, object]:
    if path.is_symlink() or not path.is_file():
        fail(f"sanitized evidence file is not a regular file: {path.name}")
    size = path.stat().st_size
    if not 0 < size <= MAX_FILE_BYTES:
        fail(f"sanitized evidence file size is invalid: {path.name}")
    raw = path.read_bytes()
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=reject_duplicate_keys)
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError):
        fail(f"sanitized evidence JSON is malformed: {path.name}")
    return raw, value


def validate_json_tree(value: object, depth: int = 0) -> None:
    if depth > 8:
        fail("sanitized evidence nesting exceeds its limit")
    if isinstance(value, dict):
        if any(not isinstance(key, str) or key.lower() in FORBIDDEN_KEYS for key in value):
            fail("sanitized evidence contains a forbidden field")
        if len(value) > 100:
            fail("sanitized evidence object exceeds its field limit")
        for child in value.values():
            validate_json_tree(child, depth + 1)
    elif isinstance(value, list):
        if len(value) > 100:
            fail("sanitized evidence array exceeds its item limit")
        for child in value:
            validate_json_tree(child, depth + 1)
    elif isinstance(value, str):
        if len(value) > 512 or any(ord(character) < 0x20 and character not in "\t\n\r" for character in value):
            fail("sanitized evidence text exceeds its limit")
    elif value is not None and type(value) not in {bool, int, float}:
        fail("sanitized evidence contains an unsupported value")


def validate_gamepad(data: object) -> None:
    expected = {"schema_version", "lane", "test_identifier", "status", "gate_passed"}
    if not isinstance(data, dict) or set(data) != expected:
        fail("entitled gamepad evidence schema is not allowlisted")
    if data.get("schema_version") != 1 or data.get("lane") != "virtual_gamepad":
        fail("entitled gamepad evidence identity is invalid")
    if data.get("test_identifier") != ENTITLED_TEST_FULL:
        fail("entitled gamepad test identity is invalid")
    if data.get("status") not in {"blocked/not-configured", "pending/configured", "passed", "failed"}:
        fail("entitled gamepad status is invalid")
    if type(data.get("gate_passed")) is not bool or data["gate_passed"] != (data["status"] == "passed"):
        fail("entitled gamepad gate status is inconsistent")


def validate_ui_tests(data: object) -> None:
    if not isinstance(data, dict) or not UI_REQUIRED_KEYS <= set(data) or not set(data) <= UI_KEYS:
        fail("UI test evidence schema is not allowlisted")
    if data.get("schema_version") != 1 or data.get("layer") != "ui":
        fail("UI test evidence identity is invalid")
    required = data.get("required_tests")
    if not isinstance(required, list) or len(required) != 1:
        fail("UI test evidence must contain exactly one required test")
    record = required[0]
    if not isinstance(record, dict) or set(record) != {"identifier", "discovered", "execution_count", "skipped", "outcome"}:
        fail("required UI test record is not allowlisted")
    if record.get("identifier") != ENTITLED_TEST_SELECTOR + "()":
        fail("required UI test identity is invalid")
    if type(record.get("discovered")) is not bool or type(record.get("skipped")) is not bool:
        fail("required UI test discovery flags are invalid")
    if type(record.get("execution_count")) is not int or record["execution_count"] < 0:
        fail("required UI test execution count is invalid")
    if record.get("outcome") not in {"passed", "failed", "skipped", "unknown", "missing"}:
        fail("required UI test outcome is invalid")


def validate_sanitizer_manifest(data: object, expected_sizes: dict[str, int]) -> None:
    expected_keys = {"schema_version", "file_count", "total_size_bytes", "files"}
    if not isinstance(data, dict) or set(data) != expected_keys or data.get("schema_version") != 1:
        fail("sanitizer manifest schema is invalid")
    files = data.get("files")
    if not isinstance(files, list) or len(files) != len(EXPECTED_FILES):
        fail("sanitizer manifest file list is invalid")
    observed: dict[str, int] = {}
    for record in files:
        if not isinstance(record, dict) or set(record) != {"path", "size_bytes"}:
            fail("sanitizer manifest record is not allowlisted")
        name = record.get("path")
        size = record.get("size_bytes")
        if not isinstance(name, str) or name not in EXPECTED_FILES or type(size) is not int or size <= 0 or name in observed:
            fail("sanitizer manifest file identity is invalid")
        observed[name] = size
    if observed != expected_sizes:
        fail("sanitizer manifest sizes do not match the sanitized evidence")
    if type(data.get("file_count")) is not int or data["file_count"] != len(EXPECTED_FILES):
        fail("sanitizer manifest file count is inconsistent")
    if type(data.get("total_size_bytes")) is not int or data["total_size_bytes"] != sum(expected_sizes.values()):
        fail("sanitizer manifest total size is inconsistent")


def run_identity() -> dict[str, str]:
    values = {field: os.environ.get(field, "") for field in ENVIRONMENT_FIELDS}
    if any(not value or len(value) > 256 or "\n" in value or "\r" in value for value in values.values()):
        fail("GitHub run identity is incomplete or malformed")
    if values["GITHUB_REPOSITORY"] != "szTheory/playstead":
        fail("GitHub repository identity is not the Playstead repository")
    if values["GITHUB_EVENT_NAME"] != "workflow_dispatch" or values["GITHUB_REF"] != "refs/heads/main":
        fail("Virtual HID evidence requires a protected-main workflow dispatch")
    if not re.fullmatch(r"[0-9a-fA-F]{40,64}", values["GITHUB_SHA"]):
        fail("GitHub commit identity is malformed")
    if not re.fullmatch(r"[0-9]{1,20}", values["GITHUB_RUN_ID"]):
        fail("GitHub run identity is malformed")
    values["GITHUB_SHA"] = values["GITHUB_SHA"].lower()
    return {
        "repository": values["GITHUB_REPOSITORY"],
        "workflow": values["GITHUB_WORKFLOW"],
        "event": values["GITHUB_EVENT_NAME"],
        "ref": values["GITHUB_REF"],
        "sha": values["GITHUB_SHA"],
        "run_id": values["GITHUB_RUN_ID"],
    }


def build_manifest(directory: pathlib.Path) -> dict[str, object]:
    if directory.is_symlink() or not directory.is_dir():
        fail("sanitized evidence directory is unavailable")
    entries = {entry.name for entry in directory.iterdir()}
    if entries != EXPECTED_FILES | {SANITIZER_MANIFEST}:
        fail("sanitized evidence directory contains missing or non-allowlisted files")
    records: dict[str, dict[str, object]] = {}
    expected_sizes: dict[str, int] = {}
    total = 0
    for name in sorted(EXPECTED_FILES):
        path = directory / name
        raw, data = read_bounded_json(path)
        validate_json_tree(data)
        if name == "entitled-gamepad.json":
            validate_gamepad(data)
        else:
            validate_ui_tests(data)
        total += len(raw)
        if total > MAX_TOTAL_BYTES:
            fail("sanitized evidence exceeds the total size limit")
        expected_sizes[name] = len(raw)
        records[name] = {"bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()}
    sanitizer_path = directory / SANITIZER_MANIFEST
    sanitizer_raw, sanitizer_data = read_bounded_json(sanitizer_path)
    validate_json_tree(sanitizer_data)
    validate_sanitizer_manifest(sanitizer_data, expected_sizes)
    if len(sanitizer_raw) > MAX_FILE_BYTES:
        fail("sanitizer manifest exceeds its size limit")
    return {
        "schema_version": 1,
        "source": "github-hosted",
        "run": run_identity(),
        "files": records,
        "total_bytes": total,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sanitized-dir", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    arguments = parser.parse_args()
    output = arguments.output
    directory = arguments.sanitized_dir
    if output.parent.resolve() != directory.resolve() or output.name != "virtual-hid-manifest.json":
        fail("manifest output must be the named file inside the sanitized directory")
    manifest = build_manifest(directory)
    temporary = output.with_name(output.name + ".tmp")
    temporary.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.chmod(temporary, stat.S_IRUSR | stat.S_IWUSR)
    temporary.replace(output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SystemExit:
        raise
    except Exception:
        print("Virtual HID evidence could not be validated", file=sys.stderr)
        raise SystemExit(1)
