# Feature Landscape

**Project:** Playstead
**Domain:** self-hosted personal game-library custody, offline play, and cross-device persistent-save continuity  
**Researched:** 2026-08-26  
**Confidence:** MEDIUM-HIGH — product direction is strongly corroborated by the discovery corpus; system/core and adapter compatibility remain empirical.

## Product Boundary

Playstead is not another ROM catalogue, emulator, operating system, or generic file-sync tool. Its v1 promise is a **canonical, private server repository** for user-supplied content; a **selective, verified client cache** for games chosen to play locally; and an **independent, verified backup** for recovery after repository loss. These are three different user promises and must never share a vague “safe/synced” label.

The product proves one polished Mac-to-server path: managed-copy import, exact-byte custody, curated browsing, selected offline download, adapter preflight and launch, persistent-save revision sync, clean-machine restore, and deterministic export. Phoenix LiveView is the first-party setup/admin console; native, browser, and future device clients use a durable versioned HTTPS API and capability negotiation. Achievements and browser play are optional later adapters, never prerequisites for library use or local launch.

## Feature Landscape

### Table Stakes — v1 Product Contract

| Feature | User value | Complexity | Dependencies | Evidence | v1 recommendation | Failure / UX considerations |
|---|---|---:|---|---|---|---|
| **Managed-copy import with receipt** | A user knows the original source remains untouched and precisely what was stored. | High | Content hash, object store, import job, provenance ledger | Discovery Summary; User Feedback S01, S03–S08; Experience Ethos “Import” | **Build first.** One explicit action: “Copy into my library”; stream and hash the original bytes without normalization. | Preview source/target and disk impact; result must say new copy, exact duplicate, variant, needs attention, or failed safely. No moves, rewrites, or silent cleanup. |
| **Exact-byte identity, manifests, and dedupe** | Bytes remain verifiable/exportable while multi-file releases do not collapse into misleading single files. | High | SHA-256 blobs, asset sets/members, source provenance | Discovery Summary “Core Domain Shape”; User Feedback S02–S06 | **Build.** Make SHA-256 of original bytes canonical; retain aliases, variants, and source records. | Paths, filenames, CRCs, archive hashes, and metadata are evidence, not identity. Never equate duplicate bytes with interchangeable releases. |
| **Single and massive import** | One ROM feels immediate; a large collection is safe, observable, resumable work. | High | Durable jobs, staging/fingerprinting, idempotent reconciliation | Project Active requirements; User Feedback S06–S08; Experience Ethos “Import” | **Build using one pipeline.** Immediate UI for a file, staged background job for folders/collections. | Discovery → cheap fingerprint → strong hash as needed → identify → enrich. Pause/resume/retry/cancel must have truthful semantics; unchanged content must not churn clients. |
| **Exception and recognition workflow** | Patched, unknown, ambiguous, malformed, incomplete, and multi-file inputs receive a recoverable outcome instead of disappearing. | High | Asset manifests, recognition providers, review queue | User Feedback S01, S03, S07, S13; Discovery Summary | **Build narrow but humane.** A “Needs attention” inbox with reason, confidence, source, retry, choose-system, attach-companion, retain-as-custom, or exclude. | Do not call unfamiliar content bad or disposable. Show “2 of 3 files found”; preserve user corrections and prior metadata edits. |
| **Curated library and information hierarchy** | A large repository remains enjoyable: users resume, choose, and find games without browsing a warehouse dump. | Medium | Library read model, metadata, local/server availability states | Project requirements; Experience Ethos “A library is not an inventory dump”; Landscape | **Build.** Lead with Continue, Favorites, Collections, Queue, Recent, selected Systems, fast search/filters. | Hide empty/unconfigured systems by default; show counts/readiness when useful. Controller, keyboard, pointer, and assistive navigation must be equivalent. |
| **Pairing, capability-aware API, and LiveView console** | A new device can securely see the catalogue and a self-hoster can administer the product without LiveView becoming a client dependency. | High | Auth/pairing, `/api/v1`, capability handshake, durable jobs/change cursor | Project decisions; Web/Client Architecture S1, S2, S13 | **Build.** API-first Phoenix plus LiveView setup/admin/import/pairing/job views; client mutations are idempotent HTTP commands. | API must survive reconnects/missed notifications. Expose version incompatibility plainly; do not make a persistent socket or HTML route semantic. |
| **Selective local cache and verified transfers** | A newly paired computer is useful immediately without mirroring a large library, while selected games work offline. | High | Manifest/blob authorization, Range download, SHA-256, cache index, capacity policy | Discovery Summary; User Feedback S09; Web/Client Architecture | **Build.** Browse metadata first; download selected games/collections with resume, verification, pin and safe eviction. | Distinguish server-only, queued, partial, verified local, pinned offline, and safe-to-evict. A partial or evicted item must never look launch-ready. |
| **Offline launch through one native adapter** | A verified local game remains playable without server, Internet, metadata, achievements, or storefront availability. | High | Mac app, local cache, adapter capability model, emulator-launch spike | Project first proof; Discovery Summary; Web/Client Architecture S10–S11 | **Build one deliberate Mac/system/emulator combination.** SwiftUI/AppKit client owns paths, processes, controller integration, and local materialization. | Local preflight gates launch; adapter failures get a concrete recovery action. Do not promise every emulator, core, platform, or save-state format. |
| **Readiness and BIOS auditor** | Players understand whether assets, adapter, BIOS, controller, cache, and save are ready *before* pressing Play. | Medium-High | Adapter matrix, local cache, BIOS validation, controller diagnostics | User Feedback S13–S18; Experience Ethos “Ready to Play” | **Build.** Compact preflight/readiness panel and a BIOS auditor for locally supplied files only. | BIOS result is scoped to the selected system/core and should state missing/valid/optional/replacement/user file required. Never offer ROM/BIOS acquisition guidance. |
| **Persistent-save revisions, restore, and conflict resolution** | Progress survives devices and failures without silently overwriting a user’s latest work. | High | Device identity, adapter-declared save type/path, immutable revision graph, offline outbox | Discovery Summary; User Feedback S09–S12; Experience Ethos “Sync” | **Build for one proven persistent-save type.** Append immutable revisions with `base_revision`, restore history, offline queue, and explicit divergent-head choice. | “Queued” is not “backed up.” Retain both binary conflict sides; show device/time/last-launch context. Save states remain local/experimental unless exact compatibility is proven. |
| **Exact export plus honest independent backup/restore** | Users can leave, audit, migrate, and recover their library rather than trusting an opaque server disk. | High | Blob/manifest model, backup target, restore verifier, storage health | Project Active requirements; User Feedback S02, S05, S08; Experience Ethos | **Build.** Deterministic ordinary folders containing exact game bytes, saves, readable manifest, and hashes; verify full/incremental backup and restore. | Server storage is not itself a backup. Report what a backup includes, health, last verification, and recovery status; do not show false green safety. |
| **Controller-first accessible interaction** | Play-facing flows work from a couch/handheld context without trapping a user when a controller fails. | Medium | Native controller API, focus system, mapping/profile model | User Feedback S15–S18; Experience Ethos; Apple Game Controls HIG | **Build baseline.** Controller pairing/test, visible focus/action hints, keyboard fallback, semantic accessibility, reduced motion. | Retain device identity/player assignment where feasible; mappings differ by OS/driver and need reset/rollback and per-game overrides. |
| **Low-administration self-hosted operations** | The private server is deployable, upgradeable, observable, and recoverable without becoming a hobby. | High | Opinionated container deployment, health checks, data inventory, migration/backup tooling | Project requirements; User Feedback S05, S08, S18 | **Build one documented container path.** Persistent volumes, mount/UID-GID validation, health, diagnostics, backup/restore, migration preflight and rollback. | Treat mount/permission/capacity failures as product UX. Healthy systems stay quiet; details are on demand, not an alert stream. |

