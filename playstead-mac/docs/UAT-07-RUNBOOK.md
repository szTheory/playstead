# Runbook — closing UAT item 7 by hand

Item 7 ("Play a game end to end with the real emulator, offline") is `partial`.
The download-and-play path is proven. Three clauses are not, and this file is how
to close each one on your own machine. Total time if you do all four runs in one
sitting: about 20 minutes.

> **Short answer to "do I turn off my Wi-Fi?" — no.** Stop one container.
> Your internet stays up.

## The knob

```sh
cd ~/projects/playstead/playstead-server
docker compose stop caddy     # server unreachable
docker compose start caddy    # server back, ~2s
```

`caddy` is the only published service in the deployment stack — `docker compose ps`
shows `0.0.0.0:18443->443/tcp` on it and nothing on `app` or `db`. Your Mac is
paired to `https://localhost:18443`, so with `caddy` stopped the app has no route
to the server at all, while `app` and `db` keep running: no migration wait, no
reindex, and `start` brings it back in seconds.

**Never `docker compose down -v` in that directory.** `playstead_db` and
`playstead_blobs` are your library. `stop`/`start` touch neither.

## Why not Wi-Fi

Two different things get called "offline", and only one of them is item 7's:

| | `stop caddy` | Wi-Fi off |
|---|---|---|
| Server unreachable | yes | yes |
| `Reachability.isOnline` flips to `false` | no | yes |
| Rest of your machine keeps working | yes | no |

`Reachability` wraps `NWPathMonitor`, which reports whether an *interface* has a
usable path — not whether your server answers. Stopping `caddy` leaves it
`satisfied`, so the app still believes it is online and tries; the connection just
fails. That is the **harsher** test of the clause: item 7 asks that pressing Play
on a cached title works with no server, and that has to hold whether or not the app
knows it is offline.

What the Wi-Fi toggle adds is the `isOnline == false` branch — downloads sitting
quietly as "queued while offline" and resuming with no user action (D-22). That
branch is already covered by automated suites driving an injected `Reachability`,
so skip it. If you ever want it by hand anyway:
`networksetup -setairportpower en0 off`, wait 30s, `… on`.

## Before you start

1. The deployment stack is up (`docker compose ps` → `app`, `caddy`, `db` running).
2. Playstead.app is running and paired to `https://localhost:18443`.
3. Pick a title that is actually cached. **Do not look for a "Ready offline"
   badge — there isn't one.** See the next section.

### How to tell what is cached (the badge lies)

Broken windows #72–#74: the grid layout hands every card a hardcoded
`.serverOnly` status, so every card shows the "On server" cloud glyph no matter
what is downloaded — and `GameListView`, the one view that would render the words
"Ready offline", has no production call site at all. Ignore the badge entirely.

**In the app:** click **List** (the button above the library) and read each row's
**action button**:

| button | meaning |
|---|---|
| **Play** | cached, and every readiness check passes — use this title |
| **Download** | the bytes are not in the local cache |
| **What's needed** | cached, but something else blocks it (BIOS, adapter) |

That button is trustworthy: it comes from the real six-check `ReadinessReport`,
which reads the CAS through `PreflightChecker(cas:)`. **Check readiness** opens the
full six-row report for a title.

**From the terminal** — authoritative, and works with the server already stopped:

```sh
python3 - <<'EOF'
import json, os, sqlite3
psd = os.path.expanduser("~/Library/Application Support/Playstead")
idx = json.load(open(f"{psd}/objects/verify-index.json"))
db  = sqlite3.connect(f"{psd}/playstead.sqlite3")
for aid, title in db.execute("select id, display_title from catalogue_entries order by display_title"):
    need = [r[0] for r in db.execute(
        "select sha256 from catalogue_members where asset_set_id=? and required=1", (aid,))]
    have = [s for s in need if s in idx]
    tag = "CACHED   " if need and len(have) == len(need) else "on server"
    print(f"{tag}  {title}  ({len(have)}/{len(need)})")
EOF
```

