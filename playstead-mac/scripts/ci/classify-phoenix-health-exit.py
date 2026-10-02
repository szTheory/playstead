#!/usr/bin/env python3
"""Map a private health-probe status code to one fixed public category."""

import sys


EXIT_CATEGORIES = {
    "10": "certificate_trust",
    "11": "endpoint_name",
    "12": "protocol",
    "13": "cipher",
    "14": "handshake",
    "15": "listener",
    "16": "unknown",
}
ALLOWED = {"certificate_trust", "endpoint_name", "protocol", "cipher", "handshake", "listener", "unknown"}


def main() -> int:
    category = EXIT_CATEGORIES.get(sys.argv[1], "unknown") if len(sys.argv) == 2 else "unknown"
    print(category if category in ALLOWED else "unknown")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
