# Domain Pitfalls: Personal Emulation Library and Continuity System

**Project:** Playstead
**Domain:** Private, self-hosted ROM library, offline-capable clients, and revisioned save continuity  
**Researched:** 2026-08-26  
**Confidence:** MEDIUM — the guidance consolidates project discovery evidence. Assertions marked **Confirmed** are supported by the cited discovery source ledgers; **Inference** is a project decision drawn from that evidence and must be validated in its delivery phase.

## Critical Pitfalls

### 1. Opaque custody and an inventory-dump experience

**What goes wrong:** Import looks successful but the user cannot tell whether bytes were copied, referenced, deduplicated, moved, or safely backed up. The library becomes a raw file table or a wall of empty systems, while unknown and imperfect media are treated as failures rather than recoverable exceptions.

**Evidence:** **Confirmed:** OpenEmu, Playnite, and RomM reports document managed-library/manual-file, duplicate-path, and scan-visibility failures. The product constitution requires managed-copy receipts, curated views, progressive disclosure, and humane exception handling. [USER-FEEDBACK S01–S08; EXPERIENCE-ETHOS §§1–6, 15–17] **Inference:** custody language and curation are reliability features, not cosmetic UI work.

**Prevention:** Make **Copy into my library** the only v1 import contract; retain source provenance and exact outcomes. Give every operation a durable receipt and route unknown, patched, malformed, incomplete, or ambiguous items to a calm Needs Attention inbox. Lead browse with Continue, Favorites, Collections, Queue, and Recent; hide empty/unconfigured systems by default. Never describe one repository disk or a queued write as a backup/success.

**Warning signs:** UI labels say only “imported” or “synced”; a user needs filesystem archaeology to determine custody; all systems render even when empty; exceptions disappear from browse; healthy routine jobs generate alerts.

**Phase to address:** **Phase 1 — Domain, custody, and durable API foundation**; enforce in **Phase 3 — Mac vertical slice and library experience**.

---

### 2. Treating a game as one filename or a hash match

**What goes wrong:** The system loses or mislabels CUE+track, multi-disc, CHD-parent, arcade+BIOS, patched, overdumped, and regional/alias content. Filename, CRC, metadata, or multipart ETag is mistaken for canonical identity; automatic normalization breaks exact export and provenance.

**Evidence:** **Confirmed:** the technical research specifies immutable SHA-256 blob identity, asset-set manifests, provider/version/confidence provenance, and exact-byte retention; OpenEmu documents multi-file optical-media constraints and custom PSX recognition failures. [TECHNICAL-RISKS: “Content and metadata model”, “Import…semantics”, S01, S06, S15; USER-FEEDBACK S01, S03, S07] **Inference:** release/group identity must be independently modeled before UI or emulator integration.

**Prevention:** Store original bytes unchanged under generated content-addressed keys. Separate `blob`, `source_file`, `asset_set`, ordered `asset_member`, and `recognition`; use SHA-256 only for exact-byte object identity/deduplication, and treat DAT hashes/serials as matching evidence. Validate a complete manifest before publishing playable status. Preserve aliases and variants, preserve matcher source/version/confidence and user overrides, and make patch application an explicit derived-asset action.

**Warning signs:** a database schema has a single `rom_path` per game; import silently unzips/renames/patches bytes; hash equality hides a regional or patched variant; a disc set is marked playable with missing tracks; recognition failure rejects otherwise retained content.

**Phase to address:** **Phase 1 — Domain, custody, and durable API foundation**, with a required **disc/manifest spike** before broader format support.

---

### 3. Parsing archives or untrusted metadata in trusted, unbounded workers

**What goes wrong:** A crafted archive/header/path causes resource exhaustion, traversal, symlink overwrite, parser compromise, data leakage, or a permanently stuck import. Supervision restarts a process but does not make unsafe parsing, quota breaches, or side effects safe.

**Evidence:** **Confirmed:** OWASP guidance and the technical threat model call out decompression bombs, traversal, symlinks, archive recursion, and untrusted filenames/metadata/emulator output. [TECHNICAL-RISKS: “Security and operational threat model”, S17–S18; PROJECT Constraints] **Inference:** opaque storage first with narrowly enabled inspection is the safe initial product posture.

**Prevention:** Accept a small magic-byte-validated allowlist; preserve archives opaque by default. Isolate any inspection/extraction in an unprivileged sandbox with CPU, memory, wall-clock, recursion, member-count, compressed/decompressed-size, path, and concurrency limits. Generate storage keys; reject absolute, traversal, NUL/control paths and archive symlinks. Quarantine with a recoverable diagnostic and test adversarial fixtures/fuzz corpus in CI before enabling a parser.

