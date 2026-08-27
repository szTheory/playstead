# Canonical Architecture

**Project:** Playstead
**Domain:** Self-hosted, user-custodied game-library and continuity system  
**Researched:** 2026-08-26  
**Confidence:** MEDIUM-HIGH for v1 boundaries; MEDIUM for unspiked adapter and remote-storage details

## Status and Architectural Stance

This document normalizes the discovery corpus into the implementation architecture. A **confirmed decision** is an explicit decision in `PROJECT.md`; a **recommendation** is the preferred implementation path supported by discovery evidence and still subject to an empirical spike.

**Confirmed decisions**

- The server is API-first Phoenix, with a versioned durable API. Phoenix LiveView is the first-party server-side web console, never the device/client protocol.
- PostgreSQL owns durable metadata and workflow state; immutable game bytes use content addressing with local storage first and an S3-compatible storage abstraction later.
- The initial proof is a native SwiftUI/AppKit Mac reference client. Browser emulation is a later, separately qualified API client.
- Game bytes and mutable saves have different models: preserve original game bytes exactly; use immutable persistent-save revisions with explicit conflict handling.
- Server work is bounded and durable: supervision complements, but does not replace, idempotency, durable records, quotas, resource limits, isolation, and recovery.

**Recommendations**

- Start as a modular Phoenix monolith plus a separate native Mac app. Publish a protocol SDK/schema only after a second adapter or client proves the contract stable.
- Begin with server-proxied streaming uploads and HTTP Range downloads; spike tus or S3 multipart before large remote/resumable uploads.
- Prove one narrowly documented Mac emulator adapter and persistent-save type, then use a second adapter/client to test that server contracts have not acquired platform assumptions.

## System Overview

```
                                          first-party web delivery only
┌──────────────────────────────┐        ┌────────────────────────────────┐
│ Native Mac reference client  │        │ Phoenix LiveView console       │
│ SwiftUI + targeted AppKit    │        │ setup / library / import / ops │
│ local cache + sync outbox    │        └───────────────┬────────────────┘
│ client emulator adapter host │                        │ application services/read models
└───────────────┬──────────────┘                        │
                │ HTTPS /api/v1: JSON, commands, Range, changes
                └─────────────────────────┬─────────────┘
                                          ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ Phoenix application                                                        │
│  HTTP API / auth-policy │ LiveView │ application services │ read models  │
│                           ▼ one-way                                         │
│  Domain: library · assets · imports · transfers · devices · saves · jobs   │
│                           ▼ ports                                           │
│  Adapters: Postgres │ local object storage │ later S3 │ metadata providers │
│            bounded worker runners │ telemetry / audit                      │
└──────────────────────────┬─────────────────────────┬──────────────────────┘
                           │                         │
                 PostgreSQL durable state    immutable content-addressed blobs
                 jobs/change journal         local volume first; S3-compatible later

Local-only Mac concerns: selected files, cache paths, BIOS materialization,
controller/input, emulator process lifecycle, safe save flush, and keychain.
They are deliberately outside the server domain and wire model.
```

### Component Boundaries and Data Ownership

| Component | Owns | Must not own / depend on |
|---|---|---|
| **Domain** | Invariants and entities: tenant/user, library item, asset set/member, blob reference, import receipt, recognition assertion, device, installation, transfer, save slot/revision/conflict, job intent | Phoenix connection/request types, Ecto schemas, storage paths, LiveView assigns, Swift types, emulator paths/settings |
| **Application services** | Transaction boundaries, authorization decisions, commands, durable job creation, read-model queries, domain events | HTTP/LiveView rendering and provider/vendor details |
| **HTTP API `/api/v1`** | Versioned wire schemas, validation at the transport edge, stable errors, authentication translation, idempotency-key handling, conditional/range response semantics | UI fragments, socket lifecycle as acknowledgement, emulator/platform behavior |
| **LiveView console** | Server setup, admin, pairing approval, import review/receipts, library views, job visibility | Native-client protocol; any unrecoverable state held only in assigns |
| **Storage port/adapters** | Atomic immutable blob staging/commit, retrieval, integrity verification, lifecycle cleanup; local filesystem adapter first, S3-compatible adapter later | Business identity or client authorization policy |
| **PostgreSQL repository** | Authoritative relational metadata, revision ancestry, durable job/change/outbox/audit state, transaction coordination | Blob payloads and unbounded queue payloads |
| **Bounded workers** | Hashing, inspection, recognition, export, reconciliation and cleanup jobs with explicit limits/retry policy | Long-lived UI/session ownership, untrusted archive parsing in the web request process |
| **Metadata-provider adapters** | Provider request/response mapping, rate-limit/cache/terms controls, provenance snapshots | Canonical identity; all matches remain evidence with confidence and user correction |
| **Mac client sync/cache** | Local command outbox, selected verified blob cache, cache capacity/pin/eviction state, local readiness state | Server canonical metadata/revision authority |
| **Mac emulator adapter** | Capability declaration, local materialization, launch/observe, controller integration, BIOS validation/materialization, safe persistent-save collection | Server process control, server data-model fields for paths/core options |

