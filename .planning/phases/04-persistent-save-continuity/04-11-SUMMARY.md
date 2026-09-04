---
phase: 04-persistent-save-continuity
plan: 11
subsystem: ui
tags: [swift, swiftui, sqlite, save-state, divergence, offline, outbox]

requires:
  - phase: 04-persistent-save-continuity
    provides: "04-09's SaveStateModel/SaveRollup/SaveHistorySheet and shared/save-vocabulary.json's locked divergence/comparison-sheet copy"
  - phase: 04-persistent-save-continuity
    provides: "04-10's saves-owned attention source pattern and console inspect/choose/keep-both surface, both mirrored client-side here"
  - phase: 04-persistent-save-continuity
    provides: "04-05's append-only divergence resolution model (Branches.heads/2, resolve_divergence/4, acknowledge_divergence/3) that this client's local resolver agrees with"
provides:
  - "SaveAttentionSource: a pure Mac-side attention source unioning divergence and blocked-capture items into the card's existing rank-1 needsAttention rung, with exact-head-set fork-disposition suppression (SaveStore.fetchHeads + save_fork_dispositions)"
  - "ConflictComparisonSheet: the four-facts-per-side comparison view (D-50 through D-55), keyboard-native, zero ranking, zero Undo, with a UI-testing-only harness (PLAYSTEAD_UI_TEST_CONFLICT_COMPARISON=1) proving real keyboard operability"
  - "SaveConflictResolver + SaveIntent + SaveOutbox: local-mutation-plus-one-outbox-entry-in-one-transaction resolution that works fully offline, targeting the server's existing /resolve and /acknowledge routes"
affects: [04-12, 04-13]

actuals:
  tokens: 21000
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "A pure attention-source function taking already-resolved candidates (SaveAttentionCandidate) and an injected disposition lookup, never touching a database itself -- same decoupling precedent as SaveHistorySession.deviceName, kept this way so the whole divergence-vs-disposition decision is unit-testable with zero SQLite fixture"
    - "Exact sorted-head-id-set matching for fork disposition suppression (SaveStore.save_fork_dispositions), mirroring the server's fork_acknowledged?/3 rule verbatim so client and server never disagree about which fork is 'done'"
    - "A second, sibling durable outbox (SaveOutbox) inside Outbox.swift reusing Outbox.enqueue's exact one-transaction crash-safety discipline against its own table/kind vocabulary, rather than widening CurationIntentKind -- the same 'own table, own vocabulary, never share the original's' pattern 04-10 used server-side for the saves attention table"
    - "A UI-testing-only production seam (ConflictComparisonHarnessRootView, env-var-gated) presenting a view directly as the app root so PlaysteadUITests -- which cannot @testable import Playstead -- can still drive real AppKit/SwiftUI keyboard focus against it, following UITestBootstrap's save-e2e hook precedent"

key-files:
  created:
    - playstead-mac/Playstead/Saves/SaveAttentionSource.swift
    - playstead-mac/Playstead/Saves/ConflictComparisonSheet.swift
    - playstead-mac/Playstead/Saves/SaveConflictResolver.swift
    - playstead-mac/Playstead/Saves/SaveIntent.swift
    - playstead-mac/PlaysteadTests/SavesTests/SaveConflictResolverTests.swift
    - playstead-mac/PlaysteadTests/SnapshotTests/ConflictComparisonContractSnapshotTests.swift
    - playstead-mac/PlaysteadUITests/ConflictResolutionInteractionTests.swift
  modified:
    - playstead-mac/Playstead/Library/StatusSlotView.swift
    - playstead-mac/Playstead/Persistence/Migrations.swift
    - playstead-mac/Playstead/Persistence/SaveStore.swift
    - playstead-mac/Playstead/Sync/Outbox.swift
    - playstead-mac/Playstead/App/PlaysteadApp.swift
    - playstead-mac/PlaysteadTests/SnapshotTests/PlaysteadSnapshot.swift
    - playstead-mac/TestPlans/Rendering.xctestplan
    - playstead-mac/TestPlans/UI.xctestplan

