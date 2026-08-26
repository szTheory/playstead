# Preliminary Discovery Synthesis

**Status:** pre-`PROJECT.md` synthesis  
**Date:** 2026-08-26  
**Confidence:** medium-high on product shape; medium on implementation choices pending empirical spikes

## The Opportunity

The open-source ecosystem already has strong local emulator frontends, ROM catalogues, launcher integrations, appliance distributions, metadata services, streaming stacks, and generic file synchronization. The closest server precedent is RomM; GameVault demonstrates scanner and typed API lessons; OpenEmu is a useful Mac experience benchmark; RetroArch/Libretro is the most important emulator-integration boundary; ES-DE, Pegasus, Playnite, Batocera, and RetroDECK show client and appliance patterns; Syncthing demonstrates safe conflict-preserving replication.

What the reviewed projects do not establish end to end is an adopted, emulator-neutral, user-custodied service that combines:

- durable game and file identity independent of paths;
- explicit managed import, exact-byte preservation, and deterministic export;
- lazy, resumable multi-device content delivery;
- adapter-defined emulator integration;
- revisioned persistent-save synchronization with visible conflicts;
- BIOS readiness without acquisition or distribution;
- a quiet, controller-friendly client experience; and
- a self-hosted happy path that does not become an operations hobby.

That is the gap. The wedge is not “another emulator frontend.” It is **trustworthy personal game-library custody and continuity across devices**.

## Product Thesis

> A turnkey, open, self-hostable personal game library that makes importing, organizing, playing, and continuing games across devices feel effortless—while keeping every byte inspectable, recoverable, portable, and under the user's control.

The server is the durable library, identity, policy, and synchronization authority. Clients own local emulator paths, launch behavior, controller integration, offline cache, BIOS materialization, and save collection through explicit adapters. The protocol must remain emulator- and platform-neutral, but its portability is proven empirically rather than promised abstractly.

The project is also motivated by preservation and agency as mainstream game distribution becomes increasingly service- and account-dependent. The product must make a locally available game dependable: after content, emulator support, BIOS, controller, and save readiness are verified, ordinary launch must not depend on a metadata provider, achievement service, storefront, or healthy internet connection.

**Precedence rule:** when feature breadth conflicts with reliability, offline continuity, clarity, data portability, or integration quality, choose the smaller polished experience.

## Recommended First Proof

Build one complete Mac-to-server vertical slice:

1. A private server starts from an opinionated Docker Compose configuration.
2. A polished Mac client pairs with it.
3. The user drops one supported ROM into the client.
4. The client clearly says that it will **copy the file into the managed library** and leave the source untouched.
5. The server streams, hashes, stores, identifies, and records provenance for the exact original bytes.
6. The Mac client presents a fast library, downloads to an offline cache, and shows readiness.
7. One supported emulator adapter launches the game with a connected controller.
8. A persistent battery/NVRAM save is captured as an immutable revision and synchronized.
9. A clean client installation can restore the game and save.
10. The user can export the original game bytes, saves, and a documented manifest to ordinary folders and verify their hashes.

This is intentionally more integrated than a ROM CRUD application and narrower than owning emulator cores or supporting every platform.

## V1 Boundaries

### Build

- Private self-hosted server, initially optimized for one person or household owner.
- Content-addressed immutable blobs using full-stream SHA-256.
- Manifested asset sets so a game is not assumed to be one file forever.
- Source provenance and an import ledger explaining copied, matched, duplicated, quarantined, or ignored outcomes.
- Managed-copy import only for the first proof; never move or mutate the source.
- Exact-byte deduplication within the user's library while preserving aliases and variants.
- Recoverable exception queue for unknown, ambiguous, patched, incomplete, or malformed inputs.
- Local-filesystem object-store adapter first; S3-compatible adapter behind the same server boundary later.
- Versioned HTTPS API, client capability negotiation, device pairing, idempotent mutations, and HTTP range downloads.
- One Mac client, one emulator adapter, one or two deliberately selected systems.
- Persistent-save revisions, restore history, offline queue, and explicit conflict choice.
- BIOS auditor/readiness UX for user-supplied files; open replacements only after per-system license and compatibility review.
- Deterministic export, backup/restore validation, health checks, and migration safety.
- Compatibility-aware, atomic client/server updates; pinned adapter/content readiness; no background change may silently turn a known-playable local game into an unlaunchable one.

### Integrate

- Existing emulators/cores through client-side adapters.
- Metadata and hash databases through replaceable providers with match provenance, confidence, terms, caching policy, and user correction.
- Controller APIs and existing profiles without assuming mappings are portable across operating systems or drivers.
- Later exporters/adapters for RetroArch, ES-DE/Pegasus, Steam ROM Manager, Playnite, Batocera/RetroDECK, and Syncthing where they add value.

### Defer

- Public sharing, community uploads, ROM/BIOS catalogues, acquisition assistance, or supposed “ownership verification.”
- Hosted multi-tenant storage until legal, abuse, privacy, takedown, security, and operational obligations receive dedicated review.
- Embedded emulator development, a custom OS/appliance, netplay, recommendations, streaming, or cloud execution.
- Achievements are a later, optional adapter only. They must never require every user to create an external account, reconcile multiple providers, keep a network connection, or accept another service as the canonical game identity. Achievement outages or configuration failures must not affect launch, saves, or the core library.
- Broad PSP/Vita/Steam Deck/Windows/Linux promises until a second adapter demonstrates the protocol boundary.
- Cross-core or cross-version save-state portability; v1 sync concerns proven persistent saves only.
- General reference-in-place mode, managed moves, destructive normalization, automatic patching, and silent cleanup.

