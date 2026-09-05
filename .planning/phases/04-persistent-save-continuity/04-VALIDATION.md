---
phase: "4"
slug: "persistent-save-continuity"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: validated
nyquist_compliant: false
wave_0_complete: true
created: "2026-09-03"
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (server) + XCTest across four named Mac test plans (Unit, Rendering, UI, LiveServer) |
| **Config file** | `playstead-server/test/test_helper.exs`; `playstead-mac/TestPlans/{Unit,Rendering,UI,LiveServer}.xctestplan` |
| **Quick run command (server, per file)** | `cd playstead-server && MIX_ENV=test mix test test/path/to/file_test.exs` |
| **Quick run command (Mac, per test)** | `cd playstead-mac && xcodebuild test -project Playstead.xcodeproj -scheme Playstead -testPlan Unit -destination 'platform=macOS' CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= -only-testing:PlaysteadTests/SomeTests/testSomething` |
| **Full suite command (server)** | `cd playstead-server && MIX_ENV=test mix test` |
| **Full suite command (Mac)** | `playstead-mac/scripts/ci/run-mac-verification.sh` (four-layer topology: Unit, Rendering, UI, LiveServer) |
| **Estimated runtime** | Server suite: seconds. Full four-layer Mac verification: tens of minutes (UI/LiveServer layers spawn a real app and, for LiveServer, a local Postgres/Phoenix instance). |

---

## Sampling Rate

