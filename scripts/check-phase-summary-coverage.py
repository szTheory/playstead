#!/usr/bin/env python3
"""Fail closed when a phase SUMMARY coverage block is not machine-classifiable.

This intentionally validates only the small coverage schema consumed by GSD's
UAT classifier. It does not interpret prose or decide whether evidence proves a
product claim; it prevents typos from silently turning automated coverage into
manual checkpoints.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


KINDS = {"unit", "integration", "e2e", "automated_ui", "manual_procedural", "other"}
STATUSES = {"pass", "fail", "unknown"}


def validate_summary_text(text: str, label: str = "SUMMARY") -> list[str]:
    """Return schema errors for one Markdown SUMMARY, allowing legacy files."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return [f"{label}: missing YAML frontmatter"]
    try:
        closing = next(i for i in range(1, len(lines)) if lines[i].strip() == "---")
    except StopIteration:
        return [f"{label}: unterminated YAML frontmatter"]

    frontmatter = lines[1:closing]
    coverage_headers = [i for i, line in enumerate(frontmatter) if re.fullmatch(r"coverage:\s*", line)]
    if not coverage_headers:
        return []  # Legacy summaries are still supported by verify-work.
    if len(coverage_headers) > 1:
        return [f"{label}: duplicate coverage blocks"]

    start = coverage_headers[0] + 1
    while start < len(frontmatter) and not frontmatter[start].strip():
        start += 1
    if start >= len(frontmatter) or frontmatter[start].strip() == "[]":
        return []

    entry_starts = [i for i in range(start, len(frontmatter)) if re.match(r"^  - id:\s*\S", frontmatter[i])]
    if not entry_starts:
        return [f"{label}: coverage block has no entries; use 'coverage: []' or valid entries"]
    errors: list[str] = []
    if frontmatter[start].strip() != "- id:" and not re.match(r"^  - id:\s*\S", frontmatter[start]):
        errors.append(f"{label}: coverage entries must use two-space '- id:' indentation")

    for index, entry_start in enumerate(entry_starts):
        entry_end = entry_starts[index + 1] if index + 1 < len(entry_starts) else len(frontmatter)
        entry = frontmatter[entry_start:entry_end]
        entry_id = re.match(r"^  - id:\s*(.*?)\s*$", entry[0]).group(1).strip(" '\"")
        prefix = f"{label}: coverage entry {entry_id or '<empty-id>'}"
        if not entry_id:
            errors.append(f"{prefix} has an empty id")
        elif any(
            re.match(r"^  - id:\s*(.*?)\s*$", frontmatter[seen]).group(1).strip(" '\"") == entry_id
            for seen in entry_starts[:index]
        ):
            errors.append(f"{prefix} duplicates an earlier id")
        if not any(re.match(r"^    description:\s*\S", line) for line in entry):
            errors.append(f"{prefix} has no description")

        human = [re.match(r"^    human_judgment:\s*(\S+)\s*$", line) for line in entry]
        human = [match.group(1) for match in human if match]
        if len(human) != 1 or human[0] not in {"true", "false"}:
            errors.append(f"{prefix} must have exactly one human_judgment: true|false")
        if human == ["true"] and not any(re.match(r"^    rationale:\s*\S", line) for line in entry):
            errors.append(f"{prefix} needs a non-empty rationale when human_judgment is true")

        kinds = [re.match(r"^ +[-] kind:\s*(\S+)\s*$", line) for line in entry]
        kinds = [match.group(1).strip(" '\"") for match in kinds if match]
        statuses = [re.match(r"^ +status:\s*(\S+)\s*$", line) for line in entry]
        statuses = [match.group(1).strip(" '\"") for match in statuses if match]
        refs = [re.match(r"^ +ref:\s*(.*?)\s*$", line) for line in entry]
        refs = [match.group(1).strip().strip(" '\"") for match in refs if match]
        # GSD permits absent or empty verification lists. It classifies those
        # entries as present/no_verification rather than auto-passing them.
        if kinds and (len(kinds) != len(statuses) or len(kinds) != len(refs)):
            errors.append(f"{prefix} verification entries need one kind, ref, and status each")
        if not kinds and statuses:
            errors.append(f"{prefix} has verification status rows without kinds")
        for kind in kinds:
            if kind not in KINDS:
                errors.append(f"{prefix} has unsupported verification kind {kind!r}")
        for status in statuses:
            if status not in STATUSES:
                errors.append(f"{prefix} has unsupported verification status {status!r}")

    return errors


def validate_tree(root: Path) -> tuple[int, int, list[str]]:
    files = sorted(root.glob("**/*-SUMMARY.md"))
    if not files:
        return 0, 0, [f"{root}: no phase SUMMARY files discovered"]
    coverage_files = 0
    errors: list[str] = []
    for path in files:
        text = path.read_text(encoding="utf-8")
        if re.search(r"^coverage:\s*$", text, re.M):
            coverage_files += 1
        errors.extend(validate_summary_text(text, str(path)))
    if coverage_files == 0:
        errors.append(f"{root}: no SUMMARY coverage blocks discovered")
    return len(files), coverage_files, errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(".planning/phases"))
    args = parser.parse_args(argv)
    if not args.root.is_dir():
        print(f"[summary-coverage] FAIL: planning directory not found: {args.root}", file=sys.stderr)
        return 1
    summary_count, coverage_count, errors = validate_tree(args.root)
    if errors:
        for error in errors:
            print(f"[summary-coverage] FAIL: {error}", file=sys.stderr)
        return 1
    print(f"[summary-coverage] OK: discovered {summary_count} phase summaries; {coverage_count} coverage blocks are classifiable")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
