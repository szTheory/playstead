# Phase 4: Persistent Save Continuity - Context

**Gathered:** 2026-09-03
**Status:** Ready for planning

<domain>
## Phase Boundary

The persistent-save half of the Mac-to-server proof: the Mac captures mGBA's adapter-declared battery-save artifact during and after play, appends it as immutable revisions, queues them locally while the server is unavailable, uploads them through the existing sync spine, shows honestly which revisions exist where, restores a compatible checksummed revision onto a clean paired Mac, keeps both sides when two devices diverge from the same base, and exports every revision into the deterministic folder layout with a readable manifest. Covers SAVE-01, SAVE-02, SAVE-03, SAVE-04, and the saves half of PORT-01 (the game-bytes half shipped in Phase 2).

Also in scope as gap closure, because three shipped defects each block a Phase 4 success criterion on its own terms: the Time Machine exclusion boundary, the free-space reservation that refuses save uploads, and the missing launch mutual exclusion (D-63, D-64, D-65).

Out of this phase: save states (SAVE-05 — v2; battery saves only), save curation/naming/tagging/treasuring (SEED-001), cartridge read/write (SEED-002, SEED-010), save-progress screenshots (SEED-006), save reimport (export is verify-only by roadmap criterion 4), a second client or adapter, browser play, metadata/artwork providers, backup/restore drills and server health (Phase 5).

</domain>

<decisions>
## Implementation Decisions

All decisions below were produced by eight parallel multi-lens research fan-outs (macOS/filesystem durability, distributed systems, Elixir/OTP/Phoenix/Ecto idiom, emulation-domain truth, security, SRE, product/JTBD, UI/UX and creative direction, accessibility, verification engineering, plus an adversarial pass per area), each with online prior-art research and a self-adversarial review, synthesized here into one coherent set. Full option tables, prior-art citations, adversarial passes, and rejected alternatives: `discussion-research/`. Phase 1/2/3/3.5 decisions are cited as `P1 D-xx` … `P3.5 D-xx`.

Seven cross-area collisions were arbitrated at synthesis; each ruling is recorded inline as **[Arbitration]** with the losing position and why.

### Capture and Local Durability

- **D-01:** Capture trigger is a **session-scoped 1 Hz read-and-hash poll** of the adapter-declared artifact — no FSEvents, no kqueue/vnode watch, no `NSFileCoordinator`, no mtime/size heuristics. Polling is the exact instrument that produced this phase's 24 s constraint (the spike's `watch-save.sh` is a 1 Hz `shasum` poller), it costs roughly 20 µs of CPU per second, and it runs only while a game is open. The widely repeated "FSEvents misses mmap writes" claim is documented for inotify/fanotify, **not** for FSEvents — it is unmeasured in either direction, and D-02 measures it rather than inheriting folklore.
- **D-02:** Run **probe SAVE-P1** as an early plan in this phase: inode stability across mGBA's flush, mtime fidelity, FSEvents/vnode event delivery for an mmap writer on APFS, and whether dirty pages land after process death. No outcome changes D-01; the probe converts four inferences into measurements and records them in the pin. The Phase 3 spike's raw artifacts (`save-timeline.jsonl`, `probe-03.json`) are gitignored and gone, so mtime fidelity and inode stability are currently **unproven, not merely unanalysed**.
- **D-03:** Quiescence is **three consecutive identical 1 Hz reads**. Raw SRAM is not self-describing — there is no header, checksum, or length field — so a torn read is undetectable by inspection and only temporal quiescence is available. **Playstead never parses save bytes, ever**, in this phase or later.
- **D-04:** Two capture tiers: one durable rolling **staged** capture per open session (each superseding the last), and exactly **one promoted revision per session**, plus a session-start **baseline** revision marked `origin: external` when the on-disk bytes changed outside a Playstead session. A revision per flush tick would be ~150 rows/hour — a log, not a history.
- **D-05:** The **post-exit settle pass is unconditional** and branches on none of `AdapterExit`'s four cases. `AdapterExit.clean` is a signal classification, not a durability guarantee, and dirty `MAP_SHARED` pages can land after process death, so a post-exit read can genuinely find bytes no pre-exit read saw. **Nothing in Phase 4 may branch capture behaviour on exit status.**
- **D-06:** Write order is **bytes before references**: read the whole artifact into one buffer, hash it once, write to a temp file, `fsync`, `rename`, `fsync` the directory, and only then insert the SQLite row. A `kill -9` of Playstead leaves at worst a collectable orphan blob, never a dangling reference and never a lost promoted revision. `StreamingSHA256` is reserved for a future large or multi-file artifact; a 32 KB artifact gets one buffer, one digest, one stored object.
- **D-07:** `SaveSessionRecovery` replays the identical settle pass over any session left open at app launch, idempotent by digest, silent when nothing is new. This is the crash-recovery path for "Playstead died between emulator exit and capture".
- **D-08:** The capture unit is an **artifact set** — a sorted, timestamp-free `(path, size, sha256)` manifest — with one entry for mGBA. This is the only abstraction built ahead of need, and it exists so that a directory-shaped or multi-file save (memory cards, `.srm` + `.rtc`) slots in without a schema migration. **[Arbitration]** The *stored blob digest is the raw artifact sha256*, not the manifest digest: dedupe (D-30), export filenames (D-58), and the compatibility gate (D-19) all key off the raw digest, and a manifest digest over a single entry would have made those three subsystems disagree with what a user sees in `sha256sum`. The manifest digest is recorded alongside for the multi-artifact future. — **Reversibility:** one-way — the artifact-set shape and the digest choice both enter the published `save` journal payload.

### Revision Model and Divergence

