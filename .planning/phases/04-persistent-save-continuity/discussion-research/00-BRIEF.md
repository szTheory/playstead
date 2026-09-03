# Phase 4 Fan-Out Brief — Persistent Save Continuity

Shared briefing for every Phase 4 discussion-research agent. Read this first,
then your assigned decision area file spec at the bottom.

## The phase (fixed boundary — never widen it)

**Goal:** A player can keep one adapter-proven persistent save safe across
offline work, clean-Mac restore, export, and divergent-device conflicts without
losing either version.

**Requirements:** SAVE-01…04, PORT-01 (verbatim in `.planning/REQUIREMENTS.md`).

**Five success criteria:** `.planning/ROADMAP.md` §"Phase 4: Persistent Save Continuity".

**Explicitly out of scope for Phase 4** (recommend nothing that requires them):
save states (SAVE-05, v2 — persistent battery saves only), save curation
UX / naming / tagging / treasuring (SEED-001, SEED-012, SEED-019 — future),
cartridge read/write hardware (SEED-002, SEED-010 — future), screenshots
(SEED-006), a second client or adapter, browser play, metadata/artwork
providers, backup/restore drills and server health (Phase 5), S3/direct transfer.

## Hard empirical constraints from the Phase 3 adapter spike (NOT negotiable)

Sources: `.planning/phases/03-mac-offline-play-vertical-slice/03-SPIKE-REPORT.md`
and `03-ADAPTER-PIN.json` (read both).

- Pinned adapter: **mGBA standalone 0.10.5**, system `gba`.
- Save artifact: `{saveDir}/{romBaseName}.sav`, injected with `-C savegamePath={dir}`.
- Format: **raw 32 KB SRAM battery file** (32768 bytes observed).
- Flush: **periodic, mmap-backed, ~24 s cadence** on disk during play, even
  though the ROM re-writes SRAM every ~5 s. Genuine periodic flush, measured.
- **`on_demand_flush_supported: false`** — no CLI/hotkey manual-save trigger.
- **SIGTERM is indistinguishable from a crash.** `Process.terminate()` produces
  `terminationStatus: 15, terminationReason: uncaughtSignal`, exactly like
  SIGSEGV/SIGKILL. There is **no observable graceful-quit signature** and no
  flush-on-exit you may assume completes.
- **Worst-case data-loss window: 24 seconds**, measured, not estimated.

Design consequence the spike itself states: the durability floor is the periodic
on-disk flush cadence; treat *every* exit (clean, crashed, killed) as potentially
losing up to ~24 s.

## Locked prior decisions you must build on, never reshape

Read `.planning/phases/01-.../01-CONTEXT.md`, `02-.../02-CONTEXT.md`,
`03-.../03-CONTEXT.md`, `03.5-.../03.5-CONTEXT.md` for the full text. Key ones:

- **P1 D-21:** change journal + snapshot + HMAC opaque cursor + 410 resync is the
  one recovery spine. **`save` is ALREADY a frozen change-journal entity kind**
  (`playstead-server/lib/playstead/sync/entity_kind.ex`:
  `~w(device pairing catalogue job transfer save curation)a`). No new sync path.
- **P1 D-19:** `save` is already a declared capability namespace
  (`Playstead.Protocol.Capabilities`: `[:protocol, :app, :cache, :transfer, :adapter, :save]`).
  Version skew must degrade with an explained remedy, never a hard break.
- **P1 D-18:** `/api/v1` is additive-only. **P1 D-20:** every mutation carries
  `Idempotency-Key` + a client-generated UUIDv7 natural key, with a transactional
  receipt. **P1 D-22:** every error is problem+json with a registered code
  (`PlaysteadWeb.Problem` / `error_codes.ex`).
- **P2 D-11/D-12:** server content-addressed blob store behind a
  `Playstead.Blobs.Store` seam (`put_stream/2`, `commit/2`, `stream/2`,
  `adopt_temp_file/2`). Storage adapters must stay free of format knowledge.
- **P2 D-34/D-35 + `Playstead.Export.Layout`:** exports are fully sorted,
  timestamp-free, collision-resolving, planned in full before a byte is written,
  written by `BagitWriter`, checked by `Verifier`, with a `Sidecar` manifest.
- **P3 D-09:** LWW-per-row is acceptable for trivia; **no client ever transmits a
  whole list as truth** — full-list LWW silently drops concurrent offline work.
- **P3 D-13 (the one that bites):** the library card has **exactly one status
  slot**, showing the single highest-priority state on a strict ladder
  (attention > missing dependency > downloading > queued > verified/pinned >
  server-only). System-identity hues and status semantics are two separate colour
  vocabularies; **no state is ever colour-only** (WCAG 1.4.1). See
  `playstead-mac/Playstead/Design/StatusToken.swift`.
