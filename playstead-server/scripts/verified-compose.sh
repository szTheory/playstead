#!/usr/bin/env bash
set -euo pipefail

SERVER_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
if [ "$#" -lt 1 ] || [ "$1" != "up" ]; then
  echo "usage: scripts/verified-compose.sh up [docker compose up options]" >&2
  exit 2
fi
shift
PLAYSTEAD_MEDIA_DECODER_IMAGE="$(bash "$SERVER_ROOT/scripts/prepare-media-decoder-image.sh")"
export PLAYSTEAD_MEDIA_DECODER_IMAGE
cd "$SERVER_ROOT"
exec docker compose up "$@"