Deferred ambition remains part of the project vision; it is staged, not discarded.

## Core Domain Shape

The durable model should distinguish:

- immutable stored bytes (`blob`);
- where bytes came from (`source_file`);
- a playable multi-component release (`asset_set` and ordered `asset_member` records);
- recognition evidence and provider provenance (`recognition` and `metadata_assertion`);
- a user's logical library item and its installations;
- devices and adapter capabilities;
- BIOS dependencies and locally supplied validation state; and
- typed save artifacts with immutable revisions and ancestry.

Filenames, paths, CRCs, metadata matches, archive hashes, and object-store ETags are evidence—not canonical identity. Original bytes must never be silently rewritten to improve a match.

## Product Lessons from User Feedback

The evidence converges on six P0 experience requirements:

1. **Explain custody.** Users must know whether bytes were copied, referenced, deduplicated, or rejected.
2. **Make automation accountable.** Every scan and identification decision needs a receipt and a reversible next action.
3. **Treat exceptions as normal.** Patched games, ambiguous extensions, disc sets, missing companions, and unknown files belong in a humane review queue.
4. **Never hide sync risk.** Device identity, last-backed-up state, history, and binary conflicts must be visible; never silently use last-write-wins.
5. **Preflight playability.** BIOS, core, game assets, controller, cache, and save readiness should be checked before launch.
6. **Make exit excellent.** Export and recovery are primary features, not compliance checkboxes.

Scanning must be incremental, idempotent, cancellable, and observable. Unchanged content cannot acquire a fake new version that causes needless client downloads. Docker volume, UID/GID, backup, migration, and storage-health errors are product UX.

Large games make offline and update semantics especially visible. Downloads need resumability, capacity planning, pin/evict controls, checksum verification, and an unambiguous “Ready offline” state. Once ready, launch uses the verified local manifest and adapter configuration. Network services enrich the experience asynchronously; they do not sit on the critical path.

## Architecture and Repository Strategy

Start with the fewest repositories consistent with honest boundaries:

- one server repository or monorepo containing isolated domain, storage, recognition, transfer, sync, and web/admin modules;
- one Mac client once native lifecycle, controller, emulator, and notarization work makes that boundary real;
- no protocol package until the first Mac integration stabilizes the contract;
- later publish a small schema/SDK package and spin out supporting libraries only when at least two consumers prove reuse.

This follows the user's successful strangler-fig pattern: own unstable or janky dependencies only when a measured boundary justifies it, and replace them incrementally behind a stable adapter.

## Required De-Risking Spikes

1. **Mac adapter:** launch a legal homebrew test game, prove deterministic persistent-save flush/capture/restore, and characterize sandbox/notarization constraints.
2. **Asset manifests:** round-trip simple ROM, patched/unknown ROM, CUE plus tracks, multi-disc set, and BIOS-dependent content without changing bytes.
3. **Save compatibility:** test persistent save versus save state across core upgrades, a different core, and a second platform; publish the supported matrix.
4. **Transfer:** compare streamed upload plus Range with tus and S3 multipart under interruption, cancellation, checksum failure, and cleanup.
5. **Archive security:** test traversal, symlinks, recursion, member-count and decompression bombs inside a resource-limited worker.
6. **Metadata/licensing:** verify exact dataset and artwork terms, database rights, commercial-use constraints, caching, attribution, and redistribution before shipping data.
7. **Launch reliability:** interrupt the network, restart server/client processes, fail optional providers, and exercise upgrade/rollback paths while repeatedly launching a pinned local game and restoring its save.

## Remaining Decisions That Change the First Spike

- First system and emulator adapter. A no-proprietary-BIOS, simple persistent-save platform such as Game Boy Advance with a controlled RetroArch/mGBA path is the lowest-risk proof; this is a recommendation, not yet a decision.
- Mac delivery shape. A native shell likely offers the best controller, filesystem, process, keychain, updater, accessibility, and platform-feel integration, but SwiftUI/AppKit versus a cross-platform shell should be decided by a short experiential spike.
- Initial account boundary. Single-user is simplest; retaining an explicit tenant/user key in the domain model avoids unsafe global dedupe assumptions.
- First remote-storage milestone. Local disk should prove custody and recovery first; direct S3/R2 transfers are not necessary for the earliest end-to-end demo.

## Diminishing-Returns Boundary

Broad competitor search is now saturated enough to begin project definition. More value will come from phase-specific primary-source review and empirical spikes, not cataloguing additional frontends. Revalidate mutable facts when adopting a project, library, API, dataset, or license.

Naming and repository-family design should wait until the protocol and product boundary survive the Mac spike. `emu-server` is an appropriate working name.

## Evidence Map

- Ecosystem comparison and 20-source ledger: [`LANDSCAPE.md`](LANDSCAPE.md)
- User feedback and 18-source ledger: [`USER-FEEDBACK.md`](USER-FEEDBACK.md)
- Technical/legal research and 24-source ledger: [`TECHNICAL-RISKS.md`](TECHNICAL-RISKS.md)
- Experience principles and design sources: [`EXPERIENCE-ETHOS.md`](EXPERIENCE-ETHOS.md)
- Original project intent: [`../../original-deep-research-prompt.txt`](../../original-deep-research-prompt.txt)
