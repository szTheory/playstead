# Phase 4: Persistent Save Continuity - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-03
**Phase:** 4-persistent-save-continuity
**Areas discussed:** Capture trigger & loss window, Lineage & conflict detection, Restore compatibility gate, Retention & storage siting, Save state surfacing vs. status ladder, Launch-path save readiness, Conflict resolution UX, Save export shape

---

## Discussion Method

The owner selected **all eight** gray areas and requested a multi-lens research fan-out rather than an interactive question-by-question discussion, with the instruction to "think deeply, one-shot a perfect set of recommendations so I don't have to think", with all recommendations coherent with each other, and with breadth and depth across every relevant stakeholder-role lens plus an adversarial pass per area.

Eight `gsd-advisor-researcher` agents ran in parallel, one per decision area, each working from a shared 243-line brief (`discussion-research/00-BRIEF.md`) carrying the phase boundary, the Phase 3 adapter-spike constraints, every locked prior decision, the design authority, and the forward-compatibility seeds — so that recommendations could be checked for mutual coherence rather than being eight local optima. Each agent was required to apply a named lens set (software architecture, distributed systems, Elixir/OTP/Phoenix/Ecto idiom, Swift/macOS, filesystem durability, security, SRE, product/JTBD, UI/UX and creative direction, accessibility, performance, verification, adversarial), research named prior art online, produce an options table with reversibility ratings, run an adversarial pass on its own leading recommendation, and flag collisions against the other seven areas.

**Interpretation note:** the request referenced "our prompts subdir" and a "brandbook". No `prompts/` subdirectory exists in this repository (the only one on the machine belongs to an unrelated project). These were mapped to the Playstead equivalents — `.planning/discovery/` with `EXPERIENCE-ETHOS.md` as the brand book, `.planning/research/`, `03-UI-SPEC.md`, and `playstead-mac/Playstead/Design/*.swift`. Recorded here so the substitution is auditable rather than silent.

---

## Area A — Capture Trigger and Loss Window

| Option | Description | Selected |
|--------|-------------|----------|
| FSEvents / vnode watch | Kernel event-driven capture | |
| `NSFileCoordinator` / `NSFilePresenter` | Coordinated-access API | |
| Periodic digest polling | Read-and-hash on a fixed cadence | ✓ |
| Post-exit only | Capture once the emulator process dies | |
| Hybrid mid-play + post-exit | Rolling staged capture, promoted at session end | ✓ (as tiering) |

**Outcome:** 1 Hz read-and-hash polling during play only, with a two-tier staged/promoted model and an unconditional post-exit settle pass.
**Notes:** Polling won on the argument that it is the exact instrument that produced the phase's 24 s constraint. The commonly cited "FSEvents misses mmap writes" claim was checked and found to be documented for inotify/fanotify, not FSEvents — unmeasured either way, so probe SAVE-P1 was added rather than inheriting folklore. The agent also established that the Phase 3 spike's raw artifacts are gitignored and gone, making mtime fidelity and inode stability *unproven* rather than merely unanalysed.

---

## Area B — Lineage and Conflict Detection Model

| Option | Description | Selected |
|--------|-------------|----------|
| Parent-pointer immutable DAG | Git-shaped; each revision names its parent | ✓ |
| Per-device vector / Lamport clocks | Causality via counters | |
| Server fast-forward-only + client branch | 409 on non-fast-forward | |
| CRDT | Convergent replicated register | |

**Outcome:** Parent-pointer DAG, accept-and-branch on the server, no automatic winner.
**Notes:** Vector clocks rejected for per-device GC state and inability to express restore-then-play. CRDTs rejected because for an opaque binary register they degrade to either LWW (forbidden by SAVE-04) or an MV-register, which is siblings with more machinery and less history. Fast-forward-rejection was rejected because it strands the losing side's only durable copy on a client. CouchDB's deterministic-winner rule was studied and explicitly rejected.

---

## Area C — Restore Compatibility Gate

| Option | Description | Selected |
|--------|-------------|----------|
| Byte-exact ROM match only | Restore only onto the identical dump | |
| Title-level match | Restore across any dump of the same game | |
| Three tiers (`exact` / `same_title` / `incompatible`) | Graded, with different affordances per tier | ✓ |
| Emulator/core-version gating | Bind saves to the emulator that wrote them | |

