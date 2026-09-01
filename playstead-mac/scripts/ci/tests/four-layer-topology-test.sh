#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
REPO_ROOT="$(cd "${MAC_ROOT}/.." && pwd)"
RUNNER="${MAC_ROOT}/scripts/ci/run-mac-verification.sh"
SCHEME="${MAC_ROOT}/Playstead.xcodeproj/xcshareddata/xcschemes/Playstead.xcscheme"
APP_ENTRY="${MAC_ROOT}/Playstead/App/PlaysteadApp.swift"
PROFILE_TEST="${MAC_ROOT}/PlaysteadTests/SnapshotTests/DeterministicProfileTests.swift"
UI_CANARY="${MAC_ROOT}/PlaysteadUITests/HostedRunnerCanaryTests.swift"
CURATION_TEST="${MAC_ROOT}/PlaysteadUITests/CurationInteractionTests.swift"
UI_BOOTSTRAP="${MAC_ROOT}/Playstead/UITesting/UITestBootstrap.swift"
STORAGE_TEST="${MAC_ROOT}/PlaysteadUITests/StorageInteractionTests.swift"
GAME_ROW="${MAC_ROOT}/Playstead/Library/GameRowView.swift"
RECLAIM_VIEW="${MAC_ROOT}/Playstead/Library/ReclaimPromptView.swift"
STORAGE_VIEW="${MAC_ROOT}/Playstead/Library/StorageView.swift"
WORKFLOW="${REPO_ROOT}/.github/workflows/ci.yml"
REFRESH_WORKFLOW="${REPO_ROOT}/.github/workflows/mac-snapshot-refresh.yml"
SANITIZER="${MAC_ROOT}/scripts/ci/sanitize-evidence.sh"
PROMPT_SAFETY="${MAC_ROOT}/scripts/ci/tests/keychain-prompt-safety-test.sh"
KEYBOARD_CLEANUP="${MAC_ROOT}/scripts/ci/tests/keyboard-mode-cleanup-test.sh"
SWIFT_SEMANTIC="${MAC_ROOT}/scripts/ci/tests/wave6-swift-semantic-test.sh"

for file in "$RUNNER" "$SCHEME" "$APP_ENTRY" "$PROFILE_TEST" "$UI_CANARY" "$CURATION_TEST" "$UI_BOOTSTRAP" "$STORAGE_TEST" "$GAME_ROW" "$RECLAIM_VIEW" "$STORAGE_VIEW" "$WORKFLOW" "$REFRESH_WORKFLOW" "$SANITIZER" "$PROMPT_SAFETY" "$KEYBOARD_CLEANUP" "$SWIFT_SEMANTIC"; do
  [ -f "$file" ] || { printf 'four-layer topology file missing: %s\n' "$file" >&2; exit 1; }
done
for plan in Unit Rendering UI LiveServer; do
  [ -f "${MAC_ROOT}/TestPlans/${plan}.xctestplan" ] || {
    printf 'test plan missing: %s\n' "$plan" >&2
    exit 1
  }
  grep -F "container:TestPlans/${plan}.xctestplan" "$SCHEME" >/dev/null || {
    printf 'scheme is not associated with test plan: %s\n' "$plan" >&2
    exit 1
  }
done

python3 - "${MAC_ROOT}/TestPlans" "$APP_ENTRY" "$RUNNER" <<'PY'
import json, pathlib, re, sys

plans_root = pathlib.Path(sys.argv[1])
app_source = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
runner_source = pathlib.Path(sys.argv[3]).read_text(encoding="utf-8")
plans = {name: json.loads((plans_root / f"{name}.xctestplan").read_text()) for name in ("Unit", "Rendering", "UI", "LiveServer")}
for name, plan in plans.items():
    if plan.get("version") != 1 or not plan.get("testTargets"):
        raise SystemExit(f"{name}: malformed or empty test plan")
    if any(target.get("parallelizable") is not False for target in plan["testTargets"]):
        raise SystemExit(f"{name}: hosted test layers must be serial")

