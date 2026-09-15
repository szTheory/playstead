#!/usr/bin/env bash
# One-shot status for the UAT item 7 runs. Read-only: opens the local SQLite
# read-only and stats files. Safe to run while the app and a game are running.
# See playstead-mac/docs/UAT-07-RUNBOOK.md.
set -uo pipefail

PSD="$HOME/Library/Application Support/Playstead"
DB="$PSD/playstead.sqlite3"
q() { sqlite3 "file:$DB?mode=ro" "$@" 2>/dev/null; }

hr() { printf '%s\n' "------------------------------------------------------------"; }

printf '\n== server ==\n'
if curl -sk --max-time 3 https://localhost:18443/healthz >/dev/null 2>&1; then
  echo "caddy: UP (answering /healthz)"
else
  echo "caddy: UNREACHABLE"
fi

printf '\n== emulator ==\n'
if pgrep -f 'mGBA.app/Contents/MacOS/mGBA' >/dev/null 2>&1; then
  pid="$(pgrep -f 'mGBA.app/Contents/MacOS/mGBA' | head -1)"
  # STAT S = running normally. T would be the suspended-at-_dyld_start shape
  # broken window #8 describes, which looks launched and never runs.
  ps -o pid,etime,stat -p "$pid" | tail -1
  echo "  (kill signals for Run D:  kill -TERM $pid | kill -SEGV $pid | kill -KILL $pid)"
else
  echo "not running"
fi

printf '\n== cached titles ==\n'
python3 - <<'PY'
import json, os, sqlite3
psd = os.path.expanduser("~/Library/Application Support/Playstead")
try:
    idx = json.load(open(f"{psd}/objects/verify-index.json"))
except Exception:
    idx = {}
db = sqlite3.connect(f"file:{psd}/playstead.sqlite3?mode=ro", uri=True)
for aid, title in db.execute("select id, display_title from catalogue_entries order by display_title"):
    need = [r[0] for r in db.execute(
        "select sha256 from catalogue_members where asset_set_id=? and required=1", (aid,))]
    have = [s for s in need if s in idx]
    tag = "CACHED   " if need and len(have) == len(need) else "on server"
    print(f"  {tag}  {title}  ({len(have)}/{len(need)})")
PY

printf '\n== play sessions (newest 3) ==\n'
q -header -column "select substr(s.id,1,8) session, e.display_title as title,
       s.ended_at, s.delivered
  from play_sessions_pending s
  left join catalogue_entries e on e.id = s.asset_set_id
 order by s.started_at desc limit 3;"
echo "  ended_at empty = still open. delivered 0 = not yet sent to the server."

printf '\n== outbox ==\n'
# state matters more than presence: 'pending' rows are work still owed, while
# 'rejected' rows are terminal by design (the server refused them permanently)
# and stay visible in RejectedIntentsView until dismissed. A queue holding only
# rejected rows is drained.
out="$(q -header -column "select substr(id,1,8) id, kind, state, attempt_count, next_retry_at from outbox_entries order by created_at;")"
[ -n "$out" ] && printf '%s\n' "$out" || echo "  (empty)"
pending="$(q "select count(*) from outbox_entries where state = 'pending';")"
echo "  pending (work still owed): ${pending:-?}   <- this is the number that should reach 0"

printf '\n== battery saves: real data or erased flash? ==\n'
# Counting non-zero bytes is NOT a content test: erased flash reads 0xFF, so an
# empty .sav looks 98%% "non-zero". Distinct byte values separate them -- an
# erased or freshly-created save has a handful, a real save has a hundred-plus.
# Got this wrong on 2026-09-13 and sent the owner into a new-game prompt.
python3 - <<'PY2'
import collections, glob, os
psd = os.path.expanduser("~/Library/Application Support/Playstead")
for f in sorted(glob.glob(f"{psd}/saves/*/*.sav")):
    d = open(f, "rb").read()
    if not d:
        print(f"  EMPTY FILE   {os.path.basename(f)}")
        continue
    c = collections.Counter(d)
    top, n = c.most_common(1)[0]
    verdict = "REAL SAVE " if len(c) >= 64 else "erased/new"
    print(f"  {verdict}  {os.path.basename(f)}  ({len(c)} distinct bytes, "
          f"{100*n/len(d):.0f}% 0x{top:02x})")
PY2

printf '\n== save artifacts, newest first ==\n'
# The battery .sav under saves/ is what the capture poller watches. A .ss1 in
# launch/ is an mGBA save STATE and produces no capture -- the distinction that
# cost a whole run on 2026-09-13.
find "$PSD/saves" "$PSD/save-captures" "$PSD/launch" -type f \
     \( -name '*.sav' -o -name '*.ss[0-9]' \) -print0 2>/dev/null \
  | xargs -0 ls -lt 2>/dev/null | head -6 \
  | sed "s|$PSD/||" | awk '{printf "  %s  %s %s %s  %s\n", $5, $6, $7, $8, $9}'

hr
echo "Runbook: playstead-mac/docs/UAT-07-RUNBOOK.md"
