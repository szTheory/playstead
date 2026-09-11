---
phase: 03-mac-offline-play-vertical-slice
plan: 15
subsystem: library
tags: [swift, elixir, availability, gap-closure, tdd, e2e]

requires:
  - phase: 03-mac-offline-play-vertical-slice
    provides: "AvailabilityReporter (03-14) with a hardcoded missingDependency: false constant, PUT /api/v1/devices/me/availability and Playstead.Availability (03-13), StatusSlot's frozen seven-value ladder"
provides:
  - "A computed missing_dependency fact on the Mac client, derived from catalogue membership, CAS presence, and download-queue rows, guarded by an engagement conjunct so server_only stays reachable"
  - "shared/availability-report-fixture.json, a committed two-sided fixture proving the Swift encoder and the real HTTP transport agree byte-for-byte"
  - "An Elixir end-to-end test (library_availability_e2e_test.exs) that proves the missing_dependency chip can return a game reported over the real endpoint, never a seeded read model"
affects: [any future phase touching library availability filters, the missing_dependency chip, or the availability report wire contract]

actuals:
  tokens: 42000
  tasks: 2
  commits: 3

tech-stack:
  added: []
  patterns:
    - "A second shared JSON fixture (availability-report-fixture.json) alongside the frozen vocabulary fixture, read at test time by both codebases and by no runtime path -- the same shared-fixture pattern 03-13/03-14 established for the vocabulary, now applied to the report body shape itself"

key-files:
  created:
    - shared/availability-report-fixture.json
    - playstead-server/test/playstead_web/live/library_availability_e2e_test.exs
  modified:
    - playstead-mac/Playstead/Cache/AvailabilityReporter.swift
    - playstead-mac/PlaysteadTests/CacheTests/AvailabilityReporterTests.swift
    - playstead-mac/scripts/ci/run-mac-verification.sh

key-decisions:
  - "The missing_dependency predicate carries an explicit engagement conjunct (cached, pinned, or queued) alongside the orphaned-member conjunct -- the literal 03-VERIFICATION.md definition alone would make every never-downloaded game report missing_dependency true, making server_only structurally unreachable one ladder slot down from the original defect."
  - "'Queued' reuses AvailabilityInputs' own doc-commented definition (waiting/active/paused in-queue; cancelled excluded) rather than a second, independently-invented notion of queued on the client."
  - "Task 2 required no production code change: Task 1's computed predicate already produces the exact facts the fixture and the Elixir end-to-end test assert against, so Task 2 is proof-only, closing the transport hole that let the prior LIBR-02 round look green on a seeded read model."

requirements-completed: []

coverage:
  - id: D1
    description: "missing_dependency is a value the Mac client can actually compute, read from catalogue/CAS/download-queue state rather than a hardcoded constant"
    requirement: "LIBR-02"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/CacheTests/AvailabilityReporterTests.swift (8 new tests: orphaned member no queue row, pinned+evicted member, waiting/paused queue rows false, cancelled-only queue row true, untouched game false, empty required list false, simultaneous orphan+active-transfer)"
        status: pass
    human_judgment: false
  - id: D2
    description: "The proof that missing_dependency can return a result comes from a device-driven encoder test and an HTTP-driven server test, not from seeding the read model directly"
    requirement: "LIBR-02"
    verification:
      - kind: unit
        ref: "AvailabilityReporterTests.swift#test_buildEntriesOutputEncodesByteIdenticallyToSharedReportFixture"
        status: pass
      - kind: integration
        ref: "library_availability_e2e_test.exs#the missing_dependency chip returns a game the device reported over HTTP"
        status: pass
    human_judgment: false
  - id: D3
    description: "The same bytes the Mac encoder produces are the bytes the server test sends -- one committed fixture, not each side's own stub"
    verification:
      - kind: other
        ref: "shared/availability-report-fixture.json, read by both AvailabilityReporterTests.swift and library_availability_e2e_test.exs (grep -c both >= 1)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Making missing_dependency reachable does not make server_only unreachable"
    verification:
      - kind: unit
        ref: "AvailabilityReporterTests.swift#test_untouchedGame_reportsMissingDependencyFalseSoServerOnlyStaysReachable; library_availability_e2e_test.exs asserts server_only returns the all-false game and excludes the missing_dependency one"
        status: pass
    human_judgment: false
  - id: D5
    description: "A game simultaneously orphaned and mid-transfer lands on exactly one chip via StatusSlot's frozen ladder, not a second client-side ladder"
    verification:
      - kind: unit
        ref: "AvailabilityReporterTests.swift#test_orphanedMemberDuringActiveTransfer_reportsBothMissingDependencyAndDownloadingTrue"
        status: pass
    human_judgment: false
  - id: D6
    description: "The new Mac test identifiers are registered with the verification harness by name"
    verification:
      - kind: other
        ref: "grep -c of all nine new identifiers in run-mac-verification.sh -> 1 each; Mac unit run reports 17/17, no 'Executed 0 tests' line"
        status: pass
    human_judgment: false
  - id: D7
    description: "A report whose entry list is unchanged since the last pass still encodes and enqueues without error (backstop truth)"
    verification: []
    human_judgment: true
    rationale: "No dedicated no-op-diff test was added in this plan; reportAll's full-replacement semantics (unchanged from 03-14) and the pre-existing test_sameReportRetried_carriesSameIdempotencyKeyAndOneServerEffect cover retry/idempotency but not literally an unchanged-diff pass. Coverage not determined at authoring time -- verifier should classify."

