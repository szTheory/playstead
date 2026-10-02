---
phase: 06-recovery-proof-ci-and-e2e-pipeline
plan: 20
subsystem: testing
tags: [mGBA, Libretro, macOS Seatbelt, continuation, recovery, evidence-sanitizer]

# Dependency graph
requires:
  - phase: 06-recovery-proof-ci-and-e2e-pipeline
    provides: Parent-owned continuation protocol, sanitizer, and public-workflow runner security correction
provides:
  - Synthetic-only mGBA capability result distinct from fixture continuation
  - Two fresh-root, fresh-process AerevenAdvance Continue runs with a title-to-map framebuffer oracle
  - Exact macOS process-execution allowlist for the private adapter and validated frontends
affects: [phase-06-continuation, macOS-recovery-evidence, mGBA-core-qualification]

# Actuals (#2632)
actuals:
  tokens: 10180
  tasks: 2
  commits: 4

# Tech tracking
tech-stack:
  added: []
  patterns: [synthetic-only qualification mode, exact process-execution allowlist, repeated cross-process framebuffer comparison]

key-files:
  created:
    - .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-20-PLAN.md
    - .planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-20-SUMMARY.md
  modified:
    - playstead-mac/docs/CONTINUATION-PROTOCOL.md
    - playstead-mac/scripts/ci/continuation_protocol.py
    - playstead-mac/scripts/ci/continuation-spike.sh
    - playstead-mac/scripts/ci/sanitize-evidence.sh
    - playstead-mac/scripts/ci/tests/continuation-process-double-test.py
    - playstead-mac/scripts/ci/tests/continuation-spike-test.sh
    - playstead-mac/scripts/ci/tests/sanitizer-test.sh

key-decisions:
  - "Keep synthetic capability qualification separate from fixture-backed oracle success."
  - "On macOS deny process execution by default and allow only validated runtime and frontend paths."
  - "Require a visible title-menu-to-map transition before accepting repeated framebuffer agreement."
  - "Add no package or runtime dependency; keep ROM, save, screenshots, and local hashes ignored."

patterns-established:
  - "A capability-only receipt is `qualification/qualified-only`; end-to-end fixture success remains `oracle/passed`."
  - "A fixture oracle captures the settled menu, applies deterministic input, requires a different in-game frame, then compares that frame after a fresh-process save reload."

requirements-completed: []

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "Synthetic-only capability validation has a distinct sanitized outcome and a fixture-blind parent path."
    verification:
      - kind: integration
        ref: "playstead-mac/scripts/ci/tests/continuation-spike-test.sh; qualification receipt 634398db-60f1-423d-9487-032ccdf12ce6"
        status: pass
    human_judgment: false
  - id: D2
    description: "Two isolated fixture runs resume to a stable in-game map frame after deterministic Continue input."
    verification:
      - kind: other
        ref: "private core-only runner; sanitized receipt 049db954-1ba3-4968-880f-e11d9426261e; private framebuffer visually inspected during execution"
        status: pass
    human_judgment: true
    rationale: "The automated oracle proves a visible transition and exact repeated frame; identifying the rendered screen as the map still relies on visual judgment. The private capture is intentionally not tracked."

# Metrics
duration: continued execution across prior turns; exact wall time not measured
completed: 2026-10-02
status: complete
---

# Phase 06 Plan 20: Continuation core qualification summary

**A synthetic-only mGBA capability gate and two contained AerevenAdvance runs now prove a visible Continue transition to the map with repeatable save reload.**

## Performance

- **Duration:** Continued execution across prior turns; exact wall time not measured
- **Started:** 2026-10-02 (time not recorded)
- **Completed:** 2026-10-02
- **Tasks:** 2
- **Files modified:** 7 tracked files, plus this plan and summary

## Accomplishments

- Added `--qualify-only`, which performs the normal contract, recovery-receipt, containment, and network-denial preflights, runs only the synthetic `qualify` action, and returns `qualification/qualified-only` without looking up fixture configuration.
- Tightened macOS child execution: process execution is denied by default; the profile permits only the validated adapter, required Python runtime chain, and validated adjacent frontends. Empty input pipes avoid opening `/dev/null` under write confinement.
- Ran two independent fixture cycles, each with an empty save root and fresh frontend/core processes. The harness captures the settled Continue menu, presses A at frames 300–305, requires a different stable in-game frame, and confirms a fresh process reloads and reproduces that map frame.
- Kept mGBA source/build products, the owner-supplied ROM and save, screenshots, and hashes in ignored private storage. No dependency, Playstead app run, XCTest run, or account/pairing flow was added.

