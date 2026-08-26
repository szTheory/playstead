# Project Research Summary

**Project:** Emu Server  
**Domain:** Self-hosted, user-custodied game-library and persistent-save continuity system  
**Researched:** 2026-08-26  
**Confidence:** MEDIUM-HIGH for product direction and v1 boundaries; MEDIUM for unspiked platform integrations

## Executive Summary

Emu Server's wedge is not emulation itself, a ROM catalogue, or generic file sync. It is trustworthy personal custody and continuity: a private canonical repository for user-supplied exact bytes, selective verified caches on clients, and independently verified backups. The first product proof must let a clean Mac installation pair, browse without mirroring the library, download one selected game, prove it ready locally, launch it offline through one adapter, preserve a compatible persistent save, restore it on a clean client, and export all original bytes and evidence.

Build this as a modular Phoenix monolith backed by PostgreSQL and a local filesystem object-store adapter, with a versioned HTTPS `/api/v1` as the product boundary and LiveView only as the first-party setup/admin console. The Mac reference client is native SwiftUI with targeted AppKit; it owns cache, Keychain, controller, emulator, BIOS, and filesystem/process effects behind a client-side adapter. Durable domain state, idempotent commands, cursor convergence, immutable manifests, bounded workers, and immutable save revisions are the reliability substrate—not Phoenix/LiveView process supervision or sockets.

The dominant risks are false custody/recovery claims, simplistic one-file game models, unsafe or ephemeral import work, unverified offline cache, and silent save loss. Counter them with managed-copy receipts, SHA-256 blob identity plus multi-member asset manifests, durable staged jobs, manifest-complete cache verification, and `base_revision` save conflicts. Do not expand to browser play, hosted storage, direct multipart transfer, broad archive inspection, or a second platform until their explicit spikes pass; each is a separate capability boundary, not an incremental UI feature.

## Decision Ledger

### Confirmed decisions from PROJECT.md

- **Product boundary:** private, user-supplied content only; preserve/export exact original bytes. Public ROM/BIOS distribution, acquisition assistance, sharing, and ownership verification are out of scope.
- **Core wedge:** canonical repository, selective client cache, and independent backup are distinct promises with distinct health states.
- **Server boundary:** API-first Phoenix with a LiveView console; native and future clients use durable versioned HTTPS, never LiveView sockets, HTML, or assigns as protocol.
- **Data model:** immutable game bytes and mutable saves have distinct models; persistent saves use revision history and conflict handling, while save states are not a v1 portability promise.
- **First proof:** one polished Mac-to-server path with a SwiftUI/AppKit reference client and one deliberately supported adapter.
- **Operations:** local disk first with a later S3-compatible storage port; one opinionated container deployment; no hosted/multi-tenant product in v1.

### Recommendations that require empirical validation

- Begin as a modular monolith with a separate Mac app; do not split SDK/schema repositories until a second real consumer demonstrates the boundary.
- Use server-proxied streaming and standard HTTP Range initially; choose `tus`, S3 multipart, or direct object-store transfer only after interruption/cleanup/authorization spikes.
- The low-risk first-adapter hypothesis is a legal homebrew GBA flow with controlled RetroArch/mGBA integration, but this is not a commitment until launch, save-flush, controller, sandbox, and notarization evidence exists.
- Keep archives opaque initially; permit inspection/extraction only after a resource-isolated adversarial-corpus spike.

## Key Findings

### Recommended Stack

The decisive stack is **Elixir/OTP + Phoenix + PostgreSQL**, delivered as an OTP release through Docker Compose. Phoenix serves both `/api/v1` and LiveView without creating a separate web backend; PostgreSQL is the authority for metadata, authorization, receipts, jobs, change journal, and save revision ancestry. Immutable bytes belong behind a project-owned object-storage port using a persistent local filesystem implementation first. This favors a testable, low-administration custody proof over early cloud or distributed-system complexity.

**Core technologies:**

