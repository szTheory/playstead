#!/usr/bin/env python3
"""Every UI test that shells out to live-server.sh must resolve the runner's
runtime config before trusting the inherited environment.

The fixture runs `mix playstead.mac_ci_fixture`. The XCTest process inherits a
PATH with no Elixir toolchain, so an inherited-only environment makes that
`mix` call die with "command not found" -- at provision-domain, on every
hosted run, forever. `LiveServerSnapshotTests` reads
`live-server-runtime.json` (which carries the runner's own PATH) and merges it
over the inherited environment. `SaveEndToEndTests` did not, and its failure
was invisible for as long as it stayed fail-open.
"""
import pathlib
import sys

FIXTURE_MARKER = "scripts/ci/live-server.sh"
CONFIG_MARKER = "live-server-runtime.json"
MERGE_MARKER = "merging(configured)"


def main(root: str) -> int:
    problems = []
    for path in sorted(pathlib.Path(root).rglob("*.swift")):
        text = path.read_text(encoding="utf-8", errors="replace")
        if FIXTURE_MARKER not in text:
            continue
        if CONFIG_MARKER not in text:
            problems.append(
                f"{path}: shells out to live-server.sh but never reads "
                f"{CONFIG_MARKER}; the inherited PATH has no `mix`"
            )
            continue
        if MERGE_MARKER not in text:
            problems.append(
                f"{path}: reads {CONFIG_MARKER} but does not merge it over the "
                "inherited environment, so the runner's PATH cannot win"
            )
    for problem in problems:
        print(problem, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: live-server-env-detector.py <swift-root>", file=sys.stderr)
        raise SystemExit(2)
    raise SystemExit(main(sys.argv[1]))
