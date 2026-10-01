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
TRUST_CAPTURE="${MAC_ROOT}/Playstead/Pairing/PinnedCertificateCapture.swift"
LIVE_SERVER_TEST="${MAC_ROOT}/PlaysteadUITests/LiveServerSnapshotTests.swift"
LIVE_SERVER_FIXTURE="${MAC_ROOT}/scripts/ci/live-server.sh"
MAC_CI_CONFIG="${REPO_ROOT}/playstead-server/config/mac_ci.exs"
STORAGE_TEST="${MAC_ROOT}/PlaysteadUITests/StorageInteractionTests.swift"
SURFACE_ACCESSIBILITY_TEST="${MAC_ROOT}/PlaysteadUITests/SurfaceAccessibilityTests.swift"
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
PG_STARTUP_CLASSIFIER="${MAC_ROOT}/scripts/ci/classify-postgres-startup.py"
PHOENIX_STARTUP_CLASSIFIER="${MAC_ROOT}/scripts/ci/classify-phoenix-startup.py"
PHOENIX_HEALTH_CLASSIFIER="${MAC_ROOT}/scripts/ci/classify-phoenix-health-exit.py"
XCODE_FAILURE_CLASSIFIER="${MAC_ROOT}/scripts/ci/classify-xcode-failure.py"

for file in "$RUNNER" "$SCHEME" "$APP_ENTRY" "$PROFILE_TEST" "$UI_CANARY" "$CURATION_TEST" "$COLLECTION_DETAIL" "$UI_BOOTSTRAP" "$TRUST_CAPTURE" "$LIVE_SERVER_TEST" "$LIVE_SERVER_FIXTURE" "$MAC_CI_CONFIG" "$STORAGE_TEST" "$SURFACE_ACCESSIBILITY_TEST" "$GAME_ROW" "$LIBRARY_SHELL" "$RECLAIM_VIEW" "$STORAGE_VIEW" "$WORKFLOW" "$REFRESH_WORKFLOW" "$SANITIZER" "$PROMPT_SAFETY" "$KEYBOARD_CLEANUP" "$SWIFT_SEMANTIC" "$PG_STARTUP_CLASSIFIER" "$PHOENIX_STARTUP_CLASSIFIER" "$PHOENIX_HEALTH_CLASSIFIER" "$XCODE_FAILURE_CLASSIFIER"; do
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

python3 - "${MAC_ROOT}/TestPlans" "$APP_ENTRY" "$RUNNER" "${MAC_ROOT}/PlaysteadUITests/ControllerHardwareIntegrationTests.swift" "$UI_BOOTSTRAP" "$TRUST_CAPTURE" "${MAC_ROOT}/PlaysteadUITests/PairingCeremonyTests.swift" <<'PY'
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

# The entitled virtual-gamepad test remains in the UI plan, but it must never
# be included in the ordinary no-HID selection. The two selectors must be
# disjoint and cover every current UI-plan entry; new plan entries therefore
# enter the ordinary lane automatically rather than being silently omitted.
virtual_class = "ControllerHardwareIntegrationTests"
ui_plan_entries = {test for _, test in selected["UI"]}
virtual_entries = {test for test in ui_plan_entries if test.split("/", 1)[0] == virtual_class}
ordinary_entries = ui_plan_entries - virtual_entries
if virtual_entries != {virtual_class} or ordinary_entries & virtual_entries:
    raise SystemExit("UI plan must keep the virtual-gamepad class as its own selection")
if ordinary_entries | virtual_entries != ui_plan_entries:
    raise SystemExit("ordinary and entitled selections do not cover the UI plan")
if "ui_test_selection() {" not in runner_source or "ui_test_selection ordinary" not in runner_source:
    raise SystemExit("runner must derive its ordinary UI selection from the current UI test plan")
if "ui_test_selection entitled" not in runner_source or "testEntitledVirtualGamepadEnumeratesDetachesAndReconnectsWithoutRelaunch" not in runner_source:
    raise SystemExit("runner must keep the exact entitled virtual-gamepad test independently selectable")
if "PlaysteadUITests/PlaysteadUITests.no-hid.entitlements" not in runner_source:
    raise SystemExit("ordinary UI runs must use the no-HID test-runner entitlements")
if "PLAYSTEAD_UI_TEST_ENTITLEMENTS=PlaysteadUITests/PlaysteadUITests.no-hid.entitlements" not in runner_source:
    raise SystemExit("no-HID entitlements must be scoped to the UI test target")
if "CODE_SIGN_ENTITLEMENTS=PlaysteadUITests/PlaysteadUITests.no-hid.entitlements" in runner_source:
    raise SystemExit("the no-HID override must not replace entitlements for every Xcode target")

hardware_source = pathlib.Path(sys.argv[4]).read_text(encoding="utf-8")
bootstrap_source = pathlib.Path(sys.argv[5]).read_text(encoding="utf-8")
trust_source = pathlib.Path(sys.argv[6]).read_text(encoding="utf-8")
pairing_source = pathlib.Path(sys.argv[7]).read_text(encoding="utf-8")
hardware_tests = set(re.findall(r"^\s*func\s+(test[A-Za-z0-9_]+)\s*\(", hardware_source, re.MULTILINE))
if hardware_tests != {"testEntitledVirtualGamepadEnumeratesDetachesAndReconnectsWithoutRelaunch"}:
    raise SystemExit("the entitled UI selection must account for every virtual-gamepad test")

live_targets = plans["LiveServer"]["testTargets"]
live_environment = {
    entry.get("key"): entry.get("value")
    for entry in plans["LiveServer"].get("defaultOptions", {}).get("environmentVariableEntries", [])
}
expected_live_environment = {
    key: f"$({key})" for key in (
        "PLAYSTEAD_MAC_CI_ROOT", "PLAYSTEAD_LIVE_SERVER_STAGE_ROOT",
        "PLAYSTEAD_LIVE_SERVER_STAGE_FILE", "MAC_CI_DATABASE_URL", "MIX_ENV", "PORT",
        "PLAYSTEAD_TEST_LIVE_SERVER_CA_DER", "PLAYSTEAD_TEST_LIVE_SERVER_CA_SHA256",
        "PLAYSTEAD_TEST_LIVE_SERVER_RUNTIME_CONFIG", "PLAYSTEAD_SAVE_RELIABILITY_EVIDENCE_PATH",
    )
}
if live_environment != expected_live_environment:
    raise SystemExit("LiveServer test plan must explicitly bridge the native service environment")
