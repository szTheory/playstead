#!/usr/bin/env python3
"""Flag XCUITest reads of static-text content through `.label`.

On macOS an AXStaticText keeps its content in AXValue. `.label` is
AXTitle/AXDescription, which a SwiftUI `Text` leaves empty -- so a test that
reads `.label` compares against "" and says nothing about what the user sees.
Read through `readableText` instead (PlaysteadUITests/Support/UITestHarness.swift).
"""
import pathlib
import re
import sys

# `let x = app.staticTexts[...]` / `= <anything>.staticTexts[` -- the binding
# whose `.label` is meaningless.
INLINE = re.compile(r"\.staticTexts\[[^\]]*\]\s*\.label\b")
PREDICATE = re.compile(r'NSPredicate\(\s*format:\s*"([^"]*)"')
STATIC_BIND = re.compile(r"\b(?:let|var)\s+(\w+)\s*(?::[^=]+)?=\s*[^\n]*\.staticTexts\[")
STATIC_MATCH = re.compile(r"\.staticTexts\.(?:matching|containing)\(")


def scan(path: pathlib.Path):
    problems = []
    for swift in sorted(path.rglob("*.swift")):
        text = swift.read_text()
        lines = text.splitlines()
        bound = set(STATIC_BIND.findall(text))
        for n, line in enumerate(lines, 1):
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("///"):
                continue
            if INLINE.search(line):
                problems.append((swift, n, "reads .label directly off a staticTexts query"))
            for name in bound:
                if re.search(r"\b%s\s*\.label\b" % re.escape(name), line):
                    problems.append((swift, n, "reads .label on `%s`, bound from staticTexts" % name))
            # Only reject a label predicate when this same query is explicitly
            # scoped to staticTexts. Button/container AX labels are valid.
            if STATIC_MATCH.search(line):
                for fmt in PREDICATE.findall(line):
                    if "label" in fmt and "value" not in fmt:
                        problems.append(
                            (swift, n, "staticTexts predicate matches on label but not value")
                        )
    return problems


def main():
    roots = [pathlib.Path(a) for a in sys.argv[1:]] or [pathlib.Path("PlaysteadUITests")]
    problems = []
    for root in roots:
        problems.extend(scan(root))
    if problems:
        print("macOS static text carries its content in `value`, not `label`.", file=sys.stderr)
        print("Read it with `readableText` (PlaysteadUITests/Support/UITestHarness.swift).\n", file=sys.stderr)
        for swift, n, why in problems:
            print("  %s:%d: %s" % (swift, n, why), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
