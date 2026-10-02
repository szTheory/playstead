---
phase: 06-recovery-proof-ci-and-e2e-pipeline
plan: 22
subsystem: testing
tags: [github-actions, linux, recovery, evidence, sanitizer]

# Dependency graph
requires:
  - phase: 06-recovery-proof-ci-and-e2e-pipeline
    provides: Existing isolated Linux recovery fixture and bounded failure-stage markers
provides:
  - Sanitized Linux recovery-failure evidence that survives a restore-step failure
  - Duplicate-key rejection for recovery pass and failure receipts
  - Exact-head hosted evidence that preserves the red restore result
affects: [phase-06-verification, hosted-ci, PORT-04, QUAL-02]

# Actuals
actuals:
  tokens: 9000
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Persist only fixed-enum failure stages; keep raw Mix output private and ephemeral
    - Run sanitizer and artifact upload after restore failure without masking the failed job
    - Reject duplicate JSON keys at both receipt boundaries

key-files:
  created:
    - .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-22-SUMMARY.md
  modified:
    - playstead-server/scripts/ci/recovery-fixture.sh
    - playstead-server/scripts/tests/recovery-fixture-test.sh
    - playstead-mac/scripts/ci/sanitize-evidence.sh
    - playstead-mac/scripts/ci/tests/sanitizer-test.sh
    - .github/workflows/ci.yml
    - .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-HOSTED-EVIDENCE.md
    - .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-VERIFICATION.md

key-decisions:
  - "Keep the failure document to four fields and fixed enums; do not publish raw Mix diagnostics."
  - "A failed restore remains a failed Linux job even when sanitizer and upload succeed."
  - "Keep PORT-04 and QUAL-02 open; the preserved stage is diagnostic evidence, not a restore pass."

patterns-established:
  - "Post-failure evidence steps validate and upload only the sanitized receipt."
  - "Hosted CI records are tied to the exact source revision and run/job identifiers."

requirements-completed: []

coverage:
  - id: D1
    description: "Linux recovery failures persist a bounded four-field sanitized receipt without changing the passing receipt schema."
    requirement: QUAL-02
    verification:
      - kind: unit
        ref: "playstead-server/scripts/tests/recovery-fixture-test.sh; playstead-mac/scripts/ci/tests/sanitizer-test.sh"
        status: pass
    human_judgment: true
    rationale: "Hosted restore remained red; the artifact stage is operation-ambiguous and does not prove recovery."
  - id: D2
    description: "Post-failure sanitization and artifact upload complete while the Linux restore job remains failed."
    requirement: PORT-04
    verification:
      - kind: other
        ref: "GitHub Actions workflow 36952647897 on 56b64e88fb55b3224206f3ef213f45eed5711586"
        status: pass
    human_judgment: true
    rationale: "The restore failure remains open and the received source-fixture-create stage conflates two operations."

# Metrics
duration: not-recorded
completed: 2026-10-01
status: complete
---

# Phase 06 Plan 22: Sanitized Linux Restore Failure Evidence Summary

**Linux restore failures now retain a strict sanitized stage receipt after failure, while CI continues to report the restore as red.**

## Performance

- **Duration:** Not separately recorded
- **Started:** Not recorded
- **Completed:** 2026-10-01
- **Tasks:** 3
- **Files modified:** 7, plus this summary

## Accomplishments

- Added a separate four-field fixed-enum failure receipt while preserving the passing recovery receipt schema and keeping raw Mix output in a private temporary directory.
- Hardened the sanitizer against malformed, conflicting, sentinel-bearing, and duplicate-key JSON evidence; the synthetic sanitizer suite passed 120 positive/negative checks.
- Wired post-failure sanitization and sanitized-only artifact upload into the Linux job without `continue-on-error`; the failed restore remains the job conclusion.
- Verified the exact-head hosted run `36952647897` on `56b64e88fb55b3224206f3ef213f45eed5711586`: Docker, server precommit, and ordinary Mac passed; Linux restore failed while sanitizer and upload succeeded.
- Recorded the artifact stage `source-fixture-create` as ambiguous because the same marker surrounds filesystem creation and PostgreSQL seed setup. Plan 06-23 splits those operations; no root cause or recovery pass is claimed.
- Kept PORT-04, QUAL-02, entitlement, continuation, and aggregate regression gates open.

## Task Commits

1. **Task 1: Persist a closed Linux failure-stage document** - `9983041` (fix)
2. **Task 2: Sanitize and publish failure evidence after restore failure** - `4a639b4` (fix)
3. **Task 2 hardening: Reject duplicate receipt keys** - `56b64e8` (fix)

**Plan metadata:** `8121cc5` created the plan; `91e0780` tightened exact-head CI outcome gates.

## Files Created/Modified

- `playstead-server/scripts/ci/recovery-fixture.sh` and its synthetic test - persist only a closed failure-stage receipt and clean private output.
- `playstead-mac/scripts/ci/sanitize-evidence.sh` and its synthetic test - enforce the exact receipt schema, stage enum, and duplicate-key rejection.
- `.github/workflows/ci.yml` - run sanitizer and upload only sanitized recovery JSON after a failed restore.
- `06-HOSTED-EVIDENCE.md` and `06-VERIFICATION.md` - record exact-head job outcomes and the artifact's ambiguous operation stage.

## Decisions Made

- Publish only a fixed stage token; never copy raw Mix output into the artifact.
- Allow sanitized failure upload after restore failure, but preserve the Linux job's failed result.
- Treat `source-fixture-create` as an operation label only. It does not reveal whether filesystem setup or database seeding failed.
- Add no dependency or new GitHub Action.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Reject duplicate JSON keys in both receipt validators**
- **Found during:** Independent review of the wrapper and sanitizer evidence boundary
- **Issue:** The standard JSON parser accepted duplicate keys and silently retained the last value.
- **Fix:** Added duplicate-key rejection with synthetic negative coverage at both boundaries.
- **Verification:** The sanitizer and wrapper contract suites passed after the fix; the exact hosted run used this change.
- **Committed in:** `56b64e8`

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** The change strengthens the existing closed-schema contract without adding dependencies or widening evidence.

## Issues Encountered

- Workflow `36952647897` left the Linux restore check red at job `110668722059`, but sanitizer and upload succeeded. The sanitized artifact reported only `source-fixture-create`; the marker is shared by two setup operations, so Plan 06-23 must narrow attribution.
- The hosted run is tied to the code head `56b64e88fb55b3224206f3ef213f45eed5711586`. Later local documentation-only commit `91e0780` is not covered by that run; the next Plan 06-23 source head will receive a fresh exact-head run.
- No local Playstead app, Xcode/XCTest, Docker restore, or private AerevenAdvance fixture was run.

## User Setup Required

None.

## Next Phase Readiness

Plan 06-23 is ready to replace the shared source-fixture marker with distinct filesystem-create and database-seed enums, validate both through the wrapper and sanitizer, and inspect a fresh exact-head sanitized outcome. PR #6 remains draft and unmerged until required checks are green on one exact head.

---
*Phase: 06-recovery-proof-ci-and-e2e-pipeline*
*Completed: 2026-10-01*