duration: 40min
completed: 2026-09-11
status: complete
---

# Phase 3 Plan 15: LIBR-02 Real-Signal Gap Closure (missing_dependency) Summary

**Replaced the hardcoded `missingDependency: false` constant with a computed fact (orphaned required member + engagement guard) and closed the transport-proof hole with a committed fixture proven identical by both the Swift encoder and a real HTTP-driven Elixir end-to-end test.**

## Performance

- **Duration:** ~40 min
- **Started:** 2026-09-11T14:43:00Z
- **Completed:** 2026-09-11T15:00:20Z
- **Tasks:** 2 (1 tracer/tdd, 1 auto/tdd)
- **Files modified:** 5 (2 created, 3 modified)

## Accomplishments

- `AvailabilityReporter.buildEntries` computes `missing_dependency` per game as `(hasOrphanedRequiredMember) && (hasEngaged)`, where an orphaned required member is a required SHA absent from the CAS with no queue row in an in-queue state (`waiting`/`active`/`paused`; `cancelled` excluded, reusing `AvailabilityInputs`' own doc-commented definition), and the engagement guard requires at least one cached required member, a pin, or a queued row — without which every never-downloaded game would report the fact true and make `server_only` structurally unreachable, the same defect one ladder slot down.
- Eight new tests drive `buildEntries` over real catalogue/CAS/queue/pin state, pinning the predicate in both directions, plus a ninth test proving the built output is byte-identical (field-for-field, both directions on the key set) to a committed shared fixture.
- `shared/availability-report-fixture.json` (four entries: missing-dependency, downloading, verified, all-false) is read at test time by both the Swift encoder test and a new Elixir end-to-end test (`library_availability_e2e_test.exs`) that PUTs the fixture's body verbatim (only `asset_set_id` rewritten) to the real `PUT /api/v1/devices/me/availability` endpoint, then asserts the `missing_dependency` chip returns the reported game and `server_only` still returns its own — never seeding `Playstead.Availability.replace_for_device/2` or a `DeviceReport` struct directly.
- All nine new Mac test identifiers registered in `run-mac-verification.sh`'s required-test list; the reporter remains provably off every launch path (`grep -rl 'AvailabilityReporter' playstead-mac --include='*.swift'` lists no `Adapter/` or `Launch*` file).
- Full server suite: 1066 tests, 0 failures — at or above the 1065 baseline recorded in `03-VERIFICATION.md` at HEAD `33a06a1`.

## Task Commits

1. **Task 1 (RED): add failing tests for computed missing-dependency fact** — `d3856de` (test)
2. **Task 1 (GREEN): compute missing-dependency fact from the stores buildEntries already holds** — `746cb87` (feat)
3. **Task 2: prove missing_dependency survives the real transport** — `22e9dd0` (test)

**Plan metadata:** committed as part of this SUMMARY (docs commit follows).

## Files Created/Modified

- `playstead-mac/Playstead/Cache/AvailabilityReporter.swift` — the hardcoded `missingDependency: false` argument replaced with a computed local (two named conjuncts, doc-commented).
- `playstead-mac/PlaysteadTests/CacheTests/AvailabilityReporterTests.swift` — nine tests added (eight predicate cases + one fixture-parity case); existing eight assertions unchanged.
- `playstead-mac/scripts/ci/run-mac-verification.sh` — nine new identifiers added to the unit-layer required-test list.
- `shared/availability-report-fixture.json` — new, four-entry committed fixture in the Mac client's own wire shape.
- `playstead-server/test/playstead_web/live/library_availability_e2e_test.exs` — new module `PlaysteadWeb.LibraryAvailabilityE2ETest`, one HTTP-driven end-to-end test.

## Decisions Made

See `key-decisions` in frontmatter.

## Deviations from Plan

None — plan executed exactly as written. Task 1 followed the letter of the TDD instruction (tests authored and run RED against the existing hardcoded constant, confirmed clean failures with no path-safety rejections, then implementation added and confirmed GREEN, as two separate commits). Task 2 required no production code change since Task 1's predicate already produced the exact facts the fixture and end-to-end test assert against; this was expected from the plan's own design (Task 2's job is closing the transport-proof hole, not changing behavior), not a deviation.

One test-authoring correction during Task 1's GREEN run: `test_orphanedMemberDuringActiveTransfer_reportsBothMissingDependencyAndDownloadingTrue`'s original setup called `enqueueGame` (which enqueues every required member, including the one meant to be truly orphaned) without cancelling the orphaned member's own resulting queue row, so the member was not actually "absent with no queue row" as the test name claims. Corrected within Task 1 by explicitly cancelling that row before asserting — an ordinary test-fixture bug fix during the same RED/GREEN session, not a plan deviation.

## Verbatim Evidence (per this plan's `<output>` instruction)

### The final predicate as implemented

```swift
let queueItems = downloadQueue.itemsForAssetSet(game.id)
let isPinned = pinnedAssetSetIDs.contains(game.id)

let hasOrphanedRequiredMember = requiredSHAs.contains { sha in
    !self.cas.contains(sha) && !queueItems.contains { item in
        item.sha256 == sha && item.state != .cancelled
    }
}

let hasEngaged = requiredSHAs.contains { self.cas.contains($0) }
    || isPinned
    || queueItems.contains { $0.state != .cancelled }

let missingDependency = !requiredSHAs.isEmpty && hasOrphanedRequiredMember && hasEngaged
```

In-queue state set: `waiting`, `active`, `paused` (i.e. `state != .cancelled`), taken verbatim from `AvailabilityInputs`' own doc comment. Engagement: cached OR pinned OR any non-cancelled queue row.

### Observed failure from removing the engagement conjunct

With `hasEngaged` removed (`let missingDependency = !requiredSHAs.isEmpty && hasOrphanedRequiredMember`), re-running `test_untouchedGame_reportsMissingDependencyFalseSoServerOnlyStaysReachable`:

```
/Users/jon/projects/playstead/playstead-mac/PlaysteadTests/CacheTests/AvailabilityReporterTests.swift:344:
error: -[PlaysteadTests.AvailabilityReporterTests test_untouchedGame_reportsMissingDependencyFalseSoServerOnlyStaysReachable] :
XCTAssertFalse failed - an untouched game is on the server, not broken -- server_only must stay reachable
```

`AvailabilityReporter.swift` was then restored byte-for-byte (`diff` against a pre-corruption backup confirmed identical), and the full `AvailabilityReporterTests` suite re-ran 17/17 green.

### Observed failures from flipping the fixture's `missing_dependency` value

`shared/availability-report-fixture.json`'s `missing-dependency-asset-set` entry's `missing_dependency` flipped from `true` to `false`:

**Swift side:**
```
/Users/jon/projects/playstead/playstead-mac/PlaysteadTests/CacheTests/AvailabilityReporterTests.swift:458:
error: -[PlaysteadTests.AvailabilityReporterTests test_buildEntriesOutputEncodesByteIdenticallyToSharedReportFixture] :
XCTAssertEqual failed: ("AvailabilityReportEntry(assetSetID: "missing-dependency-asset-set", downloading: false,
verified: false, pinned: false, missingDependency: true, downloadPercent: 0)") is not equal to
("AvailabilityReportEntry(assetSetID: "missing-dependency-asset-set", downloading: false, verified: false,
pinned: false, missingDependency: false, downloadPercent: 0)") - built entry for missing-dependency-asset-set
does not match the committed fixture
```

**Elixir side:**
```
1) test the missing_dependency chip returns a game the device reported over HTTP (PlaysteadWeb.LibraryAvailabilityE2ETest)
   test/playstead_web/live/library_availability_e2e_test.exs:42
   the missing_dependency chip must return the game the device reported over HTTP
   code: assert has_element?(lv, "#library-asset-stream ##{"asset-" <> missing_dependency_set.id}"),
   stacktrace:
     test/playstead_web/live/library_availability_e2e_test.exs:91: (test)

1 test, 1 failure
```

The fixture was then restored byte-for-byte (`diff` against a pre-corruption backup confirmed identical); both sides re-ran green (Swift 17/17, Elixir 1/1).

### Mac executed-test count and server total

- Mac unit run (`AvailabilityReporterTests` suite, full): `Executed 17 tests, with 0 failures (0 unexpected)` — no `Executed 0 tests` line.
- Server: `178 features, 13 properties, 1066 tests, 0 failures` — 1066 ≥ 1065 baseline (`03-VERIFICATION.md` HEAD `33a06a1`).

### What the predicate deliberately does not claim

- It does not claim `missing_dependency` for a never-downloaded, never-pinned, never-queued game — that is `server_only`, by the engagement guard's explicit design (`test_untouchedGame_reportsMissingDependencyFalseSoServerOnlyStaysReachable`).
- It does not claim `missing_dependency` for a game with an empty required-member list — an upstream manifest defect, not a claim this client makes (`test_emptyRequiredMemberList_reportsMissingDependencyFalse`).
- It does not compute, store, or transmit a ladder rank (D-21): the entry carries only the raw fact; `StatusSlot`'s frozen ladder on the server is the sole place collisions between simultaneous facts (e.g. orphaned + actively downloading) are resolved.
- It does not treat a `paused` queue row as missing — only `cancelled` counts as "not in the queue," matching `AvailabilityInputs`' existing definition exactly.

## Issues Encountered

None beyond the test-fixture correction documented above.

## User Setup Required

None — no external service configuration required.

## Threat Flags

None beyond the STRIDE register already authored in this plan's `<threat_model>` (T-03-15-01 through T-03-15-SC, all dispositions `mitigate` or explicitly `accept`ed with rationale in the plan itself). No new network endpoint, auth path, or schema change was introduced — this plan changes what one existing field's value is computed from, not the wire shape, the endpoint, or the trust boundary.

## Next Phase Readiness

**What remains open after this plan (unchanged by design — this plan flips no requirement checkbox and edits no verification verdict):**

- `LIBR-02` remains unmarked in `REQUIREMENTS.md`; the requirement flip is `03-16-PLAN.md`'s job, gated on this plan's own observed test runs (recorded verbatim above).
- `03-VERIFICATION.md`'s top-level `status: gaps_found` and its four `human_verification` entries (physical controller hardware, a live interactive emulator session, the experiential VoiceOver walkthrough, acceptance of real BIOS bytes) are untouched — outside this plan's scope fence.
- The device-reported availability read model remains a convenience view only (T-03-13-03, unchanged by this plan): the launch path and the Mac client's own `AvailabilityState.derive` remain the sole authority for whether a game can actually start.
- D7's backstop truth (a no-op-diff report still encodes/enqueues without error) is recorded as `human_judgment: true` in this SUMMARY's coverage block — no dedicated test asserts it literally, though `reportAll`'s unchanged full-replacement semantics and existing idempotency-key tests provide indirect coverage. An independent re-verification should classify this explicitly.

---
*Phase: 03-mac-offline-play-vertical-slice*
*Completed: 2026-09-11*

## Self-Check: PASSED

All 2 created files (`shared/availability-report-fixture.json`, `playstead-server/test/playstead_web/live/library_availability_e2e_test.exs`) found on disk; all 3 task commits (`d3856de`, `746cb87`, `22e9dd0`) found in `git log`. Plan-level `<verification>` block re-run and passing: `AvailabilityReporter.swift` contains zero hardcoded `missingDependency: false` in executable code; Mac unit run 17/17 with no `Executed 0 tests` line; `mix test test/playstead_web/live/library_availability_e2e_test.exs` 1/1, 0 failures; the e2e test file greps zero for `replace_for_device(` and `%DeviceReport{`; full `mix test` 1066/1066 (≥1065 baseline); `AvailabilityState.swift`, `shared/availability-vocabulary.json`, and `AvailabilityVocabulary.swift` all `git diff --exit-code` clean; both corrupt-and-revert checks observed to fail then pass, verbatim above; `.planning/REQUIREMENTS.md` and `03-VERIFICATION.md` both `git diff --exit-code` clean (untouched by this plan).
