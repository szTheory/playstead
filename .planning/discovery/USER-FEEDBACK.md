# Cross-Project User Feedback and UX Research

**Scope:** self-hosted emulator/library server and clients  
**Researched:** 2026-08-26  
**Confidence:** MEDIUM — primary documentation and issue trackers were cross-checked. Individual issues are incidents, not population surveys.

## Executive Readout

The recurring problem is not merely “scan my ROMs.” It is loss of *explainability* when a library changes: a user cannot tell whether a file was copied, referenced, deduplicated, moved, omitted, identified wrongly, or safely backed up. OpenEmu's managed-library model prevents casual file damage but makes manual changes an error condition; RomM and Playnite show that mounts and path canonicalization can produce hangs or duplicate records. **Product lesson (inference): make every ingest result, identity decision, and storage action inspectable and reversible.**

Save synchronization is a separate correctness product, not a side effect of file sync. webRcade deliberately requires linking each device/browser and syncs state/configuration through cloud storage; current RomM-adjacent work documents version/hash negotiation churn. **Response:** explicit device identity, immutable save versions, provenance, and a visible conflict choice — never silent last-writer-wins.

Controller, BIOS, core, and platform configuration remain high-friction despite polished frontends. Batocera’s continuing Bluetooth/controller regressions and ES-DE's requirement to configure some emulators/BIOS files show why “automatic” must end in a verification screen and a one-click recovery path. Do not make legal claims or provide acquisition instructions for ROMs/BIOS; validate locally supplied files only.

## Prioritization

Scores: Severity (harm if wrong), Frequency (evidence recurrence/documented constraint), Opportunity (distinctive UX value), each 1–5. “Recurrence” is evidence strength, not a measured user count.

| Priority | Theme | S | F | O | Why now |
|---|---|---:|---:|---:|---|
| P0 | Import ledger, safe storage semantics, export | 5 | 5 | 5 | Prevents irreversible trust loss and lock-in |
| P0 | Save sync identity/version/conflict UX | 5 | 4 | 5 | Core promise across devices; silent overwrite is unacceptable |
| P0 | Scan/identity exception workflow | 4 | 5 | 5 | Ambiguous, patched, multi-file, and missing files are normal library reality |
| P0 | BIOS/core/controller readiness checks | 4 | 5 | 4 | “Play” must fail intelligibly, not through raw emulator errors |
| P1 | Incremental scan performance and cancellation | 4 | 4 | 4 | Large libraries make rescans disruptive |
| P1 | Docker/on-prem upgrade and volume safety | 5 | 3 | 4 | Admin failure threatens all user data |
| P1 | Controller-first and accessible navigation | 4 | 4 | 4 | Essential for handheld/TV use and cannot be bolted on late |
| P2 | Mobile/handheld/offline download behavior | 3 | 3 | 4 | Valuable client expansion after a reliable protocol |
| P2 | Library discovery, collections, save gallery | 2 | 3 | 4 | Delighters once integrity is dependable |

## Feedback Themes and Product Responses

### 1. Import semantics, duplicates, and opaque/dirty files — P0

**Facts.** OpenEmu documents a *managed* game library: games must be deleted through the app; a duplicate is rejected as “Already in library”; manually deleted/unreachable records have a separate failure state. It also sends ambiguous `.bin` files to a manual system resolver. [S01] OpenEmu issue #4438 reports a fan-translated PSX BIN/CUE rejected as “No valid system detected” although other tools played it. [S03] Playnite issue #2697 reports that UNC/doubled-slash scan paths added duplicates on each scan. [S04]

**Recurrence:** documented product constraint plus several independent reports (MEDIUM confidence).  
**Product lesson (inference):** “copy/import” versus “reference in place” is a user-facing contract, not an implementation detail.

**UX response.** Offer an ingest choice once, with a recommended safe default: **Managed copy to server storage** or **Indexed external location**. Persist content hash, original URI/path, canonical path, size, mtime, detected system, detection confidence, and relationship group. Dedupe by content hash *within a defined scope*; show aliases/variants rather than silently hiding them. Quarantine unreadable, zero-byte, unsupported, ambiguous, patched, and metadata-conflicted files with a reason and actions: retry, choose system, attach companions, keep unrecognized, or exclude. Never delete/move source files without explicit confirmation; preview disk impact and always provide export.

**Overgeneralization risk.** A managed-copy default consumes storage and is not right for huge NAS collections; hash equality does not make distinct revisions or regional variants interchangeable.

### 2. Multi-file/disc games and metadata mismatch — P0

