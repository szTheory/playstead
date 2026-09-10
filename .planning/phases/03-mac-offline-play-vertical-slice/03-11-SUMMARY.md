---
phase: 03-mac-offline-play-vertical-slice
plan: 11
subsystem: adapter
tags: [bios, security, tdd, sqlite, concurrency, mac]

requires:
  - phase: 03-mac-offline-play-vertical-slice
    provides: BiosStore (03-09) with full byte-length + SHA-256 validation logic, but an empty production reference set
provides:
  - A real, two-independent-source-cited BIOS reference for the pinned gba system, pinned in 03-BIOS-PIN.json
  - BiosReferences.production wired into PlaysteadApp's composition root, closing the "no known reference" gap
  - A discriminator test proving a correctly-sized non-matching candidate is now refused for its contents, not for having no reference
  - An all-or-nothing BIOS drop under interruption and concurrency (init-time temp sweep, closed move race)
  - An operator one-command cross-check (scripts/verify-bios-reference.sh) and a fail-closed provenance guard (scripts/ci/tests/bios-pin-provenance-test.sh)
  - Honest updates to SUPPORT-MATRIX.md, 03-UAT.md item 13, and 03-VERIFICATION.md's first gaps entry (now resolved)
affects: [03-12 (notarization plan, untouched by this plan), any future plan touching BiosStore or the adapter readiness surface]

actuals:
  tokens: 42000
  tasks: 3
  commits: 4

tech-stack:
  added: []
  patterns:
    - "Reference-pin-with-provenance pattern (mirrors 03-ADAPTER-PIN.json's digest pin) reused for BIOS: a JSON pin file with a provenance array, a Swift literal mirror, and a parity test that fails if either side is edited alone."
    - "Init-time filesystem sweep keyed off a shared static prefix constant, so a writer and a sweeper can never drift into different naming schemes."

key-files:
  created:
    - .planning/phases/03-mac-offline-play-vertical-slice/03-BIOS-PIN.json
    - playstead-mac/Playstead/Adapter/BiosReferences.swift
    - playstead-mac/PlaysteadTests/AdapterTests/BiosProductionReferenceTests.swift
    - playstead-mac/scripts/verify-bios-reference.sh
    - playstead-mac/scripts/ci/tests/bios-pin-provenance-test.sh
  modified:
    - playstead-mac/Playstead/Adapter/BiosStore.swift
    - playstead-mac/Playstead/App/PlaysteadApp.swift
    - playstead-mac/PlaysteadTests/AdapterTests/BiosTests.swift
    - playstead-mac/docs/SUPPORT-MATRIX.md
    - .planning/phases/03-mac-offline-play-vertical-slice/03-UAT.md
    - .planning/phases/03-mac-offline-play-vertical-slice/03-VERIFICATION.md

key-decisions:
  - "Used the BIOS_REFERENCE_UNSOURCED blocker's resolution provided by the orchestrator verbatim: 16384-byte length, SHA-256 fd2547724b505f487e6dcb29ec2ecff3af35a841a77ab2e85fd87350abd36570, corroborated by higan's own docs, the DS-Homebrew wiki, and GBATEK — recorded no acquisition text anywhere."
  - "Split Task 1 into two literal commits (RED then GREEN): the RED commit adds the pin file and the test file only, with BiosReferences.swift deliberately not yet present, so the suite fails to compile ('Cannot find BiosReferences in scope') — a clean, unambiguous RED signal. The GREEN commit adds BiosReferences.swift, BiosStore.knownReferences, and the composition-root wiring together, making all 3 tests pass."
  - "Discovered and worked around three bugs in this plan's own <verify> commands (not in the implementation): (1) '-only-testing:PlaysteadTests/AdapterTests/BiosProductionReferenceTests' and (2) the equivalent for BiosTests both execute 0 tests in this Xcode project (the 'AdapterTests' folder segment is not part of the flat XCTest identifier scheme here) — a silent vacuous pass matching the exact failure mode the plan itself warns against; the corrected identifier omits the folder segment. (3) 'scripts/ci/run-mac-verification.sh --layers unit --only-testing ...' is rejected by the script itself ('targeted verification supports only rendering or ui', exit 1) — the unit layer must be run via plain xcodebuild, which is what this plan actually used throughout. Substituted the corrected commands for verification; documented rather than silently worked around."

patterns-established:
  - "A BIOS-style content-validation reference now has a template to follow for any future pinned system: JSON pin file with cited provenance, Swift literal mirror, and a parity test."

requirements-completed: [PLAY-03]

