# Area D — Retention, Dedupe, and Where Save Revisions Are Stored

Scope: where save revision bytes live on each side, how many are kept, what is
ever removed, how that interacts with P3 D-21's quota/eviction constitution, and
how the local-only danger window is policed.

Everything below marked **[verified]** was read in the repo at the paths given.
Everything marked **[inference]** is reasoning, not observation.

---

## 0. What is actually on disk today (grepped, not assumed)

**Server**

- `playstead-server/lib/playstead/blobs/store.ex` **[verified]** — the `Store`
  behaviour. Its moduledoc is unambiguous: *"`delete/1` is defined **only** for
  uncommitted temporary files… No v1 code path deletes, renames, truncates, or
  moves a committed blob."* There is no GC, no refcount, no sweeper for
  `objects/`. `Playstead.Import.OrphanSweeper` is scoped strictly to `tmp/`
  **[verified]**.
- `blobs/blob.ex` **[verified]** — `blobs` carries **no `user_id`**, deliberately:
  physical bytes are global, `unique_index(:sha256)` makes one copy correct, and
  *"Every logical, user-scoped record references a blob, never the reverse."*
  Columns: `sha256, size_bytes, crc32, md5, sha1, scan_state, scan_reason`.
- `blobs/store/local_disk.ex` **[verified]** — temp → fsync → verify → atomic
  rename into `objects/<aa>/<bb>/<sha>`; the DB unique constraint (never a prior
  `exists?`) is the sole "already present" authority; `tmp/` and `objects/` share
  one filesystem so the rename stays atomic.
- **The landmine.** `LocalDisk.open_write/1` calls
  `Readiness.fits_free_space?(byte_size_hint, available, capacity)`, and
  `Readiness.required_bytes/2` is `requested + max(1 GiB, 5% of capacity)`
  **[verified, `readiness.ex:367-385`]**. So **a 32 KB save upload is refused with
  `{:error, :insufficient_space}` → `storage_insufficient` (507) whenever the blob
  volume has less than ~1 GiB free**, exactly the situation in which a user most
  needs their irreplaceable save to land. This guard was written for multi-GB ROM
  imports and is correct there. It is a priority-inversion defect for saves.
  Decision D-D6 below fixes it.
- `Playstead.RateLimiter` **[verified]** — Hammer, `:ets`, fixed-window, sole
  caller `PlaysteadWeb.Plugs.Throttle` (per-IP + per-account, 429 `rate_limited`).
- `Playstead.Import.UploadSlots` **[verified]** — ETS counter for *concurrent*
  (not rate) uploads, "at most two per device", surfaced by
  `PlaysteadWeb.Plugs.UploadConcurrency` → 429 `too_many_uploads`.
- `PlaysteadWeb.ErrorCodes` **[verified]** — 27 registered codes incl.
  `import_file_too_large` (413), `storage_insufficient` (507),
  `curation_limit_exceeded` (422), `too_many_uploads` (429), `rate_limited` (429).
- `Playstead.Sync.EntityKind` **[verified]** — `~w(device pairing catalogue job
  transfer save curation)a`. `save` is registered with **no producer yet**.

**Mac**

- `Playstead/App/AppPaths.swift` **[verified]** — the whole App Support root
  (`objects/`, `partials/`, `launch/`, `emulators/`, `bios/`, **and
  `playstead.sqlite3`**) is created, then `excludeRootFromBackup` sets
  `isExcludedFromBackup = true` **on `root`**. `isExcludedFromBackup` on a
  directory excludes its entire subtree from Time Machine **[verified behaviour of
  `NSURLIsExcludedFromBackupKey`; standard macOS semantics]**. So today, if saves
  land anywhere under that root, **the single most irreplaceable bytes in the
  product are excluded from the user's only backup.** That is a data-loss defect
  the moment Phase 4 ships. Decision D-D7 fixes it.
- `Cache/QuotaManager.swift` **[verified]** — usage is
  `SELECT COALESCE(SUM(size),0) FROM cache_objects`; free space is
  `volumeAvailableCapacityForImportantUsage`; floor outranks quota; *"This type
  never deletes anything."* Because usage is scoped to the `cache_objects` table,
  a separate `save_revisions` table is **automatically** outside the quota — no
  special-casing needed, just don't insert saves into `cache_objects`.
- `Cache/EvictionPlanner.swift` **[verified]** — plans are explicit sets of
  `objectSHAs`; `execute` deletes exactly the plan; manual-only; pinned games
  excluded; unreferenced objects and quarantined partials listed separately and
  never auto-removed.
- `Cache/PinStore.swift` **[verified]** — row presence *is* the pin; pinning also
  biases `DownloadCoordinator` ordering.
- `Sync/Outbox.swift` + `OutboxWorker.swift` **[verified]** — durable SQLite
  outbox, strict **creation-order** drain that stops at the first retry-worthy
  failure, `maxAttempts = 8`, exponential backoff `min(2^n · 5s, 300s)`,
  `quarantined` poison state, `markRejected` reverts the optimistic local row on a
  permanent 4xx. Entry payload type is `CurationIntent` — **curation-specific**.
- `Persistence/Migrations.swift` **[verified]** — additive
  `CREATE TABLE IF NOT EXISTS` migrations; existing tables include
  `cache_objects`, `quota_policy`, `pins`, `outbox_entries`,
  `play_sessions_pending`.

**Roadmap** **[verified]** — Phase 5 SC3: *"restore into a clean environment and
verify database records, exact blobs, **manifests, saves**, and the known-playable
Mac path."* Saves are named **separately from blobs** in the restore drill. That
is a requirement on the *verification surface*, not on the *storage substrate* —
see D-D1.