key-decisions:
  - "Fork disposition suppression uses exact sorted-head-id-set matching (one row per line, upserted), not a running acknowledgment log -- mirrors the server's fork_acknowledged?/3 comparison exactly, and cleanly separates 'is this fork still undecided' (head-set-scoped) from 'is this exact repeat call a no-op' (action+chosen-revision-scoped), which is what lets switching back to the other side proceed while an exact repeat does not"
  - "SaveConflictResolver never touches save_revision at all -- resolution is entirely a new save_fork_dispositions row plus one outbox entry, since the local schema (unlike the server's) has no multi-parent DAG to append a resolution revision into; both original heads staying standing is therefore true by construction, not by careful non-deletion"
  - "SaveOutbox is a second, sibling durable-outbox class in Outbox.swift (own table, own SaveIntentKind vocabulary) rather than widening CurationIntentKind or generalizing Outbox/OutboxWorker -- CurationIntent's wire shape (httpMethod/path/wireBody keyed on a dozen curation cases) has no natural home for a two-case save-resolution intent, and widening it would blur two genuinely distinct bounded contexts"
  - "Device/origin names are caller-supplied on both SaveAttentionCandidate and ConflictSide (no device-name resolution built here) -- same decoupling precedent SaveHistorySession.deviceName already established in 04-09; wiring real device names is part of the same live-navigation wiring this plan defers"
  - "Added a UI-testing-only ConflictComparisonHarnessRootView (env-var-gated, PLAYSTEAD_UI_TEST_CONFLICT_COMPARISON=1) rather than skipping the required XCUITest file -- a UI test target cannot @testable import Playstead, so without a production-side presentation seam no keyboard-interaction proof against a real window is possible at all"

patterns-established:
  - "A save-domain durable outbox reuses Outbox.enqueue's one-transaction discipline via its own sibling class and table rather than widening the original intent enum -- the shape for any future bounded context needing crash-safe local-write-plus-durable-row semantics without polluting CurationIntentKind."

requirements-completed: [SAVE-02, SAVE-04]

coverage:
  - id: D1
    description: "A Mac saves attention source unions divergence (unacknowledged, exact-head-set-scoped) and blocked-capture items into the card's existing rank-1 needsAttention rung, with zero new case/glyph/colour/copy and no snapshot rebaseline"
    requirement: "SAVE-04"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/SaveConflictResolverTests.swift#SaveAttentionSourceTests (15 tests, pass)"
        status: pass
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SnapshotTests/LibraryContractSnapshotTests.swift (unaffected; zero reference-image diffs confirmed via git status)"
        status: pass
    human_judgment: false
  - id: D2
    description: "The comparison sheet renders exactly D-50's four facts per side, no file size/byte-diff/similarity/ordinal/parent, no highlight/pre-selection/colour/confirmation dialog/Undo, Keep Both as a peer action, N-way and not-downloaded variants, all keyboard-native"
    requirement: "SAVE-02"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SnapshotTests/ConflictComparisonContractSnapshotTests.swift (10 tests, pass)"
        status: pass
    human_judgment: false
  - id: D3
    description: "The comparison sheet's real keyboard operability, no-confirmation-dialog, no-Undo, and no-pre-selection behavior against a genuine hosted AppKit/SwiftUI window"
    requirement: "SAVE-02"
    verification:
      - kind: automated_ui
        ref: "playstead-mac/PlaysteadUITests/ConflictResolutionInteractionTests.swift (6 tests, written and build-verified; execution requires the hosted macOS runner per the project's local login-Keychain launch guard)"
        status: unknown
    human_judgment: true
    rationale: "Local UI-layer execution is disabled in this sandbox by the project's own login-Keychain launch guard (scripts/ci/run-mac-verification.sh); these tests build and are registered in TestPlans/UI.xctestplan but their pass/fail has not been observed outside the hosted runner (WINDOWS #34, mirrors #9/#10 precedent)."
  - id: D4
    description: "Choosing a side writes a local fork disposition and enqueues exactly one SaveOutbox entry in one transaction; the whole flow completes with the server unreachable and the entry drains later once reachable"
    requirement: "SAVE-04"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/SaveConflictResolverTests.swift#SaveConflictResolverTests (13 tests, pass, including a real transport-failure-then-recovery round trip via StubURLProtocol)"
        status: pass
    human_judgment: false
  - id: D5
    description: "Resolution never deletes a revision or moves a head pointer; both original heads remain present after every resolution; resolving the same fork twice is idempotent (no second entry); switching to the other side later is a legitimate new resolution"
    requirement: "SAVE-04"
    verification:
      - kind: unit
        ref: "playstead-mac/PlaysteadTests/SavesTests/SaveConflictResolverTests.swift#SaveConflictResolverTests (within the same 13 tests, pass)"
        status: pass
    human_judgment: false
  - id: D6
    description: "The full pre-existing Mac Unit and Rendering suites remain green after adding the two new attention/comparison-sheet surfaces"
    requirement: "SAVE-02"
    verification:
      - kind: integration
        ref: "Unit test plan: 437 tests / 0 failures (was 399); Rendering test plan run against ConflictComparisonContractSnapshotTests: 10/10 pass"
        status: pass
    human_judgment: false

