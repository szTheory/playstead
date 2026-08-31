# Roadmap: Playstead

## Overview

This MVP proves one trustworthy Mac-to-server custody and continuity journey: deploy a private server, pair a Mac, safely import and account for exact user-supplied bytes, selectively cache and play one supported game offline, preserve its persistent save across a clean Mac restore, and independently recover or export the evidence. The roadmap deliberately treats emulator, parser, save, and recovery uncertainty as pass/fail gates rather than broad compatibility promises.

## Phases

**Phase Numbering:**

- Integer phases are planned MVP work.
- Decimal phases are reserved for urgent inserted work discovered during execution.

- [x] **Phase 1: Private Custody and Durable Protocol** - Establish the self-hosted foundation and HTTP contracts every client can safely recover through. (completed 2026-08-28)
- [x] **Phase 2: Explainable Import and Exact Export** - Turn user files into recoverable, provenance-backed canonical assets through durable work. (completed 2026-08-30)
- [ ] **Phase 3: Mac Offline Play Vertical Slice** - Let a paired Mac browse, selectively cache, preflight, and launch one proven adapter path offline.
- [ ] **Phase 4: Persistent Save Continuity** - Preserve compatible progress through offline queues, immutable revisions, restore, and conflict recovery.
- [ ] **Phase 5: Recovery and Release Proof** - Demonstrate independently backed-up recovery, safe updates, diagnostics, and release-quality operations.

## Phase Details

### Phase 1: Private Custody and Durable Protocol

**Goal**: A self-hoster can run a private server and a Mac can pair and recover its authoritative state through a secure, versioned HTTPS protocol.
**Rationale**: Asset custody, device identity, idempotency, and cursor convergence are shared safety contracts. They must precede importer, cache, and save behavior so disconnects or LiveView lifecycle never define correctness.
**Depends on**: Nothing (first phase)
**Requirements**: OPER-01, OPER-02, PROT-01, PROT-02, PROT-03, PROT-04, PROT-05
**Success Criteria** (what must be TRUE):

  1. A self-hoster can deploy the private server through the documented Docker Compose path with persistent database and blob volumes, then complete setup in the LiveView console.
  2. An authenticated owner can approve a Mac pairing request, the Mac retains its scoped credential in Keychain, and the owner can revoke that device without disconnecting others.
  3. A client can declare its protocol, app, cache, transfer, adapter, and save capabilities and receive a clear remedy when they are incompatible.
  4. After a disconnection, a client can retry a mutation without creating another effect and reconstruct catalogue, job, transfer, and save state through HTTPS snapshot-and-cursor reads without a WebSocket.

**Research / spike flags**: Contract gate: prove idempotency receipts, authorization, and missed-notification cursor reset/convergence with HTTP contract tests. Preserve the API-first boundary; LiveView is console delivery only.
**Plans**: 8/8 plans executed (7/7 executed; 1 gap-closure plan pending from verification)

Plans:
**Wave 1**

- [x] 01-01-PLAN.md — Tracer: deployable HTTPS stack, `/healthz`, frozen `/api/v1/capabilities`, RFC 9457 error spine, boot gates and deploy docs

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 01-02-PLAN.md — Owner account with Phoenix Scopes, email-free password auth, setup-token bootstrap and the four-step setup wizard

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 01-03-PLAN.md — Console session list with per-session revocation, sudo-mode gate, login throttling, audit log, and email-free credential recovery

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 01-04-PLAN.md — Pairing protocol API: two-code RFC 8628 ceremony, one-time device credential, header-only auth, rotation, and revocation with tombstones

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 01-05-PLAN.md — Devices console: pairing approval queue and evidence card, device list, sudo-gated revoke, and root-CA fingerprint for client pinning

**Wave 6** *(blocked on Wave 5 completion)*

- [x] 01-06-PLAN.md — Capability negotiation with structured remedies, and the Idempotency-Key layer with transactional receipts and UUIDv7 natural keys

**Wave 7** *(blocked on Wave 6 completion)*

- [x] 01-07-PLAN.md — Change journal with tombstones, HMAC-signed opaque cursor, 410 resync, transactional snapshot, and the convergence proof

