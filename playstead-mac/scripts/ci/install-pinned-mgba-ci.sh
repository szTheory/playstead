#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PIN="${MAC_ROOT}/Playstead/Adapter/AdapterPin.json"
APP_ROOT="${HOME}/Library/Application Support/Playstead/emulators/mgba/0.10.5"
APP="${APP_ROOT}/mGBA.app"
EXECUTABLE="${APP}/Contents/MacOS/mGBA"
EXPECTED_EXECUTABLE_SHA256="f2f329b4947baa5082fcaf27ced1e2b21f2999ccf73ca481f22b44c4c87d6640"
EXPECTED_ARCHIVE_SHA256="443b490ec728293dfcde1cb9db160f73d94c457cb1864f3ce0407e60e174b09c"

python3 - "$PIN" <<'PY'
import json, pathlib, sys
pin = json.loads(pathlib.Path(sys.argv[1]).read_text())
if (pin.get("system"), pin.get("emulator"), pin.get("version"), pin.get("sha256")) != (
    "gba", "mgba", "0.10.5", "443b490ec728293dfcde1cb9db160f73d94c457cb1864f3ce0407e60e174b09c"
):
    raise SystemExit("mGBA adapter archive pin does not match the hosted test contract")
PY

if [ -x "$EXECUTABLE" ] && [ "$(shasum -a 256 "$EXECUTABLE" | awk '{print $1}')" = "$EXPECTED_EXECUTABLE_SHA256" ]; then
  printf '%s\n' 'pinned mGBA Qt executable already verified'
  exit 0
fi
if [ -e "$APP" ]; then
  printf '%s\n' 'an existing mGBA bundle failed the pinned digest check; refusing to replace it' >&2
  exit 1
fi

mkdir -p "$APP_ROOT"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/playstead-mgba-ci.XXXXXX")"
mounted=false
cleanup() {
  if [ "$mounted" = true ]; then hdiutil detach "$mount_point" -quiet || true; fi
  rm -rf "$temporary_root"
}
trap cleanup EXIT INT TERM
archive="${temporary_root}/mGBA-0.10.5-macos.dmg"
mount_point="${temporary_root}/mounted"
mkdir -m 700 "$mount_point"
curl --fail --location --retry 2 --output "$archive" \
  'https://github.com/mgba-emu/mgba/releases/download/0.10.5/mGBA-0.10.5-macos.dmg'
actual_archive_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
[ "$actual_archive_sha256" = "$EXPECTED_ARCHIVE_SHA256" ] || {
  printf '%s\n' 'pinned mGBA archive digest mismatch' >&2
  exit 1
}
hdiutil attach "$archive" -readonly -nobrowse -mountpoint "$mount_point" >/dev/null
mounted=true
source_app="$(find "$mount_point" -maxdepth 3 -name mGBA.app -type d -print -quit)"
[ -n "$source_app" ] || { printf '%s\n' 'pinned mGBA app bundle missing from verified archive' >&2; exit 1; }
ditto "$source_app" "$APP"
actual_executable_sha256="$(shasum -a 256 "$EXECUTABLE" | awk '{print $1}')"
[ "$actual_executable_sha256" = "$EXPECTED_EXECUTABLE_SHA256" ] || {
  printf '%s\n' 'pinned mGBA executable digest mismatch' >&2
  exit 1
}
printf '%s\n' 'pinned mGBA Qt executable installed and verified'