### One-Way Dependency Rules

```
Delivery (HTTP API, LiveView) ──► Application services ──► Domain
                                      │                     │
                                      └────► Ports ◄─────────┘
                                              ▲
               Postgres / object store / providers / worker runtimes adapters
```

1. Domain code has no infrastructure or delivery dependency.
2. Application services depend on domain contracts and declared ports, never adapter implementations.
3. HTTP and LiveView are sibling delivery adapters. LiveView may call application services directly; it may not expose its events, HTML, assigns, or sockets as a native-device contract.
4. The Mac app depends only on published `/api/v1` schemas and documented capability/adapter contracts. It never reads server storage or database state directly.
5. Provider, emulator, storage, and export integrations enter through ports; their proprietary identifiers, paths, credentials, and licensing constraints do not leak into canonical domain identity.

## Canonical Data Model

PostgreSQL is the authority for logical state. The object store is the authority for immutable byte payloads only after the corresponding hash verification and visibility transaction succeed.

| Record | Canonical responsibility | Key invariants |
|---|---|---|
| `blob` | Exact immutable byte object | SHA-256 + byte size are identity; filename, CRC, archive hash, and storage ETag are not. Scope dedupe to tenant/user boundary until household policy is explicit. |
| `asset_set`, `asset_member` | Playable logical release, including ordered multi-file/disc assets | Members reference exact blobs and generated export paths; a game is never assumed to be one file. |
| `source_file`, `import_receipt` | Provenance and explainable import outcome | Managed copy only; preserve source name/relative location as metadata; never mutate/move source; retain duplicate/quarantine/unknown reasons. |
| `library_item` | Curated user-facing ownership/view over assets | Favorites, collections, recency and user corrections are logical metadata, not blob properties. |
| `recognition`, `metadata_assertion` | Candidate/match evidence from DAT/metadata providers | Provider, version/timestamp, confidence, and correction provenance remain visible; an external match never changes original bytes. |
| `device`, `installation`, `capability_snapshot` | Paired client identity and locally supported matrix | Server stores declarations and compatibility results, not local absolute paths or controller/emulator implementation details. |
| `transfer`, `job`, `change_event`, `command_receipt` | Restart-safe operation identity and reconciliation | Idempotency/command receipt survives client/tab/socket loss; payloads are bounded and progress is reconstructible. |
| `save_slot`, `save_revision` | Mutable persistent-save history | Every payload is immutable; new revision declares `base_revision`, device/writer and adapter compatibility fingerprint; concurrent heads are visible conflicts. |
| `backup_run`, `export_manifest` | Recovery evidence | A repository copy is not called a backup without an independent verified destination/restore result. |

## API and Protocol Seams

### Confirmed contract direction

`/api/v1` is the cross-platform product boundary. It must support capability negotiation, idempotent mutations, resumable state, and recovery without a persistent WebSocket.

| Seam | Contract | V1 requirement |
|---|---|---|
| Pairing/auth | Device-pair flow produces revocable scoped device credentials; authenticated approval has audit record | Private by default; no unauthenticated LAN discovery; do not bake browser cookies into native auth |
| Capability hello | Client protocol major/minor, app version and declared adapter/cache/transfer/save capabilities; server returns supported features/limits | Major incompatibility yields actionable failure; additions must be ignorable |
| Commands | Explicit resources/commands with `Idempotency-Key` and durable receipt | Retry after disconnect returns original outcome, never duplicate import/save mutation |
| Catalogue sync | Snapshot plus cursor change journal/reset semantics | Browse metadata independently from selected blob transfer; do not use full listing as sync protocol |
| Immutable content | Versioned manifest, immutable blob id/hash, byte size, `Range`, `ETag`/conditional reads and SHA-256 verification | Client marks cached only after all manifest members verify; server authorization applies to manifest and every blob |
| Imports/transfers/jobs | Durable session/job IDs, status, cancellation/retry and reconciliation endpoints | UI/live push accelerates status but `GET` reconstructs truth |
| Save sync | Immutable upload/download revisions, `base_revision`, head/conflict response, restore-as-new-revision | No silent timestamp last-write-wins; only adapter-proven persistent-save types v1 |
| Errors/observability | Stable machine code + human action; correlation/receipt ID | Never make an ephemeral socket event the sole acknowledgement |

### Major data flows

**Managed import (confirmed product contract; exact upload mechanism recommended):**

