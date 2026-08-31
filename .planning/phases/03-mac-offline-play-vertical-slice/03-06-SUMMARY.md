---
phase: 03-mac-offline-play-vertical-slice
plan: 06
subsystem: sync
tags: [swift, swiftui, sqlite, urlsession, change-journal, cursor, curation, offline-first, design-system]

# Dependency graph
requires:
  - phase: 03-mac-offline-play-vertical-slice (03-03)
    provides: "Playstead.xcodeproj synchronized-group setup, APIClient/SnapshotClient/LocalStore, SQLiteConnection"
  - phase: 03-mac-offline-play-vertical-slice (03-04)
    provides: "Server curation entity kind riding the snapshot/journal/cursor spine — six payload types (favorite, collection, collection_member, queue_item, continue_dismissal, recent)"
  - phase: 03-mac-offline-play-vertical-slice (03-UI-SPEC.md, /gsd-ui-phase 3)
    provides: "Locked design contract: status glyph vocabulary + priority ladder, navigation noun order, empty-state copy, System Identity vs Status Ladder color vocabularies, motion/focus spec, accessibility floor — shared verbatim with plan 03-05's LiveView console"
provides:
  - "SyncEngine actor: snapshot bootstrap (paged via next_after_id/has_more), cursor-resumed /api/v1/changes paging, cursor-expired reset, SyncState (neverSynced/syncing/synced/offline)"
  - "CatalogueStore/CurationStore: incremental upsert/tombstone read model over catalogue_entries/catalogue_members and the six curation_* tables, plus an indexed search/system/availability filtered query"
  - "CursorStore: opaque cursor round-trip storage, never parses/derives a cursor value"
  - "JournalApplier: entity-kind/payload-type dispatch, unknown-kind skip-and-count, idempotent replay"
  - "The full library shell UI: DesignTokens/SystemAccent/StatusToken, SidebarView (frozen 8-step nav order), ShelfView/GameCardView/GameListView, StatusSlotView (7-state priority ladder), SearchField/FilterChipRow/ShowAllSystemsControl, FirstRunBanner, LibraryViewModel"
affects: [03-07, 03-08, 03-09, 03-10]

actuals:
  tokens: 31606
  tasks: 3
  commits: 5

tech-stack:
  added: []
  patterns:
    - "SQLiteConnection.onQueue(_:) uses a DispatchSpecificKey to detect reentrant calls from inside transaction(_:), so table-owning stores can call execute/query from within a caller-wrapped transaction without a queue.sync deadlock/crash"
    - "SyncEngine owns its own SnapshotEnvelope decode (curation branch + next_after_id) rather than widening 03-03's narrow SnapshotClient/SnapshotResponse, which stays scoped to its one full-replace tracer bootstrap call"
    - "JournalApplier treats a snapshot's curation array elements as synthesized JournalEntry upserts (entity_kind: curation, a locally-derived entity_id), so snapshot-sourced and journal-sourced curation rows converge through the exact same apply path"
    - "CatalogueStore.filteredQuery binds every search/system/availability value as a prepared-statement parameter through an indexed search_blob/system/availability column set — never string-interpolated into the SQL text itself (T-03-18)"
    - "Design-system color/type tokens declared as hex-literal-traceable Swift constants (DesignTokens/SystemAccent/StatusToken), so 03-UI-SPEC.md's hex table and the source are visually diffable in code review"

