# Emu Server

## What This Is

Emu Server is the working name for an open-source, self-hostable personal game-library and continuity system. It gives people a polished way to import user-supplied ROMs, understand exactly what happened to their files, browse and play through integrated clients, keep persistent saves safe across devices, and export everything without lock-in.

The first proof is one excellent Mac-to-server experience. The long-term vision is a platform-neutral protocol and family of clients for Mac, Windows, Linux, Steam Deck, PSP/Vita-class homebrew devices, arcade and living-room systems, and the web where technically appropriate.

## Core Value

A locally available game and its progress remain effortless to play, safe, understandable, synchronized, and fully under the user's control.

## Business Context

- **Customer**: Initially the project owner and technically capable self-hosters; later households and less-technical users through an increasingly turnkey path.
- **Revenue model**: Open-source self-hosted core; a paid hosted service is a possible future business only after legal, abuse, privacy, security, and operational review.
- **Success metric**: A clean Mac client can restore and reliably play a previously imported game with its current persistent save, while the user can still export and verify every underlying byte.
- **Strategy notes**: Reliability, offline continuity, portability, and integrated experience outrank feature breadth. Hosted storage and public ecosystem expansion are separate decisions, not implicit extensions of v1.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] A user can deploy a private server through one opinionated, documented container path with persistent data, health, backup, restore, and upgrade guidance.
- [ ] A Mac client can securely pair with the server and declare its protocol and emulator capabilities.
- [ ] The Phoenix application exposes a polished LiveView setup, administration, import, library, pairing, and job-status console without making LiveView the native-client protocol.
- [ ] Native and future constrained clients use a durable, versioned HTTPS API with capability negotiation, idempotent mutations, resumable state, and no requirement for a persistent WebSocket.
- [ ] A user can drop a supported ROM into the Mac client and see, before confirmation, that the product will copy it into managed storage while leaving the source untouched.
- [ ] Import streams, hashes, stores, and records provenance for the exact original bytes without destructive normalization.
- [ ] Exact duplicates, aliases, variants, unknown files, patched files, malformed files, and incomplete multi-file sets receive explicit, recoverable outcomes.
- [ ] The library identifies supported content through replaceable metadata/hash providers while retaining source, version, confidence, and user correction.
- [ ] The client presents a fast, polished, accessible, controller-friendly library rather than a generic CRUD interface.
- [ ] The client can download, verify, cache, pin, and launch one deliberately supported system/emulator combination through an adapter.
- [ ] A newly paired computer can browse the complete server library without downloading it, then fetch only selected games or collections on demand.
- [ ] The client distinguishes server-only, queued, partially downloaded, verified locally, pinned offline, and safe-to-evict content with storage-aware controls.
- [ ] A user can shape a focused personal library through favorites, collections, recent play, queue, filters, and system preferences instead of being confronted by an undifferentiated archive.
- [ ] Web and native navigation hide empty or unconfigured systems by default, expose counts and readiness when useful, and reveal system, core, controller, and advanced settings progressively in context.
- [ ] A verified local game can launch without a healthy server, metadata provider, achievement service, storefront, or internet connection.
- [ ] The product preflights game assets, emulator support, BIOS, controller, local cache, and save readiness before launch.
- [ ] The client captures a proven persistent save type, appends immutable revisions, restores history, queues safely offline, and exposes conflicts without silent last-write-wins.
- [ ] A clean client installation can restore a game and its compatible persistent save from the server.
- [ ] A user can export exact original game bytes, persistent saves, and a readable manifest into deterministic ordinary folders and verify their hashes.
- [ ] Server and client updates preserve known-playable configurations through compatibility checks, migration preflight, atomicity where possible, and rollback.
- [ ] Import supports both single-file immediacy and large staged collections through incremental, resumable, observable background work that can pause, resume, retry, and reconcile without duplicating unchanged content.
- [ ] The server reports repository protection honestly and supports verified full and incremental backup/restore to user-controlled storage; one server copy is never described as a backup.
- [ ] Failures are observable and actionable without turning normal operation into an alert stream; expert diagnostics remain available on demand.
- [ ] The codebase has automated tests, CI/CD, secure defaults, dependency boundaries, observability, and release engineering appropriate for trustworthy user data.

### Out of Scope

- Public ROM or proprietary BIOS distribution, acquisition assistance, cross-user search, sharing links, or “ownership verification” — incompatible with the private user-supplied-content posture and creates material legal/product risk.
- Paid hosted storage in the first milestone — requires dedicated counsel, policy, abuse, privacy, takedown, tenant-isolation, cost, and operations work.
- Building emulator cores or a new emulation ABI — mature ecosystems exist; integration quality is the initial value.
- Supporting every platform, emulator, controller, and system in v1 — portability must be proven with a narrow adapter and then a second independent client/adapter.
- Cross-core, cross-version, or cross-platform save-state guarantees — save states are implementation-bound; v1 concerns explicitly proven persistent saves.
- Streaming, cloud execution, netplay, recommendations, social features, and achievements in the critical path — enrichment cannot compromise launch, saves, offline use, or simplicity.
- General browser emulation in v1 — browser play is a valuable later client, but each core, system, browser, controller, and save combination needs an explicit capability, performance, storage, isolation, and licensing matrix.
- General reference-in-place libraries, managed moves, automatic patching, destructive cleanup, or file rewriting in v1 — their failure and portability semantics are not yet safe enough for the happy path.
- A custom operating-system/appliance distribution — interoperate with Batocera/RetroDECK-style environments later instead of owning their maintenance burden.