- **Elixir/OTP and Phoenix** — server, supervision, conventional HTTP API, and release path; use durable records for correctness rather than process lifetime.
- **PostgreSQL 18 (current minor validated at implementation)** with **Ecto/Postgrex** — transactional metadata, job/command receipts, change events, revision ancestry, and hard invariants.
- **Phoenix LiveView** — setup, administration, import review, pairing, library, and job visibility; all state must reconstruct after reload/reconnect.
- **Local filesystem object-store adapter** — canonical immutable blobs on an explicit persistent volume, designed for a later S3-compatible adapter without changing client semantics.
- **Oban** — durable, bounded import/hash/recognition/reconciliation/export/backup-verification work; never use UI-owned tasks for user-visible durable work.
- **OpenApiSpex + OpenAPI fixtures** — versioned API validation and compatibility evidence; retain a small hand-written Swift transport client.
- **SwiftUI with focused AppKit, URLSession, Keychain, and Game Controller** — the native Mac proof of local cache, credentials, accessibility, controller, signing, and emulator-process constraints.
- **Telemetry; ExUnit, StreamData, Mox; Docker Compose** — privacy-safe operational evidence, property/contract testing at seams, and one documented deployment path.

Pin resolver-compatible dependencies, `mix.lock`, compiler/Xcode, PostgreSQL minor, and container image digests at implementation/release time. Do not guess mutable package versions from this research snapshot.

### Expected Features

**Must have (v1 table stakes):**

- Managed-copy import preview, exact-byte stream/hash/storage, provenance receipt, dedupe/variant outcomes, and humane Needs Attention handling.
- Asset-set manifests (including multi-file/disc cases), source/recognition evidence, deterministic exact export, and independently verified backup/restore.
- Private pairing, capability-aware `/api/v1`, idempotent commands, durable jobs, cursor-based changes, authorized Range transfer, and a LiveView operations console.
- Curated, accessible library views—Continue, Favorites, Collections, Queue, Recent, search/filter—and visible readiness instead of an inventory dump.
- Selective manifest-driven cache with partial/verified/pinned/evictable states; verified offline launch through one Mac adapter plus BIOS/controller/cache preflight.
- One adapter-proven persistent-save artifact with immutable revisions, offline outbox, restore history, and explicit divergent-save resolution.
- Low-administration deployment, storage/mount health, backup/restore guidance, upgrade preflight/rollback, diagnostics, and automated quality/security checks.

**Should have (differentiators embedded in v1):**

- A truthful shared vocabulary: **on server**, **ready on this device**, **queued**, **backed up**, and **conflict** must never collapse into a generic "synced" state.
- Explainable automation: every import/match/job has evidence, confidence, a safe next action, and no destructive surprises.
- Curation before recommendations: focused personal views and portable preferences rather than a recommender or exhaustive catalogue as the default.
- Known-playable compatibility records for the first adapter so update success means preserved launchability, not merely an installed update.

**Defer (v1.x/v2+ only after their gates):** second client/adapter; S3/direct/multipart transfer; reference-in-place imports; achievements; launcher bridges; browser play; streaming/netplay/social/recommendations; hosted multi-tenant storage; core/appliance development; universal save-state claims.

### Architecture Approach

Adopt a modular monolith with one-way dependencies: delivery adapters (HTTP and LiveView) call application services; application services enforce transactions/authorization and depend on pure domain contracts plus ports; Postgres, blob storage, metadata providers, workers, and telemetry implement ports. The Mac client consumes only published v1 schemas and client-side adapter contracts. It must never inspect server storage/database state, while the server must never model local executable paths, core options, BIOS materialization, controller mappings, or save-file paths.

**Major components:**

1. **Domain and application services** — library/assets/manifests, imports/receipts, devices/capabilities, transfers/jobs/changes, save slots/revisions/conflicts, audit and recovery invariants.
2. **Protocol and delivery** — `/api/v1` schemas, stable errors, pairing/auth, idempotency, capability hello, cursor sync, Range/conditional bytes; LiveView uses the same services for console-only workflows.
3. **Persistence and storage adapters** — Postgres authoritative logical state plus atomic content-addressed blob staging/commit; metadata sources remain evidence with provenance and user override.
4. **Bounded durable workers** — staging, hashing, recognition, inspection, export, reconciliation, and verification with checkpoints, quotas, cancellation, backoff, and restart adoption.
5. **Mac sync/cache and adapter host** — local outbox, verified selected cache, readiness, materialization, controller/BIOS checks, launch, safe save flush, and capability fingerprints.