duration: 45min
completed: 2026-09-04
status: complete
---

# Phase 4 Plan 11: Two Versions of Your Progress on the Mac Summary

**A Mac-side saves attention source, a four-facts-per-side comparison sheet, and an append-only local resolver that all agree with the server's divergence model and work entirely offline — with live-navigation wiring into the app's real attention/game-detail surfaces deliberately left as this plan's honest boundary.**

## Performance

- **Duration:** ~45 min
- **Started:** 2026-09-04T19:55:00Z
- **Completed:** 2026-09-04T20:40:00Z
- **Tasks:** 3
- **Files modified:** 15 (7 created, 8 modified)

## Accomplishments

- `SaveAttentionSource` (D-38, D-66): a pure function unioning divergence (a line whose current head set is genuinely undisposed) and blocked-capture items, using the locked vocabulary verbatim including N-variant title/body for 3+ heads and the grouped "Two versions of your progress in {N} games" header once two or more games have their own divergence item. Suppression is exact-sorted-head-id-set matching against a new `save_fork_dispositions` table, mirroring the server's `fork_acknowledged?/3` rule bit-for-bit, so client and server never disagree about which fork is "done." `SaveStore.fetchHeads` (new, plural counterpart to `fetchHead`) is what lets a line report more than one current head.
- `ConflictComparisonSheet` (D-50 through D-55): renders exactly four facts per side (origin, last saved, play time since split, saves since split), with the digest behind "Details" only. No side is ever highlighted, pre-selected, or colour-distinguished, no confirmation dialog precedes choosing, and no Undo control exists anywhere — the non-chosen side keeps a live "Continue from this one" button. "Keep both" is a peer of the choice buttons. Every action is a native SwiftUI `Button` with `playsteadFocusable` (stable identity + visible focus ring), keyboard-native by construction. A UI-testing-only harness (`ConflictComparisonHarnessRootView`, `PLAYSTEAD_UI_TEST_CONFLICT_COMPARISON=1`) presents the sheet directly as the app root so a real XCUITest can drive genuine AppKit/SwiftUI keyboard focus against it — necessary because `PlaysteadUITests` cannot `@testable import Playstead`.
- `SaveConflictResolver` + `SaveIntent` + `SaveOutbox` (D-48, D-49, D-52, D-53): choosing a side or keeping both writes a local fork disposition and enqueues exactly one outbox entry in a single transaction — the local schema has no multi-parent DAG to append a resolution revision into, so both original heads staying standing is true by construction (nothing here ever touches `save_revision`). `SaveOutbox` is a sibling durable outbox inside `Outbox.swift`, reusing `Outbox.enqueue`'s exact one-transaction crash-safety discipline against its own table and `SaveIntentKind` vocabulary, targeting the server's existing `/resolve`/`/acknowledge` routes (plan 04-05) with a per-entry `Idempotency-Key`. Resolving the same fork with the same choice twice is a resolver-level no-op; choosing the other side later ("switching back") is a legitimate new resolution.
- Full local verification: Mac Unit suite 437 tests / 0 failures (was 399: +15 attention-source, +10 comparison-sheet snapshot/semantic, +13 resolver/outbox/intent); `LibraryContractSnapshotTests` unaffected (zero reference-image diffs); Rendering test plan run against `ConflictComparisonContractSnapshotTests` 10/10 pass.

