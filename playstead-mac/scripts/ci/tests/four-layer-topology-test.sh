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
COLLECTION_DETAIL="${MAC_ROOT}/Playstead/Curation/CollectionDetailView.swift"
UI_BOOTSTRAP="${MAC_ROOT}/Playstead/UITesting/UITestBootstrap.swift"
LIVE_SERVER_TEST="${MAC_ROOT}/PlaysteadUITests/LiveServerSnapshotTests.swift"
LIVE_SERVER_FIXTURE="${MAC_ROOT}/scripts/ci/live-server.sh"
MAC_CI_CONFIG="${REPO_ROOT}/playstead-server/config/mac_ci.exs"
STORAGE_TEST="${MAC_ROOT}/PlaysteadUITests/StorageInteractionTests.swift"
GAME_ROW="${MAC_ROOT}/Playstead/Library/GameRowView.swift"
LIBRARY_SHELL="${MAC_ROOT}/Playstead/Library/LibraryShellView.swift"
RECLAIM_VIEW="${MAC_ROOT}/Playstead/Library/ReclaimPromptView.swift"
STORAGE_VIEW="${MAC_ROOT}/Playstead/Library/StorageView.swift"
WORKFLOW="${REPO_ROOT}/.github/workflows/ci.yml"
REFRESH_WORKFLOW="${REPO_ROOT}/.github/workflows/mac-snapshot-refresh.yml"
SANITIZER="${MAC_ROOT}/scripts/ci/sanitize-evidence.sh"
PBXPROJ="${MAC_ROOT}/Playstead.xcodeproj/project.pbxproj"
UITEST_ENTITLEMENTS="${MAC_ROOT}/PlaysteadUITests/PlaysteadUITests.entitlements"
APP_ENTITLEMENTS="${MAC_ROOT}/Playstead/App/Playstead.entitlements"
PROMPT_SAFETY="${MAC_ROOT}/scripts/ci/tests/keychain-prompt-safety-test.sh"
KEYBOARD_CLEANUP="${MAC_ROOT}/scripts/ci/tests/keyboard-mode-cleanup-test.sh"
SWIFT_SEMANTIC="${MAC_ROOT}/scripts/ci/tests/wave6-swift-semantic-test.sh"

for file in "$RUNNER" "$SCHEME" "$APP_ENTRY" "$PROFILE_TEST" "$UI_CANARY" "$CURATION_TEST" "$COLLECTION_DETAIL" "$UI_BOOTSTRAP" "$LIVE_SERVER_TEST" "$LIVE_SERVER_FIXTURE" "$MAC_CI_CONFIG" "$STORAGE_TEST" "$GAME_ROW" "$LIBRARY_SHELL" "$RECLAIM_VIEW" "$STORAGE_VIEW" "$WORKFLOW" "$REFRESH_WORKFLOW" "$SANITIZER" "$PROMPT_SAFETY" "$KEYBOARD_CLEANUP" "$SWIFT_SEMANTIC"; do
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

live_targets = plans["LiveServer"]["testTargets"]
live_environment = {
    entry.get("key"): entry.get("value")
    for entry in plans["LiveServer"].get("defaultOptions", {}).get("environmentVariableEntries", [])
}
expected_live_environment = {
    key: f"$({key})" for key in (
        "PLAYSTEAD_MAC_CI_ROOT", "PLAYSTEAD_LIVE_SERVER_STAGE_ROOT",
        "PLAYSTEAD_LIVE_SERVER_STAGE_FILE", "MAC_CI_DATABASE_URL", "MIX_ENV", "PORT",
    )
}
if live_environment != expected_live_environment:
    raise SystemExit("LiveServer test plan must explicitly bridge the native service environment")
expected_live = {
    "HostedRunnerCanaryTests/testAdHocSignedAppLaunchesOnHostedRunner()",
    "LiveServerSnapshotTests/testPairedFreshMirrorRendersSnapshotBeforeAnyBlobDownloadAndPersistsKeychainAcrossRelaunch()",
}
if len(live_targets) != 1 or live_targets[0].get("parallelizable") is not False:
    raise SystemExit("LiveServer must remain one serial target")