**Wave 8** *(gap closure — OPER-01 blocker from 01-VERIFICATION.md)*

- [x] 01-08-PLAN.md — Stage `docs/` in the Docker builder stage before compile, guard the compile-time-resource class with an ExUnit build-context test, and re-run the OPER-01 compose smoke plus the deferred UI-SPEC walkthrough

**UI hint**: yes

### Phase 2: Explainable Import and Exact Export

**Goal**: A user can safely place exact original bytes into managed custody, understand every outcome, and export or reimport them without loss.
**Rationale**: Verified manifests and durable import receipts create the canonical assets that selective cache, launch readiness, and recovery can honestly rely on.
**Depends on**: Phase 1
**Requirements**: IMPT-01, IMPT-02, IMPT-03, IMPT-04, IMPT-05, IMPT-06, PORT-02
**Success Criteria** (what must be TRUE):

  1. Before importing a supported file, a user sees that it will be copied into managed storage, its source will remain untouched, and the expected storage use; afterward they can inspect the original byte size, SHA-256, and provenance.
  2. An import produces a durable, recoverable receipt that clearly distinguishes new bytes, exact duplicates, aliases or variants, incomplete sets, patched or unrecognized content, quarantined input, and safe failures.
  3. A user can retain a supported multi-file game as an ordered manifest with explicit required members and resolve Needs Attention items using the displayed evidence and safe next actions.
  4. A user can stage a large collection, observe bounded progress, pause, resume, retry, and reconcile it after interruption without duplicating unchanged content.
  5. A user can export exact original game bytes into deterministic ordinary folders with a readable hash manifest, verify the export, and reimport it without byte changes, missing relationships, or duplicate logical records.

**Research / spike flags**: Required archive-security gate before enabling ZIP/7z/CUE extraction or deep inspection: adversarial corpus plus isolated CPU, memory, path, recursion, and expanded-size limits. Until it passes, accept only narrow magic-byte-validated formats and retain archives opaque.
**Plans**: 10/10 plans executed (2 gap-closure plans pending from verification)

Plans:
**Wave 0**

- [x] 02-01-PLAN.md — Import problem-code registry, inbox/export/same-volume readiness, container and compose mounts, and the phase test scaffolding

**Wave 1** *(blocked on Wave 0)*

- [x] 02-02-PLAN.md — Tracer: content-addressed write path and store seam, API upload with digest verification, durable receipt, blob serving, and a one-set export/reimport round trip

**Wave 2** *(blocked on Wave 1)*

- [x] 02-03-PLAN.md — Frozen system registry, six bounded never-raising format validators, opaque archive detection, header-evidence recognition, honest titles, and ordered multi-file manifests

**Wave 3** *(blocked on Wave 2)*

- [x] 02-04-PLAN.md — Streaming browser upload, the pre-copy preview, the import console, and the library asset detail where hash, size, and provenance are inspected

**Wave 4** *(blocked on Wave 3)*

- [x] 02-05-PLAN.md — Symlink-safe inbox staging, the durable session worker with cooperative pause/resume/retry/cancel, hybrid reconcile, bounded progress, and the receipts API

**Wave 5** *(blocked on Wave 4)*

- [x] 02-06-PLAN.md — Needs Attention derivation and quarantine state, the five audited reversible resolutions, the attention API, and the console inbox

**Wave 6** *(blocked on Wave 5)*

- [x] 02-07-PLAN.md — Deterministic BagIt layout with sidecars, the resumable write-then-verify export worker, and hash-set-first reimport identity with the five PORT-02 round-trip assertions

**Wave 7** *(blocked on Wave 6 — independently droppable)*

- [x] 02-08-PLAN.md — Administrator-supplied reference packs: pinned audited dependency, entity-safe capped streaming parser, digest-based matching, and the reference packs console

**Wave 8** *(gap closure — 02-VERIFICATION.md gap 1a plus the shared `format_bytes` root cause)*

- [x] 02-09-PLAN.md — Header evidence reaches production imports (bounded `Blobs.read_leading/2`, `@max_read` 66_048), live `unknown_system` inbox item grouped per session, and live `no_reference_installed` / `no_match` quiet reasons