- **After every task commit:** Run the task's own `<automated>` command(s) — the per-file/per-test quick commands above.
- **After every plan wave:** Run the full server suite (`mix test`) and the relevant Mac test plan(s) touched by that wave.
- **Before `/gsd-verify-work`:** Full suite must be green — server (`mix test`) and all four Mac test plans via `run-mac-verification.sh`.
- **Max feedback latency:** Per-task quick commands complete in well under 4 seconds for server tests; Mac per-test `-only-testing` runs complete in seconds to low tens of seconds.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 4-01-01 | 01 | 1 | SAVE-01 | T-04-01-01 | Probe scoped to a temp directory it creates and removes; measures mmap-writer inode/mtime/writeback behavior without touching the app's real save tree | unit (script) | `cd playstead-mac && swift scripts/probes/save-p1-probe.swift \| python3 -c "..."` | ✅ | ✅ green |
| 4-01-02 | 01 | 1 | SAVE-01 | T-04-01-02 | Report schema validated with negative cases per required key, so a truncated report fails the gate instead of passing quietly | unit | `cd playstead-mac/scripts/ci/tests && python3 -m unittest test_save_p1_probe -v` | ✅ | ✅ green |
| 4-02-01 | 02 | 1 | SAVE-01, SAVE-03 | T-04-02-01 | Backup exclusion moved off the root onto reconstructable directories only; stale root flags repaired at init | unit | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` (AppPathsBackupExclusionTests) | ✅ | ✅ green |
| 4-02-02 | 02 | 1 | SAVE-01, SAVE-03 | T-04-02-02 | Per-`assetSetID` launch mutex spans prepare → spawn → exit; released exactly once even on early throws | unit | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` (AdapterLaunchMutex tests) | ✅ | ✅ green |
| 4-02-03 | 02 | 1 | SAVE-01, SAVE-03 | T-04-02-03 | Readiness probe for save-directory writability uses a uniquely-named temp path and leaves the directory unchanged on every outcome | unit | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` (readiness atomic-placement tests) | ✅ | ✅ green |
| 4-03-01 | 03 | 1 | SAVE-01 | T-04-03-01 | `reserve: :critical` bypasses only the general margin; a 64 MiB physical floor still refuses writes below it | unit (ExUnit) | `cd playstead-server && MIX_ENV=test mix test test/playstead/readiness_critical_reserve_test.exs` | ✅ | ✅ green |
| 4-03-02 | 03 | 1 | SAVE-01 | T-04-03-02 | Six save problem codes registered; a missing registration fails the gate instead of degrading to a generic 500 | unit (ExUnit) | `cd playstead-server && MIX_ENV=test mix test test/playstead_web/error_codes_test.exs` | ✅ | ✅ green |
| 4-03-03 | 03 | 1 | SAVE-01 | T-04-03-03 | Save-namespaced upload concurrency (`UploadSlots`) and 120/hour rate limit enforced independently of the general download lane | unit (ExUnit) | `cd playstead-server && MIX_ENV=test mix test test/playstead/readiness_critical_reserve_test.exs` | ✅ | ✅ green |
| 4-04-01 | 04 | 2 | SAVE-01, SAVE-02 | T-04-04-01 | End-to-end tracer: capture → upload → server revision, with path components resolved through the shipped `Sanitize`/`PathSafety` helpers | tracer (ExUnit) | `cd playstead-server && MIX_ENV=test mix test test/playstead_web/controllers/api/v1/saves_controller_test.exs` | ✅ | ✅ green |
| 4-04-02 | 04 | 2 | SAVE-01, SAVE-02 | T-04-04-02 | Capture/lane invariants: server-assigned ordering, idempotent commit, digest verification during streaming | unit | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` (capture/lane invariant tests) | ✅ | ✅ green |
| 4-04-03 | 04 | 2 | SAVE-01, SAVE-02 | T-04-04-03 | Snapshot catch-up and journal apply-back-down close the sync loop for save revisions | unit (ExUnit) | `cd playstead-server && MIX_ENV=test mix test test/playstead/saves_test.exs` | ✅ | ✅ green |
| 4-05-01 | 05 | 3 | SAVE-01, SAVE-02, SAVE-04 | T-04-05-01 | Accept-and-branch: no non-fast-forward rejection ever discards a client's only durable copy | unit (ExUnit) | `cd playstead-server && MIX_ENV=test mix test test/playstead/saves_branches_test.exs` | ✅ | ✅ green |
| 4-05-02 | 05 | 3 | SAVE-01, SAVE-02, SAVE-04 | T-04-05-02 | Committed revisions are immutable (409 on mutation attempt); branch fan-out capped at 32 heads, raised loudly | unit (ExUnit) | `cd playstead-server && MIX_ENV=test mix test test/playstead_web/controllers/api/v1/save_history_controller_test.exs test/playstead/saves_test.exs` | ✅ | ✅ green |
| 4-05-03 | 05 | 3 | SAVE-01, SAVE-02, SAVE-04 | T-04-05-03 | Divergence resolution is append-only; both arrival orders of a concurrent resolution converge to the identical retained set | unit (ExUnit) | `cd playstead-server && MIX_ENV=test mix test test/playstead/saves_test.exs` | ✅ | ✅ green |
| 4-06-01 | 06 | 3 | SAVE-01 | T-04-06-01 | Temporal quiescence (three consecutive identical 1 Hz reads) is the sole capture trigger for a live mmap artifact; bytes are never parsed | unit | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` (SaveCapturePoller tests) | ✅ | ✅ green |
| 4-06-02 | 06 | 3 | SAVE-01 | T-04-06-02 | Crash recovery replays the settle pass idempotently; disk-full path is a durable blocked row with retry, never data loss | unit | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` (SaveSessionRecovery / disk-full tests) | ✅ | ✅ green |
| 4-06-03 | 06 | 3 | SAVE-01 | T-04-06-03 | Save revisions are unconditionally excluded from eviction candidate selection, even under maximum quota pressure | unit | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` (QuotaManager eviction-exclusion tests) | ✅ | ✅ green |
| 4-07-01 | 07 | 4 | SAVE-03 | T-04-07-01 | Adapter-declared save contract; three-tier compatibility gate hard-blocks a `medium_id`/`artifact_bytes` mismatch with no override | unit | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` (SaveCompatibilityGate tests) | ✅ | ✅ green |
| 4-07-02 | 07 | 4 | SAVE-03 | T-04-07-02 | Pure `LaunchSavePlanner`: a diverged slot always yields `.keep`; never auto-picks a branch or writes a non-local head | unit | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` (LaunchSavePlannerTests) | ✅ | ✅ green |
| 4-07-03 | 07 | 4 | SAVE-03 | T-04-07-02 / T-04-07-04 | Impure executor: stage → fsync → rename → fsync directory, never in-place; always full re-hash at restore, quarantine on mismatch | unit | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` (SavePlanExecutorTests) | ✅ | ✅ green |
| 4-08-01 | 08 | 4 | PORT-01 | T-04-08-01 | Pure `Export.SavesPlan` and filename grammar route every name through the shipped `Sanitize.component/1` | unit (ExUnit) | `cd playstead-server && MIX_ENV=test mix test test/playstead/export/saves_plan_test.exs` | ✅ | ✅ green |
| 4-08-02 | 08 | 4 | PORT-01 | T-04-08-03 | Missing revision bytes are named in the sidecar and excluded from `fetch.txt`, so `sha256sum -c` still succeeds on an incomplete bag | unit (ExUnit) | `cd playstead-server && MIX_ENV=test mix test test/playstead/export/sidecar_test.exs` | ✅ | ✅ green |
| 4-08-03 | 08 | 4 | PORT-01 | T-04-08-04 | `saves_scope` persisted on `ExportRecord`; determinism asserted as plan purity plus write reproducibility plus append-only stability | unit (ExUnit) | `cd playstead-server && MIX_ENV=test mix test test/playstead/export/layout_test.exs` | ✅ | ✅ green |
| 4-09-01 | 09 | 5 | SAVE-02 | T-04-09-01 | One shared save vocabulary asserted exhaustive on both Mac and server; an unlisted string fails the gate | unit (ExUnit + XCTest) | `cd playstead-server && MIX_ENV=test mix test test/playstead/save_copy_contract_test.exs` and `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` | ✅ | ✅ green |
| 4-09-02 | 09 | 5 | SAVE-02 | T-04-09-06 | The navigational Save row can never produce `.blocked` and does not contribute to the readiness blocker count | unit | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` (SaveStateModel / rollup tests) | ✅ | ✅ green |
| 4-09-03 | 09 | 5 | SAVE-02 | T-04-09-04 | Save history sheet and card rank-1 union render from the shared vocabulary; digests/paths stay behind the Details disclosure | rendering (snapshot) | `cd playstead-mac && scripts/ci/run-mac-verification.sh --layers rendering --only-testing PlaysteadTests/SaveHistoryContractSnapshotTests` (+ `LibraryContractSnapshotTests`) | ✅ | ✅ green |
| 4-10-01 | 10 | 5 | SAVE-02, SAVE-04, PORT-01 | T-04-10-03 | Saves-owned attention source unions into the shared inbox at read time; `Playstead.Attention.Reason` stays frozen | unit (ExUnit) | `cd playstead-server && MIX_ENV=test mix test test/playstead/saves_attention_source_test.exs` | ✅ | ✅ green |
| 4-10-02 | 10 | 5 | SAVE-02, SAVE-04, PORT-01 | T-04-10-02 | Console saves surface (inspect, choose, keep-both) calls only the append-only context functions from plan 04-05; nothing is deleted | unit (ExUnit, LiveView) | `cd playstead-server && MIX_ENV=test mix test test/playstead_web/live/saves_live_test.exs` | ✅ | ✅ green |
| 4-10-03 | 10 | 5 | SAVE-02, SAVE-04, PORT-01 | T-04-10-05 | Console export control and export-this-version deep link; digest stays behind the Details disclosure | unit (ExUnit, LiveView) | `cd playstead-server && MIX_ENV=test mix test test/playstead_web/live/saves_live_test.exs` | ✅ | ✅ green |
| 4-11-01 | 11 | 6 | SAVE-02, SAVE-04 | T-04-11-01 | Mac saves attention source writes the local mutation and durable outbox row in one transaction, mirroring shipped `Outbox.enqueue` | unit + rendering | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` and `scripts/ci/run-mac-verification.sh --layers rendering --only-testing PlaysteadTests/LibraryContractSnapshotTests` | ✅ | ✅ green |
| 4-11-02 | 11 | 6 | SAVE-02, SAVE-04 | T-04-11-02 / T-04-11-04 | Comparison sheet shows four facts with no ranking, pre-selection, or colour distinction; full keyboard parity | rendering + UI (snapshot/interaction) | `scripts/ci/run-mac-verification.sh --layers rendering --only-testing PlaysteadTests/ConflictComparisonContractSnapshotTests` and `--layers ui --only-testing PlaysteadUITests/ConflictResolutionInteractionTests` | ✅ | ✅ green (rendering) / ⚠️ WINDOWS #34 (UI layer requires hosted runner) |
| 4-11-03 | 11 | 6 | SAVE-02, SAVE-04 | T-04-11-02 | Append-only resolution works fully offline with no server; both original heads asserted present after resolution | unit | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` (SaveConflictResolverTests) | ✅ | ✅ green |
| 4-12-01 | 12 | 6 | SAVE-01, SAVE-02 | T-04-12-02 / T-04-12-03 | Escalated tier fires only on the four unfixable cases (revoked auth, capability skew, server refusal, compatibility rejection) — never on duration or count | unit + rendering | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` and `scripts/ci/run-mac-verification.sh --layers rendering --only-testing PlaysteadTests/OnlyCopyContractSnapshotTests` | ✅ | ✅ green |
| 4-12-02 | 12 | 6 | SAVE-01, SAVE-02 | T-04-12-01 | Interruptive modal at each of the five destructive-intent points when only-on-this-Mac count > 0; export escape hatch is the default button | UI (interaction) | `scripts/ci/run-mac-verification.sh --layers ui --only-testing PlaysteadUITests/OnlyCopyInterruptionTests` | ✅ | ✅ green (build+registration) / ⚠️ WINDOWS #36 (UI layer requires hosted runner) |
| 4-13-01 | 13 | 7 | SAVE-01, SAVE-02, SAVE-03, SAVE-04, PORT-01 | T-04-13-01 / T-04-13-02 / T-04-13-03 | Named restore proof (`SaveRestoreProofTests`) proves the file half of SAVE-03; `ZeroNetworkPlayFlowTests` proves zero HTTP requests across the whole Play flow, including fire-and-forget tasks; both wired into the required-tests manifest with a proven negative check | UI (XCTest) | `cd playstead-mac && xcodebuild test -project Playstead.xcodeproj -scheme Playstead -testPlan LiveServer ... -only-testing:PlaysteadUITests/SaveRestoreProofTests/testCapturedRevisionRestoresToByteIdenticalArtifactInLaunchDir` — verified locally, passing | ✅ | ✅ green (executed locally this session; see 04-13-SUMMARY.md) |
| 4-13-02 | 13 | 7 | SAVE-01, SAVE-02, SAVE-03, SAVE-04, PORT-01 | T-04-13-01 | Validation map filled; two SAVE-03 verification items (automated proxy, CP7-SAVE-C) recorded separately in `04-UAT.md` | docs | `python3 -c "..."` (frontmatter/table presence assertions in this plan's own `<verify>`) | ✅ | ✅ green |
| 4-13-03 | 13 | 7 | SAVE-01, SAVE-02, SAVE-03, SAVE-04, PORT-01 | T-04-13-01 | CP7-SAVE-C — the human continuation proof | human-check (blocking-human) | N/A — real emulator, real commercial title, human-only by decision (D-68) | N/A | ⬜ blocked on human execution |

| 4-14-01 | 14 | 8 | SAVE-03 | — | First production `SavePlanExecutorEnvironment`: `revisionBytes` reads the CAS and throws for an absent digest rather than fetching over the network; `captureExistingFile` preserves pre-existing bytes; quarantine moves aside without deleting | unit | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` (LaunchSaveEnvironmentTests, 8 tests; LaunchSaveContextBuilderTests, 12 tests) | ✅ | ✅ green |
| 4-14-02 | 14 | 8 | SAVE-03 | — | The production Play button actually reaches the launch-path save machinery — `GameRowView.play()` passes a non-nil `executeSavePlan` to `AdapterHost.launch`; a throwing plan aborts before the emulator spawns | unit (wiring) | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` (PlayPathSaveWiringTests, 12 tests) | ✅ | ✅ green |
| 4-15-01 | 15 | 9 | SAVE-01, SAVE-04 | — | A revision may never parent onto another save line's revision — refused by `commit_revision/3` with `save_parent_unknown` AND by a database constraint, so a direct `Repo.insert` bypassing the context is still rejected | unit (ExUnit) | `cd playstead-server && MIX_ENV=test mix test test/playstead/saves_lineage_scoping_test.exs` | ✅ | ✅ green |
| 4-15-02 | 15 | 9 | SAVE-01, SAVE-04 | — | Save-revision rate limit, declared-length cap and save-namespaced concurrency slot enforced on the real commit/upload endpoints; a refused upload leaks no slot and a same-`command_id` retry consumes no second slot | unit (ExUnit) | `cd playstead-server && MIX_ENV=test mix test test/playstead_web/controllers/api/v1/saves_limits_test.exs` | ✅ | ✅ green |
| 4-16-01 | 16 | 10 | SAVE-01, SAVE-02 | — | Reclaim candidate rows and the storage snapshot carry the real only-on-this-Mac count through `AppEnvironment`'s production path; an in-flight upload still counts as only-on-this-Mac | unit (wiring) | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` (OnlyCopyWiringTests) | ✅ | ✅ green |
| 4-16-02 | 16 | 10 | SAVE-01, SAVE-02 | — | The export escape hatch resolves to the committed save line and never reclaims anything on the way out | unit (wiring) | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` (OnlyCopyWiringTests, 8 tests total across 4-16-01/02) | ✅ | ✅ green |
| 4-16-03 | 16 | 10 | SAVE-01, SAVE-02 | — | Diverged badge, readiness Save row, escalation panel and comparison sheet all render from real production state, not directly-constructed view fixtures; going offline outranks a previously recorded unfixable failure | unit (wiring) | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` (SaveSurfaceWiringTests) | ✅ | ✅ green |
| 4-17-01 | 17 | 11 | SAVE-01, SAVE-02 | — | Capture writes replace atomically via `rename(2)` — a failed replace leaves the prior file intact and removes the temp artifact; many sequential replacements never leave an empty or truncated file | unit | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` (SaveCaptureAtomicityTests, 6 tests) | ✅ | ✅ green |
| 4-17-02 | 17 | 11 | SAVE-01, SAVE-02 | — | A journal echo of a self-authored revision preserves every local-only column while still updating server-owned ones; repeated echoes are idempotent and never degrade local-only state | unit | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` (JournalRevisionMergeTests, 6 tests) | ✅ | ✅ green |
| 4-17-03 | 17 | 11 | SAVE-01, SAVE-02 | — | Fork-acknowledgment entries are exempt from the compaction horizon delete, so `fork_acknowledged?/3` stays true past the horizon and `oldest_surviving_seq/0` is not pulled backward | unit (ExUnit) | `cd playstead-server && MIX_ENV=test mix test test/playstead/sync/compaction_retention_test.exs` | ✅ | ✅ green |
| 4-18-01 | 18 | 12 | SAVE-03 | — | Four flagless XCUITest front-door journeys prove the save surfaces are reachable through real navigation rather than direct construction | UI (XCTest) | `scripts/ci/run-mac-verification.sh --layers ui --only-testing PlaysteadUITests/SaveFrontDoorJourneyTests` | ✅ | ⚠️ NOT EXECUTED — WINDOWS #34/#36 (hosted runner); compiles and is registered in `TestPlans/UI.xctestplan`, never run |
| 4-18-02 | 18 | 12 | SAVE-01, SAVE-02 | — | Reachability sweep promoted to a real `--strict` CI gate: a production symbol with no production caller fails the build unless it carries a reasoned allowlist entry | gate (script) | `playstead-mac/scripts/ci/reachability-sweep.sh --strict` | ✅ | ✅ green (re-run this session: no unreachable production symbols) |
| 4-19-01 | 19 | 13 | SAVE-01, SAVE-02 | — | `SaveSessionCoordinator` owns one play session's capture lifecycle: baseline on an out-of-band change, exactly one promoted revision parented onto the head read at `begin`, `end()` without `begin()` a no-op, and a capture failure recorded as a blockage rather than thrown at the Play path | unit | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` (SaveSessionCoordinatorTests, 17 tests) | ✅ | ✅ green |
| 4-19-02 | 19 | 13 | SAVE-01, SAVE-02 | — | The real Play path begins and ends a capture session bound to the same path the save plan writes, and app launch replays abandoned sessions idempotently — falsified by deleting the `begin()` call and observing the suite go red | unit (wiring) | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` (PlayPathSaveWiringTests) | ✅ | ✅ green |
| 4-19-03 | 19 | 13 | SAVE-04 | — | `SaveUploadLane` constructed in production and drained on promotion and on the reachability-online transition; `saveUploadFailureClassification()` returns the lane's real outcome instead of a constant, so D-40's four unfixable reasons are reachable | unit (wiring) | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` (SaveSurfaceWiringTests escalation tests) | ✅ | ⚠️ PARTIAL — failure-classification half green; the lane's end-to-end **success** path is unproven (no live paired server, WINDOWS #3/#6) |
| 4-19-04 | 19 | 13 | SAVE-01, SAVE-02 | — | The five wired symbols were removed from the allowlist so the sweep, not the allowlist, is what proves their reachability — allowlist 23 → 18 active entries, nothing else touched | gate (script) | `cd /Users/jon/projects/playstead && playstead-mac/scripts/ci/reachability-sweep.sh --strict` | ✅ | ✅ green (verified: exactly 5 removed in `408c245`) |
| 4-20-01 | 20 | 14 | SAVE-03, SAVE-04 | — | A sha backing a save revision is never reported by `unreferencedObjects()`, so a user's only save copy can never appear in the reclaim menu as removable junk; a genuinely orphaned sha still does | unit | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` (EvictionTests, SaveQuotaInteractionTests) | ✅ | ✅ green |
| 4-20-02 | 20 | 14 | SAVE-03, SAVE-04 | — | Capture bytes are committed into the CAS **before** the revision row is inserted, so a row never claims bytes the CAS lacks; an already-present digest is a no-op, and a commit failure is recorded as blocked without affecting the launch | unit | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` (SaveSessionCoordinatorTests CAS tests) | ✅ | ✅ green |
| 4-20-03 | 20 | 14 | SAVE-03, SAVE-04 | — | The consumer that actually reads `bytesLocal` reports `true` for a revision this Mac captured locally, with no server involvement — the assertion that would have failed before 04-20 task 2, falsified by deletion and restored | unit | `cd playstead-mac && xcodebuild test ... -testPlan Unit ...` (LaunchSaveContextBuilderTests `testASaveCapturedOnThisMacIsReportedAsBytesLocalWithNoServerInvolvement`) | ✅ | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky, unexecuted, or partial — read the cell, never just the icon*

**Sampling continuity check:** No three consecutive tasks lack an automated verify command. Every task above carries at least one `<automated>` command except 4-13-03, the phase's single designed checkpoint (`type="checkpoint:human-verify"`, `gate="blocking-human"`), which is immediately preceded and followed (across plan boundaries) by automated tasks. Two later tasks — 4-18-01 and 4-19-03 — carry automated commands that **exist but have never been executed**; they are recorded as ⚠️ above and itemised under Manual-Only rather than counted as green.

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. Every task across plans 04-01 through 04-13 declared and shipped its own test file inside its own plan (no task depended on a not-yet-existing test file from a later plan); the two files this plan (04-13) adds — `SaveRestoreProofTests.swift` and `ZeroNetworkPlayFlowTests.swift` — were created and verified within this same plan, not deferred.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| CP7-SAVE-C: a real commercial title flushes its save on a bounded cadence; captured bytes are accepted back by the emulator with correct in-game progress after a clean-Mac restore; post-exit writeback (normal quit and force-quit) behaves as designed | SAVE-03 | Requires a real emulator (pinned mGBA adapter), a real commercial GBA title, and a human judging "the game actually continued" — none of which can be synthesized or automated. The automated proxy (`testCapturedRevisionRestoresToByteIdenticalArtifactInLaunchDir`) proves only that captured bytes restore byte-identically to disk; it cannot prove the emulator accepts those bytes as valid save data or that in-game progress is correct. | Perform the five steps in 04-13-PLAN.md's Task 3 `<how-to-verify>` against a real commercial GBA title through the pinned mGBA adapter, with the server running and the Mac paired. Record each observation, the title used, and the adapter version in `04-UAT.md`. Never mark this passed from an automated test result. |
| SaveFrontDoorJourneyTests — four flagless front-door journeys proving the save surfaces are reachable through real navigation | SAVE-03 | Not manual by nature — blocked by environment. The UI layer spawns a real app process and drives a real accessibility tree; local execution is disabled by the project's login-Keychain launch guard, so it requires the centrally orchestrated hosted macOS runner (WINDOWS #34/#36). | Run `scripts/ci/run-mac-verification.sh --layers ui --only-testing PlaysteadUITests/SaveFrontDoorJourneyTests` on the hosted runner. Until then the journeys are proven to compile and to be registered in `TestPlans/UI.xctestplan` — nothing more. Do not read "registered" as "passing". |
| SaveUploadLane end-to-end success — a locally-captured revision actually reaching a live paired server | SAVE-04 | Requires a running Playstead server and a paired device, neither available in this environment (the same constraint as WINDOWS #3/#6). The lane's *failure* classification is automated and green; only the success path is unproven. | Pair a Mac against a live server, capture a save through a real play session, and assert the revision's `durability` leaves `.localOnly`. Record the result here. A green failure-classification test is not evidence for this. |
| WINDOWS #52 — crash-recovered captures never reach the CAS | SAVE-01 | **Not a testing gap — an open implementation defect.** `SaveSessionRecovery.replay` records a promoted revision but holds no `CASManager`, so `LaunchSaveContextBuilder` reports `bytesLocal: false` for it. This is the same hole 04-20 closed on the live-session path (WINDOWS #49), reached via the second capture path. No test is written for it here because any honest test would be red. | A future plan should give `SaveSessionRecovery` a `CASManager` and extract 04-20's `commitCaptureBytes` into one shared spelling rather than a second copy, then assert `bytesLocal: true` for a crash-recovered revision through `LaunchSaveContextBuilder`. |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies (55 of the 56 mapped tasks across plans 04-01 → 04-20 carry an `<automated>` command; the one checkpoint, 4-13-03, is human-only by design and recorded separately as CP7-SAVE-C above)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (none found)
- [x] No watch-mode flags
- [x] Feedback latency < 4s for per-file/per-test quick commands
- [ ] `nyquist_compliant` — **false**. Three items block it: 4-18-01's four front-door journeys have never been executed (hosted-runner-only), 4-19-03's upload success path has no live-server proof, and CP7-SAVE-C is human-only by design. Every other task in the phase is automated and independently verified green.

**Approval:** approved 2026-09-04 for plans 04-01 → 04-13. Re-approved 2026-09-05 covering plans 04-14 → 04-20 — see the audit below. Status is **PARTIAL**, not compliant: the phase's automated evidence is complete and re-executed from scratch this session, but two automated verifications remain unexecuted for environmental reasons and one checkpoint remains human-only.

---

## Validation Audit 2026-09-05

Triggered by `/gsd-validate-phase 4`. The per-task map covered plans 04-01 → 04-13 only; plans 04-14 → 04-20 (19 tasks, waves 8–14) had shipped without map rows.

| Metric | Count |
|--------|-------|
| Gaps found | 19 undocumented tasks + 1 uncovered behavior |
| Resolved (map rows added, evidence verified) | 17 |
| Escalated to Manual-Only | 3 (4-18-01, 4-19-03, WINDOWS #52) |

**Suite status was re-established by execution this session, not copied from the SUMMARYs:**

| Gate | Result | Claimed baseline |
|------|--------|------------------|
| Mac Unit test plan | 545 tests, 545 passed, **0 failures** | ≥ 536 (04-20) — exceeded |
| Mac Rendering test plan | 46 tests, 44 passed, 2 skipped, **0 failures** | 46 / 2 skipped (04-20) — matched |
| Elixir suite (`MIX_ENV=test mix test`) | 178 features, 13 properties, **1015 tests, 0 failures** | 1015 (04-17) — matched |
| `reachability-sweep.sh --strict` | no unreachable production symbols | exit 0 (04-19/04-20) — matched |

The `SetupWizardJourneyTest` / `AppPathsBackupExclusionTests` flakes named in the 04-19 and 04-20 testing notes did not recur in this run.

**Verified beyond the SUMMARY claims:**
- All 16 test files named by plans 04-14 → 04-20 exist on disk.
- The reachability allowlist went 23 → 18 active entries in `408c245` — exactly the five symbols 04-19 wired (`SaveCapturePoller`, `FileSaveArtifactSource`, `SaveSessionRecovery`, `SaveCaptureBlockedState`, `SaveUploadLane`), nothing else.
- Each task's named tests were read against its plan's `<acceptance>` block to confirm the assertion matches the claim rather than merely sharing its filename.

**No new tests were written.** Every documented gap was a missing map row over a test that already existed and passes. The one genuinely uncovered behavior — WINDOWS #52 — is an open implementation defect, and a test for it would be red; it is recorded under Manual-Only for a future plan rather than papered over. WINDOWS #52 was already disclosed by 04-20-SUMMARY.md; this audit confirms it against the source rather than discovering it.
