#!/usr/bin/env python3
"""Require the runloop hop beside every `.defaultFocus` in production views."""
import pathlib
import re
import sys

DEFAULT_FOCUS = re.compile(r"\.defaultFocus\(\s*\$(\w+)\s*,")


def scan(root: pathlib.Path):
    problems = []
    for swift in sorted(root.rglob("*.swift")):
        text = swift.read_text()
        for n, line in enumerate(text.splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith("//"):
                continue
            m = DEFAULT_FOCUS.search(line)
            if not m:
                continue
            state = m.group(1)
            # The hop: a detached main-actor task that yields once, then sets
            # this same focus state -- and an onAppear that runs it.
            hop = re.search(
                r"Task\s*\{\s*@MainActor\s+in\s*\n\s*await Task\.yield\(\)\s*\n\s*%s\s*=\s*true"
                % re.escape(state),
                text,
            )
            if not (hop and ".onAppear" in text):
                problems.append((swift, n, state))
    return problems


def main():
    roots = [pathlib.Path(a) for a in sys.argv[1:]] or [pathlib.Path("Playstead")]
    problems = []
    for root in roots:
        problems.extend(scan(root))
    if problems:
        print(".defaultFocus alone does not place focus in this app.", file=sys.stderr)
        print("Back it with the runloop hop (see OnlyCopyInterruptiveSheet):\n", file=sys.stderr)
        print("    .onAppear { placeInitialFocus() }\n", file=sys.stderr)
        print("    private func placeInitialFocus() {", file=sys.stderr)
        print("        Task { @MainActor in", file=sys.stderr)
        print("            await Task.yield()", file=sys.stderr)
        print("            <state> = true", file=sys.stderr)
        print("        }\n    }\n", file=sys.stderr)
        for swift, n, state in problems:
            print("  %s:%d: .defaultFocus($%s) has no runloop hop" % (swift, n, state), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
