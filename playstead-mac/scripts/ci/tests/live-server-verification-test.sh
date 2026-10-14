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
    db.execute("CREATE TABLE catalogue_entries (id TEXT PRIMARY KEY, display_title TEXT NOT NULL)")
    db.executemany("INSERT INTO catalogue_entries VALUES (?, ?)", [(title, title) for title in sys.argv[2:]])
PY
  python3 - "$root" "$WORK/native/phoenix.log" <<'PY'
import json, pathlib, sqlite3, sys
root, log = map(pathlib.Path, sys.argv[1:])
with sqlite3.connect(root / "playstead.sqlite3") as db:
    catalogue = dict(db.execute("SELECT id, display_title FROM catalogue_entries"))
second = catalogue.pop("Playstead CI Sentinel Two", None)
stat = log.stat()
(root / "control/request-baseline.json").write_text(json.dumps({
    "device": stat.st_dev, "inode": stat.st_ino, "offset": stat.st_size, "catalogue": catalogue}))
if second:
    (root / "control/second-sentinel.json").write_text(json.dumps({
        "sentinel": {"asset_set_id": second, "title": second}}))
PY
}

verify() {
  local profile="$1" expected_titles="$2"
  PLAYSTEAD_MAC_CI_ROOT="$WORK/native/app" bash "$FIXTURE" verify \
    "$profile" "$WORK/native/app" snapshots-not-asserted-here "$expected_titles"
}

mkdir -m 0700 -p "$WORK/native/app/mac-client-control"
# Earlier serialized tests really downloaded game bytes and fetched snapshots.
printf '%s\n' 'GET /api/v1/blobs/earlier-fixture' 'Sent 200' \
  'GET /api/v1/snapshot' 'Sent 200' >"$WORK/native/phoenix.log"

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

printf '%s\n' 'GET /api/v1/snapshot' 'Sent 200' \
  'GET /api/v1/snapshot' 'Sent 200' >>"$WORK/native/phoenix.log"
PLAYSTEAD_MAC_CI_ROOT="$WORK/native/app" bash "$FIXTURE" verify \
  "$both" "$WORK/native/app" 2 both >"$WORK/two-snapshots.out" 2>"$WORK/two-snapshots.err"
if PLAYSTEAD_MAC_CI_ROOT="$WORK/native/app" bash "$FIXTURE" verify \
  "$both" "$WORK/native/app" 1 both >"$WORK/wrong-count.out" 2>"$WORK/wrong-count.err"; then
  printf 'verify accepted the wrong current-test snapshot count\n' >&2
  exit 1
fi

retained="$WORK/retained"
make_mirror "$retained" "Playstead CI Sentinel One" "Prior authored GB import"
verify "$retained" first-only >"$WORK/retained.out" 2>"$WORK/retained.err"
python3 - "$retained/playstead.sqlite3" <<'PY'
import sqlite3, sys
with sqlite3.connect(sys.argv[1]) as db:
    db.execute("DELETE FROM catalogue_entries WHERE display_title = 'Prior authored GB import'")
PY
if verify "$retained" first-only >"$WORK/missing-retained.out" 2>"$WORK/missing-retained.err"; then
  printf 'verify accepted a mirror missing a pre-existing import\n' >&2
  exit 1
fi

printf '%s\n' 'GET /api/v1/blobs/current-fixture' 'Sent 200' >>"$WORK/native/phoenix.log"
if verify "$both" both >"$WORK/current-download.out" 2>"$WORK/current-download.err"; then
  printf 'verify accepted a blob download inside this test window\n' >&2
  exit 1
fi
test "$(cat "$both/live-server-verify-result")" = blob-request-observed
rm "$both/control/request-baseline.json"
if verify "$both" both >"$WORK/missing-baseline.out" 2>"$WORK/missing-baseline.err"; then
  printf 'verify accepted a missing request baseline\n' >&2
  exit 1
fi
test "$(cat "$both/live-server-verify-result")" = verification-input-missing

rotated="$WORK/rotated"
make_mirror "$rotated" "Playstead CI Sentinel One"
mv "$WORK/native/phoenix.log" "$WORK/native/phoenix.old"
: >"$WORK/native/phoenix.log"
if verify "$rotated" first-only >"$WORK/rotated.out" 2>"$WORK/rotated.err"; then
  printf 'verify accepted a replaced request log\n' >&2
  exit 1
fi
test "$(cat "$rotated/live-server-verify-result")" = verification-input-missing

printf '%s\n' 'live-server mirror-verification contract: passed (10 checks)'
