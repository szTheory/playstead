# Requirements: Playstead

**Defined:** 2026-08-26  
**Core Value:** A locally available game and its progress remain effortless to play, safe, understandable, synchronized, and fully under the user's control.

## v1 Requirements

Requirements for the first complete Mac-to-server custody and continuity release. Each requirement maps to exactly one roadmap phase.

### Private Server and Operations

- [x] **OPER-01**: A self-hoster can deploy the private server through one documented Docker Compose path with explicitly configured persistent database and blob volumes.
- [x] **OPER-02**: A self-hoster can complete initial setup in a Phoenix LiveView console without editing application data or calling the device API by hand.
- [ ] **OPER-03**: A self-hoster can see separate, actionable health for the database, blob store, durable work queues, migrations, storage capacity, and backup freshness.
- [ ] **OPER-04**: A self-hoster can upgrade through a compatibility and migration preflight, verify the known-playable path afterward, and follow a documented rollback when verification fails.

### Pairing and Durable Protocol

- [x] **PROT-01**: An authenticated owner can approve a Mac device-pairing request and the Mac client stores the resulting scoped credential in Keychain.
- [x] **PROT-02**: An authenticated owner can review paired devices and revoke one without invalidating other devices.
- [x] **PROT-03**: A client can declare protocol, application, cache, transfer, emulator-adapter, and save capabilities and receive an actionable incompatibility response when the server cannot support them.
- [x] **PROT-04**: A disconnected client can safely retry a mutation and receive the original durable receipt instead of creating a duplicate effect.
- [x] **PROT-05**: A client that misses notifications can reconstruct catalogue, job, transfer, and save state through a versioned HTTPS snapshot-and-cursor API without requiring a persistent WebSocket.

### Import, Identity, and Provenance

- [x] **IMPT-01**: A user can select one supported file and see before confirmation that Playstead will copy it into managed storage, leave the source untouched, and consume a stated amount of storage.
- [x] **IMPT-02**: After import, a user can verify the SHA-256 and byte size of the exact original bytes and inspect their source provenance.
- [x] **IMPT-03**: A user receives a durable import receipt that distinguishes a new asset, exact duplicate, alias or variant, incomplete set, unrecognized or patched content, quarantined input, and safely failed input.
- [x] **IMPT-04**: A user can import a supported multi-file game as an ordered asset manifest whose required members and readiness remain explicit.
- [x] **IMPT-05**: A user can stage a large collection import, observe bounded progress, pause or resume it, retry interrupted work, and reconcile it without duplicating unchanged content.
- [ ] **IMPT-06**: A user can resolve an item in a Needs Attention inbox by reviewing evidence and then correcting its system or metadata, attaching a missing companion, retaining it as custom content, excluding it, or retrying safe processing.

### Curated Library

- [ ] **LIBR-01**: A user can browse the complete server catalogue on a newly paired Mac before downloading game bytes.
- [ ] **LIBR-02**: A user can quickly find games through search, filters, systems, and availability or readiness state.
- [ ] **LIBR-03**: A user can curate focused views using favorites, collections, Continue, Recent, and a play queue without altering canonical game bytes.
- [ ] **LIBR-04**: Empty or unconfigured systems and irrelevant advanced settings stay hidden by default, while counts, readiness, and contextual setup actions appear when useful.
- [ ] **LIBR-05**: A user can browse and curate the same canonical library, review imports, approve pairing, and inspect durable job status through the responsive LiveView console without installing a native client.

### Selective Cache and Offline Play

- [ ] **CACH-01**: A user can choose a game or collection for local download and resume an interrupted transfer without restarting verified ranges.
- [ ] **CACH-02**: A user can distinguish server-only, queued, partial, verified-local, pinned-offline, and safe-to-evict content.
- [ ] **CACH-03**: A user can set a local capacity policy, pin selected content, and reclaim only reconstructable unpinned content without affecting the server repository or backup.
- [ ] **CACH-04**: A user can launch a manifest only after every required member verifies locally, and can launch that verified game while the server, internet, metadata, achievements, and other optional services are unavailable.

### Mac Readiness and Emulator Adapter

