#!/usr/bin/env bash
# `.defaultFocus` is not observed to place focus in this app.
#
# Phase 04 spent four CI round trips on one modal whose safe escape hatch never
# took focus. `.defaultFocus($x, true)` alone did nothing; setting it in
# `onAppear` fixed a harness root view but not the real `.sheet`, whose window
# is not yet key when `onAppear` runs. The only pattern here observed to work in
# CI hops one runloop first (CollectionDetailView.restoreMemberListFocus).
#
# So every `.defaultFocus` in production must be backed by that hop. This is a
# keyboard-accessibility contract, not a style rule: without it a modal opens
# with no focused control and no visible ring, and D-40's "the easiest button is
# the one that saves the user's progress" silently does not hold.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
detector="${SCRIPT_DIR}/sheet-focus-detector.py"

python3 "$detector" "${MAC_ROOT}/Playstead" || exit 1

# Negative control: the shape that shipped broken must still be rejected.
fixture="$(mktemp -d "${TMPDIR:-/tmp}/playstead-sheet-focus.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
cat >"$fixture/BadSheet.swift" <<'SWIFT'
import SwiftUI
struct BadSheet: View {
    @FocusState private var doneHasFocus: Bool
    var body: some View {
        Button("Done") {}
            .focused($doneHasFocus)
            .defaultFocus($doneHasFocus, true)
    }
}
SWIFT
if python3 "$detector" "$fixture" >/dev/null 2>&1; then
  printf 'sheet-focus detector accepted a bare .defaultFocus\n' >&2
  exit 1
fi

# ...and the fixed shape must be accepted, or the guard is unsatisfiable.
cat >"$fixture/BadSheet.swift" <<'SWIFT'
import SwiftUI
struct GoodSheet: View {
    @FocusState private var doneHasFocus: Bool
    var body: some View {
        Button("Done") {}
            .focused($doneHasFocus)
            .defaultFocus($doneHasFocus, true)
            .onAppear { placeInitialFocus() }
    }
    private func placeInitialFocus() {
        Task { @MainActor in
            await Task.yield()
            doneHasFocus = true
        }
    }
}
SWIFT
python3 "$detector" "$fixture" >/dev/null || {
  printf 'sheet-focus detector rejected the prescribed fix\n' >&2
  exit 1
}

printf 'sheet focus placement contract: passed\n'