selected = {}
for name in ("Rendering", "UI", "LiveServer"):
    selected[name] = {
        (target["target"]["name"], test)
        for target in plans[name]["testTargets"]
        for test in target.get("selectedTests", [])
    }
    if not selected[name]:
        raise SystemExit(f"{name}: selected-test ownership is empty")
names = tuple(selected)
for index, left in enumerate(names):
    for right in names[index + 1:]:
        overlap = selected[left] & selected[right]
        if overlap:
            raise SystemExit(f"test ownership overlaps between {left} and {right}: {sorted(overlap)}")

unit_skipped = set(plans["Unit"]["testTargets"][0].get("skippedTests", []))
if "StorageContractSnapshotTests" not in unit_skipped:
    raise SystemExit("storage snapshots must be excluded from the broad Unit plan")
if "StorageContractSnapshotTests" not in {test for _, test in selected["Rendering"]}:
    raise SystemExit("storage snapshot discovery is missing from Rendering")
ui_selected = {test for _, test in selected["UI"]}
for required_ui_class in ("CurationInteractionTests", "StorageInteractionTests"):
    if required_ui_class not in ui_selected:
        raise SystemExit(f"Wave 6 UI discovery is missing: {required_ui_class}")

app_decl = app_source.split("struct PlaysteadApp: App", 1)[1].split("private struct ProductionRootView", 1)[0]
if "AppEnvironment(" in app_decl:
    raise SystemExit("PlaysteadApp must not eagerly construct production dependencies in a hosted canary launch")

four_layer = runner_source.split("run_four_layer_verification() {", 1)[1].split("run_snapshot_candidates() {", 1)[0]
markers = [
    "run_test_layer unit Unit",
    "run_test_layer rendering Rendering",
    "run_test_layer ui UI",
    "run_test_layer live-server LiveServer",
    'if [ "$aggregate" -ne 0 ]',
    'sanitize-evidence.sh" --input "$FOUR_LAYER_ROOT"',
]
positions = [four_layer.rfind(marker) for marker in markers]
if any(position < 0 for position in positions) or positions != sorted(positions):
    raise SystemExit("four layers and failure sanitization must run in serial order without short-circuiting")
if four_layer.count("build-for-testing") != 1 or four_layer.count("run_test_layer ") != 4:
    raise SystemExit("four-layer runner must build exactly once and invoke exactly four layers")
deadline_pairs = re.findall(
    r"^\s*run_test_layer (unit|rendering|ui|live-server)\s+\S+\s+(\d+)\s+\\$",
    four_layer,
    flags=re.MULTILINE,
)
deadlines = {layer: int(seconds) for layer, seconds in deadline_pairs}
expected_deadlines = {"unit": 900, "rendering": 600, "ui": 1800, "live-server": 900}
if len(deadline_pairs) != 4 or deadlines != expected_deadlines:
    raise SystemExit(f"four-layer deadlines drifted: {deadlines} != {expected_deadlines}")
if any(seconds <= 0 or seconds > 1800 for seconds in deadlines.values()):
    raise SystemExit("every hosted layer deadline must remain positive and bounded at 1800 seconds")
test_layer = runner_source.split("run_test_layer() {", 1)[1].split("run_four_layer_verification() {", 1)[0]
if test_layer.count("test-without-building") != 1 or "retry" in test_layer.lower():
    raise SystemExit("a layer must execute once without automatic retry")
PY

grep -F 'app.launchEnvironment["PLAYSTEAD_WAVE_0_LAUNCH_CANARY"] = "1"' "$UI_CANARY" >/dev/null
grep -F 'environment["PLAYSTEAD_WAVE_0_LAUNCH_CANARY"] == "1"' "$APP_ENTRY" >/dev/null
grep -F 'HostedRunnerLaunchCanaryView' "$APP_ENTRY" >/dev/null
grep -F 'CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=' "$RUNNER" >/dev/null
if grep -E '(^|[[:space:]])(security|codesign)([[:space:]]|$)' "$RUNNER" >/dev/null; then
  printf 'verification runner must not invoke security(1) or codesign(1)\n' >&2
  exit 1