coverage:
  - id: D1
    description: "A BiosStore built the way the production composition root builds it now holds a real reference for gba, so a correctly-sized non-matching candidate is refused for its contents, not for having no reference at all."
    requirement: PLAY-03
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/AdapterTests/BiosProductionReferenceTests.swift#testStoreBuiltFromProductionReferencesReachesTheDigestComparison"
        status: pass
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/AdapterTests/BiosProductionReferenceTests.swift#testProductionReferenceSetIsNonEmptyAndWellFormed"
        status: pass
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/AdapterTests/BiosProductionReferenceTests.swift#testProductionLiteralsMatchThePinFile"
        status: pass
      - kind: other
        ref: "grep -v '^[[:space:]]*//' Playstead/App/PlaysteadApp.swift | grep -c 'references: BiosReferences.production' == 1"
        status: pass
    human_judgment: false
  - id: D2
    description: "Every pinned digest and byte length carries provenance from at least two independent citable public sources that agree; a fail-closed guard enforces this and has been observed failing on malformed input."
    requirement: PLAY-03
    verification:
      - kind: other
        ref: "playstead-mac/scripts/ci/tests/bios-pin-provenance-test.sh (positive check + 3 negative controls confirmed failing)"
        status: pass
    human_judgment: false
  - id: D3
    description: "The Swift reference literals and 03-BIOS-PIN.json cannot silently diverge."
    requirement: PLAY-03
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/AdapterTests/BiosProductionReferenceTests.swift#testProductionLiteralsMatchThePinFile"
        status: pass
    human_judgment: false
  - id: D4
    description: "The product still offers no BIOS acquisition, download, mirror, or source hint anywhere in code, UI copy, docs, or the pin file."
    requirement: PLAY-03
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/AdapterTests/BiosTests.swift#testBiosSourceFilesProvideNoAcquisitionPath"
        status: pass
      - kind: other
        ref: "grep -in url/http/download/obtain across verify-bios-reference.sh, bios-pin-provenance-test.sh, docs/SUPPORT-MATRIX.md — none found (comments describing the prohibition itself excluded)"
        status: pass
    human_judgment: false
  - id: D5
    description: "An interrupted or concurrent BIOS drop leaves no partial file in managed storage, no orphaned incoming temp file, and no more than one database row per accepted digest."
    requirement: PLAY-03
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/AdapterTests/BiosTests.swift#testConcurrentIdenticalDropsYieldOneManagedFileAndOneRow"
        status: pass
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/AdapterTests/BiosTests.swift#testConcurrentDistinctDropsBothSucceed"
        status: pass
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/AdapterTests/BiosTests.swift#testStaleIncomingTempIsSweptOnNextInitAndManagedFilesSurvive"
        status: pass
    human_judgment: false
  - id: D6
    description: "A rejected candidate leaves managed storage exactly as it was before the drop."
    requirement: PLAY-03
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/AdapterTests/BiosTests.swift#testRejectedCandidateLeavesManagedDirectoryUnchanged"
        status: pass
    human_judgment: false
  - id: D7
    description: "The BIOS drop surface renders the store's exact no-blame rejection reason as explanatory copy, never a blank pane and never a generic failure string (backstop truth, flagged unverified per the plan's own planner_assumptions — 03-UI-SPEC.md defines no state coverage for this surface)."
    human_judgment: true
    rationale: "03-UI-SPEC.md's own preamble excludes the BIOS drag-in surface from its state-coverage table (it says the 03-09 preflight/readiness surfaces define their own coverage when those plans run), so there is no locked contract to lift and re-verify against. BiosDropTargetView.statusView already renders BiosDropResult.rejected(reason:) as visible text (not a blank pane, not a generic string) per code inspection, but no snapshot/UI test asserts this for the BIOS surface specifically. Flagged, not silently dismissed, per this plan's planner_assumptions #2."

# Metrics
duration: ~50min
completed: 2026-09-10
status: complete
---

# Phase 3 Plan 11: BIOS Reference Sourced, Pinned, and Wired Summary

**A real, three-source-cited SHA-256 BIOS reference for the pinned `gba` system is now wired into `PlaysteadApp`'s composition root, closing Gap A: a correctly-sized dropped BIOS file is refused for its contents, not for having no reference at all — and the drop is now all-or-nothing under interruption and concurrency.**

## Performance

- **Duration:** ~50 min
- **Started:** 2026-09-10T19:03:00Z (approx.)
- **Completed:** 2026-09-10T19:24:30Z
- **Tasks:** 3
- **Files modified:** 11 (5 created, 6 modified)

## Accomplishments