`objects/verify-index.json` is the CAS's real index — the same facts the Play
button's readiness check consults. Do **not** use the `cache_objects` table or
`catalogue_entries.availability`: broken window #75 records that the Download
button's path never writes `cache_objects`, so it reads empty even with 36 MB
cached.

Handy shell aliases for the runs below:

```sh
PSD="$HOME/Library/Application Support/Playstead"
DB="$PSD/playstead.sqlite3"
EXE="$PSD/emulators/mgba/0.10.5/mGBA.app/Contents/MacOS/mGBA"
mgba_pid() { pgrep -f 'mGBA.app/Contents/MacOS/mGBA'; }
```

---

## Run A — offline launch  (closes the "network disabled" clause)

**~5 min. Nothing destructive.**

1. Confirm the title's row button says **Play** (see "How to tell what is cached").
2. `docker compose stop caddy`
3. Confirm the server really is gone:
   `curl -sk --max-time 3 https://localhost:18443/healthz || echo "unreachable — good"`
4. Press **Play** on that title.

**Pass:** the emulator window opens and the game runs. `mgba_pid` prints a pid.
The library does not show an error banner about the server.

**Fail:** any launch failure, or a modal about connectivity. Capture the exact
string in the row's status slot — it is rendered as `Launch failed: <error>`.

### A2 (optional, stronger — 2 extra min)

While `caddy` is still stopped, quit Playstead.app entirely and reopen it. A cold
start with no server is the case a self-hoster hits when their server is down:
the library should still paint from the local read model and the cached title
should still launch. If the app comes up empty or blocks on a spinner, that is a
finding worth its own record.

Bring the server back when you are done with A: `docker compose start caddy`.

---

## Run B — quit and return  (closes the rest of the quit clause)

**~5 min. Nothing destructive.** Best done with `caddy` still stopped, because it
then proves the *queued-while-offline* half for free.

1. With the game from Run A still running, **save from inside the game's own menu**
   — Advance Wars' own Save option, not mGBA's Save State. This matters: mGBA's
   Save State (Shift-F1) writes a `.ss1` snapshot, while the capture poller watches
   the battery save at `saves/<assetSet>/<rom>.sav`. Saving a state produces no
   capture, so the delivery half of this run never starts. (Learned the hard way on
   2026-09-13 — an earlier version of this file said Shift-F1.)
2. Quit the emulator normally — **⌘Q inside the mGBA window**, not from a terminal.
3. Watch the app: it should return to the library on its own, with no modal.
4. Note what the row prints for **`Last exit:`** — write the string down verbatim.
   See Run D for why that string matters.
5. With the server still down, check the local record:

```sh
sqlite3 -header -column "$DB" \
  "select id, started_at, ended_at, delivered from play_sessions_pending order by started_at desc limit 3;"
sqlite3 -header -column "$DB" "select id, kind, attempt_count from save_outbox_entries;"
```

**Expect:** `ended_at` filled in, `delivered` still `0`, and a save outbox entry
waiting. That is correct offline behaviour — the session closed locally and
delivery is queued, not lost.

6. `docker compose start caddy`, then wait. Do **not** click anything.

**Pass:** within a minute or so, `delivered` flips to `1` and
`save_outbox_entries` drains to zero with no user action.

> Already partly observed: session `50B5DD15-…` closed at `2026-09-13T03:32:19Z`
> with `delivered = 1` and an empty outbox. What that DB state does *not* show is
> whether the UI returned to the library cleanly and what `Last exit:` read — which
> is exactly what steps 3 and 4 are for.

---

## Run C — install-digest mismatch refuses to launch

**~3 min. Modifies the emulator binary, then restores it byte-for-byte.**

`AdapterHost.verifyInstalledDigest()` re-hashes the live executable on *every*
launch, so corrupting it is the whole probe. Back it up first.

