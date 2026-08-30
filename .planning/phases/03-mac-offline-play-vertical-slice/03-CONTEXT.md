# Phase 3: Mac Offline Play Vertical Slice - Context

**Gathered:** 2026-08-30
**Status:** Ready for planning

<domain>
## Phase Boundary

The first native Mac client (SwiftUI + targeted AppKit) and the LiveView library console: a newly paired Mac browses the complete server catalogue before downloading bytes, curates Favorites, Collections, Continue, Recent, and a play queue with full web-console parity; selectively downloads, range-resumes, and hash-verifies content into a managed local cache with quota, pin, and honest reclaim controls; validates readiness (adapter, BIOS, controller, cache, save path) with a concrete remedy per blocking result; and launches one deliberately supported game fully offline from a signed/notarized build through an empirically gated emulator adapter. Covers LIBR-01…05, CACH-01…04, PLAY-01…05, QUAL-01.

Out of this phase: persistent-save capture/sync/restore (Phase 4 — but the spike must prove the save-flush contract Phase 4 builds on), backup/health/upgrade tooling (Phase 5), metadata/artwork providers, achievements, browser play, a second client or adapter, S3/direct transfer.

</domain>

<decisions>
## Implementation Decisions

All decisions were produced by four parallel multi-lens research fan-outs (macOS platform, emulator ecosystem, security, licensing, product/first-adopter UX, distributed-systems/offline-sync, Elixir/Phoenix and Swift idiom, creative direction, accessibility, adversarial passes) with online prior-art research, synthesized into one coherent set, and approved by the owner as a set on 2026-08-30. The one contested point was put to the owner; the ruling is recorded at D-03. Full option tables, adversarial passes, and sources: `discussion-research/`. Phase 1 and 2 decisions are cited as `P1 D-xx` / `P2 D-xx`.

### Adapter Spike and First Emulator