if set(live_targets[0].get("selectedTests", [])) != expected_live:
    raise SystemExit("LiveServer must select exactly the launch canary and Plan 08 pairing proof")

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
native_start = four_layer.find("start_native_services")
live_layer = four_layer.find("run_test_layer live-server LiveServer")
native_cleanup = four_layer.find("cleanup_native_services", live_layer)
if not (0 <= native_start < live_layer < native_cleanup):
    raise SystemExit("native PostgreSQL/Phoenix must wrap only the LiveServer layer")
native_services = runner_source.split("start_native_services() {", 1)[1].split("run_four_layer_verification() {", 1)[0]
if 'NATIVE_ROOT="${FOUR_LAYER_RAW}/native-services"' not in native_services:
    raise SystemExit("native services must share the test-readable owned four-layer root")
if 'native service root already exists' not in native_services:
    raise SystemExit("native service root ownership must fail closed")
if "trap 'restore_live_server_xctestrun; cleanup_live_server_runtime_config; cleanup_native_services; restore_keyboard_mode' EXIT" not in four_layer:
    raise SystemExit("LiveServer xctestrun/config/native cleanup must preserve keyboard-mode restoration")
stage_preflight = four_layer.find("prepare_live_server_failure_stage")
if not (0 <= stage_preflight < live_layer):
    raise SystemExit("failure-stage channel must be cleared and validated before LiveServer")
xctestrun_materialize = four_layer.find("materialize_live_server_xctestrun")
xctestrun_restore = four_layer.find("restore_live_server_xctestrun", live_layer)
config_materialize = four_layer.find("materialize_live_server_runtime_config")
config_cleanup = four_layer.find("cleanup_live_server_runtime_config", live_layer)
if not (stage_preflight < config_materialize < xctestrun_materialize < live_layer < xctestrun_restore < config_cleanup < native_cleanup):
    raise SystemExit("generated LiveServer xctestrun must be materialized and restored around only its layer")
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
if 'test_selection=(-xctestrun "$LIVE_SERVER_XCTESTRUN")' not in test_layer:
    raise SystemExit("LiveServer must consume the exact generated xctestrun that received its concrete environment")
if 'live-server layer requires a materialized generated xctestrun' not in test_layer:
    raise SystemExit("LiveServer must fail closed before resolving an unpatched test configuration")
xctestrun_materializer = runner_source.split("materialize_live_server_xctestrun() {", 1)[1].split("restore_keyboard_mode() {", 1)[0]
if 'targets[0].setdefault("EnvironmentVariables", {})' not in xctestrun_materializer:
    raise SystemExit("LiveServer xctestrun must carry concrete scheme test-host environment")
if 'targets[0].setdefault("TestingEnvironmentVariables", {})' not in xctestrun_materializer:
    raise SystemExit("LiveServer xctestrun must carry concrete XCTest-host environment")
PY

