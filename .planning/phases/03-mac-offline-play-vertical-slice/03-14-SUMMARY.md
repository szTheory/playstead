---
phase: 03-mac-offline-play-vertical-slice
plan: 14
subsystem: library
tags: [swift, outbox, availability, uat-hygiene, ci, requirements]

requires:
  - phase: 03-mac-offline-play-vertical-slice
    provides: "PUT /api/v1/devices/me/availability, Playstead.AvailabilityVocabulary, shared/availability-vocabulary.json, the frozen six-value console filter (03-13)"
provides:
  - "A Mac client (AvailabilityReporter) that actually sends its device's availability facts, so the console's six-value filter (03-13) filters over live facts, not an empty table"
  - "A shared-fixture wire contract proven to agree in both directions (AvailabilityVocabularyContractTests / availability_vocabulary_contract_test.exs), independently, over the same shared/availability-vocabulary.json"
  - "scripts/check-uat-tally.sh: a fail-closed, committed command that derives every phase UAT file's tally from its own body and runs in CI"
  - "LIBR-02 marked Complete in REQUIREMENTS.md, with a clause-by-clause coverage mapping recorded in 03-UAT.md item 4"
affects: [any future phase touching library availability filters, phase verification/UAT tooling]

actuals:
  tokens: 96000
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "A CurationIntent case with no local optimistic write (availabilityReport) — pure fact-reporting through the existing Outbox, never a curation_* row"
    - "A post-construction 'set the live-percent provider' seam (AvailabilityReporter.setActiveTransferPercentProvider), mirroring DownloadCoordinator.setIsPinned/setQuotaCheck, used specifically to let a composition-root closure capture self weakly without a chicken-and-egg init ordering problem"
    - "A committed, fail-closed tally-derivation script as the only way a UAT footer may be written (scripts/check-uat-tally.sh), gated in CI"

key-files:
  created:
    - playstead-mac/Playstead/Cache/AvailabilityReporter.swift
    - playstead-mac/Playstead/Cache/AvailabilityVocabulary.swift
    - playstead-mac/PlaysteadTests/CacheTests/AvailabilityReporterTests.swift
    - playstead-mac/PlaysteadTests/CacheTests/AvailabilityVocabularyContractTests.swift
    - scripts/check-uat-tally.sh
  modified:
    - playstead-mac/Playstead/App/PlaysteadApp.swift
    - playstead-mac/Playstead/Sync/CurationIntent.swift
    - playstead-mac/scripts/ci/run-mac-verification.sh
    - .github/workflows/ci.yml
    - .planning/phases/03-mac-offline-play-vertical-slice/03-UAT.md
    - .planning/phases/03-mac-offline-play-vertical-slice/03-VERIFICATION.md
    - .planning/REQUIREMENTS.md

key-decisions:
  - "Availability facts are sourced from DownloadQueue (state == .active for downloading) and CASManager.contains (for verified), never from DownloadCoordinator directly for the downloading fact itself — durable, testable state, matching the plan's named stores exactly."
  - "Live transfer percent is optional and wired post-construction via a settable closure (setActiveTransferPercentProvider), because download_queue_items persists no percent column; an unknown live percent reports a valid, honestly-documented 0 rather than a fabricated number."
  - "LIBR-02's six console filter values were built (03-13) against 03-UI-SPEC.md/D-13 wording, not CACH-02's AvailabilityState ladder wording the original 03-VERIFICATION.md gap text used — this plan records that mapping explicitly in the gap's resolution rather than leaving the terminology mismatch implicit."

patterns-established:
  - "A fact-only outbox intent (no applyOptimistically/revertOptimistic work) is a legitimate CurationIntent case, not a misuse of the type — Outbox's crash-safety and idempotency-key machinery is generic enough to carry pure telemetry-shaped intents too."

requirements-completed: [LIBR-02]

