---
phase: 03-mac-offline-play-vertical-slice
plan: 16
subsystem: library
tags: [elixir, swift, availability, outbox, gap-closure, tdd, requirements]

requires:
  - phase: 03-mac-offline-play-vertical-slice
    provides: "03-15's computed missing_dependency fact and its committed shared fixture proving Swift-encoder/HTTP transport parity; 03-13's PUT /api/v1/devices/me/availability and Playstead.Availability; 03-08's Outbox/CurationIntentKind"
provides:
  - "A shape guard on AvailabilityController.replace/2 that refuses a non-list or non-map-element entries body with 422 validation_failed in the sibling endpoints' problem shape, instead of raising into a generic 500"
  - "CurationIntentKind.supersedesPending and a kind-scoped, pending-state-scoped delete inside Outbox.enqueue's existing transaction, so only the newest full-replacement availability report is ever delivered"
  - "LIBR-02 flipped to Complete in REQUIREMENTS.md, gated on 03-15's and this plan's own observed Mac-client-driven and HTTP-driven test runs"
affects: [any future phase touching AvailabilityController, Outbox.enqueue, CurationIntentKind, or REQUIREMENTS.md's LIBR-02 row]

actuals:
  tokens: 34000
  tasks: 3
  commits: 5

tech-stack:
  added: []
  patterns:
    - "ImportsController.precheck/2's guard-clause-plus-catch-all shape (matching clause + {:error, {:validation_failed, detail}} catch-all for the existing action_fallback) reused verbatim in AvailabilityController.replace/2"
    - "A kind-scoped supersede-on-enqueue delete inside an existing transaction, declared as an exhaustive switch property on the kind enum next to the kind itself, rather than folded into the shared listPending query"

key-files:
  created: []
  modified:
    - playstead-server/lib/playstead_web/controllers/api/v1/availability_controller.ex
    - playstead-server/test/playstead_web/controllers/api/v1/availability_controller_test.exs
    - playstead-mac/Playstead/Sync/Outbox.swift
    - playstead-mac/Playstead/Sync/CurationIntent.swift
    - playstead-mac/PlaysteadTests/CurationTests/OutboxTests.swift
    - playstead-mac/scripts/ci/run-mac-verification.sh
    - .planning/REQUIREMENTS.md

key-decisions:
  - "The shape guard rejects wrong shapes (non-list, list-with-non-map-element) but leaves an absent entries key exactly as it behaves today (defaults to [], a valid empty full replacement) -- turning absence into a rejection would be a silent behavior widening the plan explicitly forbade."
  - "Supersede-on-enqueue (delete inside Outbox.enqueue's transaction) was chosen over a newest-wins filter inside listPending, per planner_assumptions item 3: listPending is a generic read shared by OutboxWorker and the rejected-intents surface, and the alternative would leave stale rows accumulating on disk for an offline device."
  - "Superseded rows are deleted, not re-stated, since .availabilityReport carries no local optimistic write (confirmed by reading applyOptimistically before implementing) -- deletion also avoids adding a new OutboxEntryState case that an older build's decoder would misread."
  - "LIBR-02 flipped only after judging every clause of UAT item 4's expected text against a named test, with the availability clause specifically required to be proved by a test that drives the Mac client or the real HTTP endpoint -- never a test that seeds the server read model directly."

requirements-completed: [LIBR-02]

coverage:
  - id: D1
    description: "A malformed availability report (non-list entries, or a list with a non-map element) is refused with 422 in the sibling endpoints' problem shape instead of raising into a 500"
    requirement: null
    verification:
      - kind: integration
        ref: "playstead-server/test/playstead_web/controllers/api/v1/availability_controller_test.exs (4 new tests: string entries, map entries, list-with-string-element, list-with-number-element, each asserting 422 validation_failed on its own line)"
        status: pass
    human_judgment: false
  - id: D2
    description: "A well-formed report and an absent-entries-key report are unaffected by the new guard"
    requirement: null
    verification:
      - kind: integration
        ref: "availability_controller_test.exs#an absent entries key keeps performing a valid empty full replacement; availability_controller_test.exs#an entries list of maps still returns 200 and still writes its rows; full mix test 1072/1072, 0 failures (>= 1065 baseline)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Only the newest full-replacement availability report is ever delivered -- a pending or backed-off predecessor is superseded, an in-flight one is not, and no other intent kind is affected"
    requirement: null
    verification:
      - kind: unit
        ref: "OutboxTests.swift (5 new tests: test_secondAvailabilityReport_supersedesThePendingFirstOne, test_secondAvailabilityReport_supersedesABackedOffFirstOne, test_secondAvailabilityReport_leavesAnInFlightFirstOneAlone, test_secondFavoriteIntent_isNotSupersededBecauseOnlyReportsAreNewestWins, test_drainAfterSupersede_sendsOnlyTheNewerReportBody)"
        status: pass
    human_judgment: false
  - id: D4
    description: "LIBR-02 is marked Complete only on the strength of tests that drive the Mac client or the real endpoint, with a clause-to-test mapping recorded for re-derivation"
    requirement: LIBR-02
    verification:
      - kind: other
        ref: "03-15-SUMMARY.md's verbatim Mac unit run (17/17) and server e2e run (1/1); this plan's own Task 1/Task 2 runs (10/10 server availability tests, 37/37 Mac OutboxTests+AvailabilityReporterTests); clause-to-test mapping recorded in the Task 3 commit message and this SUMMARY's Verbatim Evidence section"
        status: pass
    human_judgment: false

duration: 22min
completed: 2026-09-11
status: complete
---

# Phase 3 Plan 16: WR-04/WR-05 Gap Closure and LIBR-02 Flip Summary

**Added a shape guard refusing malformed availability reports with 422 instead of a 500 (WR-04), made outbox enqueue supersede a pending/backed-off availability report with only the newest one (WR-05), then flipped LIBR-02 to Complete gated on 03-15's and this plan's own observed Mac-client-driven and HTTP-driven test runs.**

## Performance

- **Duration:** 22 min
- **Started:** 2026-09-11T15:01:59Z
- **Completed:** 2026-09-11T15:24:14Z
- **Tasks:** 3
- **Files modified:** 7

## Accomplishments

- `AvailabilityController.replace/2` now routes `entries` through a private `do_replace/2` with a guard clause (list of maps) plus a catch-all returning `{:error, {:validation_failed, detail}}` for the already-declared `action_fallback` to render — matching `ImportsController.precheck/2`'s shape verbatim. An absent `entries` key still defaults to `[]` (a valid empty full replacement), unchanged. The pre-existing `:too_many_entries` 5000-cap branch survives untouched.
- `CurationIntentKind.supersedesPending` (an exhaustive switch, true only for `.availabilityReport`) is consulted inside `Outbox.enqueue`'s existing transaction: before inserting a new row, any still-`pending` row of the same kind — including one backed off by the real `markPendingForRetry` path — is deleted. An `in_flight` row (a request already on the wire) is never superseded, and every other intent kind still drains in creation order with no entry dropped. `listPending(at:)`'s body is untouched (confirmed via `git diff`).
- `LIBR-02` is flipped to `Complete` in `REQUIREMENTS.md` (checkbox and traceability row, 2 lines changed), gated exclusively on 03-15's and this plan's own observed test runs and a clause-by-clause coverage judgement of UAT item 4's expected text. `03-VERIFICATION.md` and `03-UAT.md` are untouched (`git diff --exit-code` clean on both) — the phase's terminal status and gap verdicts are left for an independent re-verification, not set by the plan whose work they would grade.
- Full server suite: 1072 tests, 0 failures (>= 1065 baseline recorded in `03-VERIFICATION.md` at HEAD `33a06a1`). Full Mac `OutboxTests` + `AvailabilityReporterTests`: 37/37, 0 failures, no `Executed 0 tests` line.

## Task Commits

1. **Task 1 (RED): add failing tests for availability shape guard** — `d4b766c` (test)
2. **Task 1 (GREEN): refuse a malformed availability report with 422** — `b0d8a7a` (feat)
3. **Task 2 (RED): add failing tests for outbox newest-wins supersede** — `9321e4e` (test)
4. **Task 2 (GREEN): only the newest availability report is ever delivered** — `996fcda` (feat)
5. **Task 3: flip LIBR-02 to Complete** — `413d4c5` (docs)

**Plan metadata:** committed as part of this SUMMARY (docs commit follows).

## Files Created/Modified

- `playstead-server/lib/playstead_web/controllers/api/v1/availability_controller.ex` — shape guard (`do_replace/2`) on `entries` before the context call; existing `:too_many_entries` branch unchanged.
- `playstead-server/test/playstead_web/controllers/api/v1/availability_controller_test.exs` — 6 tests added (4 malformed-shape rejections, absent-key preservation, well-formed-list survival); existing assertions unchanged.
- `playstead-mac/Playstead/Sync/CurationIntent.swift` — `supersedesPending` added to `CurationIntentKind` as an exhaustive switch.
- `playstead-mac/Playstead/Sync/Outbox.swift` — a kind-scoped, `state = 'pending'`-scoped delete inside `enqueue(_:at:)`'s existing transaction; `listPending(at:)` unchanged.
- `playstead-mac/PlaysteadTests/CurationTests/OutboxTests.swift` — 5 tests added.
- `playstead-mac/scripts/ci/run-mac-verification.sh` — 5 new identifiers added to the unit-layer required-test list.
- `.planning/REQUIREMENTS.md` — `LIBR-02` checkbox and traceability row (2 lines).

## Decisions Made

See `key-decisions` in frontmatter.

## Deviations from Plan

None — plan executed exactly as written, including a test-fixture correction during Task 2's GREEN run (not a plan deviation, an ordinary fixture bug fix during the same RED/GREEN session): `test_drainAfterSupersede_sendsOnlyTheNewerReportBody`'s original body-capture logic read `request.httpBody`, but `URLSession` delivers a `URLRequest`'s body to `URLProtocol` as `httpBodyStream` once it has gone through `session.data(for:)`, not `httpBody` — the assertion initially reported `sentBodies.count == 0` even though the row-count assertion (`result.sent == 1`) already passed. Corrected by reading whichever of `httpBody`/`httpBodyStream` is present; re-ran green.

## Verbatim Evidence (per this plan's `<output>` instruction)

### Task 1 — observed pre-fix status for the non-list and non-map-element bodies

RED run (`mix test test/playstead_web/controllers/api/v1/availability_controller_test.exs`), before the guard existed:

```
1) test an entries list containing a string element is refused with 422 validation_failed, not a 500
   left:  500
   right: 422

2) test a map entries body is refused with 422 validation_failed, not a 500
   left:  500
   right: 422

3) test an entries list containing a number element is refused with 422 validation_failed, not a 500
   left:  500
   right: 422

4) test a string entries body is refused with 422 validation_failed, not a 500
   left:  500
   right: 422

10 tests, 4 failures
```

### Task 1 — final guard clause as implemented and its exact detail strings

```elixir
defp do_replace(conn, entries) when is_list(entries) do
  if Enum.all?(entries, &is_map/1) do
    # ... existing Idempotency.execute/4 call shape, unchanged ...
  else
    {:error,
     {:validation_failed,
      "The \"entries\" list must contain only objects, not other value types."}}
  end
end

defp do_replace(_conn, _entries) do
  {:error, {:validation_failed, "The \"entries\" field must be a list."}}
end
```

GREEN run: `10 tests, 0 failures`. Full suite: `178 features, 13 properties, 1072 tests, 0 failures`.

### Task 2 — confirmation that `applyOptimistically` is a no-op for `.availabilityReport`

Read directly in `CurationIntent.swift` before implementing the delete:

```swift
case .availabilityReport:
    // No local optimistic write: this intent reports facts read
    // fresh from disk at report time, never a `curation_*` row.
    break
```

Confirmed no local write exists for this kind, so the delete does not orphan any local mutation.

### Task 2 — observed failure from removing the kind predicate from the supersede delete

With the delete made unconditional on `state = 'pending'` alone (kind predicate removed), re-running `test_secondFavoriteIntent_isNotSupersededBecauseOnlyReportsAreNewestWins`:

```
/Users/jon/projects/playstead/playstead-mac/PlaysteadTests/CurationTests/OutboxTests.swift:456:
error: -[PlaysteadTests.OutboxTests test_secondFavoriteIntent_isNotSupersededBecauseOnlyReportsAreNewestWins] :
XCTAssertEqual failed: ("1") is not equal to ("2") - superseding is scoped to the one kind for which newest-wins is true

Executed 1 test, with 1 failure (0 unexpected)
```

`Outbox.swift` was then restored byte-for-byte (`diff` against the pre-corruption backup confirmed identical), and the full `OutboxTests` + `AvailabilityReporterTests` suite re-ran 37/37 green.

### Task 2 — Mac executed-test count

`OutboxTests` (20/20) + `AvailabilityReporterTests` (17/17): `Executed 37 tests, with 0 failures (0 unexpected)` — no `Executed 0 tests` line. Full log at `playstead-mac/build/outbox-supersede-tests.log`.

### Task 3 — clause-by-clause mapping from UAT item 4 to named tests

UAT item 4's `expected:` text: "From the web console you can reach any imported game by system, by availability, and by free-text search."

| Clause | Proving test | Drives real client? |
|---|---|---|
| "reach any imported game by system" | `test/playstead_web/live/library_live_test.exs` — "toggling a system chip... narrow the set" (pre-existing) | LiveView, server-side |
| "by availability" — 5 of 6 states (needs_attention, downloading, queued, ready_offline, server_only) | `test/playstead_web/live/library_live_test.exs` — six-value discrimination test (03-13/03-14, pre-existing to this plan) | LiveView filter clause |
| "by availability" — `missing_dependency` state specifically | `playstead-mac/PlaysteadTests/CacheTests/AvailabilityReporterTests.swift` (03-15's 8 new predicate-driving tests + `test_buildEntriesOutputEncodesByteIdenticallyToSharedReportFixture`) **and** `playstead-server/test/playstead_web/live/library_availability_e2e_test.exs#the missing_dependency chip returns a game the device reported over HTTP` | **Yes** — Mac client (`buildEntries`) and the real HTTP endpoint, not a seeded read model |
| "by free-text search" | `test/playstead_web/live/library_live_test.exs` — "searching a distinctive substring narrows the rendered set" (pre-existing) | LiveView, server-side |

Every clause is covered, and the availability/readiness-state clause is specifically proved by a Mac-client-driven test and an HTTP-driven end-to-end test, satisfying this plan's own gating requirement. `LIBR-02` was flipped to `Complete` on this evidence, cited from `03-15-SUMMARY.md`'s own verbatim "Mac unit run 17/17" and "server e2e 1/1" records plus this plan's own Task 1/Task 2 observed runs (10/10 server availability tests; 37/37 Mac `OutboxTests` + `AvailabilityReporterTests`).

## Issues Encountered

None beyond the test-fixture correction documented above.

## User Setup Required

None — no external service configuration required.

## Threat Flags

None. This plan's own `<threat_model>` STRIDE register (T-03-16-01 through T-03-16-SC) already covers every trust boundary touched: the device-request-body shape guard, the outbox delivery-order race, and the executor-writes-its-own-grading boundary (mitigated by the `git diff --exit-code` verify on `03-VERIFICATION.md`/`03-UAT.md`). No new network endpoint, auth path, or schema change was introduced.

## Next Phase Readiness

**What remains open after this plan:**

- `03-VERIFICATION.md`'s top-level `status: gaps_found` and its four `human_verification` entries (physical controller hardware, a live interactive emulator session, the experiential VoiceOver walkthrough, acceptance of real BIOS bytes) are untouched — outside this plan's scope fence, and this plan's own precondition explicitly forbids editing them. An independent re-verification is the only thing that may now set the phase's terminal status.
- `LIBR-05` (human-judgement UX review) and `PLAY-04` (physical controller hardware) remain `Pending` — neither this plan nor 03-15 advanced them, and this plan's acceptance criteria explicitly assert they were not touched.
- The device-reported availability read model remains a convenience view only (T-03-13-03, unchanged): the launch path and the Mac client's own `AvailabilityState.derive` remain the sole authority for whether a game can actually start.
- `must_haves.truths`' backstop-verification item ("a device offline for a long period accumulates no unbounded backlog of superseded availability rows on disk") is satisfied by this plan's supersede-on-enqueue design (each new report deletes its own kind's pending predecessor, so at most one pending availability-report row can ever exist per device at a time) but has no dedicated long-running/fuzz test — an independent re-verification should classify whether the unit-level supersede tests constitute sufficient evidence for this backstop truth or whether a dedicated test is warranted.

---
*Phase: 03-mac-offline-play-vertical-slice*
*Completed: 2026-09-11*

## Self-Check: PASSED

All 7 modified files found on disk (verified via `git diff --stat` against each commit); all 5 task commits (`d4b766c`, `b0d8a7a`, `9321e4e`, `996fcda`, `413d4c5`) found in `git log --oneline`. Plan-level `<verification>` block re-run and passing: `mix test test/playstead_web/controllers/api/v1/availability_controller_test.exs` 10/10, 0 failures; the four malformed shapes each return 422 `validation_failed`, absent-key and well-formed-list cases unchanged; full `mix test` 1072/1072 (>= 1065 baseline), 0 failures; Mac `OutboxTests` + `AvailabilityReporterTests` 37/37, 0 failures, no `Executed 0 tests` line; `Outbox.swift`'s `listPending(at:)` body unchanged in `git diff`; both corrupt-and-revert checks observed to fail then pass, recorded verbatim above; `03-VERIFICATION.md` and `03-UAT.md` both `git diff --exit-code` clean; `LIBR-05`/`PLAY-04` still `Pending`; `.planning/REQUIREMENTS.md` shows exactly 2 changed lines; `bash scripts/check-uat-tally.sh` exits 0.