fi

[ "$(grep -c 'run_test_layer .* Unit ' "$RUNNER")" -eq 1 ]
[ "$(grep -c 'run_test_layer .* Rendering ' "$RUNNER")" -eq 1 ]
[ "$(grep -c 'run_test_layer .* UI ' "$RUNNER")" -eq 1 ]
[ "$(grep -c 'run_test_layer .* LiveServer ' "$RUNNER")" -eq 1 ]
grep -F 'xcodebuild build-for-testing' "$RUNNER" >/dev/null
grep -F 'xcodebuild test-without-building' "$RUNNER" >/dev/null
grep -F '"automatic_retries": 0' "$RUNNER" >/dev/null
grep -F 'PLAYSTEAD_SNAPSHOT_RECORDING=0' "$RUNNER" >/dev/null
grep -F 'PLAYSTEAD_STORAGE_SNAPSHOT_CANDIDATE_OUTPUT="${FOUR_LAYER_EVIDENCE}/storage-candidate/storage-surfaces.actual.png"' "$RUNNER" >/dev/null
grep -F -- '--required-test PlaysteadTests.DeterministicProfileTests/testQuotaBlockReclaimProfileComputesExactProductionDecisionBeforeExternalIO' "$RUNNER" >/dev/null
python3 - "$RUNNER" <<'PY'
import pathlib, sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
unit = source.split("run_test_layer unit Unit", 1)[1].split("run_test_layer rendering Rendering", 1)[0]
rendering = source.split("run_test_layer rendering Rendering", 1)[1].split("run_test_layer ui UI", 1)[0]
required = "PlaysteadTests.DeterministicProfileTests/testQuotaBlockReclaimProfileComputesExactProductionDecisionBeforeExternalIO"
if required in unit or required not in rendering:
    raise SystemExit("quota decision contract must be required by Rendering and excluded from Unit")
PY
grep -F 'let attempt = await environment.attemptDownload(for: target)' "$PROFILE_TEST" >/dev/null
grep -F 'XCTAssertEqual(attempt, .blocked(expected))' "$PROFILE_TEST" >/dev/null
python3 - "$APP_ENTRY" <<'PY'
import pathlib, sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
attempt = source.split("func attemptDownload(for entry: CatalogueEntry)", 1)[1].split("func pendingDownloadBytes", 1)[0]
quota = attempt.find("let verdict = quotaVerdict(forDownloading: entry)")
credential = attempt.find("apiClientIfAvailable()")
if quota < 0 or credential < 0 or quota >= credential:
    raise SystemExit("local quota admission must precede credential and external-I/O admission")
PY
grep -F -- '--required-test PlaysteadTests.StorageContractSnapshotTests/testDownloadsQuotaReclaimAndStorageVisualContract' "$RUNNER" >/dev/null
grep -F -- '--required-test PlaysteadTests.StorageContractSnapshotTests/testStorageMotionAndReducedMotionContract' "$RUNNER" >/dev/null
for stage in \
  testCurationProfileBootstrapsLibrarySurface \
  testSidebarExposesAllFiveCurationDestinations \
  testContinueShelfRendersHonestEmptyFixture \
  testFavoritesShelfRootExists \
  testFavoritesShelfRendersExactSeededCard \
  testCollectionsShelfRootExists \
  testCollectionsShelfRendersExactSeededRoute \
  testQueueShelfRendersHonestEmptyFixture \
  testRecentShelfRendersHonestEmptyFixture \
  testCollectionDetailOpensExactSeededState \
  testCollectionDragTargetsOwnDistinctListCells \
  testCollectionMoveUpActionIsEnabledAndOwned \
  testCollectionMoveUpClickProducesOneEffect \
  testDragReorderProducesOneEffect \
  testDragReorderSurvivesRelaunch \
  testKeyboardReorderProducesOneEffectAndRetainsFocus \
  testKeyboardReorderSurvivesRelaunch \
  testKeyboardReorderRetainsFocusAndSurvivesRelaunch; do
  grep -F -- "--required-test PlaysteadUITests.CurationInteractionTests/${stage}" "$RUNNER" >/dev/null
