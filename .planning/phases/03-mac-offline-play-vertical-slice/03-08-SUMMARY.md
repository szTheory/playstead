---
phase: 03-mac-offline-play-vertical-slice
plan: 08
subsystem: sync
tags: [swift, swiftui, sqlite, outbox, idempotency, fractional-index, curation, offline-first, elixir, phoenix]

# Dependency graph
requires:
  - phase: 03-mac-offline-play-vertical-slice (03-04)
    provides: "Server-canonical curation context, curation change-journal entity kind, per-row idempotent REST intents under /api/v1/curation/* and /api/v1/play-sessions"
  - phase: 03-mac-offline-play-vertical-slice (03-06)
    provides: "SyncEngine/JournalApplier/CatalogueStore/CurationStore, SQLiteConnection reentrant transactions, the library shell UI and design tokens"
  - phase: 01-private-custody-and-durable-protocol (D-20)
    provides: "The client-generated natural-key + Idempotency-Key mechanism this outbox reuses verbatim"
provides:
  - "Outbox/OutboxWorker: a durable per-row curation-intent queue with optimistic local apply, idempotent replay, and permanent-rejection revert-and-surface"
  - "CurationIntent: all twelve curation/play-session intent kinds, matching the server's changeset field names exactly"
  - "FractionalPosition: a Swift port of the server's base-36 fractional-index algorithm, verified against server-generated fixtures"
  - "FavoritesViewModel/CollectionsViewModel/QueueViewModel/ContinueViewModel/RecentViewModel and their SwiftUI views — all five curation nouns usable offline"
  - "PlaySessionRecorder: coarse play-session recording structurally independent of the launch path, delivered through the outbox"
affects: [03-09-mac-preflight-and-readiness, 03-10-mac-controller-remap-and-notarized-build]

actuals:
  tokens: 32900
  tasks: 3
  commits: 6

tech-stack:
  added: []
  patterns:
    - "CurationIntentEnvelope: a Codable struct with every field every intent kind might need, persisted as outbox_entries.payload_json, so a restarted app reconstructs the whole CurationIntent (method/path/localRowID) from disk rather than just a bare wire body"
    - "Every intent's idempotencyKey is derived from its own client-generated id (create-shaped) or its target's local row id (remove/rename/delete/move-shaped) — stable across every send attempt of that exact intent, matching P1 D-20 verbatim"
    - "Move-shaped intents (collectionMemberMove/queueMove) carry a FractionalPosition-computed position purely as a local optimistic placeholder — the server never reads it, only the two named neighbours; the settled position always arrives through the journal"
    - "A drag reorder settles to exactly one outbox entry via a begin/previewMove*/commit API: preview calls mutate only an in-memory ordering, never the outbox; commit computes the moved item's final neighbours and enqueues once"
    - "OutboxWorker.onEntryDelivered is a delivery-completion hook distinct from Outbox's own state machine — PlaySessionRecorder uses it to flip play_sessions_pending.delivered, a status outbox_entries itself cannot represent once a successfully-sent row is deleted"

key-files:
  created:
    - playstead-mac/Playstead/Sync/CurationIntent.swift
    - playstead-mac/Playstead/Sync/Outbox.swift
    - playstead-mac/Playstead/Sync/OutboxWorker.swift
    - playstead-mac/Playstead/Curation/FractionalPosition.swift
    - playstead-mac/Playstead/Curation/FavoritesViewModel.swift
    - playstead-mac/Playstead/Curation/FavoritesShelfView.swift
    - playstead-mac/Playstead/Curation/CollectionsViewModel.swift
    - playstead-mac/Playstead/Curation/CollectionsView.swift
    - playstead-mac/Playstead/Curation/CollectionDetailView.swift
    - playstead-mac/Playstead/Curation/QueueViewModel.swift
    - playstead-mac/Playstead/Curation/QueueShelfView.swift
    - playstead-mac/Playstead/Curation/ContinueViewModel.swift
    - playstead-mac/Playstead/Curation/ContinueShelfView.swift
    - playstead-mac/Playstead/Curation/RecentViewModel.swift
    - playstead-mac/Playstead/Curation/RecentShelfView.swift
    - playstead-mac/Playstead/Curation/PlaySessionRecorder.swift
    - playstead-mac/PlaysteadTests/CurationTests/OutboxTests.swift
    - playstead-mac/PlaysteadTests/CurationTests/OrderingTests.swift
    - playstead-mac/PlaysteadTests/CurationTests/PlaySessionTests.swift
  modified:
    - playstead-mac/Playstead/Net/APIClient.swift
    - playstead-mac/Playstead/Persistence/Migrations.swift
    - playstead-mac/Playstead/Persistence/CurationStore.swift
    - playstead-server/lib/playstead_web/controllers/api/v1/curation_controller.ex
    - playstead-server/lib/playstead_web/router.ex
    - playstead-server/test/playstead_web/controllers/api/v1/curation_controller_test.exs

