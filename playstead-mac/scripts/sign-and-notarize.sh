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
#
# `PLAYSTEAD_REQUIRE_NOTARIZATION=1` (03-12, Gap B) turns that graceful
# degrade into a hard failure: the Developer ID identity check runs
# unconditionally (not only when a notary profile happens to be set), a
# missing notary profile is `FATAL: NO_NOTARY_PROFILE` instead of an
# informational deferral, and the Gatekeeper assertion requires the
# assessment to name a notarized source rather than accepting the bare word
# "accepted" (a locally-signed build can also produce that word). Default
# (unset) behavior is byte-for-byte unchanged from before this flag existed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$PROJECT_DIR/build/Release/Playstead.app"
PLAYSTEAD_NOTARY_PROFILE="${PLAYSTEAD_NOTARY_PROFILE:-}"
PLAYSTEAD_REQUIRE_NOTARIZATION="${PLAYSTEAD_REQUIRE_NOTARIZATION:-}"

if [ ! -d "$APP_PATH" ]; then
  echo "FATAL: $APP_PATH not found — run scripts/build-release.sh first." >&2
  exit 1
fi

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "==> Confirming hardened runtime and non-sandboxed entitlements"
# Captured into a variable rather than piped live into `grep`, for the
# same SIGPIPE-under-pipefail reason documented below for
# CODESIGN_DETAILS. Actually asserts the app-sandbox key's VALUE is
# false — a bare `grep -A1 | ` only confirmed the key's presence and
# printed the following line for a human to notice, which would not
# catch a regression that accidentally ships with sandboxing enabled
# (breaking D-04's non-sandboxed-launch requirement) since this
# script's own set -e/pipefail guard never inspected the value (P2-WR-003).
ENTITLEMENTS="$(codesign -d --entitlements :- "$APP_PATH" 2>/dev/null)"
if grep -A1 'com.apple.security.app-sandbox' <<< "$ENTITLEMENTS" | grep -q '<true/>'; then
  echo "FATAL: $APP_PATH is App-Sandboxed; D-04 requires a non-sandboxed build." >&2
  exit 1
fi
echo "$ENTITLEMENTS" | grep -A1 'com.apple.security.app-sandbox'

echo "==> Confirming the hardened runtime flag is set"
# Captured into a variable (not piped live into `grep -q`) so an early
# `grep -q` match/exit can never SIGPIPE the still-writing `codesign`
# process and, under `set -o pipefail`, misreport that as a failure —
# a real gotcha this script previously tripped over.
#
# -dvvv (not -dv) is required here: `codesign -dv` never prints the
# `Authority=` chain at all (verified against a real Developer ID
# Application signature on 2026-09-10 — the flags=0x10000(runtime) line
# is present at -dv but Authority= is not), so the strict-mode Developer
# ID Application check below always failed even on a genuinely
# Developer-ID-signed build. -dvvv adds Authority= lines while leaving
# every other field (including flags=) unchanged.
CODESIGN_DETAILS="$(codesign -dvvv --deep --strict "$APP_PATH" 2>&1)"
if ! grep -q 'flags=0x10000(runtime)' <<< "$CODESIGN_DETAILS"; then
  echo "FATAL: $APP_PATH is not signed with the hardened runtime (expected flags=0x10000(runtime))." >&2
  exit 1
fi

# T-03-28: the emulator is installed separately at runtime by design
# (never bundled) — a nested .app inside the exported bundle would
# couple this app's own notarization to a third party's release
# cadence, and is never expected to appear here. Fail loudly if one
# ever does.
echo "==> Confirming no nested application bundle is present"
NESTED_APPS="$(find "$APP_PATH" -name '*.app' -not -path "$APP_PATH")"
if [ -n "$NESTED_APPS" ]; then
  echo "FATAL: nested application bundle(s) found inside $APP_PATH:" >&2
  echo "$NESTED_APPS" >&2
  exit 1
fi

