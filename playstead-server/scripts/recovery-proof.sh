#!/usr/bin/env bash
# Non-destructive recovery evidence entrypoint. Fixture mode uses only fresh,
# generated Compose projects and never contacts the canonical stack.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ "${1:-}" != "--restore" ]; then
  echo "usage: $0 --restore --compose-fixture | --restore --retain ... | --restore --cleanup ..." >&2
  exit 2
fi
shift

if ! docker compose version >/dev/null 2>&1; then
  echo "SKIPPED: Docker Compose is unavailable; no recovery receipt was verified or mutated." >&2
  exit 77
fi

case "${1:-}" in
  --compose-fixture)
    if [ "$#" -ne 1 ]; then
      echo "REFUSED: fixture mode accepts no retained-target arguments." >&2
      exit 2
    fi
    mix playstead.restore --compose-fixture
    ;;
  --retain|--cleanup)
    # The Mix task owns argument validation and refuses cross-mode selection.
    mix playstead.restore "$@"
    ;;
  *)
    echo "REFUSED: select exactly --compose-fixture, --retain, or --cleanup." >&2
    exit 2
    ;;
esac
