#!/usr/bin/env bash
set -euo pipefail

SERVER_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
REPO_ROOT="$(cd "$SERVER_ROOT/.." && pwd -P)"
EVIDENCE_DIR="${PLAYSTEAD_MEDIA_DECODER_EVIDENCE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/playstead/media-decoder}"
RECEIPT="$EVIDENCE_DIR/decoder-scan-receipt.json"
REPORT="$EVIDENCE_DIR/decoder-trivy.json"
CONTEXT="$SERVER_ROOT/ops/media-decoder"
EVIDENCE="$REPO_ROOT/scripts/ci/media-decoder-evidence.py"

verify_existing() {
  [ -s "$RECEIPT" ] && [ -s "$REPORT" ] || return 1
  local image_id actual_id
  image_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["image_id"])' "$RECEIPT" 2>/dev/null)" || return 1
  actual_id="$(docker image inspect --format '{{.Id}}' "$image_id" 2>/dev/null)" || return 1
  [ "$actual_id" = "$image_id" ] || return 1
  python3 "$EVIDENCE" verify --receipt "$RECEIPT" --report "$REPORT" --context "$CONTEXT" --image-id "$actual_id" >/dev/null
  printf '%s\n' "$actual_id"
}

if image_id="$(verify_existing)"; then
  printf '%s\n' "$image_id"
  exit 0
fi

# A missing, stale, altered, or failed receipt never falls through to activation.
bash "$REPO_ROOT/scripts/ci/media-decoder-supply-chain.sh" "$EVIDENCE_DIR" >&2
image_id="$(verify_existing)" || {
  echo "decoder_scan_receipt_invalid_after_scan" >&2
  exit 1
}
printf '%s\n' "$image_id"
