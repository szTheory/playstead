#!/usr/bin/env bash
set -euo pipefail

# Build and scan the exact isolated decoder image before Compose can activate it.
# The emitted Compose env file names the immutable Docker image ID, never a tag.
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
cd "$REPO_ROOT"
CONTEXT="$REPO_ROOT/playstead-server/ops/media-decoder"
OUTPUT_DIR="${1:?usage: media-decoder-supply-chain.sh OUTPUT_DIR}"
OUTPUT_DIR="$(mkdir -p "$OUTPUT_DIR" && cd "$OUTPUT_DIR" && pwd -P)"
TRIVY_IMAGE="aquasec/trivy:0.75.0"
TRIVY_CACHE="${TRIVY_CACHE_DIR:-${HOME}/.cache/trivy}"
mkdir -p "$TRIVY_CACHE"
rm -f "$OUTPUT_DIR/decoder-scan-receipt.json" "$OUTPUT_DIR/decoder-compose.env" \
  "$OUTPUT_DIR/decoder-trivy.json" "$OUTPUT_DIR/decoder-scan-result.json"
RAW_DIR="$(mktemp -d "${RUNNER_TEMP:-/tmp}/playstead-decoder-trivy.XXXXXX")"
GENERATED_CONTEXT="$CONTEXT/build/generated"
IMAGE_TAG="playstead-media-decoder:scan-$(date +%s)-$$"
SCAN_PASSED=0
cleanup() {
  if [ "$SCAN_PASSED" -ne 1 ]; then
    docker image rm "$IMAGE_TAG" >/dev/null 2>&1 || true
    rm -rf "$GENERATED_CONTEXT"
  fi
  rm -rf "$RAW_DIR"
}
trap cleanup EXIT INT TERM

# Build locally signed, source-pinned Wolfi APK variants with exact provenance.
# The build output is copied into the Docker context only for this exact build.
bash "$CONTEXT/build/build-runtime.sh"

# This hash covers every file in the Docker build context in stable path order.
SOURCE_SHA256="$(python3 scripts/ci/media-decoder-evidence.py hash --context "$CONTEXT")"
docker build --pull --iidfile "$RAW_DIR/image-id" --tag "$IMAGE_TAG" "$CONTEXT"
IMAGE_ID="$(cat "$RAW_DIR/image-id")"
[[ "$IMAGE_ID" =~ ^sha256:[0-9a-f]{64}$ ]]
test "$(docker image inspect --format '{{.Id}}' "$IMAGE_TAG")" = "$IMAGE_ID"

# Export only the selected image. The third-party scanner receives no Docker
# socket and cannot control unrelated host containers or images.
docker image save --output "$RAW_DIR/decoder-image.tar" "$IMAGE_ID"
docker run --rm \
  -v "$REPO_ROOT/scripts/ci/trivy.yaml:/trivy-config.yaml:ro" \
  -v "$RAW_DIR:/raw" -v "$TRIVY_CACHE:/root/.cache/" \
  "$TRIVY_IMAGE" image --config /trivy-config.yaml \
  --scanners vuln,license --severity UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL \
  --input /raw/decoder-image.tar --format json --output /raw/decoder-trivy.json

python3 scripts/ci/media-decoder-evidence.py create \
  --report "$RAW_DIR/decoder-trivy.json" --output "$OUTPUT_DIR" \
  --source-sha256 "$SOURCE_SHA256" --image-id "$IMAGE_ID"
SCAN_PASSED=1
