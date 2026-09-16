---
phase: 03-mac-offline-play-vertical-slice
verified: 2026-09-16T16:20:00Z
status: human_needed
score: 5/5 roadmap truths verified or appropriately routed (SC5's controller-hardware portion present+wired, not behaviorally exercised — unchanged, routed to human verification); WR-07 client-side ordering CLOSED; WR-08 CLOSED; WINDOWS #89 CLOSED and independently falsified; WINDOWS #90 advisory CLOSED; two architectural residues remain
behavior_unverified: 1
overrides_applied: 0
covered_files:
  - ".planning/REQUIREMENTS.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-01-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-01-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-02-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-02-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-03-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-03-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-04-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-04-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-05-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-05-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-06-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-06-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-07-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-07-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-08-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-08-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-09-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-09-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-10-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-10-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-11-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-11-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-12-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-12-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-13-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-13-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-14-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-14-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-15-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-15-SUMMARY.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-16-PLAN.md"
  - ".planning/phases/03-mac-offline-play-vertical-slice/03-16-SUMMARY.md"
  - "playstead-mac/Playstead/App/PlaysteadApp.swift"
  - "playstead-mac/Playstead/Cache/AvailabilityReporter.swift"
  - "playstead-mac/Playstead/Persistence/LocalStore.swift"
  - "playstead-mac/Playstead/Persistence/Migrations.swift"
  - "playstead-mac/Playstead/Sync/Outbox.swift"
  - "playstead-mac/Playstead/Sync/OutboxWorker.swift"
  - "playstead-mac/PlaysteadTests/CurationTests/OutboxTests.swift"
  - "playstead-mac/PlaysteadTests/SyncTests/OutboxStrandedInFlightTests.swift"
  - "playstead-mac/PlaysteadTests/SyncTests/OutboxWatermarkMigrationTests.swift"
  - "playstead-mac/scripts/ci/run-mac-verification.sh"
  - "playstead-mac/scripts/ci/tests/migration-column-declaration-detector.py"
  - "playstead-mac/scripts/ci/tests/migration-column-declaration-test.sh"
  - "playstead-server/lib/playstead/availability.ex"
  - "playstead-server/lib/playstead_web/controllers/api/v1/availability_controller.ex"
covered_digest: "v1:sha256:d42298c2b685dadb4cb5986e06205abe9dca517f8520a71ae111578de1bc15bc"
re_verification:
  previous_status: "human_needed (WR-07 architectural residues; WINDOWS #90 advisory open; coincidental_reliance entry asserting the cross-restart watermark path was latent)"
  previous_score: "5/5 roadmap truths; WR-07 partial"
  gaps_closed:
    - "WINDOWS #89 (a row left `in_flight` at quit was stranded permanently) CLOSED at f2f1cd3, and with it the PREMISE OF THE PRIOR ROUND'S `coincidental_reliance_items` ENTRY. That entry asserted the cross-restart watermark path was unreachable because `Nothing reverts an in_flight row at startup: there is no recovery sweep`. f2f1cd3 added exactly that sweep. Re-derived against HEAD rather than accepted from the commit message: `recoverStrandedInFlight` (Outbox.swift:246) selects `state = 'in_flight'` and routes each row through `markPendingForRetry` (Outbox.swift:318), which runs the WR-07 supersede check FIRST (`if entry.kind.supersedesPending, isSupersededForRetry(entry)` at :340, deleting rather than reviving), then advances the attempt counter (:347) and quarantines at `maxAttempts` (:348). The call site is `AppEnvironment`'s single private designated init (PlaysteadApp.swift:525-550), which every public and UITesting initializer funnels through, and it runs BEFORE `OutboxWorker` is even constructed, so no drain trigger can race it. The cross-restart case is therefore GENUINELY REACHABLE in production, and the prior entry's `currently unexercised`/`latent`/`future-proofing, not dead code` framing is now FALSE. The entry is retired, not re-dated."
    - "WINDOWS #90 / the `save_revision.restored_here_at` ADVISORY is CLOSED. `restored_here_at TEXT` is now declared in `save_revision`'s own CREATE TABLE block (Migrations.swift:458) with the defensive `try? ALTER` deliberately KEPT and its comment rewritten to say why it must not be deleted. The generalised guard is real, wired, and fails closed — verified by execution, not by reading its header: `playstead-mac/scripts/ci/tests/migration-column-declaration-test.sh` is mode 100755 in the index, is picked up by `run_contract_self_tests`'s `for test_script in \"${SCRIPT_DIR}\"/tests/*.sh` glob (run-mac-verification.sh:1746-1753, each invocation guarded by `|| failed=1` and terminated by `die`, so a 126/127 exit cannot read as clean), and that gate is invoked from .github/workflows/ci.yml:123 as `--self-test-contracts`. Ran it at HEAD: exit 0, `verified 12 ALTER-added columns are each also declared in their CREATE TABLE block`, plus three fail-closed self-tests. INDEPENDENTLY FALSIFIED: ran the detector against 7317752's pre-fix Migrations.swift copied into a temp dir (never `git checkout`), and it exits 1 naming `undeclared=save_revision.restored_here_at`."
  gaps_remaining:
    - "WR-07 residues 2 and 3 (architectural, unchanged across all five rounds): a late-succeeding in-flight request lands after a newer one and cannot be prevented client-side; and a newer row retired by `markRejected` or quarantine is invisible to both supersede checks. Re-confirmed at HEAD by direct read, not carried forward on trust: `Availability.replace_for_device/2` (playstead-server/lib/playstead/availability.ex:56) is still a blind `Ecto.Multi.delete_all` followed by inserts, with no report sequence or monotonic guard anywhere; and `hasNewerLiveEntry` (Outbox.swift:387) still scopes to `state IN ('pending', 'in_flight')`, so `rejected` and `quarantined` rows remain invisible to both checks."
  regressions: []
  evidence_discrepancies:
    - "f2f1cd3's message claims: `This makes WR-07's cross-restart case reachable for the first time, and it passes only because the watermark migration's drop stays CONDITIONAL.` The first clause is TRUE. The second is FALSE as a statement about the test suite, and I proved it by mutation rather than by argument. `OutboxStrandedInFlightTests` builds its `relaunchedOutbox()` as a second `Outbox` over the SAME `LocalStore` instance, so it never reopens the store and migrations never re-run. With the drop made unconditional, all 6 `OutboxStrandedInFlightTests` STAY GREEN; only `OutboxWatermarkMigrationTests/test_theWatermarkSurvivesAnOrdinaryRelaunch` goes red. The coupling the message describes is real IN PRODUCTION but is not what any of the six new tests actually pin. See `coincidental_reliance_items` — the regression is still caught, but by a different test for a different reason than the author believes."
    - "f2f1cd3's message claims the bare-UPDATE mutant `fails exactly the 2 that carry the design choice and passes the other 4`. CONFIRMED by re-running it: replacing `try markPendingForRetry(entry, at: now)` with a bare `UPDATE outbox_entries SET state = 'pending'` turns exactly `test_aRowThatStrandsEveryLaunchEventuallyQuarantinesRatherThanReplayingForever` and `test_aStrandedReportIsDroppedRatherThanRevivedBehindANewerDeliveredOne` red (5 assertion failures across those 2 cases) while the other 4 pass. This is the evidence that the supersede check and the quarantine bound genuinely run on the recovered row; the routing through `markPendingForRetry` is load-bearing, not decorative. Source restored byte-exact (sha1 c9d7e4d8dd2c2cf5aed21cf61a9a72ded8accb08) and `git status` re-checked clean."
coincidental_reliance_items:
  - truth: "A report left `in_flight` at quit is dropped rather than revived behind a newer delivered one, across a real relaunch."
    reason: fixture-only
    detail: "The behaviour HOLDS at HEAD — I verified it directly rather than inferring it — but no shipped test exercises the composed path, and the coupling f2f1cd3's own comment relies on is pinned by a different test than its author believes. A real relaunch REOPENS `LocalStore`, which re-runs `Migrations.run`, and only then sweeps. `OutboxStrandedInFlightTests` simulates the relaunch with a second `Outbox` over the same live `LocalStore`, so migrations never re-run in any of its six tests; `OutboxWatermarkMigrationTests` reopens the store but contains no stranded row and never calls the sweep. Each half is covered; the seam between them is not. I built the composed probe the suite lacks (session 1: enqueue stale report, `markInFlight`, enqueue newer, `markDone`; session 2: NEW `LocalStore` at the same `AppPaths`, then `recoverStrandedInFlight`) and it PASSES at HEAD — so the composition is sound today. Falsified to confirm the probe is not vacuous: with the watermark drop made unconditional it fails with 2 assertion failures, whereas all six shipped stranded-in-flight tests stay green under that same mutant. The probe was deleted and the tree re-checked clean. NOT A DEFECT: an unconditional-drop regression IS still caught, by `test_theWatermarkSurvivesAnOrdinaryRelaunch`. The exposure is narrower — a change to the sweep's POSITION relative to store construction, or to the composition of the two mechanisms, would be caught by nothing."
    harden: "Add the composed cross-restart test to `OutboxStrandedInFlightTests` — one scenario that reopens `LocalStore` at the same `AppPaths` between the two sessions instead of reusing the instance — so the coupling f2f1cd3's comment names is pinned by the test that actually models it. Also correct that file's class doc, which states a relaunch is `only the database survives`; a relaunch also re-runs migrations, which is precisely the part it does not model."
overrides: []
gaps:
  - truth: "03-16-PLAN.md must-have: \"Only the newest full-replacement availability report is ever delivered: enqueuing a new one removes any still-pending or backed-off one, so a backed-off earlier report can no longer land after a later one that already succeeded.\""
    status: partial
    reason: "The client-side ordering question is settled, the migration carrying it is correct, and the startup strand that made the cross-restart half unreachable is now closed. TWO residues remain, both architectural, neither introduced by any fix in this lineage and neither closable in `Outbox`. (2) A LATE-SUCCEEDING IN-FLIGHT REQUEST: if A is on the wire, B is delivered meanwhile, and A's request then SUCCEEDS, `markDone(A)` correctly leaves the watermark at B and deletes the row — but A has already landed on the server AFTER B. No client-side guard can prevent this; A was sent before B existed. Only a server-side monotonic guard closes it, and `replace_for_device/2` still has none (re-read at HEAD: blind `delete_all` + inserts). (3) A NEWER ROW RETIRED WITHOUT BEING DELIVERED: `markRejected` moves a row to `rejected` and exhausting `maxAttempts` moves it to `quarantined`; neither state is live for `hasNewerLiveEntry` and neither writes a watermark — correctly, since neither is a delivery. So an older row can be revived and delivered while a newer one sits rejected or quarantined. Reachability very low. NEW THIS ROUND, and it refines rather than widens residue 2: the startup sweep deliberately REPLAYS a request that may already have been applied server-side. That is sound because the row's `idempotency_key` is `kind:entryID`, generated once in `enqueue` and persisted, so it is byte-identical across restarts (pinned by `test_aRecoveredRowKeepsTheIdempotencyKeyTheServerWillDedupeOn`), and `PUT /devices/me/availability` is on the `:idempotency` pipeline (router.ex:181-183), which holds a per-device receipt. The acknowledged gap is that receipts prune at ~90 days, after which a replay genuinely re-executes — bounded only by the sweep running at the next launch, and documented in the method's own comment rather than hidden. Disposition unchanged across all five rounds: narrow, self-correcting on the next successful `syncNow()` pass, no permanent data corruption, no trust boundary crossed, no roadmap truth contradicted — a tracked, NON-BLOCKING warning."
    artifacts:
      - path: "playstead-server/lib/playstead/availability.ex"
        issue: "`replace_for_device/2` (line 56) is a blind full replacement — `Ecto.Multi.delete_all` then per-entry inserts — with no report ordering or monotonic guard, so nothing server-side rejects a stale report the client could not prevent sending."
    missing:
      - "A server-side monotonic guard on `PUT /api/v1/devices/me/availability` (ignore a report older than the last accepted one for that device). This is the only place residue 2 can be closed at all."
      - "If residues 2 and 3 are instead accepted as permanent limitations, record them in .planning/WINDOWS.md — they are currently described only inside code comments covering the closed halves."
advisory:
  - finding: "The composed cross-restart path (reopen `LocalStore` -> migrations re-run -> startup sweep -> supersede by watermark) is exercised by no shipped test, and f2f1cd3's comment attributes the protection to a test that does not model it."
    category: architectural
    reason: "Behaviour verified sound at HEAD by a purpose-built probe that was falsified and then deleted; an unconditional-drop regression is still caught by `test_theWatermarkSurvivesAnOrdinaryRelaunch`. Recorded rather than gated. Resolved by the `harden` step in `coincidental_reliance_items`."
    evidence_status: "probe run green at HEAD; probe falsified red under an unconditional-drop mutant; tree restored clean"
  - finding: "WINDOWS #92 remains open and its failure mode is, by the ledger's own words, `currently indistinguishable from a real regression in the startup outbox sweep` — the sweep this round verified."
    category: other
    reason: "Phase 04 entry against a UI test (`CurationInteractionTests/testDragReorderSurvivesRelaunch`). dfcf029 landed caller-line forwarding so the next red run distinguishes drag-failed-to-land from reorder-failed-to-persist, but by construction that is only visible on a failure and has not yet been exercised. Correctly tracked as open; not a phase-03 gap, but the adjacency is worth naming because a genuine sweep regression could currently arrive wearing this flake's clothes."
    evidence_status: "read from the WINDOWS ledger JSON (status open); no phase-03 test failure observed at HEAD"
  - finding: "Hosted-evidence binding cannot presently be cited: the `verify hosted evidence` workflow fails with `complete evidence identity mismatch: head_sha` (run 35000960386), binding RUN_ID 34997782815 at head 8d7e842 while itself checked out at 24491a69."
    category: other
    reason: "Evidence-pipeline defect, not phase-03 code. CI itself is green at 8d7e842 (run 34997782815: mix precommit, docker compose cold start, and macOS 26 unit+rendering+UI+live server all success). Every result in this report was produced locally in this verifier's own process and does not depend on the hosted binding."
    evidence_status: "reported by the launching orchestrator; not independently re-run here"
behavior_unverified_items:
  - truth: "A user can connect, test, assign, remap, reset, and recover a controller (roadmap SC #5, controller-hardware portion)"
    test: "Connect a real, paired physical game controller; disconnect it mid-session; reconnect it."
    expected: "Connect is detected, disconnect shows the non-modal recovery banner without stranding keyboard/pointer input, and reconnect restores input without requiring a relaunch — matching what ControllerHost's unit tests already prove against an injectable ControllerInputSource."
    why_human: "No physical or paired controller hardware exists in this execution environment; 03-SPIKE-REPORT.md probe 5 recorded this as FAIL/unproven and 03-10-SUMMARY.md's D1 rationale states the same. Code is present and wired; only real-hardware behavior is unexercised. Regression-checked at HEAD: f2f1cd3 touches only Outbox/Migrations/PlaysteadApp's outbox sweep and does not reach any controller surface."
human_verification:
  - test: "Physical game controller connect/disconnect/reconnect recovery, live input test, remap, and reset on real hardware"
    expected: "Controller lifecycle logic behaves identically against a real device as it does against the injectable simulated input source in unit tests."
    why_human: "No physical or paired controller hardware exists in this execution environment. Reconciled against 03-UAT.md items 8 and 9 (both blocked_by: physical-device) and item 10's blocked sub-record. Carried forward unchanged; `check-uat-tally.sh` re-run at HEAD reports total=49 pass=45 blocked=2 partial=2."
  - test: "Full end-to-end launch of the pinned mGBA adapter against a live paired server, with a downloaded game and installed emulator, from the notarized build, driven by a live interactive display session"
    expected: "Play starts the emulator, the game runs, SRAM periodically flushes, quitting returns to the library, and Gatekeeper accepts the app without any user override (this last part is proven — see 03-NOTARIZATION-EVIDENCE.md)."
    why_human: "This execution environment cannot render a live interactive display session for a human to watch a game actually run. Reconciled against 03-UAT.md item 7. Carried forward unchanged."
  - test: "Visual/typographic fidelity and VoiceOver walkthrough of the LiveView console and the Mac library shell against 03-UI-SPEC.md"
    expected: "Spacing, color rendering, motion timing, and screen-reader sentence flow match the locked design contract on both surfaces."
    why_human: "Only the markup-level/logic-level accessibility contract was automatically verified; no live NSAccessibility tree or interactive rendering was exercised. Reconciled against 03-UAT.md item 10's blocked sub-record. Carried forward unchanged."
  - test: "Drag-in BIOS validation against a real, legally-sourced BIOS file or supported open replacement"
    expected: "A correct BIOS file is accepted and stored under managed storage; an incorrect one is rejected with a clear reason."
    why_human: "No real BIOS file exists in this execution environment, and none should. Reconciled against 03-UAT.md item 13 (result: partial, blocked_by: legally-owned-artifact-required). Carried forward unchanged."
  - test: "LIBR-05's remaining human-judgment UX review item and PLAY-04's physical controller hardware requirement"
    expected: "N/A — tracked for completeness; both requirement IDs stay Pending in REQUIREMENTS.md by explicit scope fence."
    why_human: "PLAY-04 is the same hardware-blocked item above; LIBR-05's remaining scope is a human UX judgment call. Re-confirmed both still `Pending` at REQUIREMENTS.md lines 137 and 145."
---

# Phase 3: Mac Offline Play Vertical Slice Verification Report

**Phase Goal:** A newly paired Mac can browse a curated server library, download only chosen verified content, and launch one deliberately supported game offline through a tested adapter.
**Verified:** 2026-09-16T16:20:00Z (HEAD `f4d83ed`; the orchestrator named `8d7e842`, which is one commit behind — `f4d83ed` adds only 03-UAT.md)
**Status:** human_needed
**Re-verification:** Yes — round 5, re-derived rather than re-dated. The round-4 report was written at `7317752`; `f2f1cd3` landed nineteen minutes later and modified three of that report's own `covered_files`.

## Verdict: the stale entry was not merely stale — it asserted the opposite of HEAD

Round 4 recorded a `coincidental_reliance_items` entry whose whole argument was one grep: *"Nothing reverts an `in_flight` row at startup: there is no recovery sweep."* `f2f1cd3` added that sweep. So the entry's conclusions — "currently unexercised in production", "latent", "future-proofing, not dead code" — are all false at HEAD. It is retired, and replaced by a different finding that is true.

### Priority 1 — the cross-restart path is genuinely reachable now

Traced in code, not taken from the commit message:

| Link | Evidence at HEAD |
|---|---|
| Sweep exists and selects the stranded state | `recoverStrandedInFlight` (Outbox.swift:246) → `rows(where: "state = 'in_flight'", …)` |
| It routes through `markPendingForRetry`, not a bare UPDATE | Outbox.swift:249, calling :318 |
| The WR-07 supersede check really runs on the recovered row | `markPendingForRetry` :340 — `if entry.kind.supersedesPending, isSupersededForRetry(entry)` **deletes** rather than revives, and it is the FIRST thing in the method |
| The attempt counter advances and quarantine bounds the replay | :347 `attemptCount + 1`; :348 `>= Self.maxAttempts` → `state = 'quarantined'`, `next_retry_at = NULL` |
| It is on the production path | `AppEnvironment`'s single private designated init, PlaysteadApp.swift:525-550 — every public and `#if` UITesting initializer funnels here |
| Nothing can drain before it | The sweep is at :538; `OutboxWorker` is not constructed until :560 |

**Falsified, not asserted.** Replacing `try markPendingForRetry(entry, at: now)` with a bare `UPDATE outbox_entries SET state = 'pending'` turns exactly two tests red — `test_aRowThatStrandsEveryLaunchEventuallyQuarantinesRatherThanReplayingForever` and `test_aStrandedReportIsDroppedRatherThanRevivedBehindANewerDeliveredOne` (5 assertion failures across those 2 cases) — while the other 4 stay green. That is the proof that the supersede check and the quarantine bound genuinely execute on a recovered row. Source restored byte-exact (sha1 `c9d7e4d8…`), tree re-checked clean.

### What the commit message gets wrong

> "This makes WR-07's cross-restart case reachable for the first time, and it passes only because the watermark migration's drop stays CONDITIONAL."

First clause true. **Second clause false about the test suite.** `OutboxStrandedInFlightTests` builds its `relaunchedOutbox()` as a second `Outbox` over the *same live* `LocalStore`, so migrations never re-run in any of its six tests. Under an unconditional drop, **all six stay green**; only `test_theWatermarkSurvivesAnOrdinaryRelaunch` goes red — and that test contains no stranded row and never calls the sweep.

So each half is covered and the seam is not. I built the composed probe the suite lacks (session 1: enqueue stale report → `markInFlight` → enqueue newer → `markDone`; session 2: a **new** `LocalStore` at the same `AppPaths`, then sweep). It **passes at HEAD** — the composition is sound. Falsified to prove it is not vacuous: under the unconditional-drop mutant it fails with 2 assertion failures, where all six shipped tests pass. Probe deleted; tree clean. This is not a defect — the regression is still caught, just by a different test for a different reason than the author believes — so it is recorded as advisory with a one-line hardening step.

### Priority 2 — the two WR-07 residues, re-read at HEAD

Both still open, both unchanged, neither carried forward on trust:

- **Residue 2** — `Availability.replace_for_device/2` (availability.ex:56) is still `Ecto.Multi.delete_all` followed by per-entry inserts. No report sequence, no monotonic guard, nothing that could reject a stale report.
- **Residue 3** — `hasNewerLiveEntry` (Outbox.swift:387) still scopes to `state IN ('pending', 'in_flight')`, so `rejected` and `quarantined` rows are invisible to both supersede checks.

**The quarantine bound the commit claims does hold** — proven by the mutant above, not by the message.

**One refinement, new this round.** The sweep deliberately replays a request that may already have been applied. That is sound: the key is `kind:entryID`, generated once in `enqueue` and persisted (pinned by `test_aRecoveredRowKeepsTheIdempotencyKeyTheServerWillDedupeOn`), and `PUT /devices/me/availability` is on the `:idempotency` pipeline (router.ex:181-183). The ~90-day receipt-prune window is a real residual, acknowledged in the method's own comment rather than hidden, and bounded by the sweep running next launch.

### Priority 3 — WINDOWS #90 / the `restored_here_at` advisory is CLOSED

`restored_here_at TEXT` is now in `save_revision`'s CREATE TABLE (Migrations.swift:458), with the `try? ALTER` kept and its comment rewritten to forbid deletion. The guard is real and **wired**, verified by execution rather than by reading its header:

- mode `100755` **in the git index**, so it cannot fail to execute on a fresh clone;
- discovered by `run_contract_self_tests`'s `for test_script in "${SCRIPT_DIR}"/tests/*.sh` glob (run-mac-verification.sh:1746-1753) — a glob, not a hand-kept list, so registration needed no action;
- **fails closed**: each invocation is `|| failed=1` and the function ends in `die`, so a 126/127 exit from a missing or non-executable script cannot read as clean;
- invoked in CI at `.github/workflows/ci.yml:123` (`--self-test-contracts`).

Ran at HEAD: exit 0, `verified 12 ALTER-added columns are each also declared in their CREATE TABLE block`, plus three fail-closed self-tests (ALTER-only column, no-ALTER source, missing file). **Independently falsified** against `7317752`'s pre-fix source copied to a temp dir — exits 1 naming `undeclared=save_revision.restored_here_at`.

### Priority 4 — regression surface

Only eleven files changed since the round-4 report, three of them shipped Mac source:

`PlaysteadApp.swift`, `Migrations.swift`, `Outbox.swift` (all re-verified above), plus `OutboxStrandedInFlightTests.swift` (new), `CurationInteractionTests.swift` (#92 diagnostics), `sanitize-evidence.sh` + `sanitizer-test.sh` (#91), the two new migration-guard files, `WINDOWS.md`, and `03-UAT.md`.

`AvailabilityReporter.swift`, `LocalStore.swift`, `OutboxWorker.swift` and `availability_controller.ex` are **untouched** since round 4, so LIBR-02, WR-04 and the live-row check carry forward on a bounded surface. WR-05 lives in `Outbox.swift`, which did change, so it was re-read directly: the enqueue-time `DELETE FROM outbox_entries WHERE kind = ? AND state = 'pending'` is intact inside the insert transaction (Outbox.swift:129-134), and all four supersede tests pass in the 25/25 run.

## Goal Achievement

### Observable Truths (Roadmap Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Browse the complete server catalogue before downloading bytes; find content; curate Favorites/Collections/Continue/Recent/queue; LiveView console offers the same views | ✓ VERIFIED | Unchanged; supporting files untouched since round 4. |
| 2 | Choose a game/collection for download, resume verified ranges after interruption, distinguish six availability states | ✓ VERIFIED | Unchanged; `AvailabilityState.derive` untouched by `f2f1cd3`. |
| 3 | Set capacity policy, pin content, reclaim only reconstructable unpinned bytes; launch only after every required member verifies locally; remains launchable offline | ✓ VERIFIED | Unchanged. |
| 4 | Select/install one supported Mac adapter with exact capability info; validate locally supplied BIOS or open replacement; preflight remedy per blocker | ✓ VERIFIED | Unchanged. |
| 5 | Connect/test/assign/remap/reset/recover a controller with keyboard/pointer/screen-reader/focus/reduced-motion fallbacks; launch/exit/relaunch from a signed/notarized build after app or server restart | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED (controller-hardware portion) / ✓ VERIFIED (notarization portion) | Unchanged; routed to human verification. `f2f1cd3` reaches no controller surface. |

**Score:** 5/5 roadmap truths verified or appropriately routed; 1 present-but-behavior-unverified. WR-07 is a sub-requirement-level must-have from 03-16-PLAN.md, not a roadmap SC, and is tracked in `gaps`.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `playstead-mac/Playstead/Sync/Outbox.swift` | Newest-wins supersede across the full entry lifecycle, including after a restart | ⚠️ PARTIAL | Enqueue-time, live-newer, delivered-newer and now cross-restart cases implemented, atomic and tested on a total order. Only residues 2/3 remain, both architectural and outside `Outbox`. |
| `playstead-mac/Playstead/App/PlaysteadApp.swift` | The sweep on the one path that runs once before any drain | ✓ VERIFIED | Designated init :525-550; before `OutboxWorker` construction at :560; error logged, not swallowed (`do`/`catch`, not `try?`). |
| `playstead-mac/Playstead/Persistence/Migrations.swift` | Durable delivered-fact store upgradable from every prior shape; every ALTER redundant on a fresh DB | ✓ VERIFIED | Legacy-column-gated DROP intact and still load-bearing (unconditional mutant → `test_theWatermarkSurvivesAnOrdinaryRelaunch` red). `restored_here_at` now in its CREATE block. |
| `playstead-mac/PlaysteadTests/SyncTests/OutboxStrandedInFlightTests.swift` | Fail-first coverage of the startup sweep | ✓ VERIFIED (with a seam) | 6/6 at HEAD; bare-UPDATE mutant reds exactly the 2 design-carrying tests. Does not model the migration re-run — see advisory. |
| `playstead-mac/PlaysteadTests/CurationTests/OutboxTests.swift` | Fail-first coverage of all WR-07 rounds | ✓ VERIFIED | 25/25 at HEAD. |
| `playstead-mac/PlaysteadTests/SyncTests/OutboxWatermarkMigrationTests.swift` | Coverage of the schema-upgrade path no other suite reaches | ✓ VERIFIED | 3/3 at HEAD. |
| `playstead-mac/scripts/ci/tests/migration-column-declaration-test.sh` | A wired, fail-closed generalisation of #90 | ✓ VERIFIED, WIRED | Glob-discovered, `|| failed=1` + `die`, ci.yml:123. Exit 0 at HEAD; exit 1 on pre-fix source. |
| `playstead-server/lib/playstead/availability.ex` | A server-side monotonic guard (residue 2) | ✗ ABSENT | Blind `delete_all` + inserts. Tracked in `gaps`, non-blocking. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Startup sweep, replay-key stability, quarantine bound, cross-restart supersede | `xcodebuild test … -only-testing:PlaysteadTests/OutboxStrandedInFlightTests` | Executed 6, 0 failures | ✓ PASS |
| WR-07 client-side ordering across the lifecycle | `… -only-testing:PlaysteadTests/OutboxTests` | Executed 25, 0 failures | ✓ PASS |
| Watermark schema-upgrade path | `… -only-testing:PlaysteadTests/OutboxWatermarkMigrationTests` | Executed 3, 0 failures | ✓ PASS |
| Every ALTER-added column declared in its CREATE block | `bash playstead-mac/scripts/ci/tests/migration-column-declaration-test.sh` | exit 0; 12 columns; 3 fail-closed self-tests | ✓ PASS |
| Guard actually catches #90 | detector vs `7317752:Migrations.swift` in a temp dir | exit 1, `undeclared=save_revision.restored_here_at` | ✓ PASS (falsified) |
| Sweep routing is load-bearing | bare-UPDATE mutant on `recoverStrandedInFlight` | exactly 2 of 6 red | ✓ PASS (falsified) |
| Conditional drop is load-bearing | unconditional-drop mutant | `test_theWatermarkSurvivesAnOrdinaryRelaunch` red; all 6 stranded tests green | ✓ PASS (falsified, and disconfirms the commit message) |
| Composed cross-restart path | purpose-built probe, then deleted | green at HEAD; red under unconditional-drop mutant | ✓ PASS (probe, not shipped) |
| UAT tally reconciliation | `bash scripts/check-uat-tally.sh` | `03-UAT.md: total=49 blocked=2, partial=2, pass=45` | ✓ PASS |
| UAT/roadmap evidence boundaries | `validate-phase-3-uat-evidence.py` | `phase-3 UAT and Roadmap evidence boundaries verified` | ✓ PASS |

All 34 Outbox-family tests were confirmed **discovered, executed, non-skipped and passing** by name. `TestPlans/Unit.xctestplan` has no `selectedTests` allowlist and its 3 `skippedTests` include no Outbox entry; the project uses `PBXFileSystemSynchronizedRootGroup`, so the new test file is auto-included rather than needing pbxproj registration.

### Requirements Coverage

All 15 phase-03 IDs are claimed by plan frontmatter; **no orphans** (the union across the 16 plans is exactly the phase's declared set).

| Requirement | Source Plans | Status | Evidence |
|---|---|---|---|
| LIBR-01 | 03-03, 03-06 | ✓ SATISFIED | REQUIREMENTS.md:133 Complete |
| LIBR-02 | 03-05, 03-06, 03-13, 03-14, 03-15, 03-16 | ✓ SATISFIED | REQUIREMENTS.md:134 Complete |
| LIBR-03 | 03-04, 03-08 | ✓ SATISFIED | REQUIREMENTS.md:135 Complete |
| LIBR-04 | 03-05, 03-06 | ✓ SATISFIED | REQUIREMENTS.md:136 Complete |
| LIBR-05 | 03-05 | ? NEEDS HUMAN | REQUIREMENTS.md:137 Pending — human UX judgment, by explicit scope fence |
| CACH-01 | 03-02, 03-03, 03-07 | ✓ SATISFIED | REQUIREMENTS.md:138 Complete |
| CACH-02 | 03-07 | ✓ SATISFIED | REQUIREMENTS.md:139 Complete |
| CACH-03 | 03-07 | ✓ SATISFIED | REQUIREMENTS.md:140 Complete |
| CACH-04 | 03-03, 03-09 | ✓ SATISFIED | REQUIREMENTS.md:141 Complete |
| PLAY-01 | 03-01, 03-09 | ✓ SATISFIED | REQUIREMENTS.md:142 Complete |
| PLAY-02 | 03-09 | ✓ SATISFIED | REQUIREMENTS.md:143 Complete |
| PLAY-03 | 03-09, 03-11 | ✓ SATISFIED | REQUIREMENTS.md:144 Complete |
| PLAY-04 | 03-10 | ? NEEDS HUMAN | REQUIREMENTS.md:145 Pending — physical controller hardware |
| PLAY-05 | 03-01, 03-03, 03-10, 03-12 | ✓ SATISFIED | REQUIREMENTS.md:146 Complete |
| QUAL-01 | 03-05, 03-10, 03-13, 03-14 | ✓ SATISFIED | REQUIREMENTS.md:155 Complete |

### Anti-Patterns Found

None blocking. No unreferenced `TBD`/`FIXME`/`XXX` in any file modified since round 4. The `try?` ALTERs in `Migrations.swift` are now all genuinely redundant and guarded by a CI gate that fails closed.

### Human Verification Required

Four items, all reconciled against `03-UAT.md` (total=49, pass=45, blocked=2, partial=2, re-verified by `check-uat-tally.sh` at HEAD) and **carried forward unchanged** — nothing at HEAD closed or reopened any of them. See `human_verification` in the frontmatter.

### Gaps Summary

One non-blocking gap, unchanged in substance across five rounds: WR-07's residues 2 and 3 are architectural. Residue 2 is closable only by a server-side monotonic guard on `PUT /api/v1/devices/me/availability`, which `replace_for_device/2` still lacks; residue 3 is a very-low-reachability consequence of `rejected`/`quarantined` correctly not counting as deliveries. Neither contradicts a roadmap truth, neither corrupts data, and both self-correct on the next successful `syncNow()`.

Everything the orchestrator flagged as stale has been re-derived: the `coincidental_reliance_items` entry is retired because its premise is false at HEAD, WINDOWS #89 and #90 are closed and independently falsified, the two residues are re-read rather than carried, and `covered_files`/`covered_digest` are recomputed.

---

_Verified: 2026-09-16T16:20:00Z_
_Verifier: Claude (gsd-verifier), round 5_
