#!/usr/bin/env bash
# Polls a save file's size, mtime, and SHA-256 at one-second granularity into
# a JSONL timeline. Probe 3 (D-03 owner ruling) — used to prove or disprove an
# on-disk flush during play, not only at clean exit.
#
# Usage: watch-save.sh <save-file> <duration-seconds> <output-jsonl>
set -uo pipefail

SAVE_FILE="${1:?usage: watch-save.sh <save-file> <duration-seconds> <output-jsonl>}"
DURATION="${2:?usage: watch-save.sh <save-file> <duration-seconds> <output-jsonl>}"
OUT_JSONL="${3:?usage: watch-save.sh <save-file> <duration-seconds> <output-jsonl>}"

mkdir -p "$(dirname "$OUT_JSONL")"
: > "$OUT_JSONL"

END=$(( $(date +%s) + DURATION ))
while [ "$(date +%s)" -lt "$END" ]; do
  TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  if [ -f "$SAVE_FILE" ]; then
    SIZE=$(stat -f%z "$SAVE_FILE" 2>/dev/null || echo 0)
    MTIME=$(stat -f%m "$SAVE_FILE" 2>/dev/null || echo 0)
    SHA=$(shasum -a 256 "$SAVE_FILE" | awk '{print $1}')
  else
    SIZE=0
    MTIME=0
    SHA="absent"
  fi
  printf '{"timestamp":"%s","size":%s,"mtime":%s,"sha256":"%s"}\n' "$TS" "$SIZE" "$MTIME" "$SHA" >> "$OUT_JSONL"
  sleep 1
done