# The LiveServer layer is the scarcest one in the matrix: a single serial
# target against a real running server. Its budget is deliberately small
# and every addition is a considered widening, never an incidental one.
#
# Phase 4 added the two save entries below. They earn their place because
# SAVE-03's continuation claim -- that a save captured on one Mac is
# restored byte-identically and still plays -- cannot be proven by any
# cheaper layer: it needs a real upload, a real journal return, and a real
# restore into a launch directory. Everything else about the save
# subsystem is proven in Unit or Rendering and must stay there.
#
# Plan 04.5-01 added the pairing-ceremony entry below. It earns its place for
# the same reason the save entries do: it drives the real `PairingView` against
# a real running server starting from a genuinely empty scoped Keychain, which
# is the one claim no deterministic profile can make (every other live-server
# entry is handed a credential). It was added to LiveServer.xctestplan by
# b8960d1 and this set was not updated alongside it -- the drift went unseen
# because CI last ran 2026-09-08, before that commit.
expected_live = {
    "HostedRunnerCanaryTests/testAdHocSignedAppLaunchesOnHostedRunner()",
    "LiveServerSnapshotTests/testPairedFreshMirrorRendersSnapshotBeforeAnyBlobDownloadAndPersistsKeychainAcrossRelaunch()",
    "PairingCeremonyTests/testAHumanCanPairAFreshMacEntirelyFromInsideTheAppAgainstTheRealServer()",
    "RecoveryKnownPlayableTests/testRecoveryHarnessRefusesSyntheticFixtureWithoutAnIsolatedTarget()",
    "SaveEndToEndTests/testOneSaveRoundTripsCaptureUploadAndJournalReturn()",
    "SaveRestoreProofTests/testCapturedRevisionRestoresToByteIdenticalArtifactInLaunchDir()",
}
if len(live_targets) != 1 or live_targets[0].get("parallelizable") is not False:
    raise SystemExit("LiveServer must remain one serial target")
if set(live_targets[0].get("selectedTests", [])) != expected_live:
    raise SystemExit(
        "LiveServer must select exactly the launch canary, the Plan 08 pairing proof, "
        "the Phase 4 save round-trip/restore proofs, and the parser-only recovery refusal"
    )

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
if 'mkdir -p "$FOUR_LAYER_RAW"' not in native_services:
    raise SystemExit("selected LiveServer runs must create the four-layer result parent before owning native services")
if 'native service root already exists' not in native_services:
    raise SystemExit("native service root ownership must fail closed")
if 's.bind(("127.0.0.1", 0))' not in native_services or 'pg_port=55432' in native_services:
    raise SystemExit("native PostgreSQL must select a free run-local loopback port")
native_cleanup_body = runner_source.split("cleanup_native_services() {", 1)[1].split("start_native_services() {", 1)[0]
if '[ -f "$PGDATA/postmaster.pid" ]' not in native_cleanup_body:
    raise SystemExit("native cleanup must not stop PostgreSQL when this run never started it")
if 'if [ "$cleanup_ok" = true ] && [ -n "$NATIVE_ROOT" ]' not in native_cleanup_body:
    raise SystemExit("uncertain native service cleanup must preserve the run-owned data root")
if 'tail -n 120 "$NATIVE_ROOT/phoenix.log"' in runner_source or 'tail -n 120 "$NATIVE_ROOT/bootstrap.log"' in runner_source:
    raise SystemExit("native startup diagnostics must not echo raw service log lines")
if 'classify-phoenix-startup.py' not in runner_source or 'classify-phoenix-health-exit.py' not in runner_source:
    raise SystemExit("Phoenix startup failures must use a fixed-enum classifier")
if 'classify-xcode-failure.py' not in runner_source or '"$result_log"' not in runner_source:
    raise SystemExit("xcodebuild failures must use the category-only owned-log classifier")
if re.search(r"(?:sed|tail|cat)\s+[^\n]*\$result_log", runner_source):
    raise SystemExit("the raw xcodebuild log must never be copied into failure output")
if "trap 'restore_live_server_xctestrun; cleanup_live_server_runtime_config; cleanup_native_services; restore_keyboard_mode' EXIT" not in four_layer:
    raise SystemExit("LiveServer xctestrun/config/native cleanup must preserve keyboard-mode restoration")
stage_preflight = four_layer.find("prepare_live_server_failure_stage")
if not (0 <= stage_preflight < live_layer):
    raise SystemExit("failure-stage channel must be cleared and validated before LiveServer")
if 'mac-ci-tls.sh" trust' in runner_source or 'mac-ci-tls.sh" untrust' in runner_source or "System.keychain" in runner_source:
    raise SystemExit("LiveServer wrapper must not change System Keychain trust")
if 'mac-ci-tls.sh" issue' not in runner_source or 'https://127.0.0.1:4010/healthz' not in runner_source:
    raise SystemExit("LiveServer must retain run-owned certificate issuance and HTTPS health validation")
if "PLAYSTEAD_TEST_LIVE_SERVER_CA_DER" not in runner_source or "PLAYSTEAD_TEST_LIVE_SERVER_CA_SHA256" not in runner_source:
    raise SystemExit("LiveServer must bridge the issued CA path and digest into its selected test")
if 'PLAYSTEAD_TEST_LIVE_SERVER_RUNTIME_CONFIG="$LIVE_SERVER_RUNTIME_CONFIG"' not in runner_source:
    raise SystemExit("LiveServer must bridge the run-owned runtime config path into selected and aggregate tests")
if 'label: "live pairing trust anchor"' not in bootstrap_source or "expectedDigest" not in bootstrap_source:
    raise SystemExit("app bootstrap must reject escaped and mismatched CA files")
if "https://127.0.0.1:4010" not in bootstrap_source or "SecCertificateCopyNotValidAfterDate" not in bootstrap_source:
    raise SystemExit("app bootstrap must constrain the endpoint and reject expired supplied CA")
if "pairing-ca.der" not in pairing_source or "PLAYSTEAD_UI_TEST_LIVE_SERVER_CA_SHA256" not in pairing_source:
    raise SystemExit("pairing ceremony must privately copy and verify the run CA")
if "runtime-config-ca-path-invalid" not in pairing_source or "runtime-config-ca-digest-invalid" not in pairing_source:
    raise SystemExit("pairing preflight must classify run-CA path and digest failures separately")
if "caPathMatchesRun(caPath, serverRoot: serverRoot)" not in pairing_source or "isCanonicalSHA256(digest)" not in pairing_source:
    raise SystemExit("pairing preflight must canonicalize its run-owned CA path and validate a lowercase SHA-256")
relaunch = pairing_source.split("launched.terminate()", 1)[1].split("launched.launch()", 1)[0]
for key in (
    "PLAYSTEAD_UI_TEST_LIVE_SERVER_UNPAIRED",
    "PLAYSTEAD_UI_TEST_LIVE_SERVER_CA_DER",
    "PLAYSTEAD_UI_TEST_LIVE_SERVER_CA_SHA256",
    "PLAYSTEAD_UI_TEST_LIVE_SERVER_PAIRING_TARGET",
):
    if f'"{key}"' not in relaunch:
        raise SystemExit("pairing relaunch must remove the one-session trust override")
