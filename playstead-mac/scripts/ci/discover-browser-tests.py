#!/usr/bin/env python3
"""Fail when the known Wallaby browser suite has no discoverable test cases.

Elixir 1.19 does not provide Mix's newer --dry-run discovery option. This
checks the project's explicit browser suite path and its ExUnit/Wallaby case
declarations without starting Chrome or running the cases a second time.
"""
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "test/playstead_web/browser")
files = sorted(root.rglob("*_test.exs")) if root.is_dir() else []
cases = 0
for path in files:
    for line in path.read_text(encoding="utf-8").splitlines():
        if re.match(r"^\s*#", line):
            continue
        cases += len(re.findall(r"\b(?:test|feature)\s+\"", line))
if not files or cases == 0:
    raise SystemExit(f"browser suite discovery failed: {len(files)} files, {cases} cases")
print(f"browser suite discovery passed: {len(files)} files, {cases} test/feature cases")