**Outcome:** Three tiers; emulator and core version recorded as provenance only, never gating; save-medium mismatch is a hard block with no override.
**Notes:** The decisive domain fact is that a GBA battery save is written by the *game*, not the emulator, so emulator-version gating is save-*state* thinking misapplied. The hard block exists because a mismatched medium leads the game itself to declare the save corrupt and offer to erase it — a destructive action taken by software Playstead does not control, which a warning cannot mitigate. A grep finding changed the design: `Blobs.Fingerprints.fingerprint_kind/1` returns `nil` for GBA, so for the only shipped system content identity *is* byte identity.

---

## Area D — Retention, Dedupe, and Storage Siting

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse the Phase 2 server CAS | Saves share the immutable blob store | ✓ |
| Separate saves store | Distinct store with distinct semantics | |
| Keep everything forever | No prune, no TTL | ✓ |
| Keep-all with eventual compaction | Prune under a policy | |
| Saves count against the 25 GB quota | Treated like cache bytes | |
| Saves outside the quota + reserve | Exempt, plus reserved headroom | ✓ |

**Outcome:** Server CAS, keep everything forever, outside the quota with a 256 MiB reserve, never evictable.
**Notes:** The asymmetry that drove the answer: game bytes are reconstructable from the user's own media in the worst case; save bytes are reconstructable from nowhere. Nintendo Switch Online's 180-day deletion policy and the resulting backlash was the documented counter-example against any TTL.

---

## Area E — Save State Surfacing vs. the Status Ladder

| Option | Description | Selected |
|--------|-------------|----------|
| Save states join the card's status ladder | New rungs on the frozen ladder | |
| Dedicated save surface only; card untouched | All six states live elsewhere | ✓ (mostly) |
| One narrow card affordance + dedicated surface | Only `conflicted` competes for the slot | ✓ |
| New top-level sidebar noun | "Saves" as a peer of Favorites/Collections | |

**Outcome:** The card is a router, not an explainer; only `conflicted` reaches it, via the existing rank-1 attention rung with no new token and therefore no snapshot rebaseline. Save history is a per-game sheet; no new sidebar noun.
**Notes:** The area's central insight is that the premise contained a category error — SAVE-02 is a per-revision requirement and a card is a per-game object — so the collision dissolved rather than needing a trade. Two grep findings decided the rest: `ReadinessCheckKind` already contains `saveDirectory`, and EXPERIENCE-ETHOS's shipped "Ready to Play" contract already specifies a Save row.

---

## Area F — Launch-Path Save Readiness

| Option | Description | Selected |
|--------|-------------|----------|
| Seventh blocking readiness check | Save state gates Play | |
| Seventh warning-only check | Advisory, never blocking | |
| No new check; widen existing `saveDirectory` | Strengthen a check that already exists | ✓ |
| Silent auto-restore on clean Mac | No prompt when local state is empty | ✓ |
| Prompt before restoring | Ask every time | |
| Block Play when diverged | Force resolution first | |

**Outcome:** No blocking save check beyond a widened `saveDirectory`; silent auto-restore gated on emptiness; divergence never blocks Play and playing never resolves anything.
**Notes:** The argument that carried it: a check that is green on virtually every launch is an alarm, not readiness, and "no save = start fresh" is a correct outcome rather than an error. The area produced the phase's governing invariant (CONTEXT D-44). It also found two shipped-code facts: `LaunchMaterializer.materialize` removes the entire launch directory each launch, and `AdapterProcessRegistry` tracks but does not exclude concurrent processes.

---

## Area G — Conflict Resolution UX

| Option | Description | Selected |
|--------|-------------|----------|
| Pick a winner; loser retained as a branch | Head moves, loser inspectable | |
| Resolution appends a new revision naming both parents | Resolution is itself immutable | ✓ |
| Both sides continue as separate named save lines | "Resolve" means "pick which line this device follows" | |
| Launch-time modal (the Steam shape) | Ask at the moment of play | |
| Attention-inbox item + comparison sheet | Un-missable but non-interrupting | ✓ |

**Outcome:** Resolution appends a revision naming all divergent heads; no recommended side, no confirmation dialog, no Undo control; "Keep both" is a first-class peer; nothing is ever deleted.
**Notes:** Steam's conflict dialog was studied as the canonical example of both what to copy and what to avoid — its file-size display is useless here (every side is exactly 32,768 bytes) and its confirmation flow is documented as training click-through. Play-time-since-split was identified as the only available fact correlating with value rather than ordering. The word "conflict" was banned from player-facing copy.

---

## Area H — Save Export Shape