- **D-09:** Lineage is a **parent-pointer immutable revision DAG** per save line. Because a 32 KB battery save is opaque and unmergeable, the DAG never merges — it exists for causality and provenance, which is exactly what SAVE-04 asks for. It costs one nullable column. Vector clocks were rejected (per-device GC state, and they cannot express restore-then-play); CRDTs were rejected (for an opaque register they degrade to either LWW, which is forbidden, or an MV-register, which is siblings bought with more machinery and less history).
- **D-10:** Save-line identity is **`(user_id, content_key, save_kind, slot)`** where `content_key` is the **ROM sha256**, not `asset_set_id` — a re-import would otherwise orphan every save on that game. `save_kind` (`"battery"` only in v1) and `slot` (`"0"`) ship **day one**: both are unrecoverable if omitted from a published payload, and `save_kind` is SEED-019's discriminator arriving before it is needed rather than after.
- **D-11:** Base is `parent_revision_id`; NULL means root. A second root on a line that already has a head is a genuine divergence, not an error. Restore-then-play parents on the restored revision even though that device never observed its ancestors — **lineage records where bytes came from, not what a device observed.**
- **D-12:** Also record `base_sha256` and a derived `base_matched` boolean. A mismatch is **recorded, never rejected** — it catches save-editor edits and torn reads without inventing a filesystem workaround.
- **D-13:** The server **accepts and branches**; it does **not** 409-reject a non-fast-forward. Rejecting would leave the losing side's only durable copy sitting on a client, which inverts constitutional priority #1, and it degrades worse under capability skew. The parent pointer is what keeps the client honest, not the rejection. The only rejection is `409 save_parent_unknown` with `Retry-After` for pure client outbox mis-ordering (unreachable cross-device), plus loud caps `save_branch_limit_exceeded` (32 branches) and `save_revision_immutable`.
- **D-14:** **No automatic winner, ever.** This is an explicit rejection of CouchDB's deterministic-winner rule, which is the single most complained-about property of that model. Branch heads are derived as revisions with no children.
- **D-15:** Server `recorded_at` is the **only orderable time**. Device-claimed times are stored as evidence — `device_captured_at`, `device_reported_now`, `device_clock_offset_ms` (which separates clock error from queue delay), `device_monotonic_ms` — and are displayed with a caveat when they contradict arrival order (D-52). **UUIDv7 ids embed an untrusted clock and must never be sorted on.**
- **D-16:** Two endpoints, and the split is **forced, not stylistic**: `Idempotency.fingerprint/1` canonicalizes a *parsed body* and cannot fingerprint a stream. So `PUT /api/v1/saves/uploads/:command_id` (streamed, `Repr-Digest` + `Content-Length`, TTL'd pending blob, size cap) then `POST /api/v1/saves/revisions` (the idempotent metadata commit).
- **D-17:** `Playstead.Sync.SavePayload` with `@frozen_keys` and an inner `type`, following P3 D-08's `curation` template exactly, **plus a mandatory `save:` branch in `Snapshot.read/1`**. Lineage lives in its own tables, **not** in the journal: `Compaction.run/0` deletes journal rows at 90 days, so journal-only lineage would have a 90-day event horizon. Provenance carried from day one: origin device, `capture_method`, adapter id + version, `save_format`, `format_confidence`, `blob_sha256`, `size_bytes`, and a nullable `play_session_id` (the only play-context denormalization). Naming, tags, and conversion history are deliberately deferred as future additive fields (SEED-001). — **Reversibility:** one-way — journal payloads and entity kinds are published client protocol; additive only, never renamed.

### Restore Compatibility

- **D-18:** The binding tuple is `{system_id, save_kind, medium_id, artifact_bytes, rom_sha256, title_identity, origin}`, with emulator/core/version recorded as **provenance only, never gating**. A GBA battery save is written by the *game*, not the emulator; gating on emulator version is save-*state* thinking misapplied to a system save, and SEED-019 names exactly that confusion as the thing to avoid.
- **D-19:** Three tiers, not a boolean: **`exact` / `same_title` / `incompatible`**. Byte-exact-only would stonewall the very scenario SAVE-03 describes; unrestricted title-level matching opens the erase path. **[Arbitration]** `same_title` is an explicit **cross-line** restore that creates a child revision on the target line — this reconciles D-10 (lines keyed on ROM sha256, so a different dump is a different line) with the need to carry progress across a re-dump.
- **D-20:** A `medium_id` or `artifact_bytes` mismatch is a **hard block with no override affordance at all**. GBA's backup media (SRAM, Flash 64K/128K, EEPROM 4K/64K) share memory-map space through incompatible interfaces; writing a mismatched artifact is the documented path to the game itself declaring the save corrupt and **offering to erase it**. A warning is not sufficient protection against a destructive action taken by software we do not control.
- **D-21:** **Restore never overwrites in place.** The current on-disk `.sav` is captured as a revision first, and a failed capture **aborts the restore**. This is what converts the `same_title` tier from a gamble into a recoverable attempt.
- **D-22:** All gate inputs are denormalized onto the `save` payload at capture time and the verdict is evaluated **locally with zero network**. A gate requiring a server join would fail precisely on the clean offline Mac that SAVE-03 names. Widening to `same_title` requires Phase 2 `ReferenceMatch` `:matched` with `confidence: :exact` on **both** sides; `:variant`, `:no_match`, or absent never widens — the gate degrades toward strictness when identity is unknown.
- **D-23:** **Always full re-hash at restore**, deliberately *not* P3 D-23's size+inode+mtime cheap check. That shortcut exists to avoid re-hashing 100 MB ROMs; on ≤128 KB it buys nothing and costs a staleness-reasoning surface. A digest mismatch **quarantines, never deletes**, with a no-blame redownload remedy and no override while offline.
- **D-24:** The rule is **adapter-declared**, via additive `save_contract` fields: `save_kind`, `media[]`, `size_is_medium_identity`, `accepts_foreign_medium`, `portable_across_emulators`, `max_artifact_bytes`, `proven_media`, and crucially `binding_fields` vs `provenance_fields`. These must decode as Swift `Optional`s — `AdapterSaveContract`'s existing five keys are non-optional `let`s and would fail to decode an older pin. `SUPPORT-MATRIX.md` gains a save-restore section naming `sram_32k` as the only **proven** medium. Two new problem codes: `save_binding_incompatible` (422) and `save_revision_digest_mismatch` (422). — **Reversibility:** costly — `save_contract` is consumed by the shipped client's decoder; adding required keys later breaks older pins.

### Retention and Storage

- **D-25:** Server-side save bytes live in the **existing Phase 2 CAS** via `Playstead.Blobs`. A committed revision *is* immutable, which is precisely what the CAS guarantees; irreplaceable bytes belong in the store with the strongest proven durability, and it yields free dedupe plus a single Phase 5 backup surface. Game bytes are reconstructable from the user's own media in the worst case; **save bytes are reconstructable from nowhere** — that asymmetry argues for the stronger store, not a weaker one.
- **D-26:** New **`Playstead.Saves` bounded context** (`Save` lineage root + `Revision`), scoped by `user_id` per P1 D-01, committing blob → revision → `save` journal entry → idempotency receipt in one `Ecto.Multi`. The saves context knows nothing of CAS layout and `blobs` learns nothing about saves — P2 D-12's rule applied symmetrically is what makes a shared store safe rather than a coupling.
- **D-27:** Any future blob GC is a **gated decision** that must enumerate `save_revisions` as a referencing table and prove survival by test. Git's `gc` history is the lesson: a reachability walk eventually has a bug, and here the bug would eat the one thing that cannot be re-derived.
- **D-28:** **Keep every revision forever.** No prune, no TTL, no delete endpoint, no delete UI in v1. Pathological cost is roughly 1.6 GB/year; Nintendo Switch Online's 180-day deletion policy and the backlash it produced is the documented counter-example. Per-user backstops (100k revisions / 20 GiB) surface pressure as **attention, never deletion**.
- **D-29:** Saves are **outside the P3 D-21 quota** — free, since `QuotaManager` sums `cache_objects` only — **plus a 256 MiB save reserve** subtracted from what downloads are permitted to consume. Save revisions are **never evictable**, and evicting a game **keeps its saves**. Pinning a game need not pin its saves; never-evictable is a permanent property, not a UI state, so it earns no status rung.
- **D-30:** A **same-device byte-identical capture creates no revision** — it bumps `last_confirmed_at` / `confirm_count` on the existing head. A *different* device's byte-identical capture **does** create a revision (sharing the blob), because that is genuine independent evidence. **[Arbitration]** This composes with D-04 rather than competing: D-04 is the client's promotion policy, D-30 is the server's commit invariant, and both must hold.
- **D-31:** Disk-full at capture is a **named, loud-once, never-silent failure**: a durable blocked row, one alert, a persistent attention state, retry every cycle, a direct-upload escape hatch, nothing deleted, and **the game keeps running**. This is the worst case in the phase and it gets an explicit answer rather than a generic error path.
- **D-32:** A **dedicated save-only upload lane**, drained ahead of the curation outbox and downloads, with **no quarantine-to-silence terminal state**. A revision that exists on exactly one device is the most dangerous state in the product; it is quiet under 24 h and becomes an attention state after.
- **D-33:** Server caps: 8 MiB `save_revision_too_large` (413, enforced during streaming), `UploadSlots` under a `"save:"` key namespace, 120 revisions/hour/device, reusing Phase 2's shipped upload-limit machinery rather than inventing a parallel one. — **Reversibility:** costly — "keep everything forever" is easy to promise and expensive to walk back once users rely on it; D-28's backstops exist so the decision can be revisited under evidence rather than under pressure.

### Surfacing Save State

- **D-34:** **SAVE-02 is a per-revision requirement; a library card is a per-game object.** The apparent collision with P3 D-13's single status slot is a category error: **the card is a router, not an explainer.** This dissolves the conflict rather than trading against it.
- **D-35:** The six states are **three orthogonal axes**, not one ladder: durability is per-revision and monotone (`local-only` → `queued` → `uploaded`); `current` is per-**(revision, device)**; `restored` is immutable provenance; `conflicted` is a property of a **set**. A row is truthfully uploaded *and* current *and* restored at once. **Any `SaveStatus(for: game) -> enum` is a bug.**
- **D-36:** The game-level rollup reads the durability of the **newest** revision, scoped in the sentence, **never `min()`**, never the phrase "backed up", plus an unconditional muted count of earlier local-only versions. Rollup strings are locked in D-40.
- **D-37:** Save history is a **per-game sheet**, reached from a Save row in the Ready-to-Play surface. **No new sidebar noun** — P3 D-14's eight-step order is literally asserted by a shipped test. **[Arbitration]** The Save row is **navigational and never blocking**: it never contributes to the blocker count and cannot produce `.blocked`. Area F argued for no seventh readiness concept at all (a check green on every launch is an alarm, not readiness) and area C argued for a warning-only seventh check; the deciding evidence is that EXPERIENCE-ETHOS's shipped "Ready to Play" contract **already specifies a Save row** ("current, pending backup, older remote revision, or conflict"). F's objection is honoured in full — the **only blocking** save condition remains the widened `saveDirectory` check (D-42).
- **D-38:** Only `conflicted` reaches the card, through the **existing rank-1 `needsAttention` rung** — no new case, glyph, colour token, or copy, and therefore **no snapshot rebaseline** under P3.5 D-17. **[Arbitration]** The card's attention rung is a *presentation* rank fed by a union of sources; it is **not** `Playstead.Attention.Reason`, which stays frozen (see D-66).
- **D-39:** The timeline is **session-grouped, not a flat revision list** — D-04's cadence would make a flat list a log rather than a history, and grouping fixes noise, rendering performance, and the JTBD in one move. Row anatomy is isomorphic to the card's three zones, with a 28 pt rail reserved for SEED-006 screenshots. Durability is read from SQLite, never hashed at render. **Zero new colour literals; no green anywhere** (EXPERIENCE-ETHOS #16); save glyphs asserted disjoint from the status ladder's.
- **D-40:** **Escalate on undecidability, never on duration or count.** Offline queues, slow uploads, and old local-only versions never escalate — escalating them means escalating *success*. All user-facing strings, nouns, banned words, VoiceOver sentences, and the tiered only-copy escalation are locked verbatim in **"Locked User-Facing Copy"** below.

### Launch Path

- **D-41:** Save readiness is **not** a preflight blocker. "No save on this Mac" means **start fresh**, which is a correct outcome, not an error condition.
- **D-42:** Widen the **existing** `saveDirectory` check from "directory is writable" to "**a file can be atomically placed here**". Same kind, same `repairSaveDirectory` remedy identifier. Directory-writable is a weaker claim than launch actually needs — an immutable existing `.sav` passes today and then fails at spawn. This is the sole blocking save condition in the phase.
- **D-43:** **Saves ride along with the game download**, and `JournalApplier`'s new `save` case unconditionally prefetches revision bytes for locally-present asset sets. At 32 KB, prefetching is cheaper than the code that would decide whether to prefetch — and it is what makes SAVE-03's clean-Mac restore **zero-network at Play time**.
- **D-44:** A pure `LaunchSavePlanner` produces a `SavePlan` (`.fresh` / `.restore` / `.fastForward` / `.keep`), called between `materialize` and `AdapterHost.launch`, with the impure executor kept separate. **The governing invariant: the launch path writes save bytes only into emptiness, or over bytes that hash to a proven ancestor of a single uncontested head. Everything else is `.keep`.** That single testable sentence makes silent save loss structurally impossible.
- **D-45:** **Clean-Mac first launch silently auto-restores, with no prompt.** Every console does this, and asking a question whose answer is always yes is anti-ethos. It is safe *only* because D-44 gates it on emptiness. The receipt appears afterwards in the detail view, never as a launch-path modal.
- **D-46:** A diverged slot **never blocks Play, never prompts, and never writes the other head**. Playing extends only the local branch and **resolves nothing** — a persistent non-modal inline notice says exactly that before Play. **[Arbitration]** Areas B, C, and G independently forbade auto-picking a branch at launch; this is unanimous and locked.
- **D-47:** Save bytes are staged, `fsync`'d, `rename`'d, with the directory `fsync`'d — **never written in place**, because a torn in-place write yields a `.sav` that is neither old nor new and mGBA will mmap it as truth. **Zero network in the entire Play flow**, including fire-and-forget tasks: a post-spawn fetch could not help anyway, since mutating a mmap'd `.sav` under a running emulator *is* corruption. Saves stay at `<root>/saves/<assetSetID>/`, a sibling of `launch/`, never inside it — `LaunchMaterializer.materialize` `removeItem`s the entire launch directory on every launch. Play returns silently; **never say "saved."** Blocker and launch-notice copy is locked verbatim in **"Locked User-Facing Copy"** below.

### Divergence Resolution

- **D-48:** Choosing **appends a resolution revision** naming all divergent heads as parents (one distinguished `chosen_parent`, the rest acknowledged) rather than moving a head pointer. Resolution becomes immutable and auditable, converges under concurrent offline resolution with no compare-and-swap race, handles N-way divergence in a single act, and CAS-dedupes to zero new bytes. **Nothing is ever deleted.**
- **D-49:** **No Undo affordance.** The non-chosen version stays on screen with a live "Continue from this one" button, permanently. A permanent, self-evident history beats a transient toast, and an Undo control would imply harm was done.
- **D-50:** Inspection shows exactly **four facts per side**: origin, last saved, **play time since the split**, and saves since the split. Digest lives under "Details" only. **File size, byte-diff, similarity scores, revision ordinals, and parent pointers are never shown** — play-time-since-split is the only available fact that correlates with *value* rather than ordering, and file size is Steam's exact documented mistake (here it is the constant 32,768 for every side).
- **D-51:** **No side is ever recommended, highlighted, or pre-selected**, and there is **no confirmation dialog**. Any ranking heuristic is silent last-write-wins wearing a UI costume; a confirmation before a non-destructive, fully reversible act is exactly what trains Steam's documented click-through behaviour.
- **D-52:** **"Keep both" is a peer of the choice buttons**, appends an acknowledgement, leaves both heads standing, and is **never re-raised for that fork**. Unresolved-forever is a supported, first-class outcome — "this is my brother's playthrough" is a legitimate reason, and SEED-001's insight that saves carry unequal personal meaning arrives here early.
- **D-53:** One comparison sheet with **three entry points** (attention inbox, game detail, LiveView console). **No modal, no notification, no launch prompt** — the card's rank-1 attention rung makes it un-missable without interrupting. The whole flow works **with no server**: local metadata, an eager 32 KB fetch of both sides at detection, and choosing is a local mutation plus one idempotent outbox entry.
- **D-54:** **"Conflict" never appears in player-facing copy.** The feature is named **"Two versions of your progress."** Every string — inbox item, sheet, side lines, buttons, clock caveat, not-downloaded case, post-resolution confirmations, and the two console-only variants — is locked verbatim in **"Locked User-Facing Copy"** below. **[Arbitration]** Where area E's rollup said "Two versions of this save", G's noun wins for headings and rollups; E's `Separate version` survives as the per-row timeline label.
- **D-55:** **Zero gesture-only, hover-only, or pointer-only affordances, and zero colour distinguishing the sides.** Each side is one accessibility element carrying one complete comparison sentence. P3.5 D-21's lesson (`.onMove` alone failed the keyboard-parity contract) is applied *before* shipping rather than after. The only bulk action is **"Keep both in all {N}"**; a bulk "always use this Mac" is refused and its absence is asserted by test.

### Export

- **D-56:** Phase 2 **already cut the socket**, so folder shape was never open: `layout.ex:123` computes `saves_path`, `sidecar.ex:32,50` carry `"saves" => %{"kind" => "reserved", "entries" => []}` in both root and per-set sidecars, and `sanitize.ex:77` `reserved_saves_name?/1` renames a member literally named `saves` with a passing test. P2 D-39 declared these one-way. Phase 4 **fills the reservation** at `data/<system>/<set>/saves/` — no new tree, no BagIt profile change.
- **D-57:** Two-tier interior with default `saves_scope: :all`. `Layout.plan/2` gains `opts[:saves]` read exactly like `include_excluded`, but **persisted as `ExportRecord.saves_scope`** — unlike `include_excluded` it is a user choice, and a re-enqueued Oban job must reproduce the same plan.
- **D-58:** Filenames are `{seq:06}[-{branch}]-{digest8}.{ext}`, with the branch letter derived from a stable fork-inherited `branch_key`, **never a device name** — renaming a Mac must not rewrite a past export. A drop-in `saves/{stem}.sav` copy **is** produced, named from the primary member's **original basename** rather than the display title (naming it from the title reproduces RetroArch's documented save-loss bug). **Hard rule: a diverged slot gets no drop-in copy** — silently picking a side is last-write-wins performed by the export tool.
- **D-59:** Determinism is defined precisely enough to assert: plan purity, write reproducibility, and append-only stability, with three named exceptions (two inherited from Phase 2, including the existing `bag-info.txt` `Bagging-Date` carve-out). `Verifier` needs no changes.
- **D-60:** The reserved sidecar key is populated with **`branches` always present, even when linear**, so a diverged slot is *structurally incapable* of serialising as a flat list that implies a single history. A companion `saves.txt` supplies the "readable" in "readable manifest".
- **D-61:** **Save reimport is out of scope** — roadmap criterion 4 says *verify*, not reimport. The door stays open through a tested `round_trip_test` assertion over the reconstruction fields. Missing bytes (a revision that never uploaded) are sidecar-named with one grouped attention item, non-blocking, and **explicitly not placed in `fetch.txt`** — that would render the bag *incomplete* per RFC 8493 and break the `sha256sum -c` command our own README tells users to run.
- **D-62:** A new pure `Export.SavesPlan`; `Export → Saves` coupling exists at the context boundary only and `Layout` never aliases the saves context. One console control; **no Mac-side export action in Phase 4** — area G's "export either side" deep-links to the same server-side machinery. SEED-019's structural guard: **the drop-in name is defined only for `kind: "system_save"`**, so a save state can never earn one, because a drop-in name *is* a portability claim. — **Reversibility:** one-way — the sidecar `saves` schema and the export filename grammar become published format.

### Inherited Defects Fixed In This Phase

These are defects in already-shipped Phase 2/3 behaviour, not new capabilities. Each independently blocks a Phase 4 success criterion, so each is gap closure rather than scope creep.

- **D-63:** `AppPaths.excludeRootFromBackup` (`App/AppPaths.swift:39,51-58`) sets `isExcludedFromBackup` on the **Application Support root**, which inherits to the entire subtree — including `saves/` and `playstead.sqlite3`. The only bytes on the machine that **cannot be re-derived from the server** are therefore excluded from the user's only backup. **Found independently by three of the eight agents.** Fix: move the exclusion onto `objects/`, `partials/`, `launch/`, `emulators/`, `bios/` individually, with an idempotent launch-time clear of the stale root flag for existing installs. Until this ships, SAVE-01's clean-Mac-restore criterion is not actually met.
- **D-64:** `Readiness.required_bytes/2` computes `requested + max(1 GiB, 5% capacity)` and gates `LocalDisk.open_write/1`, so a **32 KB save upload is refused with 507 whenever the blob volume is under ~1 GiB free** — the server rejects the one artifact that cannot be reconstructed in order to reserve space for artifacts that can. Fix: additive `open_write/2` with `reserve: :critical` and a 64 MiB hard floor; save writes bypass the *margin*, never the physical check.
- **D-65:** `AdapterProcessRegistry` tracks running processes but does not **exclude** them. Two mGBA instances on one 32 KB `.sav` is guaranteed silent corruption. Fix: a per-`assetSetID` launch mutex spanning prepare → spawn → exit.

### Cross-Cutting Arbitration

- **D-66:** **`Playstead.Attention.Reason` is not widened.** It is a frozen, nine-member, import-recognition-scoped vocabulary. Divergence and blocked-capture raise items through a **saves-owned attention source** that the inbox view and the card's rank-1 rung union in. **[Arbitration]** Area G asked for one additive `Attention.Reason` member; areas C and E both independently refused to widen that bounded context. The dissent is better reasoned — widening an import-scoped enum to carry save-domain meaning is precisely the infrastructure-leaks-into-domain error P2 D-12 was written to prevent — and G's user-visible outcome is fully preserved either way.
- **D-67:** One **shared save vocabulary artifact** (`shared/save-vocabulary.json`) read as a **test resource on both sides**, never at runtime, plus one golden-strings fixture asserted by both suites, with the copy test asserting the fixture is **exhaustive** rather than merely matching. P3 D-17 named SwiftUI/HEEx parity drift as the top long-term risk; this is its Phase 4 instance. The LiveView console gets **full vocabulary parity with partial verbs** — it can inspect, choose, and export, but it has no emulator, so it **must never render a global playhead**: `current` is device-scoped.
- **D-68:** Verification: one **shared UAT checkpoint across areas A, C, and F** rather than three separate ones, since they are blocked on the same thing. What remains genuinely blocked on Phase 3 checkpoint 7 (real emulator + real game bytes): that a real commercial title flushes on a bounded cadence, that our captured bytes are accepted back by mGBA with correct in-game progress, and post-exit writeback behaviour. **"Continue the game" cannot be automated**; the honest automated proxy proves the *file* half only (`testCapturedRevisionRestoresToByteIdenticalArtifactInLaunchDir`), and named blocked checkpoint **CP7-SAVE-C** carries the human half and must never be marked passed by an automated test. The launch-path zero-network test asserts **zero recorded HTTP requests across the whole Play flow** — stricter than P3.5 D-10's blob-only precedent.

### Locked User-Facing Copy

**These strings are decided. Do not reinvent, paraphrase, or "improve" them during planning or execution.** They are reproduced here in full — rather than only referenced — because P3 D-17 named SwiftUI/HEEx copy drift as the top long-term risk, and D-67 requires exactly one authoritative source. `shared/save-vocabulary.json` (D-67) is generated from this section, and the golden-strings fixture asserted by both test suites must assert this set is **exhaustive**, not merely matching.

Three consistency fixes were applied while consolidating; each is marked **[Fix]** and supersedes the wording in the source research file.

#### Vocabulary rules

- **User-facing nouns:** a save is a **save**; a revision is a **version**; the timeline is **Save history**; the destination is **your server** (never "the cloud", never "backed up" — EXPERIENCE-ETHOS #16 reserves "backup" for PORT-03's independently verified copy, and calling an upload a backup is the single most consequential lie available in this phase).
- **Banned from every save surface:** sha256, digest, hash, cursor, journal, parent, base, head, ancestor, revision, blob, CAS, idempotency key, LWW, merge, sync, uploaded, backed up. Available behind one per-row "Details" disclosure for support purposes only.
- **Banned from divergence copy specifically:** conflict, overwrite, lost, wins, loser, merge, error, failed, corrupt, stale, invalid, "you should have". Copy must never imply the user erred — **playing on two Macs is the product working.** `conflict` survives only as an internal state name.

#### The six SAVE-02 states

| # | Axis | Label | Explainer | VoiceOver |
|---|---|---|---|---|
| 1 | durability | **Only on this Mac** | "This version hasn't reached your server yet. If this Mac is lost, so is this progress." | "Saved {time}. Only on this Mac — it has not reached your server yet." |
| 2 | durability | **Waiting to copy** | "Your server isn't reachable right now. This copies over on its own as soon as it is." | "Saved {time}. Waiting to copy to your server. It will copy on its own." |
| 3 | durability | **On your server** | "Stored on your server as well as on this Mac." | "Saved {time}. On your server and on this Mac." |
| 4 | position | **You are here** | "{title} continues from this version." | "You are here. {title} continues from this version, saved {time}." |
| 5 | provenance | **Restored here {date}** | "You brought this version back on {date}, from {device}." | "Restored here on {date}, from {device}." |
| 6 | lineage | **Separate version** | "This version and the one from {device} both continue from {time}. Neither has been changed." | "Separate version, saved {time} on {device}. It has not been merged with the version from {other device}. Both are kept." |

#### Game-level rollup headers (first match wins, exhaustive)

| Condition | Header |
|---|---|
| any divergent head exists | **"Two versions of your progress."** **[Fix]** — was "Two versions of this save."; D-54 rules G's noun for all headings and rollups |
| newest version only on this Mac | **"Latest save is only on this Mac."** |
| newest version waiting to copy | **"Latest save is waiting to copy to your server."** |
| newest version on server | **"Latest save is on your server."** |
| no versions yet | **"No saves yet."** — body: "Play {title} and your progress will show up here." |

Muted second line, only when count > 0 and never alone: **"{N} earlier versions are only on this Mac."** (singular: "1 earlier version is only on this Mac.")

One-time section footnote, never a banner: **"Your server holds these versions. Backing up the server itself is separate."**

#### Readiness sheet — the Save row (navigational, never blocking, per D-37)

| Outcome | Finding |
|---|---|
| ready | "Your progress is here and on your server." |
| ready (offline, expected) | "Your progress is here. It'll copy to your server when it's reachable." |
| warning | "This Mac has your progress, but your server hasn't got it yet." |
| warning (server has newer) | "Your server has newer progress, from {device}, {relative time}. Playing now continues from what's on this Mac." |
| warning (two versions) | "Two versions of your progress are waiting for your decision." — action: **"Review versions…"** **[Fix]** — the source file made this a `blocked` outcome; D-37 forbids the Save row producing `.blocked` and D-46 forbids divergence blocking Play. It is a warning with an action. |

#### The one blocking save condition (D-42, the widened `saveDirectory` check)

| Slot | String |
|---|---|
| Blocker | "Playstead can't write this game's saves." |
| Finding | "Nothing has been lost — your saved progress is still on your server. Playstead needs to be able to write to this game's save folder before it starts the game." |
| Remedy button | "Repair save folder" |
| VoiceOver | "Blocked. Playstead can't write this game's saves. Your progress is safe on your server. Activate Repair save folder to fix it." |

`RemedyAction.repairSaveDirectory` keeps its identifier; only the visible label changes from "Repair save directory" to "Repair save folder" — "folder" is the ordinary custody noun.

#### Launch-path notices (inline in the detail view's Save section; never modal, never a toast, never the card's status slot)

| Case | Copy |
|---|---|
| Restored into emptiness | **"Picked up from your {deviceName} save."** — "Saved {relative time} on {deviceName}. Nothing on this Mac was replaced." |
| Uncaptured bytes found and kept | **"Kept the save already on this Mac."** — "Playstead found saved progress here it hadn't recorded yet, so it saved a copy before starting." |
| Head bytes not local | **"Starting fresh on this Mac."** — "Newer progress from {deviceName} hasn't downloaded here yet. It's safe on your server and nothing will be overwritten." — action "Download saved progress", deliberately **not** on the launch path; disabled offline as "Available when you're back online" |
| Diverged slot, pre-Play | **"Two versions of your progress."** **[Fix]** — was "Two versions of this save exist." — "Playing now continues the version on this Mac. The other version stays exactly as it is." — action "Review both versions" |

#### Divergence — the attention item

| Element | Copy |
|---|---|
| Card status slot, rank 1 | "Needs attention" *(unchanged, P3 D-13)* |
| Card accessible name | "{title} needs your attention." *(unchanged)* |
| Item title | "Two versions of your progress in {title}" |
| Item title, N > 2 | "{N} versions of your progress in {title}" |
| Item body | "You played {title} on {Origin A} and {Origin B} without them syncing in between. Both versions are saved. Nothing has been overwritten." |
| Item body, N > 2 | "You played {title} on {N} devices without them syncing in between. All {N} versions are saved. Nothing has been overwritten." |
| Primary action | "Compare versions" |
| Grouped header | "Two versions of your progress in {N} games" |
| Grouped secondary action | "Keep both in all {N}" |

#### Divergence — the comparison sheet

| Element | Copy |
|---|---|
| Sheet title | "Two versions of your progress" |
| Subtitle | "{title} — both versions are safe. Pick the one to continue from, or keep both." |
| Subtitle, N > 2 | "{title} — all {N} versions are safe. Pick the one to continue from, or keep them all." |
| Side heading | "{Origin name}" |
| Side line 1 | "Last saved {relative time}" / after 7 days: "Last saved on {date}" |
| Side line 2 | "You played {duration} here since these split" |
| Side line 2, no sessions | "No recorded play here since these split" |
| Side line 3 | "across {N} saves" / singular: "in 1 save" |
| Choose action | "Continue from this one" |
| Chosen state | "Currently continuing from this one" |
| Export action | "Export this version…" |
| Clock caveat | "{Origin} reported a time that doesn't line up with when this version reached your server. Times from that Mac may be wrong." |
| Not downloaded | "{title} isn't downloaded on this Mac. You can still choose and export." |
| Keep-both action | "Keep both" / N > 2: "Keep them all" |
| Keep-both explainer | "Both versions stay in your library. This Mac keeps playing the {Origin} version." |
| Expert disclosure | "Details" |
| Dismiss | "Done" |

#### Divergence — result states

| Element | Copy |
|---|---|
| After choosing | "Continuing from {Origin}. The {Other origin} version is still here — you can switch to it anytime." |
| After choosing, N > 2 | "Continuing from {Origin}. The other {N−1} versions are still here — you can switch to any of them anytime." |
| After keeping both | "Keeping both. This Mac plays the {Origin} version. Neither version will be removed." |
| After switching back | "Continuing from {Origin} again. The {Other origin} version is still here." |
| Export result | "Exported {title} — {Origin}, {date}. The folder has the exact save file and a manifest listing what's inside." |
| Launch line | "This Mac is playing the {Origin} version. The other version is untouched." |
| Console-only, after choosing | "Continuing from {Origin}. Your Macs will use this version the next time they sync." |
| Console-only, after keeping both | "Keeping both. Each Mac keeps playing the version it already has." |

#### The only-copy danger case (D-32, D-40)

Tiered by **what the user is about to do**, never by how long a state has been true.

- **Ambient (always):** the "Only on this Mac" label. Nothing more.
- **Visible (in-context, non-modal, no colour):** the rollup header, plus the readiness Save row's "This Mac has your progress, but your server hasn't got it yet."
- **Escalated — only when the system cannot fix it itself** (auth revoked, capability skew, server refusal, compatibility rejection). Persistent inline panel: **"Your progress can't reach your server."** — "The last {N} versions of {title} are only on this Mac, and this won't fix itself: {reason}. Your progress is safe here in the meantime." Controls: "Fix this" · "Export saves…" · "What's stored where?"
- **Interruptive — modal, and only at the moment of destructive intent** (remove local copy, eviction, unpair, sign out, delete game): **"This is the only copy of your progress."** — "{N} versions of {title} are only on this Mac and nowhere else. Continuing removes them for good." Buttons: **"Export saves…"** (default) · "Cancel" · "Remove anyway" (destructive styling, never the default).

The modal never says "are you sure" and never blames: it states the fact, offers the escape hatch first, and keeps the destructive path available.

#### Explicitly absent, by decision — assert their absence

- No confirmation dialog on "Continue from this one" (D-51).
- No Undo toast (D-49).
- No "recommended" badge or pre-selected side (D-51).
- No bulk "always use this Mac" preference (D-55).
- No success message after play; **never say "saved."** (D-47)

### Claude's Discretion

- Swift file, type, and test-helper names; SQLite schema details and migration mechanics on the client; the exact polling actor structure — provided D-01's trigger, D-03's quiescence rule, and D-06's write order hold.
- Phoenix/Ecto table and column naming, migration sequencing, index choices (one index on `(save_line_id, parent_revision_id)` is required for branch-head derivation), and `Ecto.Multi` composition — following idiomatic Phoenix 1.8 and P1/P2 conventions.
- Exact glyph selection within D-39's zero-new-colour-literals and disjoint-vocabulary rules; sheet layout, spacing, and type scale within the shipped design tokens.
- The `branch_key` encoding, the `seq` allocation mechanics, and `digest8` length, provided D-58's stability properties hold.
- Whether the save upload lane is a distinct Swift actor or a priority band within the existing outbox, provided D-32's ordering guarantee holds.
- Probe SAVE-P1's harness shape and report format.
- Retry/backoff curves, TTL durations for pending upload blobs, and the orphan-blob sweep cadence.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 4 discussion research (option tables, prior art with URLs, adversarial passes, rejected alternatives)
- `.planning/phases/04-persistent-save-continuity/discussion-research/00-BRIEF.md` — the shared brief every fan-out worked from; the consolidated locked-constraint list
- `.planning/phases/04-persistent-save-continuity/discussion-research/A-capture-trigger-and-loss-window.md` — capture trigger, quiescence, crash recovery, probe SAVE-P1 spec
- `.planning/phases/04-persistent-save-continuity/discussion-research/B-lineage-and-conflict-model.md` — DAG rationale, endpoint shapes, payload fields, clock trust
- `.planning/phases/04-persistent-save-continuity/discussion-research/C-restore-compatibility-gate.md` — binding tuple, three tiers, GBA save-media analysis, problem codes
- `.planning/phases/04-persistent-save-continuity/discussion-research/D-retention-and-storage.md` — CAS siting, quota interaction, disk-full path, server caps
- `.planning/phases/04-persistent-save-continuity/discussion-research/E-save-state-surfacing.md` — three-axis model, **full locked microcopy table with VoiceOver sentences**
- `.planning/phases/04-persistent-save-continuity/discussion-research/F-launch-path-save-readiness.md` — `SavePlan`, the D-44 invariant, **locked launch microcopy**, 15 named tests
- `.planning/phases/04-persistent-save-continuity/discussion-research/G-conflict-resolution-ux.md` — **full locked conflict microcopy (verbatim strings)**, five-point handoff contract
- `.planning/phases/04-persistent-save-continuity/discussion-research/H-save-export-shape.md` — sidecar schema, filename grammar, determinism definition, 20 named tests

### Project foundation
- `.planning/PROJECT.md` — the six-item priority order (data safety > reliable play/saves > clarity/low-admin > performance > delight > breadth), constraints, Key Decisions, Project DNA
- `.planning/REQUIREMENTS.md` — SAVE-01…04 and PORT-01 verbatim; SAVE-05 (save states) explicitly deferred to v2
- `.planning/ROADMAP.md` §"Phase 4: Persistent Save Continuity" — goal, five success criteria, the compatibility gate flag

### Phase 3 adapter evidence (the empirical floor — read before designing anything about capture)
- `.planning/phases/03-mac-offline-play-vertical-slice/03-SPIKE-REPORT.md` §"Save Contract (Phase 4 SAVE-01 input)" — the ~24 s flush cadence, the no-on-demand-flush finding, the SIGTERM-equals-crash finding
- `.planning/phases/03-mac-offline-play-vertical-slice/03-ADAPTER-PIN.json` — `save_contract`, `launch`, `config_injection`, `exit_detection` blocks

### Prior phase contracts (build on, never reshape)
- `.planning/phases/01-private-custody-and-durable-protocol/01-CONTEXT.md` — P1 D-18 (additive-only `/api/v1`), D-19 (capability namespaces, incl. the already-declared `save`), D-20 (idempotency + UUIDv7), D-21 (journal/snapshot/cursor/410), D-22 (problem+json codes)
- `.planning/phases/02-explainable-import-and-exact-export/02-CONTEXT.md` — P2 D-11/D-12 (CAS + store seam, and the storage-adapters-stay-format-free rule), D-26 (quiet-badge philosophy), D-33 (readiness/exports), D-34/D-35 (deterministic export layout), D-39 (the saves reservation)
- `.planning/phases/03-mac-offline-play-vertical-slice/03-CONTEXT.md` — P3 D-07 (play-sessions), D-08 (how an entity kind is added), D-09 (no whole-list-as-truth), D-13 (single status slot, two colour vocabularies, non-colour-only), D-14 (sidebar IA), D-16 (motion), D-17 (shared spec, parity drift), D-20 (CAS + clonefile, never hardlink), D-21 (quota/floor, no silent deletion), D-23 (zero-network preflight)
- `.planning/phases/03.5-mac-verification-automation/03.5-CONTEXT.md` — D-03 (named/discovered/non-skipped test evidence), D-08 (release guard), D-09 (deterministic profiles), D-13…D-17 (snapshot contract and baseline discipline), D-19…D-21 (keyboard, live a11y audits, keyboard parity), D-24/D-25 (UAT evidence boundaries)

### Design authority
- `.planning/discovery/EXPERIENCE-ETHOS.md` — the brand book; quiet-by-default, humane exceptions, motion rules, the "Ready to Play" contract that already names a Save row, and rule #16 (no green)
- `.planning/phases/03-mac-offline-play-vertical-slice/03-UI-SPEC.md` — shipped design contract: status ladder, card anatomy, sidebar order, copy rules
- `playstead-mac/Playstead/Design/` — `StatusToken.swift`, `DesignTokens.swift`, `SystemAccent.swift`, `FocusRing.swift`, `MotionPreference.swift`, `AccessibilityIdentifiers.swift`
- `playstead-mac/docs/ACCESSIBILITY.md`, `playstead-mac/docs/SUPPORT-MATRIX.md` — the latter gains a save-restore section (D-24)

### Discovery corpus
- `.planning/discovery/WEB-AND-CLIENT-ARCHITECTURE.md` — adapter host boundary, API/OpenAPI discipline
- `.planning/discovery/TECHNICAL-RISKS.md` — offline and integration risk framing
- `.planning/research/PITFALLS.md`

### Forward-compatibility seeds (do NOT build; do NOT foreclose)
- `.planning/seeds/SEED-001-save-file-curation.md` — kept open by D-17's provenance fields and D-28's keep-everything rule
- `.planning/seeds/SEED-002-physical-cartridge-save-continuity.md` — kept open by D-18's `origin` field and D-58's drop-in naming
- `.planning/seeds/SEED-019-system-saves-versus-save-states.md` — kept open by D-10's `save_kind` discriminator and D-62's system-save-only drop-in rule
- `.planning/seeds/SEED-006`, `SEED-010`, `SEED-012` — adjacent; D-39 reserves the 28 pt row rail for SEED-006

### External standards and platform docs adopted by decision
- RFC 8493 (BagIt) — D-61's refusal to use `fetch.txt` for missing bytes
- RFC 9457 + IETF Idempotency-Key draft — inherited for every new endpoint
- Apple: `fsync`/`rename` durability, FSEvents vs. vnode semantics, `isExcludedFromBackup`, `clonefile(2)` — D-01, D-06, D-63
- GBA backup-media references (SRAM/Flash/EEPROM interfaces) — D-20's hard block
- mGBA `src/gba/savedata.c` — the mmap-backed store behind the ~24 s cadence

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Playstead.Sync.EntityKind` — **`save` is already a registered kind** (`~w(device pairing catalogue job transfer save curation)a`); no journal amendment needed, unlike P3 D-08's `curation` addition.
- `Playstead.Protocol.Capabilities` — `:save` is already a declared namespace; the save contract version is advertised there.
- `Playstead.Blobs.Store` — `put_stream/2`, `commit/2`, `stream/2`, `adopt_temp_file/2`; D-25 stores revision bytes through this seam. `Blobs.Fingerprints.fingerprint_kind/1` returns **`nil` for GBA**, so for the only shipped system content identity *is* byte identity — which collapses an entire headerless-fingerprint branch of the compatibility gate.
- `Playstead.Idempotency` — `fingerprint/1` canonicalizes a **parsed body**, which is what forces D-16's two-endpoint split.
- `Playstead.Export.{Layout,Sidecar,Sanitize,BagitWriter,Verifier,ExportRecord,Worker}` — `layout.ex:123` already computes `saves_path`; `sidecar.ex:32,50` already carry the reserved `saves` key; `sanitize.ex:77` already guards the name.
- `Playstead.RateLimiter`, `UploadSlots`, `PlaysteadWeb.Problem` / `error_codes.ex`, `Playstead.AuditLog` — new limits and codes slot into existing registries.
- Mac: `Cache/StreamingSHA256.swift`, `Cache/CASManager.swift`, `Cache/LaunchMaterializer.swift`, `Cache/PreflightChecker.swift`, `Cache/QuotaManager.swift`, `Sync/Outbox.swift` + `OutboxWorker.swift`, `Sync/JournalApplier.swift`, `Adapter/AdapterHost.swift`, `Adapter/AdapterExit.swift`, `Adapter/AdapterPin.swift`, `Persistence/LocalStore.swift` + `Migrations.swift`, `Design/StatusToken.swift`.
- `PlaysteadApp.saveDirectoryURL(forAssetSetID:)` already resolves to `<root>/saves/<assetSetID>/`, a **sibling of `launch/`** — so D-47's "saves survive launch-dir teardown" holds by construction, not by new code.
- `ReadinessCheckKind` already contains `saveDirectory` with a `.repairSaveDirectory` remedy — D-42 widens its semantics rather than adding a kind.

### Established Patterns
- Phoenix 1.8 scopes: every schema carries `user_id`, context functions take the scope, contexts own transactions, LiveView calls the same context functions as controllers.
- Journal payloads are additive-only published protocol; entity kinds are registered, journaled, snapshotted, and tombstoned through one spine (P3 D-08 is the worked example to copy).
- Contract tests assert problem+json codes and journal convergence, never English strings; migrations are forward-only.
- `Compaction.run/0` deletes journal rows at **90 days** — the reason D-17 puts lineage in its own tables.
- Row deletion must go through `ChangeJournal.tombstone/3` or cursor convergence breaks silently.
- P3.5 snapshot discipline: recording disabled in CI, references must exist, baselines refreshed only by a manual workflow on the pinned runner.

### Integration Points
- `playstead-server/lib/playstead_web/router.ex` — `PUT /api/v1/saves/uploads/:command_id` and `POST /api/v1/saves/revisions` under `:device_auth`; save-history and resolution views under `:require_authenticated_user`.
- `Playstead.Sync.Snapshot.read/1` — mandatory `save:` branch inside the same consistent transaction as `catalogue`/`curation`.
- `Playstead.Readiness` — additive `open_write/2` with `reserve: :critical` (D-64).
- Mac `JournalApplier` — new `save` case with unconditional 32 KB prefetch (D-43).
- Mac launch flow — `LaunchSavePlanner` between `LaunchMaterializer.materialize` and `AdapterHost.launch` (D-44), behind the new per-game launch mutex (D-65).
- Phase 5 consumes: save blobs as first-class backup/restore/scrub subjects (D-27's gated-GC rule is a standing constraint on that phase).

</code_context>

<specifics>
## Specific Ideas

- The user asked for a full multi-lens fan-out with an adversarial pass per area and a single coherent recommendation set rather than a menu — "so I don't have to think". Every gray area is therefore **decided**, not presented as options; the rejected alternatives live in `discussion-research/` for audit rather than for re-litigation.
- No `prompts/` subdirectory exists in this repo; the request's "prompts subdir" and "brandbook" were mapped to `.planning/discovery/` (with `EXPERIENCE-ETHOS.md` as the brand book), `.planning/research/`, `03-UI-SPEC.md`, and `Playstead/Design/*.swift`. Recorded so the substitution is auditable.
- The single sentence a reviewer should check the implementation against is D-44: *the launch path writes save bytes only into emptiness, or over bytes that hash to a proven ancestor of a single uncontested head.*
- "Two versions of your progress" is the product name for divergence; the word **conflict** must not reach a player.
- Play-time-since-split is the one comparison fact that speaks to value rather than ordering — it is the reason the conflict sheet is worth building at all rather than showing two timestamps.
- Three of eight independent agents found the Time Machine exclusion defect without being asked to look for it. That convergence is the strongest signal in the fan-out and D-63 should be sequenced early.

</specifics>

<deferred>
## Deferred Ideas

- **Save curation** — naming, notes, tags, favourites, "treasured"/protected revisions, and a browsable save collection (SEED-001). D-17's provenance fields and D-28's keep-everything rule are chosen so this needs additive fields only.
- **Save states** (SAVE-05) — v2, gated on an emulator/core/build compatibility fingerprint that passes restore tests. D-10's `save_kind` discriminator and D-62's system-save-only drop-in rule exist so this can arrive without the surface lying (SEED-019).
- **Cartridge save read/write** (SEED-002, SEED-010) — hardware-dependent, likely its own milestone. D-18's `origin` field is the seam.
- **Save-progress screenshots** (SEED-006) — D-39 reserves the 28 pt row rail; nothing else is built.
- **Memory-card explorer / save hub** (SEED-012) — the per-game sheet is deliberately not generalized into a global surface.
- **Save reimport** — export is verify-only per roadmap criterion 4; D-61 keeps the reconstruction fields tested so a later reimport is possible.
- **Retention pruning** — D-28 ships keep-everything; per-user backstops surface pressure as attention so a pruning design can be made under evidence rather than under pressure.
- **Automatic conflict resolution / "always prefer this Mac"** — refused by D-51 and its absence asserted by test; not a future feature, a rejected one.
- **A rebuild-from-`saves/objects` path** for a torn SQLite index restore — flagged by area D as a Phase 5 concern, not built here.
- **`02-CONTEXT.md` D-34 is stale against shipped code** (`playstead-manifest.json`/`_unsorted`/`_quarantined` vs. the shipped `playstead-bag.json`/`unsorted`/`quarantine`). Worth a docs fix; not this phase.
- **Multi-slot and directory-shaped saves** — D-08's artifact-set and D-10's `slot` make them possible; the path ships untested in Phase 4 and should not be claimed.

</deferred>

---

*Phase: 4-persistent-save-continuity*
*Context gathered: 2026-09-03*
