# Phase 3: Mac Offline Play Vertical Slice - Research

**Researched:** 2026-08-30
**Domain:** Native macOS client (SwiftUI/AppKit) + Phoenix additive protocol hardening (Range/curation journal) + external-process emulator adapter
**Confidence:** MEDIUM — HIGH on server-side Elixir/Phoenix patterns (verified against live code); MEDIUM on Swift/macOS APIs (CITED from Apple docs, not yet exercised in this repo); the adapter spike itself is explicitly an empirical unknown (D-01/D-03) that this research cannot resolve in advance.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

All from `.planning/phases/03-mac-offline-play-vertical-slice/03-CONTEXT.md`, approved 2026-08-30. Full option tables and adversarial passes live in `discussion-research/A-D`.

**Adapter spike and first emulator**
- D-01: Adapter spike is Phase 3's opening plan (before other Mac work is planned in detail). Seven pass/fail probes: (1) notarized launch, (2) config injection, (3) save-flush observability incl. `kill -9`, (4) exit detection/recovery, (5) controller unplug/reconnect, (6) Keychain access, (7) BIOS-less + drag-in BIOS launch. Outputs: SPIKE-REPORT, `(system, emulator, version, sha256)` pin, adapter save contract. Any "Open Anyway" requirement is a FAIL; report records exact macOS build tested.
- D-02: Candidate ladder — mGBA standalone external process (primary) → RetroArch+mGBA core → SameBoy/Gambatte (GB/GBC) → RetroArch+SNES core → posture reassessment. Snes9x standalone disqualified (non-commercial license). Probe against the shipped `mGBA.app` binary via portable-mode `config.ini`. Homebrew test title must demonstrably write SRAM.
- D-03: **Owner ruling — periodic flush required.** A candidate passes the save probe only if an on-disk flush can be observed periodically or on-demand during play, not solely at clean exit. If mGBA standalone can't demonstrate this, RetroArch+mGBA wins even if mGBA passes everything else.
- D-04: Distribution posture — **Developer ID direct, notarized, hardened runtime, NOT App-Sandboxed.** Sandbox breaks launching a downloaded third-party emulator (child inherits sandbox). Reversibility: costly.
- D-05: Emulator install model — **download-on-demand from official upstream releases, version-pinned + SHA-256-verified**, into an app-managed directory (PLAY-01's "install"); "select existing install" is a hash-badged secondary path. Never bundle inside Playstead.app v1; never strip quarantine xattrs.
- D-06: BIOS posture — ship on **mGBA's built-in HLE BIOS by default**; PLAY-03 drag-in validates official `gba_bios.bin` by size+digest via the Phase 2 DAT hash-match primitive; open BIOS replacements undeclared in v1.

**Curation ownership and sync**
- D-07: All five curation nouns (Favorites, Collections, Continue, Recent, queue) are **server-canonical, per-user, synced**. Queue = backlog, never a per-device playback buffer. Recent/Continue derive from `POST /api/v1/play-sessions` (UUIDv7 id, game, start/end only) — queued in Mac outbox, deletable, **never on the launch path**.
- D-08: Add **one new `curation` change-journal entity kind** (payload `type` ∈ favorite | collection | collection_member | queue_item | continue_dismissal | recent) + a `curation` snapshot branch, riding the P1 D-21 recovery spine. Explicit, logged additive amendment to the frozen Phase 1 entity-kind set; must land before the first client ships. Never stuffed into the frozen P2 D-23 `catalogue` payload. Reversibility: one-way — additions only, never renames.
- D-09: Mutations are per-row REST intents with `Idempotency-Key` + client UUIDv7 natural keys (P1 D-20). Conflict semantics: **LWW-per-row** for favorites/collection membership; **fractional-index positions with server rebalance** for queue/collection ordering. Invariant: no client ever transmits a whole list as truth. Drag reorders coalesce into one settled position command.
- D-10: Manual, flat, **ordered** collections (same fractional-position mechanism as queue). Recently Added/per-system/Continue/Recent are built-in derived views, not stored smart collections. One queue per user. Reuse P2 D-22 name sanitization. Caps: 500 collections / 5k members per collection / 500 queue items.
- D-11: Console parity — LiveView ships all five shelves with full curation in Phase 3, via the same context functions as the API. Mac adds launch/preflight integration and availability badges on top.

**Library experience without artwork**
- D-12: Typographic-first visual identity: per-system accent color + system monogram tiles, landscape ratio, horizontal shelves + sortable list. No procedural fake box art, no per-title hash colors.
- D-13: Card anatomy — three zones: dominant two-line title; meta line (system monogram + region/version chips + "Not yet identified" badge); exactly one status slot on a strict priority ladder: attention > missing dependency > downloading (determinate ring) > queued > verified/pinned > server-only. Safe-to-evict is storage-view-only, never a card badge. No state is color-only (QUAL-01/WCAG 1.4.1).
- D-14: Mac source-list sidebar order: Home/Continue, Favorites, Collections, Queue, Recent, then non-empty Systems, Unidentified last — 1:1 with responsive LiveView sidebar. Controller: d-pad spatial focus via `.focusSection()` per shelf, LB/RB shoulder-cycling of sidebar sections, Menu-button context sheet. Search on controller = d-pad filter chips; no on-screen keyboard in Phase 3.
- D-15: Newly paired Mac is not empty — full catalogue renders immediately with cloud marks, one dismissible banner, small recommended-first-downloads shelf that never auto-downloads. Zero-import server shows one calm import invitation. Empty curation shelves hidden from Home but sidebar nouns remain with one-line explainers. LIBR-04: empty systems hide behind "Show all systems" with counts.
- D-16: Motion only where it explains state — determinate progress ring morphing to verified check, ~120ms directional focus ring, in-place crossfade to cloud mark on eviction (items never vanish). No ambient tile motion/staggered fly-ins/marquee. Reduced motion keeps ring fill, swaps morphs for instant/crossfade. Zero skeletons on synced views; fixed tile heights, `LazyVGrid`/LiveView streams for 500+ items (interactive < 1s cold).
- D-17: Status-glyph vocabulary, priority ladder, IA noun order, and empty-state copy live in **one shared spec both clients cite** — requires a UI-SPEC pass (`/gsd-ui-phase 3`) before implementation. Server-only card's primary action is **Download**, never a disabled Play.

**Cache and download semantics**
- D-18: Transfer — whole-blob GET with single-range resume (`Range: bytes=N-` + `If-Range: "<sha256>"`) via an **in-process URLSession actor** (not `URLSessionDownloadTask` background sessions). Sequential members, one game at a time; infinite backoff retry. Resume re-hashes the partial prefix from disk (disk-as-truth); full-hash verify → rename-commit into local CAS. Client hard-checks for 200-instead-of-206 on resume and truncates/restarts.
- D-19: Server's Range contract **deliberately frozen as protocol** this phase: quoted strong `ETag: "<sha256>"` (current controller emits unquoted — fix it), `Accept-Ranges: bytes`, single-range 206 with correct `Content-Range` served through the P2 D-12 `stream/2` seam (not `send_chunked`), `If-Range`, 416, HEAD, identity encoding only, multi-range collapsed to full 200. Contract tests including a kill-and-resume byte-identity test. `range-resume` advertised in the `transfer` capability namespace. Reversibility: one-way.
- D-20: Mac cache layout — sha256 CAS mirroring server's P2 D-11 layout under `~/Library/Application Support/Playstead/` (Time-Machine-excluded), per-game launch directories materialized via APFS `clonefile` (plain copy fallback, **never hardlink**). `~/Library/Caches/` rejected (OS-purgeable, breaks pinned-offline promise). Reversibility: costly.
- D-21: Capacity policy — fixed quota (default 25GB) + free-space floor (10GB; floor wins). At limit, downloads block/pause with honest reclaim prompt — **no silent deletion ever**; eviction manual-only in Phase 3 with LRU-ordered suggestions. Pin is per-game = never evictable + queue priority. Six CACH-02 states derived at read time from (queue row, partial file, CAS entry, pin flag) — never a stored enum.
- D-22: Download queue — persistent, user-visible, ordered (local SQLite, UUIDv7 ids), sequential by default, per-item pause/resume/cancel/reorder, auto-resume on reachability; queued-while-offline is quiet normal state.
- D-23: Verification lifecycle — full hash at download completion is authority. Launch preflight trusts it through cheap size+inode+mtime check, falling back to full re-hash on mismatch — **zero network calls** (CACH-04). No periodic scrub in Phase 3. Corruption → quarantine + automatic redownload with no-blame copy.

### Claude's Discretion

- SwiftUI app architecture, module layout, and local persistence library choice (SQLite wrapper etc.), provided queue/cache state derivation rules hold.
- Phoenix schema/table naming, curation REST route shapes, fractional-index encoding, and rebalance mechanics — follow idiomatic Phoenix 1.8 and P1/P2 conventions.
- Exact glyphs, accent palette values, and type scale within the two-vocabulary and non-color-only rules — the UI-SPEC pass refines these.
- Spike homebrew test-title selection (must verifiably write SRAM) and SPIKE-REPORT format.
- Exact quota/reclaim microcopy within the honesty rules (D-21, EXPERIENCE-ETHOS).
- Whether play-session events batch or post individually from the outbox.

### Deferred Ideas (OUT OF SCOPE)

- Auto-evict / LRU automatic eviction — v2, after manual eviction proves the trust model.
- Periodic local cache scrub / "verify everything" — Phase 5 (aligns with OPER-03/PORT-03 server scrub).
- On-screen keyboard for controller text search — later; Phase 3 controller search is filter chips.
- Stored smart collections (rule-based) — v2; Phase 3 ships derived views only.
- Open BIOS replacement declarations (e.g. Cult-of-GBA) — v1 ships HLE default; per-system legal review later.
- Sparkle auto-update for the Mac app — later phase; posture (D-04) keeps it possible.
- Background URLSession transfers / chunked or content-defined-chunking transfer, tus/multipart — TRAN-01 (v2) under the `transfer` capability.
- Metadata/artwork providers — META-01 (v2).
- Household sharing of collections/queues — v2.
- Second client/adapter, browser play — separate later spikes.
- Play-event analytics beyond Recent/Continue derivation — v2 curation.
- Persistent-save capture/sync/restore — Phase 4 (but the spike must prove the save-flush contract Phase 4 builds on).
- Backup/health/upgrade tooling — Phase 5.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| LIBR-01 | Browse complete server catalogue before downloading bytes | `Playstead.Catalogue.list_assets/2` already exists (verified below); Mac client renders it read-only from local snapshot on first pair |
| LIBR-02 | Search/filter/systems/availability quick-find | Filter-chip pattern (D-14); list-view sort/type-select (discussion-research C) |
| LIBR-03 | Curate Favorites/Collections/Continue/Recent/queue without altering canonical bytes | D-07…D-11, new `curation` journal kind, fractional-index ordering |
| LIBR-04 | Empty/unconfigured systems hidden by default; contextual setup surfaces | D-15, "Show all systems" pattern |
| LIBR-05 | Console parity — same canonical library/import/pairing/job views, no native install required | D-11, `library_live.ex` extension |
| CACH-01 | Choose game/collection for download; resume interrupted transfer w/o restarting verified ranges | D-18, in-process URLSession actor, disk-as-truth re-hash-on-resume |
| CACH-02 | Distinguish server-only/queued/partial/verified-local/pinned-offline/safe-to-evict | D-21 derived-state model |
| CACH-03 | Capacity policy, pin, reclaim reconstructable-only bytes | D-21 quota+floor+manual eviction |
| CACH-04 | Launch only after every required member verifies locally; fully offline afterward | D-23 preflight gate, zero network calls |
| PLAY-01 | Install/select one Mac adapter; see exact system/emulator/version/content/BIOS/save support | D-01/D-02/D-05/D-06, PLAY-01 capability card |
| PLAY-02 | Preflight readiness with concrete remedy per blocking condition | Spike probes feed the preflight state machine |
| PLAY-03 | Drag-in BIOS validation; no acquisition/distribution path; open-replacement recognition where supported | D-06 |
| PLAY-04 | Controller connect/test/assign/remap/reset/recover; keyboard/pointer/AT fallbacks retained | D-01 probe 5, Game Controller framework (below) |
| PLAY-05 | Launch/exit/relaunch one legally testable game from signed/notarized build after app/server restart | D-01 probes 1+4, notarization workflow (below) |
| QUAL-01 | Controller/keyboard/pointer/screen-reader/focus/reduced-motion parity everywhere | D-14/D-16, Validation Architecture below |
</phase_requirements>

## Summary

Phase 3 has two structurally different halves that the planner must sequence and staff differently. The **adapter spike** (D-01) is an empirical, single-machine, mostly-scripted investigation of mGBA/RetroArch behavior on a real notarized macOS build — it produces a report and a pinned `(system, emulator, version, sha256)` combo that every later Mac plan depends on, and it cannot be parallelized away or estimated by reading documentation alone. The **application build** (library browse, curation sync, cache/download engine, preflight, controller mapping, notarized launch chrome) is conventional SwiftUI/Foundation engineering plus a well-scoped, additive Phoenix change (one new journal entity kind, a hardened Range contract on an existing controller). Four upstream discussion-research documents (`discussion-research/A-D`) already carry option tables, adversarial passes, and prior-art citations for every locked decision — this document does not re-derive those; it adds exact code seams verified against the live repo, exact Apple APIs for the client-side work, and the pitfalls/validation architecture the planner needs that the discussion docs (written before implementation) could not verify against code.

Three load-bearing facts, verified by reading the source this session: (1) `Playstead.Sync.EntityKind` is `~w(device pairing catalogue job transfer save)a` with **no `curation` kind** — D-08's addition is real, not hypothetical; (2) `Playstead.Blobs.Store.LocalDisk.stream/2`'s current range branch calls `File.read!(path)` (loads the **entire file** into memory) before slicing — this is a correctness/memory landmine for PSX-sized (multi-hundred-MB) blobs that D-19's hardening plan must explicitly fix, not just add headers around; (3) `Playstead.Blobs.Store` behaviour's `stream/2` callback already accepts a `range :: Range.t() | nil` argument, so the seam exists — the controller just doesn't wire Range-header parsing to it yet, and `BlobsController` doesn't emit an `ETag` with quotes (`put_resp_header("etag", sha256)` — unquoted, confirmed).

**Primary recommendation:** Plan the adapter spike as an isolated Wave-0/1 plan whose sole output is `03-SPIKE-REPORT.md` + the pinned adapter contract; gate every adapter-touching plan (preflight, launch chrome, controller mapping, BIOS validation) behind it, while curation-journal, Range-contract-hardening, and library-browse plans proceed in parallel since they don't depend on spike results.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Catalogue browse (LIBR-01/02/04) | API/Backend (Phoenix context) | Browser/Client (Mac local read model) | `Catalogue.list_assets/2` is canonical; Mac renders from its synced snapshot, never a live query |
| Curation mutations (LIBR-03) | API/Backend | Client (SwiftUI + LiveView, same context fns) | Server-canonical per D-07; both clients call identical context functions (house rule) |
| Curation read/sync | API/Backend (journal + snapshot) | Client (local SQLite mirror) | Rides P1 D-21 recovery spine; Mac never invents its own reconciliation |
| Console library UI (LIBR-05) | Frontend Server (LiveView/SSR) | — | LiveView is first-party, never protocol (P1 house rule) |
| Blob transfer + Range contract (CACH-01) | API/Backend (Phoenix controller) | Client (download engine) | Server owns the wire contract (frozen this phase); client owns resume/retry/hash logic |
| Local cache CAS + eviction (CACH-02/03) | Client (Mac filesystem) | — | Entirely client-local; server has no visibility into client disk state |
| Launch preflight gate (CACH-04, PLAY-02) | Client | — | Must work fully offline — zero network calls is the contract |
| Emulator adapter process (PLAY-01/05) | Client (external process host) | — | Notarized non-sandboxed Mac process spawning a separate signed binary |
| BIOS validation (PLAY-03) | Client | API/Backend (DAT hash-match primitive, reused not re-served) | Digest comparison is local; the hash-match table itself may originate server-side per Phase 2 |
| Controller input (PLAY-04) | Client (Game Controller framework) | — | OS-level API, no server involvement |
| Play-session reporting (D-07) | Client (outbox) | API/Backend (durable receipt) | Coarse events only; never gates launch |
| Accessibility/motion (QUAL-01) | Client + Frontend Server | — | Both SwiftUI and LiveView independently implement the shared spec (D-17) |

## Standard Stack

### Core (server-side — no new dependencies)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| phoenix | ~> 1.8.13 | Web/API framework | Already the project's framework; `[VERIFIED: mix.exs]` |
| ecto_sql | ~> 3.14.0 | DB access, journal/snapshot writes | Existing dependency `[VERIFIED: mix.exs]` |
| oban | ~> 2.24 | Durable jobs (not newly needed this phase, but curation/session writes ride existing transactional patterns) | Existing dependency `[VERIFIED: mix.exs]` |

No new Elixir/Hex dependencies are required for Phase 3 — the Range-contract hardening and curation journal kind are additive changes to existing modules (`BlobsController`, `Blobs.Store.LocalDisk`, `Sync.EntityKind`, `Sync.Snapshot`), not new libraries. `[VERIFIED: playstead-server/mix.exs]`

### Core (Mac client — greenfield, choices below are Claude's Discretion per CONTEXT.md)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundation `URLSession` | OS-provided | In-process HTTP transfer with custom Range headers (D-18) | Apple's own guidance says background-session resume machinery ignores custom Range headers — see Pitfall below `[CITED: developer.apple.com/forums/thread/47460]` |
| GameController framework | OS-provided | Controller connect/disconnect/input (PLAY-04) | Native, no third-party mapping library needed for a single MFi/HID-class controller path `[CITED: developer.apple.com/documentation/gamecontroller]` |
| Security framework (Keychain Services) | OS-provided | Credential storage, already used for P1 D-07 pairing credential; Phase 3 reuses unchanged | `[CITED: P1 CONTEXT.md D-07]` |
| CryptoKit | OS-provided | SHA-256 incremental hashing for verify/resume | `[ASSUMED — CryptoKit's `SHA256` supports incremental `update(bufferPointer:)`; confirm exact streaming API during implementation, not yet exercised in this repo]` |

### Supporting (Mac client — local persistence, one required, exact choice is discretion)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| GRDB.swift (groue/GRDB.swift) | current stable | SQLite wrapper for local read-model mirror + outbox + download queue | If the team wants Swift-native query building, migrations, and observation (`ValueObservation`) over raw SQLite |
| SQLite.swift (stephencelis/SQLite.swift) | current stable | Lighter SQLite wrapper | If a thinner, more direct SQL surface is preferred |
| SwiftData | OS-provided (macOS 14+) | Apple-native persistence | Only if the target macOS floor and the team's comfort with SwiftData's newer, less battle-tested migration story are acceptable — the discussion-research explicitly leaves this open |

**Package name provenance note:** GRDB.swift and SQLite.swift are named from training knowledge / general ecosystem familiarity, not verified via Context7 or an authoritative source this session — both tags are `[ASSUMED]`. This phase's package-legitimacy gate (npm/pypi/cargo-oriented) does not cover Swift Package Manager; the planner should treat any SPM dependency pin as requiring a `checkpoint:human-verify` task (confirm the exact GitHub org/repo, current tag, and that it still builds for the target Swift toolchain) before first use, per the spirit of the legitimacy gate even though the tooling doesn't natively check SPM.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| In-process URLSession actor | `URLSessionDownloadTask` background session | Rejected — resume ignores custom Range headers, OS can purge temp files, resumeData is opaque `[CITED: discussion-research/D §Transfer mechanics]` |
| mGBA standalone (primary) | RetroArch + mGBA core | Fallback only if flush-observability probe fails (D-03 owner ruling) |
| sha256 CAS + clonefile | Per-game folders only (no CAS) | Rejected — no dedupe, emulator could corrupt verified bytes in place |
| Fractional-index ordering | Full-list overwrite LWW | Rejected — the one scheme that can silently drop a concurrent offline addition |
| Fractional-index ordering | Ordered-list CRDT (RGA/Logoot) | Rejected as overkill — Google-Docs-grade machinery for a list of dozens of games |

**Installation:** No `npm install`/`mix deps.get` additions required server-side. Mac client SPM dependencies (if any chosen) are added via Xcode's Swift Package Manager UI or `Package.swift`; exact command depends on the greenfield project's package manifest, created in this phase.

**Version verification:** N/A for server (no new deps). For any Mac client SPM package selected during planning, verify current tag/commit via the package's GitHub releases page before pinning — training-data versions for Swift packages are unreliable and this ecosystem has no `npm view`-equivalent single command; use `WebFetch` on the repo's releases page.

## Package Legitimacy Audit

No new Hex/npm/pypi/cargo packages are introduced by this phase's server-side work — all server changes are additive modifications to existing modules within `playstead_server` using already-present dependencies (`[VERIFIED: playstead-server/mix.exs]`, read in full this session).

Mac-client Swift Package Manager dependencies (SQLite wrapper) are Claude's Discretion and not yet selected; the ecosystem-specific `npm view`/`pip index versions`/`cargo search` commands in the Package Legitimacy Gate do not apply to SPM. **Disposition:** the planner must gate the actual SPM dependency addition behind a `checkpoint:human-verify` task that confirms (a) the exact GitHub org/repo and current release tag, (b) it is still maintained (recent commits/releases), and (c) no unexpected build-time scripts. This is a process substitute for the automated legitimacy check this phase's tooling cannot run against SPM.

**Packages removed due to [SLOP] verdict:** none (no packages checked — none proposed with sufficient specificity to check).
**Packages flagged as suspicious [SUS]:** none formally checked; treat any SPM addition as requiring manual verification per above.

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────── Mac Client (SwiftUI + AppKit) ───────────────────────────┐
│                                                                                        │
│  Pairing/Keychain (P1, unchanged)                                                    │
│         │                                                                             │
│         ▼                                                                             │
│  ┌─────────────┐   snapshot+cursor (P1 D-21)   ┌───────────────────────────────┐    │
│  │ Sync Engine  │◄──────────────────────────────┤ Local read models (SQLite)    │    │
│  │ (poll /changes│  device/pairing/catalogue/    │ - catalogue mirror            │    │
│  │  + /snapshot)│  curation kinds                │ - curation mirror              │    │
│  └──────┬───────┘                                │ - download queue (own table)  │    │
│         │  outbox (queued command replay)         │ - CAS verify records          │    │
│         ▼                                         └───────────────┬────────────────┘    │
│  ┌─────────────┐  Idempotency-Key + UUIDv7        │                │                    │
│  │ Curation      │─────────────────────────►  REST (favorites,     │                    │
│  │ mutations UI  │                            collections, queue)   │                    │
│  └─────────────┘                                                    │                    │
│                                                                       ▼                    │
│  ┌──────────────────┐   Range GET + If-Range     ┌──────────────────────────┐            │
│  │ Download Engine    │─────────────────────────►│ Blob CAS on disk           │            │
│  │ (URLSession actor)│  disk-as-truth resume       │ ~/Library/Application     │            │
│  └─────────┬──────────┘                            │ Support/Playstead/objects │            │
│            │ verify → rename-commit                 └────────────┬──────────────┘            │
│            ▼                                                      │ clonefile                │
│  ┌───────────────────┐                                            ▼                          │
│  │ Launch Preflight    │  size+inode+mtime check    ┌──────────────────────────┐             │
│  │ (CACH-04 gate,      │  (offline, no network)      │ Materialized launch dir   │             │
│  │  PLAY-02)           │                             │ launch/<asset_set_uuid>/  │             │
│  └─────────┬───────────┘                             └────────────┬──────────────┘             │
│            │ pass                                                  │                            │
│            ▼                                                       ▼                            │
│  ┌───────────────────┐  Process/posix_spawn           ┌──────────────────────────┐             │
│  │ Adapter Host        │────────────────────────────►│ mGBA.app (external, signed│             │
│  │ (config injection,  │  config.ini / CLI flags       │ separately-notarized)     │             │
│  │  exit detection)    │◄────────────────────────────│ writes .sav to app-managed │             │
│  └─────────┬───────────┘  terminationHandler            │ save dir                  │             │
│            │                                            └──────────────────────────┘             │
│            ▼                                                                                       │
│  POST /api/v1/play-sessions (outbox, never launch-blocking)                                        │
└──────────────────────────────────────┬───────────────────────────────────────────────────────────┘
                                        │ HTTPS (P1 pairing/CA pinning)
┌───────────────────────────────────────▼──────────────────────────────────────────────┐
│                              Phoenix Server (playstead-server)                        │
│                                                                                         │
│  Router :api pipeline → :device_auth → [:idempotency where mutating]                  │
│                                                                                         │
│  ┌───────────────────┐   ┌───────────────────────┐   ┌───────────────────────────┐   │
│  │ BlobsController      │   │ Curation Controllers    │   │ PlaySessionsController     │   │
│  │ (hardened Range/     │   │ (favorites/collections/ │   │ (POST, idempotent)          │   │
│  │  ETag contract)      │   │  queue REST intents)    │   │                             │   │
│  └─────────┬───────────┘   └───────────┬─────────────┘   └───────────┬─────────────┘   │
│            │ stream/2(sha256,range)     │ Ecto.Multi: mutation           │                 │
│            ▼                             │ + ChangeJournal.append/4       │                 │
│  ┌───────────────────┐                  ▼                                ▼                 │
│  │ Blobs.Store.        │       ┌──────────────────────────────────────────────────┐        │
│  │ LocalDisk (CAS,      │       │ Sync.ChangeJournal (curation kind added) +          │        │
│  │  offset/length read) │       │ Sync.Snapshot (curation branch added)              │        │
│  └───────────────────┘       └──────────────────────────────────────────────────┘        │
│                                                                                         │
│  LiveView console: library_live.ex + new curation shelves — same context fns as API   │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure (Mac client, greenfield)

```
playstead-mac/
├── Playstead/
│   ├── App/                    # App entry, Scene, sandbox-less entitlements
│   ├── Sync/                   # SyncEngine, Outbox, cursor/snapshot client
│   ├── Curation/               # Favorites/Collections/Queue/Continue/Recent view models
│   ├── Cache/                  # DownloadEngine (URLSession actor), CAS manager, quota/pin/eviction
│   ├── Adapter/                # AdapterHost (process spawn), config injection, BIOS validation
│   ├── Controller/              # GameController framework wrapper, remap/reset UI
│   ├── Library/                 # Browse UI: shelves, list, status-slot component
│   ├── Persistence/              # SQLite wrapper models (read models, outbox, queue)
│   └── Shared/                  # Design tokens shared conceptually with LiveView (per D-17 spec)
└── PlaysteadTests/
    ├── SyncTests/
    ├── CacheTests/               # Range-resume byte-identity, quota/eviction, verify lifecycle
    └── AdapterTests/             # Config injection, exit-detection state machine (spike-derived)
```

### Pattern 1: In-process range-resume download actor

**What:** A Swift `actor DownloadEngine` owns one active transfer at a time, using `URLSession.bytes(for:)` (AsyncBytes) or a streaming delegate, writing to a `.partial` file, re-hashing the on-disk prefix on resume rather than trusting any persisted hash checkpoint.
**When to use:** All CACH-01 blob transfers.
**Example (pattern, not verified against a built client — `[ASSUMED]` shape, `[CITED]` API existence):**
```swift
// Source: pattern derived from discussion-research/D + Apple URLSession docs
actor DownloadEngine {
    func resume(item: QueueItem) async throws {
        let partialURL = partialPath(for: item.sha256)
        let existingBytes = (try? FileManager.default.attributesOfItem(atPath: partialURL.path)[.size] as? Int) ?? 0

        var request = URLRequest(url: item.blobURL)
        if existingBytes > 0 {
            request.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
            request.setValue("\"\(item.sha256)\"", forHTTPHeaderField: "If-Range")
        }

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw DownloadError.badResponse }

        if existingBytes > 0 && http.statusCode == 200 {
            // Server ignored/couldn't honor Range — MUST truncate and restart,
            // never append a full body after a partial prefix (D-18 footgun).
            try FileManager.default.removeItem(at: partialURL)
        }

        // Re-hash whatever is actually on disk before appending further bytes —
        // disk is the source of truth, never a persisted hash-state file.
        var hasher = SHA256Hasher(resumingFrom: partialURL)
        let handle = try FileHandle(forWritingTo: partialURL)
        try handle.seekToEnd()

        for try await chunk in bytes.chunks(ofCount: 1 << 16) {
            let data = Data(chunk)
            handle.write(data)
            hasher.update(data)
        }

        let finalHash = hasher.finalizeHex()
        guard finalHash == item.sha256 else {
            throw DownloadError.hashMismatch  // quarantine + retry with backoff
        }
        try commitIntoCAS(partialURL, sha256: item.sha256)
    }
}
```

### Pattern 2: Server-side Range contract (BlobsController hardening)

**What:** `BlobsController.show/2` parses `Range`/`If-Range` headers and delegates to `Blobs.Store.stream/2`'s existing `range` argument; emits quoted strong `ETag`.
**Current gap (verified this session):** the controller ignores incoming `Range` entirely (`send_chunked(200)` unconditionally) and emits `put_resp_header("etag", sha256)` — **unquoted**. `Blobs.Store.LocalDisk.build_stream/2`'s range branch calls `File.read!(path)` — loads the whole file before slicing, a correctness-adjacent memory hazard for large blobs.
```elixir
# Source: current code, playstead-server/lib/playstead_web/controllers/api/v1/blobs_controller.ex
# (verified this session — NOT yet hardened; this is what Phase 3 must change)
conn
|> put_resp_header("etag", sha256)          # BUG per D-19: must be quoted `"<sha256>"`
|> put_resp_content_type("application/octet-stream")
|> send_chunked(200)                          # BUG per D-19: ignores Range entirely
|> stream_chunks(stream)
```
```elixir
# Source: current code, playstead-server/lib/playstead/blobs/store/local_disk.ex:337-341
# (verified this session — the range-slicing bug D-19 hardening must fix)
defp build_stream(path, first..last//_step) do
  data = File.read!(path)                     # loads ENTIRE file into memory — fix for PSX-sized blobs
  last = min(last, byte_size(data) - 1)
  [binary_part(data, first, last - first + 1)]
end
```
The fix must (a) use `:file.pread/3` (positional read) or `File.stream!/3` with an offset instead of `File.read!/1`, (b) return `206`/`Content-Range` when a valid single-range `Range` header is present, `416` when the start is past EOF, `200` for absent/multi-range headers, and (c) quote the ETag. `Blobs.Store` behaviour's `stream/2` callback signature already supports this (`@callback stream(hash(), range :: Range.t() | nil) :: {:ok, Enumerable.t()} | {:error, :not_found}` — verified in `store.ex`), so no behaviour change is needed, only the `LocalDisk` implementation and the controller's header parsing/response-status logic.

### Pattern 3: Curation journal entity kind (additive registration)

**What:** Register `curation` in `Playstead.Sync.EntityKind`, add a `Playstead.Sync.Snapshot` materialization branch, and use `ChangeJournal.append/4` inside the same `Ecto.Multi` as each curation mutation — this is the exact existing pattern (verified this session), no new mechanism.
```elixir
# Source: current code, playstead-server/lib/playstead/sync/entity_kind.ex (verified this session)
# BEFORE (current):
@kinds ~w(device pairing catalogue job transfer save)a
# AFTER (D-08's additive change — planner task):
@kinds ~w(device pairing catalogue job transfer save curation)a
```
```elixir
# Source: pattern from playstead-server/lib/playstead/sync/change_journal.ex (verified this session,
# append/4 signature and in-transaction discipline are load-bearing — do not open a separate transaction)
Ecto.Multi.new()
|> Ecto.Multi.insert(:favorite, Favorite.create_changeset(...))
|> Ecto.Multi.run(:journal, fn _repo, %{favorite: favorite} ->
  ChangeJournal.append(user_id, :curation, favorite.id, %{
    type: "favorite",
    asset_set_id: favorite.asset_set_id,
    created_at: favorite.inserted_at
  })
end)
|> Repo.transaction()
```

### Pattern 4: mGBA external-process launch via `Process`

**What:** Launch the pinned, downloaded, quarantine-intact `mGBA.app` binary as an external process with per-launch config injection.
**When to use:** PLAY-05 launch; exact CLI/config surface is exactly what the spike (D-01 probe 1/2) must empirically confirm.
```swift
// Source: pattern per discussion-research/A, Apple Process docs — NOT yet spike-verified;
// exact flags/config-injection mechanism is THE open question the spike answers.
let process = Process()
process.executableURL = mgbaBinaryURL   // e.g. .../mGBA.app/Contents/MacOS/mGBA
process.arguments = [
    "-C", "savegamePath=\(appManagedSaveDir.path)",
    "-C", "gba.bios=\(biosPath?.path ?? "")",
    romPath.path
]
process.terminationHandler = { proc in
    // Covers clean quit, crash, and force-kill — spike probe 4 defines the state machine
    Task { await adapterHost.handleExit(status: proc.terminationStatus, reason: proc.terminationReason) }
}
try process.run()
```

### Anti-Patterns to Avoid

- **Persisting a rolling hash-state checkpoint for resume:** CryptoKit has no serializable incremental-hash state; a crash between byte-write and state-write silently desynchronizes state from disk. Always re-hash the on-disk prefix from bytes 0 on resume (D-18).
- **Hardlinking materialized launch files to the CAS:** an emulator writing through a hardlink corrupts the verified copy. Always `clonefile`/copy (D-20).
- **Storing CACH-02 state as a persisted enum column:** it drifts from disk truth. Derive it at read time from (queue row, partial file, CAS entry, pin flag) (D-21).
- **Stuffing curation data into the frozen `catalogue` payload:** violates the P2 D-23 freeze and mixes canonical facts with per-user preference. Use the new `curation` kind (D-08).
- **Transmitting a whole ordered list as a mutation:** the one pattern proven to silently drop a concurrent offline addition. Always send single-row position intents (D-09).
- **Using `URLSessionDownloadTask` background sessions for blob transfer:** ignores custom `Range` headers, opaque resumeData, OS can purge temp files (Pitfall 1 below).
- **Bundling the emulator inside Playstead.app:** couples notarization/release cadence, adds nested-signing risk (D-05).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Range/If-Range HTTP resume semantics | A custom resume protocol/handshake | RFC 9110 §14 Range/If-Range/206/416, implemented directly in `BlobsController` + client `URLSession` | Already the exact right-sized mechanism for MB-GB blobs on LAN; a custom chunk-manifest protocol (Steam-style) is explicitly rejected as premature (discussion-research/D) |
| Ordered-list conflict resolution | A CRDT library (RGA/Logoot) or hand-rolled OT | Fractional-index position strings + server rebalance | CRDTs are Google-Docs-grade machinery for a personal library's dozens of items; fractional indexing is ~30 lines and one string column (discussion-research/B) |
| SHA-256 incremental hashing with resumable state | A custom serializable hash-state file format | Re-hash the on-disk prefix from scratch on resume | No hash library exposes safely serializable mid-stream state; re-hashing a 700MB prefix at NVMe speed is ~0.3-1s — cheaper than the correctness risk |
| Emulator process supervision/crash recovery | A custom process-babysitting daemon | `Process.terminationHandler` + the spike-derived exit-detection state machine | macOS already gives clean/crash/kill signals via the termination handler; building a separate watchdog process adds complexity the spike doesn't require |
| BIOS file validation | A file-format parser for GBA ROM headers to "detect" BIOS validity | Size (16KiB) + digest match against known reference hashes, reusing the Phase 2 DAT hash-match primitive | Consistent with the existing import-pipeline verification philosophy; a bespoke validator duplicates trusted infrastructure |

**Key insight:** Every "don't hand-roll" item in this phase already has a proven, in-repo or platform-native counterpart — the discipline is reuse, not invention. The one genuinely novel piece of engineering is the adapter host's exit-detection/config-injection state machine, and even that is scoped tightly by the seven spike probes rather than open-ended.

## Common Pitfalls

### Pitfall 1: Background URLSession resume silently ignores Range headers
**What goes wrong:** Using `URLSessionDownloadTask` with a background session for the download engine appears to work in testing, then silently falls back to full re-download or corrupts resume behavior in production.
**Why it happens:** Apple's background-session resume machinery (`resumeData`) is opaque and built for its own ETag/Last-Modified-based resume logic; it does not honor custom `Range` request headers, and the OS can purge the background session's temp file under disk pressure.
**How to avoid:** Use an in-process `URLSessionDataTask`-style stream (`bytes(for:)`/AsyncBytes or a delegate) inside a dedicated actor, as the app is a desktop foreground app — background sessions buy nothing here (D-18).
**Warning signs:** Resume "working" in dev but occasionally re-downloading the whole file in the field; `resumeData`-related crashes after app updates.
`[CITED: developer.apple.com/forums/thread/47460]`

### Pitfall 2: Server returns 200 instead of 206 on a resumed request
**What goes wrong:** A proxy or misconfigured server strips the `Range` header or the request otherwise falls through to a full-body 200 response; a naive client appends the full body after its partial prefix, producing a corrupted, doubled-length file that still might coincidentally not hash-mismatch on a short-circuited check.
**Why it happens:** Old server versions, an intermediary proxy, or a bug in the Range-parsing path.
**How to avoid:** The client MUST inspect the response status on every resumed request: on `200` where `206` was expected, truncate the partial to zero bytes and restart from scratch (D-18). Never assume `206` when a `Range` header was sent.
**Warning signs:** Verify failures after network/reconnect events; file sizes larger than expected on disk.

### Pitfall 3: `File.read!/1`-based range slicing loads whole blobs into memory
**What goes wrong:** The current `Blobs.Store.LocalDisk.build_stream/2` range branch (`File.read!(path)` then `binary_part`) reads the entire committed object into memory before returning a slice — verified in this session's code read. For a multi-hundred-MB PSX BIN track, this is a memory spike on every ranged request, and defeats the purpose of streaming.
**Why it happens:** The Range support was stubbed in for a future phase (Phase 2's D-33 deferral) without full-file streaming semantics.
**How to avoid:** Replace with `:file.pread/3` at the requested offset/length, or `File.stream!/3` with an initial byte offset, so only the requested byte range is read from disk.
**Warning signs:** Elixir process memory spikes correlated with blob download requests; slow first-byte time on large-file Range requests.

### Pitfall 4: Unquoted ETag breaks strict `If-Range` semantics
**What goes wrong:** RFC 9110 requires a strong validator for `If-Range` range-preservation to be trustworthy; an unquoted ETag (`etag: <sha256>` instead of `etag: "<sha256>"`) is not a syntactically valid strong ETag per the HTTP spec, and some HTTP client/proxy implementations will not match it correctly against a subsequently-sent `If-Range` header.
**Why it happens:** `BlobsController.show/2` currently emits `put_resp_header("etag", sha256)` — verified unquoted this session.
**How to avoid:** Quote it: `put_resp_header("etag", "\"#{sha256}\"")`. Blobs are immutable so this specific case is low-risk in practice, but D-19 explicitly freezes this as protocol — get it right now since a future client's transfer engine builds on it.
**Warning signs:** Contract test failures on `If-Range` matching; client-side `URLSession` `If-Range` mismatches against certain proxies.

### Pitfall 5: mGBA CLI/config flags verified for the wrong binary
**What goes wrong:** Manpage/README documentation for mGBA's CLI flags (`-C option=value`, `-b/--bios`) is written against the SDL frontend binary; the shipped `mGBA.app` on macOS is the Qt frontend, which may have a different or partial flag surface.
**Why it happens:** mGBA ships multiple frontends from one build; documentation doesn't always distinguish which flags apply to which.
**How to avoid:** The spike (D-01 probe 2) must test config injection against the *actual shipped* `mGBA.app/Contents/MacOS/mGBA` binary; if CLI flags don't work, use portable-mode `config.ini` placed beside a private copy of the binary as the fallback injection mechanism.
**Warning signs:** Config injection silently ignored (emulator falls back to default paths) despite flags "documented" as correct.
`[CITED: discussion-research/A adversarial pass #1, mGBA README/manpage]`

### Pitfall 6: mmap-based save flush is exit-only, not periodic
**What goes wrong:** mGBA's raw `.sav` battery-save file is memory-mapped; deterministic flush to disk is guaranteed at unmap (clean exit/ROM change), not continuously — a `kill -9` mid-play can lose save progress since the last mmap flush, which may be arbitrarily stale.
**Why it happens:** mmap-based save I/O trades continuous-durability for performance; this is standard emulator behavior, not a Playstead bug.
**How to avoid:** D-03 (owner ruling) makes this a hard pass/fail gate: if mGBA standalone cannot demonstrate a periodic or on-demand flush during play (not solely at clean exit), RetroArch+mGBA core (which has `autosave_interval`) wins the adapter selection even if mGBA passes every other probe. Do not treat this as an acceptable-by-default tradeoff — it must be an explicit, evidenced decision in the SPIKE-REPORT.
**Warning signs:** Save data missing progress made in the last N minutes of play after an unclean shutdown, where N exceeds the user's expectation.
`[CITED: discussion-research/A, mgba-emu/mgba src/gba/savedata.c]`

### Pitfall 7: App Translocation / Gatekeeper on the downloaded emulator
**What goes wrong:** A quarantined `.app` run from certain paths (e.g., directly from `~/Downloads`) can be silently relocated by macOS App Translocation, breaking relative-path assumptions in the launched process, or Gatekeeper may present an "Open Anyway" prompt on first launch.
**Why it happens:** macOS quarantines downloaded executables; translocation and Gatekeeper evaluation both key off the quarantine xattr and the app's install location.
**How to avoid:** Install the downloaded, hash-verified emulator into `~/Library/Application Support/Playstead/emulators/<name>/<version>/` (not a Downloads-style path) before first launch; never strip the quarantine xattr programmatically (that reads as malware behavior and may itself trip notarization/AV heuristics). The spike must explicitly test first-launch Gatekeeper behavior on a clean macOS user account and record the exact OS build tested — any "Open Anyway" requirement is a FAIL per D-01.
**Warning signs:** Emulator fails to find its own resources after being moved by translocation; first-run modal appears in the spike (immediate FAIL condition).

### Pitfall 8: Curation entity-kind freeze breaks catalogue payload discipline
**What goes wrong:** A tempting shortcut is adding curation fields directly to the existing `catalogue` journal payload since it's "already there" — this silently violates the P2 D-23 freeze (additions-only, never mixing canonical facts with per-user preference) and would re-emit a large catalogue entity on every favorite toggle.
**Why it happens:** Avoiding a new entity kind feels like less protocol surface.
**How to avoid:** Register the new `curation` kind explicitly in `Playstead.Sync.EntityKind` as a logged, deliberate additive amendment (D-08) — this is the one place this phase's decisions call for touching a "frozen" list, and it must be done because zero clients are deployed yet; waiting until after Phase 3 ships would require capability gating.
**Warning signs:** A code reviewer or plan-checker flags a diff touching `catalogue` payload shape for a curation feature.

## Runtime State Inventory

Not applicable — Phase 3 is greenfield Mac client work plus additive server-side changes (new entity kind, hardened controller). No rename/refactor/migration of existing identifiers, stored data, or OS-registered state occurs in this phase. Verified by reading `03-CONTEXT.md`'s phase boundary (client + additive protocol changes only) and confirming no existing production data references are altered — `EntityKind.all/0` gains a member, it does not rename or remove one.

**None found in this category — verified by reading `entity_kind.ex`, `blobs_controller.ex`, and `03-CONTEXT.md` this session; all changes are additive.**

## Common Pitfalls

(see above — merged into one section per repo convention)

## Code Examples

### Server: Range header parsing shape for BlobsController hardening
```elixir
# Source: pattern to implement per D-19; RFC 9110 §14.2/14.35 semantics
# (not yet in the repo — this is the target shape, not a verified excerpt)
defp parse_range(conn, total_size) do
  case get_req_header(conn, "range") do
    [range_header] ->
      case Plug.Conn.Utils.list(range_header) do
        # single-range only; multi-range collapses to full 200 per D-19
        _ -> parse_single_range(range_header, total_size)
      end
    [] -> :full
  end
end
```

### Client: launch preflight gate (CACH-04, zero network)
```swift
// Source: pattern per discussion-research/D §5 Verification lifecycle
func preflight(assetSet: AssetSet) throws -> ReadinessResult {
    for member in assetSet.requiredMembers {
        let casPath = casPath(for: member.sha256)
        let attrs = try FileManager.default.attributesOfItem(atPath: casPath.path)
        let cheapCheckPasses = attrs[.size] as? Int == member.sizeBytes
            && matchesInodeAndMtime(attrs, member.verifyRecord)
        if !cheapCheckPasses {
            let rehashed = try sha256(of: casPath)   // full re-hash fallback, still offline
            guard rehashed == member.sha256 else {
                throw ReadinessError.corrupted(member)  // -> quarantine + auto redownload
            }
        }
    }
    return .ready  // zero network calls anywhere in this path — CACH-04 contract
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| `BlobsController` whole-file `send_chunked(200)` | Range-aware `stream/2(sha256, range)` with 206/416/HEAD | This phase (D-19 hardening, completing P2 D-33's deferral) | Enables CACH-01 resume; becomes frozen client protocol |
| Six entity kinds (`device pairing catalogue job transfer save`) | Seven kinds, `curation` added | This phase (D-08, before any client ships) | Curation sync rides the existing recovery spine instead of a bespoke mechanism |

**Deprecated/outdated:** none — this phase extends existing infrastructure rather than replacing anything.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | GRDB.swift / SQLite.swift are the standard Swift SQLite wrapper choices | Standard Stack | Low — explicitly Claude's Discretion in CONTEXT.md; either choice is viable, gate with checkpoint:human-verify before pinning a version |
| A2 | CryptoKit's `SHA256` supports incremental streaming updates suitable for resumable hashing | Standard Stack | Medium — if the exact streaming API differs from assumed shape, the download engine's hashing loop needs adjustment during implementation; does not change the architecture |
| A3 | Exact mGBA CLI flag names (`-C option=value`, `-b/--bios`) work unmodified against the shipped Qt `mGBA.app` binary | Code Examples / Pitfall 5 | High if wrong, but explicitly the spike's job to determine — D-01 probe 2 exists precisely to de-risk this; plan should not hard-commit to these flags before the spike confirms them |
| A4 | `Process.terminationHandler` reliably distinguishes clean-exit vs crash vs force-kill via `terminationStatus`/`terminationReason` | Code Examples (Pattern 4) | Medium — spike probe 4 must empirically confirm the exact signal/reason values on macOS for mGBA specifically |

**If this table is empty:** N/A — table has 4 entries requiring confirmation, primarily around the spike's own empirical questions (by design, since the spike itself is D-01's mechanism for resolving them) and the Mac persistence library choice (explicitly deferred to discretion).

## Open Questions

1. **Exact mGBA Qt CLI/config flag surface**
   - What we know: mGBA's README documents `-C option=value` and `-b/--bios` for the SDL binary; portable-mode `config.ini` is a documented fallback.
   - What's unclear: whether the Qt `mGBA.app` binary honors the same flags identically.
   - Recommendation: the spike (D-01 probe 2) resolves this directly — do not plan downstream config-injection code around unverified flag names; treat the spike's output as the source of truth for the adapter host's config-injection module.

2. **mGBA save-flush cadence (periodic vs exit-only)**
   - What we know: mmap-based save I/O flushes deterministically at unmap; RetroArch's `autosave_interval` provides periodic flush as an alternative.
   - What's unclear: whether mGBA standalone can be coaxed into a periodic flush (e.g., via an in-app manual-save hotkey users press, or some other observable signal) that satisfies D-03's owner ruling, or whether the fallback to RetroArch is required.
   - Recommendation: the spike must test this explicitly and document the decision with evidence in `03-SPIKE-REPORT.md`; the planner should structure the adapter-selection plan so either outcome (mGBA passes or RetroArch fallback triggers) has a defined next step, not an open-ended "figure it out" task.

3. **Distribution posture — first-run Gatekeeper behavior on the current macOS build**
   - What we know: Developer ID + notarization + hardened runtime is the chosen posture; the spike must verify no "Open Anyway" friction.
   - What's unclear: Apple's Gatekeeper policy is known to tighten over macOS releases; behavior may differ from what CITED documentation from earlier macOS versions describes.
   - Recommendation: the spike report must record the exact macOS build tested; if a policy regression is found, this becomes a roadmap-level event per the adversarial pass in discussion-research/A, not a silent workaround.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| macOS (Apple Silicon or Intel Mac) with Xcode | All Mac client work, spike | Not verified this session — requires the executing developer's machine | — | Spike cannot proceed without a real Mac; this is a hard environment requirement, not a code dependency |
| Apple Developer Program membership (Developer ID cert, notarization credentials) | D-04 distribution posture, D-01 probe 1 | Not verified this session | — | No fallback — notarized build is a phase success criterion (PLAY-05) |
| mGBA official release binary (download-on-demand) | D-01/D-02 spike | Not verified this session — fetched at spike time per D-05 | Pinned exact version determined by spike | RetroArch+mGBA core fallback ladder (D-02) if mGBA standalone fails probes |
| Homebrew GBA test ROM with SRAM-writing behavior | D-01 probe 3 | Must be sourced/selected during spike (Claude's Discretion per CONTEXT.md) | — | No fallback — required for a valid save-flush probe; selection criteria specified in discussion-research/A |
| PostgreSQL (existing) | Server-side curation/journal changes | Assumed available per Phase 1/2 infrastructure | Per existing `docker-compose.yml` | Already operational — no new requirement |

**Missing dependencies with no fallback:**
- Apple Developer Program membership/notarization credentials — blocks PLAY-05 entirely if unavailable.
- A physical or virtual Mac to run the spike — this research cannot substitute for hands-on execution.

**Missing dependencies with fallback:**
- mGBA standalone → RetroArch+mGBA core → SameBoy/Gambatte → RetroArch+SNES core (D-02 fallback ladder, exhausted only on full posture reassessment).

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework (server) | ExUnit (existing) |
| Framework (Mac client) | XCTest (Swift standard; greenfield, not yet configured) |
| Config file (server) | `mix.exs` (existing) |
| Config file (Mac client) | none yet — see Wave 0 gaps |
| Quick run command (server) | `mix test test/playstead_web/controllers/api/v1/blobs_controller_test.exs` |
| Quick run command (Mac client) | `xcodebuild test -scheme Playstead -only-testing:PlaysteadTests/CacheTests` (once project exists) |
| Full suite command (server) | `mix test` |
| Full suite command (Mac client) | `xcodebuild test -scheme Playstead` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CACH-01 | Kill-and-resume byte-identity | contract/integration | `mix test test/playstead_web/controllers/api/v1/blobs_controller_test.exs` (server side); client-side resume test in `PlaysteadTests/CacheTests` | ❌ Wave 0 (both sides need new test cases) |
| CACH-01 | 206 arithmetic, If-Range, 416, HEAD, quoted ETag | contract | `mix test test/playstead_web/controllers/api/v1/blobs_controller_test.exs` | ✅ file exists (verified `blobs_controller_test.exs` present) — ❌ new range-specific cases needed |
| CACH-02 | Six-state derivation correctness | unit | `xcodebuild test -only-testing:PlaysteadTests/CacheTests/StateDerivationTests` | ❌ Wave 0 |
| CACH-03 | Quota/floor blocking, manual eviction honesty (no silent deletion) | unit + integration | client test target | ❌ Wave 0 |
| CACH-04 | Preflight gate makes zero network calls | integration (network-mocked/disabled) | client test target with network stubbed to fail | ❌ Wave 0 |
| LIBR-03 | Curation mutation idempotency + fractional-index conflict merge | contract | server-side `mix test test/playstead/curation*` (new) | ❌ Wave 0 |
| LIBR-05 | Console parity — LiveView shelves render same data as API | integration | server-side LiveView test | ❌ Wave 0 |
| PLAY-01…05 | Adapter probes 1-7 | manual-only (spike), justification: hardware/process/OS-integration behavior not meaningfully unit-testable | N/A — SPIKE-REPORT.md evidence per probe | ❌ Wave 0 — spike itself IS the test |
| QUAL-01 | Controller/keyboard/focus parity, reduced motion | manual UAT + targeted unit tests on state-derivation/focus logic | client test target + manual verification pass | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** quick run command for the touched surface (server: targeted `mix test` file; client: targeted `xcodebuild test -only-testing:`).
- **Per wave merge:** full suite on both server and client.
- **Phase gate:** Full suite green (both sides) before `/gsd-verify-work`; SPIKE-REPORT.md with all 7 probes evidenced (pass or documented fallback) is an additional phase-gate artifact beyond normal test-green, since PLAY-01/02/03/04/05 are fundamentally about real hardware/process behavior that automated tests cannot fully substitute for.

### Wave 0 Gaps
- [ ] `playstead-mac/` Xcode project + `PlaysteadTests` target — currently only a README exists (verified this session).
- [ ] `test/playstead_web/controllers/api/v1/blobs_controller_test.exs` — new Range/If-Range/416/HEAD/quoted-ETag/resume-byte-identity test cases (file exists but needs new cases per D-19).
- [ ] `test/playstead/sync/` — new tests for `curation` entity kind registration, snapshot branch, journal append inside `Ecto.Multi`.
- [ ] `playstead-mac/PlaysteadTests/CacheTests/` — download-resume, state-derivation, quota/eviction, preflight-zero-network tests.
- [ ] `03-SPIKE-REPORT.md` template/harness — the probe-by-probe evidence-recording structure (Claude's Discretion per CONTEXT.md on exact format).

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No (device pairing/credential handling unchanged from P1) | — |
| V3 Session Management | No (device-credential model unchanged) | — |
| V4 Access Control | Yes | `BlobsController.authorized?/2` (existing `source_file` ownership check, verified this session) must continue to gate every 206/HEAD response identically to the existing 200 path — the hardening must not create a Range-request bypass |
| V5 Input Validation | Yes | `Range` header parsing must reject malformed/out-of-bounds values with `416`, never crash or silently serve unbounded reads; curation REST payloads (favorite/collection/queue) validated via Ecto changesets per existing convention |
| V6 Cryptography | Yes (indirectly) | SHA-256 for content-address integrity (existing pattern, CryptoKit client-side) — never hand-roll a hash function |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Range-request used to bypass authorization (requesting bytes of a blob the user doesn't own) | Elevation of Privilege | `authorized?/2` and `playable?/2` checks (existing) must run identically for Range/HEAD requests, not just full-GET — verify this explicitly in the hardened controller, it is an easy regression to introduce while adding Range logic |
| Malicious/malformed `Range` header (negative ranges, huge offsets) causing a crash or resource exhaustion | Denial of Service | Strict RFC 9110-conformant parsing; invalid ranges get `416`, never an unhandled exception; the current `File.read!` full-load-then-slice pattern (Pitfall 3) is itself a DoS-adjacent memory-exhaustion risk on large files regardless of the requested range size |
| Downloaded emulator binary tampering (supply-chain) | Tampering | SHA-256 pin verification before first launch and at preflight re-verification (D-05); never strip quarantine xattr; Gatekeeper/notarization as the OS-level integrity gate |
| Symlink/path traversal via a maliciously-crafted BIOS drag-in file path | Tampering / Information Disclosure | BIOS validation is by size+digest match only (D-06), never by trusting a user-supplied path for anything beyond read-only digest computation; materialize into an app-managed directory, never execute or interpret the dragged-in file beyond hashing it |
| Curation REST endpoints missing per-user scoping | Elevation of Privilege | Every new curation schema/context function takes a `Scope` and filters by `user_id` per the existing P1 D-01 convention (verified pattern in `Catalogue.list_assets/2`) |

## Sources

### Primary (HIGH confidence — verified against live repository this session)
- `playstead-server/lib/playstead_web/controllers/api/v1/blobs_controller.ex` — current unquoted ETag, unconditional `send_chunked(200)`
- `playstead-server/lib/playstead/blobs/store/local_disk.ex` — `stream/2`, `build_stream/2`'s `File.read!` range bug
- `playstead-server/lib/playstead/blobs/store.ex` — `Store` behaviour, `stream/2` callback already accepts `range`
- `playstead-server/lib/playstead/sync/entity_kind.ex` — current six-kind frozen list, `valid?/1`
- `playstead-server/lib/playstead/sync/change_journal.ex` — `append/4`/`tombstone/3` in-transaction discipline, advisory-lock fencing
- `playstead-server/lib/playstead/sync/snapshot.ex` — per-domain snapshot branch precedent
- `playstead-server/lib/playstead/idempotency.ex` — `fingerprint/1`, `fetch/3` replay/mismatch/in-flight semantics
- `playstead-server/lib/playstead/protocol/capabilities.ex` — frozen `envelope/0`, six namespaces, required-vs-optional negotiation
- `playstead-server/lib/playstead_web/controllers/api/v1/hello_controller.ex` — capability negotiation controller pattern
- `playstead-server/lib/playstead/catalogue/asset_member.ex` — `required` boolean field (CACH-04 gate basis)
- `playstead-server/mix.exs` — current dependency set (no new deps needed)
- `playstead-server/lib/playstead_web/router.ex` — existing scope/pipe_through/idempotency route conventions
- `.planning/phases/03-mac-offline-play-vertical-slice/discussion-research/A-adapter-spike-and-first-emulator.md`
- `.planning/phases/03-mac-offline-play-vertical-slice/discussion-research/B-curation-ownership-and-sync.md`
- `.planning/phases/03-mac-offline-play-vertical-slice/discussion-research/C-library-experience-without-artwork.md`
- `.planning/phases/03-mac-offline-play-vertical-slice/discussion-research/D-cache-and-download-semantics.md`

### Secondary (MEDIUM confidence — official docs, WebSearch this session)
- Apple Developer Forums — Range header unsafe in background download tasks: https://developer.apple.com/forums/thread/47460
- Apple — `copyItem(at:to:)`: https://developer.apple.com/documentation/foundation/filemanager/copyitem(at:to:) (FileManager auto-clones on APFS)
- Apple — Game Controller framework, "Discovering and Connecting to Controllers": https://developer.apple.com/library/archive/documentation/ServicesDiscovery/Conceptual/GameControllerPG/DiscoveringControllers/DiscoveringControllers.html
- Apple — Notarizing macOS Software: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- `xcrun notarytool`/`stapler` workflow summary: https://tonygo.tech/blog/2023/notarization-for-macos-app-with-notarytool
- mGBA README/manpage (CLI flags, portable mode): https://github.com/mgba-emu/mgba/blob/master/README.md, https://man.archlinux.org/man/mgba.6.en
- RFC 9110 §14 (HTTP Range/If-Range/206/416 semantics)

### Tertiary (LOW confidence — training knowledge, flagged for validation)
- GRDB.swift / SQLite.swift as candidate SQLite wrappers — package names from training data, not verified via Context7/authoritative source this session; gate with `checkpoint:human-verify`.
- CryptoKit incremental `SHA256` streaming API exact shape — plausible from training knowledge, not exercised in this repo.

## Metadata

**Confidence breakdown:**
- Standard stack (server): HIGH — no new dependencies, existing code read directly.
- Standard stack (Mac client): MEDIUM — Apple framework APIs are well-documented and stable, but no code in this repo yet exercises them; SQLite wrapper choice is unverified/discretionary.
- Architecture: HIGH for server-side seams (verified against live code); MEDIUM for client-side shape (design-level, consistent with discussion-research, not yet built).
- Pitfalls: HIGH for the three server-side bugs found by direct code reading (unquoted ETag, `send_chunked` ignoring Range, `File.read!` memory issue); MEDIUM for Mac/adapter pitfalls (well-sourced from Apple docs and discussion-research, but empirically unconfirmed pending the spike by design).

**Research date:** 2026-08-30
**Valid until:** 30 days for the server-side findings (stable, code-verified); the adapter/spike findings have no meaningful staleness window since they require the spike's own execution regardless of research age — mGBA/RetroArch release versions should be re-checked at spike time regardless.