```sh
cp -p "$EXE" /tmp/mGBA.orig
shasum -a 256 "$EXE"          # f2f329b4947baa5082fcaf27ced1e2b21f2999ccf73ca481f22b44c4c87d6640
printf '\0' >> "$EXE"         # one byte -> digest no longer matches
shasum -a 256 "$EXE"          # must now differ
```

Press **Play**.

**Pass:** the launch is refused and the row reads something like
`Launch failed: digestMismatch(expected: "f2f329b4…", actual: "<the new digest>")`.
`mgba_pid` prints nothing — no process was spawned.

Restore immediately, and verify:

```sh
cp -p /tmp/mGBA.orig "$EXE"
shasum -a 256 "$EXE"   # MUST read f2f329b4947baa5082fcaf27ced1e2b21f2999ccf73ca481f22b44c4c87d6640
rm /tmp/mGBA.orig
```

Two notes:

* Appending a byte invalidates the Mach-O signature. That is fine here — the point
  is that the binary is never executed, and the restore is byte-identical.
* If the message says **`emulatorNotInstalled`** instead of `digestMismatch`, stop
  and record it. That means `installState` was not restored on this app launch, so
  the check fell back to the fixed downloaded-install path
  (`…/0.10.5/Contents/MacOS/mGBA`) which does not exist on your machine — your real
  binary lives inside `mGBA.app`. That is a different defect, not a pass.

---

## Run D — exit classification  (the interesting one)

**~5 min. `-SEGV` and `-KILL` lose unsaved progress.** Save in-game first, or use
a title you do not care about. Do this run last.

Launch the game, then in a terminal:

```sh
kill -TERM $(mgba_pid)    # then relaunch, and:
kill -SEGV $(mgba_pid)    # then relaunch, and:
kill -KILL $(mgba_pid)
```

After each one, read the row's `Last exit:` line. `AdapterPin.json`'s
`exit_detection` table is what the classifier matches against:

| what you do | status / reason | expected `Last exit:` |
|---|---|---|
| `kill -TERM` | `15` / `uncaughtSignal` | `clean` |
| `kill -SEGV` | `11` / `uncaughtSignal` | `crashed` |
| `kill -KILL` | `9` / `uncaughtSignal` | `killed` |
| **⌘Q in mGBA** | `0` / `exit` | `unknown(status: 0, reason: "exit")` — **confirmed 2026-09-13** |

### Confirmed: a normal quit classifies as `unknown`

Settled by hand on 2026-09-13 — the owner pressed ⌘Q and the row read
`Last exit: unknown(status: 0, reason: "exit")`. Recorded as a broken window. The
pin has no signature for `status 0 / exit`, so this is a real defect, not a test
artifact:

* the pin calls `15 / uncaughtSignal` **`clean`** — but SIGTERM is what *the app*
  sends via `Process.terminate()`, and the pin's own note says mGBA treats it
  exactly like a crash, with no graceful save-and-quit;
* so "clean" currently means "we asked it to stop", and the single most common real
  exit — the user pressing ⌘Q — has no signature at all;
* the automated suites cannot catch this, because they classify against the same
  pin table they are asserting. Only a real ⌘Q can.

The three `kill` rows are still unrun — those are what is left of Run D.

---

## Recording the results

Each run maps to one sub-record under `### 7.` in
`.planning/phases/03-mac-offline-play-vertical-slice/03-UAT.md`:

| run | sub-record |
|---|---|
| A, A2 | `#### Blocked offline record` |
| B | `#### Blocked quit-and-return record` |
| C, D | `#### Blocked refusal-and-exit-classification record` |

Flip `result: blocked` to `pass` only for clauses you actually watched, and put
the observed strings in `evidence`. Then run `scripts/check-uat-tally.sh` — it
reconciles the `## Summary` footer against the per-item results and will fail if
the counts drift.

None of this replaces the CI automation path, which still needs the
freely-redistributable-homebrew-ROM licensing decision. A hand run proves the path
works once, on one machine.