**Warning signs:** archive metadata is trusted for size; extractor writes user paths directly; jobs have no byte/time budget; nested archives are accepted; logs contain raw filenames or hashes; parser crashes are retried indefinitely.

**Phase to address:** **Phase 2 — Secure importer and staged jobs**, preceded by the required **archive-security spike**.

---

### 4. Ephemeral or unbounded background work

**What goes wrong:** Hashing, import, transfer, and identification run in a request/LiveView process; reconnects or restarts duplicate work, restamp unchanged records, lose cancellation semantics, or overload disk, database, and remote metadata providers.

**Evidence:** **Confirmed:** LiveView remount/reconnect behavior means assigns and async work are not durable; RomM incidents cover hangs and rescans that restamp unchanged content. [WEB-AND-CLIENT-ARCHITECTURE: “LiveView constraints”, “Command, event, and offline model”; USER-FEEDBACK S06–S08] **Inference:** durable job and command records are a prerequisite, not later operations polish.

**Prevention:** Persist an idempotency-keyed import/transfer command and job before work starts. Use staged discovery → cheap fingerprint → strong hash on new/changed/ambiguous bytes → identification → enrichment, with per-stage checkpoints, bounded queues, per-tenant byte/concurrency quotas, cancellation, backoff, and reconciliation. Keep `last_seen_at`, content version, and job attempt/outcome distinct. Retried steps must adopt verified prior output rather than recreate blobs or events.

**Warning signs:** progress exists only in a socket/LiveView assign; retry can create two library items; unchanged scan results update content timestamps; no explicit state for paused/cancelled/abandoned; a large directory makes normal API latency climb.

**Phase to address:** **Phase 2 — Secure importer and staged jobs**; validate under interruption/load in **Phase 6 — Operations, recovery, and release engineering**.

---

### 5. Calling canonical storage a backup, or making export unrecoverable

**What goes wrong:** A volume/mount change, bad migration, object-store lifecycle rule, or disk loss destroys the only copy. Export produces reorganized/modified bytes or an undocumented layout that cannot be independently verified. Deduplication assumptions fail across Docker volumes/filesystems.

**Evidence:** **Confirmed:** OpenEmu and RomM evidence covers relocation, mount, and hardlink-topology failures; project requirements explicitly distinguish repository, cache, and independent backup. [USER-FEEDBACK S01–S05; EXPERIENCE-ETHOS §16; TECHNICAL-RISKS: “Import…export semantics”, “Object storage”] **Inference:** restore drills, rather than a green status badge, establish backup truth.

**Prevention:** Treat the server as canonical repository, clients as reconstructable caches, and backups as independent verified copies. Record stable IDs and hashes rather than absolute paths. Provide mount identity/read-write/free-space health, relocation dry run/rollback, retention-aware full and incremental backup, and periodic restore verification. Export exact bytes into a deterministic ordinary-folder layout with a readable manifest and post-export hashes; rehash on reimport. Report reflink/copy/hardlink behavior accurately.

**Warning signs:** “protected” means only one disk has data; backups have never restored into a clean environment; source paths are primary keys; exported files lack manifest/hashes; an upgrade changes storage layout without preflight or rollback.

**Phase to address:** Design in **Phase 1 — Domain, custody, and durable API foundation**; ship/verify in **Phase 6 — Operations, recovery, and release engineering**.

---

### 6. Offline cache that is neither verified nor truthfully represented

**What goes wrong:** A client reports a game as available although only part of a manifest is cached; eviction removes data needed for launch; the app blocks launch on server/metadata/achievement reachability; a browser or native client mistakes its cache for a backup.

**Evidence:** **Confirmed:** the project requires Range + SHA-256 verified selective caches and local launch without optional services. Web research distinguishes durable native cache from browser quota/eviction semantics. [PROJECT Requirements/Constraints; TECHNICAL-RISKS: “Download/offline cache”; WEB-AND-CLIENT-ARCHITECTURE: “First Mac Client”, “Optional Browser Emulation”] **Inference:** availability is an explicit state machine, not a boolean.

**Prevention:** Cache immutable blobs by `(sha256, byte_size)` plus manifest, with Range/resume, ETag conditional reads, final SHA-256 verification, user-controlled capacity, pinning, and LRU eviction of only reconstructable entries. Show server-only, queued, partial, verified-local, pinned, and safe-to-evict states. Enable launch only after every required manifest member is verified and local adapter preflight succeeds; keep all enrichment off the launch path.

**Warning signs:** one “Downloaded” label covers partial bytes; launch sends a network request for metadata; cache deletion jeopardizes canonical content; offline behavior is untested after server shutdown; browser cache is promised as durable storage.