```
Mac select → preview managed-copy outcome → idempotent import command
  → durable import/job record → bounded stream/hash + policy inspection
  → stage blob through storage port → SHA-256 verify → transactional metadata/receipt
  → commit visibility + change event → recognition asynchronously → UI/client refresh
```

The source remains untouched. Unknown and patched files can be retained with recoverable unrecognized outcomes; malformed or unsafe inputs are quarantined with diagnostics. Archive inspection is optional and isolated, bounded by CPU, memory, recursion, member-count and expanded-size limits.

**Selected download and offline launch:**

```
catalogue/manifest query → client capacity decision → Range download each immutable member
  → SHA-256 verification → local cache keyed by (hash, byte_size) → readiness preflight
  → local adapter materializes content/BIOS/save → launches emulator without server dependency
```

Only verified bytes may be reported ready offline. A pinned cache may be evicted only under explicit policy; the catalogue stays lightweight and independent of a full-library mirror.

**Persistent-save reconciliation:**

```
adapter safe-flush signal → client snapshots declared save artifact → local outbox
  → upload revision(base_revision, compatibility fingerprint, hash)
  → server validates/creates immutable revision
  → advance one head OR return multiple conflict heads → client presents explicit resolution
  → restore downloads a chosen revision and writes a new revision when resaved
```

Crashes/close events are uncertain: use adapter-proven safe flush or stable-file debounce, not continuous blind uploads. Save states remain local experimental artifacts unless a later, exact core/build/options/content matrix proves otherwise.

**Durable job recovery:** create intent and receipt before work; workers claim bounded work with retry/backoff/cancellation checkpoints; progress is persisted; restart reconciliation marks or resumes safely. Phoenix supervision restarts processes, but database state and idempotent effects determine correctness.

## Deployment Topology

### V1 self-hosted path — confirmed direction

```
internet / trusted LAN
          │ TLS terminated by documented reverse proxy or deployment edge
          ▼
┌────────────────── Docker Compose ───────────────────┐
│ Phoenix release                                       │
│  HTTP API + LiveView + bounded job supervisors        │
│       │                         │                     │
│ PostgreSQL persistent volume   local blob volume      │
│ durable metadata/jobs          content-addressed data │
└──────────────────────────────────────────────────────┘
          │
 optional later: server-side S3-compatible storage adapter
 (MinIO/S3/R2), credentials stay server-side; no R2-specific client protocol
```

Deploy one documented container path with persistent volumes, health checks, migration/upgrade preflight, backup configuration, and verified restore guidance. Blob directories are not web roots. Restrict network exposure; enforce TLS/auth/CSRF for web sessions, rate/byte/concurrency limits, private object authorization, minimal sensitive telemetry, and auditability.

### Scaling without premature distribution

| Stage | Architecture adjustment |
|---|---|
| Initial household / proof | One Phoenix release, Postgres, local disk object store; bounded in-process job orchestration with durable records. |
| Larger library / many devices | Tune indexes/read models, stream blobs, isolate high-cost inspection into constrained worker execution, and add S3-compatible storage after recovery semantics are proven. |
| Hosted/multi-tenant (not v1) | Separate legal/security/operations milestone: tenant isolation, key management, abuse/takedown/privacy policy, quotas, backup/SRE and provider terms. It is not enabled merely by S3 configuration. |

## Recommended Project Structure

```
playstead-server/
  lib/playstead/
    domain/                 # pure entities, invariants, domain events/ports
    application/            # commands, queries, transactions, orchestration
    infrastructure/
      persistence/          # Ecto/Postgres implementations
      storage/              # local first; S3-compatible implementation later
      metadata/             # replaceable providers, cache/policy/provenance
      workers/              # bounded job implementations and reconciliation
    protocol/v1/            # versioned schemas, serializers, API contract tests
  lib/playstead_web/
    controllers/api/v1/     # HTTP translation only
    live/                   # web console only
playstead-mac/
  App/                      # SwiftUI views + AppKit bridges
  Protocol/                 # generated/handwritten v1 client; no server internals
  Sync/                     # outbox, change cursor, cache/index
  Adapters/                 # emulator/BIOS/controller/save integration
  Cache/                    # verified content lifecycle and capacity policy
```

This is a module boundary, not an instruction to split repositories now. Extract shared schema/SDK only after the Mac proof and a second independent consumer establish a stable public contract.

## Build Order and Dependency Gates