if [ "$PLAYSTEAD_REQUIRE_NOTARIZATION" = "1" ]; then
  echo "==> [strict] Confirming a Developer ID Application signature is present"
  if ! grep -q 'Developer ID Application' <<< "$CODESIGN_DETAILS"; then
    echo "FATAL: NO_DEVELOPER_ID_IDENTITY" >&2
    exit 1
  fi
fi

if [ -n "$PLAYSTEAD_NOTARY_PROFILE" ]; then
  if [ "$PLAYSTEAD_REQUIRE_NOTARIZATION" != "1" ]; then
    echo "==> Confirming a Developer ID Application signature is present"
    if ! grep -q 'Developer ID Application' <<< "$CODESIGN_DETAILS"; then
      echo "FATAL: PLAYSTEAD_NOTARY_PROFILE is set but $APP_PATH is not signed with a Developer ID Application identity." >&2
      exit 1
    fi
  fi

  # notarytool rejects a raw .app bundle outright ("must be a zip archive
  # (.zip), flat installer package (.pkg), or UDIF disk image (.dmg)") — it
  # never got a chance to accept or reject the signature. The submission
  # archive is a temporary artifact only; the notarization ticket is
  # stapled onto the original $APP_PATH directory below, never onto the zip.
  NOTARIZE_ZIP="$(mktemp -u "${TMPDIR:-/tmp}"/playstead-notarize-XXXXXX).zip"
  trap 'rm -f "$NOTARIZE_ZIP"' EXIT
  echo "==> Creating submission archive for notarytool"
  ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"

  echo "==> Submitting for notarization (profile: $PLAYSTEAD_NOTARY_PROFILE)"
  xcrun notarytool submit "$NOTARIZE_ZIP" --keychain-profile "$PLAYSTEAD_NOTARY_PROFILE" --wait

  rm -f "$NOTARIZE_ZIP"
  trap - EXIT

  echo "==> Stapling notarization ticket"
  xcrun stapler staple "$APP_PATH"

  echo "==> Asserting Gatekeeper acceptance"
  SPCTL_RESULT="$(spctl --assess --type execute --verbose "$APP_PATH" 2>&1)"
  echo "$SPCTL_RESULT"
  if [ "$PLAYSTEAD_REQUIRE_NOTARIZATION" = "1" ]; then
    # Strict mode requires the assessment to NAME a notarized source, not
    # merely contain the word "accepted" — a locally-signed (non-notarized)
    # build can also be "accepted" for other reasons (e.g. an explicit user
    # override), and that must never read as a notarized-release pass.
    if ! grep -q 'source=Notarized Developer ID' <<< "$SPCTL_RESULT"; then
      echo "FATAL: GATEKEEPER_REJECTED" >&2
      exit 1
    fi
  else
    if ! grep -q accepted <<< "$SPCTL_RESULT"; then
      echo "FATAL: spctl did not accept the notarized, stapled build." >&2
      exit 1
    fi
  fi
else
  if [ "$PLAYSTEAD_REQUIRE_NOTARIZATION" = "1" ]; then
    echo "FATAL: NO_NOTARY_PROFILE" >&2
    exit 1
  fi
  echo "==> PLAYSTEAD_NOTARY_PROFILE is empty — notarization DEFERRED (no paid Apple Developer Program membership)."
  echo "    This is the recorded, owner-approved posture for this phase; see 03-ADAPTER-PIN.json's"
  echo "    'deferred' section and 03-01-SUMMARY.md. spctl acceptance for a non-notarized build is"
  echo "    expected to differ from 'source=Notarized Developer ID' until a paid membership is enrolled."
  echo "    The notarization-dependent verification steps above (Developer ID identity check,"
  echo "    notarytool submit --wait, stapler staple, Gatekeeper 'accepted' assertion) are skipped"
  echo "    entirely in this branch — they are never simulated or faked."
  echo "==> spctl --assess result for the dev-signed/unnotarized build (informational only):"
  spctl --assess --type execute --verbose "$APP_PATH" 2>&1 || true
fi

echo "==> Done: $APP_PATH"
