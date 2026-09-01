#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
REPO_ROOT="$(cd "${MAC_ROOT}/.." && pwd)"
RUNNER="${MAC_ROOT}/scripts/ci/run-mac-verification.sh"
SCHEME="${MAC_ROOT}/Playstead.xcodeproj/xcshareddata/xcschemes/Playstead.xcscheme"
APP_ENTRY="${MAC_ROOT}/Playstead/App/PlaysteadApp.swift"
UI_CANARY="${MAC_ROOT}/PlaysteadUITests/HostedRunnerCanaryTests.swift"
WORKFLOW="${REPO_ROOT}/.github/workflows/ci.yml"
REFRESH_WORKFLOW="${REPO_ROOT}/.github/workflows/mac-snapshot-refresh.yml"
SANITIZER="${MAC_ROOT}/scripts/ci/sanitize-evidence.sh"
PROMPT_SAFETY="${MAC_ROOT}/scripts/ci/tests/keychain-prompt-safety-test.sh"
KEYBOARD_CLEANUP="${MAC_ROOT}/scripts/ci/tests/keyboard-mode-cleanup-test.sh"

for file in "$RUNNER" "$SCHEME" "$APP_ENTRY" "$UI_CANARY" "$WORKFLOW" "$REFRESH_WORKFLOW" "$SANITIZER" "$PROMPT_SAFETY" "$KEYBOARD_CLEANUP"; do
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
import json, pathlib, sys

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

printf 'four-layer topology contract: passed\n'
