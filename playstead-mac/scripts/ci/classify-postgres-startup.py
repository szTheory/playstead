#!/usr/bin/env python3
"""Emit one privacy-safe category for an owned PostgreSQL startup log."""

import pathlib
import re
import sys


CATEGORIES = (
    ("shared_memory", (r"shared memory", r"shmget", r"shm_open")),
    ("port_binding", (r"address already in use", r"could not bind", r"bind\(\) failed")),
    ("permission", (r"permission denied", r"operation not permitted")),
    ("resource_exhaustion", (r"resource temporarily unavailable", r"cannot allocate memory", r"out of memory", r"too many open files", r"no space left")),
    ("config_or_data", (r"invalid value for parameter", r"configuration file contains errors", r"database files are incompatible", r"invalid checkpoint record")),
)
ALLOWED = {"shared_memory", "port_binding", "permission", "resource_exhaustion", "config_or_data", "log_missing", "unknown"}


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
