---
phase: 06-recovery-proof-ci-and-e2e-pipeline
plan: 23
subsystem: ci
tags: [linux-recovery, github-actions, sanitized-evidence, stage-attribution]
requires:
  - phase: 06-recovery-proof-ci-and-e2e-pipeline
    provides: "Plan 06-22 sanitized failure artifact and exact-head CI workflow."
provides:
  - "Distinct fixed source filesystem-create and PostgreSQL database-seed failure stages."
  - "Matching wrapper and sanitizer contracts with the unchanged four-field failure receipt."
  - "Exact-head hosted evidence locating the current Linux failure at the database-seed operation boundary."
  - "Stage-scoped Plan 06-24 for deeper database-seed diagnostics."
affects: [phase-06-recovery-ci, hosted-linux-restore, recovery-evidence]
actuals:
  tokens: 11862
  tasks: 3
  commits: 6
plan_head_before: fcc4a507dd7ca677fd6735f2c1d457260995016a
tech-stack:
  added: []
  patterns: ["Fixed operation-stage enums across producer, wrapper, and sanitizer.", "Exact-head hosted evidence is recorded from structured metadata plus one sanitized artifact."]
key-files:
  created:
    - .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-24-PLAN.md
  modified:
    - playstead-server/lib/mix/tasks/playstead.restore.ex
    - playstead-server/scripts/ci/recovery-fixture.sh
    - playstead-server/scripts/tests/recovery-fixture-test.sh
    - playstead-mac/scripts/ci/sanitize-evidence.sh
    - playstead-mac/scripts/ci/tests/sanitizer-test.sh
    - .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-HOSTED-EVIDENCE.md
    - .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-VERIFICATION.md
    - .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-23-SUMMARY.md
key-decisions:
  - "Keep the failure receipt's exact four-field schema and emit only a fixed stage enum."
  - "Treat source-fixture-database-seed as an operation boundary, not a root cause or restore pass."
  - "Keep PORT-04 and QUAL-02 open and scope further diagnosis in Plan 06-24."
patterns-established:
  - "Recovery failure markers are fixed, operation-owned, and validated by both wrapper and sanitizer."
  - "Hosted Linux failures stay red even when sanitized diagnostic evidence uploads successfully."
requirements-completed: []
duration: 108min
completed: 2026-10-02
status: complete
---

# Phase 06 Plan 23: Source Fixture Stage Attribution Summary

**The source fixture filesystem and PostgreSQL seed operations now have distinct safe stages, and exact-head CI locates the remaining Linux failure at database seeding without asserting a cause.**

## Performance

- **Duration:** 1h 48m 22s
- **Started:** 2026-10-02T03:44:53Z
- **Completed:** 2026-10-02T04:44:47Z
- **Tasks:** 3
- **Files modified:** 9

## Accomplishments

