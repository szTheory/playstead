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
- [x] **Phase 3.5: Mac Verification Automation** - Stand up macOS CI and a UI-test harness so Mac client behavior is machine-verified instead of hand-checked. (completed 2026-09-03)
- [x] **Phase 4: Persistent Save Continuity** - Preserve compatible progress through offline queues, immutable revisions, restore, and conflict recovery. (completed 2026-09-09)
- [x] **Phase 4.5: Mac Pairing Ceremony** - Ship the client half of pairing so a human can actually pair a Mac, unblocking every checkpoint that needs a paired device. (completed 2026-09-10)
- [x] **Phase 4.6: Game Boy and Game Boy Color play and persistent saves** (INSERTED) - Extend the pinned adapter with cartridge-qualified battery/RTC continuity and automated fresh-profile restore proof. (completed 2026-10-12)
- [ ] **Phase 5: Recovery and Release Proof** - Demonstrate independently backed-up recovery, safe updates, diagnostics, and release-quality operations.
- [x] **Phase 5.1: Digest-bound Supply-chain Verification** - Advance recurring scanner, parser-fixture, SBOM, and artifact-attestation evidence without waiting for retained-game restore. (completed 2026-10-10)
- [ ] **Phase 6: Recovery Proof CI and E2E Pipeline** - Turn repeatable recovery evidence into fixture-driven automated proof, including a scoped deterministic continuation spike.

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
**Plans**: 30/31 have summaries. Plan 03-30 is held at the owner-directed Apple approval/provisioning gate; Plan 03-31 is complete. Phase verification remains `gaps_found` (4/5 roadmap truths), with physical PLAY-04 evidence still open.

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

- [x] 03-10-PLAN.md — Controller lifecycle with non-stranding keyboard and pointer fallbacks, the accessibility and motion floor, the notarized release, launch-exit-relaunch proof, and the honest support matrix

**Wave 7 — gap closure** *(from 03-VERIFICATION.md; CR-01/CR-02 already resolved by 03-REVIEW-FIX.md and need no plan)*

- [x] 03-11-PLAN.md — PLAY-03 gap A: source and pin a cited BIOS reference, wire it through the composition root, and make a drop all-or-nothing under interruption and concurrency
- [x] 03-12-PLAN.md — PLAY-05 gap B: one end-to-end release proof that refuses to certify an unnotarized build, behind a blocking Apple Developer Program enrolment checkpoint

**Wave 8 — gap closure** *(from the 2026-09-11 re-verification of 03-VERIFICATION.md)*

- [x] 03-13-PLAN.md — LIBR-02 gap: a device-reported availability read model, a frozen six-value filter vocabulary shared across both codebases, and a console filter where all six values discriminate and none falls through
- [x] 03-14-PLAN.md — LIBR-02 close-out: the Mac client actually reports its availability with a two-sided wire contract, the UAT tally becomes a fail-closed command, and the requirement and verification records flip only for what was proven