if 'openPairingFromMenu(in: launched)' not in pairing_source or 'app.menuBars.menuBarItems["Pairing"]' not in pairing_source or 'app.menuItems["Pair with Server…"]' not in pairing_source:
    raise SystemExit("pairing ceremony must enter through the production Pairing menu route")
if "SecTrustSetAnchorCertificatesOnly(serverTrust, true)" not in trust_source:
    raise SystemExit("scoped pairing trust must remain exclusive and preserve TLS validation")
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
# ui moved 1800 -> 2700 after run 34264338508 was SIGTERMed at exactly its
# deadline: the last green run spent 1631s here, 9% under the old cap, on a
# commit whose diff touched no file in the UI test plan. The cap stays a real
# bound -- it just has to sit above the observed runtime, not on top of it.
expected_deadlines = {"unit": 900, "rendering": 600, "ui": 2700, "live-server": 900}
if len(deadline_pairs) != 4 or deadlines != expected_deadlines:
    raise SystemExit(f"four-layer deadlines drifted: {deadlines} != {expected_deadlines}")
if any(seconds <= 0 or seconds > 2700 for seconds in deadlines.values()):
    raise SystemExit("every hosted layer deadline must remain positive and bounded at 2700 seconds")
test_layer = runner_source.split("run_test_layer() {", 1)[1].split("run_four_layer_verification() {", 1)[0]
if test_layer.count("test-without-building") != 1 or "retry" in test_layer.lower():
    raise SystemExit("a layer must execute once without automatic retry")
selected_test_layer = runner_source.split("run_selected_layer_tests() {", 1)[1].split("\nrun_entitled_virtual_gamepad_verification()", 1)[0]
if '${layer_settings[@]+"${layer_settings[@]}"}' not in selected_test_layer:
    raise SystemExit("selected-layer optional settings must tolerate an empty array under set -u")
if 'if [ "$layer" != "rendering" ] && [ "$requires_virtual_hid" = false ]; then' not in selected_test_layer:
    raise SystemExit("ordinary UI and LiveServer selections must use the scoped no-HID test entitlement")
if 'BUILD_ROOT="${PLAYSTEAD_CI_BUILD_ROOT:-${MAC_ROOT}/.build/ci}"' not in runner_source:
    raise SystemExit("targeted CI cache must support an isolated temporary build root")
if 'CFFIXED_USER_HOME=${SWIFTPM_DIAGNOSTICS_HOME}' not in runner_source or 'CLANG_MODULE_CACHE_PATH=${SWIFT_CLANG_MODULE_CACHE}' not in runner_source:
    raise SystemExit("four-layer package diagnostics and module cache must stay in the run-owned temporary root")
if '-clonedSourcePackagesDirPath' not in selected_test_layer or '-packageCachePath' not in selected_test_layer:
    raise SystemExit("targeted Xcode runs must use run-owned package caches")
if 'GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0' not in selected_test_layer:
    raise SystemExit("targeted package resolution must not use system/user Git configuration or prompts")
signing_config = runner_source.split("configure_ci_signing() {", 1)[1].split("\nassert_local_app_launch_authorized()", 1)[0]
if 'PLAYSTEAD_MAC_CI_SIGNING_MODE' not in signing_config or 'CODE_SIGN_IDENTITY="Apple Development"' not in signing_config:
    raise SystemExit("local development signing opt-in is missing")
if 'PROVISIONING_PROFILE_SPECIFIER=' not in signing_config or '-allowProvisioningUpdates' in signing_config:
    raise SystemExit("local development signing must use installed credentials without changing Apple account profiles")
if 'test_selection=(-xctestrun "$LIVE_SERVER_XCTESTRUN")' not in test_layer:
    raise SystemExit("LiveServer must consume the exact generated xctestrun that received its concrete environment")
if 'live-server layer requires a materialized generated xctestrun' not in test_layer:
    raise SystemExit("LiveServer must fail closed before resolving an unpatched test configuration")
xctestrun_materializer = runner_source.split("materialize_live_server_xctestrun() {", 1)[1].split("restore_keyboard_mode() {", 1)[0]
if 'targets[0].setdefault("EnvironmentVariables", {})' not in xctestrun_materializer:
    raise SystemExit("LiveServer xctestrun must carry concrete scheme test-host environment")
if 'targets[0].setdefault("TestingEnvironmentVariables", {})' not in xctestrun_materializer:
    raise SystemExit("LiveServer xctestrun must carry concrete XCTest-host environment")
if '"PLAYSTEAD_TEST_LIVE_SERVER_RUNTIME_CONFIG"' not in xctestrun_materializer:
    raise SystemExit("LiveServer xctestrun must carry the runtime config path with the service environment")
PY

grep -F 'app.launchEnvironment["PLAYSTEAD_WAVE_0_LAUNCH_CANARY"] = "1"' "$UI_CANARY" >/dev/null
grep -F 'environment["PLAYSTEAD_WAVE_0_LAUNCH_CANARY"] == "1"' "$APP_ENTRY" >/dev/null
grep -F 'HostedRunnerLaunchCanaryView' "$APP_ENTRY" >/dev/null
grep -F 'CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=' "$RUNNER" >/dev/null
grep -F 'server: System.get_env("PLAYSTEAD_MAC_CI_TASK") != "1"' "$MAC_CI_CONFIG" >/dev/null
# `mac_ci.exs` starts no server when PLAYSTEAD_MAC_CI_TASK=1, so every fixture
# `mix` invocation must carry that flag or it boots a second server on the same
# port. This used to assert an exact count of 3, which said "all of them" only
# by coincidence: plan 04.5-01's pairing-ceremony flow legitimately added two
# more invocations and the count was never updated, so this guard had been
# failing on main since b8960d1 (unseen -- CI last ran 2026-09-08). Comparing
# guarded against total says what was actually meant, survives a legitimate
# addition, and still fails on an unguarded one. Both counts must be nonzero so
# a renamed task cannot satisfy it with 0 == 0.
live_fixture_total="$(grep -c 'mix playstead.mac_ci_fixture' "$LIVE_SERVER_FIXTURE")"
live_fixture_guarded="$(grep -c 'PLAYSTEAD_MAC_CI_TASK=1 mix playstead.mac_ci_fixture' "$LIVE_SERVER_FIXTURE")"
[ "$live_fixture_total" -gt 0 ]
[ "$live_fixture_guarded" -eq "$live_fixture_total" ]
grep -F 'live-server fixture failed at %s' "$LIVE_SERVER_FIXTURE" >/dev/null
grep -F 'PLAYSTEAD_LIVE_SERVER_STAGE_FILE' "$LIVE_SERVER_FIXTURE" >/dev/null
grep -F 'resolved_parent" = "$resolved_root' "$LIVE_SERVER_FIXTURE" >/dev/null
grep -F 'live-server: FAILURE_STAGE %s' "$RUNNER" >/dev/null
grep -F 'prepare_live_server_failure_stage' "$RUNNER" >/dev/null
grep -F 'PLAYSTEAD_LIVE_SERVER_STAGE_FILE="$server_root/live-server-failure-stage"' "$RUNNER" >/dev/null
grep -F 'cipher_suite: :compatible' "$MAC_CI_CONFIG" >/dev/null
# The live-server test must be preflight-gated -- but NOT with a bare return,
# which this clause used to pin. A bare `else { return }` makes a failed
# preflight report success; that exact shape is how a save-upload path that
# 404'd against every real server sat behind a green end-to-end suite
# (fixed 2026-09-08, see fail-open-test-guard-test.sh). The gate is still
# required; it must now say why it stopped.
[ "$(grep -c 'guard fixtureEnvironmentIsReady() else {' "$LIVE_SERVER_TEST")" -eq 1 ]
grep -F 'return XCTFail("live fixture preflight failed")' "$LIVE_SERVER_TEST" >/dev/null
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