**Phase to address:** **Phase 3 — Mac vertical slice and library experience**; browser-specific cache semantics only in a later **browser-client spike**.

---

### 7. Silent save overwrite and false portability claims

**What goes wrong:** Concurrent devices overwrite each other, a crash uploads a partially flushed file, or save states are presented as portable across cores/builds/platforms despite implementation-bound serialization.

**Evidence:** **Confirmed:** webRcade uses device/browser linking; Libretro separates save/state paths and notes optional serialization; project evidence requires immutable revisions, `base_revision`, and manual conflict resolution. [USER-FEEDBACK S09–S12; TECHNICAL-RISKS: “Save synchronization”, S09–S13] **Inference:** only adapter-proven persistent-save classes belong in v1 sync.

**Prevention:** Pair devices with revocable identity/tokens. Synchronize only adapter-declared battery/NVRAM (and explicitly proven memory-card) paths after safe flush/stable-file debounce. Append immutable, checksummed revisions and advance a mutable head only when `base_revision` matches; divergent writes create retained conflict heads with device/last-launch context and explicit restore/copy/export choice. Treat states as local-only experimental artifacts keyed by emulator/core build, platform, content hash, and options fingerprint.

**Warning signs:** timestamps decide save conflicts; “synced” appears while an upload is queued; game title alone keys a save; continuous file watching uploads during writes; state files lack adapter/version metadata.

**Phase to address:** **Phase 4 — Save continuity and conflict recovery**, after the required **adapter and save-compatibility spikes**.

---

### 8. Server-owned emulator behavior and controller configuration promises

**What goes wrong:** Server models accumulate local paths, core options, controller mappings, and macOS process assumptions; a release breaks a formerly playable configuration; users are stranded when Bluetooth/controller index/mapping changes or an external emulator cannot be launched under the chosen sandbox/distribution model.

**Evidence:** **Confirmed:** controller regressions and platform-specific profile differences recur in emulator ecosystems; Apple integration requires controller, code-signing/notarization, and filesystem/process behavior to be proven. [USER-FEEDBACK S13–S18; TECHNICAL-RISKS: “Protocol and adapter boundary”; WEB-AND-CLIENT-ARCHITECTURE: “First Mac Client”] **Inference:** the adapter must own all platform effects and report versioned capabilities.

**Prevention:** Keep adapters client-side: discover → materialize → preflight → launch → observe safe save flush → collect controls. Require a versioned adapter fingerprint and capability matrix for system/core/BIOS/save classes; record known-playable configurations and preflight upgrades with rollback. Store raw device/platform profile separately from an editable semantic logical mapping and adapter-specific mapping. Provide visible controller test, reconnect/player assignment recovery, keyboard/pointer/assistive fallback, and reduced-motion accessible focus.

**Warning signs:** server tables contain emulator executable paths; “supports PlayStation” has no core/version matrix; UI is controller-only or mouse-only; release test covers only one controller; notarization/sandbox is assumed rather than exercised with a legal test asset.

**Phase to address:** **Phase 3 — Mac vertical slice and adapter spike**, with upgrade compatibility gates in **Phase 6 — Operations, recovery, and release engineering**.

---

### 9. Letting LiveView become the client protocol

**What goes wrong:** Native/offline clients depend on rendered HTML, sockets, LiveView events, or ephemeral push acknowledgements. Missed notifications, reconnects, and server/client version skew produce divergent state or duplicate mutations.

**Evidence:** **Confirmed:** LiveView reconnects/remounts and may stop async work when its process exits; the architecture calls for `/api/v1`, capability negotiation, idempotency keys, durable cursor changes, and Range downloads. [WEB-AND-CLIENT-ARCHITECTURE: “Recommended Boundary”, “LiveView constraints”, “Durable API”] **Inference:** LiveView is the excellent first-party console, not the cross-platform boundary.

**Prevention:** Keep domain services transport-free. Version `/api/v1`; publish schemas/examples, compatibility/deprecation policy, capability hello, stable errors, cursored change journal with snapshot/reset semantics, and idempotent commands/outbox replay. LiveView may call domain services and use push for acceleration, but reload/HTTP poll must reconstruct the same truth. Validate all LiveView params and authorization independently.

**Warning signs:** an operation ID exists only in an assign; native-client requirement says “listen for socket event”; API has no idempotency semantics or change cursor; HTML fragments are reused as an SDK; dropped-notification tests do not converge.

**Phase to address:** **Phase 1 — Domain, custody, and durable API foundation**, proven in **Phase 3 — Mac vertical slice**.

