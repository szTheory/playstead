#!/usr/bin/env bash
# scripts/check-uat-tally.sh
#
# Plan 03-14 (LIBR-02 gap closure, Task 2). Derives every UAT file's
# tally directly from its own body -- one record per "### N." heading,
# taking the FIRST "result:" line that follows it and ignoring any
# later "result:" line belonging to a sub-record (03-UAT.md's item 10
# carries exactly such a sub-record: a naive count of every "result:"
# line in that file yields 45 against 44 headings) -- and compares the
# derived counts against the file's own "## Summary" footer
# (total/passed/blocked/partial/skipped). Exits non-zero, naming the
# file and both numbers, on any disagreement.
#
# This project has already found four fail-open CI gates (03.5's
# hardening pass): a missing command exits 127, which `if cmd` reads
# as clean. This script fails closed in every direction on purpose:
#   - exits non-zero if the glob matches no file at all
#   - exits non-zero if a matched file has no "## Summary" section
#   - exits non-zero if a matched file has no "### N." headings
#   - exits non-zero if any derived count is zero for a file that has
#     headings
# A guard that silently finds nothing to check is the failure mode
# this script exists to prevent, not a pass.
#
# Usage: scripts/check-uat-tally.sh [glob]
#   glob defaults to ".planning/phases/*/*-UAT.md" (relative to the
#   repo root this script lives under).
set -euo pipefail

cd "$(dirname "$0")/.."

GLOB="${1:-.planning/phases/*/*-UAT.md}"

# Intentionally NOT `shopt -s nullglob` before this check: an
# unexpanded glob (no match) stays a literal string that fails the
# `-f` test below, which is exactly the fail-closed behavior this
# script wants for "no file matched" -- nullglob would instead produce
# an empty array here and require a second explicit emptiness check,
# which is one more place a fail-open regression could hide.
shopt -s nullglob
FILES=($GLOB)
shopt -u nullglob

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "[check-uat-tally] FAIL: no file matched '${GLOB}' -- a guard that finds nothing to check is a fail-open gate, not a pass." >&2
  exit 1
fi

STATUS=0
for file in "${FILES[@]}"; do
  if [ ! -f "$file" ]; then
    echo "[check-uat-tally] FAIL: '${file}' matched the glob but is not a regular file." >&2
    STATUS=1
    continue
  fi
  if ! python3 - "$file" <<'PY'
import re
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()

failed = False


def fail(message):
    global failed
    print(f"[check-uat-tally] FAIL: {path}: {message}", file=sys.stderr)
    failed = True


heading_pattern = re.compile(r"^### (\d+)\.", re.MULTILINE)
headings = heading_pattern.findall(text)

if not headings:
    fail("no '### N.' item headings found")
    sys.exit(1)

# Split the body into one chunk per top-level "### N." heading. Each
# chunk runs until the next top-level heading (or end of file), so a
# nested "#### " sub-heading -- and any "result:" line inside it --
# stays part of the SAME chunk as its parent, never its own record.
sections = heading_pattern.split(text)
# re.split with a capturing group interleaves [preamble, num1, body1,
# num2, body2, ...]; drop the preamble, then take every other element
# starting at index 2 (the body chunks).
bodies = sections[2::2]

if len(bodies) != len(headings):
    fail(f"heading count ({len(headings)}) does not match parsed section count ({len(bodies)})")
    sys.exit(1)

derived = {}
for heading_num, body in zip(headings, bodies):
    # A body chunk can still contain the file's own "## Summary"
    # section if this was the LAST heading -- cut there so the
    # first-result-line search never wanders into the footer.
    body = re.split(r"^## ", body, maxsplit=1, flags=re.MULTILINE)[0]
    match = re.search(r"^result:\s*(\S+)\s*$", body, re.MULTILINE)
    if not match:
        fail(f"item {heading_num} has no 'result:' line")
        continue
    result = match.group(1)
    derived[result] = derived.get(result, 0) + 1

if failed:
    sys.exit(1)

derived_total = sum(derived.values())
if derived_total == 0:
    fail(f"derived a zero total from {len(headings)} headings")
    sys.exit(1)

summary_match = re.search(r"^## Summary\n(.*?)(?=\n## |\Z)", text, re.MULTILINE | re.DOTALL)
if not summary_match:
    fail("no '## Summary' section found")
    sys.exit(1)

stated = {}
for line in summary_match.group(1).splitlines():
    m = re.match(r"^([a-z_]+):\s*(-?\d+)\s*$", line.strip())
    if m:
        stated[m.group(1)] = int(m.group(2))

if "total" not in stated:
    fail("'## Summary' section has no 'total:' line")
    sys.exit(1)

if stated["total"] != derived_total:
    fail(f"stated total ({stated['total']}) != derived total ({derived_total})")

if stated["total"] != len(headings):
    fail(f"stated total ({stated['total']}) != number of '### N.' headings ({len(headings)})")

# Every body-derived result kind must have a footer line naming it,
# with the exact derived count -- an absent line (e.g. "partial" with
# no footer line at all) is exactly the shape of defect that let
# 03-UAT.md's footer go stale (it never grew a "partial:" line when
# item 10 and item 13 became partial records).
KIND_TO_FOOTER_KEY = {"pass": "passed", "blocked": "blocked", "partial": "partial", "skipped": "skipped"}
for kind, count in sorted(derived.items()):
    footer_key = KIND_TO_FOOTER_KEY.get(kind, kind)
    if footer_key not in stated:
        fail(f"body has {count} '{kind}' result(s) but '## Summary' has no '{footer_key}:' line")
        continue
    if stated[footer_key] != count:
        fail(f"stated {footer_key} ({stated[footer_key]}) != derived {kind} count ({count})")

if failed:
    sys.exit(1)

print(f"[check-uat-tally] OK: {path}: total={derived_total} " + ", ".join(f"{k}={v}" for k, v in sorted(derived.items())))
PY
  then
    STATUS=1
  fi
done

exit "$STATUS"
