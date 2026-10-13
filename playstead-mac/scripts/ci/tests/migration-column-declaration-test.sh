#!/usr/bin/env bash
# WINDOWS #90: a column declared SOLELY by a defensive `try? ALTER`, with
# no matching entry in its own CREATE TABLE block, is a latent failure
# waiting for an ordinary tidy-up. The ALTER runs unconditionally on every
# launch, so every database has the column and nothing looks broken -- but
# delete the "redundant" line and a FRESH database silently lacks a column
# the app reads and writes, with the error swallowed by the very `try?`
# that made the line look optional.
#
# The root cause this guards is structural, not a single typo:
# Migrations.swift has no `user_version` gate anywhere, so every statement
# is written to be idempotent and re-runnable, and there is no syntactic
# distinction between "this ALTER upgrades an old database" and "this
# ALTER is the only thing that creates the column". This guard supplies
# that distinction -- every ALTER-added column must ALSO appear in its
# CREATE TABLE block, which makes every ALTER genuinely redundant on a
# fresh database and load-bearing only on an upgrade.
#
# The detector fails closed: a missing file, an unparseable source, or
# zero matched ALTER statements are all failures, because a guard that
# matches nothing reports success on a file it never understood.
#
# Every assertion is also exercised against a temporary mutated copy and
# must be observed failing there -- a guard that has never been seen to
# fail is not a guard.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
MIGRATIONS="${MAC_ROOT}/Playstead/Persistence/Migrations.swift"
DETECTOR="${SCRIPT_DIR}/migration-column-declaration-detector.py"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/playstead-migration-columns.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

[ -f "$MIGRATIONS" ] || { echo "FAIL: Migrations.swift not found at ${MIGRATIONS}" >&2; exit 1; }
[ -f "$DETECTOR" ] || { echo "FAIL: detector not found at ${DETECTOR}" >&2; exit 1; }

echo "=== migration column declaration ==="

echo "ASSERT: every ALTER-added column is also declared in its CREATE TABLE block"
python3 "$DETECTOR" "$MIGRATIONS"

# --- self-tests: the detector must be observed failing ---

echo "ASSERT: the detector rejects a column that only an ALTER declares"
python3 - "$MIGRATIONS" "$WORK_DIR/undeclared.swift" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
# Drop one column line from a CREATE block whose name is also ALTER-added,
# reproducing #90's exact pre-fix shape.
alters = re.findall(r"ALTER\s+TABLE\s+\w+\s+ADD\s+COLUMN\s+(\w+)", src, re.I)
for column in alters:
    mutated, count = re.subn(rf"^\s*{column}\s+TEXT[^\n]*\n", "", src, count=1, flags=re.M)
    if count:
        open(sys.argv[2], "w", encoding="utf-8").write(mutated)
        raise SystemExit(0)
raise SystemExit("self-test could not construct an undeclared-column source")
PY
if python3 "$DETECTOR" "$WORK_DIR/undeclared.swift" >/dev/null 2>&1; then
  echo "FAIL: detector passed a source with an ALTER-only column" >&2
  exit 1
fi

echo "ASSERT: the detector fails closed on a source containing no ALTER statements"
printf 'let x = 1\n' > "$WORK_DIR/empty.swift"
if python3 "$DETECTOR" "$WORK_DIR/empty.swift" >/dev/null 2>&1; then
  echo "FAIL: detector reported success on a file with nothing to check" >&2
  exit 1
fi

echo "ASSERT: the detector fails closed on a missing file"
if python3 "$DETECTOR" "$WORK_DIR/does-not-exist.swift" >/dev/null 2>&1; then
  echo "FAIL: detector reported success on a missing file" >&2
  exit 1
fi

echo "migration column declaration verified"
