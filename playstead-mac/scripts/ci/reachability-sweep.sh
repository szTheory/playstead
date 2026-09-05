#!/usr/bin/env bash
# Reachability sweep — find production symbols that are defined and tested but
# never reached from production code.
#
# Phase 04 shipped four safety features that were fully built, fully unit-tested,
# and unreachable from the app: the launch save-restore planner, the D-40
# only-copy modal, the divergence badge, and the readiness Save row. Every one
# passed its tests, because every test constructed the component directly rather
# than driving the path a user takes. Greps and unit runs verify that a component
# EXISTS and BEHAVES; neither can see whether anything reaches it.
#
# This script closes that specific blind spot: for each type and top-level
# function declared under a production source root, it counts references from
# OTHER production files. Zero references means the symbol is reachable only from
# tests — which is either dead code or, far worse, a feature the user can never
# get to.
#
# It is deliberately a heuristic and deliberately non-blocking by default. Swift
# and Elixir both have reflective and protocol-driven call paths a grep cannot
# see, so a finding here is a question ("who calls this?"), not a verdict. Run
# with --strict to exit non-zero on findings, once a baseline is clean.
#
# Usage:
#   scripts/ci/reachability-sweep.sh [--strict] [--allowlist FILE]

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
STRICT=0
ALLOWLIST="${REPO_ROOT}/playstead-mac/scripts/ci/reachability-allowlist.txt"

while [ $# -gt 0 ]; do
  case "$1" in
    --strict) STRICT=1; shift ;;
    --allowlist) ALLOWLIST="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# Production roots only. Test trees are what we are measuring reachability
# AGAINST, so they must never count as a reference.
SWIFT_SRC="${REPO_ROOT}/playstead-mac/Playstead"
ELIXIR_SRC="${REPO_ROOT}/playstead-server/lib"

findings=0
tmp_report="$(mktemp "${TMPDIR:-/tmp}/reachability-XXXXXX")"

is_allowlisted() {
  [ -f "$ALLOWLIST" ] || return 1
  grep -qxF "$1" "$ALLOWLIST" 2>/dev/null
}

# --- Swift ------------------------------------------------------------------
# Declarations of types and top-level funcs. SwiftUI View bodies, protocol
# witnesses and @main entry points are legitimately "uncalled" by grep, so the
# allowlist carries those rather than the script special-casing them.
sweep_swift() {
  [ -d "$SWIFT_SRC" ] || return 0
  while IFS= read -r file; do
    # Skip the UI-testing harness: it exists to drive surfaces directly and is
    # not production reachability.
    case "$file" in *"/UITesting/"*) continue ;; esac

    while IFS= read -r symbol; do
      [ -n "$symbol" ] || continue
      is_allowlisted "$symbol" && continue
      # Count references anywhere in production Swift EXCEPT the declaring file.
      refs=$(grep -rlw "$symbol" "$SWIFT_SRC" 2>/dev/null \
             | grep -v "^${file}$" \
             | grep -v "/UITesting/" \
             | wc -l | tr -d ' ')
      if [ "$refs" = "0" ]; then
        printf '  %-44s %s\n' "$symbol" "${file#$REPO_ROOT/}" >> "$tmp_report"
        findings=$((findings + 1))
      fi
    done < <(grep -hoE '^(public |internal |private |fileprivate )?(final )?(struct|enum|class|actor) [A-Z][A-Za-z0-9_]*' "$file" 2>/dev/null \
             | awk '{print $NF}' | sort -u)
  done < <(find "$SWIFT_SRC" -name '*.swift' -type f 2>/dev/null)
}

# --- Elixir -----------------------------------------------------------------
# Public functions in lib/. Phoenix controllers/LiveViews are dispatched by the
# router rather than called, so those modules ride the allowlist.
sweep_elixir() {
  [ -d "$ELIXIR_SRC" ] || return 0
  while IFS= read -r file; do
    case "$file" in
      *"_web/controllers/"*|*"_web/live/"*|*"_web/components/"*|*"/router.ex") continue ;;
    esac
    while IFS= read -r symbol; do
      [ -n "$symbol" ] || continue
      is_allowlisted "$symbol" && continue
      refs=$(grep -rlw "$symbol" "$ELIXIR_SRC" 2>/dev/null | grep -v "^${file}$" | wc -l | tr -d ' ')
      if [ "$refs" = "0" ]; then
        printf '  %-44s %s\n' "$symbol" "${file#$REPO_ROOT/}" >> "$tmp_report"
        findings=$((findings + 1))
      fi
    done < <(grep -hoE '^  def [a-z_][A-Za-z0-9_?!]*' "$file" 2>/dev/null \
             | awk '{print $2}' | sort -u)
  done < <(find "$ELIXIR_SRC" -name '*.ex' -type f 2>/dev/null)
}

echo "Reachability sweep — production symbols with no production caller"
echo

sweep_swift
sweep_elixir

if [ "$findings" -eq 0 ]; then
  echo "✓ No unreachable production symbols found."
  rm -f "$tmp_report"
  exit 0
fi

echo "Found ${findings} symbol(s) referenced only from tests (or not at all):"
echo
sort "$tmp_report"
rm -f "$tmp_report"
echo
echo "Each is one of three things:"
echo "  1. A feature the user cannot reach   <- the Phase 04 defect class, fix the wiring"
echo "  2. Dead code                          <- delete it"
echo "  3. A reflective/dispatched call path  <- add it to $(basename "$ALLOWLIST") with a reason"
echo

if [ "$STRICT" -eq 1 ]; then
  echo "--strict: failing." >&2
  exit 1
fi
echo "(advisory; pass --strict to fail the build once a baseline is clean)"
exit 0
