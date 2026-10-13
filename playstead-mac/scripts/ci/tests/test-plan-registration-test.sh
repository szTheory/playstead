#!/usr/bin/env bash
# A test no plan runs is a test that does not exist.
#
# The UI and Rendering plans enumerate `selectedTests` by name, so a newly added
# suite is invisible by default -- it compiles, it reads as registered, and it
# never executes. Phase 04 is the cautionary case: the whole UI layer sat
# deferred behind 583 green unit tests, and its first real execution found five
# production defects across three suites at once.
#
# This guard makes that impossible to repeat quietly: every `func test...` on
# disk must be selected by some plan, or be listed with a reason in
# TestPlans/unregistered-allowlist.txt.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
detector="${SCRIPT_DIR}/test-plan-registration-detector.py"

python3 "$detector" "$MAC_ROOT" || exit 1

fixture="$(mktemp -d "${TMPDIR:-/tmp}/playstead-plan-reg.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/TestPlans" "$fixture/PlaysteadTests" "$fixture/PlaysteadUITests"
cat >"$fixture/TestPlans/UI.xctestplan" <<'JSON'
{ "configurations": [], "defaultOptions": {}, "testTargets": [
  { "selectedTests": ["RegisteredTests"],
    "target": { "containerPath": "container:X.xcodeproj", "identifier": "1", "name": "PlaysteadUITests" } },
  { "target": { "containerPath": "container:X.xcodeproj", "identifier": "2", "name": "PlaysteadTests" } }
], "version": 1 }
JSON
cat >"$fixture/PlaysteadTests/RegisteredUnitTests.swift" <<'SWIFT'
import XCTest
final class RegisteredUnitTests: XCTestCase {
    func testSomething() {}
}
SWIFT
cat >"$fixture/PlaysteadUITests/RegisteredTests.swift" <<'SWIFT'
import XCTest
final class RegisteredTests: XCTestCase {
    func testRegistered() {}
}
SWIFT

# Baseline: a fully registered fixture must pass, or the guard is unsatisfiable.
python3 "$detector" "$fixture" >/dev/null || {
  printf 'registration detector rejected a fully registered fixture\n' >&2
  exit 1
}

# Negative control 1: a suite no plan names must be rejected.
cat >"$fixture/PlaysteadUITests/OrphanTests.swift" <<'SWIFT'
import XCTest
final class OrphanTests: XCTestCase {
    func testNobodyRunsMe() {}
}
SWIFT
if python3 "$detector" "$fixture" >/dev/null 2>&1; then
  printf 'registration detector accepted a suite no plan runs\n' >&2
  exit 1
fi

# ...and the allowlist must be the only way to silence it.
printf 'PlaysteadUITests/OrphanTests/testNobodyRunsMe()  # deliberate\n' \
  >"$fixture/TestPlans/unregistered-allowlist.txt"
python3 "$detector" "$fixture" >/dev/null || {
  printf 'registration detector ignored its own allowlist\n' >&2
  exit 1
}

# Negative control 2: an empty sweep must fail rather than report clean.
rm -rf "$fixture/PlaysteadUITests" && mkdir -p "$fixture/PlaysteadUITests"
if python3 "$detector" "$fixture" >/dev/null 2>&1; then
  printf 'registration detector reported clean on an empty target\n' >&2
  exit 1
fi

# The ordinary UI plan and its required-result manifest must name the exact
# regressions. The general registration detector permits broad class entries,
# so this contract also rejects that mutation and any skip/exclusion.
python3 - "$MAC_ROOT" "$fixture" <<'PY'
import copy, json, pathlib, sys

root, fixture = map(pathlib.Path, sys.argv[1:])
runner = root / "scripts/ci/run-mac-verification.sh"
source = runner.read_text(encoding="utf-8")
plan = json.loads((root / "TestPlans/UI.xctestplan").read_text(encoding="utf-8"))
tests = (
    "ControllerDpadRegressionTests/testControllerTestDpadUpStaysInSettingsAndSettingsReopensAtStorage()",
    "ControllerRecoveryBannerGeometryTests/testRecoveryBannerGeometryAcrossWindowSizesAndAppearances()",
    "ControllerNoHIDIntegrationTests/testRecoveryNoticeKeyboardDismissalPreservesFocusAndBrowsing()",
    "ControllerNoHIDIntegrationTests/testRecoveryNoticeControllerNavigationDismissesAndReturnsToBrowsing()",
    "ControllerNoHIDIntegrationTests/testRecoveryNoticeAccessibilityContractAndDismissalPreservesState()",
    "MetadataConsentUITests/testMetadataSettingsRemainInsideSettingsAndShowIndependentCacheBudget()",
    "MetadataConsentUITests/testConsentPreviewRequiresASelectedGameAndUnpairedProfileNeverEnablesProvider()",
    "MetadataCorrectionUITests/testCorrectionFormShowsPerFieldSourceAndOnlyExplicitSaveAction()",
    "MetadataCorrectionUITests/testSavingCorrectionUpdatesTheLocalMirrorBeforeServerDelivery()",

)
ordinary = source[source.index("run_four_layer_verification() {"):source.index("\nrun_snapshot_candidates() {", source.index("run_four_layer_verification() {"))]
ui_call = ordinary[ordinary.index("run_test_layer ui UI"):ordinary.index("\n  [ \"$LAYER_STATUS\"", ordinary.index("run_test_layer ui UI"))]
for test in tests:
    required = "PlaysteadUITests." + test.removesuffix("()")
    if ui_call.count("--required-test " + required) != 1:
        raise SystemExit(f"ordinary UI evidence does not require the exact identifier: {test}")

