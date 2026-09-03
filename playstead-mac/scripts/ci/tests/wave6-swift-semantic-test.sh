#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
app_source="$repo_root/playstead-mac/Playstead/App/PlaysteadApp.swift"
fixture_source="$repo_root/playstead-mac/Playstead/UITesting/DeterministicProfile.swift"

# Implemented with python3, not ripgrep. `rg` is a Homebrew install, not part of
# the GitHub macos-26 image, so the previous implementation failed on the hosted
# runner with `rg: command not found` -- and would have passed VACUOUSLY there
# had its negative control not existed: a missing command exits 127, which an
# `if rg -q ...` production check reads as "pattern absent". python3 is already
# a hard dependency of every other script in this harness.
python3 - "$app_source" "$fixture_source" <<'PY'
import pathlib, re, sys

# `.map(\.sha256)` followed (possibly across a line break) by `.sorted()`:
# sorting optional digests instead of compacting them first.
forbidden = re.compile(r"\.map\(\\\.sha256\)\s*\.sorted\(\)")
compacted = re.compile(r"compactMap\(\\\.sha256\)")

# Prove the fail-closed matcher catches the exact semantic regression before
# trusting it against production sources.
if not forbidden.search(".map(\\.sha256)\n    .sorted()\n"):
    raise SystemExit(
        "wave6 semantic contract failed: optional-digest negative control was not detected"
    )
# The inverse control: the compacted form must NOT be read as the regression.
if forbidden.search("compactMap(\\.sha256)\n    .sorted()\n"):
    raise SystemExit(
        "wave6 semantic contract failed: positive control misread the compacted form"
    )

compact_count = 0
for arg in sys.argv[1:]:
    path = pathlib.Path(arg)
    if not path.is_file():
        raise SystemExit(f"wave6 semantic contract failed: missing source {path}")
    source = path.read_text(encoding="utf-8")
    if forbidden.search(source):
        raise SystemExit(
            "wave6 semantic contract failed: optional AssetMember.sha256 values "
            "must be compacted before sorting"
        )
    compact_count += len(compacted.findall(source))

if compact_count < 3:
    raise SystemExit(
        "wave6 semantic contract failed: expected all three digest fingerprints "
        f"to compact optional values, found {compact_count}"
    )

print("wave6 optional-digest semantic contract passed")
PY