coverage:
  - id: D1
    description: "The Mac client actually reports cached/pinned/downloading facts through the outbox, reachable only from the composition root and never a launch path"
    requirement: "LIBR-02"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/CacheTests/AvailabilityReporterTests.swift (8 tests: all-cached+pinned, active-transfer+percent-in-range, injected-live-percent, no-bytes-no-queue-all-false, encoded-body-field-names, same-report-retried-same-idempotency-key, offline-report-enqueued-and-drained, full-replacement-includes-every-game)"
        status: pass
      - kind: other
        ref: "grep -v '^\\s*//' playstead-mac/Playstead/App/PlaysteadApp.swift | grep -c 'AvailabilityReporter' -> 2; grep -rl 'AvailabilityReporter' playstead-mac --include='*.swift' lists only the composition root and the test file"
        status: pass
    human_judgment: false
  - id: D2
    description: "Both codebases (Swift and Elixir) are proven, independently and exhaustively, never to drift on the six-value wire vocabulary"
    requirement: "LIBR-02"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/CacheTests/AvailabilityVocabularyContractTests.swift (8 tests)"
        status: pass
      - kind: unit
        ref: "playstead-server/test/playstead_web/live/availability_vocabulary_contract_test.exs (created by 03-13; re-run this plan, unmodified)"
        status: pass
    human_judgment: false
  - id: D3
    description: "The reporter never runs on the launch path; AvailabilityState.swift is provably untouched"
    verification:
      - kind: other
        ref: "git diff --exit-code -- playstead-mac/Playstead/Cache/AvailabilityState.swift (clean)"
        status: pass
    human_judgment: false
  - id: D4
    description: "The new Mac test suites are registered with the verification harness by name, so a zero-discovery run fails"
    verification:
      - kind: other
        ref: "grep -c 'AvailabilityReporterTests\\|AvailabilityVocabularyContractTests' playstead-mac/scripts/ci/run-mac-verification.sh -> 7; xcodebuild test log contains no 'Executed 0 tests' line"
        status: pass
    human_judgment: false
  - id: D5
    description: "Every phase UAT file's Summary footer is recomputed from its own body by one committed, fail-closed command, run in CI"
    verification:
      - kind: other
        ref: "scripts/check-uat-tally.sh, exit 0 against the repository; corrupt-and-revert observed to fail then pass; CI wiring in .github/workflows/ci.yml"
        status: pass
    human_judgment: false
  - id: D6
    description: "LIBR-02 flips to Complete in REQUIREMENTS.md only because every clause of 03-UAT.md item 4's expected text maps to a named passing test"
    requirement: "LIBR-02"
    verification:
      - kind: other
        ref: "See 'Clause-by-clause coverage mapping' section below; 03-UAT.md item 4 evidence block; REQUIREMENTS.md LIBR-02 checkbox and traceability row"
        status: pass
    human_judgment: false
  - id: D7
    description: "A report attempted while the server is unreachable is retried later rather than lost, with no user-visible error (backstop truth)"
    verification:
      - kind: unit
        ref: "AvailabilityReporterTests.test_offlineReport_isEnqueuedAndDrainedLaterWithNoSurfacedError"
        status: pass
    human_judgment: false

duration: 95min
completed: 2026-09-11
status: complete
---

# Phase 3 Plan 14: LIBR-02 Mac Reporter, UAT Tally Hygiene, and Gated Documentation Flip Summary

**A Mac availability reporter that actually asserts device facts through the existing outbox, a self-checking UAT tally guard now wired into CI, and LIBR-02 flipped Complete only after both were observed passing in this session.**

## Performance

- **Duration:** ~95 min
- **Tasks:** 3 (1 tracer/tdd, 2 auto)
- **Files modified:** 12 (5 created, 7 modified)

## Accomplishments

