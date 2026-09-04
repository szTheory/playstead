---
phase: 04-persistent-save-continuity
plan: 10
subsystem: sync
tags: [elixir, phoenix, ecto, liveview, attention, export, divergence]

requires:
  - phase: 04-persistent-save-continuity
    provides: "04-05's revision DAG, Saves.Branches.heads/2/diverged?/2, Saves.resolve_divergence/4, Saves.acknowledge_divergence/3, and Saves.needs_divergence_decision?/2"
  - phase: 04-persistent-save-continuity
    provides: "04-08's Export.SavesPlan/Sidecar/Layout pipeline and ExportRecord.saves_scope, and the console saves-scope control it deliberately deferred (WINDOWS #31)"
  - phase: 04-persistent-save-continuity
    provides: "04-09's shared/save-vocabulary.json locked copy and Playstead.SaveVocabulary console mirror pattern"
provides:
  - "Playstead.Saves.AttentionItem/AttentionSource: a saves-owned attention table and its own frozen reason vocabulary (divergence, capture_blocked, retention_backstop), unioned into PlaysteadWeb.AttentionLive's inbox at read time — Playstead.Attention.Reason stays byte-identical"
  - "PlaysteadWeb.SavesLive (/saves, /saves/:id) and PlaysteadWeb.SavesLive.ComparisonPanel: the console's inspect/choose/keep-both/export surface, the third of three entry points to the divergence comparison sheet"
  - "One saves-scope control (all/none) on the exports console surface, persisted on ExportRecord.saves_scope via Export.create_export/3, plus the 'Export this version…' deep link narrowed to a diverged line's own game"
affects: [04-11, 04-12, 04-13]

actuals:
  tokens: 16361
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "A saves-owned attention source copying Playstead.Attention.Item's upsert-by-grouping-key shape (on_conflict: [inc: [count: 1]]) into its own table and vocabulary, unioned into a shared inbox view at read time via Map.merge/3 — the general pattern for adding a bounded context's attention needs without widening a frozen, differently-scoped enum"
    - "A resolution revision's own capture_method: \"resolution\" marker is read back at render time to decide which of several standing heads currently reads as 'current' for display — no new schema, no stored pointer, consistent with D-14's computed-not-stored head derivation"
    - "Locked shared-vocabulary copy transcribed as literal Elixir strings directly in the LiveView/component that renders it, rather than routed through a vocabulary module, when that module's own contract (D-67's 'partial verbs') scopes it to only what it already renders"

key-files:
  created:
    - playstead-server/priv/repo/migrations/20260904000004_create_save_attention_items.exs
    - playstead-server/lib/playstead/saves/attention_item.ex
    - playstead-server/lib/playstead/saves/attention_source.ex
    - playstead-server/lib/playstead_web/live/saves_live.ex
    - playstead-server/lib/playstead_web/live/saves_live/comparison_panel.ex
    - playstead-server/test/playstead/saves_attention_source_test.exs
    - playstead-server/test/playstead_web/live/saves_live_test.exs
  modified:
    - playstead-server/lib/playstead/saves.ex
    - playstead-server/lib/playstead_web/live/attention_live.ex
    - playstead-server/lib/playstead_web/router.ex
    - playstead-server/lib/playstead/export.ex
    - playstead-server/lib/playstead_web/live/exports_live.ex
    - playstead-server/test/playstead_web/live/exports_live_test.exs
    - playstead-server/test/support/browser_screens.ex

