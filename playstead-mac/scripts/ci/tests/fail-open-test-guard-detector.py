#!/usr/bin/env python3
"""A test that returns early without failing is a test that reports success.

`SaveEndToEndTests` guarded three fixture stages with a bare
`guard try runFixture(...) else { return }`. When a stage failed, the test
returned having asserted nothing -- and XCTest recorded a pass. That is how a
save-upload path that 404'd against every real server sat behind a green
end-to-end suite.

Inside a `func test...`, an early return must say why: `XCTFail` when the
condition is a defect, `throw XCTSkip` when the environment genuinely cannot
run the test (a skip is visible in results; a bare return is not).
"""
import pathlib
import re
import sys

FUNC = re.compile(r"^\s*(?:@MainActor\s+)?(?:private\s+|public\s+)?func\s+(\w+)\s*\(")
BARE_RETURN_ELSE = re.compile(r"\belse\s*\{\s*return\s*\}")


def scan(root: pathlib.Path):
    problems = []
    for swift in sorted(root.rglob("*.swift")):
        current = None
        for n, line in enumerate(swift.read_text().splitlines(), 1):
            m = FUNC.match(line)
            if m:
                current = m.group(1)
            if not (current or "").startswith("test"):
                continue
            stripped = line.strip()
            if stripped.startswith("//"):
                continue
            if BARE_RETURN_ELSE.search(line):
                problems.append((swift, n, current))
    return problems


def main():
    roots = [pathlib.Path(a) for a in sys.argv[1:]]
    problems = []
    for root in roots:
        problems.extend(scan(root))
    if problems:
        print("A bare early return inside a test body reports success without", file=sys.stderr)
        print("asserting anything. Say why instead:\n", file=sys.stderr)
        print("    else { return XCTFail(\"<what went wrong>\") }   // a defect", file=sys.stderr)
        print("    else { throw XCTSkip(\"<why unrunnable>\") }     // environment\n", file=sys.stderr)
        for swift, n, func in problems:
            print("  %s:%d: in %s()" % (swift, n, func), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
