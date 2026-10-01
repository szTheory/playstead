#!/usr/bin/env bash
set -euo pipefail
[ "$#" -eq 1 ] || exit 77
case "$1" in probe|qualify|initial-run|continue) ;; *) exit 77 ;; esac
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec /usr/bin/python3 "$SCRIPT_DIR/continuation_protocol.py" runner "$1"