# The save-e2e harness reason channel is a pinned mirror across two targets,
# and nothing enforced it. UITestBootstrap reports fixed literals as either
# thrown errors or owned marker payloads; the UI test SWITCHES on them to pick
# one assertion site per cause, because CI keeps
# file:line and discards assertion text. A literal that drifts on either side
# falls through to `default` and reports every distinct cause at the same
# line -- the exact diagnosis-destroying shape the switch exists to prevent,
# and it would do so silently while still "passing".
python3 - "$MAC_ROOT" <<'GUARD'
import pathlib, re, sys

mac_root = pathlib.Path(sys.argv[1])
producer = (mac_root / "Playstead/UITesting/UITestBootstrap.swift").read_text(encoding="utf-8")
consumer = (mac_root / "PlaysteadUITests/SaveEndToEndTests.swift").read_text(encoding="utf-8")

reported = set(re.findall(r'(?:stateMismatch|Data)\("(save-e2e: [^"]+)"(?:\.utf8)?\)', producer))
# Every literal on a `case` line, including the `case "A", "B":` form --
# matching only `"...":` would miss all but the last of a combined case and
# misreport it as drift, when the real fault is two causes sharing a site.
handled = set()
for line in consumer.splitlines():
    if re.match(r'\s*case "save-e2e: ', line):
        handled.update(re.findall(r'"(save-e2e: [^"]+)"', line))

if not reported:
    raise SystemExit("found no save-e2e reason literals in UITestBootstrap -- the scan is broken")
if reported != handled:
    unhandled = sorted(reported - handled)
    stale = sorted(handled - reported)
    raise SystemExit(
        f"save-e2e reason literals drifted. reported-but-unhandled={unhandled} handled-but-never-reported={stale}"
    )

# One assertion SITE per cause: two causes sharing a line diagnose nothing,
# which is the whole reason this switch is not a single XCTFail(reason).
lines = consumer.splitlines()
sites = []
for i, line in enumerate(lines):
    if re.match(r'\s*case "save-e2e: ', line):
        for j in range(i + 1, min(len(lines), i + 4)):
            if "XCTAssertTrue(false" in lines[j]:
                sites.append(j)
                break
if len(sites) != len(handled):
    raise SystemExit(f"{len(handled)} reason cases but {len(sites)} assertion sites")
if len(set(sites)) != len(sites):
    raise SystemExit("two save-e2e causes share an assertion line; CI could not tell them apart")
GUARD

# Every caller of the shared `verify` stage must state its own snapshot
# expectation, and the fixture must refuse to guess.
#
# The count is read cumulatively from a phoenix.log shared by the whole
# LiveServer layer, so it is never a property of the mirror -- it is the
# calling test's claim. While it was hardcoded as "exactly two",
# LiveServerSnapshotTests' proof was silently binding on every other
# caller: 04.5-01 added PairingCeremonyTests, which snapshots a third
# time, and run 34636187313 failed SaveEndToEndTests on an invariant it
# had never asserted. The sentinel below is deliberately a word and not
# an empty string, so opting out is a visible decision in the diff.
for token in 'snapshots-not-asserted-here' 'snapshot_expectation="${4:-}"'; do
  grep -F "$token" "$LIVE_SERVER_FIXTURE" >/dev/null || {
    printf 'live-server.sh: the verify stage lost its caller-stated snapshot expectation (%s)\n' "$token" >&2
    exit 1
  }
done
# Fail-closed: an omitted or non-numeric expectation dies rather than
# skipping the assertion. A default here would turn a forgotten argument
# into a silent pass, which is the exact rot this guard exists to stop.
grep -F "''|*[!0-9]*) die ;;" "$LIVE_SERVER_FIXTURE" >/dev/null || {
  printf 'live-server.sh: the verify stage must DIE on an omitted or non-numeric snapshot expectation, never default\n' >&2
  exit 1
}
python3 - "$MAC_ROOT" <<'GUARD'
import pathlib, re, sys

mac_root = pathlib.Path(sys.argv[1])
callers = sorted((mac_root / "PlaysteadUITests").glob("*.swift"))
numeric, opted_out = [], []
for path in callers:
    source = path.read_text(encoding="utf-8")
    for call in re.finditer(
        r'runFixture\(\s*"verify"(.*?)\)\s*else', source, re.DOTALL
    ):
        body = call.group(1)
        if "extraArguments" not in body:
            raise SystemExit(
                f"{path.name}: runFixture(\"verify\") must state a snapshot expectation"
            )
        if "snapshots-not-asserted-here" in body:
            opted_out.append(path.name)
        elif re.search(r'extraArguments:\s*\["\d+"\]', body):
            numeric.append(path.name)
        else:
            raise SystemExit(f"{path.name}: unrecognised snapshot expectation")

if not numeric:
    raise SystemExit("no test asserts the live-server snapshot count any more")
if numeric != ["LiveServerSnapshotTests.swift"]:
    raise SystemExit(
        "the snapshot count is LiveServerSnapshotTests' proof alone; "
        f"also asserted by: {numeric}"
    )
if not opted_out:
    raise SystemExit("expected at least one caller to opt out explicitly")
GUARD
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
python3 - "$RUNNER" <<'PY_BUILD_PACKAGES'
import pathlib, sys