These exclusions scope early milestones. The broader ecosystem ambition remains recorded below and can be promoted when foundations are proven.

## Context

### Motivation

Existing emulator frontends can feel polished while making library custody, external-drive moves, duplicate handling, BIOS readiness, and save continuity manual or opaque. The project is motivated by a desire for the convenience of a modern digital game library without dependence on a proprietary storefront, permanent network connection, or hidden file layout.

The user should not fight folders, metadata providers, controller mappings, sync services, or server administration merely to resume a game. Automation should handle routine work, but every consequential action must remain explainable and reversible.

The central migration story is “new computer, same library”: install the client, pair it, immediately browse the curated catalogue, connect or select a controller, download only what is wanted, restore compatible progress, and play. Carrying an external drive or rebuilding a complete local mirror should be optional, not the default operating model.

### First End-to-End Proof

1. Start the server through the supported container configuration.
2. Pair a polished Mac client.
3. Import one user-supplied ROM through an explicit managed-copy flow.
4. Hash, identify, store, and display the exact bytes with provenance.
5. Download and verify the content into a local offline cache.
6. Confirm game, emulator, BIOS, controller, and save readiness.
7. Launch through one supported emulator adapter.
8. Play, exit safely, and synchronize a persistent save revision.
9. Restore on a clean client and continue playing.
10. Export the game, save, and manifest back to ordinary folders.

### Long-Term Vision

- Platform-neutral library and synchronization protocol with capability negotiation.
- High-quality clients for desktop, handheld, living-room, arcade, and homebrew environments.
- A built-in Phoenix LiveView web console for the self-hosted happy path and, later, narrowly supported browser play using the same API and save-revision contracts as every other client.
- Multiple storage backends, including local disk and S3-compatible object stores such as R2, without backend-specific client protocols.
- Selective synchronization: the server retains the canonical personal repository while each client downloads only chosen games, collections, or recently used content and manages a bounded local cache.
- Verified replication and backup to another local disk, NAS, or object store without requiring every client to mirror the full collection.
- Lossless ingestion of large and complex libraries, including disc sets, variants, patches, manuals, artwork, and system dependencies.
- Collections, favorites, queue, recency, play history, playlists, and restrained recommendations inspired by music-library workflows.
- Optional achievements, streaming, launcher exports, and third-party integrations isolated behind adapters.
- Potential paid hosting after the self-hosted product, legal posture, and operational model are proven.
- Supporting open-source libraries may be spun out when a stable boundary and multiple consumers justify them; repositories will not be split speculatively.

### Experience Constitution

The experience should feel like a beautifully designed console that respects ordinary files and self-hosting: effortless, never mysterious. Healthy operation is quiet. Exceptions are humane. Motion explains state or adds earned delight without slowing interaction. Every player-facing flow supports controller use without stranding keyboard, pointer, or assistive-technology users.

When tradeoffs are real, prioritize:

1. Data safety and recoverability
2. Reliable local play and save continuity
3. Clarity, accessibility, and low-administration operation
4. Performance and resource efficiency
5. Integrated delight
6. Feature breadth

See [`.planning/discovery/EXPERIENCE-ETHOS.md`](discovery/EXPERIENCE-ETHOS.md) for interaction contracts and design influences.

### Research Foundation

Pre-project research found mature local frontends, ROM managers, appliance bundles, metadata services, streaming systems, and raw synchronization tools, but no reviewed project documented the complete user-custodied, emulator-neutral library and revisioned-save boundary envisioned here.

- [Discovery synthesis](discovery/SUMMARY.md)
- [Open-source landscape](discovery/LANDSCAPE.md)
- [Cross-project user feedback](discovery/USER-FEEDBACK.md)
- [Technical, protocol, BIOS, storage, security, and legal risks](discovery/TECHNICAL-RISKS.md)
- [Web and client architecture](discovery/WEB-AND-CLIENT-ARCHITECTURE.md)
- [Naming research](discovery/NAMING.md)
- [Original vision](../original-deep-research-prompt.txt)

The discovery corpus contains 62 source-ledger entries. Mutable facts and legal/licensing claims must be revalidated when a phase depends on them.

### Project DNA

The project will be developed through GSD research, discussion, planning, implementation, and verification. It should have high automated quality, deliberate architecture, one-way dependency flow, excellent CI/CD and release engineering, containerized deployment, secure defaults, actionable observability, low operational noise, polished UX and microcopy, accessibility, and maintainable code that is a pleasure to read.

Elixir/Phoenix is the intended server foundation because it fits the owner's ecosystem and supports robust concurrent workflows and supervision. Supervision is not treated as a substitute for durable state, idempotency, bounded retries, process isolation, backpressure, resource limits, or tested recovery.

