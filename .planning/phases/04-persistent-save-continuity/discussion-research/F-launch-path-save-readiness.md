# Area F — Launch-path save readiness and preflight

**Requirements in scope:** SAVE-03 (restore a compatible checksummed revision and
continue on a clean paired Mac), CACH-04 / P3 D-23 (launch preflight makes zero
network calls), P3 D-09 (six-check readiness engine, a concrete remedy per
blocker, Play only after verified preflight).

**One-sentence thesis:** save handling is not a readiness check; it is a
*materialization step* that sits between "preflight passed" and
`AdapterHost.launch`, it never makes a network call, and it is governed by one
rule — **the launch path only ever writes save bytes into emptiness or over
bytes it can prove are an ancestor of the head it is restoring.**

---

## 0. What is actually in the repo today (grepped, not assumed)

| Fact | Evidence |
|---|---|
| `ReadinessCheckKind` already has **six** cases and the sixth is `saveDirectory` | `playstead-mac/Playstead/Readiness/ReadinessCheck.swift:6-13` |
| The sixth check tests only *directory existence + writability* | `Readiness/ReadinessEngine.swift:249-263` (`evaluateSaveDirectory`) |
| `PreflightChecker` is purely local: `attributesOfItem` → size/inode/mtime vs `cas.verifyRecord` → full re-hash fallback. No `URLSession` anywhere in the file | `Cache/PreflightChecker.swift:34-79` |
| The save directory is **already** `<AppSupport>/Playstead/saves/<assetSetID>/`, a sibling of `launch/`, and the asset-set id is `PathSafety.validatedFilename`-checked | `App/PlaysteadApp.swift:680-685` |
| `LaunchMaterializer.materialize` **deletes the entire launch dir** and rebuilds from CAS on every launch (`removeItem` at `LaunchMaterializer.swift:43-46`) | so a save inside `launch/` would be destroyed every launch — the current sibling layout is correct and must be locked |
| Materialization uses `FileManager.copyItem` (APFS clone / full copy), never hardlink, per D-20 | `LaunchMaterializer.swift:22-28, 70` |
| The live Play flow is: `readinessReport` → guard `isReady` → `materialize` → `saveDirectoryURL` + `createDirectory` → resolve BIOS → `playSessionRecorder.began` → `adapterHost.launch(romPath:saveDir:biosPath:)` with an exit callback | `Library/GameRowView.swift:314-372` |
| The emulator is handed a **directory** (`-C savegamePath={saveDir}`) and picks its own filename `{romBaseName}.sav` | `Adapter/AdapterPin.json:9,20-21` |
| `JournalApplier` has **no** `save` case — `applyOne`'s `default:` skips unknown entity kinds and counts them, never fails | `Sync/JournalApplier.swift:83-93` |
| There is **no** save table in SQLite | `Persistence/Migrations.swift` — tables are catalogue, curation×5, sync_cursor, download_queue_items, cache_objects, quota_policy, pins, outbox_entries, play_sessions_pending, adapter_installations, bios_files, controller_mappings |
| **Bug found:** `AppPaths.excludeRootFromBackup` sets `isExcludedFromBackup = true` on the **root**, so `saves/` and `playstead.sqlite3` are currently excluded from Time Machine | `App/AppPaths.swift:39, 51-58` — see D-F12 |

So: greenfield on the save side, but the launch path and the save *directory*
already exist and are correctly placed. This area mostly decides what happens in
a ~20-line gap in `GameRowView.play()` between `materialize` and `launch`.

---

## 1. JTBD framing

**Primary job.** *When* I sit down at a Mac and press Play on a game I have
progress in, *I want* the game to open exactly where I left off — on any of my
machines — *so that* my library feels like a console, not a file-sync product.

**Secondary job (the one that decides the design).** *When* my devices disagree
about my progress, *I want* to still be able to play right now, *and* I want an
absolute guarantee that pressing Play did not throw away the version I am not
looking at — *so that* I never have to audit my own saves.

| | |
|---|---|
| **Who** | The single first adopter, with 1–3 paired Macs and one server. |
| **What** | Press Play. |
| **Where/When** | At the library card or detail view; frequently offline; sometimes on a Mac paired ten minutes ago. |
| **Why** | To play, not to administer sync. Every second and every click between Play and pixels is a tax. |
| **Needs to do it** | The game bytes (already guaranteed by preflight), an emulator, and **the right 32 KB at `savegamePath`**. |
| **Gets back** | The game, at their progress. Plus, afterwards and quietly, a receipt for anything non-obvious that happened. |

**Domain nouns:** *saved progress* (the user-facing noun — never "save file",
never "revision", never "blob"), *this Mac's copy*, *the version on your server*,
*two versions*. **Verbs:** *pick up*, *restore*, *keep*, *review*. **Events:**
`SavePrepared(plan)`, `SaveRestored(revision, fromDevice)`, `SaveKeptOnDisk`,
`UncapturedBytesFound`, `LaunchedOnLocalBranch`.

**Consumer-shaped, not provider-shaped.** The launch path never shows a digest,
a revision id, a parent pointer, a cursor, or the word "journal". The one place a
backend concept is forced into the surface is *device name* ("your MacBook Air"),
because "which of my machines wrote this" is genuinely the user's own mental
model and there is no simpler way to say it. Everything else stays behind the
detail view's progressive disclosure.

---

## 2. Question 1 — is save readiness a preflight check at all?

**No. Preflight stays at six checks; `ReadinessCheckKind` stays frozen at six
cases.**