key-decisions:
  - "Play sessions are delivered as sequential individual POSTs, not the plan's own 'batch into one request' language — the server's POST /api/v1/play-sessions (shipped in 03-04) accepts exactly one session per request, no array/batch shape exists. Individual posting is the plan's own named fallback for a partially-rejected batch, so this satisfies the intent without inventing an API the server can't accept."
  - "A remove/rename/delete/move-shaped intent's permanent rejection reverts to a no-op beyond marking the entry rejected — only a create-shaped intent's revert (delete the optimistically-inserted row) is implemented. Restoring a remove/rename/delete/move's exact prior state would need a stored row snapshot; no acceptance criterion in this plan exercises that path, and it is flagged in Known Stubs rather than silently assumed correct."
  - "Continue's dismiss-then-replay auto-restore (the server's list_continue/1 compares dismissed_at against the latest session start, read-side) has no equivalent client mechanism, because the curation journal's continue_dismissal payload carries no dismissed_at field to compare against locally. PlaySessionRecorder.began instead un-dismisses locally and explicitly the moment a new session starts for that asset set — same user-visible outcome, different mechanism, and it can drift from server truth in one narrow case (see Known Stubs)."

patterns-established:
  - "Every offline mutation follows: optimistic local write (CurationStore) inside the same transaction as the durable outbox insert -> OutboxWorker sends with the intent's own stable idempotencyKey -> success deletes the row; permanent rejection reverts+marks rejected+surfaces the code; transient failure leaves the row pending and stops draining (never sends a later entry out of order)"

requirements-completed: [LIBR-03]

coverage:
  - id: D1
    description: "A durable, per-row idempotent offline outbox: a favorite applies to the local read model immediately, survives an app restart while unsent, sends exactly once when reachable, reverts and surfaces a problem code on permanent rejection, and reconciles through the journal without duplicating"
    requirement: "LIBR-03"
    verification:
      - kind: unit
        ref: "PlaysteadTests/CurationTests/OutboxTests (9 tests, all pass)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Collections, the play queue, and Continue dismissals all work offline; a drag reorder settles to exactly one intent naming the moved item and its two neighbours (never a whole list); an offline reorder and a concurrent remote addition both survive; FractionalPosition matches the server's own base-36 encoding"
    requirement: "LIBR-03"
    verification:
      - kind: unit
        ref: "PlaysteadTests/CurationTests/OrderingTests (12 tests, all pass, including fixtures generated directly from the server's Position module via mix run)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Coarse play-session recording (identifier, asset set id, start, end only) is structurally incapable of delaying or failing a launch, delivers idempotently through the outbox after the fact, and is individually deletable by the user"
    requirement: "LIBR-03"
    verification:
      - kind: unit
        ref: "PlaysteadTests/CurationTests/PlaySessionTests (7 tests, all pass) — including a real AdapterHost.launch (via /bin/echo standing in for the pinned emulator) succeeding independently of a recorder whose every write throws, plus a source-grep asserting AdapterHost.swift references no session-store type"
        status: pass
    human_judgment: true
    rationale: "No interactive display session exists in this environment to visually verify the five shelf views (FavoritesShelfView/CollectionsView/CollectionDetailView/QueueShelfView/ContinueShelfView/RecentShelfView) against 03-UI-SPEC.md's exact spacing/typography/status vocabulary, or to exercise the SwiftUI .onMove drag gesture by hand — every claim above is verified at the logic/contract level (view-model state, SQL query results, source greps), matching 03-06's identical human_judgment precedent for its own shell views."