**Wave 9 — gap closure** *(from the independent re-verification that rejected 03-14's LIBR-02 claim: missing_dependency was still a hardcoded constant, plus review warnings WR-04 and WR-05)*

- [x] 03-15-PLAN.md — LIBR-02 real signal: missing_dependency computed from catalogue membership, CAS presence, download-queue rows, and the pin flag, proved through buildEntries and through the real HTTP endpoint with one shared report fixture
- [x] 03-16-PLAN.md — WR-04's 422 shape guard, WR-05's newest-wins outbox supersede, and the LIBR-02 requirement flip gated on the Mac-client-driven tests

**Virtual HID remains a separate OS-level evidence gate.** The latest hosted attempt stopped before UI launch because the runner lacked a provisioning profile; it did not establish an Apple rejection or HID runtime result. Completed 03-25 provides a finite UI_TESTING-only source on the ordinary no-HID lane. Plans 03-18 and 03-23 now use that source for packaged app recovery and mapping; 03-21 records saved app-level and objective accessibility evidence, but leaves G-03-8/9/10, PLAY-04, and Phase 03 open. The 03-17 entitled hosted run and paired-DualSense visible-navigation walkthrough are separate evidence lanes. Simulated results cannot establish GameController enumeration, entitlement qualification, or physical behavior. See [the owner-use and Virtual HID note](../notes/2026-09-24-first-adopter-and-virtual-hid-wait.md).

**Wave 5 — production controller input bridge** *(independent of the Apple Virtual HID wait)*

- [x] 03-22-PLAN.md — Production GameController input bridge and live test, covered by deterministic source tests; DualSense confirmation is recorded in Verify

**Wave 6 — first-adopter navigation and no-HID controller test enablement**

- [x] 03-19-PLAN.md — D-pad/arrow parity across Library browse and curation destinations, including Collections list/detail and system/availability filters; Cross/Circle behavior and owner DualSense Verify. Manage screens, text entry, and collection editing remain separate.
- [x] 03-25-PLAN.md — Finite UI_TESTING-only controller source and mandatory packaged no-HID recovery/input evidence; app-level enabling seam only

**Wave 7 — independent BIOS work and accessibility contract**

- [x] 03-20-PLAN.md — Lawful BIOS acceptance seam: explicit production references, one fixed synthetic packaged-app accept path, discriminator controls, and Release-hook exclusion
- [x] 03-24-PLAN.md — Machine-observable accessibility acceptance, explicit VoiceOver non-claims, and mutation-tested contract guards

**Wave 7 — app-level recovery**

- [x] 03-18-PLAN.md — Production non-modal recovery banner plus simulated disconnect/reconnect and keyboard/pointer fallback; focused UI evidence and fail-closed registration passed, OS discovery remains open

**Wave 8 — app-level mapping lifecycle**

- [x] 03-23-PLAN.md — Shipped mapping callbacks, committed AdapterHost refresh, and one-controller simulated relaunch proof; OS/physical evidence remains separate

**Wave 9 — bounded app-level evidence reconciliation** *(03-21 records no-HID results and retains the distinct 03-17/DualSense gates.)*

- [ ] 03-21-PLAN.md — Fail-closed partial evidence policy, ordinary four-layer run, UAT/validation sub-records, and continued PLAY-04 Pending status

**Separate OS-level capability proof — do not poll Apple**

- [x] 03-17-PLAN.md — Shared virtual-HID tracer: entitled test-only IOHIDUserDevice, stable mapping identity, and fail-closed hosted qualification; current hosted attempt stopped at runner provisioning before UI launch, so the entitlement remains unqualified

**UI hint**: yes

### Phase 3.5: Mac Verification Automation

**Goal**: Mac client behavior that today can only be confirmed by a human clicking through the app is proven by an automated test run on every push.
**Rationale**: Discovered during Phase 3 UAT (03-UAT.md). `playstead-mac` holds 26 test files and has **no CI job at all** — `.github/workflows/ci.yml` runs two jobs, both `ubuntu-24.04`, so nothing Swift is verified on push. There is also no XCUITest target and no view-rendering/snapshot harness anywhere in `PlaysteadTests/`, which is the direct and only reason five Phase 3 UAT checkpoints (03-03/D1, 03-06/D2, 03-07/D6, 03-08/D3, 03-10/D2) are human-only. They are not subjective — they are unautomatable with the harness as it stands. Every future Mac phase inherits the same manual-UAT tax until this is fixed, so the cost compounds.
**Depends on**: Phase 3
**Requirements**: QUAL-01 (verification posture); unblocks re-verification of LIBR-01, LIBR-03, LIBR-04
**Success Criteria** (what must be TRUE):

  1. A `macos-*` GitHub-hosted runner job builds the Mac app and runs the existing `PlaysteadTests` target on every push and pull request, and fails the build on any test failure.
  2. An XCUITest target exists and drives the real app: the library shell, the curation shelves (including the `.onMove` drag reorder), and the downloads/quota/reclaim/storage views are exercised by automated interaction rather than by hand.
  3. A view-rendering/snapshot harness asserts the locked 03-UI-SPEC.md contract — the 8-step navigation order, the status vocabulary and its ladder, honest empty states, and card geometry that never uses cover art or title-derived color — so a visual regression fails CI instead of a UAT question.
  4. Linux `compose-smoke` proves deployment topology; native PostgreSQL 17 plus Phoenix beside XCUITest proves Mac client/server behavior.
  5. A keyboard-only navigation pass over every Mac surface is automated, and the accessibility audit runs against a live accessibility tree rather than the current declarative-manifest tree-walk.
  6. Each Phase 3 UAT checkpoint this phase closes is re-recorded in `03-UAT.md` as `source: automated` with its covering test named.

**Research / spike flags**: Runner choice is decided — GitHub-hosted `macos-*`. That deliberately leaves three classes out of scope, and they stay `blocked` in 03-UAT.md rather than being faked: physical controller hardware (checkpoints 8, 9), a real emulator install plus real game bytes (checkpoint 7), and a Developer ID certificate for signing/notarization (checkpoints 14, 15). Revisit a self-hosted runner only if those become recurring blockers. Watch Xcode-version drift on hosted runners and snapshot-test flakiness across macOS releases — pin both.
**Plans**: 10/10 have summaries. Phase execution is complete; its verification report is stale because covered source files changed after the last report. Refresh only against reviewed exact-head hosted evidence for the relevant source revision.

Plans:
**Wave 0**

- [x] 03.5-01-PLAN.md — Nine-file macos-26 adoption harness, five canaries, and fail-closed exact-run validator

**Wave 1** *(blocking Wave 0 empirical approval)*

- [x] 03.5-10-PLAN.md — Authorized push/PR publication, exact run-ID validation, and human adoption approval

**Wave 2**

- [x] 03.5-02-PLAN.md — One-build four-layer XCTest orchestration, sanitized evidence, and candidate-only refresh

**Wave 3**

- [x] 03.5-03-PLAN.md — Release-safe deterministic profiles, stable identifiers, and shared focus contract

**Wave 4**

- [x] 03.5-04-PLAN.md — Locked visual, semantic, and motion snapshot contracts

**Wave 5**

- [x] 03.5-05-PLAN.md — Production reachability, keyboard traversal, and live accessibility audits

**Wave 6**

- [x] 03.5-06-PLAN.md — Curation shelf rendering plus exact drag and keyboard reorder
- [x] 03.5-07-PLAN.md — Downloads/quota/reclaim/storage interaction plus focused visual and motion coverage

**Wave 7**

- [x] 03.5-08-PLAN.md — Native Phoenix pairing/snapshot/Keychain spine after all UI producers

**Wave 8**

- [x] 03.5-09-PLAN.md — Final allowlist, authorized exact hosted run, structured Roadmap/UAT handoff

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
**Plans**: 25/25 plans executed (23 executed; 2 gap-closure plans pending from the 4/5 re-verification)

Plans:

**Gap closure** *(from 04-VERIFICATION.md, 1/5 must-haves verified)*

- [x] 04-21-PLAN.md — Tracer: supply real `Playstead.Saves` revisions to the export pipeline (WINDOWS #30 / PORT-01)
- [x] 04-22-PLAN.md — Wire per-revision save history to real `SaveStore` data and give `SaveRollup` a caller (WINDOWS #43, #47)
- [x] 04-23-PLAN.md — Drain the save outbox, commit crash-recovered bytes to the CAS, close the ledger (WINDOWS #42, #52, #32)

**Gap closure, round 2** *(from the 04-VERIFICATION.md re-verification, 4/5 must-haves verified)*

- [x] 04-24-PLAN.md — Total order on revision queries so export `seq`/filenames are deterministic under a `recorded_at` tie (criterion 4 / PORT-01)
- [x] 04-25-PLAN.md — Fix `SaveOutboxDrainTrigger.fire()`'s TOCTOU so the single-lane drain guarantee is real (criterion 5 / SAVE-04)

- [x] 04-20-PLAN.md

- [x] 04-19-PLAN.md

- [x] 04-15-PLAN.md
- [x] 04-16-PLAN.md
- [x] 04-17-PLAN.md
- [x] 04-18-PLAN.md

- [x] 04-14-PLAN.md

**Wave 1**

- [x] 04-01-PLAN.md — Run probe SAVE-P1 and pin its report (D-02)
- [x] 04-02-PLAN.md — Fix the Mac inherited defects: backup exclusion, launch mutex, widened saveDirectory check (D-63, D-65, D-42)
- [x] 04-03-PLAN.md — Server free-space reserve, save problem codes, and save-lane limits (D-64, D-33)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 04-04-PLAN.md — Tracer: one save end-to-end, Mac capture to server revision and back

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 04-05-PLAN.md — Revision DAG, accept-and-branch, branch heads, and append-only resolution (D-09–D-15, D-30, D-48)
- [x] 04-06-PLAN.md — Capture tiers, crash recovery, disk-full path, and quota rules (D-04–D-08, D-29, D-31)

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 04-07-PLAN.md — Restore compatibility gate, LaunchSavePlanner, and the never-in-place executor (D-18–D-24, D-41–D-47)
- [x] 04-08-PLAN.md — Fill the reserved saves export slot with deterministic layout and manifest (D-56–D-62)

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 04-09-PLAN.md — Shared save vocabulary, three-axis state model, rollup, Save row, and history sheet (D-34–D-40, D-67)
- [x] 04-10-PLAN.md — Saves-owned attention source and the LiveView console saves surface (D-66, D-67, D-53)

**Wave 6** *(blocked on Wave 5 completion)*

- [x] 04-11-PLAN.md — Two versions of your progress: comparison sheet and append-only resolution on the Mac (D-48–D-55)
- [x] 04-12-PLAN.md — The only-copy danger case: escalated panel and interruptive modal (D-32, D-40)

**Wave 7** *(blocked on Wave 6 completion)*

- [x] 04-13-PLAN.md — Restore proof, zero-network Play flow, validation map, and CP7-SAVE-C (D-68)

### Phase 4.5: Mac Pairing Ceremony

**Goal**: A human with a fresh Mac install and a server URL can pair the Mac from inside the app, with no shell script, no hand-written Keychain item, and no developer intervention.
**Rationale**: Discovered 2026-09-08 during Phase 4 UAT (WINDOWS #54), when the owner tried to run CP7-SAVE-C and had no way to pair. The server half has been complete since Phase 1 — `POST /device-pairing/requests`, `GET /requests/:id`, `POST /requests/:id/redeem`, plus the devices approval console — and the client calls none of it. `APIClient.swift:57` says so outright; `LibraryShellView.swift:474` tells the user to "Pair with your Playstead server", naming an action that exists nowhere in the app. 03.5-08 proved the ceremony only by driving it from `scripts/ci/live-server.sh` and handing a credential to a test build; the human path was never built. Every production `PairingCredential` construction is a Keychain **read** — the only writers are `UI_TESTING`-gated. Consequence: every checkpoint requiring a paired Mac is unperformable across Phases 3, 4 and 5, so the cost compounds exactly the way Phase 3.5's did. Worked around for the owner's Mac only, by driving the production endpoints by hand.
**Depends on**: Phase 1 (server endpoints, complete)
**Requirements**: PROT-01 (its second clause — "the Mac client stores the resulting scoped credential in Keychain" — is currently marked complete with no user-reachable implementation); unblocks CP7-SAVE-C and every paired-device checkpoint
**Success Criteria** (what must be TRUE):

  1. A user can enter a server URL in the app, see the display code the server issued, have it approved in the devices console, and end with a working credential in the login Keychain.
  2. The ceremony lives in a `PairingCoordinator` a test constructs directly — no step of it inline in a SwiftUI view, the WINDOWS #37/#45 rule.
  3. The empty state that already says "Pair with your Playstead server" offers the action it names.
  4. Each of the server's four refusals (expired, already redeemed, not approved, slow down) is a distinct actionable state, not one generic failure.
  5. A successful pairing captures the trust anchor to `AppPaths.root/pinned-ca.der` (derived once via `AppPaths.pinnedCertificate`), which APIClient evaluates pinned trust against at every request.
  6. The whole ceremony is proven against the real Phoenix in the live-server CI layer — a UI test against a stub is not evidence that a human can pair.

**Research / spike flags**: Certificate capture is the least-proven step; which anchor to persist depends on the deployment (Caddy internal CA vs. a public certificate). If it cannot be made reliable, ship the ceremony without it and record the pin as its own window rather than writing a file `APIClient` will then trust wrongly.
**Plans**: 6/6 plans executed

Plans:
**Wave 1**

- [x] 04.5-01-PLAN.md — `PairingClient`, `PairingCoordinator`, certificate capture, `PairingView` and its two call sites, tests at three levels

**Gap closure — Wave 1**

- [x] 04.5-02-PLAN.md — https-only ceremony, fail-closed trust-anchor pinning with credential rollback, and the first test asserting `pinned-ca.der` exists (gap 1 / criterion 5)

**Gap closure — Wave 2**

- [x] 04.5-03-PLAN.md — monotonic generation token checked after every await, and tests that cancel with a request genuinely in flight (gap 2 / criterion 2)

**Gap closure — Wave 3**

- [x] 04.5-04-PLAN.md — TLS termination for the mac_ci Phoenix on 4010 (run-scoped CA + trusted anchor), the whole live-server layer moved onto https, WR-01/WR-02 closed, and one recorded green run of `PairingCeremonyTests` (criterion 6 / criterion 1)

**Gap closure — Wave 4**

- [x] 04.5-05-PLAN.md — hosted-runner TLS provisioning and teardown, `PairingCeremonyTests` promoted to `--required-test` with a fail-closed gate self-test, PROT-01 completed with cited evidence (criterion 6)

**Gap closure — Wave 5**

- [x] 04.5-06-PLAN.md — the captured anchor wired into `APIClient` at both real construction sites, one `AppPaths`-derived pinned path, a live-object key-link test, and a `PinningDelegate` unit test proving pinned-vs-default trust divergence (criterion 5)

### Phase 4.6: Game Boy and Game Boy Color play and persistent saves (INSERTED)

**Goal**: A player can import, cache and play qualified Game Boy and Game Boy Color games through the existing pinned mGBA installation, preserve complete cartridge-specific battery/RTC progress, and restore it into a fresh paired Mac profile with verified in-game continuity.
**Rationale**: The three completed GB/GBC spikes qualify emulator feasibility and identify production catalog, save-identity and independent-restore gaps. Register their implementation slice without another feasibility or owner-UAT loop.
**Depends on**: Phase 4 (completed save foundation); reuse completed Phase 2 import and Phase 4.5 pairing, plus implemented Phase 3 client software. Parked Apple/HID qualification is not a prerequisite for this software slice.
**Requirements**: PLAY-01, PLAY-02, SAVE-01, SAVE-02, SAVE-03 (additional GB/GBC acceptance; existing GBA completion remains recorded)
**Success Criteria** (what must be TRUE):

  1. One managed, pinned mGBA 0.10.5 installation exposes explicit GBA, GB and GBC system descriptors, truthful BIOS/save capabilities and supported-system readiness; verified local games remain playable without optional network services.
  2. Bounded cartridge/header qualification distinguishes the tested MBC1 8 KiB SRAM, MBC5 32 KiB SRAM and MBC3 32 KiB SRAM plus 48-byte RTC artifact. Unknown or unsupported system/cartridge/layout combinations fail closed with a recoverable explanation, instead of inheriting GBA byte-size medium labels.
  3. The production capture, queue, immutable upload/download and restore composition preserves each complete qualified battery artifact, including RTC bytes, and presents accurate revision states. Existing GBA save behavior stays covered.
  4. Restore expectations come independently from the target ROM/cartridge and declared adapter contract. Wrong ROM, system, layout, medium or byte bindings and undeclared/unknown combinations are rejected before writing; revision metadata cannot certify itself.
  5. The three authored GB/GBC layouts pass production import → verified cache/offline launch → game progress → capture/upload → fresh-profile restore → actual game readback, alongside an established GBA regression. New recurring unit, seam, server, packaged no-HID and save E2E checks use existing CI lanes and fail on missing, skipped or zero-discovery evidence; no repeated manual UAT is required for observable outcomes.

**Planning inputs**: [.codex/skills/spike-findings-playstead/SKILL.md](../.codex/skills/spike-findings-playstead/SKILL.md), [GB/GBC report](spikes/GB-GBC-REPORT.md), [wrap-up](spikes/WRAP-UP-SUMMARY.md), and [SEED-035](seeds/SEED-035-game-boy-and-color-support.md). Reuse final authored fixture registry hashes and sufficient recorded feasibility evidence; the historical gap probe is not a desired-behavior CI test.
**Qualification boundary**: Phase4.6 qualifies the declared mGBA0.10.5 GB/GBC cartridge matrix and complete persistent saves through production fresh-profile continuity. Hosted Accessibility runtime, OS enumeration, physical controllers, distribution, broader mapper/RTC cases, power-loss durability and the whole milestone remain outside this proof. Owner originals and existing imports are preserved.
**Plans**: 4/4 plans complete in 4 sequential waves — final goal verification passed64/64; all three GB/GBC game journeys and bounded GBA regression passed. See04.6-VERIFICATION.md and04.6-COMPLETION.json.

Plans:
**Wave 1**
- [x] 04.6-01-PLAN.md — GB MBC1 production tracer: verified cache/offline play, source-qualified capture, fresh paired restore and actual game readback

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 04.6-02-PLAN.md — GBC SRAM/RTC layouts, independent restore rejection, persisted format and complete-byte live-server custody

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 04.6-03-PLAN.md — All 33 approved native library/readiness/history/Details/action/status state criteria

**Wave 4** *(blocked on Wave 3 completion)*
- [x] 04.6-04-PLAN.md — Three GB/GBC game oracles, bounded established AerevenAdvance GBA regression, exact recurring CI and cleanup guards

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
**Plans**: 12/14 have summaries. Plan 05-05 is halted at the retained-restore and named in-game-observation gate; Plans 05-04 and 05-07 depend on it and are not runnable yet.

Plans:
**Wave 1**

- [ ] 05-01-PLAN.md — Independently verified full/incremental backup-set evidence and freshness

**Wave 2** *(blocked on Wave 1 completion)*

- [ ] 05-02-PLAN.md — Authenticated quiet Operations health and recovery-receipt evidence

**Wave 3** *(blocked on Wave 2 completion)*

- [ ] 05-03-PLAN.md — Isolated clean-room restore proof and deep recovery scrub
- [ ] 05-06-PLAN.md — Opaque correlation propagation and privacy-safe diagnostic bundles

**Wave 4** *(blocked on Wave 3 completion)*

- [ ] 05-08-PLAN.md — Server D-16/D-17 propagation through jobs, transfers, storage, pairing, and save reconciliation
- [ ] 05-10-PLAN.md — Real PostgreSQL backup capture and receipt correctness

**Wave 5** *(blocked on Wave 4 completion)*

- [ ] 05-09-PLAN.md — Mac D-16/D-17 propagation through pairing, transfer/save evidence, and launch handoff
- [ ] 05-11-PLAN.md — Concrete isolated Compose pg_restore, full server scrub, and verified handoff

**Wave 6** *(blocked on Plans 05-09 and 05-11 completion)*

- [ ] 05-12-PLAN.md — Verified-only restore handoff for the existing Mac preparation command
- [ ] 05-14-PLAN.md — Preflighted live Compose backup mount and durable operator receipt command

**Wave 7** *(blocked on Plans 05-12 and 05-14 completion)*

- [ ] 05-13-PLAN.md — Retained real-chain restore target, explicit handoff, and exact cleanup

**Wave 8** *(blocked on Wave 7 completion)*

- [ ] 05-05-PLAN.md — Controlled upgrade, certified rollback branches, and clean-Mac recovery proof

**Wave 9** *(blocked on Wave 8 completion)*

- [ ] 05-04-PLAN.md — Ordered fail-closed release certification core and named-observation gate

**Wave 10** *(blocked on Wave 9 completion)*

- [ ] 05-07-PLAN.md — Consume Phase 05.1 supply-chain evidence and add the duplicate-save regression

### Phase 05.1: Digest-bound supply-chain verification (INSERTED)

**Goal:** A maintainer can produce repeatable dependency, license, parser-fixture, SBOM, and attestation evidence tied to the exact tested release artifact, and missing or mismatched evidence fails closed.
**Rationale:** This recurring release-security work is already included in Phase 05 Plan 05-07, but that plan also requires the retained restore and named in-game continuation checkpoint. Split the scanner and inventory automation into an independent slice so it can advance while the genuine restore observation remains parked.
**Depends on:** Phase 4 (completed; this work does not require the retained restore target, a private game fixture, or controller/HID evidence)
**Requirements:** QUAL-02
**Success Criteria** (what must be TRUE):

  1. A repeatable CI job scans source and the exact release image with pinned scanner/action versions and emits machine-readable vulnerability and license evidence.
  2. The job creates a CycloneDX SBOM and attestations that verify against the exact tested artifact digest; missing, malformed, or mismatched evidence fails closed.
  3. A tracked inventory maps every enabled parser to an adversarial fixture category and fails when a parser or mapping is absent.
  4. Contract tests cover missing scan results, license verdicts, SBOM, attestation, parser mappings, and digest mismatch without accessing private game content or owner credentials.
  5. CI evidence excludes ROM/save bytes, owner identity, local paths, and credentials.

**Plans:** 1/1 complete. Automated verification and UAT pass for published main e115899 / run 38098375547; exact tested archive, strict complete evidence, provenance/CycloneDX and finalization verified. No human UAT remains. See `05.1-UAT.md`, `05.1-VERIFICATION.md` and `05.1-AUTOMATION-CLOSURE.json`; broader QUAL-02 and owner-workspace variants remain outside this slice.

Plans:
- [x] 05.1-01-PLAN.md — Scan and attest the tested artifact; enforce parser fixtures and strict privacy-safe evidence

### Phase 6: Recovery proof CI and E2E pipeline

**Goal**: Turn repeatable recovery evidence into a fixture-driven CI/E2E pipeline: fresh restore provisioning, database readiness, storage ownership, multi-chunk import, journal convergence, local-CA pairing, cache/preflight, and save transport.
**Rationale**: Recovery confidence must be reproducible rather than depend on a long, manual, environment-sensitive runbook. A controlled legal fixture can extend that evidence to a deterministic in-game continuation proof without overstating support for other games.
**Depends on**: Phase 5
**Requirements**: PORT-04, QUAL-02
**Success Criteria** (what must be TRUE):

  1. CI can provision a clean isolated restore target and prove the database, object store, migration and ownership readiness gates before exercising recovery.
  2. CI can prove import, change-journal convergence, private-CA pairing, offline cache/preflight, and save transport against a controlled fixture without recording owner identity, local paths, credentials, or fixture bytes in Git.
  3. A scoped spike determines whether recorded legal-fixture inputs, SRAM/save-byte evidence, a fresh emulator process, and a game-visible resumed-state assertion can provide deterministic continuation evidence. Its result makes no claim about arbitrary games.

**Research / spike flags**: The in-game assertion must verify a loaded resumed state in a newly launched emulator; an SRAM diff alone is insufficient. Fixture acquisition/distribution remains outside the repository.
**Plans:** 21/21 have summaries; 06-08 and 06-10 remain halted, and 06-13 records a blocked-capability outcome. Verification is `gaps_found`: 38/42 UAT checks pass and four are blocked on the recorded private-fixture, Apple HID, and reviewed exact-head prerequisites.

Plans:
**Wave 1**
- [x] 06-01-PLAN.md — Isolated Linux recovery fixture and privacy-safe CI evidence
- [x] 06-06-PLAN.md — Reviewed Mac visual-baseline reconciliation
- [x] 06-07-PLAN.md — Browser-session and remaining server regression repair
- [x] 06-11-PLAN.md — Independent no-HID Mac tests and explicit virtual-HID gate
- [x] 06-13-PLAN.md — Checksum-pinned private mGBA candidate qualification (blocked-capability recorded; no fixture access)
- [x] 06-14-PLAN.md — Ordinary Mac reachability and required storage rendering repair
- [x] 06-15-PLAN.md — Ordinary no-HID library, curation, search, and save-front-door UI repair
- [x] 06-17-PLAN.md — Isolated LiveServer startup and private-CA pairing without passwordless sudo

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 06-02-PLAN.md — Merge-blocking macOS native recovery-fixture coverage
- [x] 06-08-PLAN.md — Regression rerun; server passed, Mac halted at virtual-HID provisioning
- [x] 06-12-PLAN.md — Bounded reliability reproduction and save refusal classification
- [x] 06-16-PLAN.md — Storage interaction and adapter accessibility UI repair

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 06-03-PLAN.md — Same-host retained-restore-to-clean-Mac coordinator
- [x] 06-18-PLAN.md — Repaired ordinary Mac gate and separate evidence handoff

**Wave 4** *(blocked on Wave 3 completion)*
- [x] 06-04-PLAN.md — Private continuation-environment checkpoint
- [x] 06-09-PLAN.md — Current hosted Linux and ordinary native Mac evidence, with separate entitlement status

**Wave 5** *(blocked on Wave 4 completion)*
- [x] 06-05-PLAN.md — Capability-gated fixture-specific continuation spike

**Wave 6** *(blocked on Wave 5 completion)*
- [x] 06-10-PLAN.md — Continuation qualification halted before fixture access on mGBA 0.10.5

**Initial Phase 06 verification checkpoint (before Plan 06-11):** Same-host recovery passed unattended. The bounded server suite passed; the Mac aggregate stopped at virtual-HID provisioning before test execution. Actual continuation remains `qualification / blocked-capability`. Hosted evidence and the full regression gate remain open; see `06-VERIFICATION.md`, `06-REGRESSION-GATE.md`, and `06-CONTINUATION-QUALIFICATION.md`.

**Plan 06-11 update (2026-09-30):** Plan 06-18's complete current-fingerprint ordinary no-HID gate passed and resolves the local ordinary failures recorded on 2026-09-28. The entitled lane remains `blocked/not-configured`; hosted, reliability, and continuation evidence remain independent. Plan 06-11 is complete for its local ordinary lane split and CI selection deliverables. See `06-11-SUMMARY.md` and `06-REGRESSION-GATE.md`.

**Plan 06-12 update (2026-10-01):** APFS passed 20/20, Wallaby passed 20/20, and the live save refusal-classification run passed 10/10 on fingerprint `e6285b97a342f7161baf19a1689c55ddb43f27c3162a6eab0ca9247c1a0e47bd`. Earlier process-cleanup and app-not-running failures remain classified in `06-RELIABILITY-EVIDENCE.md`; only the final complete run is counted. At that update, Plan 06-09 was the only incomplete non-halted plan and still needed hosted evidence; the following update records its completion.

**Plan 06-09 update (2026-10-01):** Draft PR #6's reviewed SHA `631edf9665ace49c91a02bdebcbd49dbc0f0e6ba` passed hosted Linux recovery, server precommit, Docker cold-start, and ordinary Mac verification in workflow [36910091796](https://github.com/szTheory/playstead/actions/runs/36910091796). The entitled virtual-gamepad job was skipped/not configured and remains a separate open gate. See `06-09-SUMMARY.md` and `06-HOSTED-EVIDENCE.md`; Phase 06, `PORT-04`, and `QUAL-02` remain open.

## Progress

| Phase | Plan Summaries | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Private Custody and Durable Protocol | 8/8 | Complete    | 2026-08-28 |
| 2. Explainable Import and Exact Export | 10/10 | Complete    | 2026-08-30 |
| 3. Mac Offline Play Vertical Slice | 30/31 | In Progress — Apple HID and physical PLAY-04 evidence remain open |  |
| 3.5 Mac Verification Automation | 10/10 | Executed — verification stale pending reviewed exact-head hosted evidence |  |
| 4. Persistent Save Continuity | 25/25 | Complete | 2026-09-08 |
| 4.5 Mac Pairing Ceremony | 6/6 | Complete |  |
| 4.6 Game Boy and Game Boy Color play and persistent saves | 4/4 | Complete    | 2026-10-12 |
| 5. Recovery and Release Proof | 12/14 | In Progress — no runnable plans until 05-05's retained-restore and named-observation gate |  |
| 5.1 Digest-bound Supply-chain Verification | 1/1 | Complete    | 2026-10-10 |
| 6. Recovery Proof CI and E2E Pipeline | 21/21 | In Progress — verification gaps; 38/42 UAT checks pass, four blocked |  |

## Backlog

### Phase 999.1: Live owner-console updates and native recovery UX (BACKLOG)

**Goal:** Make the owner-facing web console dynamic with Phoenix LiveView while preserving the API/change-journal boundary for native clients; remove avoidable manual refresh, retry, and copyability friction from pairing and recovery.
**Requirements:** TBD
**Plans:** 5 plans

Plans:

- [ ] TBD (promote with $gsd-review-backlog when ready)
