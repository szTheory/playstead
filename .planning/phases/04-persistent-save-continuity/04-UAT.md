---
status: partial
phase: 04-persistent-save-continuity
source: 04-13-PLAN.md, 04-13-SUMMARY.md
started: 2026-09-04T00:00:00Z
updated: 2026-09-04T00:00:00Z
---

## Current Test

[testing paused — CP7-SAVE-C outstanding: requires a human with a real emulator and a real commercial title]

## Purpose

SAVE-03 ("the client captures a proven persistent save type, appends immutable
revisions, restores history...") has exactly **two** verification items, and
this document exists to keep them permanently, explicitly separate. A green
automated suite is not, and must never be read as, a passed continuation
proof. See D-68 in `04-CONTEXT.md`.

## Tests

### 1. Captured revision restores to byte-identical bytes on disk (the automated proxy)
expected: A captured revision, when restored onto a clean save directory through the real `SavePlanExecutor` the launch path uses, produces bytes on disk that are byte-identical to what was captured, and whose sha256 matches the revision's recorded digest.
result: pass
source: automated
evidence: |
  `SaveRestoreProofTests.testCapturedRevisionRestoresToByteIdenticalArtifactInLaunchDir`
  (plan 04-13), executed locally this session via:
  `xcodebuild test -project Playstead.xcodeproj -scheme Playstead -testPlan LiveServer
  -destination 'platform=macOS' -only-testing:PlaysteadUITests/SaveRestoreProofTests/testCapturedRevisionRestoresToByteIdenticalArtifactInLaunchDir`
  Result: 1 test, 0 failures. Writes a 32,768-byte artifact, captures it through
  `SaveCapturePoller`, clears the restore target to simulate a clean Mac, restores
  it through the real `SavePlanExecutor` (`.fastForward`, the launch path's silent
  restore), and asserts the restored bytes and sha256 match the captured original
  both from the in-process result and by re-reading the file directly.
  Registered in `TestPlans/LiveServer.xctestplan` and in
  `scripts/ci/run-mac-verification.sh`'s live-server required-tests manifest;
  a negative check (removing the identifier from the manifest's expected set)
  was run locally against the same result bundle and confirmed the gate exits
  non-zero (`required test execution count must equal 1 ... (got 0)`).
  **Evidence boundary — read this narrowly.** This proves only that captured
  bytes round-trip byte-identically through the file-write mechanism a real
  launch would use. It does NOT prove: that a real emulator accepts those bytes
  as valid save data, that in-game progress is correct after restore, that a
  real commercial title flushes on any particular cadence, or anything about
  post-exit writeback timing on real hardware. Those are exactly what test 2
  (CP7-SAVE-C) below is for, and this test's passing status must never be
  cited as evidence toward it.
coverage_id: 04-13/D1

### 2. CP7-SAVE-C — the human continuation proof
expected: Against a real commercial GBA title through the pinned mGBA adapter: (a) the on-disk `.sav` changes on a bounded cadence after an in-game save, not never; (b) a normal quit captures a revision, and a force-quit also captures a revision; (c) restoring onto a cleared save directory happens automatically with no prompt; (d) continuing the game shows the exact progress that was saved — not fresh, not stale, and with no in-game "save corrupt, erase?" prompt.
result: blocked
blocked_by: human-action
reason: "Requires a real emulator (pinned mGBA adapter), a real commercial GBA title, and a human judging in-game continuity — none of which exist or can be synthesized in this automated execution environment. This is a designed checkpoint (04-13-PLAN.md Task 3, type=\"checkpoint:human-verify\", gate=\"blocking-human\"), never auto-approved even in auto-mode, and its status may only ever be set by the developer performing the five steps in the plan's <how-to-verify> and recording the observations here. A green result on test 1 above is not, and must never be substituted as, evidence for this test."
coverage_id: 04-13/D2

## Explicit Separation Statement

Tests 1 and 2 above are deliberately recorded as two distinct rows rather than
one. The automated proxy (test 1) proves the file half of SAVE-03 and nothing
more. CP7-SAVE-C (test 2) carries the human continuation proof and is the only
thing that can close SAVE-03's "restores history" claim end to end on real
hardware. **A passing test 1 does not imply, contribute to, or partially
satisfy test 2.** Anyone reading this document who sees test 1 green must not
conclude the continuation proof has happened — it has not, until a developer
records observations under test 2 and sets its own status by hand.

## Summary

total: 2
passed: 1
issues: 0
pending: 0
skipped: 0
blocked: 1

## Gaps

- CP7-SAVE-C (test 2) requires a human session with the pinned mGBA adapter installed, a real commercial GBA title, a running paired server, and roughly 15-30 minutes to perform the five recorded steps. Until that session happens, SAVE-03's continuation claim remains open — the phase's automated evidence covers the file half only.
