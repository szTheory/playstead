---
phase: 04-persistent-save-continuity
plan: 01
subsystem: infra
tags: [swift, mmap, apfs, fsevents, probe, unittest]

requires:
  - phase: 03-mac-offline-play-vertical-slice
    provides: "03-SPIKE-REPORT.md's ~24s flush cadence and watch-save.sh's 1 Hz poller shape, which SAVE-P1 extends into a fuller measurement harness"
provides:
  - "SAVE-P1 probe harness (save-p1-probe.swift + run-save-p1-probe.sh) that measures inode stability, mtime fidelity, FSEvents/vnode event delivery, and post-death writeback for a MAP_SHARED writer on APFS"
  - "A schema-guarded, pinned 04-SAVE-P1-REPORT.json/.md citable by plans 04-04, 04-06, and 04-12"
affects: [04-04, 04-06, 04-12]

actuals:
  tokens: 11074
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Single-file `swift <script>.swift` probes with no Xcode target, following the spike's throwaway-harness convention but built as production-quality evidence"
    - "stdlib unittest validator with a shared validate_report() function reused by both happy-path and negative (deleted-key) test cases"

key-files:
  created:
    - playstead-mac/scripts/probes/save-p1-probe.swift
    - playstead-mac/scripts/probes/run-save-p1-probe.sh
    - playstead-mac/scripts/ci/tests/test_save_p1_probe.py
    - .planning/phases/04-persistent-save-continuity/04-SAVE-P1-REPORT.json
    - .planning/phases/04-persistent-save-continuity/04-SAVE-P1-REPORT.md
  modified: []

key-decisions:
  - "Combined inode_stability and mtime_fidelity measurement into one shared set of mutation rounds (both need the same fstat/digest samples per round), rather than running two separate passes over the artifact"
  - "post_death_writeback spawns the writer child as a fresh `swift <script> --writer-child <path>` process rather than a raw fork(), avoiding Swift runtime/fork interaction hazards while still producing a real independent process to SIGKILL"

requirements-completed: [SAVE-01]

coverage:
  - id: D1
    description: "Probe harness measures inode stability, mtime fidelity, FSEvents/vnode event delivery, and post-death writeback for a MAP_SHARED writer on APFS, emitting one schema-valid JSON report"
    requirement: "SAVE-01"
    verification:
      - kind: other
        ref: "cd playstead-mac && swift scripts/probes/save-p1-probe.swift | python3 -c \"...\" (plan Task 1 <verify>)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Pinned 04-SAVE-P1-REPORT.json is schema-guarded by a stdlib unittest validator with a negative case per required key"
    requirement: "SAVE-01"
    verification:
      - kind: unit
        ref: "playstead-mac/scripts/ci/tests/test_save_p1_probe.py (30 tests, all pass)"
        status: pass
    human_judgment: false
  - id: D3
    description: "mgba_observed defaults to false and both the JSON and the human-readable .md name CP7-SAVE-C (plan 04-12) as the carrier of the real-emulator confirmation"
    requirement: "SAVE-01"
    verification:
      - kind: other
        ref: "grep -c mgba_observed 04-SAVE-P1-REPORT.md; python3 assertion on JSON field"
        status: pass
    human_judgment: false

duration: 25min
completed: 2026-09-03
status: complete
---

# Phase 4 Plan 01: SAVE-P1 Probe (D-02) Summary

**A single-file Swift probe measures inode stability, mtime fidelity, FSEvents/vnode event delivery, and post-death writeback for a MAP_SHARED writer on APFS, replacing four inferences with recorded numbers in a schema-guarded, pinned report.**

## Performance

- **Duration:** 25 min
- **Started:** 2026-09-03T23:32:39Z
- **Completed:** 2026-09-03T23:41:24Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Built `save-p1-probe.swift`, a self-contained Swift script (no Xcode target) that creates its own temp directory, runs a synthetic 32,768-byte `MAP_SHARED` writer through five mutation rounds, and emits one JSON report with `inode_stability`, `mtime_fidelity`, `event_delivery`, and `post_death_writeback` measurements plus an optional read-only `--mgba-artifact` observer mode
- Built `run-save-p1-probe.sh`, a thin POSIX wrapper writing the probe's stdout to the pinned phase-4 evidence path
- Ran the probe on this Mac and committed the resulting `04-SAVE-P1-REPORT.json`, plus a human-readable `04-SAVE-P1-REPORT.md` explaining each measurement in prose and stating explicitly that D-01's polling trigger and D-03's quiescence rule are unchanged
- Wrote `test_save_p1_probe.py`, a stdlib `unittest` module (30 tests) that validates the pinned report's schema and includes a negative case per required key, proving a truncated report cannot pass

## Task Commits

1. **Task 1: Measure one mmap writer end-to-end and emit one report** - `53c47c4` (feat)
2. **Task 2: Pin the report and guard its schema** - `caa7599` (test)

## Files Created/Modified
- `playstead-mac/scripts/probes/save-p1-probe.swift` - Single-file Swift probe harness with four measurement stages and an optional read-only mGBA observer mode
- `playstead-mac/scripts/probes/run-save-p1-probe.sh` - Thin wrapper writing the probe's JSON to the pinned report path
- `playstead-mac/scripts/ci/tests/test_save_p1_probe.py` - stdlib unittest schema validator with per-key negative cases
- `.planning/phases/04-persistent-save-continuity/04-SAVE-P1-REPORT.json` - Pinned measurement report from a run on this Mac
- `.planning/phases/04-persistent-save-continuity/04-SAVE-P1-REPORT.md` - Human-readable companion, naming CP7-SAVE-C as the real-emulator carrier

## Decisions Made
- Combined the inode-stability and mtime-fidelity measurements into one shared set of rounds since both need the same per-round fstat + digest sample, avoiding a redundant second pass over the artifact
- Spawned the post-death-writeback writer child as a fresh `swift <script> --writer-child <path>` process (not a raw POSIX `fork()`), avoiding any Swift-runtime/`fork()` interaction hazard while still producing an independently-killable process

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Probe SAVE-P1 has run and its measurements (all four stages, this host: inode-stable, mtime-faithful, events observed, no post-death writeback in a 10s window) are pinned and schema-guarded, citable by plans 04-04, 04-06, and 04-12.
- The real-emulator half of the measurement (a live mGBA process against real game bytes) remains explicitly unproven here (`mgba_observed: false`) and is carried forward as blocked checkpoint CP7-SAVE-C in plan 04-12 — this is expected, not a gap in this plan.
- Ready for 04-02.

## Self-Check: PASSED

- `[ -f playstead-mac/scripts/probes/save-p1-probe.swift ]` → FOUND
- `[ -f playstead-mac/scripts/probes/run-save-p1-probe.sh ]` → FOUND
- `[ -f playstead-mac/scripts/ci/tests/test_save_p1_probe.py ]` → FOUND
- `[ -f .planning/phases/04-persistent-save-continuity/04-SAVE-P1-REPORT.json ]` → FOUND
- `[ -f .planning/phases/04-persistent-save-continuity/04-SAVE-P1-REPORT.md ]` → FOUND
- `git log --oneline --all | grep -q 53c47c4` → FOUND
- `git log --oneline --all | grep -q caa7599` → FOUND
- All plan-level `<verification>` commands re-run above: PASS

---
*Phase: 04-persistent-save-continuity*
*Completed: 2026-09-03*
