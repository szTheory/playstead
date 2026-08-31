#!/usr/bin/env bash
# Verifies the code signature of the built Playstead.app (produced by
# build-release.sh) and, when a notary keychain profile is configured,
# submits it for notarization, staples the ticket, and asserts Gatekeeper
# acceptance. Mirrors the spike's proven `spike/scripts/sign-and-notarize.sh`
# script for the shipping client.
#
# Notarization is DEFERRED for this run per the 2026-08-30 owner decision
# recorded in `.planning/phases/03-mac-offline-play-vertical-slice/03-ADAPTER-PIN.json`
# (`deferred.probe_01_notarized_launch`): no paid Apple Developer Program
# membership is configured for this Playstead installation, so there is no
# Developer ID Application certificate and no notarytool credential profile
# available in this environment. `xcodebuild archive`/`-exportArchive`
# already require a real `PLAYSTEAD_DEV_ID_APP`/`PLAYSTEAD_TEAM_ID` to run at
# all (see build-release.sh) — this script's own behavior additionally
# degrades gracefully to "verify signature only" when PLAYSTEAD_NOTARY_PROFILE
# is unset, exactly like the spike, rather than failing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$PROJECT_DIR/build/Release/Playstead.app"
PLAYSTEAD_NOTARY_PROFILE="${PLAYSTEAD_NOTARY_PROFILE:-}"

if [ ! -d "$APP_PATH" ]; then
  echo "FATAL: $APP_PATH not found — run scripts/build-release.sh first." >&2
  exit 1
fi

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "==> Confirming hardened runtime and non-sandboxed entitlements"
codesign -d --entitlements - "$APP_PATH" | grep -A1 'com.apple.security.app-sandbox'

if [ -n "$PLAYSTEAD_NOTARY_PROFILE" ]; then
  echo "==> Submitting for notarization (profile: $PLAYSTEAD_NOTARY_PROFILE)"
  xcrun notarytool submit "$APP_PATH" --keychain-profile "$PLAYSTEAD_NOTARY_PROFILE" --wait
  echo "==> Stapling notarization ticket"
  xcrun stapler staple "$APP_PATH"
  echo "==> Asserting notarized acceptance"
  spctl --assess --type execute --verbose "$APP_PATH"
else
  echo "==> PLAYSTEAD_NOTARY_PROFILE is empty — notarization DEFERRED (no paid Apple Developer Program membership)."
  echo "    This is the recorded, owner-approved posture for this phase; see 03-ADAPTER-PIN.json's"
  echo "    'deferred' section and 03-01-SUMMARY.md. spctl acceptance for a non-notarized build is"
  echo "    expected to differ from 'source=Notarized Developer ID' until plan 03-10 closes this gap."
  echo "==> spctl --assess result for the dev-signed/unnotarized build (informational only):"
  spctl --assess --type execute --verbose "$APP_PATH" 2>&1 || true
fi

echo "==> Done: $APP_PATH"