## Task Commits

1. **Task 1: A Mac saves attention source feeding the existing rank-1 rung** - `5ef923c` (test, tdd)
2. **Task 2: The comparison sheet — four facts, no ranking, full keyboard parity** - `91cdb43` (feat, tdd)
3. **Task 3: Append-only resolution that works with no server** - `145e91b` (feat, tdd)

## Files Created/Modified

- `playstead-mac/Playstead/Saves/SaveAttentionSource.swift` - Pure divergence/blocked-capture attention-item source
- `playstead-mac/Playstead/Saves/ConflictComparisonSheet.swift` - The comparison sheet + UI-testing harness root view
- `playstead-mac/Playstead/Saves/SaveConflictResolver.swift` - Local mutation + outbox enqueue resolver
- `playstead-mac/Playstead/Saves/SaveIntent.swift` - Choose-side/acknowledge-fork intent vocabulary
- `playstead-mac/Playstead/Library/StatusSlotView.swift` - Doc comment clarifying the union feed's new caller contract
- `playstead-mac/Playstead/Persistence/Migrations.swift` - `save_fork_dispositions` + `save_outbox_entries` tables
- `playstead-mac/Playstead/Persistence/SaveStore.swift` - `fetchHeads`, fork-disposition CRUD
- `playstead-mac/Playstead/Sync/Outbox.swift` - `SaveOutbox` sibling durable outbox
- `playstead-mac/Playstead/App/PlaysteadApp.swift` - Routes to the UI-testing comparison-sheet harness
- `playstead-mac/PlaysteadTests/SavesTests/SaveConflictResolverTests.swift` - 28 tests across both test classes
- `playstead-mac/PlaysteadTests/SnapshotTests/ConflictComparisonContractSnapshotTests.swift` - 10 tests
- `playstead-mac/PlaysteadTests/SnapshotTests/PlaysteadSnapshot.swift` - Registers the new snapshot suite
- `playstead-mac/PlaysteadUITests/ConflictResolutionInteractionTests.swift` - 6 keyboard-interaction tests
- `playstead-mac/TestPlans/Rendering.xctestplan` / `UI.xctestplan` - Register the two new suites

## Decisions Made