runner = pathlib.Path(sys.argv[1]).read_text()
start = runner.index("xcodebuild build-for-testing")
end = runner.index("|| build_status=$?", start)
build = runner[start:end]
for setting in (
    '-clonedSourcePackagesDirPath "${BUILD_ROOT}/SourcePackages"',
    '-packageCachePath "${BUILD_ROOT}/PackageCache"',
):
    if setting not in build:
        raise SystemExit(f"build-for-testing must use the owned package cache: {setting}")
print("build-for-testing uses the owned package cache")
PY_BUILD_PACKAGES
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

# The save-e2e harness must ask "is this retryable?" in the product's own
# vocabulary, never by comparing against `.none`.
#
# `SaveUploadFailureClassification` has seven cases and its own doc says three
# of them -- `.none`, `.offlineQueue`, `.slowUpload` -- are the product working
# correctly. Branching on `== .none` collapses that to two and reports an
# unreachable server as `save-e2e-harness=upload-server-refused`, which is what
# run 34670123715 did. `.offlineQueue` is the EXPECTED state at pairing time,
# when the app drains on the reachability transition.
#
# Requiring `OnlyCopyEscalationReason(classification:)` is what keeps the
# harness and the shipped escalation panel from ever disagreeing about which
# verdicts are unfixable: they gate on the same initializer.
python3 - "$UI_BOOTSTRAP" <<'RETRYABLE_PY'
import pathlib, sys

raw = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")

# Comment lines are stripped before any of this is judged. The first draft of
# this guard passed a probe that gutted the helper body, because the phrase it
# searched for still appeared in the doc comment above it -- a guard satisfied
# by prose rather than by code, which is the same defect class it exists to
# catch.
source = "\n".join(
    line for line in raw.splitlines() if not line.lstrip().startswith("//")
)
if "lastFailureClassification == .none" in source:
    raise SystemExit("save-e2e must not treat `.none` as the whole retryable set; .offlineQueue and .slowUpload are retryable too")
body = source.split("private static func isRetryable(", 1)
if len(body) != 2:
    raise SystemExit("save-e2e retry predicate `isRetryable` is missing")
if "OnlyCopyEscalationReason(classification:" not in body[1].split("}", 1)[0]:
    raise SystemExit("isRetryable must gate on OnlyCopyEscalationReason, the same gate the escalation panel uses")

# ...and the classification must actually be consulted at each of the three
# decision points, not merely defined. A helper nothing calls is the exact
# shape of a fix that passes its own guard and changes no behaviour.
#
# It must come off the DRAIN RESULT, never off the lane. WINDOWS #87:
# `lane.lastFailureClassification` is a nonisolated read of one
# last-writer-wins cell, and WINDOWS #67's fix made this harness share the
# app's lane -- which drains on the reachability transition at pairing time.
# So the cell can hold the app pass's classification while `stoppedForRetry`
# describes this pass's, and an ordinary `.offlineQueue` stop gets reported as
# a refusal. Reading the lane here is the defect, so the guard forbids it
# outright rather than counting correct uses.
region = source.split("func runSaveEndToEnd", 1)[1]
if "lane.lastFailureClassification" in region:
    raise SystemExit("save-e2e must classify from drainResult.failureClassification, not the lane's shared last-writer-wins cell")
uses = region.count("drainResult.failureClassification")
if uses != 3:
    raise SystemExit(f"save-e2e must consult this pass's classification at all 3 decision points, found {uses}")
RETRYABLE_PY

# ...and the lane must actually put this pass's classification INTO the result,
# or every reader above is looking at a field nobody writes. Pinned separately
# because the harness-side guard passes perfectly well against a struct field
# that is always `.none` -- which would silently reclassify every refusal as
# retryable and make this whole test unfailable.
python3 - "${MAC_ROOT}/Playstead/Saves/SaveUploadLane.swift" "${MAC_ROOT}/Playstead/Sync/OutboxWorker.swift" <<'CLASSIFICATION_PY'
import pathlib, sys

lane, worker = (pathlib.Path(argument).read_text(encoding="utf-8") for argument in sys.argv[1:3])
lane_source = "\n".join(line for line in lane.splitlines() if not line.lstrip().startswith("//"))
worker_source = "\n".join(line for line in worker.splitlines() if not line.lstrip().startswith("//"))

if "var failureClassification: SaveUploadFailureClassification" not in worker_source:
    raise SystemExit("OutboxDrainResult must carry this pass's failure classification (WINDOWS #87)")
drain = lane_source.split("func drainOnce(", 1)
if len(drain) != 2:
    raise SystemExit("SaveUploadLane.drainOnce is missing")
if "result.failureClassification = " not in drain[1]:
    raise SystemExit("drainOnce must record its own failure classification on the result it returns")
CLASSIFICATION_PY

# The most expensive test in the Unit layer must not be paid for twice.
# `ReleaseHookAbsenceTests` shells out to a full Release `xcodebuild`. On run
# 34663361104 it cost 59.39s in Unit and 46.62s in Rendering -- the same build,
# twice, and 88% of Rendering's entire in-test time. Unit selects every
# PlaysteadTests case except three named skips, so Rendering naming it again
# bought no coverage whatsoever. It stays required by Unit, where it runs, and
# absent from Rendering, where it only duplicated.
python3 - "$RUNNER" "${MAC_ROOT}/TestPlans/Rendering.xctestplan" "${MAC_ROOT}/TestPlans/Unit.xctestplan" <<'RELEASE_HOOK_PY'
import json, pathlib, sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
unit = source.split("run_test_layer unit Unit", 1)[1].split("run_test_layer rendering Rendering", 1)[0]
rendering = source.split("run_test_layer rendering Rendering", 1)[1].split("run_test_layer ui UI", 1)[0]
scan = "PlaysteadTests.ReleaseHookAbsenceTests/testNonTestingReleaseBinaryAndSymbolsContainNoBootstrapProfileOrEnvironmentKey"
if scan not in unit:
    raise SystemExit("the Release-absence scan must be required by the Unit layer")
if scan in rendering:
    raise SystemExit("the Release-absence scan must not be required by the Rendering layer")

rendering_plan = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
for target in rendering_plan["testTargets"]:
    for selected in target.get("selectedTests", []):
        if selected.split("/")[0] == "ReleaseHookAbsenceTests":
            raise SystemExit("Rendering re-selected ReleaseHookAbsenceTests; Unit already runs that Release build")