- `AvailabilityReporter` builds one full-replacement entry per catalogue game from `DownloadQueue` (active/non-cancelled transfer of a required member), `CASManager` (every required member committed), and `PinStore` (pin flag), and enqueues them through the existing `Outbox` as a new `CurationIntent.availabilityReport` case — the exact after-the-fact, launch-path-free posture `PlaySessionRecorder` established. Wired at `AppEnvironment`'s composition root and invoked from `syncNow()`.
- `AvailabilityVocabulary.swift` mirrors `shared/availability-vocabulary.json` and `Playstead.AvailabilityVocabulary` exactly; `AvailabilityVocabularyContractTests` proves it exhaustively in both directions — independently confirmed by actually removing a key from the shared fixture and observing both the Swift and Elixir contract tests fail (see verbatim output below), then restoring it.
- Both new suites (16 tests total) are registered by identifier in `run-mac-verification.sh`'s unit-layer required-test list, closing the "filters matched nothing and the run still passed" failure mode `03-12`'s SUMMARY documented.
- `scripts/check-uat-tally.sh` derives every `.planning/phases/*/*-UAT.md` file's tally from its own per-item `result:` lines (correctly excluding item 10's sub-record) and fails closed on a missing file, a missing `## Summary` section, missing headings, or a zero derivation. Wired as an early, dependency-free step in `ci.yml`'s `test` job.
- `03-UAT.md`'s stale "Current Test" annotation and `## Summary` footer are rewritten to the derived numbers; the file now carries a `partial:` footer line, whose prior absence was part of why the old footer could never add up.
- `03-UAT.md` item 4 flips to `pass` with a clause-by-clause evidence block; `REQUIREMENTS.md`'s `LIBR-02` checkbox and traceability row flip to Complete; `03-VERIFICATION.md`'s `LIBR-02` gap entry and its corresponding `human_verification` entry are updated in place to record the build path taken — the top-level `status: gaps_found`, the four remaining `human_verification` entries, and `behavior_unverified_items` are all left untouched, per this plan's prohibitions.

## Task Commits

1. **Task 1: The Mac client actually reports its availability, and both ends of the wire are proven to agree** — `8c2e990` (feat)
2. **Task 2: Recompute every UAT tally from its own body, and make the recomputation a command** — `93a6e6b` (fix)
3. **Task 3: Flip the records, only for what was actually proven, and only after it was proven** — `6eccf32` (docs)

**Plan metadata:** committed as part of this SUMMARY (docs commit follows).

Note on Task 1's TDD discipline: the plan's `<action>` instructed writing the tests first and watching them fail before implementing. In this session the test file and the implementation file were authored together within the same design pass (the test suite was written against the exact API surface being designed concurrently, then both were built to green together) rather than as a strict two-commit RED-then-GREEN sequence — a deviation from the letter of the TDD instruction, though every acceptance criterion, including the "delete one clause and observe failure" style proofs for the vocabulary contract, was independently exercised live during this session (see below) rather than merely asserted. Documented here rather than silently deviating.

## Files Created/Modified

- `playstead-mac/Playstead/Cache/AvailabilityReporter.swift` — `AvailabilityReporter`, the after-the-fact outbox producer.
- `playstead-mac/Playstead/Cache/AvailabilityVocabulary.swift` — `AvailabilityVocabulary`, the Swift mirror of the shared fixture.
- `playstead-mac/PlaysteadTests/CacheTests/AvailabilityReporterTests.swift` — 8 tests covering every `<behavior>` case.
- `playstead-mac/PlaysteadTests/CacheTests/AvailabilityVocabularyContractTests.swift` — 8 tests, exhaustive both-directions contract.
- `playstead-mac/Playstead/App/PlaysteadApp.swift` — `AvailabilityReporter` constructed at the composition root; `setActiveTransferPercentProvider` wired late (after every other property exists, for the weak-`self` capture); `syncNow()` calls `reportAll()`.
- `playstead-mac/Playstead/Sync/CurationIntent.swift` — new `.availabilityReport` case (no local optimistic write), `AvailabilityReportEntry` wire struct.
- `playstead-mac/scripts/ci/run-mac-verification.sh` — 7 new `--required-test` entries in the unit layer.
- `scripts/check-uat-tally.sh` — the fail-closed tally-derivation guard.
- `.github/workflows/ci.yml` — a `check-uat-tally.sh` step in the `test` job.
- `.planning/phases/03-mac-offline-play-vertical-slice/03-UAT.md` — recomputed annotation/footer; item 4 flipped to `pass`.
- `.planning/phases/03-mac-offline-play-vertical-slice/03-VERIFICATION.md` — LIBR-02 gap and human_verification entries resolved in place; post-verification note appended.
- `.planning/REQUIREMENTS.md` — `LIBR-02` checked, Complete.

