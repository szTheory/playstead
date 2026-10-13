#!/usr/bin/env bash
set -euo pipefail

OPS_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
BUILD_DIR="$OPS_ROOT/.build"
GENERATED="$OPS_ROOT/build/generated"
RECIPE_SOURCE="$OPS_ROOT/build/recipes"
MELANGE_VERSION="0.59.1"
MELANGE_COMMIT="107506ddac616675ad21681b8770ccb3e3bf3a07"
WOLFI_KEY_SHA256="f0031424cf46f7db780ce63a45f0fd6aa6f85f601e6bb3b7a91fe3d4d5b7d2cc"

mkdir -p "$BUILD_DIR/bin" "$BUILD_DIR/gopath" "$BUILD_DIR/gomodcache" "$BUILD_DIR/gocache" \
  "$BUILD_DIR/apk-cache" "$BUILD_DIR/source-cache"
rm -rf "$GENERATED"
mkdir -p "$GENERATED/packages"

if ! command -v go >/dev/null 2>&1; then
  echo "Go is required to bootstrap pinned Melange ${MELANGE_VERSION}." >&2
  exit 1
fi
export GOBIN="$BUILD_DIR/bin" GOPATH="${GOPATH:-$BUILD_DIR/gopath}" GOMODCACHE="${GOMODCACHE:-$BUILD_DIR/gomodcache}"
export GOCACHE="${GOCACHE:-$BUILD_DIR/gocache}" GOSUMDB=sum.golang.org GOTOOLCHAIN=go1.26.2
go version | grep -q 'go1.26.2' || { echo "Pinned Go 1.26.2 toolchain unavailable" >&2; exit 1; }
MELANGE_SOURCE="$BUILD_DIR/melange-source"
if [ ! -d "$MELANGE_SOURCE/.git" ] || [ "$(git -C "$MELANGE_SOURCE" rev-parse HEAD 2>/dev/null || true)" != "$MELANGE_COMMIT" ]; then
  rm -rf "$MELANGE_SOURCE"
  git clone --filter=blob:none --no-checkout https://github.com/chainguard-dev/melange.git "$MELANGE_SOURCE"
  git -C "$MELANGE_SOURCE" checkout --detach "$MELANGE_COMMIT"
fi
test "$(git -C "$MELANGE_SOURCE" rev-parse HEAD)" = "$MELANGE_COMMIT"
MELANGE_SOURCE_SHA256="$(git -C "$MELANGE_SOURCE" archive --format=tar "$MELANGE_COMMIT" | shasum -a 256 | awk '{print $1}')"
if [ ! -x "$GOBIN/melange" ] || [ "$(cat "$BUILD_DIR/melange-source.sha256" 2>/dev/null || true)" != "$MELANGE_SOURCE_SHA256" ]; then
  (cd "$MELANGE_SOURCE" && go build -mod=readonly -trimpath -o "$GOBIN/melange" .)
  printf '%s\n' "$MELANGE_SOURCE_SHA256" > "$BUILD_DIR/melange-source.sha256"
fi
MELANGE="$GOBIN/melange"
"$MELANGE" version | grep -Fq "GoVersion:     go1.26.2" || {
  echo "Melange was not built with pinned Go 1.26.2" >&2
  exit 1
}

ARCH="$(docker info --format '{{.Architecture}}')"
case "$ARCH" in
  arm64|aarch64) MELANGE_ARCH="aarch64" ;;
  amd64|x86_64) MELANGE_ARCH="x86_64" ;;
  *) echo "Unsupported Docker architecture: $ARCH" >&2; exit 1 ;;
esac

curl --fail --silent --show-error --location \
  https://packages.wolfi.dev/os/wolfi-signing.rsa.pub \
  --output "$BUILD_DIR/wolfi-signing.rsa.pub"
python3 - "$WOLFI_KEY_SHA256" "$BUILD_DIR/wolfi-signing.rsa.pub" <<'PY'
import hashlib
import pathlib
import sys
actual = hashlib.sha256(pathlib.Path(sys.argv[2]).read_bytes()).hexdigest()
if actual != sys.argv[1]:
    raise SystemExit("official Wolfi APK signing key digest mismatch")
PY
if [ ! -s "$BUILD_DIR/decoder-signing.rsa" ] || [ ! -s "$BUILD_DIR/decoder-signing.rsa.pub" ]; then
  "$MELANGE" keygen "$BUILD_DIR/decoder-signing.rsa"
