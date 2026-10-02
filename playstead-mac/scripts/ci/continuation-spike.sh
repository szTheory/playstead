#!/usr/bin/env bash
set -euo pipefail
MODE=spike
if [ "$#" -eq 1 ] && [ "$1" = "--qualify-only" ]; then
  MODE=qualify-only
elif [ "$#" -ne 0 ]; then
  exit 77
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec /usr/bin/python3 "$SCRIPT_DIR/continuation_protocol.py" "$MODE"