- **P3 D-20:** Mac cache is a sha256 CAS under `~/Library/Application Support/Playstead/`
  (Time-Machine-excluded); launch dirs are materialized with APFS `clonefile`,
  plain-copy fallback, **never hardlink** — an emulator writing through a hardlink
  would corrupt the verified CAS copy.
- **P3 D-21:** fixed quota (default 25 GB) **plus** a 10 GB free-space floor (the
  floor wins); **no silent deletion, ever**; eviction is manual-only in v1.
- **P3 D-23:** launch preflight makes **zero network calls** (CACH-04) and trusts
  the download-time hash via a cheap size+inode+mtime check with full re-hash fallback.
- **P3 D-16:** motion only where it explains state; reduced-motion equivalents required.
- **03.5 D-03/D-24:** every UAT checkpoint needs a **named** test proven
  discovered, executed, non-skipped and passed. Fixed sleeps and
  "exited zero" are prohibited evidence. 03.5 D-09: deterministic test profiles
  are a finite compile-gated enum seeded through real APIs — never raw SQL,
  never copyrighted ROMs or proprietary BIOS.
- **03.5 D-08:** test-only hooks must fail closed and be provably absent from release builds.

## Project constitution (`.planning/PROJECT.md`)

Priority order when tradeoffs are real:
1. Data safety and recoverability
2. Reliable local play and save continuity
3. Clarity, accessibility, low-administration operation
4. Performance and resource efficiency
5. Integrated delight
6. Feature breadth

Constraints that bind this phase: never silently discard save conflicts; preserve
exact bytes and provide verified export (no lock-in); a verified local game must
stay launchable with no network; state support as explicit matrices, never
aspirational universality; treat all imported files as untrusted.

Project DNA: idiomatic Elixir/Phoenix over generic framework-shaped code; judge
"done" from a first adopter's complete experience; DX and UX are both product
quality; retain high-signal investigation with provenance.

## Design authority (this project's "brand book")

- `.planning/discovery/EXPERIENCE-ETHOS.md` — interaction contracts, quiet-by-default,
  humane exceptions, motion rules. **This is the brand book. Read it.**
- `.planning/phases/03-mac-offline-play-vertical-slice/03-UI-SPEC.md` — the shipped
  design contract: status ladder, card anatomy, sidebar IA, copy rules.
- `playstead-mac/Playstead/Design/` — `DesignTokens.swift`, `StatusToken.swift`,
  `SystemAccent.swift`, `FocusRing.swift`, `MotionPreference.swift`,
  `AccessibilityIdentifiers.swift`.
- `.planning/discovery/WEB-AND-CLIENT-ARCHITECTURE.md`,
  `.planning/discovery/TECHNICAL-RISKS.md`, `.planning/discovery/USER-FEEDBACK.md`,
  `.planning/discovery/LANDSCAPE.md`, `.planning/research/PITFALLS.md`.

## Forward-compatibility seeds (do NOT build; do NOT foreclose)

These three seeds name this exact moment as their trigger — "surface before
locking the save-revision model". Your recommendations must leave room for them
without implementing them, and you should say explicitly which field or seam
keeps each door open:

- `.planning/seeds/SEED-001-save-file-curation.md` — a user's save collection may
  matter more than their game collection; future naming/notes/tags/treasuring,
  with provenance attached (origin device, import method, emulator/core+version,
  content fingerprint, format identity, capture time, revision ancestry,
  conversion history, known-vs-inferred).
- `.planning/seeds/SEED-002-physical-cartridge-save-continuity.md` — pulling a save
  off a real cartridge and writing one back.
- `.planning/seeds/SEED-019-system-saves-versus-save-states.md` — system saves and
  save states are alike enough to invite one surface and different enough that one
  surface quietly lies. Phase 4 ships system saves only; the vocabulary you choose
  must not make save states impossible to add honestly later.
- `.planning/seeds/SEED-012`, `SEED-010`, `SEED-006` — adjacent, same caution.

## Current code (greenfield — no save code exists on either side)

- Server contexts: `playstead-server/lib/playstead/{sync,blobs,export,catalogue,curation,idempotency,attention,import}/`
- Mac client: `playstead-mac/Playstead/{Sync,Cache,Adapter,Persistence,Library,Design,Readiness,Curation}/`
  — note `Sync/Outbox.swift`, `Sync/JournalApplier.swift`, `Cache/CASManager.swift`,
  `Cache/LaunchMaterializer.swift`, `Cache/PreflightChecker.swift`,
  `Adapter/AdapterHost.swift`, `Adapter/AdapterExit.swift`,
  `Persistence/LocalStore.swift` + `Migrations.swift` (SQLite).
- Grep before you claim anything exists or does not.

## What every fan-out must produce

Work through your decision area with **breadth and depth across every relevant
role lens**, then converge. Lenses to actually apply (name them; skip ones that
genuinely do not apply, and say so):

- Software architect / domain modeller (bounded contexts, ubiquitous language,
  one-way dependency flow, no infrastructure leakage into the core domain)