fi
cp "$BUILD_DIR/decoder-signing.rsa.pub" "$GENERATED/packages/decoder-signing.rsa.pub"
cp "$OPS_ROOT/build/SOURCE-PINS.json" "$GENERATED/SOURCE-PINS.json"
python3 - "$GENERATED/SOURCE-PINS.json" "$MELANGE_COMMIT" "$MELANGE_SOURCE_SHA256" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
data["build_tool"] = {
    "name": "melange",
    "version": "0.59.1",
    "source": "https://github.com/chainguard-dev/melange.git",
    "source_commit": sys.argv[2],
    "source_archive_sha256": sys.argv[3],
    "go_version": "1.26.2",
    "build_mode": "source",
}
path.write_text(json.dumps(data, sort_keys=True, indent=2) + "\n")
PY

# Melange's Docker runner cannot reach the public Wolfi repository directly in
# some networks. This short-lived relay accepts only GET/HEAD from the official
# repository path; APK signatures remain verified by APK.
TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(24))')"
PORT_FILE="$BUILD_DIR/proxy-port.$$"
PROXY_LOG="$BUILD_DIR/proxy-log.$$"
python3 "$OPS_ROOT/build/wolfi_repo_proxy.py" \
  --bind 127.0.0.1 --cache-dir "$BUILD_DIR/wolfi-repo-cache" \
  --port-file "$PORT_FILE" --token "$TOKEN" >"$PROXY_LOG" 2>&1 &
PROXY_PID=$!
TEMP_RECIPES=""
cleanup_proxy() {
  kill "$PROXY_PID" >/dev/null 2>&1 || true
  wait "$PROXY_PID" 2>/dev/null || true
  rm -f "$PORT_FILE" "$PROXY_LOG"
  [ -z "$TEMP_RECIPES" ] || rm -rf "$TEMP_RECIPES"
}
trap cleanup_proxy EXIT INT TERM
for _ in $(seq 1 100); do
  [ -s "$PORT_FILE" ] && break
  kill -0 "$PROXY_PID" 2>/dev/null || { cat "$PROXY_LOG" >&2; exit 1; }
  sleep 0.1
done
[ -s "$PORT_FILE" ] || { echo "Wolfi repository relay failed to start" >&2; exit 1; }
PROXY_URL="http://127.0.0.1:$(cat "$PORT_FILE")/$TOKEN/os"
TEMP_RECIPES="$(mktemp -d "${TMPDIR:-/tmp}/playstead-decoder-recipes.XXXXXX")"
cp -R "$RECIPE_SOURCE/." "$TEMP_RECIPES/"
python3 - "$TEMP_RECIPES" "$PROXY_URL" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
proxy = sys.argv[2]
for path in root.rglob("*.yaml"):
    text = path.read_text()
    path.write_text(text.replace("https://packages.wolfi.dev/os", proxy))
PY

MELANGE_CACHE="$BUILD_DIR/melange-cache"
mkdir -p "$MELANGE_CACHE"
build_package() {
  "$MELANGE" build "$TEMP_RECIPES/$1" \
    --arch "$MELANGE_ARCH" --runner docker --generate-provenance \
    --cache-dir "$MELANGE_CACHE" --apk-cache-dir "$BUILD_DIR/apk-cache" \
    --out-dir "$GENERATED/packages" --signing-key "$BUILD_DIR/decoder-signing.rsa" \
    --keyring-append "$BUILD_DIR/wolfi-signing.rsa.pub" \
    --keyring-append "$GENERATED/packages/decoder-signing.rsa.pub" --timeout 60m
}
cd "$GENERATED"
build_package glib.yaml
build_package libvips.yaml
build_package python-minimal.yaml

test -s "$GENERATED/packages/$MELANGE_ARCH/APKINDEX.tar.gz"
for package in glib-2.90.1-r0 libvips-8.18.7-r1 python-3.15-3.15.0_git20261010-r0 python-3.15-base-3.15.0_git20261010-r0; do
  find "$GENERATED/packages/$MELANGE_ARCH" -maxdepth 1 -name "$package.apk" -print -quit | grep -q . || {
    echo "missing expected signed runtime APK: $package" >&2
    exit 1
  }
done
echo "Built signed Wolfi decoder packages for $MELANGE_ARCH into $GENERATED/packages/$MELANGE_ARCH" >&2
