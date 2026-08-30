#!/usr/bin/env bash
# Downloads an official upstream emulator release, hash-verifies it, and
# expands it into the app-managed emulators directory with its quarantine
# extended attribute left intact (D-05/D-02/T-03-01/T-03-02).
#
# Usage: acquire-emulator.sh <candidate> <version>
#   candidate: mgba (only candidate implemented for D-02 rung 1; later rungs
#              add their own download_url case below when the ladder advances)
#   version:   upstream release tag, e.g. 0.10.5
#
# This script NEVER strips, clears, or rewrites the quarantine xattr, and
# NEVER calls spctl --add. It never provides, locates, or links a path to a
# proprietary BIOS image.
set -euo pipefail

CANDIDATE="${1:?usage: acquire-emulator.sh <candidate> <version>}"
VERSION="${2:?usage: acquire-emulator.sh <candidate> <version>}"

INSTALL_ROOT="$HOME/Library/Application Support/Playstead/emulators/$CANDIDATE/$VERSION"

case "$CANDIDATE" in
  mgba)
    DOWNLOAD_URL="https://github.com/mgba-emu/mgba/releases/download/${VERSION}/mGBA-${VERSION}-macos.dmg"
    ARCHIVE_NAME="mGBA-${VERSION}-macos.dmg"
    ;;
  *)
    echo "FATAL: unknown candidate '$CANDIDATE'. Only 'mgba' (D-02 rung 1) is implemented." >&2
    exit 1
    ;;
esac

mkdir -p "$INSTALL_ROOT"
DL_PATH="$INSTALL_ROOT/$ARCHIVE_NAME"

echo "==> Downloading $DOWNLOAD_URL"
curl -L --fail --show-error -o "$DL_PATH" "$DOWNLOAD_URL"

echo "==> Computed SHA-256:"
SHA256=$(shasum -a 256 "$DL_PATH" | awk '{print $1}')
echo "$SHA256"

# `curl` on the command line does NOT set com.apple.quarantine — that flag is
# applied by LSQuarantine-aware download paths (Safari, Mail, and Foundation's
# URLSession, which is exactly what the shipping Mac client uses per D-18).
# To faithfully test what a real download-on-demand install experiences
# (Gatekeeper evaluation, App Translocation, the D-01 probe-1 "no stripping"
# assertion), stamp the same quarantine attribute a URLSession download would
# receive onto the archive before expanding it. This ADDS the flag to match
# real client behavior — it is the opposite of stripping, and `ditto` (not
# `cp`) propagates it onto the extracted .app, verified this session.
echo "==> Simulating LSQuarantine (URLSession downloads receive this automatically; curl does not)"
xattr -w com.apple.quarantine "0083;$(date +%s | xargs printf '%08x');curl;$ARCHIVE_NAME" "$DL_PATH"

echo "==> Expanding disk image"
MOUNT_POINT=$(mktemp -d)
hdiutil attach "$DL_PATH" -mountpoint "$MOUNT_POINT" -nobrowse -quiet -readonly

APP_SOURCE=$(find "$MOUNT_POINT" -maxdepth 1 -name "*.app" | head -1)
if [ -z "$APP_SOURCE" ]; then
  hdiutil detach "$MOUNT_POINT" -quiet || true
  echo "FATAL: no .app found inside $ARCHIVE_NAME" >&2
  exit 1
fi

APP_NAME=$(basename "$APP_SOURCE")
DEST_APP="$INSTALL_ROOT/$APP_NAME"
rm -rf "$DEST_APP"
# ditto preserves extended attributes, including com.apple.quarantine, unlike cp -R.
ditto "$APP_SOURCE" "$DEST_APP"

hdiutil detach "$MOUNT_POINT" -quiet

echo "==> Installed: $DEST_APP"
echo "==> Quarantine attribute (must be present — proves no stripping occurred):"
xattr -p com.apple.quarantine "$DEST_APP" || {
  echo "WARNING: no com.apple.quarantine attribute present on $DEST_APP." >&2
  echo "This can happen if ditto ran from a volume/user context that already cleared it; record as evidence, do not re-add it manually." >&2
}

echo "==> sha256=$SHA256 archive=$ARCHIVE_NAME app=$APP_NAME install_root=$INSTALL_ROOT"

cat > "$INSTALL_ROOT/acquire-manifest.json" <<EOF
{
  "candidate": "$CANDIDATE",
  "version": "$VERSION",
  "download_url": "$DOWNLOAD_URL",
  "sha256": "$SHA256",
  "app_path": "$DEST_APP"
}
EOF