**Wave 9** *(gap closure — 02-VERIFICATION.md gap 2 and gap 1b; blocked on Wave 8)*

- [x] 02-10-PLAN.md — Headerless NES/SNES `blob_fingerprints` writer with unique index and lazy backfill on pack install, DAT digest zero-padding fix, and the `unrecognized{ambiguous}` detector raising an inbox item

### Phase 3: Mac Offline Play Vertical Slice

**Goal**: A newly paired Mac can browse a curated server library, download only chosen verified content, and launch one deliberately supported game offline through a tested adapter.
**Rationale**: This is the first end-to-end user proof and the empirical boundary for macOS distribution, controller, BIOS, emulator, cache, and accessibility assumptions.
**Depends on**: Phase 2
**Requirements**: LIBR-01, LIBR-02, LIBR-03, LIBR-04, LIBR-05, CACH-01, CACH-02, CACH-03, CACH-04, PLAY-01, PLAY-02, PLAY-03, PLAY-04, PLAY-05, QUAL-01
**Success Criteria** (what must be TRUE):

  1. On a newly paired Mac, a user can browse the complete server catalogue before downloading bytes, quickly find content, and curate Favorites, Collections, Continue, Recent, and a play queue; the responsive LiveView console offers the same canonical library, import, pairing, and durable-job views.
  2. A user can choose a game or collection for download, resume verified ranges after interruption, and clearly distinguish server-only, queued, partial, verified-local, pinned-offline, and safe-to-evict content.
  3. A user can set a capacity policy, pin content, and reclaim only reconstructable unpinned bytes; a game becomes launchable only after every required manifest member verifies locally and remains launchable without server, internet, metadata, achievements, or other optional services.
  4. A user can select or install one supported Mac adapter, see its exact system/emulator/version/content/BIOS/save support, validate a locally supplied BIOS or supported open replacement, and receive a preflight remedy for each blocking readiness condition.
  5. A user can connect, test, assign, remap, reset, and recover a controller while retaining keyboard, pointer, screen-reader, focus, and reduced-motion fallbacks; from a signed/notarized build they can launch, exit, and relaunch one legally testable game after app or server restart.

**Research / spike flags**: Required Mac adapter gate before commitment: empirically choose the first system/emulator and direct-notarized versus sandboxed distribution posture using legal homebrew content. Demonstrate Keychain, external-process launch/recovery, controller recovery, BIOS handling, and safe persistent-save location/flush; do not promise the current GBA/mGBA hypothesis until this passes.
**Plans**: 9/10 plans executed

Plans:
**Wave 1**

- [x] 03-01-PLAN.md — Adapter spike: notarized non-sandboxed SpikeHost, hash-pinned emulator acquisition, seven D-01 probes, SPIKE-REPORT and the machine-readable adapter pin
- [x] 03-02-PLAN.md — Frozen Range contract: quoted strong ETag, single-range 206 with Content-Range, 416, If-Range, HEAD, positional-read storage fix, and `transfer` 1.1.0 capability advertisement

**Wave 2** *(blocked on Wave 1)*

- [x] 03-03-PLAN.md — Phase tracer: Mac app skeleton, snapshot-backed catalogue, one blob range-resumed and verified into the CAS, clone-materialized launch directory, pinned emulator launched offline
- [x] 03-04-PLAN.md — Server curation domain: the additive `curation` journal kind and snapshot branch, six scoped tables, fractional-index ordering with rebalance, idempotent per-row REST intents, and play sessions

**Wave 3** *(blocked on Wave 2)*

- [x] 03-05-PLAN.md — LiveView console parity: five curation shelves, canonical sidebar order, one status-slot component, search and filters, show-all-systems, and the web accessibility floor
- [x] 03-06-PLAN.md — Mac sync engine and library browse: cursor-resumed journal apply with expiry reset, local read models, typographic library shell, search and filters, offline browse

**Wave 4** *(blocked on Wave 3)*