# Metrics
duration: ~40min
completed: 2026-08-30
status: complete
---

# Phase 3 Plan 8: Mac Curation Outbox and Play Sessions Summary

**A durable per-row SQLite outbox (favorites, collections, the play queue, Continue dismissals, play sessions) with client-generated natural keys and idempotency keys unchanged from Phase 1's mechanism, a Swift port of the server's fractional-index algorithm verified against live server fixtures, and play-session recording proven structurally incapable of touching the launch path.**

## Performance

- **Duration:** ~40 min
- **Tasks:** 3 of 3 completed
- **Files changed:** 25 (19 created, 6 modified — including one server-side fix)
- **Test suite:** 120/120 Mac tests pass (28 new: 9 OutboxTests + 12 OrderingTests + 7 PlaySessionTests), no regressions. Server suite: 871/871 pass (up from 846 before this plan).

## Accomplishments

- `Outbox`/`OutboxWorker` durably record every curation mutation (client-generated id + idempotency key, matching P1 D-20 exactly) inside the same transaction as the optimistic local write. `OutboxWorker` (an actor) drains pending entries in creation order: success deletes the row, a permanent 4xx reverts the optimistic local row and surfaces the server's problem code, a transport failure or 5xx leaves the row alone and stops draining rather than racing a later entry ahead of it.
- `CurationIntent` models all twelve mutation kinds (favorite add/remove, collection create/rename/delete/member-add/member-remove/member-move, queue enqueue/dequeue/move, continue dismiss, play-session record/delete), each with field names matching the server's changeset exactly.
- `FractionalPosition` is a digit-for-digit Swift port of `Playstead.Curation.Position`'s base-36 encoding, verified against fixtures generated by actually running the server's own module (`mix run`) — first/append/prepend/midpoint/spaced sequences and the amortized-growth stress case all match byte-for-byte.
- `CollectionsViewModel`/`QueueViewModel` expose a `beginReorder*`/`previewMove*`/`commitReorder*` API so a multi-step drag gesture writes nothing to the outbox until it settles, then enqueues exactly one move intent naming the moved item and its two neighbours — never a whole ordered list (D-09).
- `ContinueViewModel` derives Continue as recent-minus-dismissed; its shelf copy carries no promise about restoring saved progress.
- `PlaySessionRecorder` records sessions (id, asset set id, start, end — nothing else, D-07) to a dedicated table, delivered individually through the outbox after the fact. `AdapterHost` (unmodified by this plan) has zero reference to any session-store type anywhere in its launch signature — verified both by a real launch succeeding independently of a recorder whose every write is failing, and by a source-level grep.
- Fixed a genuine server-side gap found during this plan: `Playstead.Curation.dismiss_continue/3` existed for the LiveView console but had no REST endpoint for the Mac outbox to call at all.

## Task Commits

Task 1 followed the plan's `tdd="true"` RED→GREEN cycle (tracer):
1. `991628b` `test(03-08): add failing test for durable offline outbox (task 1)` (RED — verified for real: `Outbox`/`OutboxWorker`/`CurationIntent` did not exist yet, confirmed via `xcodebuild test` compile failure)
2. `0f9b020` `feat(03-08): durable offline outbox — favorite applied optimistically, replayed idempotently, reconciled by the journal (task 1)` (GREEN — 9/9 `OutboxTests` pass)

Per the tracer protocol, task 1's own `<verify>` was re-run end-to-end after GREEN and passed before task 2 began.

Task 2 also followed `tdd="true"` RED→GREEN:
3. `40a03aa` `test(03-08): add failing test for collections/queue/continue offline ordering (task 2)` (RED — confirmed compile failure)
4. `f6eaae6` `feat(03-08): collections, ordered queue, Continue dismissals, and Recent — offline (task 2)` (GREEN — 12/12 `OrderingTests` pass)