- **D-01:** The adapter spike is Phase 3's opening plan, before any other Mac work is planned in detail. Seven pass/fail probes: (1) notarized launch of the downloaded emulator, (2) config injection (save path, BIOS path, controller mapping), (3) save-flush observability including `kill -9` behavior, (4) exit detection/recovery, (5) controller unplug/reconnect, (6) Keychain access from the notarized build, (7) BIOS-less launch plus drag-in BIOS launch. Outputs: a SPIKE-REPORT, the exact `(system, emulator, version, sha256)` support pin, and the adapter save contract Phase 4 builds on. Any Gatekeeper "Open Anyway" requirement is a FAIL; the report records the exact macOS build tested.
- **D-02:** Candidate ladder: **GBA via mGBA standalone external process** primary (MPL-2.0 bundling-safe, no BIOS required, `gba` is P2 D-14 Tier A); fallback rung 1 **RetroArch + mGBA core**; then SameBoy/Gambatte (GB/GBC); then RetroArch + SNES core; then distribution-posture reassessment. Snes9x standalone is disqualified (non-commercial license clause conflicts with a possible future hosted business). Probes must run against the real shipped `mGBA.app` binary (portable-mode `config.ini` beside a private copy), and the homebrew test title must demonstrably write SRAM before the flush probe counts.
- **D-03:** **Owner ruling — periodic flush required.** A candidate passes the save probe only if an on-disk save flush can be observed periodically or on-demand during play, not solely at clean exit. If mGBA standalone cannot demonstrate one, RetroArch+mGBA wins even if mGBA passes every other probe. Rationale: priority #2 (reliable local play and save continuity) and Phase 4's capture contract outweigh adapter simplicity.
- **D-04:** Distribution posture: **Developer ID direct distribution, notarized, hardened runtime, NOT App-Sandboxed.** Child processes inherit the sandbox, which breaks launching a downloaded third-party emulator; Keychain, Game Controller framework, and future Sparkle updates all work without the sandbox; App Store review is historically hostile to emulator launchers. — **Reversibility:** costly — sandbox adoption later changes file-access, process-launch, and update architecture across the client.
- **D-05:** Emulator install model: **download-on-demand from official upstream releases, version-pinned and SHA-256-verified** into an app-managed directory (this is PLAY-01's "install"); "select an existing install" is a hash-badged secondary path. Never bundle an emulator inside Playstead.app in v1 (nested-signing coupling); never strip quarantine xattrs.
- **D-06:** BIOS posture: ship on **mGBA's built-in HLE BIOS by default** with honest fidelity caveats displayed; PLAY-03 drag-in validates an official `gba_bios.bin` by size + digest through the Phase 2 DAT hash-match primitive; open BIOS replacements stay undeclared in v1. No acquisition or distribution path anywhere.

### Curation Ownership and Sync

- **D-07:** All five curation nouns — Favorites, Collections, Continue, Recent, play queue — are **server-canonical, per-user, synced**. The queue is a backlog/watchlist, not a per-device playback buffer ("new computer, same library"). Recent/Continue derive from coarse play events: `POST /api/v1/play-sessions` carrying UUIDv7 id, game, start/end only — queued in the Mac outbox, deletable, and **never on the launch path**. Continue = recently played minus explicit dismissals; its microcopy promises recency, never save restore, until Phase 4.
- **D-08:** Protocol: add **one new `curation` change-journal entity kind** (payload `type` ∈ favorite | collection | collection_member | queue_item | continue_dismissal | recent) plus a `curation` snapshot branch, riding the P1 D-21 recovery spine rather than a second sync path. This is an explicit, logged additive amendment to the Phase 1 frozen entity-kind set and **must land in Phase 3, before the first client ships** (zero deployed clients break now; afterward it needs capability gating). Curation is never stuffed into the frozen P2 D-23 `catalogue` payload. — **Reversibility:** one-way — journal kinds and their payloads are published client protocol; additions only, never renames.
- **D-09:** Mutations are per-row REST intents with `Idempotency-Key` + client UUIDv7 natural keys (P1 D-20 mechanics, nothing new). Conflict semantics: **LWW-per-row** for favorites and collection membership; **fractional-index positions with server rebalance** for queue and collection ordering. Invariant: **no client ever transmits a whole list as truth** — full-list LWW is the one design that silently drops a concurrent offline addition. Drag reorders coalesce into one settled position command; intermediate moves are never journaled.
- **D-10:** Data model: manual, flat, **ordered** collections (same fractional-position mechanism as the queue; unordered collections are a documented Plex/Jellyfin regret); Recently Added, per-system, Continue, and Recent are built-in derived views, not stored smart collections; one queue per user; P2 D-22 name sanitization reused; sanity caps 500 collections / 5k members per collection / 500 queue items.
- **D-11:** Console parity: the LiveView console ships all five shelves with full curation in Phase 3, via the same context functions as the API (LiveView is never the protocol). The Mac client adds launch/preflight integration and availability badges on top of the same canonical views.

### Library Experience Without Artwork

- **D-12:** Visual identity is **typographic-first**: per-system accent color + system monogram tiles, landscape (not box-art portrait) ratio, horizontal shelves for curated rows plus a sortable list for system/all browsing. No procedural fake box art, no per-title hash colors — type-led surfaces read as intentional; placeholder-art surfaces read as broken.
- **D-13:** Card anatomy: three zones — dominant two-line title; meta line of system monogram + quiet region/version chips (P2 D-22 tags) + the P2 D-26 "Not yet identified" inline badge; and **exactly one status slot** showing the highest-priority state as a distinct glyph+shape on a strict ladder: attention > missing dependency > downloading (determinate ring) > queued > verified/pinned > server-only. List view adds text labels; VoiceOver gets full sentences. Safe-to-evict is a storage-view concept, never a card badge. System-identity hues and status semantics are two separate color vocabularies, and no state is color-only (QUAL-01 / WCAG 1.4.1).
- **D-14:** Navigation: Mac source-list sidebar ordered Home/Continue, Favorites, Collections, Queue, Recent, then non-empty Systems, Unidentified last — mapping 1:1 to a responsive LiveView sidebar. Controller: d-pad spatial focus via `.focusSection()` per shelf, LB/RB shoulder-cycling of sidebar sections, Menu-button context sheet. Search (LIBR-02) on controller = d-pad filter chips (system/availability); no on-screen keyboard in Phase 3. Keyboard, pointer, and VoiceOver paths stay fully equivalent; controller disconnect never strands (QUAL-01).
- **D-15:** First-run and empty states: a newly paired Mac is **not empty** — the full catalogue renders immediately with quiet cloud marks, one dismissible "your library lives on your server" banner, and a small recommended-first-downloads shelf that never auto-downloads. A zero-import server shows one calm import invitation. Empty curation shelves are hidden from Home but their sidebar nouns remain with one-line explainers. LIBR-04: empty systems hide behind "Show all systems" with counts; system/BIOS/controller settings surface contextually at first download and as preflight remedies.
- **D-16:** Motion only where it explains state: determinate progress ring morphing to a verified check, ~120 ms directional focus ring, in-place crossfade to a cloud mark on eviction (items never vanish). No ambient tile motion, staggered fly-ins, or marquee titles. Reduced motion keeps ring fill, swaps morphs/transitions for instant/crossfade. Open from local read models with zero skeletons on synced views; fixed tile heights, clamped titles, `LazyVGrid`/LiveView streams for 500+ items (interactive < 1 s cold).
- **D-17:** The status-glyph vocabulary, priority ladder, IA noun order, and empty-state copy live in **one shared spec both clients cite** — SwiftUI/HEEx parity drift is the top long-term risk. This phase requires a UI-SPEC pass (`/gsd-ui-phase 3`) before implementation; the typographic identity is carried entirely by execution quality. A server-only card's primary action is **Download** — never a disabled Play; Play appears only after verified preflight.

### Cache and Download Semantics

- **D-18:** Transfer: **whole-blob GET with single-range resume** — `Range: bytes=N-` + `If-Range: "<sha256>"` — via an in-process URLSession actor (not `URLSessionDownloadTask` background sessions: resume ignores custom Range headers and the OS can purge its temp files). Sequential members, one game at a time; infinite backoff retry. Resume re-hashes the partial prefix from disk (disk-as-truth; persisted hash state can desync after a crash), then full-hash verify → rename-commit into the local CAS. The client hard-checks for 200-instead-of-206 on resume and truncates/restarts — appending a full body after a partial prefix is the classic silent-corruption footgun.
- **D-19:** The server's Range contract is **deliberately frozen as protocol** in this phase (completing what P2 D-33 deferred): quoted strong `ETag: "<sha256>"` (the current controller emits unquoted — fix it), `Accept-Ranges: bytes`, single-range 206 with correct `Content-Range` served through the P2 D-12 `stream/2` seam (not `send_chunked`), `If-Range`, 416, HEAD, identity encoding only, multi-range collapsed to full 200. Contract tests cover all of it, including a kill-and-resume byte-identity test. `range-resume` is advertised in the `transfer` capability namespace (P1 D-19) so version skew degrades with an explained remedy. — **Reversibility:** one-way — Range/ETag semantics become published client protocol every future client's transfer engine builds on.
- **D-20:** Mac cache layout: **sha256 CAS mirroring the server's P2 D-11 layout** under `~/Library/Application Support/Playstead/` (Time-Machine-excluded), with per-game launch directories materialized via APFS `clonefile` (plain copy fallback, **never hardlink** — an emulator writing through a hardlink corrupts the verified CAS copy). `~/Library/Caches/` is rejected: OS purge would silently break the "pinned-offline" promise. — **Reversibility:** costly — the cache layout is what eviction, verification, and the adapter materialization step all key off.
- **D-21:** Capacity policy: fixed quota (default 25 GB) **plus** a free-space floor (10 GB; the floor wins). At the limit, downloads block/pause with an honest reclaim prompt — **no silent deletion ever**; eviction is manual-only in Phase 3 with LRU-ordered suggestions. Pin is per-game = never evictable + download-queue priority. The six CACH-02 states are derived at read time from (queue row, partial file, CAS entry, pin flag) — never a stored enum that can drift from disk.
- **D-22:** Download queue: persistent, user-visible, ordered (local SQLite, UUIDv7 ids), sequential by default, per-item pause/resume/cancel/reorder, auto-resume on reachability; queued-while-offline is a quiet normal state. Queue rows plus disk facts are the state machine feeding CACH-02.
- **D-23:** Verification lifecycle: the full hash at download completion is the authority. Launch preflight trusts it through a cheap size+inode+mtime check, falling back to a full re-hash on mismatch — with **zero network calls** (CACH-04). No periodic scrub in Phase 3 (the server is canonical; client bit-rot is a redownload, not a data-safety event). Corruption → quarantine + automatic redownload with no-blame copy.

### Claude's Discretion

- SwiftUI app architecture, module layout, and the local persistence library choice (SQLite wrapper etc.), provided queue/cache state derivation rules above hold.
- Phoenix schema/table naming, curation REST route shapes, fractional-index encoding, and rebalance mechanics — follow idiomatic Phoenix 1.8 and P1/P2 conventions.
- Exact glyphs, accent palette values, and type scale within the two-vocabulary and non-color-only rules — the UI-SPEC pass refines these.
- Spike homebrew test-title selection (must verifiably write SRAM) and SPIKE-REPORT format.
- Exact quota/reclaim microcopy within the honesty rules (D-21, EXPERIENCE-ETHOS).
- Whether play-session events batch or post individually from the outbox.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project foundation
- `.planning/PROJECT.md` — constraints (content posture, offline, compatibility-matrix honesty, security), priority order (data safety > reliable play/saves > clarity/low-admin > performance > delight > breadth), Key Decisions, Project DNA.
- `.planning/REQUIREMENTS.md` — LIBR-01…05, CACH-01…04, PLAY-01…05, QUAL-01 verbatim; SAVE-01…04/PORT-01 boundaries (Phase 4).
- `.planning/ROADMAP.md` §Phase 3 — goal, five success criteria, and the mandatory Mac adapter gate.

### Prior phase contracts (build on, never reshape)
- `.planning/phases/01-private-custody-and-durable-protocol/01-CONTEXT.md` — P1 D-07/D-10 (pairing, Keychain credential, CA pinning), D-18 (additive-only /api/v1), D-19 (capability namespaces incl. `cache`/`transfer`/`adapter`), D-20 (idempotency + UUIDv7 keys), D-21 (journal/snapshot/cursor/410), D-22 (problem+json codes).
- `.planning/phases/02-explainable-import-and-exact-export/02-CONTEXT.md` — P2 D-11/D-12 (CAS + store seam), D-14 (seven system ids), D-15 (asset_member roles/required), D-22 (display titles/tags), D-23 (catalogue payload — the client contract), D-26 (quiet-badge philosophy), D-30 (journal vs REST split), D-33 (blobs endpoint, Range deferred to here).

### Discovery corpus (design authority)
- `.planning/discovery/WEB-AND-CLIENT-ARCHITECTURE.md` — SwiftUI+AppKit rationale, adapter host boundary, Mac client interaction model, API/OpenAPI discipline.
- `.planning/discovery/EXPERIENCE-ETHOS.md` — interaction contracts, quiet-by-default, humane exceptions, motion rules.
- `.planning/discovery/TECHNICAL-RISKS.md` — BIOS/legal posture, emulator integration threats, offline risks.

### Phase 3 discussion research (option tables, adversarial passes, prior art, sources)
- `.planning/phases/03-mac-offline-play-vertical-slice/discussion-research/A-adapter-spike-and-first-emulator.md`
- `.planning/phases/03-mac-offline-play-vertical-slice/discussion-research/B-curation-ownership-and-sync.md`
- `.planning/phases/03-mac-offline-play-vertical-slice/discussion-research/C-library-experience-without-artwork.md`
- `.planning/phases/03-mac-offline-play-vertical-slice/discussion-research/D-cache-and-download-semantics.md`

### External standards and platform docs adopted by decision
- RFC 9110 §14 (HTTP Range/If-Range/206/416 semantics) — D-18/D-19 transfer contract.
- RFC 9457 + IETF Idempotency-Key draft — inherited for every new endpoint.
- Apple: notarization/hardened-runtime docs, Game Controller framework, `clonefile(2)` — D-04, D-14, D-20.
- mGBA (MPL-2.0) and RetroArch/libretro licensing pages — D-02/D-05 candidate and bundling constraints.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `playstead-mac/` contains only a README — the SwiftUI client is greenfield; this phase creates it.
- `Playstead.Sync.ChangeJournal` / `EntityKind` / `Snapshot` / `Compaction` — D-08 adds the `curation` kind + snapshot branch through the existing registration and advisory-lock fencing.
- `Playstead.Idempotency` — curation intents and play-session posts reuse the plug + receipt-in-transaction pattern unchanged.
- `PlaysteadWeb.API.V1.BlobsController` (`blobs_controller.ex`) — exists with ETag/basic serving; D-19 hardens it into the frozen Range contract through `Playstead.Blobs.Store.stream/2`.
- `Playstead.Catalogue.list_assets/2` / `get_asset_detail/2` — the console library read surface to extend with curation shelves.
- `Playstead.AuditLog`, `Playstead.RateLimiter`, `PlaysteadWeb.Problem` / `error_codes.ex` — new mutations, limits, and codes slot into the existing registries.
- Capabilities handshake (`hello_controller.ex`) — advertise `range-resume` under `transfer` and the adapter/save declarations the spike produces.

### Established Patterns
- Phoenix 1.8 scopes: every new schema carries `user_id` and context functions take the scope (P1 D-01); contexts own transactions; LiveView calls the same context functions as controllers.
- Contract tests assert problem+json codes and journal convergence, never English strings; migrations forward-only, backward-compatible.
- Journal payloads are additive-only published protocol (P2 D-23 discipline applies to the new `curation` payload).

### Integration Points
- `playstead-server/lib/playstead_web/router.ex` — new `/api/v1/curation/*` (or per-noun) routes, `/api/v1/play-sessions`, hardened `/api/v1/blobs/:sha256` under `:device_auth`; library-console LiveViews under `:require_authenticated_user`.
- `Playstead.Sync.Snapshot` — add the `curation` branch inside the same consistent transaction.
- Phase 4 consumes: the adapter save contract from the spike (D-01/D-03), the launch-dir materialization seam (D-20), and play-session events (D-07).

</code_context>

<specifics>
## Specific Ideas

- Spike probe list (D-01) is the acceptance checklist; the SPIKE-REPORT records macOS build, emulator version + sha256, and per-probe evidence.
- mGBA probing must target the shipped `mGBA.app` binary using portable-mode `config.ini` beside a private copy — CLI/config behavior verified in manpages applies to the SDL binary, not the Qt app.
- Server-only card: primary action **Download**; Play appears only after verified preflight — never a disabled Play button.
- First-run banner: "your library lives on your server" (dismissible, once).
- Status ladder rendering: downloading = determinate ring in the status slot, morphing to a verified check on completion.
- Reclaim honesty: "reclaim only reconstructable unpinned bytes"; the storage view shows what eviction frees and that the server keeps everything.

</specifics>

<deferred>
## Deferred Ideas

- Auto-evict / LRU automatic eviction — v2, after manual eviction proves the trust model.
- Periodic local cache scrub / "verify everything" — Phase 5 (aligns with OPER-03/PORT-03 server scrub).
- On-screen keyboard for controller text search — later; Phase 3 controller search is filter chips.
- Stored smart collections (rule-based) — v2; Phase 3 ships derived views only.
- Open BIOS replacement declarations (e.g. Cult-of-GBA) — v1 ships HLE default; per-system legal review later.
- Sparkle auto-update for the Mac app — later phase; posture (D-04) keeps it possible.
- Background URLSession transfers / chunked or content-defined-chunking transfer, tus/multipart — TRAN-01 (v2) under the `transfer` capability.
- Metadata/artwork providers — META-01 (v2); the typographic identity is designed to survive their arrival as an enhancement, not a rescue.
- Household sharing of collections/queues — v2 (schema is per-user-ready).
- Second client/adapter, browser play — separate later spikes (PROJECT.md Out of Scope).
- Play-event analytics beyond Recent/Continue derivation (playtime stats, streaks) — v2 curation.

</deferred>

---

*Phase: 03-mac-offline-play-vertical-slice*
*Context gathered: 2026-08-30*
