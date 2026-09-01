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

for file in "$RUNNER" "$SCHEME" "$APP_ENTRY" "$UI_CANARY" "$WORKFLOW"; do
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

python3 - "${MAC_ROOT}/TestPlans" "$APP_ENTRY" <<'PY'
import json, pathlib, sys

plans_root = pathlib.Path(sys.argv[1])
app_source = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
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

printf 'four-layer topology contract: passed\n'