### Critical Pitfalls

1. **Opaque custody or raw-inventory UX** — make “Copy into my library” the sole v1 contract; persist receipts/provenance, show exact outcomes, and curate views with a recoverable exception inbox.
2. **One filename/game or hash-match model** — separate immutable blobs, asset sets/members, source files, and recognition evidence; SHA-256 plus size identifies bytes only, never an interchangeable release.
3. **Unsafe parsing and ephemeral/unbounded jobs** — default to narrow opaque ingestion; persist idempotent work before starting, isolate parser work, enforce CPU/memory/size/path/concurrency limits, and test restart/cancel/retry behavior.
4. **False recovery and cache claims** — server repository is not backup; a game is not offline-ready until every manifest member verifies locally and preflight passes; prove clean restore/export rather than display reassuring badges.
5. **Silent save overwrite/platform leakage** — append immutable adapter-fingerprinted revisions, use `base_revision` for conflict heads, and keep emulator/controller/process effects entirely client-side.
6. **LiveView or scope creep becoming semantic infrastructure** — test convergence through ordinary HTTP after reload/missed push; keep browser play, public/hosted features, and third-party metadata/artwork behind separate legal/technical gates.

## Implications for Roadmap

The roadmap should optimize for a single trustworthy Mac-to-server proof, not for a broad feature catalogue. Suggested phase structure follows the architectural dependency graph and treats risk spikes as gates, not optional research.

### Phase 1: Custody Kernel and Durable API Foundation

**Rationale:** Identity, provenance, durable command semantics, and recovery language underpin every import, cache, client, and save workflow. If the model is wrong, later UI and adapter work must be rewritten.

**Delivers:** Phoenix/Postgres skeleton; tenant/user boundary; domain invariants for blobs, asset sets/members, receipts, devices/capabilities, jobs/commands/changes, save revisions; local object-storage port; `/api/v1` pairing/capability/error/idempotency/cursor/manifest/Range contract; baseline migrations, audit, health, and backup model; API contract/property tests.

**Addresses:** exact-byte custody, manifest identity, pairing, capability negotiation, LiveView boundary, truthful repository/cache/backup vocabulary.

**Must avoid:** one-file identity, paths in domain records, LiveView/socket protocol leakage, UI-owned work, unauthenticated blob access, and calling a repository a backup.

**Gate:** contract tests show duplicate mutations converge to the same receipt, missed-notification clients converge via snapshot/cursor reset, and manifest/blob authorization is explicit.

### Phase 2: Secure Managed Import, Export, and Durable Workflows

**Rationale:** Import is the first trust moment and produces the canonical assets used by cache, launch, and restore. It must survive restart and ambiguity before broad discovery/metadata polish.

**Delivers:** managed-copy preview; staged stream/hash/store/commit pipeline; durable Oban-backed jobs with cancellation/retry/reconciliation; receipt/quarantine/Needs Attention outcomes; minimal recognition provenance; deterministic exact export with readable manifest and rehash verification.

**Addresses:** single-file immediacy and collection import through one pipeline, exact dedupe/variants, exception handling, explainable automation, portability.

**Must avoid:** destructive normalization/moves, trust in filename/CRC/ETag identity, unbounded parsing, duplicate side effects, restamping unchanged files, and misleading export.

**Required spike:** archive/security corpus and resource-isolation decision before accepting ZIP/7z/CUE extraction or deep inspection. Until then, retain opaque narrow-format ingestion.

### Phase 3: Mac Adapter Spike and Offline Library Vertical Slice

**Rationale:** This phase proves whether the product’s cross-boundary assumptions are real: signing, sandboxing, controller behavior, cache semantics, emulator launch, BIOS readiness, and local offline operation can only be settled on hardware.