- [ ] **PLAY-01**: A user can install or select one deliberately supported Mac emulator adapter and see its exact supported system, emulator version, content, BIOS, and persistent-save capabilities.
- [ ] **PLAY-02**: Before launch, a user receives a clear readiness result for game assets, local cache, emulator, BIOS, controller, and persistent-save path, with a concrete remedy for every blocking result.
- [ ] **PLAY-03**: A user can drag in a locally supplied BIOS file for validation and managed local use, while the product offers no proprietary BIOS acquisition or distribution path and recognizes an open replacement when the selected adapter supports one.
- [ ] **PLAY-04**: A user can connect, test, assign, remap, reset, and recover a supported controller while retaining keyboard, pointer, and assistive-technology fallbacks.
- [ ] **PLAY-05**: A user can launch one legally testable game through the supported adapter from a signed/notarized Mac build, exit safely, and relaunch it after an application or server restart.

### Persistent Save Continuity

- [ ] **SAVE-01**: After a proven safe flush, the Mac client can capture the adapter-declared persistent-save artifact and queue it locally when the server is unavailable.
- [ ] **SAVE-02**: A user can see whether a save revision is local-only, queued, uploaded, current, restored, or in conflict without a generic “synced” label hiding the distinction.
- [ ] **SAVE-03**: A user can restore a compatible checksummed persistent-save revision and continue the game on a clean paired Mac installation.
- [ ] **SAVE-04**: When two devices create revisions from the same base, the system retains both and lets the user inspect device/time/play context, choose or export either side, and resolve the conflict without silent last-write-wins.

### Portability and Recovery

- [ ] **PORT-01**: A user can export exact original game bytes, persistent-save revisions, and a readable manifest with hashes into deterministic ordinary folders.
- [x] **PORT-02**: A user can verify an export and reimport it without byte changes, lost asset relationships, or duplicate logical records.
- [ ] **PORT-03**: A self-hoster can create full and incremental backups to an independent user-controlled destination and see exactly what each backup covers and when it was last verified.
- [ ] **PORT-04**: A self-hoster can restore the server into a clean environment and verify database records, exact blobs, manifests, saves, and the known-playable Mac path.

### Product Quality

- [ ] **QUAL-01**: Player-facing Mac and web flows support controller, keyboard, pointer, screen-reader semantics, visible focus, and reduced motion without stranding a user in setup, browse, readiness, or recovery.
- [ ] **QUAL-02**: A maintainer can verify releases through automated formatting, static analysis, unit/property/contract/integration tests, dependency and license review, container scanning/SBOM, production-release smoke tests, and adversarial fixtures for every enabled parser.
- [ ] **QUAL-03**: A self-hoster can obtain privacy-safe correlation IDs and an on-demand diagnostic bundle for failed commands, jobs, transfers, storage, pairing, launch handoff, and save reconciliation without exposing ROM names, paths, hashes, save bytes, or credentials by default.

## v2 Requirements

Deferred capabilities are recorded here but are not part of the initial roadmap.

### Platform and Storage Expansion

- **CLNT-01**: A user can pair and use a second independent native client or emulator adapter that proves the published protocol has no Mac-only server assumptions.
- **STOR-01**: A self-hoster can use a qualified S3-compatible object-store adapter without changing the client protocol or weakening export, authorization, integrity, backup, or restore semantics.
- **TRAN-01**: A user can resume multi-gigabyte remote uploads through a standardized, spike-selected transfer mechanism with checksum, cancellation, authorization-revocation, and orphan-cleanup guarantees.
- **IMPT-07**: A user can opt into reference-in-place or external-library mode with explicit mount health, relink, backup, export, and failure semantics equivalent in clarity to managed copy.

### Optional Experience Expansion

