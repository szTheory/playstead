#!/usr/bin/env python3
"""Emit one privacy-safe category for an owned Phoenix startup log."""

import pathlib
import re
import sys


CATEGORIES = (
    ("db_connection", (r"connection refused", r"database .* does not exist", r"could not connect to server", r"database connection")),
    ("listener", (r"eaddrinuse", r"address already in use", r"could not bind", r"listen tcp")),
    ("endpoint_name", (r"hostname mismatch", r"ip address mismatch", r"no alternative certificate subject name", r"subject alternative name")),
    ("certificate_trust", (r"unknown ca", r"bad certificate", r"certificate verify failed", r"unable to get local issuer", r"certificate required")),
    ("protocol", (r"protocol version", r"unsupported protocol", r"version too low")),
    ("cipher", (r"no shared cipher", r"no suitable signature algorithm", r"no suitable key share", r"no cipher match")),
    ("handshake", (r"handshake failure", r"tls handshake error", r"ssl handshake")),
    ("runtime_exit", (r"application .* exited", r"terminating", r"crash", r"exception", r"shutdown")),
)
ALLOWED = {"listener", "db_connection", "endpoint_name", "certificate_trust", "protocol", "cipher", "handshake", "runtime_exit", "readiness_timeout", "log_missing", "unknown"}


def classify(log_path: str, mode: str) -> str:
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
    return "runtime_exit" if mode == "exited" else "readiness_timeout" if mode == "deadline" else "unknown"


def main() -> int:
    category = classify(sys.argv[1], sys.argv[2]) if len(sys.argv) == 3 and sys.argv[2] in {"exited", "deadline"} else "unknown"
    print(category if category in ALLOWED else "unknown")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
