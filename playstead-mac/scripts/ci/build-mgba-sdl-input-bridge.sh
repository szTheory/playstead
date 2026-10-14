#!/usr/bin/env bash
set -euo pipefail

readonly SDL_REVISION="9519b9916cd29a14587af0507292f2bd31dd5752"
readonly REPOSITORY="https://github.com/libsdl-org/SDL.git"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Xcode grants scripts their target temporary workspace recursively.
# DerivedSources output entries grant only exact files, not a Git/CMake tree.
readonly SOURCE_ROOT="${TARGET_TEMP_DIR:?}/playstead-sdl-2.30.7"
readonly BUILD_ROOT="${SOURCE_ROOT}/build-${ARCHS:-host}"
readonly WORK_HELPERS="${SOURCE_ROOT}/helpers-${ARCHS:-host}"
readonly APP_HELPERS="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/../Helpers"
readonly APP_RESOURCES="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
readonly PRODUCT_APP="${TARGET_BUILD_DIR}/${FULL_PRODUCT_NAME}"

if [ ! -d "${SOURCE_ROOT}/.git" ]; then
  mkdir -p "$SOURCE_ROOT"
  git -C "$SOURCE_ROOT" init --quiet
  git -C "$SOURCE_ROOT" remote add origin "$REPOSITORY"
fi
# The immutable revision is sufficient: a verified warm cache needs no
# network/tag lookup, and a cold cache fetches only the pinned commit.
if ! git -C "$SOURCE_ROOT" cat-file -e "${SDL_REVISION}^{commit}" 2>/dev/null; then
  git -C "$SOURCE_ROOT" fetch --quiet --depth 1 origin "$SDL_REVISION"
fi
git -C "$SOURCE_ROOT" checkout --quiet --detach "$SDL_REVISION"
git -C "$SOURCE_ROOT" diff --quiet "$SDL_REVISION" -- || {
  echo "SDL source cache has modified tracked files; refusing an unverified build" >&2
  exit 1
}
actual="$(git -C "$SOURCE_ROOT" rev-parse HEAD)"
[ "$actual" = "$SDL_REVISION" ] || { echo "SDL source revision mismatch: $actual" >&2; exit 1; }

cmake -S "$SOURCE_ROOT" -B "$BUILD_ROOT" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES="${ARCHS:-$(uname -m)}" \
  -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST=OFF -DSDL_TESTS=OFF \
  -DSDL_FRAMEWORK=OFF -DSDL_INSTALL=ON
cmake --build "$BUILD_ROOT" --config Release --parallel 2

library="$(find "$BUILD_ROOT" -type f -name 'libSDL2*.dylib' -print -quit)"
[ -n "$library" ] && [ -f "$library" ] || { echo "SDL 2.30.7 shared library was not built" >&2; exit 1; }
mkdir -p "$WORK_HELPERS"
chmod 755 "$WORK_HELPERS"
cp "$library" "${WORK_HELPERS}/libSDL2.0.dylib"
install_name_tool -id @rpath/libSDL2.0.dylib "${WORK_HELPERS}/libSDL2.0.dylib"
clang -O2 -Wall -Wextra -Werror \
  -I "${SOURCE_ROOT}/include" \
  "${SCRIPT_DIR}/mgba-sdl-input-bridge.c" "${WORK_HELPERS}/libSDL2.0.dylib" \
  -Wl,-rpath,@loader_path -o "${WORK_HELPERS}/playstead-sdl-input-bridge"
install_name_tool -change "$library" @rpath/libSDL2.0.dylib "${WORK_HELPERS}/playstead-sdl-input-bridge"

printf 'SDL source commit: %s\nSDL release: 2.30.7\nSDL license: zlib\n' "$SDL_REVISION" \
  >"${APP_RESOURCES}/SDL-SOURCE-PROVENANCE.txt"
cp "${SOURCE_ROOT}/LICENSE.txt" "${APP_RESOURCES}/SDL-LICENSE.txt"
chmod 644 "${APP_RESOURCES}/SDL-SOURCE-PROVENANCE.txt"
chmod 644 "${APP_RESOURCES}/SDL-LICENSE.txt"

identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
codesign --force --sign "$identity" --timestamp=none "${WORK_HELPERS}/libSDL2.0.dylib"
codesign --force --sign "$identity" --timestamp=none "${WORK_HELPERS}/playstead-sdl-input-bridge"
codesign --verify --strict "${WORK_HELPERS}/libSDL2.0.dylib"
codesign --verify --strict "${WORK_HELPERS}/playstead-sdl-input-bridge"

# Binary rewriting/signing creates temporary siblings. Finish in the permitted
# workspace, then copy only the declared final outputs into the app bundle.
mkdir -p "$APP_HELPERS"
chmod 755 "$APP_HELPERS"
cp "${WORK_HELPERS}/libSDL2.0.dylib" "${APP_HELPERS}/libSDL2.0.dylib"
cp "${WORK_HELPERS}/playstead-sdl-input-bridge" "${APP_HELPERS}/playstead-sdl-input-bridge"
codesign --verify --strict "${APP_HELPERS}/libSDL2.0.dylib"
codesign --verify --strict "${APP_HELPERS}/playstead-sdl-input-bridge"
version="$("${APP_HELPERS}/playstead-sdl-input-bridge" --version)"
[ "$version" = "SDL 2.30.7" ] || { echo "bridge helper runtime mismatch: $version" >&2; exit 1; }
