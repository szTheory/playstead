#!/usr/bin/env bash
# Proves the live-server layer's PairingCeremonyTests promotion fails closed:
# a failed, skipped, or never-discovered ceremony node must make
# --verify-layer-result exit non-zero, not just be assertable by reading
# source. Each property below gets its own distinct failure line so a CI
# failure's file:line names which of the five broke (T-04.5-07).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFIER="${SCRIPT_DIR}/../run-mac-verification.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/playstead-pairing-ceremony-gate.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

CEREMONY_IDENTIFIER="PlaysteadUITests.PairingCeremonyTests/testAHumanCanPairAFreshMacEntirelyFromInsideTheAppAgainstTheRealServer"

REQUIRED_TESTS=(
  --required-test PlaysteadUITests.HostedRunnerCanaryTests/testAdHocSignedAppLaunchesOnHostedRunner
  --required-test PlaysteadUITests.LiveServerSnapshotTests/testPairedFreshMirrorRendersSnapshotBeforeAnyBlobDownloadAndPersistsKeychainAcrossRelaunch
  --required-test PlaysteadUITests.SaveRestoreProofTests/testCapturedRevisionRestoresToByteIdenticalArtifactInLaunchDir
  --required-test PlaysteadUITests.SaveEndToEndTests/testOneSaveRoundTripsCaptureUploadAndJournalReturn
  --required-test "$CEREMONY_IDENTIFIER"
)

write_fixture() {
  # $1 = output path, $2 = ceremony node result ("Passed"/"Failed"/"Skipped"),
  # $3 = "true"/"false" whether the ceremony node is present at all.
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
path, ceremony_result, include_ceremony = sys.argv[1:]
include_ceremony = include_ceremony == "true"

def case(node_identifier):
    return {
        "nodeType": "Test Case",
        "nodeIdentifier": node_identifier,
        "name": node_identifier,
        "result": "Passed",
    }

nodes = [
    case("HostedRunnerCanaryTests/testAdHocSignedAppLaunchesOnHostedRunner()"),
    case("LiveServerSnapshotTests/testPairedFreshMirrorRendersSnapshotBeforeAnyBlobDownloadAndPersistsKeychainAcrossRelaunch()"),
    case("SaveRestoreProofTests/testCapturedRevisionRestoresToByteIdenticalArtifactInLaunchDir()"),
    case("SaveEndToEndTests/testOneSaveRoundTripsCaptureUploadAndJournalReturn()"),
]
if include_ceremony:
    ceremony = case("PairingCeremonyTests/testAHumanCanPairAFreshMacEntirelyFromInsideTheAppAgainstTheRealServer()")
    ceremony["result"] = ceremony_result
    nodes.append(ceremony)

data = {
    "testPlanConfigurations": [],
    "devices": [],
    "testNodes": [{"nodeType": "Test Plan", "name": "LiveServer", "children": nodes}],
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle)
PY
}

# 1. All five required tests present and passed -> --verify-layer-result exits 0.
passing_fixture="$TMP_ROOT/passing.json"
write_fixture "$passing_fixture" Passed true
if ! "$VERIFIER" --verify-layer-result "$passing_fixture" live-server "$TMP_ROOT/passing-summary.json" \
    "${REQUIRED_TESTS[@]}" >"$TMP_ROOT/passing.out" 2>"$TMP_ROOT/passing.err"; then
  printf 'FAIL: a live-server result with all five required tests passed was rejected\n' >&2
  cat "$TMP_ROOT/passing.err" >&2
  exit 1
fi

# 2. Ceremony node present but failed -> exits non-zero.
failed_fixture="$TMP_ROOT/failed.json"
write_fixture "$failed_fixture" Failed true
if "$VERIFIER" --verify-layer-result "$failed_fixture" live-server "$TMP_ROOT/failed-summary.json" \
    "${REQUIRED_TESTS[@]}" >"$TMP_ROOT/failed.out" 2>"$TMP_ROOT/failed.err"; then
  printf 'FAIL: a failed pairing ceremony test did not fail --verify-layer-result\n' >&2
  exit 1
fi

# 3. Ceremony node present but skipped -> exits non-zero.
skipped_fixture="$TMP_ROOT/skipped.json"
write_fixture "$skipped_fixture" Skipped true
if "$VERIFIER" --verify-layer-result "$skipped_fixture" live-server "$TMP_ROOT/skipped-summary.json" \
    "${REQUIRED_TESTS[@]}" >"$TMP_ROOT/skipped.out" 2>"$TMP_ROOT/skipped.err"; then
  printf 'FAIL: a skipped pairing ceremony test did not fail --verify-layer-result\n' >&2
  exit 1
fi

# 4. Ceremony node absent entirely (never discovered) -> exits non-zero.
absent_fixture="$TMP_ROOT/absent.json"
write_fixture "$absent_fixture" Passed false
if "$VERIFIER" --verify-layer-result "$absent_fixture" live-server "$TMP_ROOT/absent-summary.json" \
    "${REQUIRED_TESTS[@]}" >"$TMP_ROOT/absent.out" 2>"$TMP_ROOT/absent.err"; then
  printf 'FAIL: an absent pairing ceremony test did not fail --verify-layer-result\n' >&2
  exit 1
fi

# 5. The ceremony identifier is anchored in the runner source at least twice
#    (the live-server layer invocation and the UAT allowlist anchor), so a
#    future edit that drops one of those anchors fails --self-test-contracts.
anchor_count="$(grep -v '^[[:space:]]*#' "$VERIFIER" | grep -c -F "$CEREMONY_IDENTIFIER" || true)"
if [ "$anchor_count" -lt 2 ]; then
  printf 'FAIL: pairing ceremony identifier is anchored fewer than twice in %s (found %s)\n' "$VERIFIER" "$anchor_count" >&2
  exit 1
fi

printf 'pairing-ceremony-gate: pass/failed/skipped/absent/anchor-count checks all passed\n'
