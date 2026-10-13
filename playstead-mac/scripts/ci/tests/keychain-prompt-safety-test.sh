#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
APP_ENTRY="${MAC_ROOT}/Playstead/App/PlaysteadApp.swift"
API_CLIENT="${MAC_ROOT}/Playstead/Net/APIClient.swift"
BOOTSTRAP="${MAC_ROOT}/Playstead/UITesting/UITestBootstrap.swift"
PAIRING_TEST="${MAC_ROOT}/PlaysteadUITests/PairingCeremonyTests.swift"
TRUST_CAPTURE="${MAC_ROOT}/Playstead/Pairing/PinnedCertificateCapture.swift"
RUNNER="${MAC_ROOT}/scripts/ci/run-mac-verification.sh"

python3 - "${MAC_ROOT}/TestPlans" "$APP_ENTRY" "$API_CLIENT" "$BOOTSTRAP" "$PAIRING_TEST" "$RUNNER" "$TRUST_CAPTURE" <<'PY'
import json, pathlib, sys

plans_root = pathlib.Path(sys.argv[1])
app = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
client = pathlib.Path(sys.argv[3]).read_text(encoding="utf-8")
bootstrap = pathlib.Path(sys.argv[4]).read_text(encoding="utf-8")
pairing_test = pathlib.Path(sys.argv[5]).read_text(encoding="utf-8")
runner = pathlib.Path(sys.argv[6]).read_text(encoding="utf-8")
trust_capture = pathlib.Path(sys.argv[7]).read_text(encoding="utf-8")

for name in ("Unit", "Rendering"):
    plan = json.loads((plans_root / f"{name}.xctestplan").read_text())
    entries = plan["defaultOptions"].get("environmentVariableEntries", [])
    values = {entry["key"]: entry["value"] for entry in entries}
    if values.get("PLAYSTEAD_XCTEST_HOST_MODE") != "inert":
        raise SystemExit(f"{name}: app-host mode is not explicitly inert")

for name in ("UI", "LiveServer"):
    plan = json.loads((plans_root / f"{name}.xctestplan").read_text())
    entries = plan["defaultOptions"].get("environmentVariableEntries", [])
    if any(entry["key"] == "PLAYSTEAD_XCTEST_HOST_MODE" for entry in entries):
        raise SystemExit(f"{name}: must use its explicit launch composition, not XCTest inert mode")

app_decl = app.split("struct PlaysteadApp: App", 1)[1].split("private struct ProductionRootView", 1)[0]
if app_decl.find("XCTestHostBootstrap.isRequested()") > app_decl.find("UITestBootstrap.isRequested()"):
    raise SystemExit("inert XCTest host selection must precede every test launch branch")
inert = app.split("private struct XCTestHostInertRootView", 1)[1].split("private struct HostedRunnerLaunchCanaryView", 1)[0]
if any(token in inert for token in ("AppEnvironment(", "APIClient(", "KeychainStore(")):
    raise SystemExit("inert XCTest root constructs a production dependency")
ui_init = app.split("convenience init(\n        uiTestingPaths", 1)[1].split("    }\n#endif", 1)[0]
if "apiClient: APIClient.unpairedForUITesting()" not in ui_init or "apiClient: nil" in ui_init:
    raise SystemExit("UI profile does not fail closed with an explicit no-Keychain client")
if "static func unpairedForUITesting()" not in client or "APIClient(credentialSource: .fixed(nil))" not in client:
    raise SystemExit("no-Keychain UI API client factory is missing")
if "live pairing trust anchor is missing" not in bootstrap or 'label: "live pairing trust anchor"' not in bootstrap:
    raise SystemExit("LiveServer trust anchor must fail closed when missing or escaped")
if "expectedDigest" not in bootstrap or "SecCertificateCopyNotValidAfterDate" not in bootstrap:
    raise SystemExit("LiveServer trust anchor must validate the issued digest and expiry")
if 'https://127.0.0.1:4010' not in bootstrap or 'SecTrustSetAnchorCertificatesOnly(serverTrust, true)' not in trust_capture:
    raise SystemExit("LiveServer pairing must retain exact HTTPS loopback and anchor-only TLS validation")
if "pairing-ca.der" not in pairing_test or "PLAYSTEAD_UI_TEST_LIVE_SERVER_CA_SHA256" not in pairing_test:
    raise SystemExit("pairing test must copy and verify the wrapper-issued CA inside its owned root")
if 'mac-ci-tls.sh" trust' in runner or 'mac-ci-tls.sh" untrust' in runner or "System.keychain" in runner:
    raise SystemExit("ordinary wrapper must not mutate the System Keychain")
PY

grep -F 'if [ "${GITHUB_ACTIONS:-}" = "true" ]' "$RUNNER" >/dev/null
grep -F 'if [ "${PLAYSTEAD_HUMAN_APPROVED_LOCAL_APP_LAUNCH:-}" = "1" ]' "$RUNNER" >/dev/null
python3 - "$RUNNER" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
body = source.split("run_four_layer_verification() {", 1)[1].split("run_snapshot_candidates() {", 1)[0]
if "assert_local_app_launch_authorized" not in body:
    raise SystemExit("the four-layer runner must preserve the local app launch preflight")
PY

blocked_log="$(mktemp)"
trap 'rm -f "$blocked_log"' EXIT
if env -u GITHUB_ACTIONS -u PLAYSTEAD_HUMAN_APPROVED_LOCAL_APP_LAUNCH \
  "$RUNNER" --layers ui --only-testing NeverLaunches >"$blocked_log" 2>&1; then
  printf 'local UI layer unexpectedly passed its launch preflight\n' >&2
  exit 1
fi
grep -F 'local UI/LiveServer verification is disabled' "$blocked_log" >/dev/null
if grep -F 'xcodebuild' "$blocked_log" >/dev/null; then
  printf 'local UI guard reached xcodebuild\n' >&2
  exit 1
fi

printf 'keychain prompt safety contract: passed\n'
