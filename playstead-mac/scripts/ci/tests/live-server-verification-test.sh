#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="${SCRIPT_DIR}/../live-server.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/playstead-live-verify.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

make_mirror() {
  local root="$1"
  shift
  mkdir -m 0700 -p "$root/control" "$root/objects" "$root/partials"
  python3 - "$root/playstead.sqlite3" "$@" <<'PY'
import pathlib, sqlite3, sys
path = pathlib.Path(sys.argv[1])
with sqlite3.connect(path) as db:
    db.execute("CREATE TABLE sync_cursor (id INTEGER PRIMARY KEY, cursor TEXT NOT NULL)")
    db.execute("INSERT INTO sync_cursor VALUES (1, 'synthetic-cursor')")
    db.execute("CREATE TABLE catalogue_entries (display_title TEXT NOT NULL)")
    db.executemany("INSERT INTO catalogue_entries VALUES (?)", [(title,) for title in sys.argv[2:]])
PY
}

verify() {
  local profile="$1" expected_titles="$2"
  PLAYSTEAD_MAC_CI_ROOT="$WORK/native/app" bash "$FIXTURE" verify \
    "$profile" "$WORK/native/app" snapshots-not-asserted-here "$expected_titles"
}

mkdir -m 0700 -p "$WORK/native/app/mac-client-control"
: >"$WORK/native/phoenix.log"

one="$WORK/one"
make_mirror "$one" "Playstead CI Sentinel One"
if ! verify "$one" first-only >"$WORK/first-only.out" 2>"$WORK/first-only.err"; then
  printf 'verify must accept the explicitly expected first-only mirror\n' >&2
  cat "$WORK/first-only.err" >&2
  exit 1
fi

both="$WORK/both"
make_mirror "$both" "Playstead CI Sentinel One" "Playstead CI Sentinel Two"
if ! verify "$both" both >"$WORK/both.out" 2>"$WORK/both.err"; then
  printf 'verify must accept the explicitly expected two-sentinel mirror\n' >&2
  cat "$WORK/both.err" >&2
  exit 1
fi

if verify "$one" both >"$WORK/wrong-set.out" 2>"$WORK/wrong-set.err"; then
  printf 'verify accepted a mirror with the wrong explicit sentinel set\n' >&2
  exit 1
fi

printf '%s\n' 'live-server mirror-verification contract: passed'