**Delivers:** SwiftUI/AppKit client; pairing and catalogue browse; curation/library/readiness UI; selected Range-resumed verified cache with capacity/pin/eviction state; one adapter’s capability declaration, preflight, materialization, controller fallback, and offline launch using legal homebrew content; LiveView console surfaces backed by durable reads.

**Addresses:** selective cache, curated library, controller-accessible interaction, BIOS/readiness audit, one known-playable launch path.

**Must avoid:** treating partial cache as ready, requiring network enrichment to launch, server-owned paths/options, accessibility/controller dead ends, or universal platform claims.

**Required spike/gate:** choose direct-notarized versus App Store/sandbox posture and first emulator/system only after observed launch, recovery, safe save location/flush, controller, Keychain, and signing/notarization evidence. The likely GBA/mGBA hypothesis is not a roadmap promise.

### Phase 4: Persistent Save Continuity and Clean-Machine Recovery

**Rationale:** Save sync is the core continuity promise but cannot be designed abstractly; it depends on the adapter-proven persistent-save artifact and safe flush semantics from Phase 3.

**Delivers:** paired-device identity, adapter fingerprint compatibility, save capture/outbox, immutable checksummed revisions, `base_revision` head advancement, retained divergent heads and resolution, restore-as-new-revision, and clean-client restore of game plus compatible save.

**Addresses:** offline queued saves, explicit conflict recovery, save history, proven cross-device continuation.

**Must avoid:** timestamps/last-write-wins, blind file watching/partial upload, game-title-only save keys, “queued means backed up,” and portable save-state claims.

**Gate:** two-device divergent offline save and crash/flush tests retain both sides and produce an understandable recovery choice; state files remain local-only unless separately fingerprint-proven.

### Phase 5: Recovery, Upgrade, and Release Proof

**Rationale:** The server only earns its custody/reliability promise after independent recovery and known-playable updates are exercised, not when Compose merely starts.

**Delivers:** documented Compose release, persistent volume/mount/UID-GID validation, storage/queue/database/backup health, full/incremental independent backup, clean restore verification, migration snapshot/preflight/rollback, known-playable compatibility gate, diagnostics, CI release smoke tests and security/licence/SBOM checks.

**Addresses:** honest backup/restore, low-administration operations, actionable low-noise diagnostics, update safety.

**Must avoid:** single-volume “backup,” untested restore, container-start-as-success, blind upgrade, sensitive telemetry/logging, and operational alerts for normal offline clients.

### Post-v1: Earned Expansion Spikes

**Rationale:** These features introduce independent protocol, legal, operational, or platform matrices; they must not dilute the proved core path.

**Candidates only after a pass/fail spike:** second native adapter/client (validates portability before SDK extraction); S3/direct/multipart transfer (interruption/checksum/cleanup/authorization); browser play (one explicit WASM core/system/browser/isolation/cache/controller/save/licence matrix); metadata/artwork/achievements (provenance, terms, attribution); hosting (counsel, privacy, abuse, tenancy, key management, cost, SRE).

### Phase Ordering Rationale

- Model and protocol precede importer/client work because receipts, manifests, idempotency, and cursor convergence define safe retry and offline behavior everywhere.
- Import/export precede cache/launch because only verified immutable manifests can make a local cache or readiness claim truthful.
- The adapter spike precedes save sync because persistent-save types, safe flush, sandboxing, and capability fingerprints are empirical, platform-local facts.
- Backup/update proof follows the complete vertical slice because it must exercise the exact schema, blob, adapter, and compatibility artifacts users depend on.
- Expansion is deferred until two real consumers or an explicit capability matrix prove the proposed boundary; this prevents speculative SDKs, cloud complexity, and portability marketing.

### Research Flags

**Requires deep research/spikes during planning:**