Task 3 is `type="auto"` (not TDD), matching plans 03-04/03-06's own convention — implementation and tests shipped together:
5. `0fd7a7e` `feat(03-08): play-session recording that can never touch the launch path (task 3)` (7/7 `PlaySessionTests` pass)

Plus one prerequisite fix committed before task 1 began (server-side, needed by task 2's continue-dismiss intent):
0. `43769ff` `fix(03-08): add missing continue-dismiss REST intent`

**Plan metadata:** this commit (docs: complete plan)

## Files Created/Modified

- `playstead-mac/Playstead/Sync/CurationIntent.swift` — all twelve intent kinds, envelope (de)serialization, HTTP method/path/body, idempotency key, optimistic apply/revert
- `playstead-mac/Playstead/Sync/Outbox.swift` — durable per-row queue: enqueue (atomic with optimistic apply), state transitions, listPending/listAll/listRejected
- `playstead-mac/Playstead/Sync/OutboxWorker.swift` — the draining actor: send, classify permanent-vs-transient, `onEntryDelivered` hook
- `playstead-mac/Playstead/Net/APIClient.swift` — general `send(method:path:queryItems:body:headers:)`; `get` is now a thin wrapper over it
- `playstead-mac/Playstead/Persistence/Migrations.swift` — `outbox_entries` and `play_sessions_pending` tables
- `playstead-mac/Playstead/Persistence/CurationStore.swift` — targeted-UPDATE helpers (rename, reposition) and fetch-by-id needed for optimistic apply/revert without clobbering unrelated columns
- `playstead-mac/Playstead/Curation/FractionalPosition.swift` — the base-36 fractional-index port
- `playstead-mac/Playstead/Curation/{Favorites,Collections,Queue,Continue,Recent}ViewModel.swift` — the five curation nouns' offline-first logic
- `playstead-mac/Playstead/Curation/{FavoritesShelfView,CollectionsView,CollectionDetailView,QueueShelfView,ContinueShelfView,RecentShelfView}.swift` — their SwiftUI views
- `playstead-mac/Playstead/Curation/PlaySessionRecorder.swift` — session recording, delivery, deletion
- `playstead-mac/PlaysteadTests/CurationTests/{OutboxTests,OrderingTests,PlaySessionTests}.swift` — 28 new tests
- `playstead-server/lib/playstead_web/controllers/api/v1/curation_controller.ex`, `router.ex`, and its test file — the missing continue-dismiss REST endpoint

## Decisions Made

See `key-decisions` in frontmatter — most consequential: play-session delivery is individual posts (the server has no batch endpoint), and a remove/rename/delete/move-shaped intent's rejection does not restore prior state (only create-shaped intents do, since only those have something to simply delete).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2/3 - Missing Critical / Blocking] `Playstead.Curation.dismiss_continue/3` had no REST endpoint**
- **Found during:** Pre-task-1 review of task 2's read_first files, confirming the endpoint this plan's `continueDismiss` intent needs to call actually exists
- **Issue:** The server context function existed (used by the LiveView console's `dismiss-continue` event) but `PlaysteadWeb.Api.V1.CurationController` and `router.ex` had no corresponding route — the Mac outbox would have had nothing to send `continueDismiss` intents to.
- **Fix:** Added `PUT /api/v1/curation/continue/:asset_set_id/dismiss`, mirroring `create_favorite/2`'s idempotent-PUT shape exactly, plus two controller tests.
- **Files modified:** `playstead-server/lib/playstead_web/controllers/api/v1/curation_controller.ex`, `router.ex`, `test/.../curation_controller_test.exs`
- **Verification:** New tests pass; full server suite (871 tests) passes with 0 failures, up from 846 before this plan.
- **Committed in:** `43769ff` (standalone prerequisite commit, before task 1)

**2. [Rule 3 - Blocking] `APIClient` had no method for anything but `GET`**
- **Found during:** Task 1, implementing `OutboxWorker`'s send path
- **Issue:** Every curation intent needs PUT/POST/PATCH/DELETE with a body and an `Idempotency-Key` header; `APIClient.get` only supported `GET`.
- **Fix:** Added a general `send(method:path:queryItems:body:headers:)`; `get` is now `send(method: "GET", ...)`. Fully backward compatible — every existing `get` call site is unchanged.
- **Files modified:** `playstead-mac/Playstead/Net/APIClient.swift`
- **Committed in:** `0f9b020` (task 1 GREEN commit)

**3. [Rule 1 - Bug, self-caught during test authoring] Move-intent neighbour assertion was wrong in the test itself, not the implementation**
- **Found during:** Task 2, first run of `test_moveIntentPayload_namesMovedItemAndTwoNeighboursOnly`
- **Issue:** The test asserted the wrong "before" neighbour for a member moved to the end of a 3-item list (asserted `"b"`, the correct value for that final ordering is `"c"`) — a test-authoring arithmetic error, not a `CollectionsViewModel`/`FractionalPosition` bug.
- **Fix:** Corrected the assertion; `CollectionsViewModel.commitReorderMembers`'s neighbour computation was already correct.
- **Files modified:** `playstead-mac/PlaysteadTests/CurationTests/OrderingTests.swift`
- **Verification:** Test passes; re-verified the neighbour-computation logic by hand against the final preview order.
- **Committed in:** `f6eaae6` (task 2 GREEN commit)

**4. [Rule 1 - Bug] The server has no play-session batch endpoint, contradicting this plan's own "batch pending sessions into one request" action text**
- **Found during:** Task 3, implementing `PlaySessionRecorder`'s delivery path
- **Issue:** `POST /api/v1/play-sessions` (shipped in plan 03-04) accepts exactly one session object per request — there is no array/batch body shape anywhere in the controller or router.
- **Fix:** Implemented sequential individual posting only, which the plan's own text names as "the correct fallback ... when a batch is partially rejected" — so the fallback path is simply the only path, and it satisfies every acceptance criterion (idempotent per session id, delivered after reachability returns) without inventing an API the server cannot accept.
- **Files modified:** None beyond the already-planned `PlaySessionRecorder.swift`
- **Verification:** `PlaySessionTests` exercises offline→online delivery and duplicate-post idempotency directly against the real single-session endpoint shape.
- **Committed in:** `0fd7a7e` (task 3 commit)

---

**Total deviations:** 4 auto-fixed (1 missing-critical-functionality server fix, 1 blocking client capability gap, 1 self-caught test-authoring bug, 1 plan-vs-server-reality correction). **Impact:** All were necessary for correctness or for this plan's own acceptance criteria to be genuinely provable rather than vacuously passing. No scope creep — the server-side fix stayed within the two files (`curation_controller.ex`, `router.ex`) plus their test file, the minimum needed to make `continueDismiss` reachable at all.

## Issues Encountered

- **`xcodebuild test -only-testing:PlaysteadTests/CurationTests` (this plan's own `<verification>` line, and every task's `<verify>` line using the same `PlaysteadTests/CurationTests` folder-style selector) silently selects zero tests** — the identical vacuous-selector bug plan 03-06 already flagged for its own `SyncTests`/`LibraryTests` folders (`-only-testing` requires `Target/TestClass`, not a containing folder). Confirmed via `xcrun xcresulttool`: `PlaysteadTests/CurationTests` matches no test class (the actual classes are `OutboxTests`, `OrderingTests`, `PlaySessionTests`, each living in that folder). Every verification claim in this SUMMARY instead used the correct per-class selectors (`-only-testing:PlaysteadTests/OutboxTests`, etc.) and the unscoped full-suite line, both of which genuinely ran and reported real pass counts. No plan-file edit made — flagged here for whichever plan writes 03-09/03-10's `<verify>` lines next, since the same folder-name pattern recurs there.
- The tailwind/esbuild binaries `mix test`'s asset-build alias needs were not present in this fresh worktree and this sandboxed environment has no outbound network access to fetch them; copied the already-cached binaries from the main checkout's `_build/` directory (not committed — `_build/` is gitignored) rather than attempting a network fetch. Purely a local environment setup step, not a code change.

## User Setup Required

None — no external service configuration required.

## Known Stubs

- **A remove/rename/delete/move-shaped intent's permanent rejection does not restore the row's prior state** — only the state-was-nothing→state-is-something direction (a create-shaped intent, reverted by deleting the row it inserted) is implemented. Restoring, say, a rejected rename back to its old name, or a rejected member-remove back to its prior row, would need a stored snapshot of the row before the optimistic write — no acceptance criterion in this plan exercises that path, and every such intent's `revertOptimistic` case is an explicit documented no-op (`CurationIntent.swift`), not a silent gap. A future plan touching rejection UX should close this if it becomes user-visible.
- **Continue's dismiss-then-replay auto-restore has a narrower mechanism than the server's** — the server's `list_continue/1` compares each dismissal's `dismissed_at` against the latest session's start time, read-side; the client instead un-dismisses locally and explicitly the instant `PlaySessionRecorder.began` records a new session for that asset set (`CurationStore.tombstoneContinueDismissalByAssetSet`'s doc comment explains why: the journal's `continue_dismissal` payload, from plan 03-04, carries no `dismissed_at` field to compare against). The user-visible outcome is identical for the common case (play the game again → it reappears in Continue), but if a dismissal syncs down from the console *after* the Mac already un-dismissed it locally, the two can briefly disagree until the next full sync. Closing this properly needs the server's journal payload to start carrying `dismissed_at` — out of this plan's file scope (`playstead-server/lib/playstead/sync/curation_payload.ex`).
- **No live visual/UAT pass on the five new shelf views** — this sandboxed session has no interactive display to render/screenshot `FavoritesShelfView`/`CollectionsView`/`CollectionDetailView`/`QueueShelfView`/`ContinueShelfView`/`RecentShelfView` against 03-UI-SPEC.md's exact spacing/typography, or to exercise the `.onMove` drag gesture by hand. Every claim is verified at the logic/contract level (view-model state, SQL results, source greps) — matching plan 03-06's identical, already-documented limitation for its own shell views.
- **App-shell wiring (attaching these five shelves to `SidebarView`'s sections, hiding empty ones from Home) is not done in this plan** — matching 03-06's own explicit deferral of `PlaysteadApp.swift`/`AppEnvironment`/`LibraryShellView` assembly, none of which were in either plan's file list. The five view models and views built here are the integration point for whichever plan first assembles the full running app window.
- **`PlaySessionRecorder` is not wired to `AdapterHost`'s actual launch/exit events** — by design (see this plan's own `<action>` text: "the recorder subscribes to the adapter host's published events," but `AdapterHost.swift` was not in this plan's file list and was left untouched). `AdapterHost.launch` currently takes a plain `onExit` closure, not a published-event stream; whichever future plan assembles the running app should call `PlaySessionRecorder.began`/`ended` from that closure (or extend `AdapterHost` with a proper event publisher first) — the recorder itself is ready and independently tested for that integration.

## Next Phase Readiness

- **This plan is `status: complete`.** `LIBR-03` is complete in `requirements-completed` above.
- `Outbox`, `OutboxWorker`, `CurationIntent`, `FractionalPosition`, and all five curation view models/views are ready for plan 03-09 (preflight/readiness) and 03-10 (controller remap, notarized build) to build on directly.
- `PlaySessionRecorder` is ready for whichever plan assembles the running app to wire into `AdapterHost`'s launch/exit closure — see Known Stubs.
- No blockers for downstream plans in this phase.

---
*Phase: 03-mac-offline-play-vertical-slice*
*Completed: 2026-08-30*

## Self-Check: PASSED

- All `key-files.created` verified present on disk.
- `git log --oneline --all --grep="03-08"` returns all 6 commits (`43769ff`, `991628b`, `0f9b020`, `40a03aa`, `f6eaae6`, `0fd7a7e`) plus this SUMMARY's own metadata commit.
- Re-ran every task's `<acceptance_criteria>` via the corrected per-class selectors: `OutboxTests` 9/9, `OrderingTests` 12/12, `PlaySessionTests` 7/7 — all pass.
- Re-ran the plan-level `<verification>`'s unscoped full-suite line (`xcodebuild test -scheme Playstead`): 120/120 pass, no regressions.
- Re-ran the full server suite (`mix test`): 871/871 pass, 0 failures (up from 846 before this plan).
