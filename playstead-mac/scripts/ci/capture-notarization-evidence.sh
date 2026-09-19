#!/usr/bin/env bash

# Source this file to capture a function or command already available in the
# current shell. Executing it directly retains the CLI used by focused tests.
capture_notarization_evidence() (
  set -euo pipefail

  capture_die() {
    printf 'capture-notarization-evidence: %s\n' "$*" >&2
    exit 1
  }

  [ "$#" -ge 2 ] || capture_die "usage: capture_notarization_evidence OUTPUT COMMAND [ARG ...]"
  local capture_requested_output="$1"
  shift

  local capture_script_dir
  local capture_sanitizer
  capture_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  capture_sanitizer="${capture_script_dir}/sanitize-evidence.sh"

  [ -n "$capture_requested_output" ] || capture_die "output file must not be empty"
  [ "$capture_requested_output" != "/" ] && [ "$capture_requested_output" != "." ] && [ "$capture_requested_output" != ".." ] || capture_die "unsafe output file"
  [ ! -L "$capture_requested_output" ] || capture_die "symlink output file is forbidden"
  [ ! -d "$capture_requested_output" ] || capture_die "output file must not be a directory"

  local capture_output_parent_input
  local capture_output_basename
  local capture_output_parent
  local capture_output_path
  capture_output_parent_input="$(dirname "$capture_requested_output")"
  capture_output_basename="$(basename "$capture_requested_output")"
  [ -n "$capture_output_basename" ] && [ "$capture_output_basename" != "." ] && [ "$capture_output_basename" != ".." ] || capture_die "unsafe output file name"
  [ -d "$capture_output_parent_input" ] || capture_die "output parent directory does not exist"
  [ ! -L "$capture_output_parent_input" ] || capture_die "symlink output parent is forbidden"
  capture_output_parent="$(cd "$capture_output_parent_input" && pwd -P)"
  capture_output_path="${capture_output_parent}/${capture_output_basename}"
  [ "$capture_output_path" != "/" ] || capture_die "unsafe output file"
  [ -x "$capture_sanitizer" ] || capture_die "evidence sanitizer is missing or not executable"

  umask 077
  local capture_private_root
  local capture_publish_temp=""
  capture_private_root="$(mktemp -d "${TMPDIR:-/tmp}/playstead-notarization-capture.XXXXXX")"
  capture_cleanup() {
    if [ -n "$capture_publish_temp" ]; then
      rm -f "$capture_publish_temp"
    fi
    rm -rf "$capture_private_root"
  }
  trap capture_cleanup EXIT
  chmod 700 "$capture_private_root"
  mkdir -p "$capture_private_root/raw/evidence"

  local capture_raw_transcript="$capture_private_root/raw/evidence/notarization.log"
  local capture_sanitized_root="$capture_private_root/sanitized"
  local capture_wrapped_status

  set +e
  # Isolate errexit/exit from a captured shell function so it can abort its
  # proof normally while this outer capture frame still sanitizes the record.
  ( set -e; "$@" ) >"$capture_raw_transcript" 2>&1
  capture_wrapped_status=$?
  set -e

  if ! "$capture_sanitizer" --input "$capture_private_root/raw" --output "$capture_sanitized_root" \
    >"$capture_private_root/sanitizer.stdout" 2>"$capture_private_root/sanitizer.stderr"; then
    printf 'capture-notarization-evidence: FATAL: EVIDENCE_SANITIZATION_FAILED\n' >&2
    exit 1
  fi

  local capture_sanitized_transcript="$capture_sanitized_root/notarization.log"
  local capture_manifest="$capture_sanitized_root/manifest.json"
  [ -f "$capture_sanitized_transcript" ] && [ ! -L "$capture_sanitized_transcript" ] && [ -s "$capture_sanitized_transcript" ] || \
    capture_die "sanitizer did not produce a regular, non-empty notarization transcript"
  [ -f "$capture_manifest" ] && [ ! -L "$capture_manifest" ] || capture_die "sanitizer did not produce a manifest"

  python3 - "$capture_manifest" "$capture_sanitized_transcript" <<'PY'
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

  capture_publish_temp="$(mktemp "${capture_output_parent}/.${capture_output_basename}.tmp.XXXXXX")"
  chmod 600 "$capture_publish_temp"
  cp "$capture_sanitized_transcript" "$capture_publish_temp"

  [ ! -L "$capture_output_path" ] || capture_die "symlink output file is forbidden"
  [ ! -d "$capture_output_path" ] || capture_die "output file must not be a directory"
  mv -f "$capture_publish_temp" "$capture_output_path"
  capture_publish_temp=""

  exit "$capture_wrapped_status"
)

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  [ "$#" -ge 4 ] || {
    printf 'capture-notarization-evidence: usage: capture-notarization-evidence.sh --output FILE -- COMMAND [ARG ...]\n' >&2
    exit 1
  }
  [ "$1" = "--output" ] || {
    printf 'capture-notarization-evidence: first argument must be --output\n' >&2
    exit 1
  }
  capture_cli_output="$2"
  [ "$3" = "--" ] || {
    printf 'capture-notarization-evidence: third argument must be --\n' >&2
    exit 1
  }
  shift 3
  [ "$#" -gt 0 ] || {
    printf 'capture-notarization-evidence: a command is required after --\n' >&2
    exit 1
  }
  capture_notarization_evidence "$capture_cli_output" "$@"
fi