key-decisions:
  - "Clearing a saves attention item deletes the row outright rather than transitioning a status column — there is no 'open/resolved/excluded' lifecycle here, only 'currently raised' or 'not', which is what makes D-52's 'never re-raised for that fork' fall out for free: nothing re-raises an item on its own, only an explicit caller decision does."
  - "The comparison panel's 'Continue from this one' button uses the same neutral bordered style as every other action, not the accent CTA color — highlighting one side with the accent would visually contradict D-51's 'no side is ever recommended or highlighted', and the browser palette contract test caught this before it shipped."
  - "'Export this version…' narrows scope to the diverged line's own game (asset set), not a single revision — no per-revision export filter exists anywhere in the shipped Export.SavesPlan/Layout pipeline (04-08 built it against synthetic data only), so narrowing to the game is the honest, buildable interpretation of D-62's deep link within this plan's declared files."
  - "\"Play time since the split\" always renders its no-sessions fallback string — Playstead.Curation.PlaySession has no device association at all, so no per-device play-time-since-fork computation is possible with the shipped schema; documented as a known limitation rather than fabricated."
  - "Registered /saves and /saves/:id in the browser-coherence screen registry with a populated (diverged) fixture, required by an existing shipped gate (PlaysteadWeb.Browser.CoherenceTest) that fails closed on any router route with no matching screen."

patterns-established:
  - "A frozen, import-recognition-scoped attention enum stays frozen by giving a new bounded context its own attention table/vocabulary and unioning at the view layer — never widening the original enum, never sharing its table."

requirements-completed: [SAVE-02, SAVE-04, PORT-01]

coverage:
  - id: D1
    description: "Playstead.Attention.Reason's nine-member list is byte-identical before and after this plan, pinned by test and by an empty git diff"
    requirement: "SAVE-04"
    verification:
      - kind: unit
        ref: "playstead-server/test/playstead/saves_attention_source_test.exs (frozen vocabulary test, pass)"
        status: pass
      - kind: other
        ref: "git diff playstead-server/lib/playstead/attention/reason.ex"
        status: pass
    human_judgment: false
  - id: D2
    description: "Divergence, blocked capture, and per-user backstops raise/clear saves-owned attention items with their own reason vocabulary, upserting by grouping key rather than duplicating, unioned into the shared inbox at read time"
    requirement: "SAVE-04"
    verification:
      - kind: unit
        ref: "playstead-server/test/playstead/saves_attention_source_test.exs (10 tests, pass)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Resolving or acknowledging a fork clears its divergence attention item; a backstop crossing raises an item and refuses no commit"
    requirement: "SAVE-04"
    verification:
      - kind: unit
        ref: "playstead-server/test/playstead/saves_attention_source_test.exs (resolve/acknowledge/backstop describe blocks, pass)"
        status: pass
    human_judgment: false
  - id: D4
    description: "The console can inspect, choose, keep both, and export a diverged save line at /saves and /saves/:id — exactly four facts per side, digest behind Details only, no confirmation dialog, no Undo, no recommended/pre-selected side, no bulk always-use-this-Mac control, all asserted absent by test"
    requirement: "SAVE-02"
    verification:
      - kind: unit
        ref: "playstead-server/test/playstead_web/live/saves_live_test.exs (13 tests, pass)"
        status: pass
    human_judgment: true
    rationale: "Automated tests assert the DOM-level absences and the correct context calls; the actual visual read (does the sheet feel calm, does keyboard order feel natural) is a genuine UX judgment call no test proves."
  - id: D5
    description: "The exports console exposes exactly one saves-scope control (all/none), persisted and reproduced on re-enqueue; 'Export this version…' deep-links into the same Export.create_export/3 -> Export.Worker machinery"
    requirement: "PORT-01"
    verification:
      - kind: unit
        ref: "playstead-server/test/playstead_web/live/exports_live_test.exs (saves-scope describe block, pass)"
        status: pass
      - kind: unit
        ref: "playstead-server/test/playstead_web/live/saves_live_test.exs (export-this-version test, pass)"
        status: pass
    human_judgment: false
  - id: D6
    description: "The full pre-existing server suite (995 tests) and the browser-coherence/palette/typography/keyboard-reachability contract suites remain green after adding the two new console screens"
    requirement: "SAVE-02"
    verification:
      - kind: integration
        ref: "mix test (995 tests, 0 failures); coherence/palette/typography/keyboard_reachability browser suites (all green)"
        status: pass
    human_judgment: false

duration: 130min
completed: 2026-09-04
status: complete
---

# Phase 4 Plan 10: Saves-Owned Attention and the Console's Inspect/Choose/Export Surface Summary