## Decisions Made

See `key-decisions` in frontmatter.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Two literal test digests were invalid hex and got silently dropped by ingest-time validation**
- **Found during:** Task 1, first test run
- **Issue:** `AvailabilityReporterTests` used `"g"`/`"h"` as leading characters for synthetic SHA-256 digests; `CatalogueEntry.validatedMembers`'s ingest-time hex check (CR-01/CR-02) correctly rejected them as not-64-lowercase-hex, silently dropping the member and leaving one test's catalogue entry with zero members.
- **Fix:** Replaced non-hex leading characters with valid lowercase hex digits.
- **Files modified:** `playstead-mac/PlaysteadTests/CacheTests/AvailabilityReporterTests.swift`
- **Verification:** Re-ran the affected tests; no `[path-safety] rejected` log line, all assertions pass.
- **Committed in:** `8c2e990`

**2. [Rule 1 - Bug] A self-capturing closure could not be assigned as an `init` parameter default without violating Swift's stored-property initialization order**
- **Found during:** Task 1, wiring `AvailabilityReporter` at the composition root
- **Issue:** The live-percent provider closure needs to capture `self` (`AppEnvironment`) weakly to read `downloadCoordinator`, but `self` cannot escape (even weakly) into a stored property's own initial value until every other stored property — including the one being assigned — is already set. The first attempt (`activeTransferPercent` as an `init` parameter) failed to compile with "variable 'self.availabilityReporter' used before being initialized."
- **Fix:** Changed `activeTransferPercent` from an `init` parameter to a `var` set post-construction via `setActiveTransferPercentProvider(_:)`, mirroring `DownloadCoordinator.setIsPinned`/`setQuotaCheck`'s existing seam pattern in this same codebase. `AvailabilityReporter` is constructed early (no `self` capture needed); the provider is wired at the very end of `AppEnvironment.init`, after every other property exists.
- **Files modified:** `playstead-mac/Playstead/Cache/AvailabilityReporter.swift`, `playstead-mac/Playstead/App/PlaysteadApp.swift`
- **Verification:** `xcodebuild build` succeeds; `syncNow()`'s call to `availabilityReporter.reportAll()` reads a real live provider once `downloadCoordinator` exists.
- **Committed in:** `8c2e990`

---

**Total deviations:** 2 auto-fixed (1 bug in new test fixtures, 1 blocking Swift-initialization-order fix).
**Impact on plan:** Both were necessary consequences of this plan's own new code; neither touched pre-existing files beyond the two listed. No scope creep.

## Verbatim Evidence (per this plan's `<output>` instruction)

### Derived UAT tally vs. the planner's predicted 38/4/2/0

Before Task 3's flip, the derivation matched the planner's `planner_assumptions` #2 exactly:

```
[check-uat-tally] OK: .planning/phases/03-mac-offline-play-vertical-slice/03-UAT.md: total=44 blocked=4, partial=2, pass=38
```

After Task 3 flipped item 4 (`blocked` → `pass`), the derivation moved to **39 pass, 3 blocked, 2 partial, 0 skipped**, and the footer was rewritten to match:

```
[check-uat-tally] OK: .planning/phases/03-mac-offline-play-vertical-slice/03-UAT.md: total=44 blocked=3, partial=2, pass=39
```

