#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
REPO_ROOT="$(cd "${MAC_ROOT}/.." && pwd)"

require_text() {
  local file="$1"
  local text="$2"
  grep -F -- "$text" "$file" >/dev/null || {
    printf 'missing required topology marker %s in %s\n' "$text" "$file" >&2
    exit 1
  }
}

project="$MAC_ROOT/Playstead.xcodeproj/project.pbxproj"
scheme="$MAC_ROOT/Playstead.xcodeproj/xcshareddata/xcschemes/Playstead.xcscheme"
lockfile="$MAC_ROOT/Playstead.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
config="$REPO_ROOT/playstead-server/config/mac_ci.exs"
runner="$MAC_ROOT/scripts/ci/run-mac-verification.sh"
workflow="$REPO_ROOT/.github/workflows/ci.yml"
ui_canary="$MAC_ROOT/PlaysteadUITests/HostedRunnerCanaryTests.swift"
snapshot_canary="$MAC_ROOT/PlaysteadTests/SnapshotTests/SnapshotHarnessCanaryTests.swift"
app_entry="$MAC_ROOT/Playstead/App/PlaysteadApp.swift"

for file in "$project" "$scheme" "$lockfile" "$config" "$runner" "$workflow" "$ui_canary" "$snapshot_canary" "$app_entry"; do
  [ -f "$file" ] || { printf 'required topology file missing: %s\n' "$file" >&2; exit 1; }
done

require_text "$project" 'https://github.com/pointfreeco/swift-snapshot-testing'
require_text "$project" 'version = 1.19.4;'
require_text "$lockfile" '59a99c458de4d2dee580529b61b4f78dca7b7fa6'
require_text "$config" 'ip: {127, 0, 0, 1}'
require_text "$config" 'server: true'
if grep -F 'Ecto.Adapters.SQL.Sandbox' "$config" >/dev/null; then
  printf 'mac_ci must not use the SQL sandbox\n' >&2
  exit 1
fi

require_text "$runner" 'postgresql@17'
require_text "$runner" 'MIX_ENV=mac_ci'
require_text "$runner" 'snapshot_triplets'
require_text "$runner" 'linux_jobs'
require_text "$runner" 'verify_result() ('
require_text "$runner" 'trap cleanup_native_services EXIT'
require_text "$runner" 'bootstrap.log'
require_text "$runner" 'exec mix phx.server'
require_text "$runner" 'ui_only+=("-only-testing:${identifier%%.*}/${identifier#*.}")'
require_text "$runner" '-only-testing:"${snapshot_identifier%%.*}/${snapshot_identifier#*.}"'
require_text "$runner" 'PLAYSTEAD_SNAPSHOT_CANARY_OUTPUT="$snapshot_output"'
require_text "$scheme" 'key="PLAYSTEAD_SNAPSHOT_CANARY_OUTPUT" value="$(PLAYSTEAD_SNAPSHOT_CANARY_OUTPUT)" isEnabled="YES"'
require_text "$snapshot_canary" 'appendingPathComponent(".snapshot-testing", isDirectory: true)'
if grep -F "trap 'rm -f \"\$required_file\"' RETURN" "$runner" >/dev/null; then
  printf 'verifier temp-file cleanup must not leak a RETURN trap\n' >&2
  exit 1
fi
if grep -F '@testable import Playstead' "$ui_canary" >/dev/null; then
  printf 'XCUITest canaries must not link directly against the app module\n' >&2
  exit 1
fi
require_text "$ui_canary" 'kSecUseKeychain as String'
require_text "$ui_canary" 'kSecMatchSearchList as String'
require_text "$ui_canary" 'app.launchEnvironment["PLAYSTEAD_WAVE_0_FOCUS_CANARY"] = "1"'
require_text "$app_entry" '#if DEBUG'
require_text "$app_entry" 'ProcessInfo.processInfo.environment["PLAYSTEAD_WAVE_0_FOCUS_CANARY"] == "1"'
require_text "$app_entry" 'HostedRunnerFocusCanaryView'
require_text "$workflow" 'test:'
require_text "$workflow" 'compose-smoke:'
require_text "$workflow" 'runs-on: macos-26'

printf 'wave-0 topology contract: passed\n'
