#!/usr/bin/env bash
# Every client API path must be spelled from the server's mount point.
#
# `APIClient.send` does `credential.baseURL.appendingPathComponent(path)`, and
# the paired credential's baseURL is the server ORIGIN ("https://host:18443"),
# not an API root. So the caller owns the whole path, "/api/v1/..." included.
#
# SaveUploadLane got this wrong at both of its call sites -- "saves/uploads/..."
# and "saves/revisions" -- so every save upload 404'd, silently and forever, in
# the shipped app against a real server. Save capture worked; save *upload* had
# never worked. Found on 2026-09-08 by reading server logs during CP7-SAVE-C,
# not by any test.
#
# The rule is trivially checkable and the failure is invisible at runtime (a 404
# is swallowed into a retry), which is exactly the combination that earns a gate.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
detector="${SCRIPT_DIR}/api-path-detector.py"

python3 "$detector" "${MAC_ROOT}/Playstead" || exit 1

fixture="$(mktemp -d "${TMPDIR:-/tmp}/playstead-api-path.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT

# Negative control: the exact shape that shipped broken.
cat >"$fixture/BadClient.swift" <<'SWIFT'
import Foundation
func upload(_ apiClient: Any, _ commandID: String) async throws {
    _ = try await apiClient.send(
        method: "PUT",
        path: "saves/uploads/\(commandID)",
        body: Data()
    )
}
SWIFT
if python3 "$detector" "$fixture" >/dev/null 2>&1; then
  printf 'api-path detector accepted an unprefixed API path\n' >&2
  exit 1
fi

# ...and the fixed shape must pass, or the guard is unsatisfiable.
cat >"$fixture/BadClient.swift" <<'SWIFT'
import Foundation
func upload(_ apiClient: Any, _ commandID: String) async throws {
    _ = try await apiClient.send(
        method: "PUT",
        path: "/api/v1/saves/uploads/\(commandID)",
        body: Data()
    )
}
SWIFT
python3 "$detector" "$fixture" >/dev/null || {
  printf 'api-path detector rejected a correctly prefixed path\n' >&2
  exit 1
}

printf 'client API path prefix contract: passed\n'