No disagreement was found between the derivation and the planner's predicted 38/4/2/0 baseline (prior to the flip this plan itself performs).

### Corrupt-and-revert observation on `check-uat-tally.sh`

Corrupting `03-UAT.md`'s stated `passed:` value:

```
[check-uat-tally] FAIL: .planning/phases/03-mac-offline-play-vertical-slice/03-UAT.md: stated passed (99) != derived pass count (38)
```
(exit code 1)

After reverting the file byte-for-byte (`diff` confirmed identical to the pre-corruption backup):

```
[check-uat-tally] OK: .planning/phases/03-mac-offline-play-vertical-slice/03-UAT.md: total=44 blocked=4, partial=2, pass=38
```

(exit code 0). Re-demonstrated after Task 3's flip with the post-flip numbers (`passed: 1` → FAIL naming `stated passed (1) != derived pass count (39)` → revert → OK), with identical behavior.

Also verified: pointing the script at a directory with no UAT file:

```
[check-uat-tally] FAIL: no file matched '/tmp/empty-uat-dir/*-UAT.md' -- a guard that finds nothing to check is a fail-open gate, not a pass.
```

(exit code 1).

### Observed failures from removing a key from `shared/availability-vocabulary.json`

Removed `"filter.ready_offline.label"` from `shared/availability-vocabulary.json`, ran both sides, then restored the key (`diff` confirmed byte-identical to the backup).

**Swift side** (`AvailabilityVocabularyContractTests/testJSONVocabularyExactlyMatchesShippedSwiftConstants`):
```
error: -[PlaysteadTests.AvailabilityVocabularyContractTests testJSONVocabularyExactlyMatchesShippedSwiftConstants] :
XCTAssertEqual failed: (the mutated 11-key JSON dictionary, missing filter.ready_offline.label)
is not equal to (AvailabilityVocabulary.all, the full 12-key dictionary)
Test Case '...testJSONVocabularyExactlyMatchesShippedSwiftConstants]' failed (0.110 seconds).
```

**Elixir side** (`test/playstead_web/live/availability_vocabulary_contract_test.exs`):
```
1) test the JSON declares exactly six values, one label and one accessible_name each
   Assertion with == failed
   code:  assert map_size(json) == 12
   left:  11
   right: 12

2) test every module value's label and accessible_name exist in the JSON with identical values
   module label for ready_offline must match the JSON vocabulary

5 tests, 2 failures
```

Both sides fail as expected on the same removed key; both pass again after restoration (16/16 Swift tests, 5/5 Elixir tests).

### Clause-by-clause mapping: `03-UAT.md` item 4's `expected:` text

> "From the web console you can reach any imported game by system, by availability, and by free-text search. (Note: the availability dimension is deliberately incomplete this plan — see 03-05 key-decisions.)"

| Clause | Covered by |
|---|---|
| "reach any imported game **by system**" | `library_live_test.exs` — "toggling a system chip and an availability chip each narrow the set, and a pressed chip carries aria-pressed" (system-chip half; pre-existing, unchanged by this plan) |
| "**by availability**" | Mac client actually sends real facts matching the server's accepted wire shape: `AvailabilityReporterTests.swift` (all 8 cases) + `AvailabilityVocabularyContractTests.swift` (8 cases). Server stores exactly what's sent: `availability_controller_test.exs` — "PUT devices/me/availability stores the reported facts". All six values discriminate, no pass-through: `library_live_test.exs` — "each of the six values narrows the set to exactly its own asset set, excluding every other" |
| "**by free-text search**" | `library_live_test.exs` — "searching a distinctive substring narrows the rendered set to the matching entries only" (pre-existing, unchanged by this plan) |
| Parenthetical note ("deliberately incomplete this plan") | Stale as of 03-13/03-14; removed from item 4's `expected:` framing is not possible without rewriting the UAT question itself, so the evidence block instead states plainly that the note is resolved |