- [x] 03-07-PLAN.md — Mac cache: persistent download queue with per-item control and auto-resume, read-time six-state derivation, quota plus free-space floor, pinning, and manual LRU-ordered reclaim
- [x] 03-08-PLAN.md — Mac curation: durable outbox of idempotent per-row intents, all five nouns usable offline, fractional-index reorder settle commands, and play-session recording off the launch path

**Wave 5** *(blocked on Wave 4)*

- [x] 03-09-PLAN.md — Adapter install and selection with an honest capability card, drag-in BIOS validation with no acquisition path, and the six-check readiness engine with a remedy per blocker and zero network calls

**Wave 6** *(blocked on Wave 5)*

- [ ] 03-10-PLAN.md — Controller lifecycle with non-stranding keyboard and pointer fallbacks, the accessibility and motion floor, the notarized release, launch-exit-relaunch proof, and the honest support matrix

**UI hint**: yes

### Phase 4: Persistent Save Continuity

**Goal**: A player can keep one adapter-proven persistent save safe across offline work, clean-Mac restore, export, and divergent-device conflicts without losing either version.
**Rationale**: Save behavior depends on the adapter's empirically proven save artifact and flush protocol from the Mac vertical slice; it cannot be safely generalized beforehand.
**Depends on**: Phase 3
**Requirements**: SAVE-01, SAVE-02, SAVE-03, SAVE-04, PORT-01
**Success Criteria** (what must be TRUE):

  1. After the adapter proves a safe flush, the Mac captures its declared persistent-save artifact and queues it locally while the server is unavailable.
  2. A user can see whether each save revision is local-only, queued, uploaded, current, restored, or conflicted rather than being shown a misleading generic sync status.
  3. On a clean paired Mac, a user can restore a compatible checksummed save revision and continue the game.
  4. A user can export exact original game bytes and persistent-save revisions into deterministic ordinary folders with a readable hash manifest, then verify the exported bytes and revision evidence.
  5. When two devices save from the same base revision, both revisions remain available with device, time, and play context; the user can inspect, choose, export, and resolve either side without silent last-write-wins.

**Research / spike flags**: Required compatibility gate: test the selected adapter's persistent-save type, safe-flush/debounce, crash behavior, and two-device divergent offline revisions. Save states remain local-only and outside the v1 portability contract.
**Plans**: TBD

### Phase 5: Recovery and Release Proof

**Goal**: A self-hoster can observe, back up, restore, update, and diagnose the proven Mac path with evidence rather than reassuring but unverified status.
**Rationale**: Canonical storage earns the custody promise only after an independent restore drill and known-playable upgrade/rollback path exercise the exact artifacts users depend on.
**Depends on**: Phase 4
**Requirements**: OPER-03, OPER-04, PORT-03, PORT-04, QUAL-02, QUAL-03
**Success Criteria** (what must be TRUE):

  1. A self-hoster can see separate, actionable health for the database, blob store, durable queues, migrations, storage capacity, and backup freshness without normal operation becoming an alert stream.
  2. A self-hoster can create full and incremental backups to an independent user-controlled destination and see each backup's coverage and last verification.
  3. A self-hoster can restore into a clean environment and verify database records, exact blobs, manifests, saves, and the known-playable Mac path.
  4. A self-hoster can run an upgrade compatibility and migration preflight, verify known playability afterward, and follow a documented rollback when the verification fails.
  5. A maintainer can run automated release checks for code quality, contracts, integration, enabled-parser adversarial fixtures, dependencies/licenses, container/SBOM security, and production smoke behavior; failed operations expose privacy-safe correlation IDs and an on-demand diagnostic bundle without leaking sensitive game data or credentials.

**Research / spike flags**: Recovery gate: clean-environment restore, mount/permission failure, migration rollback, and post-upgrade relaunch are mandatory evidence. Do not count a started container or a single repository volume as successful recovery.
**Plans**: TBD

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Private Custody and Durable Protocol | 8/8 | Complete    | 2026-08-28 |
| 2. Explainable Import and Exact Export | 10/10 | Complete    | 2026-08-30 |
| 3. Mac Offline Play Vertical Slice | 9/10 | In Progress|  |
| 4. Persistent Save Continuity | 0/TBD | Not started | - |
| 5. Recovery and Release Proof | 0/TBD | Not started | - |
