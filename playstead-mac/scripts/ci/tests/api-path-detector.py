#!/usr/bin/env python3
"""Every `path:` handed to APIClient must start at the server's mount point."""
import pathlib
import re
import sys

# `path: "..."` string literals passed to the API client.
PATH_ARG = re.compile(r'\bpath:\s*"([^"]*)"')
# Paths that are not API calls at all (SQLite opens a `:memory:` "path").
EXEMPT = re.compile(r"^(:memory:|/|)$|^[A-Za-z0-9_./-]*\.sqlite3$")


def scan(root: pathlib.Path):
    problems = []
    for swift in sorted(root.rglob("*.swift")):
        text = swift.read_text()
        for n, line in enumerate(text.splitlines(), 1):
            if line.strip().startswith("//"):
                continue
            for value in PATH_ARG.findall(line):
                if value == ":memory:" or value.endswith(".sqlite3"):
                    continue
                # A filesystem path variable, not an API route.
                if "/" not in value and "\\(" not in value:
                    continue
                if not value.startswith("/api/v1/"):
                    problems.append((swift, n, value))
    return problems


def main():
    roots = [pathlib.Path(a) for a in sys.argv[1:]] or [pathlib.Path("Playstead")]
    problems = []
    for root in roots:
        problems.extend(scan(root))
    if problems:
        print("API paths must be spelled in full, starting '/api/v1/'.", file=sys.stderr)
        print("APIClient appends the path to the server ORIGIN, so an unprefixed", file=sys.stderr)
        print("path 404s silently and is swallowed into a retry.\n", file=sys.stderr)
        for swift, n, value in problems:
            print('  %s:%d: path: "%s"' % (swift, n, value), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