- **WEBP-01**: A user can play a qualified game in a supported desktop browser through one explicitly tested core, system, browser, controller, cache, save, isolation, and license matrix.
- **ACHV-01**: A user can opt into an achievements provider without making its account or availability a prerequisite for browse, launch, saves, or export.
- **META-01**: A user can install or select additional metadata, DAT, and artwork providers whose source, version, confidence, attribution, caching, and redistribution terms remain visible.
- **CURT-01**: A user can receive restrained, explainable recommendations based on portable personal-library signals after manual curation workflows are proven.
- **SAVE-05**: A user can opt into save-state transfer only for an exact content, emulator/core build, platform, options, and state-format compatibility fingerprint that has passed restore tests.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Public ROM or proprietary-BIOS catalogue, download, search, sharing, or acquisition assistance | Conflicts with the private user-supplied-content posture and creates material legal, abuse, and product risk. |
| “Ownership verification” based on possession, account data, filename, or hash | The project cannot reliably prove legal ownership and must not imply that it can. |
| Paid hosted or multi-tenant storage in the initial product | Requires separate counsel, privacy, abuse/takedown, tenant isolation, key management, cost, incident-response, and SRE design. |
| Building emulator cores or a new emulation ABI | Mature emulators should be integrated through adapters; core development is not the product wedge. |
| Custom appliance operating system | Owning an OS expands hardware, update, driver, and security maintenance beyond the first proof. |
| Universal platform, emulator, controller, game-format, or save-state compatibility claims | Compatibility is an empirical matrix and v1 deliberately proves one narrow adapter path. |
| Destructive managed moves, silent normalization, auto-patching, or cleanup of source files | These violate exact-byte custody, reversibility, provenance, and the explicit managed-copy contract. |
| Full-library replication to every client | Large collections should be browsable before transfer and selectively cached according to local capacity. |
| Streaming, cloud execution, netplay, social sharing, and public profiles | These are separate products that add latency, security, moderation, privacy, and operational risk without proving custody or continuity. |
| Kubernetes, Redis, Kafka, or independently deployed web/API services in v1 | They add operational and coordination complexity before the modular Phoenix/PostgreSQL architecture demonstrates a measured need. |
| Public protocol SDK or speculative family of repositories before a second consumer | Package and repository boundaries should be extracted from proven contracts rather than designed around imagined reuse. |

## Traceability

Which phases cover which requirements. This table is populated by roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| OPER-01 | Phase 1 | Complete |
| OPER-02 | Phase 1 | Complete |
| OPER-03 | Phase 5 | Pending |
| OPER-04 | Phase 5 | Pending |
| PROT-01 | Phase 1 | Complete |
| PROT-02 | Phase 1 | Complete |
| PROT-03 | Phase 1 | Complete |
| PROT-04 | Phase 1 | Complete |
| PROT-05 | Phase 1 | Complete |
| IMPT-01 | Phase 2 | Complete |
| IMPT-02 | Phase 2 | Complete |
| IMPT-03 | Phase 2 | Complete |
| IMPT-04 | Phase 2 | Complete |
| IMPT-05 | Phase 2 | Complete |
| IMPT-06 | Phase 2 | Pending |
| LIBR-01 | Phase 3 | Pending |
| LIBR-02 | Phase 3 | Pending |
| LIBR-03 | Phase 3 | Pending |
| LIBR-04 | Phase 3 | Pending |
| LIBR-05 | Phase 3 | Pending |
| CACH-01 | Phase 3 | Pending |
| CACH-02 | Phase 3 | Pending |
| CACH-03 | Phase 3 | Pending |
| CACH-04 | Phase 3 | Pending |
| PLAY-01 | Phase 3 | Pending |
| PLAY-02 | Phase 3 | Pending |
| PLAY-03 | Phase 3 | Pending |
| PLAY-04 | Phase 3 | Pending |
| PLAY-05 | Phase 3 | Pending |
| SAVE-01 | Phase 4 | Pending |
| SAVE-02 | Phase 4 | Pending |
| SAVE-03 | Phase 4 | Pending |
| SAVE-04 | Phase 4 | Pending |
| PORT-01 | Phase 4 | Pending |
| PORT-02 | Phase 2 | Complete |
| PORT-03 | Phase 5 | Pending |
| PORT-04 | Phase 5 | Pending |
| QUAL-01 | Phase 3 | Pending |
| QUAL-02 | Phase 5 | Pending |
| QUAL-03 | Phase 5 | Pending |

**Coverage:**

- v1 requirements: 40 total
- Mapped to phases: 40
- Unmapped: 0
- Coverage summary: 40/40/0

---
*Requirements defined: 2026-08-26*  
*Last updated: 2026-08-26 after canonical project research*