- Added `source-fixture-filesystem-create` and `source-fixture-database-seed` at their owning Mix operations; fake-command contracts verify each marker and ensure the retired shared token falls back to `unknown`.
- Carried the two fixed enums through the sanitizer while retaining duplicate-key rejection, sentinel checks, mutual exclusion of success/failure receipts, and the exact four-key failure schema.
- Completed synthetic wrapper and sanitizer checks, shell syntax, Mac static-contract checks, and whitespace validation without running the local app, Xcode/XCTest, Docker, a real restore, or private fixture data.
- Pushed exact-head SHA `dbe3f3802ba1a88b877c6144492835b9a87ea338`; workflow [36961936830](https://github.com/szTheory/playstead/actions/runs/36961936830) passed Docker job `110697303449`, server precommit job `110697303490`, and ordinary Mac job `110698990104`. Linux job `110697303338` failed only at restore; sanitization and sanitized evidence upload passed.
- Validated the sole downloaded sanitized receipt as one regular `recovery-failure.json`, with no duplicate keys and the unchanged four fields. Its stage was `source-fixture-database-seed`; this identifies an operation boundary only. Created stage-scoped Plan 06-24, and left PORT-04/QUAL-02 and all aggregate gates open.

## Task Commits

1. **Task 1 RED:** `b523ce9` — operation-owned source-stage contract.
2. **Task 1 GREEN:** `a148d1d` — split filesystem and database-seed markers.
3. **Task 2 RED:** `1b5b2a6` — sanitizer coverage for both replacement stages and rejection of the retired token.
4. **Task 2 GREEN:** `dbe3f38` — sanitizer accepts only the two new fixed stages.
5. **Task 3:** `ee29de0` — hosted outcome, verification record, and Plan 06-24.

The final documentation commit records this summary and the revised Plan 06-24; STATE.md and ROADMAP.md remain for the orchestrator to synchronize with the current phase position.

## Files Created/Modified

- `playstead-server/lib/mix/tasks/playstead.restore.ex` — operation-specific filesystem and database-seed markers.
- `playstead-server/scripts/ci/recovery-fixture.sh` — closed wrapper enum and synthetic self-test cases.
- `playstead-server/scripts/tests/recovery-fixture-test.sh` — source ownership and fake-command contracts.
- `playstead-mac/scripts/ci/sanitize-evidence.sh` — strict acceptance of the new stages.
- `playstead-mac/scripts/ci/tests/sanitizer-test.sh` — positive stage coverage and retired-stage rejection.
- `06-HOSTED-EVIDENCE.md` and `06-VERIFICATION.md` — exact SHA, run/job IDs, and sanitized database-seed outcome.
- `06-24-PLAN.md` — follow-up narrowed to the `source-fixture-database-seed` operation.

## Decisions Made

- Kept all public failure evidence fixed-enum and schema-bounded; raw Mix/psql output remains behind the existing private-output redirection.
- Recorded the hosted failure as red. Sanitizer and upload success do not convert a failed restore into a pass.
- Did not infer why the PostgreSQL fixture-seed command failed. Plan 06-24 adds a bounded database-connect probe to distinguish connectivity from seed SQL execution.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Added the missing regex import to the new source-stage contract.**
- **Found during:** Task 1 RED.
- **Issue:** The initial intentional-RED attempt stopped on a `NameError` because the new Python assertion used `re` without importing it.
- **Fix:** Imported `re`, reran the contract, and recorded a valid target-assertion RED before implementation.
- **Files modified:** `playstead-server/scripts/tests/recovery-fixture-test.sh`.
- **Verification:** `gsd_run check tdd-red-evidence` returned `RED_EVIDENCE_OK`; the subsequent wrapper contracts passed.
- **Committed in:** `b523ce9`.

**Total deviations:** 1 auto-fixed (Rule 1).
**Impact on plan:** None beyond making the planned ownership assertion executable.

## TDD Gate Compliance

- Task 1's source marker contract failed on the old shared producer marker, then passed after the two assignments were split.
- Task 2's sanitizer contract failed because the old sanitizer rejected the new filesystem stage, then passed after the closed enum update.
- Both RED records were validated as intentional target-test failures; no test framework or package was added.

## Checks Run

- `bash playstead-server/scripts/tests/recovery-fixture-test.sh` — passed (fake command only).
- `bash playstead-server/scripts/ci/recovery-fixture.sh --self-test` — passed.
- `bash -n playstead-server/scripts/ci/recovery-fixture.sh` — passed.
- `bash playstead-mac/scripts/ci/tests/sanitizer-test.sh` — passed, 122 positive/negative checks.
- `bash playstead-mac/scripts/ci/run-mac-verification.sh --self-test-contracts` — passed; all static contract guards passed.
- `git diff --check HEAD --` — passed.
- Hosted CI completed on the exact PR head. Docker, Mix precommit, and ordinary Mac passed. Linux restore failed at `Run isolated restore fixture`; sanitizer and upload succeeded. The sanitized receipt stage was `source-fixture-database-seed`.
- No raw GitHub logs or raw artifacts were inspected. No Playstead app, Xcode/XCTest, local Docker, real restore, or private fixture data was used.

## Issues Encountered

The exact-head Linux restore remains red at the source PostgreSQL fixture-seed operation. Its root cause is not established by the sanitized artifact. Plan 06-24 is the next scoped diagnostic; PR #6 remains draft and unmerged.

## User Setup Required

None.

## Next Phase Readiness

Plan 06-24 is awaiting revised plan review. It scopes a bounded connectivity probe separately from the existing seed SQL and preserves the current privacy boundary; execution must wait until its hosted verifier and exact-head evidence sequence pass review. A successful Plan23 diagnostic artifact does not close PORT-04, QUAL-02, entitlement, continuation, or phase aggregate requirements.

---
*Phase: 06-recovery-proof-ci-and-e2e-pipeline*
*Completed: 2026-10-02*

## Self-Check: PASSED