The argument from what preflight *is*: `ReadinessEngine` returns
`.blocked(String)` only with an executable `Remedy` attached
(`Readiness/Remedy.swift:3-6` — "A blocking result is never shipped without one
of these"). A check earns a slot in that engine only if it can be *false* in a
way that (a) makes launching pointless or destructive and (b) has a button the
user can press to fix it.

Run save conditions through that test:

| Candidate save condition | Blocks launch? | Has a remedy? | Verdict |
|---|---|---|---|
| No saved progress anywhere | No — starting a fresh game is the *normal, correct* outcome and the phase premise | n/a | Not a check. An alarm here would fire on every first launch of every game forever. |
| Local has the head revision's bytes | No — this is the healthy case | n/a | Not a check. "Quiet by default" (ethos #3): a check that is green 99% of the time is chrome, not readiness. |
| A newer server revision is known but its bytes are not local | No — the game is fully playable; the newer version is *preserved*, not lost | Only a network action, which is forbidden here | Not a check. Degraded-launch metadata. |
| Slot is conflicted | No — blocking play to force sync administration is hostile (§5) | Remedy exists but it is a *user flow* (area G), not a one-button fix | Not a check. Non-modal notice. |
| Save directory missing / unwritable | **Yes** — the emulator will run and silently discard 100% of the session | **Yes** — `repairSaveDirectory`, already implemented at `PlaysteadApp.swift:740-750` | **The one blocking save condition. Already check #6. Keep it, sharpen its finding text.** |
| Save file itself unwritable (dir writable, file mode/immutable-flag wrong) | Yes, same reason | Same remedy | **Fold into check #6** — widen `evaluateSaveDirectory` from a directory test to a *"can I atomically place a file here"* test (§7). No new kind. |

That last row is the only substantive change to preflight and it is a
strengthening of an existing check, not a seventh one. Keeping the enum at six
also protects `ReadinessReportView`/`ReadinessSheetView` and their tests from a
contract change, and keeps the P3 D-09 sentence "six real, entirely local checks"
true (`ReadinessEngine.swift:3-8`).

**Where save handling lives instead:** a new type, `LaunchSavePlanner`, called
from `GameRowView.play()` *after* `report.isReady` and *after*
`materialize(...)`, returning a `SavePlan` that a small `SaveMaterializer`
executes before `adapterHost.launch`. Pure decision / impure execution, split so
the decision is exhaustively testable without a filesystem.

---

## 3. Question 2 — the zero-network wall, resolved

**Preflight and the whole Play flow make zero network calls. No exceptions, no
"cheap 32 KB", no cancellable step, no fire-and-forget task.** CACH-04 is a
constitutional constraint (`.planning/PROJECT.md`: "a verified local game must
stay launchable with no network"), and a 32 KB fetch on the launch path is still
a DNS lookup, a TLS handshake, a captive-portal hang, and a timeout budget
sitting between the user and their game. Xbox's GDK flow is the cautionary
example: its step 2 is a **connection check** and its step 3 is a **distributed
lock acquisition**, both before gameplay, and the documented failure modes
include "the title terminates" and "we need to close this game or app" mid-
session ([Xbox GDK, Understanding the Game Saves sync
flow](https://learn.microsoft.com/en-us/gaming/gdk/docs/features/common/game-save/game-saves-syncing)).
That is precisely the class of failure this project exists not to have.

### What "newer" means with zero network

It means: **strictly what already-applied local journal state says.** Once area
B/D land, `JournalApplier` gains a `case "save"` (currently the `default:` skip
at `JournalApplier.swift:88-93`) and a `save_revisions` table exists locally.
`LaunchSavePlanner` reads that table with one indexed SQLite query. The client
therefore routinely knows a server-side revision exists whose bytes it has not
fetched — that knowledge is free, and it is what makes case (b) below
distinguishable from case (c).

### The three situations, decided

**(a) Local knows of a newer head *and* already has its bytes.**
Handled entirely offline. `SavePlan` = `.restore(head)` if the save file is
absent, or `.fastForward(head)` if the on-disk bytes hash to a known **ancestor**
of `head` (§4). Zero network, zero prompts, zero ceremony. This is the case the
whole design optimises for, and the answer to "why does this feel like a
console".

**(b) Local knows of a newer head whose 32 KB it has not fetched.**
The launch does **not** fetch it. `SavePlan` = whatever the local bytes support
(`.keep` or `.fresh`), tagged `degraded(.headBytesUnavailable)`. Nothing is
overwritten; the unfetched head is safe on the server; the revision captured at
exit descends from the *local* head, so the slot becomes divergent and area B's
detection catches it on the next sync. The user sees a quiet, non-blocking notice
(§9) and a non-launch-path action to bring the bytes down.

**The real fix for (b) is to make it nearly impossible, off the launch path**,
via two prefetch rules I am asserting as decisions here because this area is the
one that suffers when they are absent:

- **D-F03 — saves ride along with the game download.** Downloading a game is
  inherently an online act on a non-critical path. The download job for an asset
  set also fetches the head save revision's bytes into the CAS. This is what
  makes the clean-Mac headline flow (§5) a *zero-network* auto-restore at Play
  time. 32 KB on top of a multi-megabyte ROM is free.
- **D-F04 — journal-apply prefetch.** When `JournalApplier` applies a `save`
  entry for an asset set that is locally present (verified or pinned), the sync
  engine enqueues the revision's bytes immediately. No heuristic, no "is it
  worth it" decision: at 32 KB, unconditional prefetch is cheaper than the code
  that would decide.

With both, case (b) reduces to "you added a save on another device while this
Mac was offline, and you are still offline" — which is case (c) wearing a hat,
and is exactly the situation where a network call was never going to help.

**(c) Local is stale and does not know at all.**
Indistinguishable from "no newer revision exists", and that is fine and honest.
Play the local bytes. Recovery is by convergence, not by prediction: the exit
capture creates a revision, the next successful sync applies the server's, and
area B detects divergence. The user is never told "you might be stale" — that is
an unfalsifiable anxiety message with no action attached, and it is exactly the
Steam Cloud "you may have a conflict later, click Play anyway" pattern that users
have complained about for years with no way to disable it
([Steam Community, "Games not launching with cloud sync issue popping
up"](https://steamcommunity.com/discussions/forum/1/4202490424037431587)).

---

## 4. The launch-time save algorithm (the load-bearing artefact)

```
LaunchSavePlanner.plan(assetSetID:romURL:) -> SavePlan     // pure w.r.t. writes; reads disk + SQLite

  target   = saves/<assetSetID>/<romURL.deletingPathExtension().lastPathComponent>.sav
  onDisk   = stat(target)  ? sha256(read(target)) : nil    // 32 KB, ~0.1 ms
  slot     = saveStore.slot(assetSetID)                    // area B: heads[], known revision digests, ancestry

  case (onDisk == nil || size == 0):
    slot.heads == []                              -> .fresh
    slot.heads == [h], bytesLocal(h)              -> .restore(h)              // clean-Mac case
    slot.heads == [h], !bytesLocal(h)             -> .fresh + degraded(.headBytesUnavailable)
    slot.heads.count > 1                          -> .restore(localBranchHead) if bytesLocal
                                                     else .fresh
                                                   + conflicted
  case (onDisk != nil):
    slot.heads == [h] && onDisk == h              -> .keep                    // already correct
    slot.heads == [h] && onDisk ∈ ancestors(h)    -> .fastForward(h)          // ONLY safe overwrite
    slot.heads.count > 1                          -> .keep + conflicted       // never write a head over a head
    onDisk ∉ slot.knownDigests                    -> .keep + uncaptured       // stale/foreign bytes: capture first
    otherwise                                      -> .keep + degraded
```

**The invariant, stated as a testable sentence:** *the launch path writes to
`savegamePath` only when the target is absent/empty, or when the bytes currently
there hash to a proven ancestor of a single uncontested head.* Everything else is
`.keep`. There is no code path in which Play overwrites bytes whose content is
not already recorded in the revision graph.

`.fastForward` is the concession that makes multi-device life bearable and it is
the one I had to argue myself into. Without it, returning to Mac A after playing
on Mac B leaves Mac A's older `.sav` in place forever and the design fails the
console test. With it, the overwrite is *provably lossless*: the on-disk bytes
are byte-identical to a revision already in the graph, so replacing them destroys
nothing that is not already durable. It is Xbox's "only cloud changed → download
cloud>local" row, reached without a network call because ancestry is local
knowledge.

**Filename derivation.** `romBaseName` is derived from the *materialized ROM URL
the same launch is about to pass to the emulator* (`materialized.files.first`),
never from an independently stored name. Two sources would drift the day a server
renames a member, and the symptom — "my save vanished" — would be maddening to
diagnose.

**One launch per asset set.** A per-`assetSetID` mutex guards the whole
prepare→spawn→exit window. Two mGBA processes mmap-ing the same `.sav` is
guaranteed corruption, and `AdapterProcessRegistry` (`Adapter/AdapterHost.swift`)
currently tracks processes globally without any such exclusion.

---

## 5. Question 3 — the clean-Mac first launch

**D-F05: silent auto-restore, but only into emptiness.** On a freshly paired Mac
that has just downloaded a game the user has progress in, `onDisk == nil` and
`slot.heads == [h]` with bytes local (guaranteed by D-F03), so the plan is
`.restore(h)`, executed with no prompt, no sheet, no confirmation. Play → game →
their progress.

**Why silent is right.** Least surprise favours it: the player's model is
"my progress follows me", and every console honours it. Nintendo's automatic
save-data download runs *in sleep mode*, before the user ever presses anything
([Nintendo, How to Download Save Data Cloud
Backups](https://en-americas-support.nintendo.com/app/answers/detail/a_id/41208/)).
PS Plus auto-download retrieves the latest cloud save on game start with no
dialog ([PlayStation, PS Plus cloud storage for PS5
consoles](https://www.playstation.com/en-us/support/subscriptions/ps5-ps-plus-cloud-storage/)).
Even Xbox — the most dialog-happy of the three — prompts *only* on the
"both changed" row of its four-outcome table; "only cloud changed" downloads
silently. An explicit "restore your progress?" step would make Playstead the only
system in the category that asks a question whose answer is always yes.

**Why silent is nonetheless dangerous, and how that is neutralised.** The failure
mode is overwriting a local save the user did not know existed — the exact
complaint pattern behind Xbox's "choosing Older will permanently overwrite your
progress" warnings and GOG's conflict prompt firing "even if the files are
exactly the same but Galaxy lost track of them"
([GOG forum](https://www.gog.com/forum/general/galaxy_cloud_storage_algorithm_curiousity)).
The algorithm in §4 makes that failure structurally impossible rather than
improbable: restore is reachable only from `onDisk == nil`, and the only other
write is a provable fast-forward. **The answer to "does it depend on whether
local state is empty" is: yes, entirely — emptiness is the precondition, not a
heuristic.**

**Receipt, not prompt.** Ethos #1 requires every automated action to produce an
understandable receipt. The receipt is *after* the fact and *outside* the launch
path: the game's detail view Save section reads "Picked up from your {device}
save — {relative time}." It is not a toast, not a modal, and it does not delay
the emulator by one frame.

**A save-timeline choice at launch is rejected outright.** It is SEED-001/019
territory, it is out of scope for Phase 4, and putting a picker between Play and
pixels would be the single most anti-ethos thing this phase could ship.

---

## 6. Question 4 — launching a conflicted slot

**D-F06: Play never blocks on a conflict, never prompts at launch, and never
writes the other head's bytes.** The plan is `.keep` (or `.restore` into
emptiness on the local branch). The bytes already on disk stay exactly as they
are.

Blocking is hostile — the user pressed Play, not "Resolve". But the counter-
argument in the prompt is real and I am treating it as decisive: **playing
extends one branch, so the act of playing changes the shape of the conflict.**
Here is exactly what the recommendation does about it:

1. **The act of playing resolves nothing, and is never presented as resolving
   anything.** The other head is untouched: not deleted, not superseded, not
   marked "loser". The slot is still conflicted after the session. Area G's
   resolution flow sees the same two branches it saw before, one of which is now
   longer.
2. **Divergence deepens by exactly one revision, on the branch that was already
   the one physically on this Mac** — the branch the user was demonstrably about
   to continue. We do not create a *third* branch, and we do not silently
   fast-forward across the conflict.
3. **The user is told before they press Play, without a modal.** A persistent,
   focusable, non-colour-only inline notice in the card's detail region (never the
   card's single status slot — that is P3 D-13's frozen ladder and area E's
   territory) says what playing will do (§9). It is *informational and
   pre-emptive*, which is the honest version of Steam's "clicking Play may
   overwrite the save you want to keep" — with the crucial difference that in our
   design it *cannot* overwrite anything, so the notice is a description rather
   than a warning.
4. **A one-click escape hatch exists and is not on the launch path**: "Review
   both versions" opens area G's flow. If the user wants the other side before
   playing, that is where they get it, deliberately.

RetroArch is the closest prior art for the underlying stance and it got this
right: on conflict it overwrites neither side and excludes the file from sync
until resolved ([libretro docs, RetroArch Cloud
Sync](https://docs.libretro.com/guides/retroarch-cloud-sync/)). Its documented
failures are all in the *transport* (crashes on Windows fetch, iOS >10 files,
Android WebDAV — issues
[#17474](https://github.com/libretro/RetroArch/issues/17474),
[#17991](https://github.com/libretro/RetroArch/issues/17991),
[#17462](https://github.com/libretro/RetroArch/issues/17462)) — which is a second
argument for keeping transport off the launch path entirely.

---

## 7. Question 5 — what launch does to the save directory

**D-F07: lock the existing location.** `<AppSupport>/Playstead/saves/<assetSetID>/`,
a **sibling** of `launch/`, never inside it. This is already what
`PlaysteadApp.saveDirectoryURL` does and it must never change, because
`LaunchMaterializer.materialize` unconditionally `removeItem`s the whole launch
directory on every single launch (`LaunchMaterializer.swift:43-46`) — a save
under `launch/` would be deleted by the very next Play. The clonefile-materialized
launch dir holds only re-derivable ROM bytes; save bytes are irreplaceable and
live outside it. D-20's "never hardlink, so the emulator cannot write through to
a verified CAS copy" applies with more force here: save bytes are **never**
cloned, hardlinked, or symlinked from the CAS into `saves/` — they are written as
a fresh independent file, because the emulator will mmap and rewrite it in place
and any sharing at all would corrupt the CAS object.

**D-F08: atomic, crash-safe pre-launch write.**

```
staging = saves/<id>/.staging-<uuid>.sav        // same directory ⇒ same filesystem ⇒ rename is atomic
write(staging, bytes); fsync(fd); close(fd)
rename(staging, target)                          // atomic replace
fsync(dirfd(saves/<id>))                         // durable directory entry
```

Never write in place. An in-place write that is torn by a crash or a `kill -9`
produces a `.sav` that is neither the old nor the new save, and mGBA will mmap it
and treat the garbage as the player's progress. `.staging-*` files are reaped on
next planner run — their presence means a previous prepare died before its
rename, in which case `target` is provably still the prior good bytes, so the
staging file is simply deleted. The write only happens on `.restore` /
`.fastForward`, i.e. never in steady-state play, so its ~10 ms cost is not on the
common path at all.

**Widen check #6.** `evaluateSaveDirectory` becomes a "can I atomically place a
file here" probe: directory exists, is a directory, is writable, **and** a
zero-byte staging create+rename+unlink round-trip succeeds. Same
`ReadinessCheckKind.saveDirectory`, same `RemedyAction.repairSaveDirectory`, one
extra syscall triple. Directory-writable alone is a weaker claim than the launch
actually needs (an immutable-flagged or root-owned existing `.sav` passes the
current check and then fails the launch).

**Stale uncaptured `.sav` — collision with area A, assumption stated not decided.**
When `onDisk ∉ slot.knownDigests`, the bytes on disk are unrecorded work: last
session's progress after a crash, an import, or a user hand-dropping a file. The
launch plan is **always `.keep`** — those bytes are never overwritten and never
discarded.

> **Assumption (area A owns this):** before spawn, the launch path calls a
> synchronous `SaveCapture.captureIfUncaptured(assetSetID:at:)` that reads the
> 32 KB, hashes it, and records a revision with provenance
> `origin: .recoveredAtLaunch`. I am assuming this exists, is synchronous, costs
> <2 ms, and is a no-op when the digest is already known. **If area A instead
> makes capture exclusively post-exit, this becomes a real data-loss hole**: the
> emulator will mmap and rewrite those bytes within ~24 s and the unrecorded
> prior state is gone forever. **Area A must expose a pre-launch capture entry
> point.** Flagged loudly.

---

## 8. Question 6 — after the emulator exits

**D-F09: the Play flow returns silently and awaits nothing.** On the exit
callback the launch path does exactly three things: release the per-asset-set
launch mutex; hand `(assetSetID, sessionID, exitInfo)` to area A's post-exit
capture as a detached task; return. No modal, no "Saving…" spinner, no
success confirmation, no blocking wait.

The spike's finding forces this. `SIGTERM` is indistinguishable from a crash
(`terminationStatus: 15, terminationReason: uncaughtSignal` for clean quit,
SIGSEGV and SIGKILL alike; `03-ADAPTER-PIN.json` records "no observed
graceful-quit path"), so **the exit status carries zero information about save
completeness.** Any UI the launch path showed on exit would be a claim it cannot
support. Two concrete rules follow:

- **Exit info is provenance, never a gate.** Capture must run identically for
  every exit code. The launch path passes `AdapterExit` through as metadata for
  the revision record and nothing else. A `guard exit.status == 0` anywhere in
  the save path would be a bug that discards saves precisely when they matter.
- **Never say "saved".** Because of the measured ~24 s mmap flush cadence, up to
  24 s of play may not be on disk at exit. The truthful surface is the recorded
  revision's own timestamp in the detail view, not a launch-path affirmation.
  Ethos: "Never say 'Synced' when a write is merely queued."

`PlaySessionRecorder.ended(sessionID)` already runs in this callback
(`GameRowView.swift:365-369`) and swallows its own failures; save capture adopts
the same discipline — it can never make a launch or an exit fail.

---

## 9. Question 7 — remedies and microcopy (locked strings)

**Blocking — exactly one, the sharpened check #6.**

| Slot | String |
|---|---|
| Blocker (`outcome.blocked`) | `Playstead can't write this game's saves.` |
| Finding | `Nothing has been lost — your saved progress is still on your server. Playstead needs to be able to write to this game's save folder before it starts the game.` |
| Remedy button | `Repair save folder` |
| VoiceOver | `Blocked. Playstead can't write this game's saves. Your progress is safe on your server. Activate Repair save folder to fix it.` |

(`RemedyAction.repairSaveDirectory` keeps its identifier; only the user-visible
label changes from "Repair save directory" to "Repair save folder" — "folder" is
the ordinary custody noun, per ethos #2. The current finding string
"Playstead can't currently write saves to its save directory" is replaced because
it answers only question 1 of the five the ethos error template requires.)

**Non-blocking, worth saying. All four are inline, quiet, in the game detail
view's Save section — never a modal, never a toast, never the card's one status
slot.**

| Case | Copy |
|---|---|
| Restored into emptiness (§5) | **`Picked up from your {deviceName} save.`** — sub-line: `Saved {relative time} on {deviceName}. Nothing on this Mac was replaced.` |
| Uncaptured bytes found and kept (§7) | **`Kept the save already on this Mac.`** — sub-line: `Playstead found saved progress here it hadn't recorded yet, so it saved a copy before starting.` |
| Head bytes not local, case (b) (§3) | **`Starting fresh on this Mac.`** — sub-line: `Newer progress from {deviceName} hasn't downloaded here yet. It's safe on your server and nothing will be overwritten.` — action: `Download saved progress` (network action, deliberately **not** on the launch path; enabled only when reachable, otherwise shown disabled with `Available when you're back online`) |
| Conflicted slot, pre-Play notice (§6) | **`Two versions of this save exist.`** — sub-line: `Playing now continues the version on this Mac. The other version stays exactly as it is.` — action: `Review both versions` |

Voice check against EXPERIENCE-ETHOS: no blame ("This wasn't caused by anything
you did" is already the house pattern at `ReadinessEngine.swift:139`), no jargon,
data-safety stated before the problem, one concrete next action, and no
exclamation of success we cannot prove.

---

## 10. Question 8 — offline, end to end

Verified local game, no server, no internet, no optional services:

1. Press Play. `readinessReport` runs six checks — all local `stat`/re-hash/SQLite
   (`PreflightChecker.swift`, `ReadinessEngine.swift`). Zero sockets.
2. `LaunchMaterializer.materialize` clonefiles ROM bytes out of the local CAS.
   Zero sockets.
3. `LaunchSavePlanner.plan` reads one SQLite row and one 32 KB file. Zero sockets.
4. `SaveMaterializer` executes at most one staged-write+rename. Zero sockets.
5. `AdapterHost.launch` spawns mGBA. Zero sockets.

**What save is used:** whatever §4's algorithm resolves from purely local
knowledge — head bytes if present and safe, otherwise the bytes already on disk,
otherwise nothing (fresh). **What the user is told:** normally nothing at all;
the offline indicator already reads "Last synced {relative time}" per the UI-SPEC
copywriting contract, and no save-specific offline messaging is added. **What is
queued:** the post-exit capture writes a revision locally and an outbox entry
(`Sync/Outbox.swift`, existing machinery, P1 D-20 idempotency key + UUIDv7).
**On reconnect:** the outbox drains, the server accepts or the journal reveals a
concurrent head, and area B's detection turns that into a conflict the user sees
in the detail view — never during a launch.

**Confirmation:** nothing in this area's recommendation reads the network. D-F03
and D-F04 are the only network-touching decisions and both are explicitly on the
download/sync path, not the launch path. Proven by test #5 in §13.

---

## 11. Question 9 — performance budget

**Budget: ≤ 25 ms p99 added to the synchronous pre-spawn window, and ≤ 3 ms in
the steady state.** P3 D-07 kept session recording off the launch path
deliberately; this area spends a strictly smaller amount.

| Step | Cost | When |
|---|---|---|
| One indexed SQLite read of the save slot | < 1 ms | every launch |
| `stat` on the target `.sav` | < 0.1 ms | every launch |
| Read + SHA-256 of 32 KB | ~0.1 ms | every launch where a `.sav` exists |
| Ancestor lookup in the local revision graph | < 1 ms | when both a head and on-disk bytes exist |
| Pre-launch capture of uncaptured bytes (area A) | ~2 ms | rare |
| Staged write + `fsync` + rename + dir `fsync` of 32 KB | ~5–15 ms APFS | **only** on `.restore` / `.fastForward` — i.e. first launch on a Mac, or after playing elsewhere |
| Widened check-6 staging probe | ~1 ms | every launch |

**Allowed synchronously before spawn:** exactly the rows above. **Deferred to
after spawn or after exit:** revision upload, journal emission, retention and
dedupe (area D), provenance enrichment, detail-view refresh, receipt rendering,
session recording (already deferred). **Forbidden synchronously, always:** any
network call, any directory tree walk, any re-hash of ROM bytes beyond preflight's
existing cheap size+inode+mtime check, any UI that can take focus.

---

## 12. Questions 10 & 11 — accessibility, and what survives save states

**D-F10: zero modals on the launch path.** This is the accessibility decision and
it falls out of §5/§6 rather than being bolted on. Every save communication is
inline text plus at most one button inside the game detail region the user was
already navigating. Consequences: nothing to focus-trap, nothing to
Escape-dismiss, no focus to restore, no controller-hostile dialog between Play
and the game. A modal on the launch path is expensive for every input method and
worst for controller users, and since the only genuinely blocking save condition
already routes through the existing `ReadinessSheetView` (which carries 03.5
D-20's focus-containment, Escape-dismissal and focus-restoration behaviour), the
modal budget is already spent and does not need topping up.

Inline notices are: reachable in the existing focus order, operable with
keyboard and controller identically (P3 D-14), announced as one VoiceOver
sentence, and **never colour-only** — each pairs an SF Symbol glyph with its text
(`exclamationmark.arrow.triangle.2.circlepath` for the conflict notice,
`arrow.down.circle` for the not-yet-downloaded notice), per WCAG 1.4.1 and P3
D-13's non-colour-only rule. The conflict notice must not borrow a
`--status-*` colour value in a way that implies a card-status ladder rank; it
lives in the detail region, and area E owns whether anything reaches the card's
single status slot.

**Forward compatibility (SEED-019).** The surviving seam is **`SavePlan` plus one
type owning the decision.** `LaunchSavePlanner` is the only code allowed to
decide what bytes are at `savegamePath`; when save states arrive, the enum gains
`.resumeFromState(...)` and the launch path is unchanged. The vocabulary survives
too: the user-facing noun is **"saved progress"** for battery saves specifically,
never a generic "save" — so a future "resume from a state" surface can introduce
its own honest noun without either surface lying about the other, which is
exactly SEED-019's stated fear. SEED-001's provenance rides on the revision
record area B/D own, and the launch path contributes two provenance fields it is
uniquely able to know: `origin: .recoveredAtLaunch | .capturedAfterSession` and
`launchedFromRevision: <parent>`.

**Deliberately not built:** any launch-time save picker; any "resume from state
or system save?" prompt; any save timeline, naming, tagging, or slot UI; any
launch-time network fetch, retry, or lock-acquisition protocol; any
Steam-style "Play anyway" affordance (there is nothing to play *anyway* past,
because nothing blocks).

---

## 13. Question 12 — how this is proven (named tests, 03.5 D-03)

| # | Test | Asserts | Runs now? |
|---|---|---|---|
| 1 | `LaunchSavePlannerTests.testEmptyLocalStateRestoresHeadRevision` | `onDisk == nil`, one head with local bytes → `.restore(h)`; target file afterwards is byte-identical to the revision | ✅ synthetic 32 KB fixture |
| 2 | `LaunchSavePlannerTests.testExistingUnknownBytesAreKeptAndNeverOverwritten` | unknown digest on disk → `.keep` + `uncaptured`; target bytes unchanged after prepare | ✅ |
| 3 | `LaunchSavePlannerTests.testConflictedSlotNeverWritesTheOtherHead` | two heads → plan writes nothing when a file exists; both heads still present in the store afterwards; playing does not mark either head resolved | ✅ |
| 4 | `LaunchSavePlannerTests.testAncestorOnDiskFastForwardsToHead` | on-disk digest ∈ `ancestors(head)`, single head → `.fastForward`; and the negative: a non-ancestor never fast-forwards | ✅ |
| 5 | `LaunchSavePlannerTests.testKnownNewerHeadWithMissingBytesDegradesWithoutNetwork` | head known, bytes absent → `.fresh`/`.keep` + `degraded`, and zero requests issued | ✅ |
| 6 | `LaunchPathZeroNetworkTests.testPlayFlowIssuesNoHTTPRequestsAtAll` | drives the **whole** Play flow (readiness → materialize → save prepare → spawn stub) behind `StubURLProtocol`; asserts `recordedRequests.isEmpty` — **stricter than 03.5 D-10's precedent**, which asserted zero `/api/v1/blobs/` requests; here *any* request is a failure | ✅ |
| 7 | `LaunchPathZeroNetworkTests.testOfflineLaunchSucceedsWithReachabilityDown` | `Reachability` forced offline, no server process → launch still spawns and the correct bytes are at `savegamePath` | ✅ |
| 8 | `ReadinessEngineTests.testSaveDirectoryIsTheOnlyBlockingSaveCondition` + `testReadinessCheckKindHasExactlySixCases` | `ReadinessCheckKind.allCases.count == 6`; each non-directory save condition produces `.ready` from the engine | ✅ |
| 9 | `ReadinessEngineTests.testUnwritableSaveTargetBlocksWithRepairRemedy` | immutable/root-owned existing `.sav` with a writable directory → blocked + `repairSaveDirectory`; the *current* directory-only check would pass, so this is a regression guard for the widening | ✅ |
| 10 | `SaveMaterializerTests.testInterruptedStagingWriteLeavesPriorSaveIntact` | a `.staging-*` file left behind → target unchanged, staging reaped, plan still correct | ✅ |
| 11 | `SaveMaterializerTests.testSaveIsNeverInsideTheLaunchDirectory` | asserts `saves/` is not a descendant of `paths.launch`, and that a `materialize()` call does not delete the save file — the direct regression guard for `LaunchMaterializer.swift:43-46` | ✅ |
| 12 | `LaunchPathPerformanceTests.testSavePreparationStaysUnderBudget` | measured (XCTMetric, no fixed sleeps — 03.5 D-03 prohibits them): prepare ≤ 25 ms with a write, ≤ 3 ms steady-state | ✅ |
| 13 | `SaveNoticeAccessibilityTests.testConflictNoticeIsFocusableKeyboardOperableAndNotColourOnly` | notice is in the focus order, activatable by keyboard and controller, exposes one VoiceOver sentence, carries a glyph alongside colour | ✅ |
| 14 | `SaveNoticeAccessibilityTests.testLaunchPathPresentsNoModal` | no sheet/alert is presented anywhere in a successful Play flow, including the conflicted and degraded cases | ✅ |
| 15 | `SaveMicrocopyTests.testLockedStrings` | the six strings in §9 exist verbatim and are reachable from their states | ✅ |

**Honestly blocked on checkpoint 7 (real emulator + real game bytes):** that mGBA
*semantically* resumes from a restored `.sav` (tests 1–4 prove the bytes land;
only a real ROM proves the player sees their progress); the interaction between a
pre-launch write and the measured ~24 s mmap flush cadence; `romBaseName`
derivation against a real ROM filename; and whether a `.sav` written immediately
before spawn is picked up by mGBA's initial mmap rather than being clobbered by
its first flush. Tests 1–15 run today on synthetic 32 KB fixtures under 03.5 D-09's
deterministic profiles — no copyrighted ROMs, no proprietary BIOS.

---

## 14. Options considered

| Option | Sketch | Pros | Cons | Failure modes | Reversibility | Effort |
|---|---|---|---|---|---|---|
| **A. Seventh preflight check "save readiness"** | `ReadinessCheckKind.saveContinuity` with `.ready/.warning/.blocked` | fits the existing engine; one place to look | fires green on ~every launch (alarm, not readiness); its blocking cases have no local remedy; widens a frozen enum and its UI | user learns to ignore the readiness sheet; a network-shaped remedy leaks onto a zero-network path | costly (public enum + sheet + tests) | M |
| **B. Launch-time 32 KB fetch, cancellable, offline-degradable** | before spawn, `GET` the head revision if bytes missing | matches Steam/Xbox; the multi-device case always works | violates CACH-04's plain reading; adds DNS/TLS/captive-portal latency to Play; a cancel button on the launch path is the exact thing users complain about | hang behind a captive portal; a "Play anyway" affordance appears and the design becomes Steam's | one-way in spirit — once Play can touch the network the constraint is gone | M |
| **C. Prompt at launch ("restore your progress?" / "which version?")** | modal sheet before spawn | explicit consent; no silent overwrite | asks a question whose answer is always yes; modal on the launch path is worst-case for controller users; the documented complaint pattern for Steam, Xbox and GOG alike | prompt fatigue → the user clicks through the one prompt that mattered | cheap to remove, expensive to un-teach | M |
| **D. Silent restore always (overwrite whatever is there with the head)** | `restore(head)` unconditionally | simplest; feels most console-like | destroys unrecorded local bytes; violates "never silently discard save conflicts" | the crash-recovery case loses a session every time | one-way per incident — bytes are gone | S |
| **E. ⭐ Restore into emptiness + provable fast-forward + keep otherwise (§4)** | the algorithm above | zero network; zero prompts; structurally cannot lose bytes; multi-device happy path still works; conflicts stay conflicts | a user can play a stale save for one session before noticing (§15); depends on D-F03/D-F04 prefetch to be quiet in practice; needs area A's pre-launch capture hook | if area A ships capture as post-exit-only, the uncaptured-bytes case leaks | cheap — it is a pure planner behind one enum | M |

---

## 15. Adversarial pass on option E

**"Your 'never overwrite non-empty bytes' rule reintroduces exactly the stale-save
problem consoles solved."** The strongest hit, and the reason `.fastForward`
exists. Without it, a user who plays on Mac B and returns to Mac A gets Mac A's
old file forever and the product fails its own headline promise. With it, the
common multi-device case is handled with a *provably lossless* overwrite and the
`.keep` rule only binds when the on-disk bytes are genuinely unrecorded — which
is precisely when keeping them is right. **Residual risk:** if the on-disk bytes
are an ancestor *and* the slot is conflicted, we still keep, so the user plays
the local branch. That is correct (we cannot pick a winner) but it is a real
"why is my progress old" moment; the §9 conflict notice is the whole mitigation.

**"A hostile reviewer says silent auto-restore is the RetroArch/Steam clobbering
bug with better prose."** It is not, and the difference is checkable in one test
(#2): restore is unreachable when a file exists. The clobbering bugs in that
literature all stem from timestamp comparison across machines with untrusted
clocks; this design compares *content digests and ancestry*, never clocks.

**"Zero network at launch means you can be confidently wrong."** True. Case (c)
plays stale bytes and cannot know it. Accepted: it is unavoidable given CACH-04,
it is the same situation as any offline console, and the cost is bounded by
convergence-on-reconnect plus never destroying either side.

**"Your budget assumes area A's pre-launch capture."** Yes, and that is the one
dependency that can turn this design from safe to lossy. Flagged as the top
collision (§16) rather than assumed quietly.

**"25 ms is not free."** Correct, and in the steady state it is ~3 ms: no write
happens on a normal repeat launch, because `onDisk == head` yields `.keep`.

**"What if two Playstead windows launch the same game?"** The per-asset-set mutex
(§4). Without it, two mGBA processes mmap the same 32 KB and the loser's session
is silently annihilated. This is a real hole in today's code
(`AdapterProcessRegistry` tracks but does not exclude) and I am closing it here.

---

## 16. Decisions (one-shot, numbered)

| # | Decision | Rationale (one line) | Reversibility |
|---|---|---|---|
| **D-F01** | Save readiness is **not** a preflight check; `ReadinessCheckKind` stays at exactly six cases. | A check that is green on virtually every launch is an alarm, not readiness. | cheap |
| **D-F02** | Widen check #6 `saveDirectory` from "directory writable" to "a file can be atomically placed here", keeping the same kind and the same `repairSaveDirectory` remedy. | Directory-writable is a weaker claim than the launch actually needs; an immutable existing `.sav` passes today and fails at spawn. | cheap |
| **D-F03** | **Saves ride along with the game download**: the download job for an asset set also fetches the head save revision's 32 KB into the CAS. | Turns SAVE-03's clean-Mac restore into a zero-network operation at Play time. | cheap |
| **D-F04** | `JournalApplier`'s new `save` case triggers **unconditional prefetch** of the revision's bytes for any locally-present asset set. | At 32 KB, prefetching is cheaper than the code that would decide whether to. | cheap |
| **D-F05** | New type `LaunchSavePlanner` returns a `SavePlan` (`.fresh/.restore/.fastForward/.keep` + flags), called between `materialize` and `AdapterHost.launch`. Pure decision, separate impure executor. | One type owns "what bytes are at `savegamePath`" — the seam SEED-019 needs. | cheap |
| **D-F06** | **The launch path writes save bytes only into emptiness, or over bytes that hash to a proven ancestor of a single uncontested head.** Everything else is `.keep`. | Makes silent save loss structurally impossible rather than merely unlikely; one testable invariant. | one-way in spirit (it is the safety contract) |
| **D-F07** | Clean-Mac first launch **silently auto-restores** the head; no prompt, no sheet. Receipt appears afterwards in the detail view. | Every console does this; asking a question whose answer is always yes is anti-ethos. Safe only because D-F06 gates it on emptiness. | cheap |
| **D-F08** | A conflicted slot **never blocks Play, never prompts at launch, and never writes the other head**. Playing extends only the local branch and resolves nothing. A persistent non-modal inline notice says so before Play. | The user pressed Play, not Resolve — but the act of playing must never be presented, or coded, as picking a side. | cheap |
| **D-F09** | Saves live at `<root>/saves/<assetSetID>/`, a sibling of `launch/`, **never** inside it, and are **never** cloned/hardlinked/symlinked from the CAS. | `LaunchMaterializer` deletes the whole launch dir every launch; and the emulator mmap-rewrites the save in place. | one-way (locking existing behaviour) |
| **D-F10** | Pre-launch writes are staged in the same directory, `fsync`'d, `rename`d, then the directory is `fsync`'d. Never in place. Orphan staging files are reaped. | A torn in-place write yields a `.sav` that is neither old nor new, and mGBA will mmap it as truth. | cheap |
| **D-F11** | Zero network calls anywhere in the Play flow — not preflight, not the save step, not a background task kicked off by Play. Proven by asserting **zero** recorded requests, not zero blob requests. | CACH-04 is constitutional; and a fetch after spawn cannot help anyway, since mutating a mmap'd `.sav` under a running emulator is corruption. | one-way |
| **D-F12** | Per-`assetSetID` launch mutex covering prepare→spawn→exit. | Two emulator processes mmap-ing one 32 KB `.sav` is guaranteed silent corruption; today nothing prevents it. | cheap |
| **D-F13** | The Play flow returns **silently** after spawn and awaits nothing from capture; exit info is passed as provenance and is **never** a gate on capture. | Exit is indistinguishable from a crash, so exit status carries no information about save completeness. | cheap |
| **D-F14** | **No modal anywhere on the launch path.** All save communication is inline, focusable, keyboard/controller-operable, non-colour-only, in the detail region. | The modal budget is already spent on `ReadinessSheetView`; a second one is worst-case for controller users. | cheap |
| **D-F15** | Lock the six microcopy strings in §9. User-facing noun is **"saved progress"**, never "save file"/"revision"/"blob"; the one backend concept allowed through is *device name*. | Keeps SEED-019's future "save state" surface able to introduce an honest noun without either surface lying. | cheap |
| **D-F16** | **Bug fix:** move `isExcludedFromBackup` off `AppPaths.root` onto `objects/`, `partials/`, `launch/`, `emulators/` individually, leaving `saves/` and `playstead.sqlite3` backed up by Time Machine. | Today `AppPaths.swift:39,51-58` excludes the entire root, so save bytes — the one irreplaceable thing on the client — are silently outside the user's backups, violating ethos #16. | cheap |

---

## 17. Prior art — what to copy, what to avoid

| System | Copy this | Avoid this |
|---|---|---|
| **Xbox GDK Game Saves** ([sync flow](https://learn.microsoft.com/en-us/gaming/gdk/docs/features/common/game-save/game-saves-syncing)) | The four-outcome table (neither/local/cloud/both changed) is exactly right, and only the *both* row prompts. Explicit offline mode. | Connection check + distributed lock acquisition **before** gameplay, "forcefully acquire the lock", and mid-session termination ("We need to close this game or app"). Never put a lock protocol on a launch path. |
| **Steam Cloud** ([partner docs](https://partner.steamgames.com/doc/features/cloud); [complaint thread](https://steamcommunity.com/discussions/forum/1/4202490424037431587)) | "Files are automatically downloaded to the new computer prior to the game launching" — the clean-Mac promise, stated plainly. | The unsuppressible pre-launch conflict dialog and its "Play anyway" escape. Steam Support's own answer is "you can ignore it"; there is no option to disable it. A warning the user is told to ignore is worse than no warning. |
| **Nintendo Switch Online** ([download cloud backups](https://en-americas-support.nintendo.com/app/answers/detail/a_id/41208/); [missing backups](https://en-americas-support.nintendo.com/app/answers/detail/a_id/41227/)) | Sync happens **in sleep mode and on software close** — never at launch. Automatic download when cloud is newer, no dialog. This is D-F03/D-F04's model. | Silent deletion of backups after subscription lapse; and the deliberate per-title exclusions that surprise users. Our equivalent sin would be evicting save bytes under quota — saves must never be evictable (area D). |
| **PS Plus cloud storage** ([PlayStation support](https://www.playstation.com/en-us/support/subscriptions/ps5-ps-plus-cloud-storage/)) | Auto-upload on close/rest, auto-download on start, both invisible. | Dependence on a rest-mode setting most users never find; the feature silently does nothing if "Stay Connected to the Internet" is off. Our design must not have a settings-dependent silent no-op. |
| **GOG Galaxy** ([forum](https://www.gog.com/forum/general/galaxy_cloud_storage_algorithm_curiousity); [sync-failed KB](https://support.gog.com/hc/en-us/articles/360013667997)) | Honesty about uncertainty. | "Galaxy will always ask if it's not sure — **even if the files are exactly the same** but Galaxy lost track of them." Prompting on a false conflict is the worst outcome; digest comparison (not bookkeeping state) is why we cannot do this. No "keep both" option is offered — ours is effectively always keep-both. |
| **RetroArch Cloud Sync** ([docs](https://docs.libretro.com/guides/retroarch-cloud-sync/); issues [#17474](https://github.com/libretro/RetroArch/issues/17474), [#17991](https://github.com/libretro/RetroArch/issues/17991), [#16663](https://github.com/libretro/RetroArch/issues/16663)) | On conflict, overwrite **neither** side, log it, exclude the file from sync until resolved. Directly D-F08. | All the documented failures are transport crashes and platform-specific sync bugs — a standing argument for keeping transport off the launch path entirely. |
| **EmuDeck CloudSync** ([manual](https://manual.emudeck.com/using-app/10_cloud_saves/); issue [#1082](https://github.com/dragoonDorise/EmuDeck/issues/1082)) | Warns about a failed upload on the *next* launch rather than blocking the current one. | Recurring error notifications after closing a game (#1082) — post-exit noise for a condition the user cannot act on. D-F13's "return silently" is the direct response. |

*Mutable sources:* the Xbox GDK page (edited 2025-06-20, moniker gdk-2604) and
the RetroArch issue tracker both change; revalidate at plan time.

---

## 18. Role-lens sweep

- **Architect / domain modeller:** `LaunchSavePlanner` is a pure domain service over
  (slot, on-disk digest); `SaveMaterializer` is the only infrastructure. The launch
  path depends on the save context, never the reverse. No digest, cursor, or journal
  noun crosses into the UI layer.
- **Distributed systems:** causality is content-ancestry, never wall clocks — the one
  design choice that immunises us against the timestamp-comparison bugs behind most
  cloud-save clobbering. Partition behaviour is total (offline is the design centre).
  Convergence is deferred to area B; the launch path's only obligation is to never
  create a third branch.
- **Elixir/OTP/Phoenix:** no server-side change is required by this area at all —
  `save` is already a frozen journal entity kind and `/api/v1` is additive-only.
  Explicitly not applicable beyond that.
- **Swift/macOS:** `Process` lifecycle already handled by `AdapterProcessRegistry`;
  this area adds the missing per-asset-set exclusion. mmap/page-cache semantics are
  the reason for staged-write-and-rename and for never sharing inodes with the CAS.
- **Filesystem/durability:** same-directory rename for atomicity, two `fsync`s, no
  clonefile for save bytes, `kill -9` leaves either the old file or the new one and
  never a hybrid.
- **Security:** `assetSetID` and `declaredName` are already `PathSafety`-validated
  before becoming path components (`PlaysteadApp.swift:680-685`,
  `LaunchMaterializer.swift:59-64`); the save target inherits that. Restored bytes are
  untrusted input, but they are handed only to the emulator, never parsed by us — the
  32 KB size is validated against the format identity area C owns. No digest, device
  id, or ROM name reaches logs or CI evidence.
- **SRE/operator:** the launch path emits no alerts. The only observable is the
  revision record and its provenance.
- **Product/first adopter:** step 9–10 of PROJECT.md's First End-to-End Proof works
  with zero clicks beyond Play.
- **Performance:** ~3 ms steady state on a 32 KB file. No database was built for it.
- **Accessibility:** no launch-path modal at all — see D-F14.

---

## 19. Coherence notes — collisions with the other areas

| Area | What I assume | Collision risk |
|---|---|---|
| **A — capture trigger and loss window** | 🚨 **Loudest flag.** I need a **synchronous pre-launch** `captureIfUncaptured(assetSetID:at:)` (32 KB read + hash, no-op when the digest is known). If area A ships capture as post-exit-only, the crash-recovery case is a real data-loss hole: mGBA rewrites those bytes within ~24 s. I also assume capture never gates on exit status (D-F13) and never runs on the synchronous launch path except for that one no-op-usually probe. | **High.** Must be resolved at synthesis. |
| **B — revision lineage and conflict detection** | I need three primitives locally, offline: `slot.heads`, `bytesLocal(revision)`, and `isAncestor(digest, of: head)`. `.fastForward` is impossible without cheap local ancestry, and the whole design degrades to "always keep" without it. I also assume a conflicted slot is representable with ≥2 heads and that "which head is on this Mac" is derivable. | **High.** `.fastForward` is my answer to the strongest objection against this design; if ancestry is not locally queryable, re-litigate §4. |
| **C — restore compatibility gate** | The gate runs **inside `LaunchSavePlanner`**, before any write, and an incompatible revision degrades to `.fresh`/`.keep` + a notice — **never** to a blocking preflight check and never to a write. Compatibility must be checkable with zero network (adapter id/version and format identity are local facts). | **Medium.** If area C wants a blocking gate, it collides with D-F01. |
| **D — retention, dedupe, storage** | Save bytes are **never evictable** under P3 D-21's quota/floor and never garbage-collected while they are a head or an ancestor of one; D-F03/D-F04 prefetch is compatible with retention policy; and D-F16's backup-exclusion fix is really area D's to own. | **Medium** on eviction: if saves are evictable, `bytesLocal(head)` becomes flaky and case (b) stops being rare. |
| **E — status surfacing vs. the one-status-slot ladder** | Nothing I recommend writes to the card's single status slot. All four notices live in the detail region. If area E wants a save state on the card ladder, it must fit P3 D-13's strict priority and it is area E's call, not mine. | **Low**, but say it explicitly at synthesis so both areas do not claim the same pixel. |
| **G — what "resolve a conflict" does** | My conflict notice's `Review both versions` is the sole entry point from the launch surface into area G's flow, and it is **never** auto-opened. Area G owns the modal. | **Low.** |
| **H — export shape** | No interaction. Launch never touches export layout. | None. |

---

## 20. Residual risks (recorded, not hand-waved)

1. **A user can play a stale save for one session and only find out afterwards**
   (case (c), or a conflicted slot where the local branch is behind). This is the
   direct price of zero-network launch plus never-clobber. Accepted under precedence
   #1 (data safety) over #2 (continuity). Mitigated only by D-F03/D-F04 prefetch and
   the §9 notices.
2. **Everything depends on area A exposing pre-launch capture.** Without it, the
   uncaptured-bytes case loses data within ~24 s of spawn.
3. **`.fastForward` depends on cheap local ancestry from area B.** Without it the
   multi-device return-to-Mac-A case regresses to "your save looks old".
4. **Unproven until checkpoint 7:** that mGBA actually resumes from a `.sav` written
   moments before spawn rather than clobbering it on its first mmap flush. Tests 1–4
   prove the bytes land; only real bytes prove the player sees them.
5. **Pre-launch `fsync` cost is measured only on APFS/SSD.** An external or network-
   backed Application Support directory could blow the 25 ms budget; the budget is a
   test, so it will fail loudly rather than degrade silently.
6. **`AppPaths` backup exclusion (D-F16) may be load-bearing elsewhere** — moving it
   off the root changes Time Machine behaviour for the SQLite database too. That is
   intended (the read model plus outbox is worth backing up) but it should be
   confirmed against whatever area D decides about server-authoritative rebuild.