def selected_exactly_once(changed, test):
    targets = [
        target for target in changed.get("testTargets", [])
        if target.get("target", {}).get("name") == "PlaysteadUITests"
    ]
    if len(targets) != 1:
        return False
    target = targets[0]
    selected = target.get("selectedTests", [])
    skipped = target.get("skippedTests", [])
    test_class = test.split("/", 1)[0]
    return (
        selected.count(test) == 1
        and test_class not in selected
        and not set(skipped).intersection({
            test_class, test, test.removesuffix("()")
        })
    )

for test in tests:
    test_class = test.split("/", 1)[0]
    if not selected_exactly_once(plan, test):
        raise SystemExit(f"real ordinary UI plan does not select the exact regression once: {test}")
    for name, mutate in (
        ("removed", lambda t: t["selectedTests"].remove(test)),
        ("broad-class", lambda t: (t["selectedTests"].remove(test), t["selectedTests"].append(test_class))),
        ("excluded", lambda t: t.setdefault("skippedTests", []).append(test)),
        ("class-excluded", lambda t: t.setdefault("skippedTests", []).append(test_class)),
    ):
        changed = copy.deepcopy(plan)
        target = next(t for t in changed["testTargets"] if t["target"]["name"] == "PlaysteadUITests")
        mutate(target)
        (fixture / "TestPlans/UI.xctestplan").write_text(json.dumps(changed), encoding="utf-8")
        if selected_exactly_once(json.loads((fixture / "TestPlans/UI.xctestplan").read_text(encoding="utf-8")), test):
            raise SystemExit(f"ordinary UI contract accepted {name} mutant: {test}")
    print(f"exact ordinary selection contract: passed — {test_class}")

live_test = "MetadataPrivateMediaJourneyTests/testPrivateMediaExportAndProviderDisclosureUsePairedProductionRoutes()"
live_plan = json.loads((root / "TestPlans/LiveServer.xctestplan").read_text(encoding="utf-8"))
live_call_start = ordinary.index("run_test_layer live-server LiveServer")
live_call_end = ordinary.index('\n  [ "$LAYER_STATUS"', live_call_start)
live_call = ordinary[live_call_start:live_call_end]
live_required = "PlaysteadUITests." + live_test.removesuffix("()")
if live_call.count("--required-test " + live_required) != 1:
    raise SystemExit(f"LiveServer evidence does not require the exact private-media selector: {live_test}")
if not selected_exactly_once(live_plan, live_test):
    raise SystemExit(f"LiveServer plan does not select the exact private-media selector once: {live_test}")
print("exact LiveServer selection contract: passed — MetadataPrivateMediaJourneyTests")
PY

# The result verifier must reject evidence with no executed regression case even
# when an unrelated case passed. These fixtures never launch the app.
python3 - "$MAC_ROOT" "$fixture" <<'PY'
import json, pathlib, subprocess, sys

root, fixture = map(pathlib.Path, sys.argv[1:])
runner = root / "scripts/ci/run-mac-verification.sh"
identifiers = (
    "ControllerDpadRegressionTests/testControllerTestDpadUpStaysInSettingsAndSettingsReopensAtStorage()",
    "ControllerRecoveryBannerGeometryTests/testRecoveryBannerGeometryAcrossWindowSizesAndAppearances()",
    "ControllerNoHIDIntegrationTests/testRecoveryNoticeKeyboardDismissalPreservesFocusAndBrowsing()",
    "ControllerNoHIDIntegrationTests/testRecoveryNoticeControllerNavigationDismissesAndReturnsToBrowsing()",
    "ControllerNoHIDIntegrationTests/testRecoveryNoticeAccessibilityContractAndDismissalPreservesState()",
    "MetadataConsentUITests/testMetadataSettingsRemainInsideSettingsAndShowIndependentCacheBudget()",
    "MetadataConsentUITests/testConsentPreviewRequiresASelectedGameAndUnpairedProfileNeverEnablesProvider()",
    "MetadataCorrectionUITests/testCorrectionFormShowsPerFieldSourceAndOnlyExplicitSaveAction()",
    "MetadataCorrectionUITests/testSavingCorrectionUpdatesTheLocalMirrorBeforeServerDelivery()",
    "MetadataPrivateMediaJourneyTests/testPrivateMediaExportAndProviderDisclosureUsePairedProductionRoutes()",

)
def check(name, nodes, expected):
    result = fixture / f"{name}.json"
    summary = fixture / f"{name}-summary.json"
    result.write_text(json.dumps({"testNodes": [{"nodeType": "Test Plan", "children": nodes}]}), encoding="utf-8")
    run = subprocess.run([str(runner), "--verify-layer-result", str(result), "ui", str(summary), "--required-test", required], capture_output=True, text=True)
    if (run.returncode == 0) != expected:
        raise SystemExit(f"result verifier accepted invalid {name} evidence: {identifier}" if not expected else f"result verifier rejected valid {name} evidence: {identifier}: {run.stderr}")
    if expected:
        record = json.loads(summary.read_text(encoding="utf-8"))["required_tests"][0]
        if record["identifier"] != identifier or record["execution_count"] != 1 or record["skipped"] or record["outcome"] != "passed":
            raise SystemExit(f"result evidence did not record one successful execution: {identifier}")

for identifier in identifiers:
    required = "PlaysteadUITests." + identifier.removesuffix("()")
    case = {"nodeType": "Test Case", "nodeIdentifier": identifier, "result": "Passed"}
    other = {"nodeType": "Test Case", "nodeIdentifier": "OtherTests/testUnrelated()", "result": "Passed"}
    check("passed", [case], True)
    check("missing", [other], False)
    check("skipped", [{**case, "result": "Skipped"}], False)
    check("zero-discovery", [], False)
    print(f"exact result evidence contract: passed — {identifier.split('/', 1)[0]}")
PY

printf 'test plan registration contract: passed\n'
