# Area A — Capture Trigger and Loss Window (SAVE-01)

**Question:** when, exactly, does mGBA's on-disk `{saveDir}/{romBaseName}.sav`
become an immutable Playstead save revision on the Mac?

**Answer in one line:** while a play session is live, Playstead reads the whole
32 KB artifact once per second, hashes the bytes it read, and turns a digest that
has held still for 3 consecutive reads into a staged capture; the last staged
capture of a session — after a bounded post-exit settle pass that survives app
death — is promoted to an immutable revision. No FSEvents. No kqueue. No mtime.

---

## 0. What the repo actually says (grepped, not assumed)

| Claim | Verified where | Verdict |
|---|---|---|
| Save dir is **outside** the launch dir and outside the CAS | `Playstead/App/PlaysteadApp.swift:681` `saveDirectoryURL(forAssetSetID:)` → `<root>/saves/<assetSetID>/` | **Already true.** Q7 is settled by shipped code. `AppPaths` (`App/AppPaths.swift`) owns `objects/ partials/ launch/ emulators/ bios/`; `saves/` is created by `PlaysteadApp`, sibling to `launch/`. Launch-dir teardown/eviction (`EvictionPlanner`, `LaunchMaterializer`) can never reach it. |
| `savegamePath` is injected per-asset-set, not per-launch-dir | `AdapterHost.renderedLaunchArguments(romPath:saveDir:)` :189, pin `argument_template: ["-C","savegamePath={saveDir}","{romPath}"]` | Verified. Emulator writes only into `saves/<id>/`, never through a `clonefile` into the CAS (P3 D-20 holds). |
| Save dir writability is already a preflight check | `Readiness/ReadinessEngine.swift:252` `.saveDirectory`, with a `repairSaveDirectory` remedy (`PlaysteadApp.swift:742`) | Verified. Area F inherits a working seam. |
| **`saves/` is currently excluded from Time Machine** | `AppPaths.excludeRootFromBackup()` sets `isExcludedFromBackup = true` on **`root`**, and `saves/` + `playstead.sqlite3` live under `root` | **VERIFIED BUG.** See D-A9. This is the single most important finding in this area. |
| `AdapterExit.clean` does **not** mean "the emulator flushed" | `Adapter/AdapterExit.swift` classifies `(15, uncaughtSignal)` → `.clean`; the pin says SIGTERM is a raw signal death | Verified. The enum case is a *classification of the signal we sent*, not a durability guarantee. Nothing in Phase 4 may branch capture behaviour on it. |
| No save code exists yet | `grep -rn "Revision\|capture" Playstead/` → nothing save-shaped | Verified greenfield. |
| `StreamingSHA256` exists with `update/finalizeHex/resume(from:)` | `Cache/StreamingSHA256.swift:14-28` | Verified — reusable, but see D-A6 for why the 32 KB path does not use the streaming form. |

**Spike artifacts are gone.** `spike/out/save-timeline.jsonl` and `probe-03.json`
are `.gitignore`d and not present on disk (`find` over the repo: no matches). The
surviving evidence is `03-SPIKE-REPORT.md` lines 13 and 29–36, which record:
8 distinct SHA-256 values over a 185 s live-play window at indices
**1, 25, 49, 73, 97, 121, 145, 169 seconds** — dead-regular 24 s spacing — and
`kill -9` two seconds after a flush losing nothing (pre/post digests identical).

**The measurement method matters enormously and is the key to this whole area.**
`spike/scripts/watch-save.sh` is a **1 Hz `stat` + `shasum -a 256` poller**. So:

- **PROVEN:** the bytes returned by an ordinary `read()` of the `.sav` file change
  every ~24 s during play, and are byte-stable in between. This is measured with
  exactly the mechanism I am recommending we ship. That is a very strong position:
  the trigger is the instrument that produced the constraint.
- **PROVEN:** `kill -9` mid-window loses nothing beyond the last flush; the flush
  cadence *is* the durability floor.
- **NOT PROVEN, and unprovable from surviving evidence:** whether `st_mtime`
  moves in lockstep with content (the script recorded mtime, but the JSONL is
  gone and the report never analysed it); whether the inode is stable (never
  recorded — so "mGBA rewrites in place rather than write-and-rename" is
  **inference from the mmap architecture, not measurement**); whether FSEvents or
  a `DispatchSource` vnode watch fires at all for these writes.
- **NOT PROVEN:** anything about a *real* commercial GBA game. `savetest.gba`
  writes SRAM every ~5 s in a tight loop. A real game writes on room transitions
  and menu saves, which is far sparser and burstier. The 24 s cadence is a
  property of mGBA's dirty-timer, not of the ROM — but that is inference too.

I refuse to claim more than that.

---

## 1. Detection mechanism

### The mmap problem, stated honestly

