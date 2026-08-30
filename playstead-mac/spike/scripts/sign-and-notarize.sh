#!/usr/bin/env bash
# Builds SpikeHost (Swift Package executable), assembles a real .app bundle,
# and signs it with the hardened runtime enabled.
#
# Notarization is DEFERRED per the 2026-08-30 owner decision recorded in
# 03-01-SUMMARY.md: this Playstead installation is not enrolled in the paid
# Apple Developer Program, so there is no Developer ID Application certificate
# and no notarytool credential profile. This script dev-signs with
# PLAYSTEAD_DEV_ID_APP (an "Apple Development: ..." identity) instead of a
# "Developer ID Application: ..." identity, and skips the notarytool
# submit/staple steps entirely when PLAYSTEAD_NOTARY_PROFILE is unset/empty.
#
# When notarization *is* available in a future run (paid membership present),
# set PLAYSTEAD_DEV_ID_APP to a "Developer ID Application: ..." identity and
# PLAYSTEAD_NOTARY_PROFILE to a notarytool keychain profile name; this script
# runs the full submit --wait / staple / spctl "Notarized Developer ID" path
# unchanged.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIKE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOST_DIR="$SPIKE_DIR/SpikeHost"
BUILD_DIR="$SPIKE_DIR/build"
APP_PATH="$BUILD_DIR/Release/SpikeHost.app"

: "${PLAYSTEAD_DEV_ID_APP:?PLAYSTEAD_DEV_ID_APP must be set to a signing identity name}"
: "${PLAYSTEAD_TEAM_ID:?PLAYSTEAD_TEAM_ID must be set}"
PLAYSTEAD_NOTARY_PROFILE="${PLAYSTEAD_NOTARY_PROFILE:-}"

echo "==> Building SpikeHost (release, universal arm64+x86_64)"
cd "$HOST_DIR"
BUILD_ARCH_FLAGS=(--arch arm64 --arch x86_64)
if ! swift build -c release "${BUILD_ARCH_FLAGS[@]}"; then
  echo "==> Universal build failed; falling back to host-arch-only build"
  BUILD_ARCH_FLAGS=()
  swift build -c release
fi
# --show-bin-path MUST be called with the identical --arch flags used above —
# omitting them resolves to a different (and possibly stale/non-universal)
# .build subdirectory, silently shipping an out-of-date binary (found and
# fixed this session: it was serving a binary built before launch-and-terminate
# existed).
BUILT_BINARY="$(swift build -c release "${BUILD_ARCH_FLAGS[@]}" --show-bin-path)/SpikeHost"

if [ ! -f "$BUILT_BINARY" ]; then
  echo "FATAL: expected built binary not found at $BUILT_BINARY" >&2
  exit 1
fi

echo "==> Assembling .app bundle at $APP_PATH"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BUILT_BINARY" "$APP_PATH/Contents/MacOS/SpikeHost"
cp "$HOST_DIR/Info.plist" "$APP_PATH/Contents/Info.plist"

echo "==> Recording environment (macOS build under test)"
mkdir -p "$SPIKE_DIR/out"
sw_vers -productVersion > /dev/null # fail fast if sw_vers is unavailable
python3 - "$SPIKE_DIR/out/environment.json" <<'PYEOF'
import json, subprocess, sys, datetime
path = sys.argv[1]
product = subprocess.check_output(["sw_vers", "-productVersion"]).decode().strip()
build = subprocess.check_output(["sw_vers", "-buildVersion"]).decode().strip()
with open(path, "w") as f:
    json.dump({
        "macos_product_version": product,
        "macos_build_version": build,
        "recorded_at": datetime.datetime.utcnow().isoformat() + "Z"
    }, f, indent=2, sort_keys=True)
PYEOF

echo "==> Code-signing with hardened runtime: $PLAYSTEAD_DEV_ID_APP"
codesign --force --deep --options runtime --timestamp \
  --entitlements "$HOST_DIR/SpikeHost.entitlements" \
  --sign "$PLAYSTEAD_DEV_ID_APP" \
  "$APP_PATH"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

if [ -n "$PLAYSTEAD_NOTARY_PROFILE" ]; then
  echo "==> Submitting for notarization (profile: $PLAYSTEAD_NOTARY_PROFILE)"
  xcrun notarytool submit "$APP_PATH" --keychain-profile "$PLAYSTEAD_NOTARY_PROFILE" --wait
  echo "==> Stapling notarization ticket"
  xcrun stapler staple "$APP_PATH"
  echo "==> Asserting notarized acceptance"
  spctl --assess --type execute --verbose "$APP_PATH"
else
  echo "==> PLAYSTEAD_NOTARY_PROFILE is empty — notarization DEFERRED (no paid Apple Developer Program membership)."
  echo "    Recording dev-signed evidence instead of a notarized spctl acceptance."
  echo "==> spctl --assess result for the dev-signed build (expected: NOT 'source=Notarized Developer ID'):"
  spctl --assess --type execute --verbose "$APP_PATH" 2>&1 || true
fi

echo "==> Done: $APP_PATH"