done
if grep -E 'testFiveShelves(AndDurableDragReorder|RenderExactFixtures)|test(Favorites|Collections)ShelfRendersExactSeededFixture|testDragReorderProducesOneEffectAndSurvivesRelaunch' "$RUNNER" "$CURATION_TEST" >/dev/null; then
  printf 'broad curation UI identity must remain split into exact hosted stages\n' >&2
  exit 1
fi
grep -F 'withVelocity: XCUIGestureVelocity.slow' "$CURATION_TEST" >/dev/null
grep -F 'thenHoldForDuration: 1' "$CURATION_TEST" >/dev/null
grep -F 'harness.app.cells.containing(.any, identifier: identifier)' "$CURATION_TEST" >/dev/null
[ "$(grep -c 'harness.relaunch' "$CURATION_TEST")" -eq 4 ]
[ "$(grep -c '\.typeKey(.space' "$CURATION_TEST")" -eq 4 ]
if grep -F 'harness.app.typeKey(.space' "$CURATION_TEST" >/dev/null; then
  printf 'curation keyboard activation must target the already-focused exact button\n' >&2
  exit 1
fi
[ "$(grep -Fc 'testKeyboardMoveTargetReceivesFocus' "$CURATION_TEST")" -eq 1 ]
[ "$(grep -Fc 'testKeyboardMoveSpaceProducesOneEffect' "$CURATION_TEST")" -eq 1 ]
[ "$(grep -Fc 'testKeyboardMoveRetainsFocusAfterSettlement' "$CURATION_TEST")" -eq 1 ]
grep -F 'target.value(forKey: "hasKeyboardFocus") as? Bool == true' "$CURATION_TEST" >/dev/null
grep -F 'curation-keyboard-stage=focus-not-reached' "$CURATION_TEST" >/dev/null
if grep -F 'harness.focusContainedAction' "$CURATION_TEST" >/dev/null; then
  printf 'curation keyboard focus must use exact-target canary semantics\n' >&2
  exit 1
fi
[ "$(grep -Fc 'let keyboardMove = moveID(memberID(3), direction: "up")' "$CURATION_TEST")" -eq 1 ]
grep -F 'assertEnabled(true, element: button)' "$CURATION_TEST" >/dev/null
grep -F 'harness.element(collectionRowID, type: .button)' "$CURATION_TEST" >/dev/null
if grep -F 'try fixture.assertExactState()' "$UI_BOOTSTRAP" >/dev/null; then
  printf 'bootstrap must preserve makeFixture relaunch validation instead of requiring fresh positions\n' >&2
  exit 1
fi
for stage in \
  testDownloadsPauseResumeFlow \
  testQuotaEditAndFocusRestoration \
  testReclaimRouteSettlesToUniqueDownloadTrigger \
  testReclaimRouteKeyboardFocusOwnsUniqueDownloadTrigger \
  testReclaimRouteDirectActivationDispatchesQuotaEffect \
  testReclaimRouteActivationDispatchesQuotaEffect \
  testReclaimPromptPresentsProductionRoot \
  testReclaimPromptInitialStateIsExact \
  testReclaimPromptRowIdentityExists \
  testReclaimPromptRowValueIsExact \
  testReclaimPromptToggleBelongsToPrompt \
  testReclaimPromptSelectionTextTracksExactBytes \
  testReclaimPromptConfirmBecomesEnabled \
  testReclaimPromptActionsPassLiveAudit \
  testReclaimPromptConfirmRemovesExactEligibleBytes \
  testReclaimPromptPostMutationPreservesCanonicalRows \
  testStorageInventoryPresentsProductionRoot \
  testStorageInventoryRowIdentityExists \
  testStorageInventoryRowValueIsExact \
  testStorageInventoryToggleBelongsToSurface \
  testStorageInventorySelectionTracksExactBytes \
  testStorageInventoryConfirmBecomesEnabled \
  testStorageInventoryActionsPassLiveAudit \
  testStorageInventoryConfirmMutationRemovesOnlyEligibleCopy \
  testStorageInventoryPostMutationPreservesCanonicalRows \
  testStorageInventoryProtectsPinnedCopy; do
  grep -F -- "--required-test PlaysteadUITests.StorageInteractionTests/${stage}" "$RUNNER" >/dev/null