grep -F 'app.launchEnvironment["PLAYSTEAD_WAVE_0_LAUNCH_CANARY"] = "1"' "$UI_CANARY" >/dev/null
grep -F 'environment["PLAYSTEAD_WAVE_0_LAUNCH_CANARY"] == "1"' "$APP_ENTRY" >/dev/null
grep -F 'HostedRunnerLaunchCanaryView' "$APP_ENTRY" >/dev/null
grep -F 'CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=' "$RUNNER" >/dev/null
grep -F 'server: System.get_env("PLAYSTEAD_MAC_CI_TASK") != "1"' "$MAC_CI_CONFIG" >/dev/null
[ "$(grep -c 'PLAYSTEAD_MAC_CI_TASK=1 mix playstead.mac_ci_fixture' "$LIVE_SERVER_FIXTURE")" -eq 3 ]
grep -F 'live-server fixture failed at %s' "$LIVE_SERVER_FIXTURE" >/dev/null
grep -F 'PLAYSTEAD_LIVE_SERVER_STAGE_FILE' "$LIVE_SERVER_FIXTURE" >/dev/null
grep -F 'resolved_parent" = "$resolved_root' "$LIVE_SERVER_FIXTURE" >/dev/null
grep -F 'live-server: FAILURE_STAGE %s' "$RUNNER" >/dev/null
grep -F 'prepare_live_server_failure_stage' "$RUNNER" >/dev/null
grep -F 'PLAYSTEAD_LIVE_SERVER_STAGE_FILE="$server_root/live-server-failure-stage"' "$RUNNER" >/dev/null
[ "$(grep -c 'guard fixtureEnvironmentIsReady() else { return }' "$LIVE_SERVER_TEST")" -eq 1 ]
for key in PLAYSTEAD_MAC_CI_ROOT PLAYSTEAD_LIVE_SERVER_STAGE_ROOT PLAYSTEAD_LIVE_SERVER_STAGE_FILE MAC_CI_DATABASE_URL MIX_ENV PORT; do
  grep -F "${key}=\"\$${key}\"" "$RUNNER" >/dev/null