key-files:
  created:
    - playstead-mac/Playstead/Sync/SyncEngine.swift
    - playstead-mac/Playstead/Sync/ChangesClient.swift
    - playstead-mac/Playstead/Sync/CursorStore.swift
    - playstead-mac/Playstead/Sync/JournalApplier.swift
    - playstead-mac/Playstead/Persistence/CatalogueStore.swift
    - playstead-mac/Playstead/Persistence/CurationStore.swift
    - playstead-mac/Playstead/Design/DesignTokens.swift
    - playstead-mac/Playstead/Design/SystemAccent.swift
    - playstead-mac/Playstead/Design/StatusToken.swift
    - playstead-mac/Playstead/Library/SidebarView.swift
    - playstead-mac/Playstead/Library/ShelfView.swift
    - playstead-mac/Playstead/Library/GameCardView.swift
    - playstead-mac/Playstead/Library/StatusSlotView.swift
    - playstead-mac/Playstead/Library/SystemMonogramView.swift
    - playstead-mac/Playstead/Library/LibraryViewModel.swift
    - playstead-mac/Playstead/Library/FirstRunBanner.swift
    - playstead-mac/Playstead/Library/SearchField.swift
    - playstead-mac/Playstead/Library/FilterChipRow.swift
    - playstead-mac/Playstead/Library/GameListView.swift
    - playstead-mac/Playstead/Library/ShowAllSystemsControl.swift
    - playstead-mac/PlaysteadTests/SyncTests/SyncEngineTests.swift
    - playstead-mac/PlaysteadTests/LibraryTests/StatusLadderTests.swift
    - playstead-mac/PlaysteadTests/LibraryTests/FilterTests.swift
  modified:
    - playstead-mac/Playstead/Persistence/Migrations.swift
    - playstead-mac/Playstead/Persistence/LocalStore.swift
    - playstead-mac/Playstead/Persistence/SQLiteConnection.swift
    - playstead-mac/Playstead/Net/APIClient.swift

key-decisions:
  - "APIClient gained queryItems: [URLQueryItem] and injectable session/credential overrides — required for GET /api/v1/changes?cursor=… (URL.appendingPathComponent cannot carry a query string) and for headless SyncEngineTests/FilterTests to run against a URLProtocol stub, avoiding 03-03's documented Keychain 'dark wake' failure in this sandboxed environment."
  - "SQLiteConnection.execute/query detect (via DispatchSpecificKey) when already running on their own queue inside transaction(_:) and skip the redundant queue.sync — the original unconditional queue.sync crashed with 'dispatch_sync called on queue already owned by current thread' the instant any store method ran inside a transaction closure, which is exactly the pattern this task's page-apply discipline (Task 1's own <action> text) requires."
  - "LocalStore now exposes its SQLiteConnection and a transaction(_:) passthrough; CatalogueStore/CurationStore/CursorStore own their tables' read/write logic directly rather than LocalStore growing a method per table."
  - "SyncEngine decodes its own SnapshotEnvelope (curation branch, next_after_id) instead of widening 03-03's SnapshotClient/SnapshotResponse, which stays exactly as narrow as that tracer plan needed it."
  - "SidebarView uses SwiftUI's .listStyle(.sidebar) (NSOutlineView-backed under the hood on macOS) rather than a hand-rolled NSViewRepresentable — satisfies 'AppKit-backed source list' without adding bespoke AppKit bridging code this plan's file list didn't call for."
  - "catalogue_entries gained an availability column that upsert never touches (setAvailability/availability(forID:) are the only writers) — no download engine wires real values through it until a later plan (03-07/08); this still proves the search+system+availability intersection semantics FilterTests requires against real SQL."
  - "LibraryStatus intentionally has 7 cases (not 6) to match 03-UI-SPEC.md's Status Vocabulary table exactly — needsAttention/missingDependency/downloading/queued/pinned/verified/serverOnly, with pinned and verified sharing rank 5 (pinned always implies verified, D-21) rather than collapsing them into one case as the plan's own prose summary ('verified or pinned') might suggest; the locked UI-SPEC table, which lists them as two distinct rows with distinct glyphs/badges/accessible names, is the authoritative source."

patterns-established:
  - "Every apply (catalogue or curation, upsert or tombstone) is keyed on entity id and idempotent by construction (SQL upsert / DELETE-if-exists), so replaying a page after an interrupted apply is always safe."
  - "SyncState has no bare failure case — offline reads as .offline(since:) or .neverSynced, never a hard error, matching the phase's 'being offline is a normal state' contract."
  - "SwiftUI views in this codebase expose their derived-label/selection logic as static/pure functions (GameCardView.accessibleLabel, FilterChipRow.isSelected, ShowAllSystemsControl.label, LibraryStatus.accessibleName) precisely so headless XCTest (no ViewInspector dependency) can assert the same computation the view renders, without needing a hosting window."

requirements-completed: [LIBR-01, LIBR-02, LIBR-04]