---

### 10. Accidental public distribution, insecure hosting, or metadata-license drift

**What goes wrong:** A private organizer grows sharing/search/acquisition features, proprietary BIOS distribution, misleading “ownership verification,” public object URLs, or a hosted tier by merely enabling S3. Redistributed DAT/artwork is assumed license-free.

**Evidence:** **Confirmed:** the project excludes public content distribution and v1 hosting; technical research identifies separate hosted legal, privacy, abuse, tenant-isolation, and operational requirements, and flags third-party metadata license/provenance. [PROJECT Out of Scope/Constraints; TECHNICAL-RISKS: “Database roles…licensing”, “Legal/product posture”, S02, S19–S24] **Inference:** hosted launch is a separate product/research program, not a deployment option.

**Prevention:** Default to private authenticated tenancy, TLS, CSRF protection for web sessions, audit trail, non-predictable authorized blob/manifest access, rate/byte/concurrency quotas, and minimized telemetry. Never distribute/locate ROMs or proprietary BIOS, claim a hash proves ownership, or upload private files to public scanners without consent. Ship no third-party DAT payload/artwork until source, revision, license, attribution, and downstream obligations are recorded. Require counsel, policy/takedown/abuse/privacy design, vendor review, tenant isolation, incident response, and cost/SRE plan before hosted service.

**Warning signs:** a “share” link works without an authorization model; object-store credentials are exposed to clients; docs say “legal ROMs only” as a compliance mechanism; packaged metadata has no provenance/license; hosting appears in the roadmap as an infrastructure toggle.

**Phase to address:** Private security posture in **Phase 1–2**; any hosted offering is a **separate post-v1 discovery and compliance phase**.

---

### 11. Quiet operational failure, unrehearsed updates, and premature ecosystem expansion

**What goes wrong:** A container upgrade, mount permission drift, orphaned multipart upload, failed migration, or client/core update leaves data/playability broken without recovery evidence. Conversely, new platforms, browser play, repositories, achievements, or streaming are added before the initial contracts have multiple proven consumers.

**Evidence:** **Confirmed:** update churn affects controller, Wi-Fi, cores, paths, and mounts; project requirements call for compatibility checks, migration preflight, rollback, observability, and a narrow first proof. [USER-FEEDBACK S05, S08, S18; EXPERIENCE-ETHOS §§3–4, 13–14; PROJECT Key Decisions/Constraints] **Inference:** observable, recoverable operations and a stable monorepo/domain boundary are the feature-bloat countermeasure.

**Prevention:** Provide an opinionated persistent-container path with UID/GID/mount validation, health endpoints, storage inventory, low-noise actionable diagnostics, compatibility records, migration snapshot/preflight, atomic update where possible, rollback, and post-update verification. Alert only on action/risk; keep expert bundles on demand. Keep one repository and build contracts/adapters first; split a library only after a stable boundary and at least two real consumers. Defer browser play, second platform, broad format support, cross-version states, streaming, netplay, achievements, social/recommendation features, and custom appliance work until they pass isolated spikes without weakening local play.

**Warning signs:** an update is “successful” when the container starts; no restore/relaunch test after upgrade; operational failures require raw logs; a proposed shared package has one consumer; roadmap adds platform/features before the Mac slice restores and exports exact bytes.

**Phase to address:** Baseline in **Phase 1–2**; full backup/update/recovery verification in **Phase 6 — Operations, recovery, and release engineering**; expansion only after the vertical slice is validated.

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|---|---|---|---|
| One `game.path`/filename identity | Fast CRUD demo | Cannot model aliases, disc sets, export, dedupe, or provenance | Never |
| Hashing only after copy completes | Simpler importer | Duplicate objects, unverifiable partial uploads, weak receipts | Never |
| LiveView/socket-owned jobs | Fast progress UI | Lost/repeated work on navigation or reconnect | Never for durable work |
| Last-write-wins save sync | Fewest screens | Silent progress loss | Never |
| Treating save states like persistent saves | Early cross-device demo | Corruption and broken portability promises | Only local experimental artifacts with explicit fingerprint |
| Server-side emulator paths/options | Faster first launch | Platform coupling and untestable compatibility | Never |
| Reference-in-place or managed move | Less storage initially | Broken portability, rollback, permissions, custody semantics | Spike only; not v1 |
| Split protocol/core repositories early | Perceived reuse | Version choreography and speculative abstractions | Only after stable boundary + multiple consumers |

## Integration and Performance Gotchas

