#!/usr/bin/env python3
"""Reduce an owned xcodebuild log to one privacy-safe failure category."""

import pathlib
import re
import sys


CATEGORIES = (
    ("package_resolution", (r"unable to resolve package", r"failed to resolve dependencies", r"could not resolve package", r"package resolution failed")),
    ("signing", (r"code signing error", r"code signing failed", r"signing .* requires a development team", r"no signing certificate", r"no profiles for", r"requires a provisioning profile", r"provisioning profile .* not found", r"errsec")),
    ("test_plan_selection", (r"test plan .* not found", r"no tests found", r"unable to find test", r"test identifier .* not found", r"test target .* not found")),
    ("simulator_runner", (r"unable to boot", r"failed to install", r"test runner failed", r"failed to launch", r"launchd_sim.*error", r"simulator.*(?:failed|error|unable)")),
    ("compile", (r"error:.*swift", r"swift compiler.*error", r"failed to compile", r"failed to build module", r"swiftfrontend.*failed")),
)
ALLOWED = {"compile", "signing", "package_resolution", "test_plan_selection", "simulator_runner", "unknown", "log_missing"}


def classify(log_path: str) -> str:
    path = pathlib.Path(log_path)
    try:
        if not path.is_file():
            return "log_missing"
        content = path.read_text(encoding="utf-8", errors="replace").lower()
    except OSError:
        return "unknown"
    for category, patterns in CATEGORIES:
        if any(re.search(pattern, content) for pattern in patterns):
            return category
    return "unknown"


def main() -> int:
    category = classify(sys.argv[1]) if len(sys.argv) == 2 else "unknown"
    print(category if category in ALLOWED else "unknown")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