- Sourced and pinned a real, two-independent-source-corroborated BIOS reference for `gba` (16384-byte length, SHA-256 `fd2547724b505f487e6dcb29ec2ecff3af35a841a77ab2e85fd87350abd36570`) in `03-BIOS-PIN.json`, with a three-source `provenance` array (higan docs, DS-Homebrew wiki, GBATEK).
- Wired `BiosReferences.production` into `PlaysteadApp`'s composition root via a genuine RED-then-GREEN commit pair, proven by `BiosProductionReferenceTests` (3/3 passing).
- Pinned the discriminating rejection-reason strings with regression tests, and shipped an operator one-command cross-check (`scripts/verify-bios-reference.sh`) plus a fail-closed provenance guard (`scripts/ci/tests/bios-pin-provenance-test.sh`, with 3 negative controls confirmed to actually fail).
- Made a BIOS drop all-or-nothing under interruption and concurrency: an init-time sweep of stale incoming-temp files (sharing one `incomingPrefix` constant with the writer) and a closed managed-file move race, proven by 4 new concurrency/interruption tests.
- Updated `docs/SUPPORT-MATRIX.md`, `03-UAT.md` item 13 (now `partial` with automated evidence, not `pass`), and `03-VERIFICATION.md`'s first gaps entry (now `status: resolved`) to state honestly what is proven automatically versus what remains operator-verified.

## Task Commits

Task 1 followed a genuine RED-then-GREEN TDD cycle (two commits); Tasks 2 and 3 were each committed atomically.

1. **Task 1 RED: add failing test for production BIOS reference wiring** - `0907ff5` (test)
2. **Task 1 GREEN: wire the production BIOS reference into the composition root** - `a8a91ac` (feat)
3. **Task 2: pin the discriminating reason strings and add an operator cross-check** - `a930305` (test)
4. **Task 3: make a drop all-or-nothing under interruption and concurrency, update docs** - `1d34282` (fix)

_Note: Task 1's RED commit deliberately fails to compile ("Cannot find 'BiosReferences' in scope") — confirmed via `xcodebuild test`, "** TEST FAILED **" — before the GREEN commit lands and all 3 tests pass._

## Files Created/Modified

- `.planning/phases/03-mac-offline-play-vertical-slice/03-BIOS-PIN.json` - The pinned gba reference with 3-source provenance
- `playstead-mac/Playstead/Adapter/BiosReferences.swift` - `BiosReferences.production`, mirroring the pin file
- `playstead-mac/Playstead/Adapter/BiosStore.swift` - `knownReferences` read seam, `incomingPrefix` constant + init-time sweep, closed move race
- `playstead-mac/Playstead/App/PlaysteadApp.swift` - Composition root now supplies `references: BiosReferences.production`
- `playstead-mac/PlaysteadTests/AdapterTests/BiosProductionReferenceTests.swift` - 3 tests proving the wiring
- `playstead-mac/PlaysteadTests/AdapterTests/BiosTests.swift` - 7 new tests (discriminator, wrong-length, symlink/directory, 2× concurrency, sweep, rejected-unchanged); 22 tests total (was 15)
- `playstead-mac/scripts/verify-bios-reference.sh` - Operator one-command cross-check, exits 0/2/3/4
- `playstead-mac/scripts/ci/tests/bios-pin-provenance-test.sh` - Fail-closed provenance guard with 3 negative controls
- `playstead-mac/docs/SUPPORT-MATRIX.md` - BIOS posture row states what's proven vs. operator-verified
- `.planning/phases/03-mac-offline-play-vertical-slice/03-UAT.md` - Item 13: `result: partial`, `source: automated` evidence block
- `.planning/phases/03-mac-offline-play-vertical-slice/03-VERIFICATION.md` - First gaps entry now `status: resolved`; notarization gap untouched

## Decisions Made