## Task Commits

1. **Task 1: Prove core control and framebuffer oracle with generated content** — `16e3605` (`fix`)
2. **Task 2: Run two private fixture continuations through the qualified core** — `8875177` (`docs`)

**Plan metadata:** `e40493c` (`docs: record continuation qualification plan`).

## Files Created/Modified

- `.planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-20-PLAN.md` — execution plan and bounded acceptance criteria.
- `playstead-mac/docs/CONTINUATION-PROTOCOL.md` — narrow verified core/fixture outcome and limitations.
- `playstead-mac/scripts/ci/continuation_protocol.py` — fixture-blind qualification mode, independent roots, and macOS executable allowlist.
- `playstead-mac/scripts/ci/continuation-spike.sh` and `sanitize-evidence.sh` — expose and validate the distinct synthetic-only receipt.
- `playstead-mac/scripts/ci/tests/continuation-process-double-test.py`, `continuation-spike-test.sh`, and `sanitizer-test.sh` — cover process order, isolation rules, and exact receipt pairings.
- `.planning/phases/06-recovery-proof-ci-and-e2e-pipeline/06-20-SUMMARY.md` — this execution record.

## Decisions Made

- Synthetic capability success uses `qualification/qualified-only`; only the fixture-backed path can produce `oracle/passed`.
- macOS process execution is denied by default and granted only to validated runtime and adjacent frontend executables.
- Frame agreement counts only after a distinct post-Continue game frame is observed; a title-menu-to-title-menu match is rejected.
- No package or runtime dependency was added. Fixture artifacts remain in ignored local storage.

## Verification

- `scripts/ci/tests/continuation-spike-test.sh` — passed, including process doubles, fixture-blind qualification, independent roots, and Seatbelt allowlist assertions.
- `scripts/ci/tests/sanitizer-test.sh` — passed, 131 positive/negative checks.
- Shell syntax, Python AST parsing, and `git diff --check` — passed.
- Synthetic qualification receipt: `qualification/qualified-only`, run ID `634398db-60f1-423d-9487-032ccdf12ce6`.
- Fixture receipt: `oracle/passed`, run ID `049db954-1ba3-4968-880f-e11d9426261e`.
- The private framebuffer was visually inspected and showed the world map; it was not copied into tracked evidence.
- Hosted CI is the merge gate; the PR carries exact-head checks. No local Playstead/XCTest suites were run.

## Deviations from Plan

An initial framebuffer equality check passed while displaying the title menu in both processes. Visual inspection exposed that false positive. The private fixture harness now waits for the title screen to settle, captures it before input, rejects a post-input frame that remains on the menu, and compares the in-game frame across fresh processes. The corrected two-root run passed.

**Total deviations:** 1 corrective refinement.
**Impact:** Necessary to make the visible-state oracle prove resumed gameplay rather than repeatable menu rendering; scope and dependency count stayed unchanged.

## Issues Encountered

macOS denied nested `sandbox-exec` under the workspace sandbox (`status 71`). The authorized elevated execution path was used for the harmless containment probe and the bounded qualification/fixture commands; all passed. No raw fixture content or process output was added to the repository.

## User Setup Required

None. The existing private fixture and local recovery receipt were reused; no account, pairing, signing, or dependency setup was needed.

## Scope and next work

This proves a narrow local path: official mGBA 0.10.5 Libretro core plus the registered AerevenAdvance fixture under parent-owned isolation. It does not qualify the Qt frontend, Playstead's shipped emulator adapter, arbitrary games, or close all of PORT-04/QUAL-02. The remaining Phase 06 gap plans and release/security gates remain open.

## Next Phase Readiness

Plan 06-20's bounded continuation oracle is complete. Create a PR and require all exact-head hosted CI checks to pass before squash merge. Resume `$gsd-execute-phase 06 --gaps-only` afterward to reconcile the phase's remaining hosted evidence, entitlement, and aggregate verification gates.

---
*Phase: 06-recovery-proof-ci-and-e2e-pipeline*
*Completed: 2026-10-02*