# Dropping it from Rendering is only safe while Unit still reaches it. A skip
# added there would leave the Release-absence scan running in no layer at all,
# which is a far worse outcome than the duplication this removed.
unit_plan = json.loads(pathlib.Path(sys.argv[3]).read_text(encoding="utf-8"))
reached = False
for target in unit_plan["testTargets"]:
    if target["target"]["name"] != "PlaysteadTests":
        continue
    if "ReleaseHookAbsenceTests" in {entry.split("/")[0] for entry in target.get("skippedTests", [])}:
        raise SystemExit("Unit skips ReleaseHookAbsenceTests, so nothing runs the Release-absence scan")
    selected = target.get("selectedTests")
    if selected is None or any(entry.split("/")[0] == "ReleaseHookAbsenceTests" for entry in selected):
        reached = True
if not reached:
    raise SystemExit("Unit no longer selects ReleaseHookAbsenceTests")
RELEASE_HOOK_PY
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
  testFavoritesShelfRendersExactSeededRowAndStatus \
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
grep -F 'waitForKeyboardFocus(list, stage: "library-list-arrow-focus")' "$SURFACE_ACCESSIBILITY_TEST" >/dev/null
grep -F 'readinessContent.swipeUp()' "$SURFACE_ACCESSIBILITY_TEST" >/dev/null
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
  testReclaimRouteArrowSelectionTargetsUniqueDownloadTrigger \
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
# `readableText`, not `label`: on macOS a static text keeps its content in
# AXValue, so `.label` reads empty and this canonical-row proof would assert
# nothing (ax-value-semantics-test.sh now forbids the `.label` form outright).
grep -F 'XCTAssertTrue(row.readableText.hasPrefix(title)' "$STORAGE_TEST" >/dev/null
python3 - "$STORAGE_TEST" <<'PY'
import pathlib, sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
storage = source.split("private func dismissStorageAndAssertCanonicalRows()", 1)[1].split("private func launchStorageProfile", 1)[0]
markers = [
    storage.find('harness.element("playstead.sidebar.home").clickWhenHittable()'),
    storage.find('harness.element("playstead.surface.library").awaitExistence(timeout: 5)'),
    storage.find('harness.element("playstead.control.show-list").clickWhenHittable()'),
    storage.find('harness.element("playstead.surface.game-list").awaitExistence(timeout: 5)'),
    storage.find('assertCanonicalRow(assetID: quotaReclaimAssetID'),
    storage.find('assertCanonicalRow(assetID: quotaDownloadAssetID'),
]
if any(marker < 0 for marker in markers) or markers != sorted(markers):
    raise SystemExit("storage canonical proof must return through Home, reveal List, and assert both rows after mutation")
if "launchStorageProfile" in storage or "harness.relaunch" in storage:
    raise SystemExit("storage canonical proof must inspect post-mutation state without reseeding")
PY
grep -F 'action.frame,' "$STORAGE_TEST" >/dev/null
grep -F 'exactIdentity.frame,' "$STORAGE_TEST" >/dev/null
grep -F 'List(selection: $selectedListEntryID)' "$LIBRARY_SHELL" >/dev/null
# The List iterates the entries it was handed, through the sort the user
# chose (WINDOWS #79) -- `ordered` is `LibrarySortOption.sortedEntries(entries,
# by: librarySort)` on the line above, so this still pins "one row per
# catalogue entry, tagged by id", which is what the selection and
# Download-selected paths below depend on. Both halves are asserted so a
# future edit cannot silently drop the ordering and keep the ForEach.
grep -F 'let ordered = LibrarySortOption.sortedEntries(entries, by: librarySort)' "$LIBRARY_SHELL" >/dev/null
grep -F 'ForEach(ordered) { entry in' "$LIBRARY_SHELL" >/dev/null
if grep -F '.accessibilityIdentifier("playstead.game.\(entry.id).row")' "$LIBRARY_SHELL" >/dev/null; then
  printf 'selectable List row identity must not overwrite descendant Download AX identity\n' >&2
  exit 1
fi
# WINDOWS #83: the "no matches" state promised by 03-UI-SPEC's Copywriting
# Contract was computed, unit-tested and snapshot-tested while no view read it,
# so a search miss showed the empty-library pairing prompt over a full library.
# Both layouts must reach `NoMatchesView` from `library.searchResultState`.
#
# Comments are stripped before matching on purpose. This file's own prose names
# `searchResultState`, and so does LibraryShellView's -- a whole-file grep here
# would be satisfied by a doc comment over a gutted body, which is exactly how
# a guard goes vacuous.
python3 - "$LIBRARY_SHELL" <<'NOMATCH'
import re, sys

source = open(sys.argv[1]).read()
code = "\n".join(re.sub(r"//.*$", "", line) for line in source.splitlines())

binding = code.count("if let state = library.searchResultState {")
renders = code.count("NoMatchesView(state: state) { library.clearSearch() }")
if binding != 2 or renders != 2:
    sys.exit(
        "both layouts must render NoMatchesView from searchResultState "
        f"(bindings={binding}, renders={renders}, expected 2 and 2)"
    )

# The pairing prompt must stay behind an empty catalogue, never be the
# fall-through for a search that matched nothing.
if "} else if !library.catalogue.isEmpty {" not in code:
    sys.exit("the empty-list pane no longer distinguishes an empty library from an empty filter result")
NOMATCH
grep -F '.focused($libraryListHasFocus)' "$LIBRARY_SHELL" >/dev/null
python3 - "$LIBRARY_SHELL" <<'PY'
import pathlib, sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
focus = source.split(".focused($libraryListHasFocus)", 1)[1].split(".listStyle(.inset)", 1)[0]
yielded = focus.find("await Task.yield()")
assigned = focus.find("libraryListHasFocus = true")
if "Task { @MainActor in" not in focus or yielded < 0 or assigned <= yielded:
    raise SystemExit("library List focus must resume after the destination route settles")
PY
grep -F '.keyboardShortcut("d", modifiers: .command)' "$LIBRARY_SHELL" >/dev/null
grep -F 'downloadCommand = LibraryDownloadCommand(' "$LIBRARY_SHELL" >/dev/null
grep -F '.onChange(of: downloadCommand)' "$GAME_ROW" >/dev/null
[ "$(grep -Fc '.keyboardShortcut("d", modifiers: .command)' "$LIBRARY_SHELL")" -eq 1 ]
# The library List's focus is set only in its appearance lifecycle, after the
# destination route has yielded a main-actor turn (covered by the ordered check
# above). Keep a single assignment so keyboard focus cannot be stolen later.
if [ "$(grep -Fc 'libraryListHasFocus = true' "$LIBRARY_SHELL")" -ne 1 ]; then
  printf 'library List focus must have one appearance-lifecycle assignment\n' >&2
  exit 1
fi
if grep -F '.keyboardShortcut(' "$GAME_ROW" >/dev/null; then
  printf 'row-local duplicate download shortcuts are forbidden\n' >&2
  exit 1