The intended delivery boundary is API-first Phoenix with LiveView as the first-party web console. LiveView may call the same application services directly inside the Phoenix application, but sockets, assigns, HTML, and LiveView events are never the cross-platform protocol. The first Mac proof is a SwiftUI application with targeted AppKit use, pending an empirical signing, sandbox, and emulator-launch spike.

## Constraints

- **Content posture**: User-supplied, private content only — do not distribute, locate, or facilitate acquisition of copyrighted ROMs or proprietary BIOS files.
- **Data ownership**: Preserve exact original bytes and provide documented, verified export — convenience cannot create lock-in.
- **Repository safety**: Distinguish canonical storage from independent backup copies and display their health — centralization must reduce rather than concentrate the risk of disk loss.
- **Reliability**: Never silently discard save conflicts or mutate imported source data — progress and provenance are trust-critical.
- **Offline**: A verified locally cached game must remain launchable without optional network services — network enrichment stays off the critical path.
- **Compatibility**: State support in terms of explicit client/emulator/core/system/version matrices — do not market aspirational universal compatibility.
- **Security**: Treat uploaded files, archives, metadata, filenames, emulator output, and parsers as untrusted — use validation, quotas, bounded workers, and isolation.
- **Operations**: Optimize for an opinionated low-administration deployment while preserving documented advanced adapters — the happy path is intentionally narrow.
- **Architecture**: Build domain contracts before splitting repositories; integrate mature emulators and services behind adapters; avoid cyclic dependencies and infrastructure leakage into the core domain.
- **Technology**: Elixir/Phoenix server is the strong default; Mac client technology and emulator adapter are decided by experiential spikes.
- **Delivery boundary**: Phoenix LiveView is the built-in web experience, not the durable client protocol; native clients must converge through API state after disconnects and missed notifications.
- **Naming**: `emu-server` is temporary until the product/protocol boundary survives the Mac spike.
- **Commercialization**: Hosting is not a configuration toggle — it requires separate legal, policy, security, tenant, cost, and SRE readiness.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Prove one complete Mac-to-server vertical slice first | Exposes real protocol, emulator, filesystem, controller, offline, and save constraints before broad platform promises | — Pending |
| Make trustworthy custody and continuity the product wedge | Adjacent projects cover local frontends and generic sync; evidence shows explainability, portability, and conflict-safe saves remain underserved | — Pending |
| Use managed copy as the initial import contract | It makes server availability, dedupe, backup, and export semantics reliable while leaving the source untouched | — Pending |
| Address immutable game bytes separately from mutable saves | Their identity, transfer, caching, conflict, and compatibility properties are fundamentally different | — Pending |
| Keep emulator adapters client-side | Local paths, process control, BIOS, controllers, and saves are platform/emulator concerns; the server protocol stays neutral | — Pending |
| API-first Phoenix with a LiveView web console | LiveView provides a superb turnkey browser/admin experience while a durable API supports offline native and constrained-device clients | — Pending |
| Native SwiftUI/AppKit Mac reference client | It most directly tests macOS filesystem, controller, Keychain, process, accessibility, signing, notarization, and offline requirements | — Pending |
| Treat browser emulation as a separate later client | WebAssembly play can be a major convenience win, but browser storage, threading, controller, lifecycle, core maturity, and licensing are matrix-specific | — Pending |
| Sync proven persistent saves before save states | Persistent saves have a more realistic portability contract; save states remain core/build/config bound | — Pending |
| Local disk first, S3-compatible storage behind an adapter | Proves custody and recovery with minimal operations while retaining a route to R2/S3/MinIO | — Pending |
| Server repository with selective client caches | Users can browse everywhere and download only what they intend to play; large collections do not need to travel with every device | — Pending |
| Curated personal views before exhaustive catalogue features | Information hierarchy, favorites, collections, recency, and queue reduce choice overload without requiring a recommendation engine | — Pending |
| Optional services never gate play | Metadata, artwork, achievements, storefronts, and recommendations must fail independently from local launch and saves | — Pending |
| Polish outranks breadth | The project exists to remove friction; features that destabilize or fragment the happy path are deferred | — Pending |
| Defer repository family and public naming | Stable contracts and multiple consumers should determine package boundaries and names | — Pending |

## Open Questions for Phase Planning

- Which first system and emulator adapter best prove persistent-save and BIOS behavior? A no-proprietary-BIOS GBA path using a controlled RetroArch/mGBA integration is the current low-risk hypothesis.
- Which direct macOS distribution and sandbox posture permits the required emulator adapter while retaining signing, notarization, secure credentials, accessibility, and safe file access?
- Does the initial account model expose one user only or a household owner? Keep tenant/user scope explicit even if the UI is single-user.
- When should S3-compatible direct transfer become necessary relative to server-proxied streaming?
- Which metadata/DAT/artwork sources can be used or redistributed under the intended open-source and possible commercial models?
- Which single WebAssembly core, system, and desktop-browser set, if any, passes the later browser-play performance, offline-cache, controller, save-sync, isolation-header, and licensing spike?

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `$gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `$gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-08-26 after initialization and preliminary ecosystem research*
