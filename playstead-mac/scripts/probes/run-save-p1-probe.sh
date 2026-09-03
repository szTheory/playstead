#!/usr/bin/env bash
# Runs Probe SAVE-P1 (D-02) and writes its JSON report to the pinned phase-4
# evidence artifact. Thin wrapper only — all measurement logic lives in
# save-p1-probe.swift; this script never touches save bytes itself.
#
# Usage: run-save-p1-probe.sh [--mgba-artifact <path>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPO_ROOT="$(cd "${MAC_ROOT}/.." && pwd)"

PROBE_SWIFT="${SCRIPT_DIR}/save-p1-probe.swift"
REPORT_JSON="${REPO_ROOT}/.planning/phases/04-persistent-save-continuity/04-SAVE-P1-REPORT.json"

die() {
  printf 'run-save-p1-probe: %s\n' "$*" >&2
  exit 1
}

[ -f "$PROBE_SWIFT" ] || die "probe script not found at $PROBE_SWIFT"

mkdir -p "$(dirname "$REPORT_JSON")"

swift "$PROBE_SWIFT" "$@" > "$REPORT_JSON"

printf 'run-save-p1-probe: wrote %s\n' "$REPORT_JSON" >&2
