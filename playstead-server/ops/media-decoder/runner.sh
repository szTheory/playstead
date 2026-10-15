#!/bin/sh
set -eu
if [ "${1:-serve}" = "serve" ]; then
  exec python3 /opt/media-decoder/server.py
fi
if [ "${1:-}" = "self-test" ]; then
  exec python3 /opt/media-decoder/server.py --self-test
fi
exec "$@"