**Facts.** OpenEmu says compressed archives with multiple files or optical-disc media cannot be imported as a single-ROM archive; CD/disc imports need CUE/CCD/M3U handling, and missing referenced files/invalid cue sheets are distinct import errors. [S01] The same project’s patched PSX issue demonstrates that checksum/system recognition can conflict with playable user-modified content. [S03] RomM issue #2329 requests a middle scan mode because new files nested in already identified folders can remain invisible until manual metadata refresh or costly complete rescan. [S07]

**Recurrence:** documented constraint plus several independent reports (MEDIUM).  
**UX response.** Model a **game release** separately from **files**: a release may own a disc set, playlists, patches, manuals, and alternate dumps. Validate referenced companions before publishing; show “2 of 3 files found,” not a misleading playable game. Metadata matching must expose candidate/score/source and permit user override; patched/hacked/homebrew media can be “recognized as custom” rather than rejected. Include per-item retry and re-identify; preserve prior metadata edits.

**Overgeneralization risk.** Exact grouping rules differ by platform/core, so do not promise universal automatic assembly in v1.

### 3. Library moves, external drives, and backup/exit — P0

**Facts.** An open OpenEmu report (#4063, Dec 2019) says moving a library to an external drive and resetting it left games unable to find ROM files despite files existing. [S02] OpenEmu’s guidance says manual deletion creates an unreachable database state. [S01] RomM issue #3483 (closed, Jun 2026) explains how Docker `VOLUME` topology can defeat hardlink optimization even when host directories are on the same filesystem. [S05]

**Recurrence:** several independent reports plus product constraint (MEDIUM).  
**UX response.** Store stable object IDs and content hashes, not just absolute paths. Provide a “storage health” page with mount identity, free space, last-seen time, read/write test, relocation wizard, dry run, rollback, and re-link-by-hash. Make **portable export** first-class: a manifest plus user-owned files/saves/assets in documented layout, and an import verifier. Call out whether a backup includes originals, metadata, artwork, saves, settings, and audit history.

**Overgeneralization risk.** Cross-filesystem hardlinks are impossible; copy/reflink behavior must be reported accurately rather than marketed as dedupe.

### 4. Scanning speed, correctness, and visibility — P0/P1

**Facts.** RomM #2329 contrasts quick scans that miss new nested files with complete rescans that recalculate known hashes and take too long. [S07] RomM #3836 (closed, Jul 2026) found unchanged records had their modification timestamps restamped during scans, breaking incremental clients and invalidating cover caches. [S06] RomM #2487 (closed, Sep 2025) reports a scan hang from Docker-volume ownership/persistence failure. [S08]

**Recurrence:** several independent reports and active issue history (MEDIUM).  
**UX response.** Implement bounded stages: discovery → cheap fingerprint → strong hash on new/changed/ambiguous → identification → enrichment. Persist a file fingerprint and a true content version separately from `last_seen_at`. Show count, rate, estimated remaining, current location, warnings, pause/cancel semantics, and a final reconciliation report. Make a scan idempotent: unchanged content must not trigger outbound sync/download/cache invalidation.

**Overgeneralization risk.** mtime/size shortcuts are not cryptographic proof; users need a slower “verify integrity” mode.

### 5. Saves, cloud/device sync, and conflicts — P0

**Facts.** webRcade documents optional Dropbox-backed persistent state for save states, in-game saves, high scores, and hardware settings, but linking is performed once **per device and/or browser**. [S09] Its changelog records cloud in-game-save support and later game-specific saves after state loading. [S10] RomM #3830 (open, Jul 2026) asks for a cross-library saves/states gallery because per-game visibility makes old saves hard to identify/clean up. [S11] A Decky RomM Sync research issue reports protocol negotiation/hash drift and notes it was not stable in its target release; treat this as a secondary implementation warning, not a protocol endorsement. [S12]

**Recurrence:** documented product behavior plus several requests/implementation reports (MEDIUM).  
**UX response.** Pair devices using revocable tokens; every sync records game identity, emulator/core, save path mapping, content hash, device, timestamp, and parent version. Upload versions append-only; automated merge is only permitted for known mergeable formats. For divergent binary saves, retain both, label the conflict clearly, show last launch/device context, and require selection/copy/export. Sync on explicit launch/exit and background reconnect, with an offline queue and clear “not yet backed up” state. A save gallery with thumbnails where available is a high-value follow-on.

**Overgeneralization risk.** Save formats and core paths differ; identical ROM title alone is insufficient mapping. Cloud-provider linking may be unsuitable for self-hosted/privacy-first users.

### 6. BIOS, cores/emulators, legal UX — P0

**Facts.** ES-DE Android guidance says some emulators require BIOS files configured before use and gives external-storage path constraints; it also only shows games when at least one supported-extension item exists. [S13] Its container documentation describes the frontend as browsing-only, with separate ROM and optional BIOS mounts. [S14] OpenEmu documents explicit errors for missing referenced files, unrecognized system, permissions, and invalid CUE content. [S01]

**Recurrence:** documented constraints across products (MEDIUM).  
**UX response.** Introduce a preflight **Ready to play** panel: game group completeness, supported client/core, optional/required BIOS status, checksum/filename match when known, controller readiness, and concise remedies. Scan locally supplied BIOS files and report only validation/result/location; avoid acquisition links or instructions. Core setup should be a declarative capability matrix per client, versioned separately from the game library, with safe defaults and per-game overrides.

**Overgeneralization risk.** BIOS necessity depends on core/system/mode; do not state “required” from a generic platform list alone.

### 7. Controllers, controller-first UX, accessibility — P0/P1

**Facts.** Original EmulationStation explicitly targets keyboardless navigation and retains configured devices; its recovery is deleting the input config to reopen setup. [S15] Batocera issue #11066 reports reconnecting a controller receives a new index, leaving player-one menu actions inaccessible. [S16] Batocera issues include Bluetooth pairing/device regressions and mapping failures; its current changelog also contains multiple controller/input fixes, including Bluetooth and per-game/controller paths. [S17][S18]

**Recurrence:** several independent reports plus ongoing update churn (MEDIUM).  
**UX response.** Make every screen usable with controller, keyboard, pointer, and screen-reader semantics; preserve focus, show visible action hints, and support reduced motion/contrast/large targets. Persist controller identity by hardware fingerprint where feasible, retain player assignment on reconnect, and expose a controller test/diagnostic view. Keep global defaults, per-client profiles, and per-game overrides with a reset/rollback trail. A first-run pairing wizard must offer keyboard fallback and never strand the user behind a nonworking binding.

**Overgeneralization risk.** Controller identity and mappings are OS/driver dependent; server-side policy cannot fix all local hardware failures.

### 8. Offline behavior, clients, updates, and self-hosted admin burden — P1/P2

**Facts.** webRcade makes cloud storage optional, implying a usable non-cloud base while cloud-backed uploads/state need activation. [S09] Batocera’s changelog shows updates routinely touch OS hardware support, Wi-Fi, controller mappings, save paths, cores, and NAS mounts; its release notes now display old/new versions before upgrading. [S18] RomM’s permission and mount reports show container defaults can turn an ordinary scan into an operational failure. [S05][S08]

**Recurrence:** documented operational constraints plus several independent reports (MEDIUM).  
**UX response.** Clients need an explicit download/cache state: available offline, queued, expired, storage use, checksum, and offline-safe launch rules. Treat server upgrades as migrations: compatibility check, automatic snapshot/backup suggestion, progress, rollback plan, post-upgrade health checks, and release notes keyed to changed capabilities. Provide an opinionated Docker compose path with UID/GID, mount validation, persistent-data inventory, health endpoint, backups, and in-app diagnostics bundle. Do not couple initial Mac-client proof to mobile/handheld delivery; define an authenticated protocol and capability negotiation first.

**Overgeneralization risk.** A single-container default will not cover all NAS/security models; keep advanced deployment paths documented but outside the happy path.

## Positive Patterns Worth Preserving

| Valued behavior | Evidence | Emu-server interpretation |
|---|---|---|
| Controller-first, keyboardless browsing | EmulationStation describes this as a core design goal. [S15] | Game-room/handheld UI cannot be a mouse-first admin console with controller support added later. |
| Explicit import diagnostics | OpenEmu enumerates concrete failure categories and a manual system resolver. [S01] | Keep automation, but name the problem and offer a safe next action. |
| Optional, device-aware persisted state | webRcade documents per-device/browser linking and saves/config sync. [S09] | Pairing and visible state are more trustworthy than invisible global syncing. |
| Per-game configuration and progressive fixes | Batocera’s changelog includes per-game configuration and recurring hardware fixes. [S18] | Defaults should be excellent, but overrides must survive upgrades and be easy to reset. |
| Visual save organization request | RomM #3830 requests a save/state gallery with thumbnails. [S11] | Later library UX should make progress recognizable, not filename archaeology. |

## Roadmap Implications

1. **Foundation: identities, storage contract, and audit trail.** Content-addressed objects, import/reference policy, grouped releases/files, export/backup manifest, mount health. This is the prerequisite for trustworthy sync.
2. **Mac vertical slice: scan → verify → browse → download/launch handoff.** Add staged/incremental scans, exception queue, candidate metadata, readiness panel, protocol capability negotiation; measure timing and failure modes.
3. **Save-sync correctness.** Device pairing, immutable versions, explicit conflict UI, offline queue, event journal, and recovery/export before automatic sync convenience.
4. **Client polish and accessibility.** Controller pairing/test, controller-first accessible navigation, per-game profiles, offline cache/download manager.
5. **Operations and expansion.** Opinionated Docker deployment, backups/migrations/diagnostics, then handheld/mobile clients backed by the same protocol.

## Facts vs. Inference

All “Facts” paragraphs above are source-backed observations. “Product lesson” and “UX response” sections are design inferences from those observations, not claims that the cited projects already implement them. No issue count in this document is treated as a prevalence statistic.

## Sources Ledger

Accessed 2026-08-26. Primary = official project documentation, GitHub issue, or official repository. Secondary source is explicitly labeled.

| ID | Title / date/status when material | URL | Type | Supports |
|---|---|---|---|---|
| S01 | OpenEmu User guide: Importing (edited 2021) | https://github.com/OpenEmu/OpenEmu/wiki/User-guide%3A-Importing | Primary docs | Managed library, duplicates, ambiguous BIN, archives/discs, import errors |
| S02 | OpenEmu #4063 “Move game library location” (open, 2019) | https://github.com/OpenEmu/OpenEmu/issues/4063 | Primary issue | External-drive relocation/relink failure |
| S03 | OpenEmu #4438 “Cannot add custom PSX rom” (closed, 2021) | https://github.com/OpenEmu/OpenEmu/issues/4438 | Primary issue | Patched/custom ROM recognition mismatch |
| S04 | Playnite #2697 duplicate entries on UNC paths (closed, 2021) | https://github.com/JosefNemec/Playnite/issues/2697 | Primary issue | Path normalization/duplicate risk |
| S05 | RomM #3483 Docker VOLUME/hardlink optimization (closed, 2026) | https://github.com/rommapp/romm/issues/3483 | Primary issue | Mount topology and dedupe semantics |
| S06 | RomM #3836 scan restamps unchanged ROM timestamps (closed, 2026) | https://github.com/rommapp/romm/issues/3836 | Primary issue | Incremental scan/sync/cache correctness |
| S07 | RomM #2329 intermediate scan request (open, 2025) | https://github.com/rommapp/romm/issues/2329 | Primary issue | Scan completeness versus speed |
| S08 | RomM #2487 volume permission scan hang (closed, 2025) | https://github.com/rommapp/romm/issues/2487 | Primary issue | Docker admin/permission failure |
| S09 | webRcade Cloud Storage docs | https://docs.webrcade.com/storage/ | Primary docs | Per-device link, optional cloud, saves/state/config sync |
| S10 | webRcade changelog | https://github.com/webrcade/webrcade/blob/master/CHANGELOG.md | Primary repository | Evolution of cloud in-game/game-specific saves |
| S11 | RomM #3830 save/state gallery (open, 2026) | https://github.com/rommapp/romm/issues/3830 | Primary issue | Save discoverability request |
| S12 | decky-romm-sync #829 protocol research (open, 2026) | https://github.com/danielcopper/decky-romm-sync/issues/829 | Secondary project issue | Save-sync implementation/churn warning only |
| S13 | RetroDECK ES-DE Android guidance | https://github.com/RetroDECK/ES-DE/blob/retrodeck-main/ANDROID.md | Primary docs | BIOS/config/external storage constraints |
| S14 | Containerized ES-DE documentation | https://github.com/blackoutsecure/docker-emulationstation-de | Secondary implementation docs | Frontend-only and persistent mount separation |
| S15 | Original EmulationStation repository/readme | https://github.com/Aloshi/EmulationStation | Primary repository | Keyboardless navigation and input recovery |
| S16 | Batocera #11066 controller index on reconnect (open, 2024) | https://github.com/batocera-linux/batocera.linux/issues/11066 | Primary issue | Reconnection/player assignment failure |
| S17 | Batocera #13201 Bluetooth/Wi-Fi/controller detection (open, 2025) | https://github.com/batocera-linux/batocera.linux/issues/13201 | Primary issue | Pairing/hardware regression risk |
| S18 | Batocera changelog (current repository) | https://github.com/batocera-linux/batocera.linux/blob/master/batocera-Changelog.md | Primary repository | Ongoing input, update, BIOS, NAS, and migration churn |

## Gaps / Follow-up Research

- Validate direct official APIs and current licensing for any metadata/hash databases before choosing an identification provider.
- Conduct actual user interviews/usability testing; issue trackers skew toward failures and technical users.
- Phase-specific spike: file watcher + object store + external-drive reconnect semantics on macOS and a NAS.
- Phase-specific spike: save-path mapping and conflict behavior for the first supported emulator/core pair.