- Distributed-systems / offline-sync engineer (causality, idempotency,
  partition behaviour, clock trust, convergence)
- Elixir/OTP + Phoenix 1.8 + Ecto idiom (contexts own transactions, scopes,
  `Ecto.Multi`, supervision is not a substitute for durable state, backpressure,
  forward-only migrations, additive published payloads)
- Swift/macOS client engineer (FSEvents/DispatchSource vs polling, atomic file
  writes, mmap and page-cache semantics, App Support layout, SQLite durability,
  process lifecycle, sandbox-free hardened runtime)
- Filesystem/durability engineer (APFS, `fsync`, rename-atomicity, clonefile,
  torn writes, `kill -9`)
- Security engineer (untrusted bytes, path traversal, quota/DoS, no credentials
  or ROM identity in logs or CI evidence)
- SRE / operator (observability without alert noise, low-administration)
- Product / first-adopter (does a real person's progress survive; JTBD)
- UI/UX + creative direction + microcopy (only where the area has a surface)
- Accessibility (WCAG 1.4.1 non-colour-only, VoiceOver sentences, keyboard
  parity, reduced motion) — a design pillar, not an afterthought
- Performance/resource (a 32 KB file; do not build a distributed database for it)
- Test/verification engineer (how is this proven by a named automated test under
  03.5 D-03, given checkpoint 7 is still blocked on real emulator + real bytes)
- QA adversarial / red-team (see below)

Also required in every file:

1. **JTBD framing** for any user-facing decision: who / what / where / when / why,
   what they need to do it, what they get back — and the domain nouns, verbs, and
   events that fall out of it. Keep the interface consumer-shaped, not
   provider-shaped: **never expose backend guts** (digests, cursors, journal
   kinds, parent pointers) unless a fundamental constraint forces it, and say
   why when it does.
2. **Prior art**, researched online, from this and adjacent ecosystems — be
   concrete and name the system. Candidates worth checking: RetroArch cloud sync
   and its known save-clobbering complaints, EmuDeck/Steam Deck save sync,
   Steam Cloud (its conflict dialog is the canonical example of both good and
   bad), Nintendo Switch Online save data cloud (and its deliberate exclusions),
   PlayStation Plus cloud saves, Ludusavi, syncthing/Resilio conflict files,
   Dropbox "conflicted copy", iCloud Documents & `NSFileVersion`, git's
   three-way merge and DAG, Fossil, Datomic/immutable-log designs, CRDT
   literature and its limits for opaque binary blobs, Obsidian Sync, 1Password's
   item history, Time Machine's local snapshots, `NSFileCoordinator`/File
   Provider, borg/restic snapshot models, Litestream. **What did each get right
   that we should copy, and what is the documented footgun we must avoid?**
   Cite sources with URLs and note anything mutable that needs revalidation.
3. **An options table**: each option with concrete example/sketch, pros, cons,
   failure modes, reversibility (one-way / costly / cheap), and effort.
4. **An explicit adversarial pass** on your own leading recommendation: how does
   it lose data, mislead a user, or become the thing we regret? What would a
   hostile reviewer say? Then either fix the recommendation or record the
   residual risk honestly.
5. **A one-shot recommendation** stated as a numbered decision list (`D-xx`
   placeholders are fine — I renumber at synthesis), each with a one-line
   rationale and a reversibility note. Write it so the owner does not have to
   think: pick, do not present a menu.
6. **Coherence notes**: what your recommendation assumes about the *other*
   decision areas (listed below), and any place you might collide with them.
   Flag collisions loudly rather than quietly assuming.
7. **Forward compatibility**: the exact field/seam that keeps SEED-001/002/019
   open, and what you deliberately did NOT build.
8. **Open questions only if genuinely unresolvable** — prefer a decision plus a
   stated assumption.

Style: dense, specific, no filler, no corporate voice. Assert things you verified;
mark inference as inference. Grep the repo before claiming what exists.

## The eight decision areas (so you can flag collisions)

- **A** — Capture trigger and loss window (SAVE-01)
- **B** — Revision lineage and conflict detection model (SAVE-04 mechanism)
- **C** — Restore compatibility gate (SAVE-03)
- **D** — Retention, dedupe, and where revisions are stored (client + server)
- **E** — Save state surfacing vs. the frozen one-status-slot ladder (SAVE-02)
- **F** — Launch-path save readiness and preflight (SAVE-03 + CACH-04's zero-network rule)
- **G** — What "resolve a conflict" actually does, as a user flow (SAVE-04 UX)
- **H** — Save export shape in the deterministic layout (PORT-01)

## Output

Write your file with Bash (heredoc or `cat >`), to the exact path given in your
task prompt, under
`.planning/phases/04-persistent-save-continuity/discussion-research/`.

Then return to the orchestrator a **compact** summary: your numbered
recommendations with one-line rationales, your collision flags, and your residual
risks. Do not paste the whole file back.