### Differentiators — Why This Product Exists

| Feature | User value | Complexity | Dependencies | Evidence | v1 recommendation | Failure / UX considerations |
|---|---|---:|---|---|---|---|
| **Custody model: repository ≠ cache ≠ backup** | Gives users a truthful mental model of availability and recoverability across devices. | Medium | Storage/accounting states, cache manager, backup verification | Experience Ethos principle 16; Discovery Summary; User Feedback S02 | **Make this a cross-cutting v1 language and UI contract.** | Never use one sync icon for metadata, game bytes, saves, and backups. Use plain terms: on server, ready on this device, queued, backed up, conflict. |
| **Explainable automation and recoverable evidence** | Automation helps without becoming mysterious: every import, match, dedupe, or job has proof and a next step. | High | Provenance ledger, receipts, recognition confidence, diagnostics | Experience Ethos principles 1, 5, 10; User Feedback S01–S08 | **Build into import and sync, not as an audit afterthought.** | Progressively disclose technical detail. Include what changed, why, confidence, source/version, safe remedy, and reversible actions. |
| **Curation before recommendation** | Personal favorites, collections, queue, recency, and system preferences reduce choice overload without data-mining or a fragile recommender. | Medium | Library model, user preferences, activity history | Project decisions; Experience Ethos principle 15 | **Build curation in v1; defer algorithmic recommendations.** | Do not make exhaustive catalogue views the default. Curation is user-directed and portable/exportable. |
| **Compatibility-aware durable play path** | Known-playable local configurations remain launchable through updates rather than breaking from incidental core/metadata changes. | High | Adapter fingerprint, content manifest, update preflight, rollback | Project requirement; Experience Ethos principle 14 | **Build a minimal known-good record for the first adapter.** | Update success is not merely “installed.” Warn before incompatibility, retain working configuration where possible, and validate rollback. |
| **Emulator-neutral server, client-side adapters** | The library protocol survives platform/emulator growth instead of embedding local paths, cores, or controllers into server domain logic. | High | Capability negotiation, adapter contract, API schema | Discovery Summary; Landscape; Web/Client Architecture | **Establish boundary in v1 and prove it with one Mac adapter.** | Do not split an SDK or support many adapters prematurely. Compatibility claims are explicit matrices, not aspirational universality. |

