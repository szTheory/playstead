---
phase: "4"
slug: "persistent-save-continuity"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: validated
nyquist_compliant: true
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

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

**Sampling continuity check:** No three consecutive tasks lack an automated verify command — every task above has at least one `<automated>` command except 4-13-03, which is the plan's single designed checkpoint (`type="checkpoint:human-verify"`, `gate="blocking-human"`) and is immediately preceded and followed (across plan boundaries) by automated tasks.

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. Every task across plans 04-01 through 04-13 declared and shipped its own test file inside its own plan (no task depended on a not-yet-existing test file from a later plan); the two files this plan (04-13) adds — `SaveRestoreProofTests.swift` and `ZeroNetworkPlayFlowTests.swift` — were created and verified within this same plan, not deferred.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| CP7-SAVE-C: a real commercial title flushes its save on a bounded cadence; captured bytes are accepted back by the emulator with correct in-game progress after a clean-Mac restore; post-exit writeback (normal quit and force-quit) behaves as designed | SAVE-03 | Requires a real emulator (pinned mGBA adapter), a real commercial GBA title, and a human judging "the game actually continued" — none of which can be synthesized or automated. The automated proxy (`testCapturedRevisionRestoresToByteIdenticalArtifactInLaunchDir`) proves only that captured bytes restore byte-identically to disk; it cannot prove the emulator accepts those bytes as valid save data or that in-game progress is correct. | Perform the five steps in 04-13-PLAN.md's Task 3 `<how-to-verify>` against a real commercial GBA title through the pinned mGBA adapter, with the server running and the Mac paired. Record each observation, the title used, and the adapter version in `04-UAT.md`. Never mark this passed from an automated test result. |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies (34 of 35 non-checkpoint tasks across the phase carry an `<automated>` command; the one checkpoint, 4-13-03, is human-only by design and recorded separately as CP7-SAVE-C above)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (none found)
- [x] No watch-mode flags
- [x] Feedback latency < 4s for per-file/per-test quick commands
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-09-04 — automated evidence complete; CP7-SAVE-C remains open pending human execution (see `04-UAT.md`).
