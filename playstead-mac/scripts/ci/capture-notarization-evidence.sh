#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANITIZER="${SCRIPT_DIR}/sanitize-evidence.sh"

die() {
  printf 'capture-notarization-evidence: %s\n' "$*" >&2
  exit 1
}

[ "$#" -ge 4 ] || die "usage: capture-notarization-evidence.sh --output FILE -- COMMAND [ARG ...]"
[ "$1" = "--output" ] || die "first argument must be --output"
REQUESTED_OUTPUT="$2"
[ "$3" = "--" ] || die "third argument must be --"
shift 3
[ "$#" -gt 0 ] || die "a command is required after --"

[ -n "$REQUESTED_OUTPUT" ] || die "output file must not be empty"
[ "$REQUESTED_OUTPUT" != "/" ] && [ "$REQUESTED_OUTPUT" != "." ] && [ "$REQUESTED_OUTPUT" != ".." ] || die "unsafe output file"
[ ! -L "$REQUESTED_OUTPUT" ] || die "symlink output file is forbidden"
[ ! -d "$REQUESTED_OUTPUT" ] || die "output file must not be a directory"

OUTPUT_PARENT_INPUT="$(dirname "$REQUESTED_OUTPUT")"
OUTPUT_BASENAME="$(basename "$REQUESTED_OUTPUT")"
[ -n "$OUTPUT_BASENAME" ] && [ "$OUTPUT_BASENAME" != "." ] && [ "$OUTPUT_BASENAME" != ".." ] || die "unsafe output file name"
[ -d "$OUTPUT_PARENT_INPUT" ] || die "output parent directory does not exist"
[ ! -L "$OUTPUT_PARENT_INPUT" ] || die "symlink output parent is forbidden"
OUTPUT_PARENT="$(cd "$OUTPUT_PARENT_INPUT" && pwd -P)"
OUTPUT_PATH="${OUTPUT_PARENT}/${OUTPUT_BASENAME}"
[ "$OUTPUT_PATH" != "/" ] || die "unsafe output file"

[ -x "$SANITIZER" ] || die "evidence sanitizer is missing or not executable"

umask 077
PRIVATE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/playstead-notarization-capture.XXXXXX")"
PUBLISH_TEMP=""
cleanup() {
  if [ -n "$PUBLISH_TEMP" ]; then
    rm -f "$PUBLISH_TEMP"
  fi
  rm -rf "$PRIVATE_ROOT"
}
trap cleanup EXIT
chmod 700 "$PRIVATE_ROOT"
mkdir -p "$PRIVATE_ROOT/raw/evidence"

RAW_TRANSCRIPT="$PRIVATE_ROOT/raw/evidence/notarization.log"
SANITIZED_ROOT="$PRIVATE_ROOT/sanitized"

set +e
"$@" >"$RAW_TRANSCRIPT" 2>&1
WRAPPED_STATUS=$?
set -e

if ! "$SANITIZER" --input "$PRIVATE_ROOT/raw" --output "$SANITIZED_ROOT" \
  >"$PRIVATE_ROOT/sanitizer.stdout" 2>"$PRIVATE_ROOT/sanitizer.stderr"; then
  printf 'capture-notarization-evidence: FATAL: EVIDENCE_SANITIZATION_FAILED\n' >&2
  exit 1
fi

SANITIZED_TRANSCRIPT="$SANITIZED_ROOT/notarization.log"
MANIFEST="$SANITIZED_ROOT/manifest.json"
[ -f "$SANITIZED_TRANSCRIPT" ] && [ ! -L "$SANITIZED_TRANSCRIPT" ] && [ -s "$SANITIZED_TRANSCRIPT" ] || \
  die "sanitizer did not produce a regular, non-empty notarization transcript"
[ -f "$MANIFEST" ] && [ ! -L "$MANIFEST" ] || die "sanitizer did not produce a manifest"

python3 - "$MANIFEST" "$SANITIZED_TRANSCRIPT" <<'PY'
import json
import pathlib
import sys

manifest_path = pathlib.Path(sys.argv[1])
transcript_path = pathlib.Path(sys.argv[2])
try:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
except (OSError, UnicodeError, json.JSONDecodeError) as exc:
    raise SystemExit(f"invalid sanitizer manifest: {exc}")

entries = manifest.get("files")
expected = {"path": "notarization.log", "size_bytes": transcript_path.stat().st_size}
if manifest.get("schema_version") != 1 or entries != [expected]:
    raise SystemExit("sanitizer manifest does not bind the notarization transcript")
PY

PUBLISH_TEMP="$(mktemp "${OUTPUT_PARENT}/.${OUTPUT_BASENAME}.tmp.XXXXXX")"
chmod 600 "$PUBLISH_TEMP"
cp "$SANITIZED_TRANSCRIPT" "$PUBLISH_TEMP"

# Re-check immediately before publication so an existing symlink is never an
# accepted destination. rename(2) then atomically installs sanitized bytes.
[ ! -L "$OUTPUT_PATH" ] || die "symlink output file is forbidden"
[ ! -d "$OUTPUT_PATH" ] || die "output file must not be a directory"
mv -f "$PUBLISH_TEMP" "$OUTPUT_PATH"
PUBLISH_TEMP=""

exit "$WRAPPED_STATUS"
