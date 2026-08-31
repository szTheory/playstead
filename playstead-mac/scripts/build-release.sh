#!/usr/bin/env bash
# Archives and exports Playstead.app for Developer ID direct distribution
# (D-04: hardened runtime, not App-Sandboxed).
#
# Reads the signing identity from PLAYSTEAD_DEV_ID_APP rather than hardcoding
# it in the Xcode project — the project's own Debug/Release build settings use
# the dev-signing identity for local `xcodebuild build`/`test` runs (matching
# plan 03-01's spike posture); this script is the one place a real Developer
# ID Application identity is substituted in for a distributable build.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/Playstead.xcarchive"
EXPORT_PATH="$BUILD_DIR/Release"
EXPORT_OPTIONS_PLIST="$BUILD_DIR/export-options.plist"

: "${PLAYSTEAD_DEV_ID_APP:?PLAYSTEAD_DEV_ID_APP must be set to a 'Developer ID Application: ...' signing identity}"
: "${PLAYSTEAD_TEAM_ID:?PLAYSTEAD_TEAM_ID must be set}"

mkdir -p "$BUILD_DIR"

cat > "$EXPORT_OPTIONS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>teamID</key>
	<string>${PLAYSTEAD_TEAM_ID}</string>
	<key>signingCertificate</key>
	<string>${PLAYSTEAD_DEV_ID_APP}</string>
	<key>signingStyle</key>
	<string>manual</string>
</dict>
</plist>
PLIST

echo "==> Archiving Playstead (Release, Developer ID: $PLAYSTEAD_DEV_ID_APP)"
xcodebuild archive \
  -project "$PROJECT_DIR/Playstead.xcodeproj" \
  -scheme Playstead \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_IDENTITY="$PLAYSTEAD_DEV_ID_APP" \
  DEVELOPMENT_TEAM="$PLAYSTEAD_TEAM_ID" \
  CODE_SIGN_STYLE=Manual

echo "==> Exporting for Developer ID direct distribution"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

echo "==> Done: $EXPORT_PATH/Playstead.app"