1. **Trustworthy server kernel.** Create tenant/user boundary, Postgres schema, object-store port/local adapter, blob/asset/import/save invariants, audit model, migrations and backup/restore baseline.
2. **Protocol foundation.** Implement `/api/v1` capability/auth/pairing, error/idempotency/receipt model, library/manifest reads, durable jobs/change journal and authorized Range blob delivery. Contract-test it independently of LiveView and Swift.
3. **Safe import/export vertical slice.** Managed-copy preview, bounded streamed hash/store, receipt/quarantine paths, minimal recognition provenance, deterministic ordinary-folder export and verification.
4. **Operational web console.** LiveView setup/admin/import/library/pairing/job surfaces using the same services/read models; every view recovers after reconnect/reload.
5. **Mac empirical vertical slice.** SwiftUI/AppKit pairing, metadata browse, selected verified cache, a single adapter, preflight/launch, and one proven persistent save artifact revision/recovery. The adapter spike gates expansion.
6. **Reliability and protocol pressure tests.** Interruption/restart/conflict/upgrade/rollback/restore tests; second adapter or client before publishing a reusable SDK and broad platform claims.
7. **Deferred capability phases.** S3 direct-transfer/multipart only after transfer spike; browser play only after separate WASM/core/browser/storage/isolation/license matrix; third-party metadata/export integrations remain adapter phases.

## Anti-Patterns to Reject

| Anti-pattern | Why it fails | Required alternative |
|---|---|---|
| LiveView as device protocol | Native/offline clients inherit socket lifecycle as semantics and cannot converge after disconnect | `/api/v1` commands, receipts, cursor changes and immutable resources |
| UI-owned long work | Closing a tab/process loses operation truth or causes duplicate work | Durable job/transfer records and bounded worker execution |
| Paths/cores in server domain | Makes a portable protocol permanently Mac/emulator-specific | Client adapter capabilities and local configuration fingerprints |
| Filename/CRC/ETag identity | Creates false dedupe and corrupts provenance guarantees | Full-stream SHA-256 plus size for exact byte identity |
| Last-write-wins saves | Silently loses user progress | Immutable revisions, `base_revision`, visible competing heads/resolution |
| Full-library cache/mirror by default | Large libraries waste capacity and make offline semantics unclear | Catalogue sync plus selected manifest-driven verified cache |
| Blob store described as backup | One failure domain remains one failure domain | Independent backup destinations with verified restore status |
| General browser Play button | Browser support is core/browser/system/save/license matrix-specific | Later explicit readiness matrix; hide unsupported launch with reasons |
| In-process unrestricted parsing | Archives and parsers are untrusted resource/escape risks | Narrow formats, generated storage keys, constrained isolated inspection |

## Evidence and Confidence

This architecture is derived from project decisions and discovery sources, rather than a new external implementation claim. High-confidence facts are direct project decisions and primary documentation; architecture synthesis is medium confidence until spikes validate the chosen adapter, transfer mechanism and platform support.

| Provenance | Confidence | Used for |
|---|---|---|
| [`PROJECT.md`](../PROJECT.md) | HIGH | Confirmed product constraints and decisions: Phoenix/API-first, LiveView scope, Postgres/local-to-S3 direction, native Mac first, browser later, data custody/offline guarantees. |
| [`SUMMARY.md`](../discovery/SUMMARY.md) | MEDIUM-HIGH | First proof, domain records, repository strategy, build/integrate/defer boundary and spike gates. |
| [`WEB-AND-CLIENT-ARCHITECTURE.md`](../discovery/WEB-AND-CLIENT-ARCHITECTURE.md) | HIGH for documented Phoenix/Apple/API facts; MEDIUM for recommendations | One-way API/LiveView/client boundary, durable protocol mechanisms, Mac and browser constraints, delivery order. |
| [`TECHNICAL-RISKS.md`](../discovery/TECHNICAL-RISKS.md) | HIGH for cited protocol/security facts; MEDIUM for selected mechanics | Content addressing, Range/resumable-transfer constraints, save/BIOS isolation, object-store and worker safety. |
| [`LANDSCAPE.md`](../discovery/LANDSCAPE.md) | MEDIUM-HIGH | Ecosystem precedents, server-owned records, adapter boundaries and local-first deployment recommendation. |

### Phase-specific research flags

- **Required before Mac expansion:** first adapter’s save flush, paths, sandbox/notarization and compatibility matrix, using legal homebrew content.
- **Required before large/remote upload:** server stream vs tus vs S3 multipart interruption/cancellation/checksum/cleanup spike; never invent partial-PUT semantics.
- **Required before enabling archive inspection:** adversarial traversal/symlink/recursive/decompression-bomb corpus in an isolated resource-limited worker.
- **Required before metadata/artwork shipment or hosting:** provider terms, caching/attribution/redistribution and hosted legal/privacy/abuse review.
- **Required before browser play:** one core/system/browser matrix for WASM performance, isolation headers, cache eviction, controller lifecycle, save conflicts and licenses.

---

*Canonical architecture for Playstead. This document preserves current decisions while naming empirical gates instead of promising unproven portability.*