done
if grep -E 'testDownloadsQuotaReclaimAndStorageFlows|testReclaimPrompt(ShowsExactEligibleCandidate|SelectionTracksExactBytes|ConfirmationRemovesExactEligibleBytes)|testStorageInventory(ReclaimsOnlyEligibleCopies|ReclaimRemovesOnlyEligibleCopy)' "$RUNNER" "$STORAGE_TEST" >/dev/null; then
  printf 'broad storage UI identity must remain split into exact hosted stages\n' >&2
  exit 1
fi
grep -F 'static func downloadActionIdentifier(assetSetID: String) -> String' "$GAME_ROW" >/dev/null
grep -F '@FocusState private var downloadActionHasFocus: Bool' "$GAME_ROW" >/dev/null
grep -F '.focused($downloadActionHasFocus)' "$GAME_ROW" >/dev/null
grep -F '.accessibilityIdentifier(Self.downloadActionIdentifier(assetSetID: entry.id))' "$GAME_ROW" >/dev/null
grep -F 'playstead.game.00000000-0000-7000-8000-000000000042.download' "$STORAGE_TEST" >/dev/null
grep -F 'action.frame,' "$STORAGE_TEST" >/dev/null
grep -F 'exactIdentity.frame,' "$STORAGE_TEST" >/dev/null
grep -F 'for _ in 0..<64 {' "$STORAGE_TEST" >/dev/null
grep -F 'target.typeKey(.space, modifierFlags: [])' "$STORAGE_TEST" >/dev/null
if grep -F 'harness.app.typeKey(.space' "$STORAGE_TEST" >/dev/null; then
  printf 'storage keyboard activation must target the already-focused exact button\n' >&2
  exit 1
fi
python3 - "$GAME_ROW" <<'PY'
import pathlib, sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
download = source.split('Button("Download")', 1)[1].split('case .downloading:', 1)[0]
focused = download.find(".focused($downloadActionHasFocus)")
identified = download.find(".accessibilityIdentifier(Self.downloadActionIdentifier(assetSetID: entry.id))")
ring = download.find("PlaysteadFocusRing.opacity(isFocused: downloadActionHasFocus)")
if min(focused, identified, ring) < 0 or not focused < identified < ring:
    raise SystemExit("Download must bind row-owned focus, exact AX identity, and its visible ring on one Button")
if ".focusable()" in download or ".playsteadFocusable(" in download:
    raise SystemExit("Download must not create a modifier-owned or duplicate focus participant inside List")
PY
python3 - "$RECLAIM_VIEW" "$STORAGE_VIEW" <<'PY'
import pathlib, sys

