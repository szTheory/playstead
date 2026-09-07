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
BIND = re.compile(r"\b(?:let|var)\s+(\w+)\s*(?::[^=]+)?=\s*[^\n]*\.staticTexts\[")
INLINE = re.compile(r"\.staticTexts\[[^\]]*\]\s*\.label\b")
PREDICATE = re.compile(r'NSPredicate\(\s*format:\s*"([^"]*)"')
# Any read of `.label` on an element. `readableText` prefers `label` and falls
# back to `value`, so it is never worse and is right in the cases `.label`
# silently gets wrong -- which makes this a blanket rule with a narrow
# allowlist for the places that assert on the AX label attribute itself.
BARE_LABEL = re.compile(r"\.label\b")

ALLOWLIST = {
    # `readableText`'s own definition -- it is what everything else must use.
    ("Support/UITestHarness.swift", "label.isEmpty ? (value as? String ?? \"\")"),
    # The surface inventory's AX-label contract: emptiness here IS the subject
    # of the assertion, for targets declared `requiresLabel`.
    ("Support/UITestHarness.swift", "requiresLabel"),
}


def allowed(path, line):
    """Only the two lines that are *about* the AX label attribute itself."""
    for suffix, marker in ALLOWLIST:
        if str(path).endswith(suffix) and marker in line:
            return True
    return False


def scan(path: pathlib.Path):
    problems = []
    for swift in sorted(path.rglob("*.swift")):
        text = swift.read_text()
        lines = text.splitlines()
        bound = set(BIND.findall(text))
        # A predicate is only suspect if this file matches it against staticTexts.
        matches_static_texts = ".staticTexts.matching(" in text or ".staticTexts.containing(" in text
        for n, line in enumerate(lines, 1):
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("///"):
                continue
            if BARE_LABEL.search(line) and not allowed(swift, line):
                problems.append((swift, n, "reads user-visible text through `.label`"))
            if INLINE.search(line):
                problems.append((swift, n, "reads .label directly off a staticTexts query"))
            for name in bound:
                if re.search(r"\b%s\s*\.label\b" % re.escape(name), line):
                    problems.append((swift, n, "reads .label on `%s`, bound from staticTexts" % name))
            if matches_static_texts:
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
