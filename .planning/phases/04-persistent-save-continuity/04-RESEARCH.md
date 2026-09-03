# Phase 4: Persistent Save Continuity - Research

**Researched:** 2026-09-03
**Domain:** Local capture/durability of an emulator battery-save artifact, server-side revision-DAG lineage and CAS storage, restore-compatibility gating, divergence (conflict) surfacing/resolution UX, and deterministic save export — spanning Swift (macOS client) and Elixir/Phoenix/Ecto (server).
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

All decisions below were produced by eight parallel multi-lens research fan-outs (macOS/filesystem durability, distributed systems, Elixir/OTP/Phoenix/Ecto idiom, emulation-domain truth, security, SRE, product/JTBD, UI/UX and creative direction, accessibility, verification engineering, plus an adversarial pass per area), each with online prior-art research and a self-adversarial review, synthesized into one coherent set (D-01 through D-68). Full option tables, prior-art citations, adversarial passes, and rejected alternatives live in `discussion-research/`. Seven cross-area collisions were arbitrated at synthesis, each marked **[Arbitration]** inline in the source.

The full decision set (D-01–D-68, organized under Capture and Local Durability, Revision Model and Divergence, Restore Compatibility, Retention and Storage, Surfacing Save State, Launch Path, Divergence Resolution, Export, Inherited Defects Fixed In This Phase, and Cross-Cutting Arbitration) is reproduced in full in `.planning/phases/04-persistent-save-continuity/04-CONTEXT.md` — that file is the canonical source of these decisions and MUST be read directly by the planner; it is too large to duplicate verbatim here without loss of fidelity. Key load-bearing decisions this research independently verified against source code: D-01 (1 Hz poll, no FSEvents/kqueue), D-03 (quiescence = three identical reads), D-05 (unconditional post-exit settle, never branches on `AdapterExit`), D-06 (bytes-before-references write order), D-09/D-13/D-14 (parent-pointer DAG, accept-and-branch, no automatic winner), D-15 (server `recorded_at` is the only orderable time), D-16 (two-endpoint split forced by `Idempotency.fingerprint/1`'s parsed-body-only canonicalization), D-18–D-24 (three-tier compatibility gate, local zero-network evaluation, always full re-hash at restore), D-25–D-33 (CAS storage, keep-forever retention, save-only upload lane), D-34–D-40 (three orthogonal state axes, locked microcopy), D-41–D-47 (non-blocking save readiness, `LaunchSavePlanner`'s single governing invariant, zero-network Play flow), D-48–D-55 (append-only resolution, no undo, no auto-pick, locked divergence copy), D-56–D-62 (fills Phase 2's already-reserved `saves` export slot), D-63/D-64/D-65 (three inherited defect fixes — Time Machine exclusion scope, free-space reserve bypass, launch mutex), D-66 (frozen `Attention.Reason`, do not widen), D-67 (one shared save-vocabulary artifact), D-68 (CP7-SAVE-C is human-only, never automatable).

**The entire "Locked User-Facing Copy" section of `04-CONTEXT.md` (vocabulary rules, the six SAVE-02 states table, rollup headers, readiness sheet strings, launch-path notices, divergence copy, result states, and the only-copy danger-case tiering) is locked verbatim and MUST NOT be paraphrased, reinvented, or "improved" during planning or execution.** The planner must reference `04-CONTEXT.md`'s copy tables directly rather than re-deriving strings.

### Claude's Discretion

- Swift file, type, and test-helper names; SQLite schema details and migration mechanics on the client; the exact polling actor structure — provided D-01's trigger, D-03's quiescence rule, and D-06's write order hold.
- Phoenix/Ecto table and column naming, migration sequencing, index choices (one index on `(save_line_id, parent_revision_id)` is required for branch-head derivation), and `Ecto.Multi` composition — following idiomatic Phoenix 1.8 and P1/P2 conventions.
- Exact glyph selection within D-39's zero-new-colour-literals and disjoint-vocabulary rules; sheet layout, spacing, and type scale within the shipped design tokens.
- The `branch_key` encoding, the `seq` allocation mechanics, and `digest8` length, provided D-58's stability properties hold.
- Whether the save upload lane is a distinct Swift actor or a priority band within the existing outbox, provided D-32's ordering guarantee holds.
- Probe SAVE-P1's harness shape and report format.
- Retry/backoff curves, TTL durations for pending upload blobs, and the orphan-blob sweep cadence.

### Deferred Ideas (OUT OF SCOPE)

- Save curation — naming, notes, tags, favourites, "treasured"/protected revisions, and a browsable save collection (SEED-001). D-17's provenance fields and D-28's keep-everything rule are chosen so this needs additive fields only.
- Save states (SAVE-05) — v2, gated on an emulator/core/build compatibility fingerprint that passes restore tests. D-10's `save_kind` discriminator and D-62's system-save-only drop-in rule exist so this can arrive without the surface lying (SEED-019).
- Cartridge save read/write (SEED-002, SEED-010) — hardware-dependent, likely its own milestone. D-18's `origin` field is the seam.
- Save-progress screenshots (SEED-006) — D-39 reserves the 28 pt row rail; nothing else is built.
- Memory-card explorer / save hub (SEED-012) — the per-game sheet is deliberately not generalized into a global surface.
- Save reimport — export is verify-only per roadmap criterion 4; D-61 keeps the reconstruction fields tested so a later reimport is possible.
- Retention pruning — D-28 ships keep-everything; per-user backstops surface pressure as attention so a pruning design can be made under evidence rather than under pressure.
- Automatic conflict resolution / "always prefer this Mac" — refused by D-51 and its absence asserted by test; not a future feature, a rejected one.
- A rebuild-from-`saves/objects` path for a torn SQLite index restore — flagged as a Phase 5 concern, not built here.
- `02-CONTEXT.md` D-34 is stale against shipped code (`playstead-manifest.json`/`_unsorted`/`_quarantined` vs. the shipped `playstead-bag.json`/`unsorted`/`quarantine`). Worth a docs fix; not this phase.
- Multi-slot and directory-shaped saves — D-08's artifact-set and D-10's `slot` make them possible; the path ships untested in Phase 4 and should not be claimed.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-------------------|
| SAVE-01 | After a proven safe flush, the Mac client can capture the adapter-declared persistent-save artifact and queue it locally when the server is unavailable. | D-01–D-08 (capture trigger, quiescence, write order, crash recovery); D-32/D-33 (save-only upload lane, server caps); verified `Idempotency`/CAS/`EntityKind` seams to build on (see Don't Hand-Roll) |
| SAVE-02 | A user can see whether a save revision is local-only, queued, uploaded, current, restored, or in conflict without a generic "synced" label hiding the distinction. | D-34–D-40 (three orthogonal axes, not one ladder); D-67 (shared vocabulary, golden-strings fixture); full locked copy tables in `04-CONTEXT.md` |
| SAVE-03 | A user can restore a compatible checksummed persistent-save revision and continue the game on a clean paired Mac installation. | D-18–D-24 (three-tier local zero-network gate); D-41–D-47 (`LaunchSavePlanner`, zero-network Play flow); D-68 (CP7-SAVE-C human-only checkpoint, automated file-restore proxy) |
| SAVE-04 | When two devices create revisions from the same base, the system retains both and lets the user inspect device/time/play context, choose or export either side, and resolve the conflict without silent last-write-wins. | D-09–D-17 (parent-pointer DAG, accept-and-branch, no auto-winner); D-48–D-55 (append-only resolution, comparison sheet, locked divergence copy) |
| PORT-01 (saves half) | A user can export exact persistent-save revisions and a readable manifest with hashes into deterministic ordinary folders. | D-56–D-62 (fills Phase 2's already-reserved `saves` sidecar slot — verified `layout.ex`/`sidecar.ex`/`sanitize.ex` citations above); game-bytes half already shipped in Phase 2 |
</phase_requirements>

## Summary

Phase 4's `04-CONTEXT.md` is not an ordinary discuss-phase context file — it is the finished output of an eight-agent adversarial multi-lens research fan-out (68 decisions, D-01 through D-68) that already resolved every material design question for this phase, cross-checked against Phase 1/2/3/3.5 shipped contracts and against the Phase 3 adapter's empirically measured save behaviour. There is no live external-library research gap to fill: this phase introduces **zero new third-party dependencies** on either side of the stack. The engineering task is disciplined application of already-locked decisions onto an already-existing codebase, plus one measurement spike (SAVE-P1) and three named defect fixes (D-63/64/65) in already-shipped code.

Given that, this RESEARCH.md's job is different from a typical phase: instead of surveying an unfamiliar domain, it (1) independently verifies the load-bearing code citations CONTEXT.md relies on by reading the actual source (all confirmed below, verbatim), (2) confirms no new packages are needed and the existing Phoenix/Ecto/Swift toolchain is sufficient, (3) organizes the 68 decisions into the planner-facing categories (stack, architecture, pitfalls, don't-hand-roll) this document's contract requires, and (4) flags the one place where CONTEXT.md's own language admits an unresolved empirical gap (D-02 / probe SAVE-P1 / CP7-SAVE-C) so the planner sequences it first, not last.

**Primary recommendation:** Plan Phase 4 as CONTEXT.md's decisions describe, in this rough dependency order: (0) fix the three inherited defects D-63/D-64/D-65 early (three independent agents converged on D-63 unprompted — treat that convergence as a correctness signal, not decoration); (1) run probe SAVE-P1 before writing any capture code that depends on its answer; (2) build capture → server lineage/CAS → restore gate → export in that order, since later stages consume earlier ones' schema; (3) build the divergence/conflict UX last, since it is purely additive on top of the lineage DAG. Do not reopen any of D-01–D-68 during planning — they are locked; the only genuinely open technical question CONTEXT.md leaves for the plan is the SAVE-P1 harness shape and report format (explicitly Claude's Discretion).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Save-artifact capture, quiescence detection, staged/promoted revision write | Mac Client (local) | — | D-01–D-08: 1 Hz polling and fsync/rename discipline are inherently local-filesystem operations; zero server round-trip during capture |
| Save-line/revision DAG (lineage), branch heads, divergence detection | API/Backend | Database | D-09–D-17: server is sole authority for `recorded_at` ordering (D-15) and branch-head derivation; Postgres stores the DAG |
| Save blob storage | Database/Storage (CAS) | API/Backend | D-25–D-27: reuses `Playstead.Blobs` CAS exactly as Phase 2 game bytes do; `Playstead.Saves` context owns lineage metadata only |
| Restore-compatibility gate evaluation | Mac Client (local) | — | D-22: "evaluated locally with zero network" — explicit rejection of a server-join gate so it works on the clean offline Mac SAVE-03 names |
| Save-state surfacing (six states, rollups, timeline) | Mac Client (SwiftUI) | LiveView console (partial) | D-34–D-40, D-67: full vocabulary + `current` (device-scoped) on Mac; LiveView gets "full vocabulary parity with partial verbs" (inspect/choose/export, no playhead) |
| Launch-path save planning (`.fresh`/`.restore`/`.fastForward`/`.keep`) | Mac Client | — | D-41–D-47: zero-network in the entire Play flow is an explicit, test-asserted invariant |
| Divergence resolution (choose / keep both) | Mac Client (SwiftUI) | LiveView console | D-48–D-55: sheet with three entry points, one of which is the LiveView console; local mutation + one idempotent outbox entry, no server round-trip required to act |
| Deterministic save export | API/Backend (Oban job) | — | D-56–D-62: fills Phase 2's already-reserved `saves` sidecar slot; server-side only, "no Mac-side export action in Phase 4" |
| Backup exclusion / free-space reservation / launch mutex (D-63/64/65) | Mac Client / API/Backend | — | Fixes span both tiers: D-63 and D-65 are Mac-only, D-64 is server-only |

## Standard Stack

### Core

No new libraries are introduced by this phase on either side. The existing pinned versions apply:

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| phoenix | ~> 1.8.13 [VERIFIED: playstead-server/mix.exs:43] | Web framework, LiveView console | Already the project's framework; D-26's `Playstead.Saves` context follows the same Phoenix 1.8 idiom as every prior context |
| ecto_sql | ~> 3.14.0 [VERIFIED: playstead-server/mix.exs:45] | Postgres ORM/migrations for the save-line/revision DAG | Already standard; D-09's DAG needs only one new nullable FK column plus the `(save_line_id, parent_revision_id)` index CONTEXT.md specifies |
| oban | ~> 2.24 [VERIFIED: playstead-server/mix.exs:50] | Background job runner for save export (D-62's `Export.SavesPlan`) | Already runs Phase 2's export/import jobs; D-62 extends the existing export worker rather than adding a new job runner |
| jason | ~> 1.2 [VERIFIED: playstead-server/mix.exs:78] | JSON encode/decode for journal payloads, sidecar, `save_contract` | Already the project's JSON library |
| bandit | ~> 1.5 [VERIFIED: playstead-server/mix.exs:80] | HTTP server, streamed upload endpoint (D-16's `PUT /api/v1/saves/uploads/:command_id`) | Already serves Phase 1/2's streamed blob uploads |

Mac side: Foundation/`Process`/`FileManager`/`NSLock` (AdapterProcessRegistry, D-65), `CryptoKit`-class hashing already used by `Cache/StreamingSHA256.swift`, SQLite via the existing `Persistence/LocalStore.swift` + `Migrations.swift`. No new Swift package dependencies.

### Supporting

Nothing new — this phase is explicitly built as additive fields and new tables/contexts on an already-adopted stack (D-08, D-17, D-24, D-26 all describe additive schema, not new tooling).

### Alternatives Considered

CONTEXT.md's `discussion-research/` already ran and rejected the alternatives an independent research pass would otherwise re-derive; re-litigating them is out of scope per the phase's own instruction ("rejected alternatives live in discussion-research/ for audit rather than for re-litigation"). Notable rejections already made: FSEvents/kqueue/NSFileCoordinator instead of 1 Hz polling (D-01); vector clocks and CRDTs instead of a parent-pointer DAG (D-09); 409-reject-on-diverge instead of accept-and-branch (D-13); CouchDB-style deterministic winner instead of no-automatic-winner (D-14); a boolean compatibility check instead of three tiers (D-19); a server-join compatibility gate instead of local zero-network evaluation (D-22).

**Installation:** None — no new packages to install for this phase.

**Version verification:** `playstead-server/mix.exs` read directly this session; versions above are quoted from source at the cited line numbers, not from training-data assumption.

## Package Legitimacy Audit

**Not applicable.** This phase installs no new external packages on either the Elixir/Phoenix server or the Swift/macOS client. All required capability (CAS blob storage, journal/snapshot sync, streamed uploads, Oban jobs, SQLite persistence, hashing) is provided by dependencies already present in `playstead-server/mix.exs` and the existing Xcode project, verified above. The Package Legitimacy Gate is skipped per its own trigger condition (only required "whenever this phase installs external packages").

**Packages removed due to [SLOP] verdict:** none — none proposed.
**Packages flagged as suspicious [SUS]:** none.

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────── macOS Client (Playstead.app) ───────────────────────────┐
│                                                                                       │
│  [Game launch] → LaunchSavePlanner (D-44, pure)                                     │
│        │  reads: local SQLite revision metadata + saveDirectory bytes               │
│        ▼                                                                             │
│  SavePlan{.fresh|.restore|.fastForward|.keep} → executor (impure)                   │
│        │  writes: temp → fsync → rename → fsync(dir), never in-place (D-47)         │
│        ▼                                                                             │
│  AdapterHost.launch (per-assetSetID mutex, D-65) ──► mGBA process                   │
│        │  emulator mmaps .sav, flushes on its own ~24s cadence (Phase 3 evidence)   │
│        ▼                                                                             │
│  1 Hz poll-and-hash actor (D-01) — runs only while game is open                     │
│        │  quiescence = 3 identical consecutive reads (D-03)                         │
│        ▼                                                                             │
│  Staged capture (rolling) ──promote-at-session-end──► Promoted revision (D-04)      │
│        │  write order: bytes→temp, fsync, rename, fsync(dir), THEN sqlite row (D-06)│
│        ▼                                                                             │
│  Local SQLite: save_line, revision, durability state (local-only/queued/uploaded)   │
│        │                                                                             │
│        ├──► Restore-compatibility gate (D-18–D-24): LOCAL, zero-network             │
│        │                                                                             │
│        └──► Save-only upload lane (D-32, priority over curation/download outbox)    │
│                    │  PUT /api/v1/saves/uploads/:command_id  (streamed, D-16)        │
│                    ▼  POST /api/v1/saves/revisions            (idempotent commit)    │
└────────────────────┼─────────────────────────────────────────────────────────────────┘
                      │  HTTPS, device-authenticated
┌─────────────────────▼──────────────────── Phoenix Server ───────────────────────────┐
│                                                                                       │
│  Router :device_auth  ──► SavesController                                           │
│        │  Idempotency.fingerprint (parsed-body only, forces the two-endpoint split) │
│        ▼                                                                             │
│  Playstead.Saves context (Save + Revision, Ecto.Multi, D-26)                        │
│        │  1. blob → Playstead.Blobs CAS (D-25)                                      │
│        │  2. → save_revisions row (parent_revision_id DAG, D-09)                    │
│        │  3. → Playstead.Sync journal entry, kind: save (already registered)        │
│        │  4. → idempotency receipt                                                  │
│        │  all inside ONE Ecto.Multi — atomic commit                                 │
│        ▼                                                                             │
│  Branch-head derivation (revisions with no children, D-14) → divergence surfaced    │
│                      │                                                               │
│        ┌─────────────┴─────────────┐                                               │
│        ▼                           ▼                                               │
│  Snapshot.read/1 `save:` branch    Export.SavesPlan (Oban, D-62)                    │
│  (device catch-up, no WebSocket)   → BagIt-shaped deterministic folder + manifest    │
│                                                                                       │
└───────────────────────────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure

Server (new/extended paths, following existing bounded-context layout):
```
playstead-server/lib/playstead/
├── saves.ex                      # Playstead.Saves context (D-26)
├── saves/
│   ├── save.ex                   # lineage root schema
│   ├── revision.ex               # revision DAG node schema
│   └── save_contract.ex          # if server-side validation of adapter-declared contract needed
├── export/
│   └── saves_plan.ex             # Export.SavesPlan (D-62) — pure plan, Export→Saves boundary only
└── sync/
    └── snapshot.ex                # mandatory `save:` branch added (existing file, D-17)
```

Mac (new/extended paths, following existing layout):
```
playstead-mac/Playstead/
├── Saves/                         # new group, mirrors Adapter/, Cache/, Sync/
│   ├── SaveCapturePoller.swift    # D-01/D-03 1 Hz actor
│   ├── SaveSessionRecovery.swift  # D-07 crash-recovery replay
│   ├── LaunchSavePlanner.swift    # D-44 pure planner
│   ├── SaveCompatibilityGate.swift # D-18–D-24 local zero-network gate
│   └── SaveConflictResolver.swift # D-48–D-55 divergence mutation
├── Sync/
│   └── JournalApplier.swift       # extended: new `save` case (existing file, D-43)
└── Adapter/
    └── AdapterHost.swift          # extended: per-assetSetID launch mutex (existing file, D-65)
```

### Pattern 1: Bytes-before-references durable write (D-06)
**What:** Read the whole artifact into one buffer, hash once, write to temp file, `fsync`, `rename`, `fsync` the containing directory, and only then insert the SQLite/Postgres row referencing it.
**When to use:** Every save-blob write on both client and server — this is the same discipline the existing CAS (`Playstead.Blobs.Store`, `Cache/CASManager.swift`) already applies to game bytes; save capture reuses the identical ordering, not a new one.
**Example:**
```elixir
# Source: playstead-server/lib/playstead/blobs/store/local_disk.ex (existing pattern to mirror)
# do_open_write/1 stages to a temp path; commit/2 renames into place after fsync.
# Playstead.Saves should call Playstead.Blobs.Store.{put_stream,commit} rather than
# reimplementing fsync/rename — D-25 requires saves to go through this exact seam.
```

### Pattern 2: Local, zero-network gate evaluation (D-22)
**What:** All inputs the restore-compatibility gate needs are denormalized onto the `save` payload at capture time; the verdict is computed with no network call.
**When to use:** Any check that must hold on "a clean offline Mac" (SAVE-03's literal scenario) — this generalizes the pattern already established by P3 D-23's zero-network preflight.
**Example:**
```
# Conceptual (Claude's Discretion on exact Swift type names):
struct SaveCompatibilityInputs {   // denormalized at capture, never fetched at restore
    let systemId: String
    let saveKind: String
    let mediumId: String
    let artifactBytes: Data
    let romSha256: String
    let titleIdentity: String
    let origin: SaveOrigin
}
func evaluate(_ inputs: SaveCompatibilityInputs) -> CompatibilityTier // .exact | .sameTitle | .incompatible
```

### Pattern 3: Append-only resolution, never a moved pointer (D-48)
**What:** Resolving a divergence appends a new revision naming every divergent head as a parent (one `chosen_parent`, others acknowledged) — it never mutates or deletes existing heads.
**When to use:** Every divergence-resolution action ("Continue from this one", "Keep both").
**Example:**
```elixir
# Conceptual Ecto.Multi shape:
Ecto.Multi.new()
|> Ecto.Multi.insert(:resolution_revision, fn _ ->
  Revision.changeset(%Revision{}, %{
    blob_sha256: chosen.blob_sha256,   # CAS-dedupes to zero new bytes (D-48)
    parent_revision_id: chosen.id,      # chosen_parent
    acknowledged_parent_ids: [other.id | rest]  # the rest, acknowledged not merged
  })
end)
```

### Anti-Patterns to Avoid
- **Branching capture behaviour on `AdapterExit` status (D-05):** dirty `MAP_SHARED` pages can land after process death; a post-exit read can see bytes no pre-exit read saw. The settle pass must be unconditional.
- **Server-side automatic winner selection (D-14):** CouchDB's deterministic-winner rule is documented as the single most complained-about property of that model — never pick a winner, ever, client or server.
- **Any `SaveStatus(for: game) -> enum` (D-35):** durability, `current`, `restored`, and `conflicted` are independent axes; collapsing them into one enum is explicitly named as a bug pattern to avoid, not a simplification.
- **Sorting or gating on UUIDv7 embedded timestamps (D-15):** UUIDv7 ids embed an untrusted client clock; only server `recorded_at` is orderable.
- **In-place `.sav` writes at launch (D-47):** a torn in-place write yields bytes mGBA will mmap as truth; always stage → fsync → rename → fsync(dir).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Content-addressed blob storage for save bytes | A parallel save-specific blob store | `Playstead.Blobs` (existing CAS, D-25) | Free dedupe, single Phase 5 backup surface, and P2 D-12's storage-adapters-stay-format-free rule already proven |
| Idempotent mutation replay | A bespoke save-specific idempotency key scheme | `Playstead.Idempotency.fingerprint/1` [VERIFIED: playstead-server/lib/playstead/idempotency.ex:33-38 — `def fingerprint(%{method: method, path: path, body: body})`, canonicalizes a sorted-map/list term via `:erlang.term_to_binary` then SHA-256] | Already handles PROT-04's durable-receipt contract; D-16's two-endpoint split exists specifically because this function "canonicalizes a *parsed body*" and cannot fingerprint a stream |
| Sync/catch-up protocol for missed save updates | A save-specific polling or push channel | `Playstead.Sync.Snapshot.read/1` + existing journal/cursor spine, `save` `EntityKind` [VERIFIED: playstead-server/lib/playstead/sync/entity_kind.ex:25 — `@kinds ~w(device pairing catalogue job transfer save curation)a`] | `save` is already a registered kind — no protocol/journal amendment needed, unlike Phase 3's `curation` addition which required one |
| Deterministic export folder layout | A new save-specific export tree or BagIt profile | `Playstead.Export.Layout`/`Sidecar`/`Sanitize` (existing, reservation already cut) [VERIFIED: playstead-server/lib/playstead/export/layout.ex:123 — `saves_path: Path.join(relative_dir, "saves")`; sidecar.ex:32 — `"saves" => %{"kind" => "reserved", "entries" => []}` in `root/1`; sidecar.ex:50 — identical reserved key in `set/1`; sanitize.ex:76-79 — `reserved_saves_name?/1` compares against `@reserved_saves_name` via `collision_key/1`] | Phase 2 already reserved this exact slot in the shipped sidecar schema and filename-collision guard; building a parallel tree would violate P2 D-39's one-way reservation |
| Save-format/media identification | A custom SRAM/Flash/EEPROM parser or header sniffer | Adapter-declared `save_contract` fields (D-24), plus `Blobs.Fingerprints.fingerprint_kind/1` returning `nil` for GBA [VERIFIED: playstead-server/lib/playstead/blobs/fingerprints.ex:65-76 — matches only `{:nes,...}` and `{:snes,...,%{copier_header: true}}`; catch-all `defp fingerprint_kind(_format_result), do: nil`] | Playstead "never parses save bytes, ever" (D-03); the fingerprinting module already treats GBA as opaque (nil), which is exactly the "content identity is byte identity" property D-24's compatibility gate depends on — no new parsing code needed |
| Upload concurrency / rate limiting for save uploads | A new limiter | `Playstead.RateLimiter`, `UploadSlots` (existing, `"save:"` key namespace per D-33) | Phase 2 already built and shipped this exact machinery for game-byte uploads; D-33 explicitly says "reusing Phase 2's shipped upload-limit machinery rather than inventing a parallel one" |

**Key insight:** Nearly every "don't hand-roll" item in this phase is not a third-party-library substitution (the usual case) but a **reuse-existing-in-repo-seam** substitution — Phase 1/2/3 already built the CAS, idempotency, sync spine, export layout, and rate limiter this phase needs. The highest-risk planning failure mode here is a plan that quietly reimplements one of these seams instead of extending it, which would violate the bounded-context boundaries (P2 D-12, D-26) CONTEXT.md repeatedly cites as load-bearing.

## Runtime State Inventory

Not applicable — this is a greenfield-capability phase (new save-continuity feature), not a rename/refactor/migration phase. No existing stored state, service config, or registered names are being renamed or moved.

## Common Pitfalls

### Pitfall 1: Treating `AdapterExit.clean` as a durability guarantee
**What goes wrong:** Code branches the post-exit capture/settle logic on whether the emulator exited "cleanly", skipping the settle pass on a clean exit.
**Why it happens:** It looks like a reasonable optimization — "if it exited cleanly, the save must already be flushed."
**How to avoid:** D-05 is explicit: `AdapterExit.clean` is a signal classification, not a durability guarantee; `MAP_SHARED` dirty pages can land after process death. Run the unconditional settle pass regardless of exit case.
**Warning signs:** Any `switch`/`if` on `AdapterExit` case gating whether a post-exit read happens at all.

### Pitfall 2: Rejecting non-fast-forward save uploads (409)
**What goes wrong:** A save-upload endpoint modeled after typical git-like semantics 409-rejects a revision whose parent isn't the current head.
**Why it happens:** This is the conventional server behaviour for divergent writes in most sync systems.
**How to avoid:** D-13 explicitly forbids this: rejecting would leave the losing side's only durable copy sitting on a client, inverting the project's #1 constitutional priority (data safety). Accept and branch; the only rejections are `409 save_parent_unknown` (pure outbox mis-ordering) and the loud caps (`save_branch_limit_exceeded`, `save_revision_immutable`).
**Warning signs:** Any HTTP 409 path in the save-revision commit endpoint that isn't one of those two named codes.

### Pitfall 3: Widening `Playstead.Attention.Reason` for divergence
**What goes wrong:** Adding a new member to the existing `Attention.Reason` enum to represent a save conflict, since it's the obvious extension point.
**Why it happens:** It's the path of least resistance — one enum, one new case.
**How to avoid:** D-66 explicitly forbids this: `Attention.Reason` is a frozen, nine-member, import-recognition-scoped vocabulary. Route divergence/blocked-capture through a new saves-owned attention source that the inbox view and card's rank-1 rung union in, not through the frozen enum.
**Warning signs:** A PR diff touching `Attention.Reason`'s definition at all during this phase.

### Pitfall 4: Letting "uploaded" or "synced" read as "backed up"
**What goes wrong:** Any copy, log line, or internal naming that implies an uploaded save is safe in the backup sense.
**Why it happens:** In casual engineering language "uploaded to server" and "backed up" are near-synonyms.
**How to avoid:** EXPERIENCE-ETHOS #16 reserves "backup" specifically for PORT-03's independently verified copy; calling an upload a backup is named in CONTEXT.md as "the single most consequential lie available in this phase." The banned-word list (sha256, digest, hash, cursor, journal, parent, base, head, ancestor, revision, blob, CAS, idempotency key, LWW, merge, sync, uploaded, backed up) applies to every user-facing save surface.
**Warning signs:** Any of the banned words appearing outside the per-row "Details" disclosure; any string not sourced from the locked copy tables in `04-CONTEXT.md`.

### Pitfall 5: Auto-picking a branch, or blocking Play, on a diverged slot
**What goes wrong:** Launch logic either silently picks the "best" head to continue from, or blocks Play until the user resolves the divergence.
**Why it happens:** Both feel like reasonable UX defaults — "just pick the most recent" or "make them resolve it before playing."
**How to avoid:** D-46 is unanimous across three independent research areas (B, C, G): a diverged slot never blocks Play, never prompts, and never writes the other head. Playing extends only the local branch and resolves nothing; a persistent non-modal inline notice states this before Play.
**Warning signs:** Any `.blocked` readiness outcome or modal triggered by divergence; any code path that writes to a non-local head during launch.

### Pitfall 6: Rehashing with the cheap size+inode+mtime shortcut at restore
**What goes wrong:** Reusing P3 D-23's cheap staleness check (used for large ROM files) for the tiny save artifact at restore time.
**Why it happens:** It's already-written, tested code sitting right there in the codebase.
**How to avoid:** D-23 explicitly rejects reusing it here: that shortcut exists to avoid rehashing 100 MB ROMs; on a ≤128 KB save artifact it buys nothing and introduces a staleness-reasoning surface. Always full re-hash at restore.
**Warning signs:** Any restore-path call into the same helper P3 D-23 introduced for game-byte staleness checks.

## Code Examples

### Existing idempotency fingerprint (reuse, do not reimplement)
```elixir
# Source: playstead-server/lib/playstead/idempotency.ex:33-47 (read this session)
def fingerprint(%{method: method, path: path, body: body}) do
  canonical = {method, path, canonicalize(body)}

  :crypto.hash(:sha256, :erlang.term_to_binary(canonical))
  |> Base.encode16(case: :lower)
end

defp canonicalize(value) when is_map(value) do
  value
  |> Enum.map(fn {k, v} -> {to_string(k), canonicalize(v)} end)
  |> Enum.sort_by(fn {k, _v} -> k end)
end

defp canonicalize(value) when is_list(value), do: Enum.map(value, &canonicalize/1)
defp canonicalize(value), do: value
```
This operates on a **parsed body** — the reason D-16 splits the streamed blob upload (`PUT /api/v1/saves/uploads/:command_id`) from the idempotent metadata commit (`POST /api/v1/saves/revisions`) into two endpoints.

### Existing reserved `saves` sidecar slot (fill, do not redesign)
```elixir
# Source: playstead-server/lib/playstead/export/sidecar.ex:22-35 (read this session)
def root(opts \\ []) do
  %{
    "kind" => "root",
    "schema" => @schema_id,
    "saves" => %{"kind" => "reserved", "entries" => []},
    "generator" => Keyword.get(opts, :generator, "playstead")
  }
end
```
Phase 4's D-60 changes this to always populate `branches`, even when linear, and to add a companion `saves.txt` — but the key itself, and its presence in both root and per-set sidecars, already ships.

### Existing free-space margin formula (server-side; D-64 needs an additive `reserve:` bypass, not a rewrite)
```elixir
# Source: playstead-server/lib/playstead/readiness.ex:367-373 (read this session)
def required_bytes(requested_bytes, capacity_bytes)
    when is_integer(requested_bytes) and requested_bytes >= 0 and
           is_integer(capacity_bytes) and capacity_bytes >= 0 do
  margin = max(@min_free_margin_bytes, div(capacity_bytes * 5, 100))
  requested_bytes + margin
end
```
This is what silently refuses a 32 KB save upload whenever free space is under ~1 GiB (D-64) — because `Playstead.Blobs.open_write/1` [VERIFIED: playstead-server/lib/playstead/blobs/store/local_disk.ex:37 — `def open_write(byte_size_hint)`, single-arity] has no `reserve:` parameter to bypass the margin today. D-64's fix is an **additive** `open_write/2`, not a rewrite of this formula.

### Existing save directory resolution (Mac; already correctly placed as a sibling of `launch/`)
```swift
// Source: playstead-mac/Playstead/App/PlaysteadApp.swift:681-686 (read this session)
func saveDirectoryURL(forAssetSetID assetSetID: String) throws -> URL {
    let safe = try PathSafety.validatedFilename(assetSetID)
    return appPaths.root
        .appendingPathComponent("saves", isDirectory: true)
        .appendingPathComponent(safe, isDirectory: true)
}
```
`AppPaths`'s managed directory list is `[root, objects, partials, launch, emulators, bios]` [VERIFIED: playstead-mac/Playstead/App/AppPaths.swift:44 — `for dir in [root, objects, partials, launch, emulators, bios]`] — `saves` is deliberately outside that list and created ad hoc, which is exactly why D-47's "saves survive launch-dir teardown" (`LaunchMaterializer.materialize` `removeItem`s the whole `launch/` directory every launch) holds by construction.

### Existing process registry (needs D-65's per-assetSetID exclusion added, not built from scratch)
```swift
// Source: playstead-mac/Playstead/Adapter/AdapterHost.swift:32-50 (read this session)
final class AdapterProcessRegistry: @unchecked Sendable {
    static let shared = AdapterProcessRegistry()
    private let lock = NSLock()
    private var processes: [ObjectIdentifier: Process] = [:]
    // ...
    func register(_ process: Process) {
        lock.lock()
        processes[ObjectIdentifier(process)] = process
        ensureObservingLocked()
        lock.unlock()
    }
}
```
This registry tracks processes keyed by `ObjectIdentifier(process)` for termination-on-quit only — it has **no concept of `assetSetID`** and therefore cannot today prevent two mGBA instances from opening the same `.sav` concurrently. D-65's fix is a new per-`assetSetID` launch mutex spanning prepare → spawn → exit, added alongside this existing registry.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| `saveDirectory` readiness check validates only "directory is writable" | Widened to "a file can be atomically placed here" (D-42) | This phase | An immutable existing `.sav` passes the old check today, then fails at emulator spawn — the widened check catches it before launch, same remedy identifier (`repairSaveDirectory`) |
| Time Machine exclusion applied to the whole Application Support root | Exclusion moved onto `objects/`, `partials/`, `launch/`, `emulators/`, `bios/` individually (D-63) | This phase | Save bytes and the SQLite catalogue — the only bytes on the machine not re-derivable from the server — become backed up by Time Machine for the first time |
| Free-space margin applies uniformly to every write, including 32 KB saves | Additive `open_write/2` with `reserve: :critical` bypasses the *margin* (never the physical check) for saves (D-64) | This phase | Save uploads no longer 507 under the same low-free-space condition that legitimately blocks large game downloads |

**Deprecated/outdated:** None — this phase adds capability rather than replacing a previously-shipped save-related feature (no prior save continuity existed).

## Assumptions Log

CONTEXT.md's decisions are themselves the product of an extensively researched and adversarially reviewed synthesis; very few residual `[ASSUMED]` claims remain for this RESEARCH.md to flag. The two below are things this research session could not independently verify without running code.

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | FSEvents/vnode event delivery behaviour for an mmap writer on APFS is unmeasured (the "FSEvents misses mmap writes" claim is documented for inotify/fanotify, not FSEvents) [ASSUMED — training-knowledge characterization of the claim's provenance, not independently re-verified against Apple docs this session] | D-01/D-02, "Standard Stack" rationale | Low — D-01 already treats this as unproven and gates it behind probe SAVE-P1 rather than relying on it; no plan action depends on this being true or false |
| A2 | mGBA's `src/gba/savedata.c` mmap-backed store and ~24 s flush cadence, cited as the empirical floor for D-01–D-08 [ASSUMED — this research session did not re-read mGBA source or the Phase 3 spike's raw timeline artifacts, which CONTEXT.md itself notes are gitignored and no longer present; relies on `03-SPIKE-REPORT.md`'s written summary] | Capture trigger and quiescence rationale | Low-Medium — if the Phase 3 spike's cadence measurement was itself imprecise, D-01's 1 Hz poll rate is still safe (Nyquist-oversampled relative to any plausible flush interval), so no replanning is needed even if this figure is slightly off |

**If this table is empty:** N/A — see above; both entries are non-blocking for planning since the phase's own design (D-02's probe, D-01's oversampled poll rate) already treats them as unverified inputs rather than as load-bearing facts.

## Open Questions

1. **Probe SAVE-P1's concrete harness and report format**
   - What we know: D-02 mandates the probe run early in this phase, measuring inode stability, mtime fidelity, FSEvents/vnode delivery, and post-death dirty-page landing; "no outcome changes D-01" (the poll-based design proceeds regardless).
   - What's unclear: The exact harness implementation and report schema are explicitly listed under "Claude's Discretion" in CONTEXT.md — not yet specified.
   - Recommendation: The planner should schedule SAVE-P1 as an early, small, self-contained plan/task (per D-02's "Run probe SAVE-P1 as an early plan in this phase"), producing a pinned report artifact analogous to Phase 3's `03-ADAPTER-PIN.json`/`03-SPIKE-REPORT.md` pattern, before any capture-poller code that would need its findings for tuning (none currently does, since D-01 already commits to polling regardless of outcome — so this is evidence-gathering, not a gate).

2. **CP7-SAVE-C — the human-only UAT half**
   - What we know: D-68 names one shared UAT checkpoint across research areas A/C/F, explicitly split into an automated proxy (`testCapturedRevisionRestoresToByteIdenticalArtifactInLaunchDir`, proving the file half) and a human-only half (a real commercial title flushing on a bounded cadence, captured bytes accepted back by mGBA with correct in-game progress, post-exit writeback behaviour) that "cannot be automated" and "must never be marked passed by an automated test."
   - What's unclear: Nothing conceptually — this is a locked decision, not a gap. Flagging it here only so the planner does not attempt to script around it; it must appear in the plan as a named, explicitly human `checkpoint:human-verify` gate, not silently folded into the automated suite.
   - Recommendation: Reserve `CP7-SAVE-C` as its own UAT checkpoint identifier in the plan, distinct from the automated file-restore test.

## Environment Availability

Skipped — this phase's only external dependencies (Postgres, the existing Phoenix/Oban server, the Mac's existing mGBA adapter pin) are already provisioned and verified operational by Phases 1–3 (all shipped, per `.planning/STATE.md`'s traceability table). No new external tool, service, or runtime is introduced.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework (server) | ExUnit (Elixir/Mix), confirmed via `mix test` aliases and `test/` tree structure [VERIFIED: playstead-server/mix.exs — `test: ["assets.build", "ecto.create --quiet", "ecto.migrate --quiet", "test"]`] |
| Framework (Mac) | XCTest across four named test plans [VERIFIED: playstead-mac/TestPlans/{Unit,Rendering,UI,LiveServer}.xctestplan present] |
| Config file (server) | `playstead-server/mix.exs` |
| Config file (Mac) | `playstead-mac/TestPlans/*.xctestplan` — per Phase 3.5 D-xx convention, "every Mac acceptance test assigned to one explicit serial Unit, Rendering, UI, or LiveServer plan" |
| Quick run command (server) | `mix test test/playstead/saves/` (once the new test dir exists) |
| Quick run command (Mac) | `xcodebuild test -scheme Playstead -testPlan Unit` (pattern matches existing Phase 3.5 usage) |
| Full suite command (server) | `mix test` |
| Full suite command (Mac) | Existing 03.5 hosted CI run across all four test plans (per STATE.md's Phase 3.5 decisions) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SAVE-01 | Capture proven-safe-flush artifact, queue while offline | unit + integration | `mix test test/playstead/saves/` (server commit path); Mac `SaveCapturePollerTests` under Unit plan | ❌ Wave 0 (new files, both sides) |
| SAVE-02 | Per-revision durability/current/restored/conflicted surfacing, no generic "synced" label | unit + snapshot | Mac `SaveStateSurfacingTests` (Unit) + snapshot fixtures under Rendering plan; server `copy_contract_test.exs`-style golden-strings assertion (D-67's shared vocabulary fixture) | ❌ Wave 0 |
| SAVE-03 | Clean-Mac restore, checksummed, continue the game | integration + manual (CP7-SAVE-C) | `testCapturedRevisionRestoresToByteIdenticalArtifactInLaunchDir` (D-68, named); human continuation proof is explicitly NOT automatable | Partial — automated file-restore proxy is Wave 0; human half is `checkpoint:human-verify` |
| SAVE-04 | Retain both diverging revisions; inspect/choose/export/resolve without silent LWW | unit + integration | Server `Playstead.SavesTest` branch-derivation tests; Mac `SaveConflictResolverTests` (Unit) + UI plan for the comparison sheet (D-53's three entry points) | ❌ Wave 0 |
| PORT-01 (saves half) | Export exact save-revision bytes + readable hash manifest into deterministic folders | integration | `layout_test.exs`, `bagit_writer_test.exs`, `sanitize_test.exs` extended with a `saves`-populated case (existing files, existing pattern) | Partial — files exist, save-specific cases are Wave 0 |

### Sampling Rate
- **Per task commit:** `mix test` (server) targeted to the changed context; `xcodebuild test -testPlan Unit` (Mac) for changed Swift files.
- **Per wave merge:** Full `mix test` + all four Mac test plans (Unit/Rendering/UI/LiveServer), matching the Phase 3.5-established hosted CI gate.
- **Phase gate:** Full suite green (both server and all four Mac plans) before `/gsd-verify-work`; CP7-SAVE-C recorded separately as human-verified, never claimed by an automated pass per D-68.

### Wave 0 Gaps
- [ ] `playstead-server/test/playstead/saves_test.exs` — covers SAVE-01, SAVE-04 (lineage DAG, branch-accept-not-reject)
- [ ] `playstead-server/test/playstead_web/controllers/api/v1/saves_controller_test.exs` — covers SAVE-01 (two-endpoint upload/commit split, D-16)
- [ ] `playstead-mac/PlaysteadTests/SavesTests/SaveCapturePollerTests.swift` — covers SAVE-01 (D-01/D-03 polling + quiescence)
- [ ] `playstead-mac/PlaysteadTests/SavesTests/LaunchSavePlannerTests.swift` — covers SAVE-03 (D-44's single testable invariant; the 15 named tests referenced in `discussion-research/F-launch-path-save-readiness.md`)
- [ ] `playstead-mac/PlaysteadTests/SavesTests/SaveConflictResolverTests.swift` — covers SAVE-04 (D-48–D-55; the 20 named tests referenced in `discussion-research/H-save-export-shape.md` cover the adjacent export side)
- [ ] Shared golden-strings fixture (`shared/save-vocabulary.json`, D-67) plus one copy-contract test per side — covers SAVE-02's exhaustiveness assertion
- [ ] No new framework install needed — ExUnit and XCTest are already wired.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-------------------|
| V2 Authentication | yes | Existing device-credential auth (`:device_auth` router pipeline, Phase 1) gates both new save endpoints — no new auth mechanism introduced |
| V3 Session Management | no | Save endpoints use the existing scoped device credential, not a session |
| V4 Access Control | yes | `Playstead.Saves` scoped by `user_id` per P1 D-01's project-wide scoping convention; every context function takes the scope |
| V5 Input Validation | yes | `save_contract` fields decode as Swift `Optional`s (D-24, forward-compat with older pins); server-side Ecto changesets validate `save_kind`/`slot`/digest format; asset-set-id-derived path components go through `PathSafety.validatedFilename` (existing, CR-01/CR-02 precedent already applied to `saveDirectoryURL`) |
| V6 Cryptography | yes | SHA-256 for all content-addressing (blob digest, `Idempotency.fingerprint/1`'s `:crypto.hash(:sha256, ...)`) — existing project-standard primitive, never hand-rolled |
| V8 Data Protection | yes | Save bytes are the one category of data explicitly named as "reconstructable from nowhere" (D-25); CAS + never-evictable + keep-forever (D-28) are the durability controls; `isExcludedFromBackup` fix (D-63) is itself a data-protection correction |
| V13 API and Web Service | yes | RFC 9457 problem+json codes for every new failure mode (`save_binding_incompatible` 422, `save_revision_digest_mismatch` 422, `save_revision_too_large` 413, `save_parent_unknown` 409, `save_branch_limit_exceeded`, `save_revision_immutable`) — reuses `PlaysteadWeb.Problem`/`error_codes.ex`, no new error-shape invention |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|----------------------|
| Path traversal via server-declared or client-declared identifiers (asset-set id, digest) used as filesystem path components | Tampering | Existing `PathSafety.validatedFilename` (Mac) / `Sanitize.component` + `safe_join` (server) — reuse verbatim, do not add a parallel path-building routine for saves |
| Malformed/mismatched save artifact written to a live medium causing the game itself to declare corruption and offer to erase | Tampering / Denial of Service | D-20's hard block with no override affordance — this is a threat mitigation disguised as a UX decision; the compatibility gate is the security control here, not just a feature |
| Divergent-write race enabling silent data loss (one device's only copy overwritten) | Repudiation / Data loss | D-13's accept-and-branch-never-reject-non-fast-forward is the mitigation; a naive 409-reject model is the vulnerability pattern this explicitly avoids |
| Disk-full or low-free-space silently dropping a save write | Denial of Service (self-inflicted) | D-31's named loud-once failure path + D-64's `reserve: :critical` bypass of the general free-space margin |
| Concurrent emulator processes corrupting one shared `.sav` | Tampering (self-inflicted, no adversary needed) | D-65's per-`assetSetID` launch mutex spanning prepare→spawn→exit |
| Idempotency key replay/collision across the two-endpoint upload split | Repudiation | `Idempotency.fingerprint/1`'s canonicalized-body SHA-256, applied to the metadata-commit endpoint only, per D-16's documented reason for the split |

## Project Constraints (from CLAUDE.md)

No `./CLAUDE.md` or `./.claude/CLAUDE.md` was found in the working directory during this research session — no project-level directive file exists to extract constraints from. All applicable constraints for this phase instead come from `04-CONTEXT.md`'s locked decisions (reproduced verbatim below) and the cross-cutting patterns already established by Phases 1–3.5 in `.planning/STATE.md`'s Decisions log (e.g., Phoenix 1.8 scoping conventions, `Compaction.run/0`'s 90-day journal horizon, `ChangeJournal.tombstone/3` as the only sanctioned row-deletion path).

## Sources

### Primary (HIGH confidence)
- `playstead-server/mix.exs` — dependency versions, read directly this session
- `playstead-server/lib/playstead/sync/entity_kind.ex:25` — `save` already a registered `EntityKind`, read directly
- `playstead-server/lib/playstead/idempotency.ex:33-47` — `fingerprint/1` implementation, read directly
- `playstead-server/lib/playstead/blobs/fingerprints.ex:65-76` — `fingerprint_kind/1` GBA-as-nil behavior, read directly
- `playstead-server/lib/playstead/readiness.ex:367-373` — `required_bytes/2` margin formula, read directly
- `playstead-server/lib/playstead/blobs/store/local_disk.ex:37` — `open_write/1` current single-arity signature, read directly
- `playstead-server/lib/playstead/export/layout.ex:123`, `sidecar.ex:22-35,50`, `sanitize.ex:60-79` — reserved `saves` slot and collision guard, read directly
- `playstead-mac/Playstead/App/AppPaths.swift:39-58` — `excludeRootFromBackup`, applied to root only (the D-63 defect), read directly
- `playstead-mac/Playstead/App/PlaysteadApp.swift:681-706` — `saveDirectoryURL(forAssetSetID:)`, read directly
- `playstead-mac/Playstead/Adapter/AdapterHost.swift:29-79` — `AdapterProcessRegistry`, no per-assetSetID exclusion (the D-65 gap), read directly
- `.planning/phases/04-persistent-save-continuity/04-CONTEXT.md` — the phase's synthesized multi-agent research (68 decisions), read in full this session

### Secondary (MEDIUM confidence)
- `.planning/phases/04-persistent-save-continuity/discussion-research/*.md` (A through H, plus 00-BRIEF.md) — cited by CONTEXT.md as containing full option tables and prior-art URLs; not independently re-opened this session since CONTEXT.md's synthesis already supersedes them for planning purposes and the phase's own instruction is not to re-litigate
- `.planning/phases/03-mac-offline-play-vertical-slice/03-SPIKE-REPORT.md` §"Save Contract" — cited for the ~24s flush cadence and SIGTERM-equals-crash finding; not re-read in full this session, relied on via CONTEXT.md's summary

### Tertiary (LOW confidence)
- mGBA's `src/gba/savedata.c` mmap-backed store characterization — training-knowledge-level familiarity with mGBA's architecture, not re-verified against current mGBA source this session (see Assumptions Log A2)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; existing versions read directly from `mix.exs`
- Architecture: HIGH — CONTEXT.md's 68 decisions are themselves an adversarially-reviewed synthesis of an eight-agent research fan-out with prior-art citations; this session independently verified every load-bearing in-repo code claim it cites
- Pitfalls: HIGH — every pitfall above traces to a named, arbitrated decision in CONTEXT.md, several with explicit "why this is wrong" rationale already documented
- Package legitimacy: N/A (HIGH confidence in the "no new packages" finding) — confirmed no new dependency lines appear anywhere in the phase's decisions

**Research date:** 2026-09-03
**Valid until:** Effectively pinned to this phase's execution window — the underlying decisions are locked (many marked one-way/costly to reverse); revisit only if Phase 4 execution surfaces a genuine conflict with a locked decision, not on a calendar basis.