- **Phase 2:** archive inspection/extraction threat model and malicious-corpus tests before enabling parsers; metadata-provider licence/provenance before redistribution.
- **Phase 3:** first emulator/system selection; macOS signing/notarization/sandbox/distribution; external-process lifecycle, controller recovery, BIOS validation, safe save flush using legal homebrew assets.
- **Phase 4:** adapter-specific persistent-save compatibility and crash/debounce behavior; no generalization to states.
- **Post-v1 storage:** server-stream vs `tus` vs S3 multipart/direct transfer under cancellation, revocation, checksum, orphan cleanup, and large-file interruption.
- **Post-v1 browser/hosting:** browser core/system/license/isolation matrix; hosted legal, privacy, abuse, tenant, cost, and SRE design.

**Standard patterns; research-phase can be lighter:**

- **Phase 1:** Phoenix/Postgres/Ecto migrations, OpenAPI contract fixtures, HTTP auth/idempotency/cursor patterns, and local storage port testing.
- **Phase 5:** Compose release hardening, health/readiness, CI quality gates, and restore/migration drills—implementation-specific verification still remains mandatory.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM | Core versions and capabilities were checked against primary vendor/registry documentation; the composed architecture and mutable pins remain project-specific implementation choices. |
| Features | MEDIUM-HIGH | Strongly corroborated by project discovery and user-feedback synthesis; system/core and adapter coverage are intentionally narrow and unproven. |
| Architecture | MEDIUM-HIGH | API/LiveView, custody, domain boundaries, and data-flow conclusions follow confirmed PROJECT.md decisions and documented platform constraints; adapter and remote-storage details await spikes. |
| Pitfalls | MEDIUM | Prevention derives from multiple discovery sources and project constraints, but most operational/effectiveness claims require adversarial and recovery testing in this codebase. |

**Overall confidence:** MEDIUM-HIGH for the narrow v1 roadmap; LOW-MEDIUM for any broad portability, browser, remote storage, or hosted-service promise.

### Gaps to Address

- **First adapter/system and macOS distribution:** select only after an experiential spike establishes legal fixture, emulator licence, external launch, safe save flush, controller behavior, sandbox permissions, and notarization.
- **Account/household boundary:** keep tenant/user scope explicit in Phase 1 even if initial UI is single-user; decide the household authority model before cross-person sharing semantics appear.
- **Metadata/DAT/artwork:** identify sources, revisioning, caching, attribution, and redistribution rights before shipping third-party data or asserting identification quality.
- **Large/remote transfer:** establish need and choose protocol only from measured interruption/recovery results; never invent partial-PUT behavior.
- **Backup target and remote provider:** validate provider terms, encryption/lifecycle, credentials, restore semantics, and a clean restore drill before any S3-compatible adapter is called supported.
- **Browser and hosted products:** remain separate discovery/compliance programs, not later toggles on v1 infrastructure.

## Sources

### Primary / confirmed project decisions (HIGH confidence)

- [PROJECT.md](../PROJECT.md) — core product wedge, requirements, scope boundaries, technology/delivery decisions, first proof, and planning questions.
- [STACK.md](STACK.md) — official Phoenix/LiveView/Oban/OpenApiSpex/PostgreSQL/Apple source checks, stack constraints, and dependency validation strategy.

### Synthesized research (MEDIUM to MEDIUM-HIGH confidence)

- [FEATURES.md](FEATURES.md) — table stakes, differentiators, feature dependency graph, explicit anti-features, and product-surface evidence.
- [ARCHITECTURE.md](ARCHITECTURE.md) — normalized component boundaries, canonical data model, protocol seams, flows, topology, and phase gates.
- [PITFALLS.md](PITFALLS.md) — failure modes, prevention strategies, operational warnings, and phase-to-verification mapping.
- Discovery corpus cited by these files: `discovery/SUMMARY.md`, `LANDSCAPE.md`, `USER-FEEDBACK.md`, `TECHNICAL-RISKS.md`, `WEB-AND-CLIENT-ARCHITECTURE.md`, and `EXPERIENCE-ETHOS.md`.

---
*Research completed: 2026-08-26*  
*Ready for roadmap: yes — begin with the narrow Mac-to-server custody and continuity proof.*