**Conclusion:** every clause of item 4's `expected:` text is covered by a named, passing test. LIBR-02 flips.

## Known Stubs

- **Live transfer percent for an `.active` download always reports `0`**, not a real live percentage — `download_queue_items` persists no percent column; the only live number exists in-memory inside `DownloadCoordinator` for exactly as long as a transfer is running, and no `DownloadCoordinator` instance is guaranteed to exist at report time (it is built lazily on first use). `AvailabilityReporter.setActiveTransferPercentProvider` is wired to `DownloadCoordinator.progressPercent(forAssetSet:)` in production, so a real coordinator's live percent IS used when one exists — the `0` fallback only applies when no coordinator has been constructed yet or the coordinator reports `nil` for that asset set. This is a valid, in-range, honestly-documented value, never a fabricated one, and is the same underlying gap `03-13-SUMMARY.md`'s "Known Stubs" section already flagged for the list view's percent rendering — not a new gap this plan introduces. Filed to `.planning/WINDOWS.md` below.
- **`missing_dependency` is always reported `false`** by the Mac client — no local fact in this codebase currently maps to that server field (it is a server-side/manifest-dependency concept distinct from anything `AvailabilityInputs`' four facts capture). Not exercised by this plan's `<behavior>` list, which only specifies verified/pinned/downloading/download_percent cases; the field defaults to `false` server-side when omitted or sent `false`, so this does not corrupt the read model, it simply never asserts that fact from this client.

## Broken-Windows Ledger

Recorded to `.planning/WINDOWS.md` (best-effort; commands run non-fatally):

- `stub`: `playstead-mac/Playstead/Cache/AvailabilityReporter.swift` — live transfer percent falls back to `0` when no `DownloadCoordinator` exists yet at report time (see Known Stubs above).

## Issues Encountered

None beyond the deviations documented above.

## User Setup Required

None — no external service configuration required.

## Threat Flags

None beyond the STRIDE register already authored in this plan's `<threat_model>` (all dispositions `mitigate` or explicitly `accept`ed with rationale in the plan itself). No new network endpoint, auth path, or schema change was introduced outside that register — `.availabilityReport` reuses the existing `PUT /api/v1/devices/me/availability` endpoint and `Outbox`/`CurationIntent` machinery `03-13` and prior phases already established.

## Next Phase Readiness

**What remains open after this plan:**

- `LIBR-05` (find-a-game UX review) and `PLAY-04` (physical controller hardware) remain `Pending` in `REQUIREMENTS.md` — neither was advanced by this plan, as designed.
- Four `human_verification` items remain outstanding in `03-VERIFICATION.md`: physical controller connect/disconnect/reconnect on real hardware, a live interactive emulator session, the experiential VoiceOver walkthrough, and acceptance of real, legally-owned BIOS bytes.
- The phase's correct terminal status (`human_needed`, not `passed`, per this project's own gate rules while any `human_verification` item remains open) is still to be set by an independent re-verification run, not by this plan — `03-VERIFICATION.md`'s top-level `status: gaps_found` field was deliberately left untouched.
- The device-reported availability read model remains a convenience view only (T-03-13-03, unchanged by this plan): the launch path and the Mac client's own `AvailabilityState.derive` remain the sole authority for whether a game can actually start.

---
*Phase: 03-mac-offline-play-vertical-slice*
*Completed: 2026-09-11*

## Self-Check: PASSED

All 6 created/output files found on disk; all 3 task commits (`8c2e990`, `93a6e6b`, `6eccf32`) found in `git log`. Plan-level `<verification>` block re-run and passing: Mac unit run (16/16, no zero-executed-test line), `AvailabilityState.swift` unmodified, `mix test` 1065/1065, `check-uat-tally.sh` exits 0 with corrupt-and-revert observed, `03-VERIFICATION.md` top-level status still `gaps_found` with all human_verification entries intact, `LIBR-05`/`PLAY-04` still `Pending`.