See `key-decisions` in frontmatter — most notably: exact sorted-head-id-set matching for fork-disposition suppression (mirroring the server's `fork_acknowledged?/3`), the resolver never touching `save_revision` (both heads stand by construction, not by care), `SaveOutbox` as a sibling durable outbox rather than widening `CurationIntentKind`, caller-supplied origin/device names throughout (matching 04-09's precedent), and the UI-testing-only harness seam required because `PlaysteadUITests` cannot `@testable import Playstead`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `SaveStore.swift` needed a plural `fetchHeads` and fork-disposition CRUD, neither in the plan's declared file list**
- **Found during:** Task 1
- **Issue:** The plan's task 1 file list did not name `SaveStore.swift`, but detecting divergence at all requires reading every current head of a line (not just one), and suppressing a disposed fork requires somewhere durable to record the disposition.
- **Fix:** Added `fetchHeads(saveLineID:)` (plural counterpart to the shipped `fetchHead`) and a small fork-disposition CRUD (`upsertForkDisposition`/`fetchForkDisposition`) backed by a new `save_fork_dispositions` table.
- **Files modified:** `playstead-mac/Playstead/Persistence/SaveStore.swift`, `playstead-mac/Playstead/Persistence/Migrations.swift`
- **Verification:** `SaveAttentionSourceTests` (15 tests) and `SaveConflictResolverTests` (13 tests) both pass
- **Committed in:** `5ef923c` (Task 1), `145e91b` (Task 3, for the disposition table's write side)

**2. [Rule 3 - Blocking] Outbox.swift needed a second durable table for save intents, since `Outbox`/`OutboxWorker` are hard-typed to `CurationIntent`**
- **Found during:** Task 3
- **Issue:** The shipped `Outbox` class's `enqueue`/`listPending`/`markDone` are all typed against `CurationIntent`/`CurationIntentKind`; a two-case save-resolution intent has no natural home there without either widening `CurationIntentKind` (blurring two bounded contexts) or duplicating the transactional discipline elsewhere.
- **Fix:** Added `SaveOutbox`, a sibling class in the same file, reusing `Outbox.enqueue`'s exact one-transaction discipline against its own `save_outbox_entries` table and `SaveIntentKind` vocabulary.
- **Files modified:** `playstead-mac/Playstead/Sync/Outbox.swift`, `playstead-mac/Playstead/Persistence/Migrations.swift`
- **Verification:** `SaveConflictResolverTests` (13 tests, including a transport-failure-then-recovery round trip via `StubURLProtocol`) pass
- **Committed in:** `145e91b`

**3. [Rule 3 - Blocking] A UI test target cannot `@testable import Playstead`, so the required `ConflictResolutionInteractionTests.swift` had nothing to drive without a production-side seam**
- **Found during:** Task 2
- **Issue:** The plan requires a genuine keyboard-interaction XCUITest, but no live navigation path presents `ConflictComparisonSheet` yet (that wiring is this plan's own deferred scope, see Known Stubs), and `PlaysteadUITests` has no way to reference the Swift type at all.
- **Fix:** Added a small, explicitly UI-testing-only, env-var-gated (`PLAYSTEAD_UI_TEST_CONFLICT_COMPARISON=1`) presentation seam (`ConflictComparisonHarnessRootView`) inside `ConflictComparisonSheet.swift`, plus one routing line in `PlaysteadApp.swift` — following `UITestBootstrap`'s already-shipped save-end-to-end hook precedent verbatim (a UI test target cannot `@testable import Playstead`, so a small test-only production seam is the accessible surface).
- **Files modified:** `playstead-mac/Playstead/Saves/ConflictComparisonSheet.swift`, `playstead-mac/Playstead/App/PlaysteadApp.swift`
- **Verification:** Both targets build cleanly for testing; local execution of the UI layer itself is disabled by the project's login-Keychain launch guard (see Known Stubs / WINDOWS #34)
- **Committed in:** `91cdb43`

---

**Total deviations:** 3 auto-fixed, all Rule 3 (blocking) additions required to complete the plan's declared scope within the existing schema/outbox/testing machinery. No scope creep — none of the three adds new user-facing behavior beyond what the plan's tasks already required.

## Issues Encountered

None beyond the deviations above.

## Known Stubs

- **No live navigation wires `ConflictComparisonSheet` into the running app yet.** The sheet is built and tested standalone (rendering, semantic, and keyboard-interaction tests). The plan's "reachable from three entry points" truth is met server-side (04-10's `/saves`/`/saves/:id` console) but the Mac's own attention-inbox and game-detail entry points still need a presentation call site (a state variable + `.sheet` modifier somewhere in the library shell). Tracked as WINDOWS #32.
- **No eager 32 KB prefetch triggers at divergence detection.** `CacheObjectsSaveBytesPrefetcher.onPrefetchNeeded` remains the no-op WINDOWS #29 already tracks (from plan 04-04); this plan's comparison sheet and resolver work offline once both sides' bytes are already locally cached by some other path, but nothing here newly triggers that fetch the moment a fork is detected. Tracked as WINDOWS #33.
- **Device/origin names are caller-supplied, not resolved from a device store.** Same precedent `SaveHistorySession.deviceName` already established in 04-09 — no device-name-resolution machinery exists on the Mac client yet.
- **UI-layer XCUITest execution requires the hosted macOS runner.** `ConflictResolutionInteractionTests.swift` builds and is registered in `TestPlans/UI.xctestplan`, but this sandbox's `scripts/ci/run-mac-verification.sh` refuses local UI/LiveServer execution (login-Keychain launch guard) unless a human explicitly sets `PLAYSTEAD_HUMAN_APPROVED_LOCAL_APP_LAUNCH=1`, which automated GSD runs must never set. Tracked as WINDOWS #34, mirroring the #9/#10 precedent from phase 03.5.

## Threat Flags

None beyond what the plan's own `<threat_model>` already covers. T-04-11-01 through T-04-11-04 are mitigated as designed: the local mutation and durable outbox row are one transaction (proven by `testAFailingLocalMutationLeavesNoOutboxEntryBehind`), resolution never deletes or moves a head (proven structurally — the resolver never touches `save_revision`), the same fork/action pair enqueues nothing twice (proven), and no recommendation/highlight/pre-selection/colour distinction exists anywhere in `ConflictComparisonSheet.swift` (proven by source-scan test). T-04-11-05 (eager fetch on a metered connection) is accepted per the plan's own disposition and, per the Known Stubs above, not yet even triggered. T-04-11-06 (divergence interrupting play) is mitigated — the attention source never renders a modal/notification/launch prompt (proven by source-scan). T-04-11-07 (banned words) — the "conflict" internal state name never reaches any locked copy string used here; all strings are read verbatim from `SaveVocabulary`. T-04-11-SC — no package-manager install occurred in this plan.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `SaveAttentionSource`, `ConflictComparisonSheet`, and `SaveConflictResolver`/`SaveIntent`/`SaveOutbox` are complete, unit/snapshot-tested, and structurally agree with the server's append-only divergence model (04-05) and its console counterpart (04-10).
- The three deferred wiring gaps (live navigation, eager prefetch trigger, device-name resolution) are all tracked in WINDOWS.md (#32, #33, #29-already-open) rather than silently dropped, and none block this plan's own must-have truths about offline correctness, idempotency, and non-destructive resolution.
- Ready for 04-12.

---
*Phase: 04-persistent-save-continuity*
*Completed: 2026-09-04*

## Self-Check: PASSED

- `[ -f playstead-mac/Playstead/Saves/SaveAttentionSource.swift ]` → FOUND
- `[ -f playstead-mac/Playstead/Saves/ConflictComparisonSheet.swift ]` → FOUND
- `[ -f playstead-mac/Playstead/Saves/SaveConflictResolver.swift ]` → FOUND
- `[ -f playstead-mac/Playstead/Saves/SaveIntent.swift ]` → FOUND
- `[ -f playstead-mac/PlaysteadTests/SavesTests/SaveConflictResolverTests.swift ]` → FOUND
- `[ -f playstead-mac/PlaysteadTests/SnapshotTests/ConflictComparisonContractSnapshotTests.swift ]` → FOUND
- `[ -f playstead-mac/PlaysteadUITests/ConflictResolutionInteractionTests.swift ]` → FOUND
- `git log --oneline --all | grep -q 5ef923c` → FOUND
- `git log --oneline --all | grep -q 91cdb43` → FOUND
- `git log --oneline --all | grep -q 145e91b` → FOUND
- Mac Unit test plan: 437 tests / 0 failures (baseline 399) → PASS
- Rendering test plan (`ConflictComparisonContractSnapshotTests`): 10/10 pass → PASS
- `LibraryContractSnapshotTests`: zero reference-image diffs (`git status --porcelain` clean for that suite's snapshots) → PASS
- `grep -rniE 'always use this mac|prefer this mac' playstead-mac/Playstead/` → empty (PASS)
- `git diff playstead-mac/Playstead/Design/StatusToken.swift` → empty (PASS)
