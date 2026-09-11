#!/usr/bin/env bash
# The single end-to-end command that proves PLAY-05 against a genuinely
# notarized artifact: preflight -> build -> sign+notarize (strict) ->
# staple validation -> Gatekeeper assessment -> launch/exit/relaunch.
#
# `--preflight-only` runs only the identity/credential preflight and stops —
# this is what `notarization-preflight-test.sh` and CI exercise to prove the
# refusal fires without needing a real build or paid credentials.
#
# Every failure path exits non-zero and prints exactly one of these tokens
# to stderr: NO_TEAM_ID, NO_DEVELOPER_ID_IDENTITY, NO_NOTARY_PROFILE,
# NOT_STAPLED, GATEKEEPER_REJECTED. Never a credential, a profile's stored
# contents, or an app-specific password.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$PROJECT_DIR/build/Release/Playstead.app"

PREFLIGHT_ONLY=0
if [ "${1:-}" = "--preflight-only" ]; then
  PREFLIGHT_ONLY=1
fi

preflight() {
  echo "==> Preflight: checking required environment variables"
  if [ -z "${PLAYSTEAD_TEAM_ID:-}" ]; then
    echo "FATAL: NO_TEAM_ID" >&2
    exit 1
  fi
  if [ -z "${PLAYSTEAD_DEV_ID_APP:-}" ]; then
    echo "FATAL: NO_DEVELOPER_ID_IDENTITY" >&2
    exit 1
  fi
  if [ -z "${PLAYSTEAD_NOTARY_PROFILE:-}" ]; then
    echo "FATAL: NO_NOTARY_PROFILE" >&2
    exit 1
  fi

  echo "==> Preflight: checking for a Developer ID Application codesigning identity"
  # Captured into a variable with the exit code recorded explicitly, not
  # tested live in an `if cmd | grep -q` pipeline — a missing `security`
  # binary would exit 127, which a bare `if` reads as "clean" (the fail-open
  # shape this repo has been bitten by four times before).
  set +e
  IDENTITY_OUTPUT="$(security find-identity -v -p codesigning 2>&1)"
  IDENTITY_STATUS=$?
  set -e
  if [ "$IDENTITY_STATUS" -ne 0 ]; then
    echo "FATAL: NO_DEVELOPER_ID_IDENTITY" >&2
    exit 1
  fi
  if ! grep -q 'Developer ID Application' <<< "$IDENTITY_OUTPUT"; then
    echo "FATAL: NO_DEVELOPER_ID_IDENTITY" >&2
    exit 1
  fi

  echo "==> Preflight: checking notarytool credential profile"
  set +e
  NOTARY_OUTPUT="$(xcrun notarytool history --keychain-profile "$PLAYSTEAD_NOTARY_PROFILE" 2>&1)"
  NOTARY_STATUS=$?
  set -e
  if [ "$NOTARY_STATUS" -ne 0 ]; then
    echo "FATAL: NO_NOTARY_PROFILE" >&2
    exit 1
  fi

  echo "==> Preflight passed"
}

preflight

if [ "$PREFLIGHT_ONLY" -eq 1 ]; then
  exit 0
fi

echo "==> Building release"
"$SCRIPT_DIR/build-release.sh"

echo "==> Signing and notarizing (strict mode)"
PLAYSTEAD_REQUIRE_NOTARIZATION=1 "$SCRIPT_DIR/sign-and-notarize.sh"

echo "==> Validating the stapled notarization ticket"
set +e
STAPLE_OUTPUT="$(xcrun stapler validate "$APP_PATH" 2>&1)"
STAPLE_STATUS=$?
set -e
echo "$STAPLE_OUTPUT"
if [ "$STAPLE_STATUS" -ne 0 ]; then
  echo "FATAL: NOT_STAPLED" >&2
  exit 1
fi

echo "==> Re-asserting Gatekeeper acceptance names a notarized source"
SPCTL_RESULT="$(spctl --assess --type execute --verbose "$APP_PATH" 2>&1)"
echo "$SPCTL_RESULT"
if ! grep -q 'source=Notarized Developer ID' <<< "$SPCTL_RESULT"; then
  echo "FATAL: GATEKEEPER_REJECTED" >&2
  exit 1
fi

echo "==> Running RelaunchTests against the notarized build"
# DEVELOPMENT_TEAM overrides the project's checked-in REPLACE_WITH_YOUR_TEAM_ID
# placeholder (README.md documents that placeholder as intentional — each
# operator's machine substitutes its own local dev-signing team) for this one
# invocation only, using the same PLAYSTEAD_TEAM_ID already required by
# preflight. This is local test-signing, unrelated to the Developer ID
# release identity asserted above; RelaunchTests itself exercises LocalStore
# and CASManager directly and is code-signing-independent.
xcodebuild test \
  -project "$PROJECT_DIR/Playstead.xcodeproj" \
  -scheme Playstead \
  -destination 'platform=macOS' \
  DEVELOPMENT_TEAM="$PLAYSTEAD_TEAM_ID" \
  -only-testing:PlaysteadTests/RelaunchTests

echo "==> Launching the exported, notarized app to confirm clean exit and relaunch"
APP_BUNDLE_ID="$(defaults read "$APP_PATH/Contents/Info" CFBundleIdentifier)"

open "$APP_PATH"
sleep 3
if ! pgrep -f "$APP_PATH/Contents/MacOS/" >/dev/null; then
  echo "FATAL: notarized app failed to launch" >&2
  exit 1
fi

osascript -e "tell application id \"$APP_BUNDLE_ID\" to quit" >/dev/null
sleep 2
if pgrep -f "$APP_PATH/Contents/MacOS/" >/dev/null; then
  echo "FATAL: notarized app failed to exit cleanly" >&2
  exit 1
fi

open "$APP_PATH"
sleep 3
if ! pgrep -f "$APP_PATH/Contents/MacOS/" >/dev/null; then
  echo "FATAL: notarized app failed to relaunch" >&2
  exit 1
fi
osascript -e "tell application id \"$APP_BUNDLE_ID\" to quit" >/dev/null

echo "==> Done: $APP_PATH is signed, notarized, stapled, Gatekeeper-accepted, and relaunch-proven."