| Area | Common mistake | Correct approach |
|---|---|---|
| Object storage | Treat multipart ETag as object MD5; leave parts orphaned | Verify final stream SHA-256; track/expire/abort upload sessions [TECHNICAL-RISKS S06–S08] |
| Transfer | Invent partial PUT/resume | Start bounded server streaming; spike tus or S3 multipart before multi-GB remote transfers |
| Metadata/DAT | Make metadata authoritative or redistribute without review | Keep pluggable provider provenance/version/confidence; review license before shipping payload |
| Browser play | Equate WebAssembly with universal/offline emulator support | Separate client/adapter with core/browser/license/isolation/storage capability matrix |
| Scan | Full rehash/restamp on every run | Fingerprint first, strong hash only when needed; integrity verification is explicit |
| Cache | Cache by title or URL | Cache immutable manifest members by SHA-256 + size; verify all members before launch |

## Looks Done But Isn't

- [ ] **Import:** survives a process restart and retry without duplicate blobs/items/events; produces a durable receipt and recoverable quarantine.
- [ ] **Asset set:** CUE+track, multi-disc, BIOS-dependent, unknown, and patched fixtures preserve exact bytes and show correct readiness.
- [ ] **Offline play:** server, metadata, and internet can be unavailable after verification; launch still succeeds from a complete local manifest.
- [ ] **Save sync:** a divergent offline write creates visible retained heads; safe-flush/crash behavior is tested; state compatibility is not overstated.
- [ ] **Export/backup:** independent clean-environment restore and ordinary-folder export/reimport verify every hash.
- [ ] **Mac adapter:** one legal test asset proves external launch, controller fallback, save collection, signing/notarization/sandbox posture, and relaunch after handoff.
- [ ] **API/LiveView:** reload, reconnect, duplicate mount, missed notification, and client retry converge through durable HTTP state.
- [ ] **Updates:** a known-playable configuration survives or is blocked preflight with rollback; container mount/permissions are validated.

## Pitfall-to-Phase Mapping

| Pitfall | Prevention phase | Verification |
|---|---|---|
| Custody/UX opacity; bad identity model; LiveView protocol leakage | Phase 1 — Domain, custody, and durable API foundation | Contract tests for receipts, manifests, provenance, idempotency, cursor convergence |
| Parser exposure; job retries/backpressure | Phase 2 — Secure importer and staged jobs | Adversarial archive corpus; restart/cancel/retry/load tests; no duplicate side effects |
| Offline-cache truth; Mac adapter/controller readiness | Phase 3 — Mac vertical slice and library experience | Offline launch and controller fallback on clean Mac; adapter spike report |
| Save overwrite/compatibility | Phase 4 — Save continuity and conflict recovery | Two-device divergent-save, crash/flush, restore-as-new-revision tests |
| Browser, second adapter, broad formats | Post-v1 scoped spikes | Explicit capability matrix and pass/fail evidence before roadmap promotion |
| Backups, update/recovery, observability | Phase 6 — Operations, recovery, and release engineering | Clean restore drill, migration rollback, mount failure, post-upgrade known-playable checks |
| Hosting/public distribution | Separate post-v1 compliance/discovery phase | Counsel/policy/tenant/abuse/privacy/SRE readiness decision; not an implementation toggle |

## Sources and Provenance

This guide synthesizes, rather than replaces, the linked discovery evidence. Source identifiers below are the authoritative ledgers in those files.

- **Primary project requirements and phase constraints:** [PROJECT.md](../PROJECT.md), especially Requirements, Constraints, Key Decisions, and Open Questions.
- **Product/UX and ecosystem incident evidence:** [USER-FEEDBACK.md](../discovery/USER-FEEDBACK.md), source ledger S01–S18 (OpenEmu, Playnite, RomM, webRcade, ES-DE, EmulationStation, Batocera).
- **Identity, transfer, security, storage, BIOS, legal, and save-contract evidence:** [TECHNICAL-RISKS.md](../discovery/TECHNICAL-RISKS.md), source ledger S01–S24 (Libretro, tus, RFC 9110, AWS/R2, OWASP, U.S. Copyright Office).
- **API/LiveView/Mac/browser boundary evidence:** [WEB-AND-CLIENT-ARCHITECTURE.md](../discovery/WEB-AND-CLIENT-ARCHITECTURE.md), source ledger S01–S17 (Phoenix, Apple, IETF/MDN, Electron/Tauri, EmulatorJS).
- **Product precedence and interaction contracts:** [EXPERIENCE-ETHOS.md](../discovery/EXPERIENCE-ETHOS.md).

Legal and licensing items are implementation-planning constraints, not legal advice; revalidate mutable technical facts and obtain specialist advice before a hosted service, redistribution, or firmware/replacement-BIOS feature.
