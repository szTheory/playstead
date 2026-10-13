#!/usr/bin/env bash
set -euo pipefail
[ "$#" -eq 0 ] || exit 77
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec /usr/bin/python3 "$SCRIPT_DIR/continuation_protocol.py" spike