coverage:
  - id: D1
    description: "The Mac's local read model converges with the server through the snapshot/journal/cursor recovery spine alone: empty-store bootstrap (catalogue + curation), cursor-resumed changes paging, cursor-expired full reset with no duplicates, idempotent replay, unknown-entity-kind forward compatibility, and a transport failure leaving the stored cursor and read model byte-identical/untouched"
    requirement: "LIBR-01"
    verification:
      - kind: unit
        ref: "PlaysteadTests/SyncTests/SyncEngineTests (11 tests, all pass)"
        status: pass
      - kind: other
        ref: "xcodebuild test -scheme Playstead -destination 'platform=macOS' (full suite, 50 tests) — all pass, no regressions"
        status: pass
    human_judgment: false
  - id: D2
    description: "The library has its canonical 8-step navigation order, one status vocabulary matching 03-UI-SPEC.md's locked ladder table, honest empty states (first-run banner, zero-import invitation, per-shelf empty explanations), and card geometry/typography that never uses cover art or title-derived color"
    requirement: "LIBR-04"
    verification:
      - kind: unit
        ref: "PlaysteadTests/LibraryTests/StatusLadderTests (9 tests, all pass): highest-ranked-wins across the full ladder, distinct glyph+full-sentence accessible name per state, SystemAccent/StatusToken disjoint value sets, safeToEvict absent from the card ladder, empty-title fallback, fixed card geometry for a 500-entry snapshot, frozen 8-step sidebar order (Home/Continue never merged), Unidentified hidden when absent, no placeholder/generated-art vocabulary via source grep"
        status: pass
      - kind: other
        ref: "grep -rniE 'placeholderImage|boxArt|coverArt|hash.*[Cc]olor' playstead-mac/Playstead/Library/ playstead-mac/Playstead/Design/ — no match"
        status: pass
    human_judgment: true
    rationale: "Visual/typographic fidelity (exact spacing, color rendering, motion timing feel) and true GameController-framework directional-pad input were not exercised — this environment has no interactive display session to render/screenshot SwiftUI views, and no GameController hardware wiring was in this plan's file scope (native SwiftUI focus/keyboard navigation is what's implemented; explicit controller input mapping is deferred to plan 03-10 per the phase's architecture map). A human on an interactive Mac session should visually confirm the shell against 03-UI-SPEC.md once real catalogue data flows through it."
  - id: D3
    description: "A user can find anything in a large library by search (display title and original filename, diacritic-insensitive), system, or availability, from keyboard or pointer; controller narrows via chips only (no on-screen keyboard, by design); a search matching nothing explains itself with a clear control; the library renders its full local entry count and a last-synced indicator with every network request stubbed to fail; systems with zero entries are hidden behind a count-labeled control"
    requirement: "LIBR-02"
    verification:
      - kind: unit
        ref: "PlaysteadTests/LibraryTests/FilterTests (7 tests, all pass): filename-substring search, no-matches state with query+clear-control, diacritic/case-insensitive search, system+availability chip intersection, chip selection model, show-all-systems hidden count and label toggle, full offline render with a stubbed-to-fail network and a non-nil last-synced description"
        status: pass
      - kind: other
        ref: "xcodebuild test -scheme Playstead -destination 'platform=macOS' (full suite, 50 tests) — all pass"
        status: pass
    human_judgment: false

# Metrics
duration: 145min
completed: 2026-08-30
status: complete
---

# Phase 3 Plan 6: Mac Sync Engine and Library Shell Summary

**A Swift actor converges the Mac's local SQLite catalogue+curation mirror with the server through the snapshot/journal/cursor spine alone (survives cursor expiry, replays idempotently, treats offline as normal), underneath a typographic, controller-and-keyboard-navigable library shell built exactly to 03-UI-SPEC.md's locked design contract — source list, shelves, cards, the 7-state status ladder, search, and filter chips.**

## Performance

- **Duration:** ~145 min total across two sessions (Task 1 ~55 min; Tasks 2–3 ~90 min, resumed after `/gsd-ui-phase 3` produced `03-UI-SPEC.md` on `main` mid-session — see "Resumption" below)
- **Tasks:** 3 of 3 completed
- **Files changed:** 27 (23 created, 4 modified)
- **Test suite:** 50/50 tests pass (11 `SyncEngineTests` + 9 `StatusLadderTests` + 7 `FilterTests` + 23 pre-existing), no regressions

## Resumption note

