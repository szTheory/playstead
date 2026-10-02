#!/usr/bin/env bash
# Keep the native proof registered and its failure evidence behind the sanitizer.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAC_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPO_ROOT="$(cd "$MAC_ROOT/.." && pwd)"
runner="$SCRIPT_DIR/run-mac-verification.sh"
plan="$MAC_ROOT/TestPlans/LiveServer.xctestplan"
python3 - "$runner" "$plan" "$MAC_ROOT" "$SCRIPT_DIR/recovery-e2e.sh" <<'PY'
import json, pathlib, re, sys
runner=pathlib.Path(sys.argv[1]).read_text()
plan=json.loads(pathlib.Path(sys.argv[2]).read_text())
selected={test.removesuffix("()") for target in plan["testTargets"] for test in target.get("selectedTests", [])}
required={
 "PlaysteadUITests.LiveServerSnapshotTests/testPairedFreshMirrorRendersSnapshotBeforeAnyBlobDownloadAndPersistsKeychainAcrossRelaunch",
 "PlaysteadUITests.SaveEndToEndTests/testOneSaveRoundTripsCaptureUploadAndJournalReturn",
}
for identifier in required:
    short=identifier.removeprefix("PlaysteadUITests.")
    assert identifier in runner, f"required live-server argument missing: {identifier}"
    assert short in selected, f"LiveServer test plan selection missing: {short}"
assert '"$FOUR_LAYER_ROOT" --output "$FAILURE_EVIDENCE"' in runner
assert "run_test_layer live-server LiveServer" in runner
root=pathlib.Path(sys.argv[3])
recovery=json.loads((root/"TestPlans/Recovery.xctestplan").read_text())
private_test="RecoveryKnownPlayableTests/testPreparedRecoveryTargetLaunchesTheCleanMacAppAndRequestsPairing"
local_selected={test.removesuffix("()") for target in recovery["testTargets"] for test in target.get("selectedTests", [])}
assert private_test not in selected, "same-host private test must not run on hosted CI"
assert local_selected == {private_test}, "Recovery must select exactly the same-host journey"
assert all(not target["parallelizable"] for target in recovery["testTargets"])
scheme=(root/"Playstead.xcodeproj/xcshareddata/xcschemes/Playstead.xcscheme").read_text()
assert re.search(r'reference\s*=\s*"container:TestPlans/Recovery\.xctestplan"', scheme)
assert "-testPlan Recovery" in pathlib.Path(sys.argv[4]).read_text()
PY
echo "native recovery tests remain required and sanitizer-bound"