### Later Enrichments — Earned Only After the Core Is Proven

| Feature | User value | Complexity | Dependencies / trigger | Evidence | Recommendation | Failure / UX considerations |
|---|---|---:|---|---|---|---|
| **Second native client or emulator adapter** | Tests true protocol portability and extends play to a new context. | High | Stable v1 API, first adapter/saves/launch proven; second platform spike | Project decisions; Web/Client Architecture delivery order | **v1.x.** Add only after the Mac vertical slice is reliable; then consider Windows/Linux/Steam Deck/handheld adapters. | Do not extract shared SDKs until two consumers demonstrate a real boundary. |
| **S3-compatible object-store and direct transfer adapters** | More storage choices and potentially better large-transfer economics. | High | Verified local-disk custody/recovery, authorization model, interruption/cleanup spike | Project Context; Discovery Summary transfer spike | **Later.** Keep client protocol storage-neutral; begin with server-proxied bounded transfers. | Signed/direct URLs must remain private, short-lived, authorized, and resumable; object-store ETags are not canonical content identity. |
| **Save gallery and richer recovery views** | Makes history and conflicts recognizable rather than filename archaeology. | Medium | Revisioned saves, adapter thumbnails/metadata where available | User Feedback S11; positive patterns | **v1.x.** Add after revision correctness, not before. | Show provenance and export paths; never imply thumbnails guarantee compatibility. |
| **Advanced reference-in-place/import modes** | Supports very large existing NAS libraries without a second managed copy. | High | Stable identity/relink/health/export semantics, external drive spike | User Feedback S01–S05; Experience Ethos | **Defer.** Managed copy is the safe v1 contract. | External moves, mounts, permissions, dedupe, and backup make this fundamentally different from import; no destructive automatic migration. |
| **Optional achievements provider adapter** | Delight and progress enrichment for users who opt in. | Medium-High | Stable canonical identity, provider/license/privacy review, isolated adapter | Project Out of Scope; Experience Ethos principle 13 | **Later and optional.** | No external account requirement for core play, no canonical identity replacement, no network/achievement outage impact on browsing, launch, saves, or export. |
| **Browser play adapter** | Convenient browser companion for a narrow, tested system/core/browser matrix. | Very High | Stable API/save contracts, WebAssembly core, license/BOM, isolation, cache and controller spike | Web/Client Architecture S3–S9, S14–S15 | **Later, after a dedicated spike.** It is a separate API client, not a LiveView feature. | Per-item readiness; manifest-first Range + SHA-256 transfer; quota/eviction recovery; persistent browser data is not backup. No broad “Play in browser” button. |
| **Launcher/export bridges and appliance integrations** | Lets users use a canonical library with mature external frontends/environments. | Medium-High | Stable export manifests, adapter boundaries, per-tool compatibility review | Landscape taxonomy; Project long-term vision | **Later.** Evaluate RetroArch/ES-DE/Pegasus/Steam ROM Manager/Playnite/Batocera/RetroDECK adapters one at a time. | Export should not seize ownership of external configuration or weaken core custody semantics. |
| **Streaming, cloud execution, netplay, social/recommendation layers** | Broader convenience and discovery. | Very High | Reliable custody/play/save/operations baseline plus separate security and latency product work | Project Out of Scope; Landscape | **v2+ only.** | These must never compromise offline local play, private-content posture, or save/data correctness. |

### Anti-Features — Explicitly Do Not Build in v1

