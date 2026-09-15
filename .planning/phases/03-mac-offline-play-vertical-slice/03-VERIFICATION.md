---
phase: 03-mac-offline-play-vertical-slice
verified: 2026-09-15T17:00:00Z
status: human_needed
score: 5/5 roadmap truths verified (SC5's controller-hardware portion present+wired, not behaviorally exercised — unchanged, routed to human verification); WR-07 client-side ordering CLOSED; WR-08 CLOSED; two architectural residues remain
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
  - "playstead-mac/Playstead/Persistence/Migrations.swift"
  - "playstead-mac/Playstead/Sync/Outbox.swift"
  - "playstead-mac/Playstead/Sync/OutboxWorker.swift"
  - "playstead-mac/Playstead/Persistence/LocalStore.swift"
  - "playstead-mac/PlaysteadTests/CurationTests/OutboxTests.swift"
  - "playstead-mac/PlaysteadTests/SyncTests/OutboxWatermarkMigrationTests.swift"
  - "playstead-server/lib/playstead_web/controllers/api/v1/availability_controller.ex"
covered_digest: "v1:sha256:03c2526bd9889d23f232e8f6cb8819205da714dd4f0ac1ce1c6e9a845b4bc8ff"
re_verification:
  previous_status: "human_needed (two gaps: WR-07 architectural residues, WR-08 migration defect)"
  previous_score: "5/5 roadmap truths; WR-07 partial, WR-08 failed"
  gaps_closed:
    - "WR-08 (the watermark upgrade left the table unwritable): CLOSED at 8d008b4. The broken `try? ALTER` is replaced by a DROP gated on `SELECT 1 FROM pragma_table_info('outbox_delivered_watermark') WHERE name = 'created_at'`. Detection verified complete in sqlite3 against all FOUR reachable schema states, not just the one named: table absent -> no drop, CREATE makes it; current schema -> no drop, watermark preserved; 47ac7b6 legacy `(kind, created_at)` -> drop; 711f866 half-migrated `(kind, created_at, delivered_seq)` -> drop. Falsified both directions: restoring the broken `try? ALTER` fails the two upgrade tests with exactly `NOT NULL constraint failed: outbox_delivered_watermark.created_at` while the 25 OutboxTests stay green; and making the drop UNCONDITIONAL (the instrument the author's own message described) fails `test_theWatermarkSurvivesAnOrdinaryRelaunch` at :96, so the conditional gate is load-bearing and not decorative. Restored byte-exact; 25/25 + 3/3 green at HEAD."
  gaps_remaining:
    - "WR-07 residues 2 and 3 (architectural, unchanged across all four rounds): a late-succeeding in-flight request lands after a newer one and cannot be prevented client-side; and a newer row retired by `markRejected` or quarantine is invisible to both supersede checks. Neither is closable in `Outbox` alone; residue 2 needs a server-side monotonic guard."
  regressions: []
  evidence_discrepancies:
    - "The author's message reports `OutboxWatermarkMigrationTests 2/2`. There are THREE tests in that file and all three pass. The third, `test_theWatermarkSurvivesAnOrdinaryRelaunch`, is the one that pins the conditional gate — the author's own stated worry — so the report understated the work rather than overstating it."
    - "The author's message describes the fix as `try connection.execute(\"DROP TABLE IF EXISTS outbox_delivered_watermark;\")` run unconditionally, and asks whether that is a cross-restart regression. The code at HEAD is NOT unconditional: it is gated on the legacy-column probe. The message is stale relative to the commit; the concern it raises is already guarded in the shipped code and pinned by a test."
  coincidental_reliance_items:
    - truth: "The watermark must survive an ordinary relaunch so a pre-restart delivery still supersedes afterwards."
      reason: undeclared-precondition
      detail: "Correct and correctly guarded, but currently unexercised in production for an unrelated reason. The scenario the comment and the relaunch test model — an older row still `in_flight` at quit reverting afterwards — requires `markPendingForRetry` to be called for that row in the next session. Nothing reverts an `in_flight` row at startup: there is no recovery sweep (grep confirms the only `in_flight` references outside Outbox.swift are a comment), and `listPending` excludes `in_flight`, so such a row is stranded rather than retried. The conditional drop is the right instrument and is future-proofing, not dead code — but its stated justification overstates present reachability, and the coupling runs the other way: whoever fixes the stranded-`in_flight` gap by adding the obvious startup sweep makes this path live, at which point an unconditional drop would silently reintroduce WR-07."
      harden: "Note in the migration comment that the cross-restart path is currently latent because `in_flight` rows are stranded at startup, so the coupling is visible to whoever adds a recovery sweep."
overrides: []
gaps:
  - truth: "03-16-PLAN.md must-have: \"Only the newest full-replacement availability report is ever delivered: enqueuing a new one removes any still-pending or backed-off one, so a backed-off earlier report can no longer land after a later one that already succeeded.\""
    status: partial
    reason: "The client-side ordering question is settled and the migration that carries it is now correct. TWO residues remain, both architectural, neither introduced by any of the four fixes and neither closable in `Outbox`. (2) A LATE-SUCCEEDING IN-FLIGHT REQUEST: if A is on the wire, B is delivered meanwhile, and A's request then SUCCEEDS, `markDone(A)` correctly leaves the watermark at B and deletes the row — but A has already landed on the server AFTER B. No client-side guard can prevent this; A was sent before B existed. Only a server-side monotonic guard closes it, and `Availability.replace_for_device/2` still has none (blind full replacement, re-confirmed by direct read). (3) A NEWER ROW RETIRED WITHOUT BEING DELIVERED: `markRejected` moves a row to `rejected` and exhausting `maxAttempts` moves it to `quarantined`; neither state is live for `hasNewerLiveEntry` and neither writes a watermark — correctly, since neither is a delivery. So an older row can be revived and delivered while a newer one sits rejected or quarantined. This does not violate the sentence's final clause (nothing newer succeeded) but does violate its leading clause. Reachability very low. Disposition unchanged across all four rounds: narrow, self-correcting on the next successful `syncNow()` pass, no permanent data corruption, no trust boundary crossed, no roadmap truth contradicted — a tracked, NON-BLOCKING warning. The client-side half of the sentence is now true; the leading clause cannot be made true in `Outbox` alone."
    artifacts:
      - path: "playstead-server/lib/playstead_web/controllers/api/v1/availability_controller.ex"
        issue: "`replace_for_device/2` is a blind full replacement with no report ordering/monotonic guard, so nothing server-side rejects a stale report the client could not prevent sending."
    missing:
      - "A server-side monotonic guard on `PUT /api/v1/devices/me/availability` (ignore a report older than the last accepted one for that device). This is the only place residue 2 can be closed at all."
      - "If residues 2 and 3 are instead accepted as permanent limitations, record them in .planning/WINDOWS.md — they are currently described only inside code comments covering the closed halves."
advisory:
  - finding: "`save_revision.restored_here_at` is the only column in the entire schema declared SOLELY by a `try? ALTER TABLE ... ADD COLUMN` and absent from its own `CREATE TABLE IF NOT EXISTS` block. Verified by extracting every CREATE block and every ALTER in Migrations.swift and diffing them: 11 of the 12 ALTER-added columns also appear in their table's CREATE; `restored_here_at` does not."
    category: architectural
    reason: "Not a live defect and NOT WR-08's failure mode (that was a reshape leaving a NOT NULL survivor). It works today only because the `try?` ALTER runs unconditionally on every `LocalStore` open, so even a fresh database acquires the column that way. The hazard is its asymmetry with every sibling: it is exactly the line a future cleanup deletes as redundant, after which a fresh database silently lacks a column `SaveStore` reads and writes in four places (SaveStore.swift:224, :248, :275, :305), with the error swallowed by `try?`. This is phase 04 code (save_revision, plans 04-06/04-11), so it is outside phase 03's scope and is recorded rather than gated. Answering the author's scoping question directly: NO other table carries WR-08's hazard — the watermark is the only table ever RESHAPED, and all 19 commits touching Migrations.swift made otherwise purely additive changes, each with a matching ALTER."
    evidence_status: "verified by schema extraction + git history scan; no runtime failure observed or claimed"

behavior_unverified_items:
  - truth: "A user can connect, test, assign, remap, reset, and recover a controller (roadmap SC #5, controller-hardware portion)"
    test: "Connect a real, paired physical game controller; disconnect it mid-session; reconnect it."
    expected: "Connect is detected, disconnect shows the non-modal recovery banner without stranding keyboard/pointer input, and reconnect restores input without requiring a relaunch — matching what ControllerHost's unit tests already prove against an injectable ControllerInputSource."
    why_human: "No physical or paired controller hardware exists in this execution environment; 03-SPIKE-REPORT.md probe 5 recorded this as FAIL/unproven and 03-10-SUMMARY.md's D1 rationale states the same. Code is present and wired; only real-hardware behavior is unexercised. Unchanged by 847165b/97b1358/47ac7b6, regression-checked."
human_verification:
  - test: "Physical game controller connect/disconnect/reconnect recovery, live input test, remap, and reset on real hardware"
    expected: "Controller lifecycle logic behaves identically against a real device as it does against the injectable simulated input source in unit tests."
    why_human: "No physical or paired controller hardware exists in this execution environment. Reconciled against 03-UAT.md items 8 and 9 (both blocked_by: physical-device) and item 10's blocked sub-record. Carried forward unchanged."
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
    why_human: "PLAY-04 is the same hardware-blocked item above; LIBR-05's remaining scope is a human UX judgment call. Confirmed both still `Pending` at REQUIREMENTS.md lines 137 and 145."
---

# Phase 3: Mac Offline Play Vertical Slice Verification Report

**Phase Goal:** Let a paired Mac browse, selectively cache, preflight, and launch one proven adapter path offline.
**Verified:** 2026-09-15T17:00:00Z (HEAD `8d008b4`)
**Status:** human_needed
**Re-verification:** Yes — fifth independent pass, adjudicating `8d008b4` (the watermark migration fix) for WR-08, after `711f866` (monotonic sequence), `47ac7b6` (delivered watermark) and `847165b` (live-row check) for WR-07. Everything outside these was re-checked and stands.

## Verdict: WR-08 is CLOSED; what remains of WR-07 is architectural

Round 4. You asked me to assume this round has something wrong with it too. This time the code is right — the thing that is wrong is your description of it.

### WR-08 is closed

The broken `try? ALTER` is gone, replaced by a DROP gated on a legacy-column probe. **Detection is complete across all four reachable schema states, not just the one named** — I checked each in sqlite3 rather than reasoning about them:

| Database state | `pragma_table_info … WHERE name='created_at'` | Behaviour |
|---|---|---|
| table absent | `[]` | no drop; `CREATE` makes it |
| current `(kind, delivered_seq)` | `[]` | **no drop — watermark preserved** |
| 47ac7b6 legacy `(kind, created_at)` | `[1]` | dropped and rebuilt |
| 711f866 half-migrated `(kind, created_at, delivered_seq)` | `[1]` | dropped and rebuilt |

That fourth row matters and was not in your list: a database that ran the *broken* build carries all three columns, and the probe catches it because it keys on the stale column rather than on the absence of the new one. Had it keyed on `delivered_seq` being missing, that state would have been missed.

**Falsified in both directions.** Restoring the broken `try? ALTER` fails the two upgrade tests with exactly `NOT NULL constraint failed: outbox_delivered_watermark.created_at`, while the 25 `OutboxTests` stay green — confirming your claim. And making the drop **unconditional**, which is what your message says you did, fails `test_theWatermarkSurvivesAnOrdinaryRelaunch` at :96. So the conditional gate is load-bearing, not decorative. 25/25 + 3/3 at HEAD, restored byte-exact.

### Two discrepancies between your message and your commit

**Your message describes an unconditional `DROP TABLE IF EXISTS` and asks whether it is a cross-restart regression. The code at HEAD is not unconditional** — it is gated on the legacy-column probe, with a comment that spells out precisely the failure mode you were worried about. The concern is already guarded and already pinned by a test. Your message is stale relative to your own commit; the code is the better of the two.

**You report `OutboxWatermarkMigrationTests 2/2`. There are three tests, and all three pass.** The third is the one that pins the conditional gate. You understated your own work rather than overstating it — but since you asked me to confirm evidence rather than accept it, the count is wrong.

### Your other three questions

**Is `DROP` safe in every state — does losing the watermark ever fail CLOSED?** No. Two readers, both safe. `isSupersededForRetry` does `guard let watermark = deliveredWatermark(...) else { return false }` — no watermark means *not superseded*, so the entry is retried. Fails open, as you claim. The second reader is the one your question did not mention: `enqueue`'s sequence subquery takes `COALESCE((SELECT MAX(delivered_seq) …), 0)`. A missing watermark makes that term 0, but the sibling term `MAX(enqueue_seq) FROM outbox_entries` independently guarantees the new sequence exceeds every live row, so a lost watermark can never produce a sequence that collides with, or sorts below, anything still present. No wrong-drop is reachable from the table's absence.

**Do the tests actually exercise the upgrade, or does `LocalStore` cache a connection?** They genuinely exercise it. `LocalStore.init` constructs a **new** `SQLiteConnection` per instance and calls `Migrations.run` immediately (LocalStore.swift:17-20); there is no cache, no shared handle, and no path keying. Reopening at the same `AppPaths` therefore re-runs migrations against the same file exactly as a relaunch does. The first instance stays alive holding its own connection, which SQLite handles fine. The `_ = hasLegacyWatermarkColumn` falsification above also proves the second open really does re-run the migration — otherwise neither falsification could have changed a result.

**Does anything else carry the same hazard?** No — and I checked rather than assumed. I extracted every `CREATE TABLE IF NOT EXISTS` block and every `ALTER … ADD COLUMN` from Migrations.swift and scanned all 19 commits that touched the file. The watermark is the only table ever **reshaped** (a column replaced); every other change across the file's history is purely additive, and each added column has both a `DEFAULT`-or-nullable declaration and a matching `ALTER`. WR-08's failure mode cannot recur elsewhere as the schema stands.

### One latent issue, its own entry as you asked

The scan did turn up an asymmetry, though it is the *mirror* of WR-08 rather than the same hazard. **`save_revision.restored_here_at` is the only column in the whole schema declared solely by a `try? ALTER` and absent from its own `CREATE TABLE` block** — 11 of the 12 ALTER-added columns also appear in their table's CREATE; this one does not.

It works today, because the `try?` ALTER runs unconditionally on every open, so even a fresh database acquires the column that way. The hazard is the asymmetry itself: it is exactly the line a future cleanup deletes as redundant, after which a fresh database silently lacks a column `SaveStore` reads and writes in four places (SaveStore.swift:224, :248, :275, :305) — with the failure swallowed by the `try?`. It is phase 04 code, so it is outside this phase's scope and is recorded as advisory rather than gated.

### A coincidental reliance worth naming before someone trips on it

The conditional drop is the right instrument and I am not arguing against it. But the scenario its comment and its test model — *"an older row still `in_flight` at quit could revert afterwards and deliver stale facts"* — **cannot currently happen in production**, for a reason unrelated to this change. Nothing reverts an `in_flight` row at startup: there is no recovery sweep (grep confirms the only `in_flight` mention outside `Outbox.swift` is a comment), and `listPending` excludes `in_flight`, so a row in flight at quit is *stranded* — never retried, never superseded. `markPendingForRetry` is therefore never called for it in the next session, and the watermark's cross-restart value goes unexercised.

So the protection is latent rather than active. That is fine — it is future-proofing, not dead code — but the coupling runs in a direction worth writing down: **whoever fixes the stranded-`in_flight` gap by adding the obvious startup sweep makes this path live.** At that moment the conditional gate is what prevents WR-07 from silently returning. Recorded in `coincidental_reliance_items` so the two changes are not made independently.

### What remains of WR-07

Residues 2 and 3, unchanged and architectural: a late-succeeding in-flight request lands after a newer one (closable only by a server-side monotonic guard, which `replace_for_device/2` still lacks), and a newer row retired by rejection or quarantine is invisible to both checks. Disposition unchanged across all four rounds — tracked, non-blocking.

### A note on the compromised local evidence

I did not run the full Unit layer, so WINDOWS #88's five child-process failures did not arise and nothing here depends on them. Every result cited comes from `OutboxTests` and `OutboxWatermarkMigrationTests` (neither spawns a child process), from sqlite3 run directly against the migration statements, or from source reads.

## Regression Re-checks (by source read, not by reading the prior verification)

| Prior finding | Status | Evidence re-derived |
|---|---|---|
| **LIBR-02** (`missing_dependency` structurally unreachable) | ✓ STILL CLOSED | `AvailabilityReporter.buildEntries` computes `missingDependency = !requiredSHAs.isEmpty && hasOrphanedRequiredMember && hasEngaged` from real CAS/queue/pin state. `grep -c 'missingDependency: false'` (comments stripped) → `0`. `grep -c 'replace_for_device(\|%DeviceReport{' library_availability_e2e_test.exs` → `0`. Untouched by `47ac7b6`. |
| **WR-04** (malformed `entries` → 500) | ✓ STILL CLOSED | `do_replace/2` retains the `is_list` clause + `Enum.all?(entries, &is_map/1)` + catch-all through `action_fallback`; absent-key default and `:too_many_entries` branch intact. |
| **WR-05** (enqueue-time newest-wins supersede) | ✓ STILL CLOSED | `Outbox.enqueue` still deletes `kind = ? AND state = 'pending'` inside the insert transaction; all four supersede tests pass in the 24/24 run. |
| **847165b live-row check** | ✓ STILL LOAD-BEARING | Both `…ArrivedMeanwhile` and `…NothingNewerArrived` still pass with the watermark clause disabled, confirming the two clauses are independent and neither masks the other. |

`97b1358` touches `OutboxWorker.swift` only to add `OutboxDrainResult.failureClassification`; creation-order draining, the stop-on-first-retry rule, the WR-01 markInFlight-failure stop, and the permanent-rejection branch are unchanged. No regression.

## Goal Achievement

### Observable Truths (Roadmap Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Browse the complete server catalogue before downloading bytes; find content; curate Favorites/Collections/Continue/Recent/queue; LiveView console offers the same views | ✓ VERIFIED | Unchanged; LIBR-02 re-confirmed closed above. |
| 2 | Choose a game/collection for download, resume verified ranges after interruption, distinguish six availability states | ✓ VERIFIED | Unchanged; `AvailabilityState.derive` untouched by all three commits on this head. |
| 3 | Set capacity policy, pin content, reclaim only reconstructable unpinned bytes; launch only after every required member verifies locally; remains launchable offline | ✓ VERIFIED | Unchanged. |
| 4 | Select/install one supported Mac adapter with exact capability info; validate locally supplied BIOS or open replacement; preflight remedy per blocker | ✓ VERIFIED | Unchanged. |
| 5 | Connect/test/assign/remap/reset/recover a controller with keyboard/pointer/screen-reader/focus/reduced-motion fallbacks; launch/exit/relaunch from a signed/notarized build after app or server restart | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED (controller-hardware portion) / ✓ VERIFIED (notarization portion) | Unchanged; routed to human verification. |

**Score:** 5/5 roadmap truths verified or appropriately routed; 1 present-but-behavior-unverified. WR-07 is a sub-requirement-level must-have from 03-16-PLAN.md, not a roadmap SC, and is tracked in `gaps`.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `playstead-mac/Playstead/Persistence/Migrations.swift` | Durable store for the delivered fact + a total order, upgradable from every prior shape | ✓ VERIFIED | `enqueue_seq` column, backfill and index correct. The watermark upgrade is now a legacy-column-gated DROP, verified in sqlite3 against all four reachable schema states, and falsified both directions. |
| `playstead-mac/Playstead/Sync/Outbox.swift` | Newest-wins supersede across the full entry lifecycle | ⚠️ PARTIAL | Enqueue-time, live-newer and delivered-newer cases implemented, atomic and tested, on a total order. Only residues 2/3 remain, both architectural and outside `Outbox`. |
| `playstead-mac/PlaysteadTests/CurationTests/OutboxTests.swift` | Fail-first coverage of all WR-07 rounds | ✓ VERIFIED | 25/25 at HEAD; inverted tie test and kind-scoping test both genuine and load-bearing. |
| `playstead-mac/PlaysteadTests/SyncTests/OutboxWatermarkMigrationTests.swift` | Coverage of the schema-upgrade path no other suite can reach | ✓ VERIFIED | 3/3 (not 2/2 as reported). Genuinely exercises the upgrade: `LocalStore.init` opens a fresh connection and re-runs migrations, with no caching. The relaunch test pins the conditional gate. |
| `playstead-mac/Playstead/App/PlaysteadApp.swift` | Comments that do not assert false serialization | ✓ VERIFIED | Both `drainOutbox` and `drainSaveUploads` now state entry/revision-level non-racing without claiming serialization, and point at `Outbox` as the component that must be correct across reentrancy. |
| `playstead-mac/Playstead/Cache/AvailabilityReporter.swift` | Real, non-constant `missing_dependency` signal | ✓ VERIFIED | Re-confirmed; 0 hardcoded literals in executable code. |
| `playstead-server/.../availability_controller.ex` | 422 shape guard on malformed `entries` | ✓ VERIFIED (WR-04) | Guard intact. Noted: still no report-ordering guard, which is why residue 2 has no server-side mitigation. |
| `.planning/REQUIREMENTS.md` | Authoritative requirement traceability | ✓ VERIFIED | Untouched; LIBR-05 (line 137) and PLAY-04 (line 145) still correctly `Pending`. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `CurationIntentKind.availabilityReport` → `Outbox.enqueue` | at-most-one-pending-row | `supersedesPending` scoped delete | ✓ WIRED | Unchanged, tested. |
| `Outbox.markDone` → `outbox_delivered_watermark` | the delivered fact outlives the row | single transaction, `INSERT…SELECT` + `MAX` upsert | ✓ WIRED | Correct on a fresh schema and now on every upgraded one; missing-row case verified safe in sqlite3. |
| `Outbox.markPendingForRetry` → `isSupersededForRetry` | drop a superseded revived row | live-row check OR watermark check, both on `enqueue_seq` | ✓ WIRED | Both clauses independently load-bearing; the tie window is closed — flattening the sequence to a constant fails all three supersede tests. |
| `Outbox.onEnqueue` → `OutboxWorker.drainOnce` | post-enqueue drain | `OutboxDrainTrigger.fire()` → `Task { await … }` | ✓ WIRED | PlaysteadApp.swift:648. Still the wiring that makes the reentrancy window reachable; now documented accurately. |
| `AvailabilityReporter.buildEntries` → `missing_dependency` chip | HTTP-driven, no read-model seeding | shared fixture → real controller → LiveView | ✓ WIRED | Re-confirmed by grep (0 bypasses). |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| `OutboxTests` + `OutboxWatermarkMigrationTests` at HEAD `8d008b4` | `xcodebuild test … -only-testing:…` | 25/25 and 3/3, 0 failures | ✓ PASS |
| Broken `try? ALTER` restored (falsification) | conditional DROP → the old ALTER | both upgrade tests fail with `NOT NULL constraint failed: outbox_delivered_watermark.created_at`; 25 OutboxTests stay green | ✓ PASS (fails as required) |
| Conditional gate is load-bearing (falsification) | DROP made unconditional | `test_theWatermarkSurvivesAnOrdinaryRelaunch` fails at :96 | ✓ PASS (fails as required) |
| Legacy detection, table absent | sqlite3 `pragma_table_info … WHERE name='created_at'` | `[]` → no drop | ✓ PASS |
| Legacy detection, current schema | same | `[]` → no drop, watermark preserved | ✓ PASS |
| Legacy detection, 47ac7b6 schema | same | `[1]` → dropped | ✓ PASS |
| Legacy detection, 711f866 half-migrated schema | same | `[1]` → dropped | ✓ PASS |
| No other table carries WR-08's hazard | CREATE/ALTER extraction + scan of all 19 commits touching Migrations.swift | watermark is the only table ever reshaped; all other changes additive with a matching ALTER | ✓ PASS |
| ALTER-only columns (mirror hazard) | CREATE-vs-ALTER column diff | 1 found: `save_revision.restored_here_at` — advisory, phase 04 scope | ℹ️ INFO |
| No startup `in_flight` recovery sweep | `grep -rn in_flight playstead-mac/Playstead/` | only `Outbox.swift` + one comment | ✓ PASS (confirms the coincidental reliance) |
| Byte-exact restore after both probes | `git diff HEAD --stat -- playstead-mac/` | empty | ✓ PASS |
| Debt-marker scan (TBD/FIXME/XXX) on all files in `8d008b4` | `grep -nE` | no matches | ✓ PASS |

Per project convention, every probe restore was done by copying back a saved byte-exact backup, never by `git checkout`.

### Requirements Coverage

All 15 phase requirement IDs accounted for against REQUIREMENTS.md.

| Requirement | Status | Evidence |
|---|---|---|
| LIBR-01 | ✓ SATISFIED | Line 133 Complete. Unchanged. |
| LIBR-02 | ✓ SATISFIED | Line 134 Complete. Re-confirmed closed by direct read. |
| LIBR-03 | ✓ SATISFIED | Line 135 Complete. Unchanged. |
| LIBR-04 | ✓ SATISFIED | Line 136 Complete. Unchanged. |
| LIBR-05 | ? NEEDS HUMAN | Line 137 Pending. Human UX judgment; explicit scope fence. |
| CACH-01 | ✓ SATISFIED | Line 138 Complete. Unchanged. |
| CACH-02 | ✓ SATISFIED | Line 139 Complete. Unchanged. |
| CACH-03 | ✓ SATISFIED | Line 140 Complete. Unchanged. |
| CACH-04 | ✓ SATISFIED | Line 141 Complete. Unchanged. |
| PLAY-01 | ✓ SATISFIED | Line 142 Complete. Unchanged. |
| PLAY-02 | ✓ SATISFIED | Line 143 Complete. Unchanged. |
| PLAY-03 | ✓ SATISFIED | Line 144 Complete. Real-BIOS acceptance remains human-gated (03-UAT.md item 13). |
| PLAY-04 | ? NEEDS HUMAN | Line 145 Pending. Physical controller hardware. |
| PLAY-05 | ✓ SATISFIED | Line 146 Complete. Live interactive launch remains human-gated (03-UAT.md item 7). |
| QUAL-01 | ✓ SATISFIED | Line 155 Complete. Live VoiceOver/visual walkthrough remains human-gated. |

No orphaned requirement IDs.

### Anti-Patterns Found

None in the files modified by the three commits on this head. No `TBD`/`FIXME`/`XXX` markers.

ℹ️ Info (pre-existing, unchanged): `markPendingForRetry` remains the only path from `in_flight` back to `pending`, so a process crash while a row is `in_flight` strands it with no startup recovery sweep — neither retried nor superseded. Out of scope for this gap, but a durable watermark plus a startup sweep would address both together.

### Note on evidence provenance

The `OutboxTests` runs, the falsification of the watermark clause, and the tie probe were all executed by this verification directly and are first-hand results. The reported full local Unit layer (702 tests / 0 failures) was **not** re-run here and is not load-bearing for any verdict above. Hosted CI for `47ac7b6` was not consulted. The intermittent live-server failures tracked as WINDOWS #70/#71/#87 are deliberately **not** attributed to any phase 03 requirement.

### Gaps Summary

One gap. **WR-08 is closed.** The legacy-column-gated DROP is correct, its detection covers all four reachable schema states including the half-migrated one the author did not enumerate, and I falsified it in both directions — restoring the broken ALTER fails the upgrade tests, and making the drop unconditional fails the relaunch test. The two discrepancies I found are between the author's *message* and the author's *commit*, not in the code: the message describes an unconditional drop (the code gates it) and reports 2 tests (there are 3). Both errors understate the work.

What remains of WR-07 is the two architectural residues that have been stable across all four rounds: a late-succeeding in-flight request, and a newer row retired by rejection or quarantine. Neither is closable in `Outbox`; residue 2 needs a server-side monotonic guard on `PUT /api/v1/devices/me/availability`, and both want a WINDOWS.md entry if they are to be accepted instead.

One advisory, outside phase 03: `save_revision.restored_here_at` is the only column in the schema declared solely by a `try? ALTER` and missing from its `CREATE` block — sound today, fragile to a future cleanup. And one coincidental reliance recorded: the watermark's cross-restart protection is currently latent, because `in_flight` rows are stranded at startup; whoever adds a recovery sweep makes that path live and must not also relax the conditional drop.

Four human verification items carry forward unchanged: physical controller hardware, a live interactive emulator launch session, a live VoiceOver/visual walkthrough, and real BIOS bytes.

---

_Verified: 2026-09-15T17:00:00Z at HEAD 8d008b4_
_Verifier: Claude (gsd-verifier) — fifth independent pass; no source files modified (working tree clean, all probe files restored byte-exact)_
