#!/usr/bin/env bash
# Cross-checks a file the operator already legally owns against the pinned
# BIOS reference (03-BIOS-PIN.json) — exact byte length, then SHA-256.
#
# This script validates what the operator has and nothing more: it never
# prints a URL, a mirror, or any hint about where to obtain BIOS content.
#
# Usage: verify-bios-reference.sh <path-to-file>
#
# Exit codes:
#   0  MATCH             - both length and digest match a pinned value
#   2  LENGTH_MISMATCH   - byte length does not match the pin
#   3  DIGEST_MISMATCH   - length matched, but no digest matched
#   4  PIN_MISSING       - the pin file could not be found
#   1  usage error (no argument, or supplied path is not a readable file)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${MAC_ROOT}/.." && pwd)"
PIN_FILE="${REPO_ROOT}/.planning/phases/03-mac-offline-play-vertical-slice/03-BIOS-PIN.json"

if [ "$#" -ne 1 ]; then
  printf 'usage: %s <path-to-file>\n' "$0" >&2
  exit 1
fi

CANDIDATE="$1"

if [ ! -f "$PIN_FILE" ]; then
  printf 'PIN_MISSING: %s not found\n' "$PIN_FILE" >&2
  exit 4
fi

if [ ! -f "$CANDIDATE" ]; then
  printf 'usage error: %s is not a readable file\n' "$CANDIDATE" >&2
  exit 1
fi

EXPECTED_LENGTH="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['expected_byte_length'])" "$PIN_FILE")"
ACTUAL_LENGTH="$(wc -c < "$CANDIDATE" | tr -d '[:space:]')"

if [ "$ACTUAL_LENGTH" -ne "$EXPECTED_LENGTH" ]; then
  printf 'LENGTH_MISMATCH: expected %s bytes, got %s bytes\n' "$EXPECTED_LENGTH" "$ACTUAL_LENGTH" >&2
  exit 2
fi

ACTUAL_DIGEST="$(shasum -a 256 "$CANDIDATE" | awk '{print $1}')"
DIGEST_MATCHES="$(python3 -c "
import json, sys
pin = json.load(open(sys.argv[1]))
print('1' if sys.argv[2] in pin['known_sha256_digests'] else '0')
" "$PIN_FILE" "$ACTUAL_DIGEST")"

if [ "$DIGEST_MATCHES" != "1" ]; then
  printf 'DIGEST_MISMATCH: %s does not match a pinned reference digest\n' "$ACTUAL_DIGEST" >&2
  exit 3
fi

printf 'MATCH: %s matches the pinned reference (length %s, digest %s)\n' "$CANDIDATE" "$ACTUAL_LENGTH" "$ACTUAL_DIGEST"
exit 0