This plan halted after Task 1 in its first execution because Task 2's `<precondition>` — `.planning/phases/03-mac-offline-play-vertical-slice/03-UI-SPEC.md` must exist — was genuinely unmet (verified absent; see the git history's now-superseded halt commit `2175ce4`). The coordinator confirmed `/gsd-ui-phase 3` produced and checker-approved that file on `main` (commit `d5fd81e`) while this worktree was still running, forked before that commit. Per the coordinator's explicit instruction, the file was **read** from the main checkout's absolute path (`~/projects/playstead/.planning/phases/03-mac-offline-play-vertical-slice/03-UI-SPEC.md`) — outside this worktree, which the path-safety guard permits since it restricts writes, not reads — and treated as the locked design contract for Tasks 2 and 3. It was never copied or committed into this worktree; it reaches `main` independently through its own commit.

## Accomplishments

- `SyncEngine` (an actor) converges the local SQLite read model with the server through the D-21 snapshot/journal/cursor spine alone: bootstraps from `/api/v1/snapshot` when no cursor is stored (paging via `next_after_id`/`has_more`, every page pinned to the first page's own returned cursor), otherwise pages `/api/v1/changes` from the stored cursor and commits the new cursor only after each page's transaction commits.
- `JournalApplier` dispatches every entry by `entity_kind` (`catalogue`/`curation`) and, for curation, further by the payload's `type` field across all six shapes. An unrecognised kind or type is skipped and counted, never a hard failure. Every apply is an idempotent upsert/delete keyed on entity id, proven directly and via a full cursor-expired reset that produces exactly the fresh snapshot's row set with zero duplicates.
- The library shell renders the frozen 8-step sidebar order (Home, Continue, Favorites, Collections, Queue, Recent, non-empty systems in registry order, Unidentified last-and-only-if-present — Home and Continue never merged), fixed 280×158 landscape cards with no cover art or title-derived color, and the exact 7-state/6-rank status ladder from 03-UI-SPEC.md's locked table (`SystemAccent` and `StatusToken` share no color value, per D-13).
- `CatalogueStore.filteredQuery` answers search (display title + original filename, diacritic/case-insensitive), system, and availability filtering as one indexed SQL `WHERE` clause with every value bound as a prepared-statement parameter (T-03-18) — never string-interpolated into the SQL text. A search matching nothing renders `NoMatchesView`'s heading/body/clear-control rather than a blank pane.
- `LibraryViewModel.isOffline`/`lastSyncedDescription()` let the library keep rendering its full local entry count with a quiet "Last synced {relative time}" indicator when every network request is stubbed to fail — offline reads as a normal state, never an error page (EXPERIENCE-ETHOS #7).

## Task Commits

1. **Task 1 (tracer + TDD): Sync engine — snapshot bootstrap, cursor-resumed journal apply, and expiry reset**
   - `0d0fd90` `test(03-06): add failing test for sync engine snapshot/journal/cursor convergence` (RED — verified for real: implementation files temporarily moved out of the target, `xcodebuild test` failed to compile, then restored before committing)
   - `ca9d057` `feat(03-06): sync engine — snapshot bootstrap, cursor-resumed journal apply, expiry reset` (GREEN — all 11 `SyncEngineTests` pass)
2. **Task 2 (auto): Library shell — source list, shelves, cards, and the status vocabulary**
   - `5aaa389` `feat(03-06): library shell — source list, shelves, cards, status vocabulary`
3. **Task 3 (auto): Finding things — search, filter chips, sortable list, show-all-systems, and offline browse**
   - `7b2ae5d` `feat(03-06): search, filter chips, sortable list, show-all-systems, offline browse`

(An intermediate `docs(03-06)` commit, `2175ce4`, recorded the Task-1-only halt in the first execution session; it is superseded by this SUMMARY and Tasks 2–3's commits above, all on this same worktree branch.)

No REFACTOR commit — the `SQLiteConnection` reentrancy fix (see Task 1's Deviations, carried forward below) was needed to reach GREEN in the first place and is folded into that GREEN commit; no further cleanup was warranted in Tasks 2–3.

## TDD Gate Compliance

Task 1 (`type="tracer" tdd="true"`) followed the RED→GREEN cycle: `test(03-06)` commit `0d0fd90` precedes `feat(03-06)` commit `ca9d057`. RED was verified for real. No REFACTOR commit was needed. Tasks 2 and 3 are `type="auto"` (not TDD) — each shipped as one commit with its tests included, matching this plan's own convention (see plan 03-04's SUMMARY for the identical precedent).

Per the tracer protocol, Task 1's own `<verify>` was re-run end-to-end after its GREEN commit (via the corrected `-only-testing:PlaysteadTests/SyncEngineTests` identifier — see Deviation 4 below) and passed before Task 2 was attempted.

## Files Created/Modified

- `playstead-mac/Playstead/Sync/{SyncEngine,ChangesClient,CursorStore,JournalApplier}.swift` — the sync spine (Task 1)
- `playstead-mac/Playstead/Persistence/{CatalogueStore,CurationStore}.swift` — incremental read-model stores (Task 1), `CatalogueStore` extended with the filtered query (Task 3)
- `playstead-mac/Playstead/Persistence/{Migrations,LocalStore,SQLiteConnection}.swift` — schema, transaction passthrough, reentrancy fix (Task 1); `Migrations` extended with `search_blob`/`availability` columns+indexes (Task 3)
- `playstead-mac/Playstead/Net/APIClient.swift` — `queryItems:`, injectable `session`/`credential` (Task 1)
- `playstead-mac/Playstead/Design/{DesignTokens,SystemAccent,StatusToken}.swift` — the two disjoint color vocabularies, type/spacing scale, frozen `SystemRegistry` (Task 2)
- `playstead-mac/Playstead/Library/{SidebarView,ShelfView,GameCardView,StatusSlotView,SystemMonogramView,LibraryViewModel,FirstRunBanner}.swift` — the library shell (Task 2); `LibraryViewModel` extended with search/filter/offline state (Task 3)
- `playstead-mac/Playstead/Library/{SearchField,FilterChipRow,GameListView,ShowAllSystemsControl}.swift` — finding things (Task 3)
- `playstead-mac/PlaysteadTests/SyncTests/SyncEngineTests.swift` (Task 1), `PlaysteadTests/LibraryTests/{StatusLadderTests,FilterTests}.swift` (Tasks 2–3)

## Decisions Made

See `key-decisions` in frontmatter — most consequential: the `SQLiteConnection` reentrancy fix (a crash, not a mere assertion failure) and treating 03-UI-SPEC.md's 7-row Status Vocabulary table (not the plan's own summarized "verified or pinned" prose) as the authoritative ladder shape.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `APIClient.get` had no way to attach a query string**
- **Found during:** Task 1, implementing `ChangesClient.fetch(after:)`
- **Fix:** Added `queryItems: [URLQueryItem] = []`, applied via `URLComponents`. Backward compatible.
- **Files modified:** `playstead-mac/Playstead/Net/APIClient.swift`
- **Committed in:** `ca9d057`

**2. [Rule 3 - Blocking] `APIClient` had no seam for headless testing (real Keychain, hardcoded session)**
- **Found during:** Task 1, writing `SyncEngineTests`
- **Fix:** Added optional `session:`/`credential:` init params, defaulting to existing real behavior. Reused again in `FilterTests`' offline test (Task 3).
- **Files modified:** `playstead-mac/Playstead/Net/APIClient.swift`
- **Committed in:** `ca9d057`

**3. [Rule 1 - Bug] `SQLiteConnection`'s `queue.sync` was not reentrant — crashed the instant a store method ran inside `transaction(_:)`**
- **Found during:** Task 1, first full test run — a hard libdispatch crash (`dispatch_sync called on queue already owned by current thread`), not an assertion failure, in every test exercising a real transactional page apply.
- **Fix:** Added a per-instance `DispatchSpecificKey<Void>` and a shared `onQueue(_:)` helper (standard GCD reentrant-queue pattern).
- **Files modified:** `playstead-mac/Playstead/Persistence/SQLiteConnection.swift`
- **Verification:** All previously-crashing tests pass; full 50-test suite green.
- **Committed in:** `ca9d057`

**4. [Rule 1 - Bug] The plan's own `<verify>` commands select zero tests**
- **Found during:** Task 1 (and reconfirmed for Tasks 2/3), running the tracer's `<verify>`
- **Issue:** `-only-testing:PlaysteadTests/SyncTests` / `.../LibraryTests` address the containing source **folder**, not a test **class** — `-only-testing` requires `Target/TestClass`. The actual classes are `SyncEngineTests`, `StatusLadderTests`, `FilterTests`. Running the plan's literal commands produces `"totalTestCount": 0` (confirmed via `xcrun xcresulttool get test-results summary`) — a vacuous, silent "success."
- **Fix:** Ran `-only-testing:PlaysteadTests/SyncEngineTests`, `.../StatusLadderTests`, `.../FilterTests` (and the unscoped full-suite line) instead for actual verification. No plan-file edit — flagged here for whoever authors plans 03-07/08/09/10's `<verify>` lines, which follow the same folder-name pattern.
- **Files modified:** None (verification-only correction).
- **Committed in:** N/A

**5. [Rule 2 - Missing Critical, flagged not silently worked around] The server's snapshot `curation` branch payload carries no row id**
- **Found during:** Task 1, implementing snapshot-bootstrap curation convergence
- **Fix (bounded, not a silent workaround):** `SyncEngine.synthesizedCurationEntry(from:)` builds a local key from each type's own natural unique key when no `id` is present — matching the server's own unique index for `favorite`/`continue_dismissal`/`queue_item`/`collection_member`. `collection` has no natural key in this payload shape and falls back to `name` (not guaranteed unique) — see Known Stubs.
- **Files modified:** `playstead-mac/Playstead/Sync/SyncEngine.swift`
- **Committed in:** `ca9d057`

**6. [Rule 1 - Bug] `LibraryStatus`'s case count: 7, not 6, to match the locked UI-SPEC table exactly**
- **Found during:** Task 2, implementing `StatusSlotView` against the now-available `03-UI-SPEC.md`
- **Issue:** Plan 03-06's own `<action>` prose ("needs-attention outranks a missing dependency, which outranks downloading, which outranks queued, which outranks verified or pinned, which outranks server-only") reads as 6 ladder groups. The now-authoritative `03-UI-SPEC.md` Status Vocabulary table lists `pinned` and `verified` as two distinct rows — distinct glyphs (`mappin.circle.fill` vs `checkmark.circle.fill`), distinct badge shapes, distinct accessible-name sentences — sharing rank 5, not one collapsed case.
- **Fix:** Implemented `LibraryStatus` with 7 cases (`needsAttention`, `missingDependency`, `downloading`, `queued`, `pinned`, `verified`, `serverOnly`), `pinned`/`verified` sharing `rank == 5`. `StatusLadderTests` exercises all 7 for distinct glyphs and rank ordering.
- **Files modified:** `playstead-mac/Playstead/Library/StatusSlotView.swift`, `playstead-mac/PlaysteadTests/LibraryTests/StatusLadderTests.swift`
- **Committed in:** `5aaa389`

**7. [Rule 3 - Blocking] `CatalogueEntry`'s existing schema has no searchable-filename or availability data**
- **Found during:** Task 3, implementing `CatalogueStore.filteredQuery`
- **Fix:** Added `search_blob` (folded title + all member declared names, populated on every `upsert`) and `availability` (a new, separately-settable column `upsert` never touches, defaulting to `"server_only"`) columns + indexes to `catalogue_entries`, plus defensive `ALTER TABLE ... ADD COLUMN` statements (via `try?`) so a pre-03-06 dev database upgrades in place rather than only a brand-new one getting the columns.
- **Files modified:** `playstead-mac/Playstead/Persistence/{Migrations,CatalogueStore}.swift`
- **Committed in:** `7b2ae5d`

---

**Total deviations:** 7 auto-fixed (3 blocking API/schema gaps, 2 blocking bugs — one a crash, one a vacuous-verification command, 1 verification-command correction folded into #4 above, 1 flagged missing-critical/known-gap workaround, 1 spec-fidelity correction against the now-available locked contract). **Impact:** All were necessary for correctness, for this task's own explicit testability requirements, or to genuinely match the locked design contract rather than an earlier prose summary of it. The curation-snapshot-id gap (Deviation 5) is a real, bounded, documented limitation inherited from a completed sibling plan (03-04) outside this plan's file scope to fix.

## Issues Encountered

- **Task 2's `<precondition>` (`03-UI-SPEC.md` must exist) was genuinely unmet at this plan's first execution attempt** — resolved by the coordinator's mid-session resumption once `/gsd-ui-phase 3` produced and checker-approved the file on `main`. See "Resumption note" above for the full account, including how the file was consumed (read from the main checkout's absolute path, never copied/committed into this worktree).
- No other issues beyond the deviations documented above, each resolved during its originating task.

## User Setup Required

None — no external service configuration required.

## Known Stubs

- **`SyncEngine.synthesizedCurationEntry(from:)`'s `collection` fallback key is the collection's `name`, not a stable id** (Deviation 5). Inherited from plan 03-04's `Playstead.Sync.CurationPayload.build/1`, out of this plan's file scope (`playstead-server/`) to fix directly; a future plan should add `id` to all six of that function's clauses.
- **`catalogue_entries.availability` has no real writer yet** — every row defaults to `"server_only"` until the download engine (plan 03-07/08) calls `CatalogueStore.setAvailability`. The filter/search UI is fully functional against real SQL today; it just has nothing but `"server_only"` to show until that wiring lands.
- **True GameController-framework directional-pad input is not wired.** `FilterChipRow`/`ShelfView`/`SidebarView` are standard SwiftUI views with native keyboard/pointer focus support; 03-UI-SPEC.md's "navigable by directional pad" language is satisfied at the *design* level (chip/shelf layout, focus-ring token, accessibility traits) but explicit `GameController.framework` event handling was not in this plan's file list and does not exist anywhere in this codebase yet. Expected in a later plan (03-10, controller remap) per the phase's architecture map — flagged here so that plan's author knows this shell's views are the integration point, not a placeholder needing rebuilding.
- **No live visual/UAT pass.** This sandboxed session has no interactive display to render/screenshot the actual SwiftUI output against 03-UI-SPEC.md's exact spacing/color/motion feel — every claim above is verified at the logic/contract level (pure computed properties, SQL query results, source greps), never by looking at rendered pixels. See coverage `D2`'s `human_judgment: true` rationale.

## Next Phase Readiness

- **This plan is now `status: complete`.** `LIBR-01`, `LIBR-02`, and `LIBR-04` are all marked complete in `requirements-completed` above.
- `SyncEngine`, `CatalogueStore`, `CurationStore`, and every Library/Design-layer view/view-model are ready for plans 03-07 (storage/reclaim view), 03-08 (Mac curation outbox), 03-09 (LiveView curation console parity — same UI-SPEC contract), and 03-10 (controller remap, notarized build) to build on directly.
- **App-shell wiring is not done in this plan.** `PlaysteadApp.swift`/`AppEnvironment` and the pre-existing `LibraryShellView.swift` (from plan 03-03) were not in this plan's declared file list and were left untouched — assembling `SidebarView` + `ShelfView`/`GameListView` + `LibraryViewModel` into the actual app window (replacing `LibraryShellView`) is the next integration step, likely owned by whichever plan first needs the full app to run end-to-end against a live server.
- A human with an interactive (non-headless) Mac session should run the assembled shell against a live paired server once real catalogue/curation data exists, to close the visual/UAT gap noted in Known Stubs.

---
*Phase: 03-mac-offline-play-vertical-slice*
*Completed: 2026-08-30*

## Self-Check: PASSED

- All `key-files.created` verified present on disk (spot-checked with `[ -f ]`; full list matches `git diff --stat` across this plan's five commits).
- `git log --oneline --all --grep="03-06"` returns 5 commits: `0d0fd90` (RED), `ca9d057` (GREEN, Task 1), `2175ce4` (superseded halt doc), `5aaa389` (Task 2), `7b2ae5d` (Task 3).
- Re-ran every task's `<acceptance_criteria>`: all pass (see coverage `D1`/`D2`/`D3`'s `verification` lists above).
- Re-ran the corrected per-class `<verify>` commands (`-only-testing:PlaysteadTests/{SyncEngineTests,StatusLadderTests,FilterTests}`): 27/27 pass. Re-ran the plan-level `<verification>`'s full-suite line (`xcodebuild test -scheme Playstead`, unscoped): 50/50 pass, no regressions.
- Re-ran the acceptance-grep for placeholder/generated-art vocabulary: `grep -rniE 'placeholderImage|boxArt|coverArt|hash.*[Cc]olor' playstead-mac/Playstead/Library/ playstead-mac/Playstead/Design/` — no match.