| Option | Description | Selected |
|--------|-------------|----------|
| `saves/` inside each game's set folder | Fill the Phase 2 reservation | ✓ |
| Parallel top-level saves tree | Separate hierarchy | |
| Export current revision only | One file per game | |
| Export all revisions (two-tier interior) | Full history, default `:all` | ✓ |
| Drop-in compatible `.sav` copy | Immediately usable with another emulator | ✓ (except when diverged) |

**Outcome:** Fill the existing reservation; two-tier interior defaulting to all revisions; drop-in copy named from the original basename, and **never** produced for a diverged slot.
**Notes:** Question 1 turned out not to be open — Phase 2 shipped three live reservations (`layout.ex:123`, `sidecar.ex:32,50`, `sanitize.ex:77`) that P2 D-39 declared one-way. The agent redirected its budget to what was genuinely open. Ludusavi's layout was studied as the closest prior art; the agent noted it chose Phase-2 consistency over Ludusavi's Finder-proximity for `saves.txt` placement and flagged that as the weakest point of its own recommendation.

---

## Cross-Area Arbitration

Seven collisions were arbitrated at synthesis rather than left to the planner. Full reasoning is inline in CONTEXT.md as **[Arbitration]** notes.

| Collision | Positions | Ruling |
|---|---|---|
| Seventh readiness check | C: warning-only check · E: needed as save-history entry point · F: no seventh concept at all | Navigational Save row, never blocking; F's objection honoured — the only blocking save condition is the widened `saveDirectory` check |
| Widening `Attention.Reason` | G: one additive member · C and E: refuse, it is frozen and import-scoped | Not widened; a saves-owned attention source feeds the inbox and the card's rank-1 rung |
| Divergence noun | E: "Two versions of this save" · G: "Two versions of your progress" | G's noun for headings and rollups; E's "Separate version" survives as the per-row label |
| Revision digest identity | A: artifact-set manifest digest · C/D/H: raw artifact sha256 | Raw sha256 is the key for dedupe, export names, and the compatibility gate; manifest digest recorded alongside for the multi-artifact future |
| Revision-per-capture | A: one promoted per session · B/D: byte-identical child collapses | Both hold — A is the client promotion policy, D is the server commit invariant |
| Save-line identity vs. cross-dump restore | B: line keyed on ROM sha256 · C: `same_title` tier across dumps | `same_title` is an explicit cross-line restore creating a child on the target line |
| Client CAS vs. Time Machine | A: warned against putting saves in the CAS tree · D: server CAS | No real conflict — A's concern was the client backup boundary, D's siting is server-side |

---

## Defects Found During Research

Three shipped defects were found by agents grepping the codebase, none of which were the object of any question:

- **Time Machine exclusion boundary** (`App/AppPaths.swift:39,51-58`) — found independently by **three of eight** agents. The exclusion is set on the Application Support root and inherits to `saves/` and `playstead.sqlite3`.
- **Free-space reservation refuses save uploads** (`Readiness.required_bytes/2`) — a 32 KB save is refused with 507 whenever the blob volume is under ~1 GiB free.
- **No launch mutual exclusion** (`AdapterProcessRegistry`) — tracks processes but does not exclude them.

Each independently blocks a Phase 4 success criterion, so all three were folded into scope as gap closure (CONTEXT D-63, D-64, D-65) rather than deferred.

Also noted, not folded: `02-CONTEXT.md` D-34 is stale against shipped export code (`playstead-manifest.json`/`_unsorted`/`_quarantined` vs. the shipped `playstead-bag.json`/`unsorted`/`quarantine`).

---

## Claude's Discretion

Recorded in CONTEXT.md `<decisions>` → "Claude's Discretion": Swift type and test-helper naming; client SQLite schema and migration mechanics; the polling actor's structure; Phoenix/Ecto naming, migration sequencing, and `Ecto.Multi` composition; glyph selection within the zero-new-colour-literals rule; `branch_key` encoding, `seq` allocation, and `digest8` length; whether the save upload lane is a distinct actor or a priority band; probe SAVE-P1's harness shape; and retry/backoff, TTL, and sweep cadences.

## Deferred Ideas

Recorded in CONTEXT.md `<deferred>`: save curation (SEED-001); save states / SAVE-05 (SEED-019); cartridge save read/write (SEED-002, SEED-010); save-progress screenshots (SEED-006); memory-card explorer (SEED-012); save reimport; retention pruning; a rebuild-from-`saves/objects` index recovery path; multi-slot and directory-shaped saves; and the stale `02-CONTEXT.md` D-34 docs fix.

Explicitly **rejected** rather than deferred: automatic conflict resolution and any "always prefer this Mac" bulk preference — CONTEXT D-51 refuses these and asserts their absence by test.