fi
python3 - "$STORAGE_TEST" <<'PY'
import pathlib, sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
selection = source.split("private func selectQuotaDownloadByKeyboard()", 1)[1].split("private func activateSelectedDownloadByKeyboard()", 1)[0]
markers = [
    selection.find('XCTAssertEqual(list.value as? String, "Synthetic Quota Download")'),
    selection.find('list.typeKey(.downArrow, modifierFlags: [])'),
    selection.find('XCTAssertEqual(list.value as? String, "Synthetic Reclaim Candidate")'),
    selection.find('list.typeKey(.upArrow, modifierFlags: [])'),
    selection.find('XCTAssertEqual(list.value as? String, "Synthetic Quota Download")', selection.find('list.typeKey(.upArrow, modifierFlags: [])')),
]
if any(marker < 0 for marker in markers) or markers != sorted(markers):
    raise SystemExit("keyboard test must prove exact List selection before, between, and after arrow movement")
PY
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

def brace_matched_body(source, opener):
    """The text between `opener`'s trailing '{' and its matching '}'.

    A plain `.split('}', 1)` stops at the first nested closure's brace, which
    silently truncates the body and turns any later marker into a false
    violation. Braces inside string literals are not tracked; no Swift button
    body in this repo contains one, and a naive split handled them no better.
    """
    start = source.index(opener) + len(opener)
    depth = 1
    for offset in range(start, len(source)):
        character = source[offset]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return source[start:offset]
    raise SystemExit(f"unbalanced braces after {opener!r}")


for path in map(pathlib.Path, sys.argv[1:]):
    source = path.read_text(encoding="utf-8")
    action = brace_matched_body(source, 'Button("Reclaim selected") {')
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
grep -F -- '--run-unprivileged-verification' "$WORKFLOW" >/dev/null || {
  printf 'the hosted macOS job must run the no-HID ordinary lane\n' >&2
  exit 1
}
grep -F 'name: mac-ordinary-evidence' "$WORKFLOW" >/dev/null || {
  printf 'the ordinary macOS lane must publish its sanitized evidence\n' >&2
  exit 1
}
python3 - "$WORKFLOW" <<'PY_RUNNER'
import pathlib, re, sys

workflow = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")

# This is trusted-code regression coverage only. A fork can modify both the
# workflow and this guard, so runner availability/access policy is the actual
# security boundary for public pull requests.
runner_specs = []
lines = workflow.splitlines()
index = 0
while index < len(lines):
    match = re.match(r"^([ \t]*)runs-on[ \t]*:[ \t]*(.*)$", lines[index])
    if not match:
        index += 1
        continue
    indent = len(match.group(1))
    spec = [match.group(2).split("#", 1)[0]]
    index += 1
    while index < len(lines):
        current = lines[index]
        stripped = current.lstrip()
        if not stripped or stripped.startswith("#"):
            index += 1
            continue
        current_indent = len(current) - len(stripped)
        if current_indent <= indent:
            break
        spec.append(current.split("#", 1)[0])
        index += 1
    runner_specs.append(" ".join(spec))

if not runner_specs:
    raise SystemExit("CI workflow must declare inspectable runner targets")

allowed_hosted_targets = {"ubuntu-24.04", "macos-26"}

def is_allowed_hosted_target(spec):
    normalized = spec.strip().strip("[]").strip().strip("\"'")
    return normalized in allowed_hosted_targets

if any(not is_allowed_hosted_target(spec) for spec in runner_specs):
    raise SystemExit("public CI runner targets must stay on the reviewed GitHub-hosted labels")
for unsafe_target in (
    "[self-hosted, macOS, playstead-virtual-hid]",
    "playstead-virtual-hid",
    "${{ vars.PLAYSTEAD_RUNNER }}",
):
    if is_allowed_hosted_target(unsafe_target):
        raise SystemExit(f"runner guard accepted an unsafe target: {unsafe_target}")
if "--run-entitled-virtual-gamepad-verification" in workflow:
    raise SystemExit("public pull-request CI must not invoke the entitled virtual-gamepad lane")
if re.search(r"(?m)^\s*mac-entitled-virtual-gamepad\s*:", workflow):
    raise SystemExit("public pull-request CI must not define the entitled runner job")

print("public workflow runner trust-boundary regression guard: passed")
PY_RUNNER
python3 - "$WORKFLOW" <<'PY_GATE'
import pathlib, sys
workflow = pathlib.Path(sys.argv[1]).read_text()
gate = workflow.find("--self-test-contracts")
build = workflow.find("--run-unprivileged-verification")
if gate < 0 or build < 0 or gate > build:
    raise SystemExit("the static contract gate must run before the ordinary no-HID Mac job")
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
grep -F 'path: playstead-mac/.build/ci/ordinary-failure-evidence' "$WORKFLOW" >/dev/null
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
[ "$(grep -c 'CODE_SIGN_ENTITLEMENTS = "$(PLAYSTEAD_UI_TEST_ENTITLEMENTS)";' "$PBXPROJ")" -eq 2 ]
[ "$(grep -Ec 'PLAYSTEAD_UI_TEST_ENTITLEMENTS = "?PlaysteadUITests/PlaysteadUITests\.no-hid\.entitlements"?;' "$PBXPROJ")" -eq 2 ]
[ "$(grep -c 'CODE_SIGN_IDENTITY = "-";' "$PBXPROJ")" -eq 6 ]
[ "$(grep -c 'CODE_SIGN_STYLE = Manual;' "$PBXPROJ")" -eq 6 ]
[ "$(grep -c 'DEVELOPMENT_TEAM = "";' "$PBXPROJ")" -eq 6 ]
[ "$(grep -c 'PROVISIONING_PROFILE_SPECIFIER = "";' "$PBXPROJ")" -eq 6 ]
if grep -F 'REPLACE_WITH_YOUR_TEAM_ID' "$PBXPROJ" >/dev/null; then
  printf 'ordinary Xcode targets must not require a placeholder Apple team\n' >&2
  exit 1
fi
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
python3 - "$PG_STARTUP_CLASSIFIER" "$PHOENIX_STARTUP_CLASSIFIER" "$PHOENIX_HEALTH_CLASSIFIER" "$XCODE_FAILURE_CLASSIFIER" <<'PGCLASS'
import pathlib, subprocess, sys, tempfile