mGBA maps the save file (`GBASavedataInitSRAM` → `vf->map(..., MAP_WRITE)`,
`GBASavedataClean` → `vf->sync(...)` on a dirty timer;
[savedata.c](https://github.com/mgba-emu/mgba/blob/master/src/gba/savedata.c)) and
`sync` is `msync` on a shared mapping. There is **no temp-file-and-rename**. This
is the architectural reading; it is consistent with everything measured, but it is
inference.

For an in-place `msync` writer, event-based watchers are the wrong instrument, and
the ecosystem documents this — for Linux. fswatch's README states plainly that the
**inotify** and **fanotify** monitors "do not report accesses or modifications
that occur through `mmap(2)`, `msync(2)`, or `munmap(2)`", and in the same list
says the **FSEvents** monitor "has no known limitations"
([fswatch README](https://github.com/emcrisostomo/fswatch/blob/master/README.md)).

I want to be very precise here, because a careless reading (including the first
page of search results, which conflates the two) will tell you "FSEvents doesn't
see mmap writes." **That is not a documented fact for macOS.** What is true:

- The mmap/msync blind spot is *documented* for inotify/fanotify.
- For macOS it is *plausible by the same mechanism* — FSEvents is fed from VFS
  operations, and `msync` writeback reaches the disk through `VNOP_PAGEOUT`
  rather than `VNOP_WRITE` — but Apple documents neither the presence nor the
  absence of an event on that path, and `DispatchSource`'s `.write` vnode flag
  has the same question mark.
- Nobody has measured it for mGBA on APFS. Not the spike, not me.

So the design choice is between "build on an undocumented kernel behaviour we
have not measured" and "build on the exact behaviour we *have* measured, eight
times, at 1 Hz."

### Options

| Option | Sketch | Pros | Cons / failure modes | Reversibility | Effort |
|---|---|---|---|---|---|
| **A1. FSEvents on `saves/<id>/`** | `FSEventStreamCreate` with `kFSEventStreamCreateFlagFileEvents`, latency 1.0 | Cheap at rest; scales to many dirs; kernel-coalesced | **May never fire for `msync` writeback** — unmeasured. Coalescing + latency means the event is not a settle signal anyway. Historical-event replay (`sinceWhen`, device UUID) is real bookkeeping we do not need. Silent total failure mode: you simply capture nothing and don't know it | cheap | M |
| **A2. `DispatchSource.makeFileSystemObjectSource` vnode watch** | open an fd on the `.sav`, watch `.write .extend .attrib .delete .rename` | Per-file, low latency, no stream bookkeeping | Same unmeasured `msync` question. Requires the file to **already exist** — on a first-ever launch it does not, so you need a directory watch to catch creation, i.e. two mechanisms. Holds an fd on a file the emulator owns | cheap | M |
| **A3. 1 Hz read-and-hash poll, session-scoped** | while a session is live: `Data(contentsOf:)` → SHA-256 → compare | **This is the instrument that produced the phase's constraint.** Cannot miss an mmap/msync write, because it does not depend on kernel notification at all. Content *is* the signal: no mtime trust, no inode trust, no rename question. Deterministic and trivially testable with a fake clock. Lifetime is bounded by the session — no daemon, no background watch, no wake-the-disk-at-idle | Wakes 1×/s during play (only during play); "polling" reads as unsophisticated to a reviewer | cheap | **S** |
| **A4. Hybrid: event watcher as accelerant + poll as ground truth** | A1/A2 to shorten latency, A3 as the truth | Fast *and* correct | Two code paths, two sets of tests, two failure modes, for a **24-second** cadence. The accelerant saves at most 1 second on a 24-second clock. Pure cost | cheap | M |
| **A5. `NSFilePresenter` / `NSFileCoordinator`** | present the save dir, react to `presentedItemDidChange` | Correct macOS idiom for *cooperating* processes; gives you conflict-safe reads | **mGBA is not a coordinated writer.** File coordination only serialises against other coordinators; an uncooperative mmap writer ignores it entirely. It buys nothing and implies a safety it does not deliver | cheap | M |

### Cost check on A3, because "polling" triggers reviewers

32768 bytes read + SHA-256 once per second, only while a game is running (the
CPU is already busy emulating). SHA-256 on Apple silicon is ~1–2 GB/s via
CryptoKit's accelerated path: **~20 µs of CPU per second, ~0.002%.** The file is
in the unified buffer cache the emulator is actively mapping, so the read costs no
I/O. There is no energy argument, no thermal argument, no battery argument. A
`stat` prefilter to avoid the hash would add an mtime-trust dependency we
explicitly do not want, to save 20 µs. Don't.

### Decision

**Poll. Only poll.** A3.

### The probe that settles what remains open

**Probe SAVE-P1 — "flush observability and file identity"** (30 minutes of work,
belongs in the first plan of Phase 4, not in discussion):

Run pinned mGBA 0.10.5 against `spike/testrom/savetest.gba` for 180 s with three
simultaneous observers on `saves/<id>/`:
1. the existing 1 Hz read-and-hash poller (ground truth), extended to also record
   `st_ino`, `st_mtimespec` (nanoseconds), `st_size`, and APFS clone/dataless flags;
2. an `FSEventStream` with `kFSEventStreamCreateFlagFileEvents`, latency 0.0;
3. a `DispatchSource` vnode source on the open `.sav` fd.

**Pass/fail (this probe cannot fail the phase — it only decides an optimisation):**
- **P1a — inode stability.** PASS iff `st_ino` is identical across all 180 samples.
  If it fails, mGBA is doing write-and-rename and Area A's "in place" reasoning
  needs revisiting (event watching would then work fine, and the torn-read worry
  in §2 evaporates). *Expected: pass.*
- **P1b — mtime fidelity.** PASS iff every observed digest change is accompanied
  by an `st_mtimespec` change. *If it fails, no design change — we already ignore
  mtime.* Recording it kills the temptation forever.
- **P1c — event delivery.** PASS iff ≥5 consecutive digest changes each have at
  least one FSEvents or vnode event within 2 s. **A pass does not change the
  shipped design**; it only records that an accelerant is available if a future
  adapter has a much longer cadence. A fail is the documented justification for
  polling. Either way we stop guessing.
- **P1d — post-exit writeback.** After `kill -9`, poll 30 s. Record whether the
  digest changes *after* process death (dirty MAP_SHARED pages are flushed by the
  pager independent of the process). This sizes the post-exit settle window in
  D-A5. *Expected: either no change, or a change within ~1 s.*

Every one of these is recordable into `04-*-PROBE.json` in the same shape as
`03-ADAPTER-PIN.json`'s `save_contract`, and P1d's measured value becomes a real
field rather than a guess.

---

## 2. Debounce and settle policy

### The honest part first: a torn 32 KB SRAM read is undetectable

A raw GBA battery file has no header, no magic, no length field, no checksum, no
version. It is 32768 bytes of game-defined structure. Many games embed their own
checksum — and Playstead **must not know that**, both because it cannot know it
for every game and because format knowledge in the storage path is exactly what
P2 D-11/D-12 forbade on the server side (`Playstead.Blobs.Store` adapters "must
stay free of format knowledge"). The client store gets the same rule. So:

> **There is no way to look at 32768 bytes and know whether they are a coherent
> save.** Any claim otherwise is a lie. We can only reason about time.

Litestream is the instructive contrast. It can copy a live-mutating SQLite file
safely *only because SQLite hands it a coordination API* — it holds a long-running
read transaction to control checkpointing and copies the WAL to a shadow WAL
([litestream.io/how-it-works](https://litestream.io/how-it-works/)); the same docs
are blunt that `cp` of a live SQLite file "is not transactionally safe"
([Cron-based backup](https://litestream.io/alternatives/cron/)). mGBA offers **no
such API** — `on_demand_flush_supported: false` is precisely the statement that
there is no coordination seam. We are in the `cp` position and cannot leave it.

### What we can do

**Settle rule:** a digest becomes a *capture candidate* when the same digest is
returned by **3 consecutive 1 Hz reads** (i.e. ≥2 s of byte-stability) **and** it
differs from the last staged digest for this session.

Why 3 s against a 24 s cadence:
- It cannot miss a flush: 3 ≪ 24, and even a 4× faster adapter (6 s) has room.
- It costs at most 3 s of extra loss window in the pathological case where the
  process dies mid-settle — and that case is already covered by the post-exit
  pass (§4), which re-reads the file after death.
- A single-poll straddle of an in-progress writeback resolves on the next poll,
  because writeback of 8 pages is microseconds and cannot persist across 2 s.

**What I explicitly reject:**
- *Size stability* as a signal. Size is 32768 forever. It carries zero bits.
- *mtime stability* as a signal. Unmeasured fidelity (P1b), and an mmap writer's
  mtime is updated by the kernel at a time POSIX deliberately leaves loose.
- *Read-twice-and-compare-within-one-poll.* Two reads 100 µs apart is a weaker
  test than two reads 1 s apart and doubles the code.
- *Any parse or plausibility check of the bytes.* See above.

### The property that makes the residual risk survivable

**Capture is append-only and never destructive.** A revision is a new immutable
object; nothing is overwritten, nothing is deleted, no previous revision is
invalidated. Therefore:

> **A torn capture is a wasted 32 KB, never a lost byte.**

That inversion is the whole safety argument, and it is why I am comfortable
shipping a heuristic where a proof is impossible. Record it as accepted residual
risk R-A1 with that mitigation stated in exactly those terms.

---

## 3. Capture cadence during play

Volume arithmetic, so nobody hand-waves: 24 s cadence → **150 captures/hour →
4.8 MB/hour** of raw bytes, before dedupe. A 300-hour RPG playthrough is ~1.4 GB
of 32 KB files. Against a 25 GB quota (P3 D-21) that is not free, and against a
"save history" UI it is pure noise: 150 rows an hour is not a history, it is a log.

But mid-session captures are not worthless: if Playstead is killed at minute 40 of
a 60-minute session, the user's last 40 minutes must not vanish.

**Decision — two-tier, session-scoped:**

- **Staged capture (rolling, durable, invisible).** Every settled distinct digest
  is written to disk immediately (blob + a row on the open `play_session`), and
  **supersedes** the previous staged capture for that session. Exactly **one**
  staged capture is retained per open session. It is durable (survives `kill -9`
  of Playstead) but is not a revision, has no lineage, is never shown, never
  syncs, never exports.
- **Promoted revision (immutable, user-visible, one per session).** At session
  end — after the post-exit settle pass — the final staged capture is promoted to
  an immutable save revision with lineage, and the session row is closed.

Volume becomes **one revision per play session** — a number a human can read, and
a number that makes Area B's lineage DAG a comprehensible object rather than a
firehose. Superseding is a rename of a blob reference plus a row update; the
superseded blob is unreferenced and collectible.

Plus two boundary captures:

- **Session-start baseline.** Read-and-hash the artifact *before* launching. If it
  differs from the last promoted revision's digest, someone modified the save
  outside Playstead (another emulator, a Finder copy, a restore we did not make).
  That is a **real revision with `origin: external`**, promoted immediately, before
  the emulator ever runs. Not doing this means the next session's promoted
  revision silently absorbs foreign bytes and attributes them to us — a lineage
  lie, and precisely the class of thing the constitution's "never silently
  discard" clause exists to prevent. (Cheap: one 32 KB hash at launch, on a path
  that already hashes ROMs.)
- **Empty is not a revision.** If the artifact is absent or zero-length at
  session start (first ever play), there is no baseline and no revision. Absence
  is not data.

---

## 4. Post-exit capture

There is no clean-exit signal — `.clean`, `.crashed`, `.killed`, `.unknown` are
four labels for "the process is gone." **Capture branches on none of them.** One
path, always run.

**Post-exit settle pass (mandatory), triggered from `AdapterHost`'s
`terminationHandler`:**

1. Keep the 1 Hz read-and-hash poller running after `terminationHandler` fires.
   This is not belt-and-braces: dirty pages of a `MAP_SHARED` mapping are written
   back by the pager and **are not discarded when the process dies** — so bytes
   can legitimately appear on disk *after* exit. Probe SAVE-P1d measures this.
2. Stop on the **first** of: (a) 5 consecutive identical digests, or (b) a **10 s**
   hard cap. Whichever fires, the last read wins.
3. If the final digest differs from the last staged capture, stage it. Then
   promote the staged capture to a revision and close the session.
4. If the final digest equals the last promoted revision's digest (a session where
   the player saved nothing new), **promote nothing.** Do not create a revision
   whose only content is "they played and didn't save." The user is not shown a
   version that is identical to the one before it.

The digest comparison is what distinguishes "already captured" from "new bytes."
It is exact, requires no metadata trust, and costs 20 µs.

**Crash recovery — Playstead itself killed between emulator exit and promotion.**

This is the case the question rightly singles out, and it is handled by writing the
session row *before* the launch, not after:

- Before `AdapterHost.launch` is called, insert a `play_session` row in the SQLite
  store (`Persistence/LocalStore.swift` + a forward-only migration) with:
  `id` (client UUIDv7, per P1 D-20 — the same natural key that will carry into
  the change journal), `asset_set_id`, `save_dir_path`, `adapter_pin_digest`,
  `baseline_revision_digest`, `state = 'open'`, `started_at`. Commit it with
  SQLite `synchronous = FULL` before spawning the process.
- On every app launch, `SaveSessionRecovery` scans for `state = 'open'` rows. For
  each: run the **identical** settle-and-capture pass on `save_dir_path`, promote
  the result if it differs, close the row. The pass is idempotent by digest, so
  recovering a session that had actually completed is a no-op.
- Recovery is **silent when it finds nothing new** and quiet-but-visible when it
  promotes a revision (the revision simply appears in the game's save history with
  its capture time). No modal, no "we recovered from a crash" alarm — the user's
  data is fine and telling them about our process is noise
  (EXPERIENCE-ETHOS quiet-by-default).
- An orphan **launch** directory with a still-open session row must not be evicted
  before the row is closed. P3 D-21 already forbids silent deletion, and the save
  dir is not in the launch dir anyway, so this is a belt on an existing brace:
  `EvictionPlanner` gains "an asset set with an open `play_session` is not
  evictable." One predicate.

**Failure mode I am accepting:** if the app is killed *and the save directory is
deleted by the user* before the next launch, recovery finds nothing and logs a
closed-with-no-artifact session. Nothing better is possible.

---

## 5. Atomicity of the capture itself

Two atomicity problems, different and both real.

### 5a. Reading a file the emulator still owns

For a 32 KB artifact: **read the whole file into memory in one pass, hash the
in-memory buffer, and treat that buffer as the capture.** Not "copy then hash"
(the second read can see different bytes than the first, so the digest would not
describe the stored bytes). Not "hash while streaming from the source into the
destination" either, for the same reason at page granularity.

The consequence is the property we want: **the digest provably describes the exact
bytes we are about to store, because both come from one buffer.** The source file
is never read again.

`StreamingSHA256` stays and is not deleted — it is the path for the
generalisation in §8 (a future adapter with a multi-megabyte or directory-shaped
save, where "load it all into memory" is wrong). Rule: **artifacts under a
declared in-memory ceiling (say 8 MB) take the buffer path; larger take the
streaming path with a copy-first-then-hash-the-copy discipline** (hash what
landed, not what was read). Today, mGBA never leaves the buffer path.

Residual: a single `read()` of 32 KB is not itself atomic against a concurrent
`msync`. Unfixable without writer cooperation (§2). Mitigated by the settle rule
and by append-only capture.

### 5b. Storing it crash-safely

Reuse the CAS discipline the client already has (`CASManager`, `AppPaths.objectURL(for:)`,
`PathSafety.validatedDigest`) rather than inventing a second store:

1. Write the buffer to a temp file in a staging directory **on the same APFS
   volume** as the destination (a sibling of the save store, not `/tmp`, so the
   rename is a true rename and not a cross-device copy).
2. `fsync` the temp file's fd. Not optional; a rename does not imply the data
   landed.
3. `rename()` the temp onto the content-addressed path (`<store>/ab/cd/<sha256>`).
   Rename is atomic on APFS.
4. `fsync` the destination *directory* fd, so the directory entry itself is durable.
5. **Only then** write the SQLite row (staged-capture pointer, or promoted
   revision) inside one transaction, with `synchronous = FULL` for save-path writes.

**Ordering rule: bytes before references, always.** A crash at any point leaves
either (a) nothing, or (b) an unreferenced blob — garbage that a later sweep
collects — and *never* a metadata row pointing at bytes that do not exist. A
`kill -9` of Playstead cannot produce a half-written revision, because a revision
does not exist until a committed row names an already-fsynced blob. And it cannot
lose an already-captured revision, because the row was committed durably before we
told anyone the capture happened.

**Digest-addressed storage gives idempotent re-capture for free:** if the blob path
already exists with the right digest, step 1–4 is skipped. Re-running recovery is
harmless by construction.

**Untrusted-bytes posture:** the `.sav` came from an emulator process we launched
but did not audit, in a directory the user can write. Bytes are never parsed, never
executed, never used to derive a path. The path comes from the digest *we*
computed (`PathSafety.validatedDigest` on our own hex output — cheap, keeps one
rule). Size is capped by an adapter-declared ceiling so a rogue writer cannot make
us buffer 4 GB (see §8). No ROM name, no digest, no path is logged at info level.

---

## 6. Honest communication of the 24 s window

### JTBD

**Who:** a person who just played for 40 minutes and is closing the window.
**What:** be confident their progress is kept.
**When/where:** at quit, and again months later when they open the save history.
**Why:** because the failure they fear — losing a session — is invisible until it
is too late to fix.
**What they need:** evidence that a copy exists and *when* it was taken.
**What they get back:** a timestamped save version, and — if they look — one plain
sentence about why it might be a few seconds behind the game.

Domain nouns/verbs/events that fall out: **save** (the thing a game keeps),
**version** (an immutable capture of it, with a time), **play session**;
*play, keep, restore, export*; `session started`, `save version kept`,
`save version restored`. Deliberately **not** in the user's vocabulary: digest,
blob, manifest, capture, promote, staged, revision-parent, cursor, journal.

### The tension

PROJECT.md forbids overclaiming and demands honesty about limits.
EXPERIENCE-ETHOS demands quiet-by-default. A "your last 24 seconds may be at risk"
banner during play would satisfy the first and violate the second, and would also
be **subtly false** — the true exposure at any instant is "time since last flush",
which oscillates between 0 and 24 s and which we would be presenting as a constant.
False precision is a form of overclaiming.

### Decision

**Three placements, none of them interruptive, none of them during play.**

1. **During play: nothing.** No timer, no countdown, no "at risk" chrome. Zero.
2. **After a session, on the save version itself:** a time and a provenance line,
   which is honest by construction because it states what we know rather than what
   we hope.
   > `Kept 3:41 PM · from mGBA 0.10.5`
   (VoiceOver: "Save version, kept today at 3:41 PM, from mGBA 0.10.5.")
3. **Once, in the game's save detail panel — a standing explanatory line, rendered
   from `save_contract`, never hardcoded:**

   > **How Playstead keeps this save**
   > Playstead copies what the emulator has written to disk. mGBA writes about
   > every 24 seconds, so the newest copy can be a few seconds behind where you
   > stopped playing. Save in-game before you quit and it will be there.

   The "24" and "mGBA" are interpolated from `worst_case_loss_seconds` and the
   adapter pin. An adapter with `on_demand_flush_supported: true` renders a
   different, shorter sentence. The last clause is the actionable part and is the
   only advice a user can actually act on.

**Copy rules applied:** plain sentences, no jargon, no exclamation, no fear
framing, no colour-only signal (this is text, and it never becomes a status
badge — the one-status-slot ladder of P3 D-13 is untouched by Area A).

**What I refuse to write:** any string implying "your save is safe up to the
moment you quit", any "saving…" progress affordance at quit (there is nothing to
progress — we cannot ask mGBA to flush), and any "the game crashed" message (we
cannot tell — `(15, uncaughtSignal)` is what a normal quit looks like).

---

## 7. Interaction with the launch directory

Settled by shipped code; recorded here so Phase 4 does not relitigate it.

- `savegamePath` → `~/Library/Application Support/Playstead/saves/<assetSetID>/`,
  a **sibling of** `launch/`, produced by `PlaysteadApp.saveDirectoryURL(forAssetSetID:)`
  with `PathSafety.validatedFilename` on the server-supplied id.
- The emulator therefore writes into a directory that is not the launch dir, not
  a clone of a CAS object, and not reachable from `LaunchMaterializer`'s
  `clonefile` tree. P3 D-20's "never hardlink" invariant is preserved with room to
  spare.
- **Saves survive launch-dir teardown and eviction by construction.** P3 D-21's
  "no silent deletion, ever" absolutely extends to saves, and Phase 4 hardens it:
  `EvictionPlanner` never enumerates `saves/`, and additionally never evicts an
  asset set with an open `play_session`. If a user removes a game entirely, its
  saves are retained and orphaned, not deleted — Area D owns the retention policy,
  but the floor is "eviction of a game never destroys its saves."

### The bug: `saves/` is currently excluded from Time Machine

`AppPaths.excludeRootFromBackup()` sets `isExcludedFromBackup = true` on the cache
**root** — correctly, for `objects/ partials/ launch/ emulators/`, which are all
re-downloadable. But `saves/` and `playstead.sqlite3` live under that same root,
and **backup exclusion of a directory applies to its whole subtree**; setting
`isExcludedFromBackup = false` on the child does not rescue it.

So today, the one class of bytes on this machine that is **not** re-derivable from
the server — the user's actual game progress, and the database that will index it —
is the one class of bytes excluded from the user's backups. That directly inverts
constitution priority #1 (data safety and recoverability) and SAVE-01's
clean-Mac-restore promise.

**Fix (D-A9):** split the root so the exclusion attaches only to derivable data:

```
~/Library/Application Support/Playstead/
  cache/        <- isExcludedFromBackup = true   (objects, partials, launch, emulators)
  saves/        <- backed up                     (live emulator save dirs)
  savestore/    <- backed up                     (content-addressed save revisions)
  playstead.sqlite3  <- backed up
```

with a one-shot idempotent migration that moves the existing subdirectories and,
crucially, **clears** the exclusion flag from the old root. Add a named regression
test asserting `isExcludedFromBackup == false` on `saves/`, `savestore/`, and the
database URL. Exact layout inside `savestore/` is Area D's call; the *exclusion
boundary* is Area A's, because it is a direct consequence of where captures land.

---

## 8. Generalisation boundary — one seam, not a framework

Everything in this design is driven by `save_contract` from the adapter pin. The
mGBA-specific facts (`.sav`, 32768 bytes, 24 s) appear in **no** Swift source.

| `save_contract` field | Consumed by | Behaviour if it changes |
|---|---|---|
| `directory_key` | `AdapterHost.renderedLaunchArguments` (already) | different CLI flag, no capture change |
| `artifact_glob` | the capture unit resolver | more/fewer files, no capture change |
| `on_demand_flush_supported` | pre-capture flush request; today a hard `false` | `true` → request flush, then settle. Same settle code |
| `worst_case_loss_seconds` | §6 microcopy; the settle-window sanity check | different number in one sentence |
| `flush_triggers` | diagnostics only (see below) | — |

**The one abstraction I am building now, because it is the only one a second
adapter genuinely needs:**

> The unit of capture is an **artifact set**: the ordered list of files matching
> `artifact_glob` under the resolved save directory, each as
> `(relative_path, size, sha256)`. The **revision identity is the sha256 of the
> canonicalised manifest** of that list (sorted by relative path, no timestamps —
> the same discipline as `Playstead.Export.Layout` / P2 D-34/D-35).

For mGBA that manifest has exactly one entry, and the extra indirection costs one
hash of ~80 bytes. But it means a multi-file save (PS1 memory cards), a
directory-shaped save (Dolphin GCI folders), and a single-file save are the same
object to lineage (Area B), retention (D), restore (C/F), and export (H), with
**no redesign**. Settle then means "every member's digest stable for 3 polls,"
which falls out unchanged.

**Two additive fields I recommend the pin gain (both defaulted, both honest):**
- `max_artifact_bytes` — a declared ceiling per member, so the capture path
  refuses to buffer an artifact set that has grown implausibly (DoS/quota guard).
  For gba: 131072 (covers 128 KB flash carts).
- `observed_flush_interval_seconds` — written by SAVE-P1, distinct from the
  declared `worst_case_loss_seconds`. RetroArch's history is the reason: its
  10 s SRAM autosave default was added specifically because of unclean-exit data
  loss ([PR #7691](https://github.com/libretro/RetroArch/pull/7691)) and then was
  repeatedly reported **not to actually work** on several platforms
  ([#10644](https://github.com/libretro/RetroArch/issues/10644),
  [#16323](https://github.com/libretro/RetroArch/issues/16323),
  [#17128](https://github.com/libretro/RetroArch/issues/17128)). A declared cadence
  is a claim; ours is measured, and we keep measuring at runtime.

**What I deliberately did NOT build:** a `SaveWatcher` protocol with FSEvents and
polling implementations; a pluggable settle-strategy; a save-format registry; a
generic "capture engine" with adapters. One concrete poller, one manifest concept,
one flush-request call site that returns false today.

---

## 9. Prior art — what to copy, what to avoid

| System | Copy this | Documented footgun to avoid |
|---|---|---|
| **RetroArch SRAM autosave** ([PR #7691](https://github.com/libretro/RetroArch/pull/7691), [#10644](https://github.com/libretro/RetroArch/issues/10644), [#16323](https://github.com/libretro/RetroArch/issues/16323), [#17128](https://github.com/libretro/RetroArch/issues/17128)) | Periodic SRAM flush exists *because* crashes and unclean exits lost saves — exactly our premise. A short interval is the durability floor | A **declared** interval that silently doesn't run on some platforms, with no user-visible signal. Never trust `worst_case_loss_seconds` as behaviour; measure it (`observed_flush_interval_seconds`) |
| **RetroArch Cloud Sync** ([docs](https://docs.libretro.com/guides/retroarch-cloud-sync/)) | On conflict it changes **neither** side and logs it — the right instinct, and the same instinct as our append-only capture | It logs the conflict where a user will never see it. Detection without a surface is not safety (Area G's problem) |
| **Litestream** ([how it works](https://litestream.io/how-it-works/), [cron](https://litestream.io/alternatives/cron/)) | Safe live-file capture *requires writer cooperation*; `cp` of a live DB is not transactionally safe | Do not pretend we have coordination we don't. We are in the `cp` position; the answer is append-only + quiescence + honesty, not a fake guarantee |
| **Ludusavi** ([repo](https://github.com/mtkennerly/ludusavi)) | Scan-and-compare against the last backup, "updated" derived from content diff, not from filesystem events. A removed save is a *state*, not a silent no-op | Its trigger is manual/scheduled; a crash between scans loses the session. Our session-scoped poll closes that gap |
| **Syncthing / Resilio / Dropbox conflicted copies** ([Retro Game Corps guide](https://retrogamecorps.com/2024/08/11/guide-using-syncthing-with-retro-handhelds/)) | Never destroy the loser; materialise both | Conflict files named `foo.sync-conflict-2024….sav` leak the mechanism into the user's folder and are then re-synced as new saves. Keep lineage *inside* our store, not as sibling files in `saves/` |
| **`NSFileCoordinator`/`NSFilePresenter`** | The correct idiom **when both writers cooperate** | mGBA does not coordinate. Using it here would imply a serialisation guarantee that does not exist |
| **fswatch** ([README](https://github.com/emcrisostomo/fswatch/blob/master/README.md)) | Documents per-backend limitations honestly — inotify/fanotify miss `mmap`/`msync`/`munmap` | Do not transplant that claim onto FSEvents; fswatch lists FSEvents as having "no known limitations". macOS behaviour under `msync` is **unmeasured**, which is exactly why SAVE-P1c exists |
| **Time Machine local snapshots** | Cheap immutable point-in-time copies of a mutating volume | They are volume-wide and opaque to us. What we *must* borrow is the inverse lesson: our excluded-root bug means TM is currently not protecting the saves at all (§7, D-A9) |
| **Steam Cloud / Nintendo Switch Online** | NSO deliberately excludes games where cloud restore would break the game's own integrity — an explicit support matrix, not aspirational universality (PROJECT.md's exact constraint) | Steam Cloud's conflict dialog offers "keep local / keep cloud" and *destroys* the loser. Area G must not copy that |

---

## 10. Adversarial pass on my own recommendation

**"You're polling. In 2026."** Yes. The alternative depends on an undocumented,
unmeasured kernel notification path for `msync` writeback, to save at most 1
second on a 24-second clock, at a cost of 0.002% CPU during play only. If SAVE-P1c
passes I *still* would not switch, because the poll is also the settle mechanism
and the ground truth — the event would only tell me to poll sooner.

**"Your settle rule is a superstition. Two identical reads don't prove
coherence."** Correct, and I said so. There is no proof available: the artifact is
not self-describing, and the writer offers no coordination (Litestream's lesson).
The rule reduces the probability of a torn capture to near zero at a 24 s cadence,
and — this is the actual defence — capture is append-only, so a torn capture is a
wasted 32 KB and never a lost byte. Residual risk R-A1, accepted, stated.

**"One revision per session means I can't get back to where I was 20 minutes
ago."** True and deliberate. Intra-session rollback is save-curation territory
(SEED-001/SEED-012), out of scope, and 150 rows/hour would make the save history
unusable and the retention story (Area D) unaffordable. The staged capture keeps
the *data* safe mid-session; it just isn't a *version*. If SEED-001 ever lands,
promoting more staged captures is an additive policy change — the capture pipeline
already produces them. Reversible.

**"Session-start baseline capture will spam revisions."** Only when the artifact
actually changed outside Playstead, which for most users is never. And the
alternative — silently absorbing foreign bytes into our next revision — is a
lineage lie, which is worse than an extra row.

**"You are trusting SQLite for durability of the session row."** With
`synchronous = FULL` on the save path and bytes-before-references ordering, the
worst crash outcome is an unreferenced blob. That is the same trade `CASManager`
already makes for downloads.

**"You've quietly enlarged the phase by fixing a Time Machine bug."** The fix is
a directory split plus a migration, and without it SAVE-01's clean-Mac-restore
criterion is not actually met on a real Mac. It is not scope creep; it is the
phase's stated goal.

**"Your microcopy tells the user about a 24-second window they can do nothing
about."** They can do exactly one thing: save in-game before quitting. The copy
says that, and it is the last clause because it is the actionable part. If a
future adapter has on-demand flush, the sentence disappears on its own.

---

## 11. Decisions (one-shot; renumber at synthesis)

| # | Decision | Rationale | Reversibility |
|---|---|---|---|
| **D-A1** | Capture trigger is a **session-scoped 1 Hz read-and-hash poll** of the artifact set. No FSEvents, no kqueue/`DispatchSource`, no `NSFileCoordinator`, no mtime or size heuristics. | It is the only mechanism proven to observe mGBA's mmap flush — it is the instrument that produced the phase's 24 s constraint. ~20 µs CPU/s, during play only. | **Cheap** — an event accelerant is additive later |
| **D-A2** | Run **Probe SAVE-P1** (a: inode stability, b: mtime fidelity, c: FSEvents/vnode delivery, d: post-exit writeback) in the first Phase 4 plan; record results into the pin's `save_contract`. No result changes D-A1; P1d sizes D-A5's window. | Replaces four inferences with four measurements, at 30 minutes' cost. | **Cheap** |
| **D-A3** | **Settle rule:** a digest is a capture candidate after **3 consecutive identical 1 Hz reads** and only if it differs from the last staged digest. No parse, no plausibility check, no checksum inspection of save bytes — ever. | A raw SRAM file is not self-describing; only temporal quiescence is available, and format knowledge in the store is forbidden (P2 D-11/D-12's rule, applied client-side). | **Cheap** (a tunable constant) |
| **D-A4** | **Two-tier cadence:** every settled distinct digest becomes a durable **staged capture** that supersedes the previous one (exactly one per open session); exactly **one revision is promoted per play session**. Plus a **session-start baseline revision** (`origin: external`) when the artifact differs from the last promoted revision. | 150 rows/hour is a log, not a history; one row/session is legible and affordable. The baseline stops foreign bytes being silently attributed to our session. | **Cheap** — promoting more staged captures is additive (SEED-001) |
| **D-A5** | **Post-exit settle pass is mandatory and unconditional** — it branches on **none** of `AdapterExit`'s four cases. Keep polling after `terminationHandler`; stop at 5 consecutive identical digests or a 10 s cap; promote if the final digest differs from the last promoted revision, otherwise promote nothing. | SIGTERM is indistinguishable from a crash, so there is only one honest path. Dirty `MAP_SHARED` pages can land *after* process death, so post-exit reads can genuinely find new bytes. Identical digest ⇒ nothing new ⇒ no revision. | **Cheap** |
| **D-A6** | **Capture atomicity:** read the whole artifact into one buffer, hash **that buffer**, store **that buffer**. Never hash one read and store another. Artifacts above a declared `max_artifact_bytes` in-memory ceiling take `StreamingSHA256` with hash-what-landed semantics. | Makes the digest provably describe the stored bytes — the property lineage (B), restore (C), and export (H) all depend on. | **Cheap** |
| **D-A7** | **Store discipline: bytes before references.** temp on the same volume → `fsync` file → `rename` to the content-addressed path → `fsync` directory → **then** the SQLite row in one `synchronous = FULL` transaction. A `play_session` row (client UUIDv7, per P1 D-20) is committed **before** the emulator is launched. | A `kill -9` of Playstead at any instant leaves either nothing or a collectible unreferenced blob — never a half-written revision, never a dangling reference, never a lost committed one. | **Costly** to change later (it is the durability contract) |
| **D-A8** | **Crash recovery:** on every app launch, `SaveSessionRecovery` runs the identical settle-and-capture pass over every `state = 'open'` `play_session`, promotes if new, closes the row. Idempotent by digest; silent when nothing is new. `EvictionPlanner` gains "an asset set with an open session is not evictable." | An app killed between emulator exit and promotion must not lose the session; digest-idempotence makes re-running free. Quiet-by-default: a recovered version just appears with its time. | **Cheap** |
| **D-A9** | **Split the Application Support root** so `isExcludedFromBackup` covers only `cache/` (objects, partials, launch, emulators). `saves/`, `savestore/`, and `playstead.sqlite3` move out from under the exclusion, with an idempotent migration that clears the flag from the old root, and a named regression test. | **Verified bug:** `AppPaths.excludeRootFromBackup()` currently excludes the user's saves and the save index from Time Machine — the only non-re-derivable bytes on the machine. Inverts constitution priority #1 and defeats SAVE-01's clean-Mac-restore criterion. | **Costly if deferred** (users accumulate unbacked-up saves); cheap now |
| **D-A10** | **The capture unit is an artifact set**: files matching `artifact_glob` under `directory_key`'s directory, as an ordered `(relative_path, size, sha256)` manifest; **revision identity = sha256 of the canonicalised, sorted, timestamp-free manifest**. One entry for mGBA. | The single seam that lets a multi-file or directory-shaped save adapter slot in with no redesign, mirroring `Export.Layout`'s existing determinism rules (P2 D-34/D-35). | **Costly** to retrofit (it is the identity of a revision), trivial to add now |
| **D-A11** | **No mGBA-specific constant in Swift.** `.sav`, 32768, and 24 all come from `save_contract`. Add two additive pin fields: `max_artifact_bytes` and `observed_flush_interval_seconds` (measured by SAVE-P1 and re-measured per session as a diagnostic). | RetroArch's autosave interval was declared-but-not-working on several platforms; a declared cadence is a claim, and we should measure ours rather than trust it. | **Cheap** (additive pin fields) |
| **D-A12** | **Loss-window microcopy:** nothing during play; a `Kept 3:41 PM · from mGBA 0.10.5` line on each version; and one standing sentence in the save detail panel rendered from `save_contract` (text in §6). Never claim "safe up to the moment you quit", never show a quit-time "saving…" affordance, never say "the game crashed". | Satisfies PROJECT.md's honesty constraint at the one moment a user is actually asking, without violating EXPERIENCE-ETHOS's quiet-by-default rule or presenting an oscillating exposure as a constant. | **Cheap** |
| **D-A13** | **User vocabulary is "save" and "version"**, never "snapshot" (which reads as save-state) and never a backend noun (digest, manifest, blob, capture, promote, cursor). | SEED-019: system saves and save states must stay separable in language; "snapshot" pre-spends the word save states will need. | **Cheap** now, **costly** after users learn it |

---

## 12. How this is proven (03.5 D-03, D-09, D-08)

**The synthetic writer that makes almost all of this provable without hardware:**
`MMapSaveWriterFixture` — a test helper that `mmap`s a real 32768-byte file
`MAP_SHARED`, mutates it on an injected schedule, and `msync`s on an injected
cadence, mimicking `savetest.gba`'s measured behaviour. It uses **real** `mmap`,
`msync`, and real file APIs (03.5 D-09: deterministic profiles seed through real
APIs), with the *clock* injected — never `sleep`, never a fixed delay as evidence
(03.5 D-03).

| Test (named, discoverable, non-skipped) | Proves |
|---|---|
| `SaveCaptureTests.testDistinctFlushProducesExactlyOneStagedCapture` | D-A1, D-A3 — n msync cycles ⇒ n staged captures, each superseding the last |
| `SaveCaptureTests.testUnchangedBytesProduceNoCapture` | D-A4 — identical digest is not a revision |
| `SaveCaptureTests.testTornWriteAcrossPollsDefersUntilQuiescent` | D-A3 — fixture holds a half-updated buffer across 2 polls; exactly one capture, of the completed bytes |
| `SaveCaptureTests.testCaptureDigestEqualsStoredBytesDigest` | D-A6 — one buffer, one digest, one stored object |
| `SaveCaptureTests.testArtifactExceedingDeclaredCeilingIsRefused` | D-A11 — DoS/quota guard |
| `SaveSessionTests.testPostExitSettleCapturesBytesWrittenAfterChildProcessExits` | D-A5 — a child process msyncs then `_exit`s; the post-exit pass captures |
| `SaveSessionTests.testEveryExitClassificationTakesTheIdenticalCapturePath` | D-A5 — parameterised over `.clean/.crashed/.killed/.unknown`; asserts identical outcome |
| `SaveSessionTests.testSessionStartBaselineCapturesExternalModification` | D-A4 — external edit becomes an `origin: external` revision before launch |
| `SaveRecoveryTests.testOpenSessionIsSettledAndPromotedOnNextLaunch` | D-A8 — `SIGKILL` a helper harness mid-session, restart, assert promotion |
| `SaveRecoveryTests.testRecoveryOfAlreadyPromotedSessionIsANoOp` | D-A8 — digest idempotence |
| `SaveStoreTests.testCrashBetweenBlobCommitAndRowInsertLeavesNoDanglingReference` | D-A7 — injected failure at the seam; asserts an orphan blob and no row |
| `SaveStoreTests.testBlobIsFsyncedAndRenamedNotWrittenInPlace` | D-A7 — via an injected file-op recorder (a `FileOps` seam, not a test-only production branch — 03.5 D-08) |
| `EvictionPlannerTests.testAssetSetWithOpenSessionIsNotEvictable` | D-A8 |
| `AppPathsTests.testSavesAndDatabaseAreNotExcludedFromBackup` | **D-A9** — asserts `isExcludedFromBackup == false` on `saves/`, `savestore/`, the DB, and `== true` on `cache/` |
| `AppPathsTests.testRootExclusionMigrationIsIdempotent` | D-A9 |
| `SaveContractTests.testCaptureUnitResolvesMultiFileGlobAsOrderedManifest` | D-A10 — a synthetic 3-file save contract produces a deterministic manifest digest |
| `SaveContractTests.testLossWindowCopyIsRenderedFromPinNotHardcoded` | D-A11, D-A12 — change `worst_case_loss_seconds` to 5, assert the sentence changes |

**What genuinely still needs the blocked hardware/content path** (Phase 3 UAT
checkpoint 7 remains open; do not claim otherwise):

1. That **real mGBA 0.10.5 on real commercial game bytes** flushes on a bounded,
   regular cadence. Measured once, on one homebrew ROM. A real game's SRAM write
   pattern is sparser and burstier; the *emulator's* dirty timer should dominate,
   but that is inference. → SAVE-P1 with a real title.
2. That an artifact written by a real game and captured by us is **accepted back
   by mGBA** as a valid save and shows the right in-game progress. No synthetic
   test can prove this; it needs a human, a real ROM, and eyes on the game's load
   screen. This is Area C/F's UAT too and should be one shared checkpoint, not three.
3. That the post-exit writeback behaviour (P1d) holds for a real title.

Everything else above is provable today, offline, deterministically.

---

## 13. Forward compatibility

| Seed | The exact seam that keeps it open | What I did **not** build |
|---|---|---|
| **SEED-001 (save curation)** | Two things: (a) the **staged capture** tier already produces intra-session captures — promoting more of them is a policy change, not a pipeline change; (b) the revision row carries provenance at capture time: `adapter_pin_digest`, emulator name+version, `origin` (`session` / `external` / `restored` / `imported`), `captured_at`, `manifest_digest`, `session_id`, and per-field `known` vs `inferred`. That provenance is written now because it is only knowable now. | No naming, no notes, no tags, no treasuring, no intra-session history UI |
| **SEED-002 (cartridge)** | `origin: external` + the artifact-set manifest already accept bytes that no play session produced. A cartridge dump is an artifact set with `origin: cartridge` and no `session_id`. No schema change. | No hardware path, no dump/write flow, no format conversion |
| **SEED-019 (system saves vs save states)** | Vocabulary (D-A13: "save"/"version", never "snapshot") plus a `kind` discriminator on the revision, pinned to `battery` in Phase 4 with a compile-gated enum. Save states are a different `kind` with a different `save_contract`, sharing the capture pipeline and **not** sharing the identity/compat rules. | No save-state capture, no second `kind` value, no shared UI surface that would quietly lie |
| **SEED-012 / SEED-010 / SEED-006** | Untouched — none of them intersect the capture trigger. | — |

---

## 14. Coherence notes and collision flags

**Loud collisions (resolve at synthesis, do not assume):**

1. **→ B (lineage).** I assert **revision identity = manifest digest** (D-A10) and
   **one revision per play session** (D-A4), plus a `baseline` revision on external
   modification. If B keys lineage on anything other than the manifest digest, or
   wants a revision per flush, we disagree and it must be settled. I also hand B a
   durable `play_session` row with a client UUIDv7 (P1 D-20's natural key) — B
   should use that as the lineage parent pointer's provenance, not invent a second id.
2. **→ D (retention/storage).** I create staged blobs that are superseded within a
   session, and I claim the exclusion boundary between `cache/` and `savestore/`
   (D-A9). D owns what lives inside `savestore/` and how long, **but must accept
   that (i) save revisions are never silently deleted, (ii) they are never
   Time-Machine-excluded, and (iii) unreferenced blobs need a sweep**. If D wants
   saves inside the CAS `objects/` tree, that directly conflicts with D-A9's
   exclusion split — flagging hard.
3. **→ F (launch preflight).** I add a pre-launch step: baseline read-and-hash +
   `play_session` insert **before** `AdapterHost.launch`. That is on F's critical
   path and must stay zero-network (CACH-04 / P3 D-23) — it is: one 32 KB local
   read and one local SQLite write. F also owns the existing `.saveDirectory`
   readiness check, which my design now depends on being non-advisory: **if the
   save dir is not writable, launch must be blocked, not warned**, because an
   unwritable save dir means the session cannot produce a capture at all.
4. **→ C (restore compat gate).** A restore writes bytes into the live save dir
   *between* sessions. My session-start baseline would then see a change and want
   to record an `origin: external` revision — **wrong**. C's restore must record
   `origin: restored` with a known parent, and the baseline check must recognise
   its own restore's digest and not double-record. Concrete seam: restore writes
   the revision row first, then the file; baseline compares against "last known
   digest for this save", not "last promoted session revision."
5. **→ G (conflict UX).** I promise the user "Kept 3:41 PM" and a *version*
   vocabulary. G must not introduce a competing noun (copy/snapshot/backup) for the
   same object. Also: my design never destroys a loser, which is the precondition
   G needs.
6. **→ E (status ladder).** I add **no** new status-slot state. Capture is
   invisible; there is no "capturing…" state on the card, ever. If E wants a
   save-related rung on P3 D-13's frozen ladder, it does not come from Area A.
7. **→ H (export).** The manifest (D-A10) is deliberately shaped like
   `Export.Layout`'s determinism rules — sorted, timestamp-free. H should export
   the manifest's members by relative path, and the capture provenance belongs in
   the `Sidecar`, not in filenames.

**Assumptions I am making about others:** that revisions are append-only and never
overwritten (the load-bearing assumption of §2's safety argument — if any area
proposes mutating or garbage-collecting-by-default a promoted revision, my torn-read
risk acceptance is void); that the server-side `save` change-journal entity kind
(P1 D-21, already frozen in `entity_kind.ex`) carries revision *metadata* while
bytes go through `Playstead.Blobs.Store`.

## 15. Residual risks

- **R-A1 (accepted).** A capture can be torn and undetectable. Mitigation: 3-second
  quiescence at a 24 s cadence, and append-only capture — a torn capture is a
  wasted 32 KB, never a lost byte. No proof is available (no writer coordination
  API; Litestream's precondition is absent).
- **R-A2 (accepted, measurable).** The 24 s cadence is measured on one homebrew
  ROM. A real title may flush less regularly. Mitigation: SAVE-P1 with a real
  title; `observed_flush_interval_seconds` re-measured per session; microcopy
  rendered from the pin so the number is never a hardcoded lie.
- **R-A3 (accepted).** Up to ~24 s of play is unrecoverable on any exit. Not
  fixable at any layer we control (`on_demand_flush_supported: false`). Mitigation
  is honesty (D-A12), not engineering.
- **R-A4 (open until D-A9 ships).** Saves are currently excluded from Time Machine.
  Until the split lands, SAVE-01's clean-Mac-restore criterion is not met.
- **R-A5 (accepted).** If a user deletes `saves/<id>/` while Playstead is not
  running, the next recovery finds nothing. Nothing better is possible.
- **R-A6 (low).** Polling holds the save file in the page cache and keeps the
  volume from idling during play. The emulator is already doing both.