- Used the orchestrator-supplied BIOS_REFERENCE_UNSOURCED resolution verbatim (see `key-decisions` in frontmatter for the full provenance chain and citations). No acquisition text was carried across from any source.
- Split Task 1 into a genuine two-commit RED/GREEN pair rather than a single commit, satisfying the plan's explicit acceptance criterion that the commit history show the contents-mismatch test failing then passing.
- Reused the existing `03-ADAPTER-PIN.json` / `BiosTests.swift` fixture-and-analog conventions throughout rather than inventing new patterns.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug in plan's own `<verify>` commands] Three verification commands specified in `03-11-PLAN.md` do not work as written in this environment**
- **Found during:** Tracer feedback gate after Task 1, and again running Task 2/3 `<verify>` blocks
- **Issue:** (a) `xcodebuild test ... -only-testing:PlaysteadTests/AdapterTests/BiosProductionReferenceTests` and (b) the equivalent for `BiosTests` both silently execute **0 tests** ("Executed 0 tests, with 0 failures ... ** TEST SUCCEEDED **") — this Xcode project's flat XCTest identifier scheme does not include the `AdapterTests` folder segment, so the `-only-testing` filter matches nothing and the command reports a vacuous pass, exactly the failure mode the plan's own `<fails_when>` clause warns about ("a run executing 0 tests is exactly the vacuous pass this gap is made of"). (c) `scripts/ci/run-mac-verification.sh --layers unit --only-testing PlaysteadTests/AdapterTests/BiosProductionReferenceTests` is rejected outright by the script itself: `mac verification: targeted verification supports only rendering or ui` (exit 1) — the `--layers` flag's targeted mode only supports `rendering` and `ui`, never `unit`.
- **Fix:** Ran the corrected, semantically-equivalent commands instead: `xcodebuild test -scheme Playstead -destination 'platform=macOS,arch=arm64' -only-testing:PlaysteadTests/BiosProductionReferenceTests` (drops the `AdapterTests` segment) confirmed 3/3 passing; the equivalent for `PlaysteadTests/BiosTests` confirmed 22/22 passing; the unit layer was verified via plain `xcodebuild` (as the rest of this plan's own verification already did), not through `run-mac-verification.sh`'s targeted-layer mode.
- **Files modified:** None — this is a defect in the plan's verification text, not in shipped code. Not corrected in `03-11-PLAN.md` itself (plans are immutable); documented here and in `key-decisions` instead.
- **Verification:** All corrected commands re-run and their actual output quoted above and in the Self-Check section below.
- **Committed in:** N/A (no code change; documentation-only observation)

---

**Total deviations:** 1 auto-fixed (plan verification-text bug, worked around with corrected equivalent commands; no impact on shipped code).
**Impact on plan:** None on the delivered functionality — every acceptance criterion and the plan's overall `<verification>` block were independently confirmed via the corrected commands, including a full 629-test Unit test plan run (green) and a 3× repeated run of the new concurrency tests (stable, no flakiness observed).

## Issues Encountered

None beyond the three verify-command deviations documented above.

## User Setup Required

None - no external service configuration required. Real BIOS bytes cannot be acquired or tested by this product or in this environment by design; acceptance of a real, legally-owned file remains a one-command operator step (`scripts/verify-bios-reference.sh <path>`), tracked honestly as `partial`/not-`pass` in `03-UAT.md` item 13 rather than claimed complete.

## Next Phase Readiness

- Gap A from `03-VERIFICATION.md` is closed (`status: resolved`, `resolved_by: 03-11-PLAN.md`); PLAY-03 is now true in practice for the composition-root wiring, not just in unit tests against synthetic fixtures.
- `03-VERIFICATION.md` overall `status:` remains `gaps_found` — the notarization gap (second `gaps:` entry) is untouched and still open; `03-12-PLAN.md` owns it, as scoped.
- No blockers for `03-12`. CR-01/CR-02 remain recorded resolved (untouched by this plan, as scoped).

## Self-Check: PASSED

Files verified present on disk:
- FOUND: `.planning/phases/03-mac-offline-play-vertical-slice/03-BIOS-PIN.json`
- FOUND: `playstead-mac/Playstead/Adapter/BiosReferences.swift`
- FOUND: `playstead-mac/PlaysteadTests/AdapterTests/BiosProductionReferenceTests.swift`
- FOUND: `playstead-mac/scripts/verify-bios-reference.sh` (executable)
- FOUND: `playstead-mac/scripts/ci/tests/bios-pin-provenance-test.sh` (executable)

Commits verified in `git log --oneline`:
- FOUND: `0907ff5`, `a8a91ac`, `a930305`, `1d34282`

Acceptance criteria re-verified:
- `xcodebuild test ... -only-testing:PlaysteadTests/BiosProductionReferenceTests` → 3 tests, all pass.
- `xcodebuild test ... -only-testing:PlaysteadTests/BiosTests` → 22 tests, all pass (was 15 before this plan).
- `scripts/ci/tests/bios-pin-provenance-test.sh` → exit 0, "8 assertions ran against the real pin, all passed (plus 3 negative controls confirmed failing)".
- `grep -c 'status: resolved' 03-VERIFICATION.md` → 2 (BIOS gap + pre-existing CR-01/CR-02 entry).
- `grep -v '^[[:space:]]*//' PlaysteadApp.swift | grep -c 'references: BiosReferences.production'` → 1.
- Full Unit test plan (`xcodebuild test -testPlan Unit`) → 629 tests, 0 failures.
- No BIOS binary bytes committed; no URL/acquisition hint in any touched file (verified by grep and by `testBiosSourceFilesProvideNoAcquisitionPath`).

---
*Phase: 03-mac-offline-play-vertical-slice*
*Completed: 2026-09-10*