pg_classifier, phoenix_classifier, probe_classifier, xcode_classifier = sys.argv[1:5]
allowed = {"shared_memory", "port_binding", "permission", "resource_exhaustion", "config_or_data", "log_missing", "unknown"}
phoenix_allowed = {"listener", "db_connection", "endpoint_name", "certificate_trust", "protocol", "cipher", "handshake", "runtime_exit", "readiness_timeout", "log_missing", "unknown"}
probe_allowed = {"certificate_trust", "endpoint_name", "protocol", "cipher", "handshake", "listener", "unknown"}
xcode_allowed = {"compile", "signing", "package_resolution", "test_plan_selection", "simulator_runner", "unknown", "log_missing"}
private_marker = "PRIVATE_PATH_AND_USER_MUST_NEVER_ESCAPE"
with tempfile.TemporaryDirectory() as directory:
    log_path = pathlib.Path(directory) / "postgres.log"
    log_path.write_text(f"FATAL: could not create shared memory segment for {private_marker}\n", encoding="utf-8")
    result = subprocess.run([sys.executable, pg_classifier, str(log_path)], capture_output=True, text=True, check=True)
    if result.stdout.strip() not in allowed or result.stdout != "shared_memory\n" or result.stderr or private_marker in result.stdout + result.stderr:
        raise SystemExit("PostgreSQL classifier did not emit a category-only shared-memory result")
    log_path.write_text(f"unclassified diagnostic {private_marker}\n", encoding="utf-8")
    result = subprocess.run([sys.executable, pg_classifier, str(log_path)], capture_output=True, text=True, check=True)
    if result.stdout.strip() not in allowed or result.stdout != "unknown\n" or result.stderr or private_marker in result.stdout + result.stderr:
        raise SystemExit("PostgreSQL classifier leaked or misclassified unrecognized log content")
    result = subprocess.run([sys.executable, pg_classifier, str(pathlib.Path(directory) / "absent.log")], capture_output=True, text=True, check=True)
    if result.stdout != "log_missing\n" or result.stderr:
        raise SystemExit("PostgreSQL classifier did not safely classify a missing log")
    phoenix_log = pathlib.Path(directory) / "phoenix.log"
    phoenix_log.write_text(f"TLS alert Protocol Version at {private_marker}\n", encoding="utf-8")
    result = subprocess.run([sys.executable, phoenix_classifier, str(phoenix_log), "deadline"], capture_output=True, text=True, check=True)
    if result.stdout.strip() not in phoenix_allowed or result.stdout != "protocol\n" or result.stderr or private_marker in result.stdout + result.stderr:
        raise SystemExit("Phoenix classifier did not emit only its protocol category")
    for diagnostic, expected in (("unknown ca", "certificate_trust"), ("IP address mismatch", "endpoint_name"), ("no shared cipher", "cipher"), ("handshake failure", "handshake"), ("EADDRINUSE", "listener")):
        phoenix_log.write_text(f"TLS startup diagnostic {diagnostic} {private_marker}\n", encoding="utf-8")
        result = subprocess.run([sys.executable, phoenix_classifier, str(phoenix_log), "deadline"], capture_output=True, text=True, check=True)
        if result.stdout.strip() not in phoenix_allowed or result.stdout != expected + "\n" or result.stderr or private_marker in result.stdout + result.stderr:
            raise SystemExit("Phoenix log classifier returned an unsafe or incorrect TLS subtype")
    phoenix_log.write_text(f"unrecognized diagnostic {private_marker}\n", encoding="utf-8")
    result = subprocess.run([sys.executable, phoenix_classifier, str(phoenix_log), "deadline"], capture_output=True, text=True, check=True)
    if result.stdout.strip() not in phoenix_allowed or result.stdout != "readiness_timeout\n" or result.stderr or private_marker in result.stdout + result.stderr:
        raise SystemExit("Phoenix classifier leaked unrecognized log content")
    result = subprocess.run([sys.executable, phoenix_classifier, str(pathlib.Path(directory) / "absent-phoenix.log"), "exited"], capture_output=True, text=True, check=True)
    if result.stdout != "log_missing\n" or result.stderr:
        raise SystemExit("Phoenix classifier did not safely classify a missing log")
    for code, expected in (("10", "certificate_trust"), ("11", "endpoint_name"), ("12", "protocol"), ("13", "cipher"), ("14", "handshake"), ("15", "listener"), ("16", "unknown"), ("99", "unknown")):
        result = subprocess.run([sys.executable, probe_classifier, code], capture_output=True, text=True, check=True)
        if result.stdout.strip() not in probe_allowed or result.stdout != expected + "\n" or result.stderr:
            raise SystemExit("health probe exit classifier emitted a non-enum result")
    xcode_log = pathlib.Path(directory) / "xcodebuild.log"
    for diagnostic, expected in (("Swift compiler error: failed to emit module", "compile"), ("error: Signing for AppTarget requires a development team", "signing"), ("Unable to resolve package dependencies", "package_resolution"), ("No tests found in selected test plan", "test_plan_selection"), ("Unable to boot test runner", "simulator_runner")):
        xcode_log.write_text(f"{diagnostic} {private_marker} /private/secret/user-path\n", encoding="utf-8")
        result = subprocess.run([sys.executable, xcode_classifier, str(xcode_log)], capture_output=True, text=True, check=True)
        if result.stdout.strip() not in xcode_allowed or result.stdout != expected + "\n" or result.stderr or private_marker in result.stdout + result.stderr or "/private/secret" in result.stdout + result.stderr:
            raise SystemExit("xcodebuild classifier leaked details or misclassified its fixed category")
    xcode_log.write_text(f"CodeSign /private/secret/user-path {private_marker}\nSwiftCompile normal arm64\n", encoding="utf-8")
    result = subprocess.run([sys.executable, xcode_classifier, str(xcode_log)], capture_output=True, text=True, check=True)
    if result.stdout.strip() not in xcode_allowed or result.stdout != "unknown\n" or result.stderr or private_marker in result.stdout + result.stderr or "/private/secret" in result.stdout + result.stderr:
        raise SystemExit("routine signing/compiler progress must not be classified as a signing failure")
    xcode_log.write_text(f"unrecognized xcode output {private_marker}\n", encoding="utf-8")
    result = subprocess.run([sys.executable, xcode_classifier, str(xcode_log)], capture_output=True, text=True, check=True)
    if result.stdout.strip() not in xcode_allowed or result.stdout != "unknown\n" or result.stderr or private_marker in result.stdout + result.stderr:
        raise SystemExit("xcodebuild classifier leaked an unrecognized diagnostic")
    result = subprocess.run([sys.executable, xcode_classifier, str(pathlib.Path(directory) / "absent-xcode.log")], capture_output=True, text=True, check=True)
    if result.stdout != "log_missing\n" or result.stderr:
        raise SystemExit("xcodebuild classifier did not safely classify a missing log")
print("PostgreSQL, Phoenix, and Xcode classifier contracts: passed")
PGCLASS

printf 'four-layer topology contract: passed\n'