done
grep -F 'raw.replacingOccurrences(' "$LIVE_SERVER_TEST" >/dev/null
grep -F 'sanitized.prefix(160)' "$LIVE_SERVER_TEST" >/dev/null
# One distinct assertion site per allowlisted stage, plus the default arm.
# Derived from live-server.sh's own allowlist rather than hardcoded, so adding a
# stage cannot leave its assertion site missing without failing here.
live_stage_count="$(sed -n 's/^    \([a-z|-]*\)) ;;$/\1/p' "$LIVE_SERVER_FIXTURE" | tr '|' '\n' | grep -c .)"
[ "$live_stage_count" -ge 7 ]
[ "$(grep -c 'XCTAssertEqual(status, 0, "live-server-stage=' "$LIVE_SERVER_TEST")" -eq "$((live_stage_count + 1))" ]
[ "$(grep -c 'guard try runFixture' "$LIVE_SERVER_TEST")" -eq 3 ]
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
  testKeyboardSelectionTargetReceivesFocus \
  testKeyboardCommandProducesOneEffect \
  testKeyboardCommandRetainsSelectionAndFocus \
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
[ "$(grep -Fc 'testKeyboardSelectionTargetReceivesFocus' "$CURATION_TEST")" -eq 1 ]
[ "$(grep -Fc 'testKeyboardCommandProducesOneEffect' "$CURATION_TEST")" -eq 1 ]
[ "$(grep -Fc 'testKeyboardCommandRetainsSelectionAndFocus' "$CURATION_TEST")" -eq 1 ]
grep -F 'List(selection: $selectedMemberID)' "$COLLECTION_DETAIL" >/dev/null
grep -F '.focused($memberListHasFocus)' "$COLLECTION_DETAIL" >/dev/null
grep -F '.keyboardShortcut("u", modifiers: [.command, .option])' "$COLLECTION_DETAIL" >/dev/null
grep -F 'moveSelected(.up)' "$COLLECTION_DETAIL" >/dev/null
grep -F 'settleMove(assetSetID: members[index].assetSetID, to: destination)' "$COLLECTION_DETAIL" >/dev/null
grep -F 'list.typeKey(.downArrow, modifierFlags: [])' "$CURATION_TEST" >/dev/null
grep -F 'harness.app.typeKey("u", modifierFlags: [.command, .option])' "$CURATION_TEST" >/dev/null
grep -F 'curation-keyboard-stage=selection-target-not-reached' "$CURATION_TEST" >/dev/null
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
grep -F 'static func summaryIdentifier(assetSetID: String) -> String' "$GAME_ROW" >/dev/null
grep -F '.accessibilityIdentifier(Self.summaryIdentifier(assetSetID: entry.id))' "$GAME_ROW" >/dev/null
python3 - "$GAME_ROW" <<'PY'
import pathlib, sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
summary = source.split("VStack(alignment: .leading, spacing: 2)", 1)[1].split("Spacer()", 1)[0]
if ".accessibilityElement(children: .contain)" not in summary:
    raise SystemExit("game summary identity must surface as a contained AX sibling")
if ".accessibilityElement(children: .combine)" in summary:
    raise SystemExit("combined game summary identity is not independently queryable by XCUI")
PY
grep -F '@FocusState private var downloadActionHasFocus: Bool' "$GAME_ROW" >/dev/null
grep -F '.focused($downloadActionHasFocus)' "$GAME_ROW" >/dev/null
grep -F '.accessibilityIdentifier(Self.downloadActionIdentifier(assetSetID: entry.id))' "$GAME_ROW" >/dev/null
grep -F 'private let quotaDownloadAssetID = "00000000-0000-7000-8000-000000000042"' "$STORAGE_TEST" >/dev/null
grep -F 'private let quotaReclaimAssetID = "00000000-0000-7000-8000-000000000041"' "$STORAGE_TEST" >/dev/null
grep -F '"playstead.game.\(quotaDownloadAssetID).download"' "$STORAGE_TEST" >/dev/null
grep -F 'harness.element("playstead.game.\(assetID).summary")' "$STORAGE_TEST" >/dev/null
grep -F 'XCTAssertTrue(row.label.hasPrefix(title)' "$STORAGE_TEST" >/dev/null
python3 - "$STORAGE_TEST" <<'PY'
import pathlib, sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
storage = source.split("private func dismissStorageAndAssertCanonicalRows()", 1)[1].split("private func launchStorageProfile", 1)[0]
markers = [
    storage.find('dismissSheet(root: "playstead.surface.storage")'),
    storage.find('harness.element("playstead.control.show-list", type: .button).click()'),
    storage.find('harness.element("playstead.surface.game-list").waitForExistence'),
    storage.find('assertCanonicalRow(assetID: quotaReclaimAssetID'),
]
if any(marker < 0 for marker in markers) or markers != sorted(markers):
    raise SystemExit("storage canonical proof must dismiss, reveal List without relaunch, then assert exact rows")
if "launchStorageProfile" in storage or "harness.relaunch" in storage:
    raise SystemExit("storage canonical proof must inspect post-mutation state without reseeding")
PY
grep -F 'action.frame,' "$STORAGE_TEST" >/dev/null
grep -F 'exactIdentity.frame,' "$STORAGE_TEST" >/dev/null
grep -F 'List(selection: $selectedListEntryID)' "$LIBRARY_SHELL" >/dev/null
grep -F 'ForEach(entries) { entry in' "$LIBRARY_SHELL" >/dev/null
if grep -F '.accessibilityIdentifier("playstead.game.\(entry.id).row")' "$LIBRARY_SHELL" >/dev/null; then
  printf 'selectable List row identity must not overwrite descendant Download AX identity\n' >&2
  exit 1
fi
grep -F '.focused($libraryListHasFocus)' "$LIBRARY_SHELL" >/dev/null
grep -F '.onAppear { libraryListHasFocus = true }' "$LIBRARY_SHELL" >/dev/null
grep -F '.keyboardShortcut("d", modifiers: .command)' "$LIBRARY_SHELL" >/dev/null
grep -F 'downloadCommand = LibraryDownloadCommand(' "$LIBRARY_SHELL" >/dev/null
grep -F '.onChange(of: downloadCommand)' "$GAME_ROW" >/dev/null
[ "$(grep -Fc '.keyboardShortcut("d", modifiers: .command)' "$LIBRARY_SHELL")" -eq 1 ]
if grep -F 'Task.yield()' "$LIBRARY_SHELL" >/dev/null; then
  printf 'library List focus must use its concrete appearance lifecycle, not generic Task inference\n' >&2
  exit 1
fi
if grep -F '.keyboardShortcut(' "$GAME_ROW" >/dev/null; then
  printf 'row-local duplicate download shortcuts are forbidden\n' >&2
  exit 1
fi
grep -F 'list.value(forKey: "hasKeyboardFocus") as? Bool == true' "$STORAGE_TEST" >/dev/null
grep -F 'let currentSelection = selection.value as? String' "$STORAGE_TEST" >/dev/null
grep -F 'if currentSelection == quotaDownloadAssetID { break }' "$STORAGE_TEST" >/dev/null
grep -F 'let settledSelection = selection.value as? String' "$STORAGE_TEST" >/dev/null
grep -F 'XCTAssertEqual(settledSelection, quotaDownloadAssetID)' "$STORAGE_TEST" >/dev/null
if grep -F 'where selection.value as? String' "$STORAGE_TEST" >/dev/null; then
  printf 'XCUI selection casts must be materialized before control-flow predicates\n' >&2
  exit 1
fi
grep -F 'harness.app.typeKey("d", modifierFlags: [.command])' "$STORAGE_TEST" >/dev/null
python3 - "$GAME_ROW" "$LIBRARY_SHELL" <<'PY'
import pathlib, sys

row = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
shell = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
handler = row.split(".onChange(of: downloadCommand)", 1)[1].split(".sheet(isPresented: $showsReadinessSheet)", 1)[0]
if "guard command?.assetSetID == entry.id" not in handler or "Task { await download() }" not in handler:
    raise SystemExit("selected Download command must reach exactly its row's production download method")
request = shell.split("private func requestSelectedDownload()", 1)[1].split("\n    }", 1)[0]
if "guard let entry = selectedDownloadEntry" not in request or "assetSetID: entry.id" not in request:
    raise SystemExit("Download command must be scoped to the selected eligible asset")
PY
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
# The contract gate must stay wired into CI, and must stay ahead of the build so
# static drift fails in seconds rather than after a ~20-minute compile. Without
# this assertion the gate is one careless workflow edit away from being
# unreachable again -- which is exactly how two guards silently drifted before.
grep -F -- '--self-test-contracts' "$WORKFLOW" >/dev/null || {
  printf 'ci.yml must invoke run-mac-verification.sh --self-test-contracts\n' >&2
  exit 1
}
python3 - "$WORKFLOW" <<'PY_GATE'
import pathlib, sys
workflow = pathlib.Path(sys.argv[1]).read_text()
gate = workflow.find("--self-test-contracts")
build = workflow.find("--run-four-layer-verification")
if gate < 0 or build < 0 or gate > build:
    raise SystemExit("the static contract gate must run before the four-layer build")
print("contract gate wiring: passed")
PY_GATE
# T-03.5-01/T-03.5-20: the hosted-evidence validator must stay wired to a real
# run's artifact, not merely exist. It cannot live in `ci` -- it asserts the
# run's own conclusion -- so it runs from a workflow_run-triggered workflow.
EVIDENCE_WORKFLOW="${REPO_ROOT}/.github/workflows/verify-hosted-evidence.yml"
[ -f "$EVIDENCE_WORKFLOW" ] || {
  printf 'missing .github/workflows/verify-hosted-evidence.yml\n' >&2
  exit 1
}
python3 - "$EVIDENCE_WORKFLOW" <<'PY_EVIDENCE'
import pathlib, sys
raw = pathlib.Path(sys.argv[1]).read_text()
# Check EXECUTABLE content only. This file documents the very flags it wires,
# so scanning the whole text lets a comment satisfy a marker whose real
# invocation was removed -- the guard passes while the wiring is gone. Strip
# whole-line comments first. (Deliberately no YAML parse: PyYAML is not in the
# stdlib and is absent from the runner image, which is how the ripgrep
# dependency turned this suite's sibling guard into a vacuous pass.)
workflow = "\n".join(
    line for line in raw.split("\n") if not line.lstrip().startswith("#")
)
for marker in (
    "workflow_run:",            # cannot self-validate inside `ci`
    "workflows: [ci]",          # triggered by the run that produced the evidence
    "types: [completed]",
    "actions: read",            # needed to download the triggering run's artifact
    "--verify-hosted-run complete",
    "--run-record",
    "--run-view",
    "--manifest",
    "complete-verification-evidence",
    "github.event.workflow_run.conclusion == 'success'",
):
    if marker not in workflow:
        raise SystemExit(f"hosted-evidence workflow lost required wiring: {marker}")
if "contents: write" in workflow or "pull-requests: write" in workflow:
    raise SystemExit("hosted-evidence workflow must stay read-only")
print("hosted-evidence wiring: passed")
PY_EVIDENCE
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
grep -F '"failure_diagnostics": [dict(fields) for fields in all_failure_diagnostics[:max_failure_diagnostics]]' "$RUNNER" >/dev/null
grep -F 'value.get("nodeType") == "Failure Message"' "$RUNNER" >/dev/null
grep -F 'failure_message_location_pattern.match(message_name)' "$RUNNER" >/dev/null
grep -F 'print_failure_diagnostics "$result_summary" "$slug"' "$RUNNER" >/dev/null
grep -F 'FAILURE_DIAGNOSTICS_TRUNCATED shown=' "$RUNNER" >/dev/null
grep -F 'print_build_diagnostics "${FOUR_LAYER_RAW}/build.log" build' "$RUNNER" >/dev/null
grep -F 'COMPILER_DIAGNOSTICS_TRUNCATED shown=' "$RUNNER" >/dev/null
grep -F '"audit_issues": [dict(fields) for fields in all_audit_issues[:max_audit_issues]]' "$RUNNER" >/dev/null
grep -F 'len(failed) > 50' "$SANITIZER" >/dev/null
grep -F 'len(diagnostics) > 50' "$SANITIZER" >/dev/null
grep -F 'len(audit_issues) > 50' "$SANITIZER" >/dev/null
grep -F '{"identifier", "outcome"}' "$SANITIZER" >/dev/null
grep -F '{"test_identifier", "assertion", "source_file", "source_line"}' "$SANITIZER" >/dev/null
grep -F '{"test_identifier", "category", "element_identifier", "element_role"}' "$SANITIZER" >/dev/null

# Xcode generates the UI test runner sandboxed with a read-only exception for
# "/" and no write exception, which denies every fixture write with EPERM no
# matter the uid or mode bits. The live-server layer cannot work without this
# override, and nothing else in the suite would notice if it were dropped --
# the layer would just start failing at a preflight line number again.
plutil -lint "$UITEST_ENTITLEMENTS" >/dev/null
[ "$(grep -c 'CODE_SIGN_ENTITLEMENTS = PlaysteadUITests/PlaysteadUITests.entitlements;' "$PBXPROJ")" -eq 2 ]
python3 - "$UITEST_ENTITLEMENTS" "$APP_ENTITLEMENTS" <<'SANDBOX'
import pathlib, plistlib, sys

runner, app = (plistlib.loads(pathlib.Path(path).read_bytes()) for path in sys.argv[1:3])
# The UI test runner spawns the live-server fixture, which writes into the
# native server root and executes the Elixir toolchain. Xcode's generated
# runner entitlements sandbox it read-only, which denies both -- EPERM on
# write, exit 126 on exec -- so the layer silently stops working if this
# override is dropped. Filesystem exceptions alone are not sufficient: exec is
# a separate sandbox operation whose sbpl exception is not honored here.
if runner.get("com.apple.security.app-sandbox") is not False:
    raise SystemExit("UI test runner must set com.apple.security.app-sandbox = false")
# Separate decision, separate reason: the shipped app is unsandboxed so it can
# launch a downloaded emulator process, per D-04. Pinned here so neither the
# test-only override nor the product decision can drift unnoticed.
if app.get("com.apple.security.app-sandbox") is not False:
    raise SystemExit("shipped app must keep com.apple.security.app-sandbox = false (D-04)")
SANDBOX

"$PROMPT_SAFETY"
bash "$KEYBOARD_CLEANUP"
bash "$SWIFT_SEMANTIC"

printf 'four-layer topology contract: passed\n'