| Anti-feature | Surface appeal | Why it is harmful | Safer alternative |
|---|---|---|---|
| Public ROM/BIOS catalogue, sharing, acquisition help, or “ownership verification” | Makes onboarding/content discovery look easy. | Violates the private user-supplied-content posture and introduces major legal, abuse, and privacy risk. | Accept and validate only user-supplied local files; no acquisition or proprietary-BIOS guidance. |
| Full-library replication to every client | Feels like simple sync. | Wastes device storage/bandwidth and makes a new machine slow before it is useful. | Canonical server catalogue plus selected, verified, storage-aware local cache. |
| Calling server storage a backup | Reassuring single green status. | One disk/server failure can lose the only repository. | Independent backup/replication target with verified restore and honest coverage state. |
| Silent last-write-wins save sync | Looks effortless. | Destroys progress and hides divergent binary state. | Immutable revisions, base revision, explicit conflict copies/choice, offline queue. |
| Universal save-state or cross-core portability | Promises seamless continuation. | Save states are build/core/options/content dependent and may corrupt or mislead. | Sync only proven persistent saves; keep states local and compatibility-keyed until demonstrated. |
| General browser Play button | Makes the web console look complete. | Browser/core/BIOS/controller/performance/storage/isolation/license support is a matrix, not a binary. | Later adapter with declared supported matrix and readiness explanations. |
| Building emulator cores or a custom appliance OS | Appears to give total control. | Diverts effort into mature, fragile ecosystems and expands maintenance/security burden. | Integrate mature local emulators through client adapters; interoperate with appliances later. |
| LiveView/WebSocket as native-client protocol | Reduces initial server work. | Couples offline clients to UI connection/lifecycle and makes reconnect behavior semantic. | Versioned HTTPS API, idempotency, durable jobs/change cursor; LiveView is a first-party console. |
| Managed moves, destructive normalization, auto-patching, or silent cleanup | Promises tidier libraries. | Violates source custody/provenance and creates unrecoverable mistakes. | Exact-byte managed copies, safe exception queue, user-authorized exports/corrections. |
| Hosted multi-tenant storage in first milestone | Increases convenience and monetization potential. | Requires dedicated legal, abuse, tenant-isolation, privacy, cost, and operations design. | Finish the private self-hosted proof; evaluate hosting as a separate later program. |

## Feature Dependencies

```text
Managed-copy import + source provenance
  └─requires─> immutable SHA-256 blobs + asset manifests
                    ├─requires─> storage adapter + durable job/receipt model
                    ├─enables──> exact export and dedupe/variant display
                    ├─enables──> recognition and exception workflow
                    └─enables──> verified selective client cache

Versioned API + pairing + capability negotiation
  ├─enables──> LiveView console (as a separate delivery surface)
  ├─requires─> idempotent commands + durable change/job cursor
  └─enables──> Mac client and later browser/native adapters

Verified selective cache + adapter capability record
  └─requires─> readiness (assets, emulator, BIOS, controller, save)
                    └─enables──> offline launch

Adapter-proven persistent save path + paired device identity
  └─requires─> immutable save revisions + base-revision conflicts + offline outbox
                    └─enables──> clean-machine restore and save gallery

Canonical repository
  └─requires─> independent verified backup/restore

Curated library views
  └─enhance──> selective cache actions and new-computer setup

Browser play / achievements / streaming
  └─require──> stable API, isolated adapter contracts, and proven core play path
```

### Dependency Notes

- **Import requires immutable blobs and asset manifests:** exactly preserving a disc set, variant, or companion files cannot be reconstructed from a title record or path alone.
- **Offline launch requires a verified local manifest and local preflight:** a server listing, queued download, or metadata match is insufficient proof that a game can start.
- **Save sync requires an adapter-proven persistent-save mapping:** title and ROM identity alone cannot safely map emulator save files; save states do not enter the v1 guarantee.
- **Backup is downstream of repository identity but independent of cache:** a reconstructable cache is not recovery protection, and a backup must be verified through restore drills.
- **Browser play conflicts with a generic LiveView play surface:** it has its own browser cache, isolation headers, controller, persistence, and licensing constraints; it is a later client adapter.

## MVP Recommendation

### Launch With (v1)

