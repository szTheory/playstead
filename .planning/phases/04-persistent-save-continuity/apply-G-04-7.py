#!/usr/bin/env python3
"""G-04-7: make the reclaim-ordering guard brace-aware instead of splitting on the first '}'.

Run from the repo root:    python3 .planning/phases/04-persistent-save-continuity/apply-G-04-7.py

The guard asserts that "Reclaim selected" snapshots the selection, clears it, then invokes
the effect -- in that order. It extracts the button body with

    source.split('Button("Reclaim selected") {', 1)[1].split('}', 1)[0]

which stops at the FIRST '}'. Phase 4 added the only-copy interruption gate to that body,
whose `candidates.filter { ... }` closure now closes a brace before any of the markers.
The body is truncated to two lines and the guard reports a violation that is not there:
ReclaimPromptView.swift:137-148 still does `let selection = selected`, `selected.removeAll()`,
`onReclaim(selection)`, in order.

This replaces the split with real brace matching, so the guard reads the whole body and keeps
asserting exactly what it always asserted. It does NOT weaken the check -- verify by running
the script's own negative control, printed at the end.
"""
import pathlib
import sys

TARGET = pathlib.Path("playstead-mac/scripts/ci/tests/four-layer-topology-test.sh")

OLD = '''for path in map(pathlib.Path, sys.argv[1:]):
    source = path.read_text(encoding="utf-8")
    action = source.split('Button("Reclaim selected") {', 1)[1].split('}', 1)[0]'''

NEW = '''def brace_matched_body(source, opener):
    """The text between `opener`'s trailing '{' and its matching '}'.

    A plain `.split('}', 1)` stops at the first nested closure's brace, which
    silently truncates the body and turns any later marker into a false
    violation. Braces inside string literals are not tracked; no Swift button
    body in this repo contains one, and a naive split handled them no better.
    """
    start = source.index(opener) + len(opener)
    depth = 1
    for offset in range(start, len(source)):
        character = source[offset]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return source[start:offset]
    raise SystemExit(f"unbalanced braces after {opener!r}")


for path in map(pathlib.Path, sys.argv[1:]):
    source = path.read_text(encoding="utf-8")
    action = brace_matched_body(source, 'Button("Reclaim selected") {')'''


def main() -> int:
    if not TARGET.exists():
        print(f"error: {TARGET} not found -- run this from the repo root", file=sys.stderr)
        return 1

    source = TARGET.read_text(encoding="utf-8")

    if "def brace_matched_body(" in source:
        print("already applied; nothing to do")
        return 0

    count = source.count(OLD)
    if count != 1:
        print(
            f"error: expected exactly 1 occurrence of the anchor, found {count}.\n"
            "The file has drifted -- edit it by hand rather than letting this guess.",
            file=sys.stderr,
        )
        return 1

    TARGET.write_text(source.replace(OLD, NEW, 1), encoding="utf-8")
    print(f"applied to {TARGET}")
    print()
    print("verify it passes:   bash playstead-mac/scripts/ci/tests/four-layer-topology-test.sh")
    print()
    print("negative control -- confirm it still CATCHES a real violation:")
    print("  1. in playstead-mac/Playstead/Library/ReclaimPromptView.swift, swap the order of")
    print("     `selected.removeAll()` and `onReclaim(selection)`")
    print("  2. re-run the guard; it MUST fail with the reclaim-ordering message")
    print("  3. undo with: git checkout -- playstead-mac/Playstead/Library/ReclaimPromptView.swift")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