---

## 1. JTBD framing

**Who / when:** a self-hoster's household player, mid-session and afterwards,
across a Mac that may be offline for days and a server that may be down.

**Job:** *"When I put an hour into a game, I want the outcome of that hour to be
somewhere other than the one machine I played it on, without me thinking about
it, so that a dead SSD, a clean reinstall, or a second device never costs me the
hour."*

**Needed to do it:** nothing. The user's contribution to this job is playing.

**What they get back:** a promise with a visible truth value — "this hour is
backed up" / "this hour exists only here" — and a guarantee, stated in words the
product can keep, that **Playstead has never deleted a save revision.**

**Domain nouns:** `Save` (the per-game persistent-save identity — the lineage
root), `SaveRevision` (one immutable captured state of it), `SaveBlob` (the
bytes), `SaveLineage` (area B's parent chain). **Verbs:** capture, retain,
upload, adopt, restore, export. **Events:** `revision_captured`,
`revision_uploaded`, `revision_restored`, `capture_blocked_no_space`.

**Consumer-shaped rule:** the user surface must never say "digest", "blob",
"CAS", "cursor", or "parent pointer". It says *"safe on the server"*, *"only on
this Mac"*, *"3 saved moments today"*. The one leak I permit is the SHA-256 in
the **export** manifest — PORT-01 forces a verifiable hash into user-visible
artifacts, and that is a fundamental constraint (area H owns the shape).

---

## 2. Prior art (researched, with the footgun each one hands us)

| System | Got right — copy this | Documented footgun — avoid |
|---|---|---|
| **git object store + `gc`/reflog** | Content-addressed immutable objects; dedupe is a side effect of addressing, not a feature. Deletion is *only* reachable via unreachability + a 90-day reflog grace, and `gc` is famously conservative. | `gc --prune=now` plus a detached HEAD loses work permanently. Lesson: **any GC whose safety depends on a correct reachability walk will eventually have a bug in the walk.** The safest GC is the one that does not exist. |
| **restic / borg `forget --prune`** | Snapshot policies are declarative and *named* (`--keep-last/daily/weekly`), and `forget` without `--prune` is a metadata-only, reversible dry run. `--dry-run` is the default habit. | borg users have lost archives to a mis-typed `--keep-within`; restic's docs warn that policies interact non-obviously. Lesson: **if we ever prune, the policy must be previewable as an explicit named plan** — which is exactly `EvictionPlanner`'s existing shape. |
| **Ludusavi** `--full-limit` (1–255) / `--differential-limit` per full backup ([docs](https://github.com/mtkennerly/ludusavi/blob/master/docs/help/backup-retention.md)) | The nearest analogue in our own domain proves a bounded rotation is *acceptable* to emulation users, and that "full + differential" beats "N independent copies" for 32 KB-class data. | Its default full-limit is small; users who wanted a save from months ago find it rotated out. Lesson: bounded rotation is a *storage* answer, not a *treasuring* answer — and SEED-001 wants treasuring. |
| **Nintendo Switch Online** — cloud saves deleted 180 days after a lapsed subscription ([Kotaku](https://kotaku.com/cloud-saves-will-last-six-months-after-a-switch-online-1829314409), [Forbes](https://www.forbes.com/sites/erikkain/2018/09/15/nintendo-will-delete-your-cloud-saves-when-your-online-subscription-ends/)) | Nothing. | The canonical anti-pattern: a **time-based deletion of irreplaceable progress**, described in the press as "draconian" and "kidnapping your cloud saves"; GBAtemp threads show users discovering it only after the loss ([thread](https://gbatemp.net/threads/found-out-the-hard-way-nintendo-only-keeps-cloud-saves-180-days-if-you-cancel-online-membership.681819/)). Xbox, which keeps them indefinitely, took zero reputational damage. **Time-based save deletion is off the table.** |
| **Steam Cloud** — per-AppID per-user quota set by the developer; over-quota files are "logged and removed from the cloud", and the user must launch the game and delete saves in-game to recover ([Steam discussion](https://steamcommunity.com/discussions/forum/0/546740620659541288/)) | Per-scope quotas make one bad actor unable to exhaust shared storage. | The failure mode is *silent server-side removal* plus a remedy that requires launching the very game that is broken. **A quota whose enforcement mechanism is deletion is a data-loss mechanism.** Ours must be *refusal*, never removal. |
| **Dropbox / Google Drive version history** — 30 days (Basic/Plus), 180/365 on business tiers ([Dropbox help](https://help.dropbox.com/delete-restore/version-history-overview)); Drive keeps non-Google files "30 days or 100 versions, whichever comes first", with a manual per-version **"Keep forever"** capped at 200 | The **"Keep forever" pin** is the right primitive: a user-declared exemption from any automatic policy. | It requires the user to *remember to press it before the deadline*. Retention that depends on user foresight fails the people it was for. If we ever add pruning, the pin must be **opt-out of pruning**, not opt-in to keeping. |
| **1Password item history** | Unbounded per-item history on a tiny payload; nobody has ever complained about its storage cost. Direct precedent that **keep-everything on small records is a shipped, boring, correct answer.** | None material at our scale. |
| **Time Machine local snapshots** | Thinning is *pressure-triggered and explicitly bounded* (24h / free-space-driven), and it thins a *cache of a backup*, never the backup. | Users conflate local snapshots with backups. Lesson: **never let a reclaimable tier and a durable tier look the same in the UI** — the exact reason saves and cache objects must be different directories with different exclusion flags. |
| **Litestream / WAL retention** | Retention is expressed against a *restorable point*, not against file count; it will not prune below what a restore needs. | Misconfigured retention has silently made restores impossible. Lesson: retention must be defined by *what remains restorable*, and area B's lineage is what defines that. |
| **iCloud storage-full** | Honest, persistent, actionable prompt naming the shortfall. | It degrades to a nagging banner people learn to dismiss; and Photos-full stops *new* backups silently for some users. Lesson: the disk-full save failure must be **loud once, then persistent-but-quiet, and must never be a modal over a running game.** |
| **Obsidian Sync version history** (1-year retention, per-vault storage cap) | Explicit, documented, purchasable limit. | Version expiry surprises users who treated it as a backup. Same lesson as Dropbox. |

**Revalidation note:** every third-party retention figure above is a mutable
vendor policy. Cite it as "as of 2026-09" in any doc that ships.

---

## 3. Options considered

### 3a. Server-side siting

| Option | Sketch | Pros | Cons | Failure modes | Reversibility | Effort |
|---|---|---|---|---|---|---|
| **A1. Reuse `Playstead.Blobs` CAS** (chosen) | `save_revisions.blob_id → blobs.id`; upload path streams through `Blobs.put_stream/3` or `adopt_temp_file/2` | Dedupe free and automatic (identical SRAM ⇒ one object); one backup/export/verify/quarantine surface for Phase 5; proven fsync+verify+atomic-rename; `Store` seam already S3-ready; zero new storage code | Save bytes share a digest namespace and a volume with game bytes; a *future* blob GC must learn about a new referencing table; the free-space guard is tuned for GB-scale writes (D-D6) | A future GC with a bad reachability walk deletes a referenced save | Costly to undo (migration + byte move) | Low |
| **A2. Separate `saves/` store** | second `Store` impl or a second root | Physical isolation; independent retention/quota; can be on a different volume | Reimplements commit/verify/atomicity/quarantine; **doubles** what Phase 5 must back up and verify; loses cross-user and cross-revision dedupe; two things to get right instead of one | Backup config drifts and covers `objects/` but not `saves/` — the classic split-backup loss | Cheap to undo *into* A1 | Medium-high |
| **A3. Bytes in Postgres (`bytea`)** | 32 KB inline column | Transactional with the metadata; `pg_dump` covers it; trivially small | Breaks the one-storage-seam architecture; makes the DB dump the sole custody of the largest-value artifact; forecloses SEED-002's larger cartridge dumps and any future save-state (SEED-019) at MB scale | DB bloat and vacuum pressure; a `pg_dump` that is now load-bearing for game progress | Costly | Low |

**Chosen: A1.** The asymmetry in the brief decides it. Game blobs are
reconstructable from the user's own media; save bytes are not. The correct
response to "these bytes are irreplaceable" is **to put them in the store with
the strongest existing durability guarantees**, not in a new store that has to
re-earn them. And the "mixing mutable-progress artifacts with immutable game
bytes" worry evaporates on inspection: a committed save revision **is** immutable
game-bytes-shaped. A revision is never edited; a new capture is a new object.
The CAS's actual semantic contract is "immutable, never deleted, verified by
digest" — which describes a save revision more perfectly than it describes a ROM.

Two sub-questions the brief asked explicitly:

- *Does a save blob and a game blob sharing a digest namespace ever surprise?*
  **No, and it cannot.** Sharing a digest means the bytes are byte-identical.
  `blobs` deliberately has no `user_id` **[verified]**, so cross-user sharing is
  already the design. If some 32 KB homebrew ROM ever hashes equal to some SRAM,
  they *are* the same 32 KB and one object is correct. The only real hazard would
  be *semantics stored on the blob* — and `blobs` carries only bytes-level facts
  plus `scan_state`. **Rule (D-D3): the `save_revisions` row carries 100% of the
  save semantics; `blobs` learns nothing about saves.** That is P2 D-12's
  "adapters stay free of format knowledge" applied one layer up.
- *Does refcounting/GC differ?* Today there is no refcount and no GC **[verified]**
  — so no. The forward risk is real and I am pinning it: **D-D4.**

### 3b. Server-side retention

| Option | Pros | Cons | Reversibility |
|---|---|---|---|
| **B1. Keep every revision forever** (chosen) | Zero deletion code ⇒ zero deletion bugs; SEED-001's treasuring stays possible; matches 1Password's shipped precedent; the promise "Playstead has never deleted a save" is checkable in code by `grep`; Phase 5's restore drill has a fixed, total target | Unbounded row count; an SRE will ask about it | Cheap to add policy later |
| **B2. Keep-all + operator-initiated compaction (deferred, unbuilt)** | Answers the SRE | Nothing needs it yet; premature policy is how Nintendo happened | — |
| **B3. Bounded rotation (Ludusavi-style N)** | Bounded storage | Silently destroys the thing the phase exists to protect; violates the constitution | One-way (data gone) |

**Chosen: B1, with the arithmetic stated rather than hand-waved.** 32 KiB ×
capture cadence. With area A's dedupe-at-capture (below), a *heavily* played game
produces on the order of 100 distinct revisions a year ≈ **3.2 MB/game/year**. A
500-game library where every game is played hard: **1.6 GB/year** — against a
blob store already holding tens of GB of ROMs, on a self-hosted box. And that is
the pathological case; the realistic one is two orders of magnitude smaller.
**The storage argument for pruning does not exist at this scale.** Adding
deletion code to save a rounding error, in a product whose #1 priority is data
safety, is a bad trade in every direction.

**Does P3 D-21's "no silent deletion, ever" extend to saves? Yes, and strictly
more so.** D-21's rule protects *reconstructable* cache bytes. Saves are not
reconstructable from anywhere. The rule that protects the cheap thing must
a fortiori protect the priceless thing. I go one step further than D-21:
**for saves there is no non-silent deletion either, in v1.** D-21 permits
user-confirmed manual reclaim of game bytes; Phase 4 ships **no save deletion UI
at all**. If a user genuinely wants a revision gone, that is a future,
consciously designed, confirm-by-typing feature (area G's territory, and out of
scope). Shipping no delete button is the strongest possible v1 statement.

**The retention invariant, stated so a test can assert it** (D-D5):

> No row is ever removed from `save_revisions`, and no `blobs` row referenced by
> a `save_revisions` row is ever removed or mutated except for `scan_state`.
> There is no application code path — worker, job, migration, LiveView action,
> or API endpoint — that issues a `DELETE` against `save_revisions`.

**Phase 5 hand-off:** total, append-only, digest-verifiable. `Blobs.stream/2`
plus the `save_revisions` table is a complete backup unit; the restore drill
asserts "every `save_revisions` row resolves to a present blob whose re-hash
equals its `sha256`". Append-only is the easiest thing in the world to back up
incrementally — B1 makes Phase 5 *easier*, not harder.

### 3c. Dedupe of no-op captures

The spike measured a ~24 s mmap flush cadence with no on-demand flush **[verified,
brief]**. Area A's policy will therefore capture on a timer and/or on exit, and
most captures during idle, menuing, or pausing will be **byte-identical**.

| Option | What the timeline shows after an idle hour | Verdict |
|---|---|---|
| **C1. No revision at all when the digest equals the head's digest** (chosen) | nothing new | Honest — nothing happened |
| **C2. New revision row pointing at the same blob** | 150 identical entries | Dishonest by volume; buries the real moments |
| **C3. Revision row + `capture_count`/`last_seen_at` on the head** (chosen, as the addendum to C1) | one entry, "last confirmed 14:32" | Honest *and* quiet |

**Chosen: C1 + C3.** An unchanged capture creates **no new revision**; instead it
bumps the head revision's `last_confirmed_at` (and `confirm_count`). Lineage is
untouched — area B's parent chain only ever gains a link when the bytes actually
change, which is exactly what a lineage means.

**The honesty argument, taken seriously.** The brief asks: if a user plays an
hour and sees three entries, is that a lie or a mercy? It is **neither — it is
the truth, stated at the right granularity.** The claim a timeline entry makes is
*"the game's persisted state was **this** at **this** time"*. During an idle hour
the persisted state genuinely did not change; 150 identical entries would assert
150 distinct facts where one fact exists. That is the *dishonest* option, and it
is dishonest in the way EXPERIENCE-ETHOS specifically warns about: noise that
looks like information. The constitution's honesty constraint is *"never silently
discard save conflicts"* and *"preserve exact bytes"* — C1 discards **no bytes and
no state**, because the byte-identical capture *is* the retained head. Nothing is
lost, so nothing is concealed. `last_confirmed_at` is the mercy that makes it
also *complete*: the user can see the save was checked at 15:31 even though it
last changed at 14:32, which pre-empts the only real worry ("is it still
working?"). Quiet-by-default and honest coincide here; they are not in tension.

Where dedupe must **not** apply (D-D8): a byte-identical capture from a
**different device** or across a **different lineage branch** is not a no-op —
it is convergence evidence area B needs. Dedupe is keyed on
`(save_id, device_id, sha256 == head.sha256)`. A different device's identical
capture records a revision (pointing at the same blob, so zero extra bytes).

### 3d. Client-side siting and the Time Machine question

| Option | Pros | Cons |
|---|---|---|
| **D1. Inside the existing CAS under the TM-excluded root** | zero new plumbing | **Excludes irreplaceable local-only saves from the user's only backup.** Disqualifying. |
| **D2. Separate `saves/` tree, still under the excluded root** | separates concerns | Same exclusion defect — exclusion is inherited by the subtree |
| **D3. Separate `saves/` tree + move the exclusion off `root` onto the reclaimable subdirectories** (chosen) | Saves *and* the SQLite DB become backed up; cache stays out of the backup budget; automatically outside `QuotaManager` (which sums `cache_objects` only) | One `AppPaths` change; a Migration; a snapshot test |

**Chosen: D3.** Concretely, in `AppPaths`:

- `~/Library/Application Support/Playstead/` (**root**) — **NOT excluded**
  (this is the change; `excludeRootFromBackup` is deleted).
- `root/objects/`, `root/partials/`, `root/launch/`, `root/emulators/`,
  `root/bios/` — **each individually `isExcludedFromBackup = true`**. Cache
  objects and emulator binaries are re-downloadable; `launch/` is clonefile-
  materialized scratch; `partials/` is unverified.
  *Note:* `bios/` is user-supplied and **not** re-downloadable by design (P3 D-09
  ships no acquisition path). I still exclude it — but flag it as a deliberate,
  logged judgement call, and recommend the operator-facing note. **[inference]**
- `root/saves/` — **backed up**, sha256-CAS-shaped
  (`saves/objects/<aa>/<bb>/<sha>`), mirroring `CASManager`'s layout so
  `PathSafety.validatedDigest` and the commit discipline are reused verbatim.
- `root/playstead.sqlite3` — **backed up** (the metadata without which the save
  objects are anonymous blobs). Requires SQLite WAL discipline for a coherent
  TM copy; recommend the DB stay in WAL with periodic `wal_checkpoint(TRUNCATE)`
  **[inference]**.

**Why not just leave the root backed up entirely?** Because a 25 GB ROM cache
inside Time Machine is a real cost the D-20 rationale correctly identified. Both
concerns are satisfiable at once — the exclusion just has to be applied at the
*right* granularity. The current code applied it at the wrong one because, in
Phase 3, everything under the root genuinely was reconstructable. Phase 4 changes
that premise, and the exclusion must move with it.

**Migration hazard [inference]:** existing installs already have the exclusion
flag set on `root`. Clearing it requires an explicit `isExcludedFromBackup =
false` write on `root` at launch, because the flag is a persisted xattr and
simply not setting it is not the same as clearing it. This must be idempotent and
run before the first save is ever written.

---

## 4. Decisions

> `D-xx` numbers are placeholders for synthesis renumbering.

**D-D1 — Save revision bytes live in the existing server CAS via
`Playstead.Blobs`.** *Rationale:* irreplaceable bytes belong in the store with
the strongest proven durability, dedupe, and one Phase-5 backup surface; a save
revision is immutable-by-construction, which is what the CAS's contract actually
guarantees. *Reversibility:* costly (migration + byte move), but the `Store` seam
means the substrate can still change under it.

**D-D2 — A new `Playstead.Saves` bounded context owns the domain; it is the only
non-Blobs caller of `Playstead.Blobs`, and it never touches `Blobs.Store`.**
Schemas: `Playstead.Saves.Save` (per `(user_id, asset_set_id, save_kind)`
lineage root) and `Playstead.Saves.Revision`. Every schema carries `user_id`;
every public function takes the scope first (P1 D-01). The commit is one
`Ecto.Multi`: `put/adopt blob → insert revision → insert journal entry (kind:
"save") → idempotency receipt`. *Rationale:* saves are a distinct ubiquitous
language (capture/retain/restore/resolve) from catalogue or curation, and the
transactional boundary is the context's job. *Reversibility:* cheap pre-ship.

**D-D3 — The saves context knows nothing about CAS on-disk layout, and `blobs`
learns nothing about saves.** No new column on `blobs`; no path construction
outside `Blobs.Store.LocalDisk`. *Rationale:* P2 D-12's rule, applied
symmetrically — it is what makes the shared store safe rather than a coupling.
*Reversibility:* cheap.

**D-D4 — Any future blob garbage collection is now a gated decision, recorded
here: a GC may not ship without enumerating every referencing table
(`import_source_files`, `catalogue_asset_members`, **`save_revisions`**) and
proving, by test, that a save-referenced blob survives a full sweep.** Add a
`@moduledoc` line to `Blobs.Store` and a test named
`blobs_never_deleted_test.exs` asserting no production code path deletes under
`objects/`. *Rationale:* the one way A1 loses is a future GC with a bad
reachability walk (git's lesson); make that impossible to do accidentally.
*Reversibility:* n/a (a guard).

**D-D5 — Keep every save revision forever. No pruning, no compaction, no TTL, no
delete endpoint, no delete UI in v1.** The invariant in §3b is asserted by a
named test. *Rationale:* the storage saved is ~1.6 GB/year in the pathological
case; the risk removed is the entire class of "we deleted the thing we existed to
protect"; Nintendo's 180-day policy is the documented counter-example.
*Reversibility:* cheap to add a policy later; impossible to undo a deletion.

**D-D6 — Save-revision writes bypass the 1 GiB/5% free-space *margin*, never the
physical space check.** Add `@callback open_write(byte_size_hint, opts)` to
`Playstead.Blobs.Store` with `reserve: :critical`; `LocalDisk` then requires only
`available >= requested + 64 MiB` (a hard floor that keeps Postgres alive) instead
of `requested + max(1 GiB, 5% capacity)`. `Playstead.Saves` is the only caller
that passes it. *Rationale:* **[verified defect]** — today a 32 KB irreplaceable
save is refused by a guard sized for GB-scale ROM imports whenever the volume
drops under ~1 GiB free. Priority #1 (data safety) outranks the import path's
comfort margin. *Reversibility:* cheap (additive callback, one impl).

**D-D7 — Move the Time Machine exclusion off the App Support root onto
`objects/`, `partials/`, `launch/`, `emulators/`, `bios/`; put save revisions in
a backed-up `saves/` CAS; leave `playstead.sqlite3` backed up.** Include an
idempotent launch-time `isExcludedFromBackup = false` on the root to undo the
Phase 3 flag on existing installs. *Rationale:* excluding reconstructable cache
was right; inheriting that exclusion onto irreplaceable local-only saves is a
data-loss defect. *Reversibility:* cheap.

**D-D8 — A capture whose digest equals the current head's digest **for the same
save and the same device** creates no revision; it bumps
`revisions.last_confirmed_at` and `confirm_count` on the head. A byte-identical
capture from a *different device* or a different lineage branch **does** create a
revision (sharing the blob, costing zero bytes).** *Rationale:* the timeline
asserts "state changed to X at T"; repeating an unchanged fact 150 times is the
dishonest option, and nothing is discarded. *Reversibility:* cheap (the collapsed
captures carried no unique bytes, so nothing is unrecoverable — but the *count*
of collapsed captures is lost unless `confirm_count` records it, which is why it
is in the decision).

**D-D9 — Save revisions do not count against the P3 D-21 quota and are exempt
from the free-space floor's *blocking* behaviour, but are subject to their own
hard reserve.** Concretely: saves are stored in `save_revisions`, never in
`cache_objects`, so `QuotaManager`'s `SUM(size) FROM cache_objects` excludes them
**with no code change** **[verified]**. Additionally, `QuotaManager` gains a
`saveReserveBytes = 256 MiB` that is **subtracted from the space available to
downloads**: game-byte downloads block 256 MiB earlier than they otherwise would,
so a full cache can never be the reason a save cannot be written. *Rationale:*
priority #2 (reliable save continuity) beats priority #4 (resource efficiency);
256 MiB is ~8,000 revisions of headroom and an invisible cost against a 25 GB
quota. *Reversibility:* cheap (a constant).

**D-D10 — Saves have absolute priority at reclaim time and are never evictable.**
`EvictionPlanner` never enumerates a save object as a candidate, an unreferenced
object, or a quarantined partial (it operates over `cache_objects` and
`paths.objects`/`paths.partials`, all of which exclude `saves/` by construction
under D-D7 **[verified by inspection of the candidate queries]**). **Evicting a
game leaves its saves untouched** — an evicted game is a game you may reinstall
tomorrow, and its progress is precisely the part you cannot re-download.
**Pinning a game does not need to pin its saves**, because saves are already
unconditionally retained; "never evictable" is simply their permanent property,
not a user-visible state. *Rationale:* one fewer concept in a UI that already has
exactly one status slot. *Reversibility:* cheap.

**D-D11 — Disk-full at capture time is a first-class, named, loud-once failure —
never a silent drop.** Sequence: (1) the capture is attempted into `saves/`;
(2) on `ENOSPC`, the app **does not** touch the emulator, **does not** modal over
a running game, and **does not** delete anything; (3) it writes a durable
`save_capture_blocked` row (SQLite, tens of bytes — it fits when 32 KB does not);
(4) it raises **one** user-visible alert, worded with the shortfall and the two
real remedies ("Reclaim game files" → the existing `ReclaimPromptView`; "Free
space in Finder"), and thereafter shows a persistent non-modal attention state
on the game (area E's ladder — flagged below); (5) it **retries every capture
cycle**, and the first success clears the state; (6) if the server is reachable,
it attempts a **direct streaming upload without local staging** as the escape
hatch, since 32 KB in flight needs no disk. Copy (area E owns final wording):
*"Your progress in **Metroid Fusion** couldn't be saved to this Mac — the disk is
full. The game is still running; free up space and it will save automatically.
Nothing has been deleted."* *Rationale:* this is the worst case in the phase and
it deserves a specific answer; iCloud's nag-banner and Steam's delete-to-recover
are both worse. *Reversibility:* cheap.

**D-D12 — Save uploads use a dedicated, save-only outbox lane that is drained
ahead of the curation outbox and ahead of the download queue, with its own
backoff and no quarantine-to-silence.** The existing `Outbox` is
`CurationIntent`-typed and strictly creation-ordered with head-of-line blocking
**[verified]** — a stuck favourite would otherwise block an irreplaceable save
behind it. So: a new `save_uploads` table + `SaveUploadWorker`, same durable
patterns (idempotency key, UUIDv7 natural key, exponential backoff), but
(a) drained first, (b) `DownloadCoordinator` yields its concurrency slot to a
pending save upload, (c) **no `quarantined` terminal state that stops retrying**
— after `maxAttempts` the entry keeps retrying at the 300 s cap forever and the
save is surfaced as needing attention. A save that stops trying is a save that
gets lost. *Rationale:* the local-only window is the most dangerous state in the
product; a 32 KB upload cannot meaningfully compete with a download for
bandwidth, so jumping the queue costs nothing. *Reversibility:* cheap.

**D-D13 — "Local-only" stops being quiet after one successful contact with the
server fails to clear it, or after 24 hours, whichever comes first.** Below that
threshold, local-only is normal and silent (offline play is a feature, not a
fault). Above it, the game carries a persistent, non-modal attention state and
the sidebar shows a count. It is **never** an alert or a notification.
*Rationale:* EXPERIENCE-ETHOS quiet-by-default, bounded by the honest fact that a
day-old unbacked-up save is a real risk the user should get to know about. Area E
owns the pixels; this is the policy. *Reversibility:* cheap (a constant).

**D-D14 — Server-side abuse limits, reusing existing patterns, each with a
registered problem code.**
- **Size cap:** `save_revision_too_large` (413) at **8 MiB**, enforced by
  `Content-Length` *and* by a streaming byte counter that aborts the write (never
  trusting the declared length). 8 MiB is ~256× the pinned 32 KB GBA SRAM, and
  leaves room for future SNES/DS-class saves and SEED-002 cartridge dumps without
  ever admitting a 4 GB "save".
- **Per-device concurrency:** reuse `Playstead.Import.UploadSlots` with a
  **separate key namespace** (`"save:" <> device_id`) so a save upload is never
  blocked by two in-flight ROM imports, and vice versa → `too_many_uploads` (429).
- **Rate limit:** `PlaysteadWeb.Plugs.Throttle`-shaped Hammer window, per-device,
  **120 revisions/hour** (≈4× the theoretical 24 s cadence ceiling, so honest
  clients never trip it) → `rate_limited` (429) with `Retry-After`.
- **Per-user cap:** a `curation_limit_exceeded`-shaped guard — `save_limit_exceeded`
  (422) at **100,000 revisions/user** and **20 GiB of save bytes/user**. These are
  DoS backstops, not retention policy; crossing one is an operator-visible
  attention item, never a deletion trigger.
- **Untrusted bytes:** save uploads are opaque; no format parsing, no
  decompression, no filename from the client used as a path component. The digest
  is verified server-side by re-hash (`commit/2` already does this) **[verified]**.
- **Logs:** device id and digest only; never ROM identity, never save bytes.
*Rationale:* a paired device is an untrusted client writing to the operator's
disk; reuse beats invention. *Reversibility:* cheap (constants + registry rows).

**D-D15 — The `save_revisions` schema fields that carry retention and
provenance** (area B owns lineage semantics; these are D's storage/retention
requirements on the row):
`id` (client UUIDv7), `user_id`, `save_id`, `blob_id`, `sha256`, `size_bytes`,
`parent_revision_id`, `origin_device_id`, `captured_at`, `last_confirmed_at`,
`confirm_count`, `save_kind` (**`"battery"`** in v1 — the SEED-019 seam),
`origin_method` (**`"emulator_flush"`** in v1 — the SEED-002 seam),
`adapter_id` + `adapter_version` (the pinned mGBA 0.10.5), `retention_class`
(**`"permanent"`** — the only value in v1), `user_label` (nullable, unused in v1
— the SEED-001 seam), `evidence` (jsonb, additive provenance).

---

## 5. Adversarial pass on my own recommendation

**"You put mutable user progress in a store whose entire design rationale was
immutable game bytes; when Phase 5 writes a scrub/health job it will treat them
identically and you will find out the hard way."**
Partly fair. Mitigation is D-D4 (GC is a gated decision with a named test) plus
the observation that a committed revision genuinely *is* immutable — the
mutability is in *which revision is head*, which lives in Postgres, not on the
volume. **Residual risk: accepted, guarded by test.**

**"'Never delete' is not a policy, it is the absence of one. In five years an
operator with a 40-year-old NAS will beg you for a prune, and you will design it
under pressure."**
Fair, and I accept it deliberately. Designing pruning under pressure with real
data and real complaints beats designing it now with none. D-D14's per-user caps
give the operator a *ceiling* that surfaces the problem long before it is an
emergency, without deleting anything. **Residual risk: accepted.**

**"D-D8's dedupe means a corrupted-but-identical-length capture that happens to
match the head is invisible."**
Not a real hazard — matching the head's SHA-256 means the bytes are the head's
bytes. A *different* corruption produces a different digest and therefore a real
revision, which is the honest outcome (area C's compatibility gate, not D's).
**Not a risk.**

**"Turning off the Time Machine exclusion on the root re-exposes the SQLite DB to
TM's non-atomic file copy, and you will restore a torn database."**
Genuine. Mitigation: WAL mode + periodic `wal_checkpoint(TRUNCATE)`, and the DB is
*not* the custody of the save bytes — the `saves/` CAS objects are self-describing
by digest and re-indexable. **Residual risk: a torn DB restore loses the
*index*, not the *bytes*; a rebuild-from-`saves/objects` path should be a Phase 5
concern.** Flagged, not built.

**"D-D9's 256 MiB reserve is a magic number and a user who set a 25 GB quota now
gets 24.75 GB."**
True and correct. It is disclosed in the Storage view's arithmetic (area E), not
hidden. A user who would rather have the 256 MiB back is asking to trade their
saves for a quarter-gig, which the product declines to offer.

**"D-D12's never-quarantine loop is a battery-draining infinite retry against a
permanently rejecting server."**
Bounded by the 300 s cap (12 attempts/hour, 32 KB each — negligible). A
**permanent 4xx** (e.g. `capability_incompatible`) is genuinely terminal and does
stop retrying — but it moves to a loud, named attention state, never to silence.
That distinction is the fix; **residual risk: none material.**

**"You said no delete UI, but a user who imported a save by mistake now has an
undeletable wrong revision forever."**
True. It is a non-head revision in a lineage; it is invisible in the default
surface and costs 32 KB. Living with a stray row is strictly better than shipping
a delete path in the phase whose purpose is not losing things. **Accepted.**

---

## 6. Coherence notes and collision flags

- **Area A (capture trigger)** — I assume A produces `(bytes, digest,
  captured_at, device_id)` and calls the saves context, and that A's cadence is
  timer-based such that D-D8's dedupe is what keeps the revision count sane.
  **If A decides to capture only on genuine change (via FSEvents + its own
  digest compare), D-D8 becomes a cheap belt-and-braces double-check rather than
  the primary filter — still keep it.** I also assume A's exit-path capture uses
  the same commit path, so D-D11's disk-full handling covers it.
- **Area B (lineage)** — **Collision to resolve loudly:** D-D8 says an unchanged
  capture creates no lineage node. If B's model needs a node per capture for
  causality (e.g. a vector clock tick), we disagree and B wins on mechanism — but
  then B must supply the *display* rule that collapses them, because 150 identical
  timeline entries is not shippable. My preference is strongly D-D8. I also assume
  `parent_revision_id` is B's field; I only require it exist and never be nulled.
- **Area C (restore gate)** — I assume C reads `adapter_id`/`adapter_version`/
  `save_kind`/`size_bytes` off the revision row (D-D15) and needs no additional
  retention guarantee beyond "the revision still exists", which D-D5 gives
  unconditionally. C should know that **restoring never deletes** — it creates a
  new revision whose parent is the restored one.
- **Area E (surfacing)** — **Two collisions.** (1) D-D10 removes the need for a
  "save pinned"/"save evictable" vocabulary entirely — E's ladder should have no
  such rung. (2) D-D11's disk-full state and D-D13's aged-local-only state both
  need a rung on the one-status-slot ladder, and disk-full must rank at or above
  `attention`. E owns the ladder; I am claiming two states and no more.
- **Area F (launch preflight)** — D-D11's blocked-capture state is a *warning*,
  never a launch blocker: a user with a full disk must still be able to play,
  informed. Also: preflight must make zero network calls (CACH-04), and D-D12's
  upload lane must therefore never be on the launch path.
- **Area G (conflict resolution)** — D-D5 means resolution can never be
  implemented as "delete the loser". Resolution is a *new revision* with two
  parents, or a head pointer move. G should assume both siblings survive forever
  and design the UI around that freedom rather than around a cleanup step.
- **Area H (export)** — H can rely on: every revision has a stable `sha256`, a
  `captured_at`, an `origin_device_id`, and permanent existence. H must decide
  whether export includes *all* revisions or the head (my input: PORT-01 says
  "persistent-save revisions", plural — export all, in `captured_at` then digest
  order for determinism per P2 D-34/D-35). H should also know the exported bytes
  come from `Blobs.stream/2`, identical to game-byte export.

---

## 7. Forward compatibility

| Seed | The exact field/seam that keeps it open | What I deliberately did not build |
|---|---|---|
| **SEED-001** (curation/treasuring) | **D-D5 is the seed's real enabler — you cannot treasure what you pruned.** Plus `user_label` (nullable, unused), the `evidence` jsonb for provenance (origin device, adapter+version, capture time, ancestry, known-vs-inferred), and `origin_method`. | No naming UI, no tags, no notes, no browse surface. |
| **SEED-002** (cartridge) | `origin_method` (`"emulator_flush"` in v1; `"cartridge_read"` later) and the 8 MiB size cap sized for cartridge-class dumps rather than exactly 32 KB. | No hardware path, no writeback. |
| **SEED-019** (system saves vs save states) | `save_kind` (`"battery"` in v1) as a **first-class column from day one**, and `Saves.Save` keyed on `(user_id, asset_set_id, save_kind)` so a `"state"` lineage is a *sibling* record, never a retrofitted flag on the battery one. `retention_class` lets save states get a *different* retention policy later (states are big and genuinely prunable) without touching battery saves. | Nothing state-related. The vocabulary does not say "save" where it means "battery save". |
| **SEED-010/012** (memory-card archive) | Same `save_kind`/`origin_method` pair, plus the fact that the CAS is byte-agnostic — a memory-card image is just another blob under a new `save_kind`. | No multi-slot decomposition, no card format knowledge anywhere. |

---

## 8. How this is proven (named automated tests, 03.5 D-03)

Server (ExUnit):
1. `saves_retention_invariant_test.exs` — asserts by source scan that no module
   under `lib/` issues a `DELETE` against `save_revisions`, and by behaviour that
   a full application boot + orphan sweep + import + export cycle leaves every
   revision and its blob byte-identical.
2. `blobs_never_deleted_test.exs` (D-D4) — a save-referenced blob survives
   `OrphanSweeper.sweep(0)`; `Store.delete/1` returns `{:error, :refused}` for an
   `objects/` path.
3. `saves_dedupe_test.exs` — same device + same digest ⇒ no new revision,
   `confirm_count` incremented, `last_confirmed_at` advanced; **different device**
   + same digest ⇒ new revision sharing one `blobs` row (asserts
   `Repo.aggregate(Blob, :count) == 1`).
4. `saves_low_disk_write_test.exs` (D-D6) — with a stubbed
   `free_bytes`/`capacity_bytes` putting the volume at 900 MiB free, a ROM import
   is refused with `storage_insufficient` **and** a 32 KB save revision commits
   successfully. This is the regression test for the verified defect.
5. `saves_upload_limits_test.exs` (D-D14) — 8 MiB + 1 byte streamed body aborts
   with `save_revision_too_large` (413) *even when `Content-Length` lies*;
   121st revision in an hour returns `rate_limited` with `Retry-After`; a third
   concurrent save upload returns `too_many_uploads`; a save upload succeeds while
   two ROM imports hold their own slots (namespace separation).
6. `saves_scope_test.exs` — every `Playstead.Saves` public function rejects a
   cross-user `save_id` (P1 D-01).

Mac (XCTest / XCUITest, on the 03.5 macos runner):
7. `AppPathsBackupExclusionTests` (D-D7) — asserts
   `root.resourceValues(.isExcludedFromBackupKey) == false`,
   each of `objects/ partials/ launch/ emulators/ bios/` `== true`,
   `saves/` `== false`, `playstead.sqlite3` `== false`; plus a migration case
   that starts with the flag set on `root` and asserts it is cleared.
8. `SaveQuotaExemptionTests` (D-D9) — with `cache_objects` at exactly the quota,
   a save revision still writes; `QuotaManager.verdict(forAdditional:)` for a game
   download reflects the 256 MiB reserve.
9. `SaveDiskFullCaptureTests` (D-D11) — injected `ENOSPC` on the saves write:
   asserts nothing is deleted, a durable `save_capture_blocked` row exists, the
   alert fires exactly once, the attention state persists, the next cycle retries,
   and a success clears it. Event-driven (`XCTestExpectation`), no fixed sleeps.
10. `SaveEvictionImmunityTests` (D-D10) — `EvictionPlanner.candidates()` and
    `plan(for:)` never contain a save object; executing a plan that evicts a game
    leaves that game's save revisions and bytes present.
11. `SaveUploadPriorityTests` (D-D12) — with a poisoned/quarantined curation
    outbox entry at the head and a download in flight, a newly captured save still
    uploads first; a permanent 4xx moves it to attention rather than silence; a
    transport failure retries forever at the 300 s cap without quarantining.
12. `SaveLocalOnlyAgingTests` (D-D13) — under 24 h with the server unreachable,
    no attention state; past the threshold, the state appears; a successful upload
    clears it.

Checkpoint 7 (real emulator + real bytes) stays blocked; **none of the above
depends on it** — all twelve run against synthetic 32 KB fixtures and injected
filesystem conditions, which is deliberate.

---

## 9. Open questions

Only one I could not resolve without another area:

- **Does area B require a lineage node per capture (against D-D8)?** I have stated
  my position and my fallback (B wins on mechanism, but owes the collapse rule).
  Everything else in this file is a decision, not a menu.