- [ ] **Trustworthy repository foundation** — managed-copy import, exact-byte SHA-256 blobs, manifests, provenance, duplicates/variants, exception inbox, and immediate/large-job import.
- [ ] **API-first private server and web console** — pairing, capability negotiation, idempotent mutations, durable job/change status, LiveView setup/admin/import/library views, and one opinionated container deployment.
- [ ] **Curated personal library** — favorites, collections, Continue/Recent/Queue, system preferences, searchable library, and plainly differentiated availability states.
- [ ] **Mac vertical play slice** — browse server catalogue, selected resumable verified download/cache, one native emulator adapter, controller-aware accessible UI, readiness panel, and offline launch.
- [ ] **Persistent-save continuity** — one supported persistent save type with immutable revision history, restore, explicit conflicts, offline queue, and clean-client recovery.
- [ ] **Exit and operations proof** — deterministic exact export plus independent backup/restore validation, storage health, safe upgrade/migration preflight, and actionable diagnostics.

### Add After Validation (v1.x)

- [ ] **Second client/adapter** — pressure-test capability/API boundaries before publishing shared packages or broadening platform promises.
- [ ] **Save gallery, richer metadata providers, and refined curation** — only after core custody and save correctness are dependable.
- [ ] **S3-compatible storage/direct-transfer adapter** — when measured collection size/interruption data justifies the extra authorization and cleanup complexity.
- [ ] **Reference-in-place and external-library modes** — only after relink, mount health, backup, and export semantics are shown equally trustworthy.

### Future Consideration (v2+)

- [ ] **Browser play** — a separately licensed/tested adapter for one system/core/browser matrix, following an explicit feasibility spike.
- [ ] **Achievements and third-party integrations** — opt-in adapters that remain outside the play/save critical path.
- [ ] **Streaming, netplay, recommendations/social, hosted service, appliance distribution** — separate product programs after the self-hosted data-safety and operational model is proven.

## Prioritization Matrix

| Feature | User value | Cost | Priority | Why now / gate |
|---|---:|---:|---|---|
| Custody-preserving import, identity, manifest, receipts | High | High | P1 | The trust foundation for every other feature. |
| Exception workflow and recognition provenance | High | High | P1 | Real libraries are messy; hidden failures destroy confidence. |
| Pairing, versioned API, durable jobs/change cursor | High | High | P1 | Required for LiveView and native clients without connection coupling. |
| Curated library hierarchy | High | Medium | P1 | Makes the canonical repository usable rather than archival. |
| Selective verified cache + offline launch | High | High | P1 | Delivers the new-computer/local-play promise. |
| Readiness/BIOS/controller UX | High | Medium-High | P1 | Turns predictable emulator failures into recoverable setup. |
| Persistent-save revisions/conflicts | High | High | P1 | The continuity promise; do not substitute last-write-wins. |
| Export, independent backup/restore, operations | High | High | P1 | Ensures no lock-in and makes self-hosting safe. |
| Second adapter/client | Medium-High | High | P2 | Validates the protocol after the first proof. |
| S3/direct transfer, save gallery, reference mode | Medium | Medium-High | P2 | Add when core behavior and measured needs justify them. |
| Browser play and achievements | Medium | High | P3 | Optional adapters with significant compatibility/licensing constraints. |
| Streaming/netplay/hosted service | Low for initial proof | Very High | P3 | Separate products, not extensions of v1. |

## Sources

Primary project evidence:

- [Project definition](../PROJECT.md)
- [Discovery synthesis](../discovery/SUMMARY.md)
- [User feedback and source ledger](../discovery/USER-FEEDBACK.md)
- [Experience ethos](../discovery/EXPERIENCE-ETHOS.md)
- [Open-source landscape](../discovery/LANDSCAPE.md)
- [Web and client architecture](../discovery/WEB-AND-CLIENT-ARCHITECTURE.md)

Selected direct sources already verified in those ledgers:

- [OpenEmu importing guide](https://github.com/OpenEmu/OpenEmu/wiki/User-guide%3A-Importing) — managed library, duplicate and disc/ambiguous-file behavior (HIGH).
- [webRcade cloud storage documentation](https://docs.webrcade.com/storage/) — per-device/browser state linking and optional cloud behavior (HIGH).
- [Apple Game Controller documentation](https://developer.apple.com/documentation/gamecontroller) — native controller integration boundary (HIGH).
- [MDN Gamepad API](https://developer.mozilla.org/en-US/docs/Web/API/Gamepad_API) and [Storage API](https://developer.mozilla.org/en-US/docs/Web/API/Storage_API) — browser adapter constraints (MEDIUM).
- [Phoenix LiveView documentation](https://phoenix-live-view.hexdocs.pm/Phoenix.LiveView.html) — web-console lifecycle; not a durable native-client protocol (HIGH).

---
*Feature research for Playstead — repository custody and game continuity, not ROM/BIOS acquisition.*