**A saves-owned attention table with its own frozen vocabulary reaches the shared inbox without widening `Playstead.Attention.Reason`, and a new `/saves` console LiveView lets an owner inspect, choose, keep both, and export a diverged save line with the same context functions the Mac calls and every rejected divergence affordance asserted absent.**

## Performance

- **Duration:** ~130 min
- **Started:** 2026-09-04T18:10:00Z (approx.)
- **Completed:** 2026-09-04T19:50:00Z (approx.)
- **Tasks:** 3
- **Files modified:** 14 (7 created, 7 modified)

## Accomplishments

- `Playstead.Saves.AttentionItem`/`AttentionSource` (D-66): a new `save_attention_items` table with its own reason vocabulary (`divergence`, `capture_blocked`, `retention_backstop`), upserting by `(user_id, grouping_key, reason)` exactly like `Playstead.Attention.Item`'s shape without sharing its table or vocabulary — `Playstead.Attention.Reason`'s nine-member list is verified byte-identical (empty `git diff`, pinned by test)
- `Playstead.Saves.commit_revision/3` now raises/clears divergence attention and checks per-user retention backstops inside the same transaction as the commit; `resolve_divergence/4` and `acknowledge_divergence/3` clear the fork's item on success
- `PlaysteadWeb.AttentionLive`'s inbox unions saves items in at read time via `Map.merge/3`, rendered through a new `saves_item/1` component (never `EvidenceCard`, which is shaped for import-domain evidence this schema doesn't carry)
- `PlaysteadWeb.SavesLive` (`/saves`, `/saves/:id`) and `PlaysteadWeb.SavesLive.ComparisonPanel`: the console's inspect/choose/keep-both/export surface, calling the exact `Saves.resolve_divergence/4`/`Saves.acknowledge_divergence/3` functions the Mac client calls — renders exactly D-50's four facts per side, with the digest behind a "Details" disclosure and no file size, byte-diff, similarity score, revision ordinal, or parent pointer anywhere
- Every rejected divergence affordance is asserted absent by test: no confirmation dialog, no Undo control, no recommended/pre-selected side, no bulk always-use-this-Mac preference, no global playhead
- One saves-scope control (all/none) added to the exports console surface, closing the gap plan 04-08 deliberately deferred (WINDOWS #31); `Export.create_export/3` now threads `opts[:saves_scope]` into the persisted `ExportRecord`; "Export this version…" deep-links into the same `Export.Worker` machinery, narrowed to the diverged line's own game

## Task Commits

1. **Task 1: A saves-owned attention source that leaves Attention.Reason frozen** - `ab35522` (feat, tdd)
2. **Task 2: The console saves surface — inspect, choose, keep both** - `7d6c885` (feat, tdd)
3. **Task 3: One console export control and the export-this-version deep link** - `b168ada` (feat, tdd)

## Files Created/Modified

- `playstead-server/priv/repo/migrations/20260904000004_create_save_attention_items.exs` - The `save_attention_items` table
- `playstead-server/lib/playstead/saves/attention_item.ex` - The saves-owned attention schema, frozen reason vocabulary
- `playstead-server/lib/playstead/saves/attention_source.ex` - Raise/clear/list functions, upsert-by-grouping-key
- `playstead-server/lib/playstead/saves.ex` - Wires the three raisers/clearers, `report_capture_blocked/2`, `clear_capture_blocked/2`
- `playstead-server/lib/playstead_web/live/attention_live.ex` - Unions saves items at read time; `saves_item/1` component
- `playstead-server/lib/playstead_web/live/saves_live.ex` - The console's saves LiveView
- `playstead-server/lib/playstead_web/live/saves_live/comparison_panel.ex` - The comparison sheet component
- `playstead-server/lib/playstead_web/router.ex` - `/saves`, `/saves/:id` routes
- `playstead-server/lib/playstead/export.ex` - `create_export/3` threads `opts[:saves_scope]`
- `playstead-server/lib/playstead_web/live/exports_live.ex` - The one saves-scope control
- `playstead-server/test/playstead/saves_attention_source_test.exs` - 10 tests
- `playstead-server/test/playstead_web/live/saves_live_test.exs` - 13 tests
- `playstead-server/test/playstead_web/live/exports_live_test.exs` - Saves-scope control tests
- `playstead-server/test/support/browser_screens.ex` - `/saves`, `/saves/:id` screen fixtures (required by the shipped coherence gate)

## Decisions Made

See `key-decisions` in frontmatter. Most notable: the comparison panel's choose button deliberately does not use the accent CTA color (the browser palette contract test caught this as an accent misuse before it shipped, and using it would have visually contradicted D-51's "no side is ever recommended" anyway); "Export this version…" narrows to the diverged line's own game rather than a single revision, since no per-revision export filter exists anywhere in the shipped pipeline; and "play time since the split" always renders its no-sessions fallback since `PlaySession` carries no device association.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `Export.create_export/3` did not thread a `saves_scope` option**
- **Found during:** Task 3
- **Issue:** `ExportRecord.saves_scope` (added in 04-08) was schema-ready and validated, but `Export.create_export/3` never read a `saves_scope` option from its caller — a console control selecting "none" would have had no effect.
- **Fix:** `create_export/3` now reads `opts[:saves_scope]` (default `"all"`) into the persisted attrs.
- **Files modified:** `playstead-server/lib/playstead/export.ex` (not in this plan's declared file list, but required to make the declared exports-console control actually work)
- **Verification:** `test/playstead_web/live/exports_live_test.exs`'s new saves-scope tests pass
- **Committed in:** `b168ada` (Task 3 commit)

**2. [Rule 1 - Bug] The comparison panel's "Continue from this one" button used the accent CTA color**
- **Found during:** Task 2, running the browser palette contract test against the new `/saves/:id` screen
- **Issue:** Styling the choose button with the accent color (`#38BDF8` background) is both an outright palette-contract violation (accent is reserved for primary CTAs/focus/display-code) and a substantive UX bug: it visually singles out one side, directly contradicting D-51's "no side is ever recommended, highlighted, or pre-selected".
- **Fix:** Switched to the same neutral bordered style every other action on the sheet uses.
- **Files modified:** `playstead-server/lib/playstead_web/live/saves_live/comparison_panel.ex`
- **Verification:** `mix test test/playstead_web/browser/palette_test.exs` passes for every screen, including the two new ones
- **Committed in:** `7d6c885` (Task 2 commit)

**3. [Rule 3 - Blocking] `/saves` and `/saves/:id` were missing from the browser-coherence screen registry**
- **Found during:** Task 2, running the full test suite
- **Issue:** `PlaysteadWeb.Browser.CoherenceTest` fails closed whenever a router route has no matching entry in `PlaysteadWeb.BrowserScreens` — an existing shipped gate from Phase 3.5, not something this plan could skip.
- **Fix:** Added `:saves`/`:saves_detail` screens with a populated (diverged-line) fixture, following the existing `:attention`/`:library_detail` precedent exactly.
- **Files modified:** `playstead-server/test/support/browser_screens.ex`
- **Verification:** `coherence_test.exs`, `palette_test.exs`, `typography_test.exs`, and `keyboard_reachability_test.exs` all pass for the two new screens
- **Committed in:** `7d6c885` (Task 2 commit)

**4. [Rule 3 - Blocking] The pre-existing `#export-library` button test broke when the export button moved inside a form**
- **Found during:** Task 3
- **Issue:** Adding the saves-scope `<select>` required wrapping the export button in a `<form phx-submit>` (to submit both fields together); the pre-existing test clicked the button directly via `phx-click`, which no longer exists on it.
- **Fix:** Updated the pre-existing test to submit the form instead.
- **Files modified:** `playstead-server/test/playstead_web/live/exports_live_test.exs`
- **Verification:** `mix test test/playstead_web/live/exports_live_test.exs` passes
- **Committed in:** `b168ada` (Task 3 commit)

---

**Total deviations:** 4 auto-fixed (1 bug caught by an existing visual contract test, 3 blocking issues required to keep pre-existing shipped gates green). **Impact:** All auto-fixes were necessary to complete the plan's declared scope without breaking existing contracts; none widen scope beyond what the plan already required.

## Issues Encountered

None beyond the deviations above.

## Known Stubs

- **"Play time since the split" always renders its no-recorded-play fallback.** `Playstead.Curation.PlaySession` (Phase 3) has no device association at all — only `user_id`, `asset_set_id`, `started_at`, `ended_at` — so no per-device "play time since the fork point" can be computed with the shipped schema. The comparison panel always shows "No recorded play here since these split," which is honest (not fabricated) but never shows the one fact D-50 calls "the reason the conflict sheet is worth building at all." Closing this requires either a device-scoped play-session column or a separate signal, and is left for a future plan.
- **"Export this version…" narrows to the diverged line's own game, not a single revision.** No per-revision filter exists anywhere in the shipped `Export.SavesPlan`/`Layout`/`BagitWriter` pipeline — 04-08 built and tested it against synthetic data only, and real `Playstead.Saves` revision data is still not wired into `Export.to_layout_input/1` at all (WINDOWS #30, still open). The deep link enqueues a `:set`-scope export of the game with `saves_scope: "all"`, which is the honest, buildable interpretation within this plan's declared files; a true per-revision export narrowing is future work tracked by WINDOWS #30.
- **The console never renders per-device download state, so the "not downloaded" case is decided purely by CAS presence.** `compare.not_downloaded`'s locked copy ("isn't downloaded on this Mac") is a Mac-client concept; the console substitutes "blob missing from server CAS" as the closest analogous condition, since the console has no local cache concept at all.

## Threat Flags

None beyond what the plan's own `<threat_model>` already covers. All seven threats (T-04-10-01 through T-04-10-06, plus T-04-10-SC) are mitigated as designed: every saves/attention query is scoped through `current_scope`/explicit `user_id` filters; choosing and keeping-both call the append-only `Saves` context functions with nothing deleted; `Playstead.Attention.Reason` stays frozen and pinned by test; the console never renders a global playhead and uses console-only result strings; the digest sits behind "Details" only; export volume is bounded by the existing Oban worker's concurrency limits; and no package-manager install occurred in this plan.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The saves-owned attention source is ready for plan 04-11 to union into the Mac card's rank-1 rung — one source, two consumers, exactly as this plan's `key_links` specify
- `PlaysteadWeb.SavesLive`/`ComparisonPanel` and the exports console's saves-scope control are complete and tested against real `Saves`/`Export` data (not synthetic) for the first time in this phase
- WINDOWS #31 (no console `saves_scope` control) is closed; WINDOWS #30 (no real revision data wired into `Export.to_layout_input/1`) remains open and is the honest boundary of what "Export this version…" can narrow to today
- Ready for 04-11.

## Self-Check: PASSED

- `[ -f playstead-server/priv/repo/migrations/20260904000004_create_save_attention_items.exs ]` → FOUND
- `[ -f playstead-server/lib/playstead/saves/attention_item.ex ]` → FOUND
- `[ -f playstead-server/lib/playstead/saves/attention_source.ex ]` → FOUND
- `[ -f playstead-server/lib/playstead_web/live/saves_live.ex ]` → FOUND
- `[ -f playstead-server/lib/playstead_web/live/saves_live/comparison_panel.ex ]` → FOUND
- `[ -f playstead-server/test/playstead/saves_attention_source_test.exs ]` → FOUND
- `[ -f playstead-server/test/playstead_web/live/saves_live_test.exs ]` → FOUND
- `git log --oneline --all | grep -q ab35522` → FOUND
- `git log --oneline --all | grep -q 7d6c885` → FOUND
- `git log --oneline --all | grep -q b168ada` → FOUND
- `cd playstead-server && MIX_ENV=test mix test test/playstead/saves_attention_source_test.exs test/playstead_web/live/saves_live_test.exs` → PASS (23 tests, 0 failures)
- `git diff playstead-server/lib/playstead/attention/reason.ex` → empty (PASS)
- `cd playstead-server && MIX_ENV=test mix test` (full suite) → PASS (995 tests, 0 failures)

---
*Phase: 04-persistent-save-continuity*
*Completed: 2026-09-04*