for path in map(pathlib.Path, sys.argv[1:]):
    source = path.read_text(encoding="utf-8")
    action = source.split('Button("Reclaim selected") {', 1)[1].split('}', 1)[0]
    markers = [action.find("let selection = selected"), action.find("selected.removeAll()"), action.find("onReclaim(selection)")]
    if any(marker < 0 for marker in markers) or markers != sorted(markers):
        raise SystemExit(f"{path.name}: reclaim must snapshot, clear stale selection, then invoke its effect")
    if source.count(".accessibilityElement(children: .contain)") != 1:
        raise SystemExit(f"{path.name}: only the surface root may be an accessibility container")
    if ".accessibilityIdentifier(Automation.candidate(slot))" not in source:
        raise SystemExit(f"{path.name}: candidate title is missing its stable row identity")
    if ".playsteadFocusable(identifier: Automation.candidateToggle(slot))" not in source:
        raise SystemExit(f"{path.name}: candidate select control is missing its independent identity")
    if path == pathlib.Path(sys.argv[1]) and ".focusSection()" in source:
        raise SystemExit("ReclaimPromptView: nested focus section must not rewrite the sheet accessibility subtree")
print("storage selection reset contract: passed")
PY
grep -F 'VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm)' "$STORAGE_VIEW" >/dev/null
grep -F '.padding(DesignTokens.Spacing.sm)' "$STORAGE_VIEW" >/dev/null
grep -F '.frame(minHeight: DesignTokens.InteractiveTarget.minimum)' "$STORAGE_VIEW" >/dev/null
grep -F 'if: failure()' "$WORKFLOW" >/dev/null
grep -F 'path: playstead-mac/.build/ci/failure-evidence' "$WORKFLOW" >/dev/null
grep -F 'retention-days: 7' "$WORKFLOW" >/dev/null
if grep -E 'path: .*\.(xcresult)|path: .*DerivedData' "$WORKFLOW" >/dev/null; then
  printf 'CI upload paths must exclude raw xcresults and DerivedData\n' >&2
  exit 1
fi

grep -F 'workflow_dispatch:' "$REFRESH_WORKFLOW" >/dev/null
grep -F 'contents: read' "$REFRESH_WORKFLOW" >/dev/null
grep -F 'runs-on: macos-26' "$REFRESH_WORKFLOW" >/dev/null
grep -F 'DEVELOPER_DIR: /Applications/Xcode_26.6.app/Contents/Developer' "$REFRESH_WORKFLOW" >/dev/null
grep -F -- '--run-snapshot-candidates' "$REFRESH_WORKFLOW" >/dev/null
grep -F 'macos-26-xcode-26.6-snapshot-candidates' "$REFRESH_WORKFLOW" >/dev/null
if grep -E 'contents: write|git (commit|push)|--record|recordMode.*all|PLAYSTEAD_SNAPSHOT_RECORDING=1' "$REFRESH_WORKFLOW" >/dev/null; then
  printf 'snapshot refresh must be read-only and candidate-only\n' >&2
  exit 1
fi

grep -F 'max_files = 40' "$SANITIZER" >/dev/null
grep -F 'max_total = 12 * 1024 * 1024' "$SANITIZER" >/dev/null
grep -F 'max_storage_candidate = 8 * 1024 * 1024' "$SANITIZER" >/dev/null
grep -F 'storage-candidate/storage-surfaces.actual.png' "$SANITIZER" >/dev/null
grep -F '(width, height) != (5760, 3040)' "$SANITIZER" >/dev/null
grep -F 'snapshot-triplet' "$SANITIZER" >/dev/null
grep -F 'environment-fingerprint.json' "$SANITIZER" >/dev/null
grep -F '"failed_tests": all_failed[:max_failed_tests]' "$RUNNER" >/dev/null
grep -F '"audit_issues": [dict(fields) for fields in all_audit_issues[:max_audit_issues]]' "$RUNNER" >/dev/null
grep -F 'len(failed) > 50' "$SANITIZER" >/dev/null
grep -F 'len(audit_issues) > 50' "$SANITIZER" >/dev/null
grep -F '{"identifier", "outcome"}' "$SANITIZER" >/dev/null
grep -F '{"test_identifier", "category", "element_identifier", "element_role"}' "$SANITIZER" >/dev/null

"$PROMPT_SAFETY"
bash "$KEYBOARD_CLEANUP"
bash "$SWIFT_SEMANTIC"

printf 'four-layer topology contract: passed\n'
