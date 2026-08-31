---
phase: 03-mac-offline-play-vertical-slice
plan: 05
subsystem: ui
tags: [liveview, phoenix, curation, favorites, collections, queue, continue, search, filters, accessibility, streams, css]

# Dependency graph
requires:
  - phase: 03-mac-offline-play-vertical-slice
    provides: "03-04: Playstead.Curation context (Favorites, Collections, play queue, Continue, Recent) riding the change-journal/snapshot/idempotency spine"
provides:
  - "PlaysteadWeb.LibraryLive.StatusSlot — the single status vocabulary component implementing the D-13 priority ladder"
  - "PlaysteadWeb.LibraryLive.GameCard — the three-zone card anatomy and the frozen system-id registry (monogram/display name)"
  - "PlaysteadWeb.LibraryLive.Shelves and .Sidebar — the five curation shelves and the D-14 canonical navigation order"
  - "PlaysteadWeb.CollectionsLive — /library/collections and /library/collections/:id management console"
  - "LibraryLive extended with search, system/availability filters, sortable list view, and a 500-item-safe LiveView stream"
  - "--system-accent-* and --status-* CSS token vocabularies (03-UI-SPEC.md), disjoint from each other and from Phase 1's semantic roles"
affects: [03-06-mac-swiftui-shell-and-source-list, 03-07-mac-status-vocabulary-and-game-detail, 03-09-mac-readiness-and-preflight]

actuals:
  tokens: 24678
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "One LiveView stream (`phx-update=\"stream\"`) with per-item content branching on an assign (grid vs. list) instead of two conditionally-visible stream containers sharing one stream name — LiveView only ever diffs insert/delete/reorder for a streamed container, never re-patches an already-inserted item's markup, so a bare `@view` toggle without `stream(..., reset: true)` leaves stale content in place"
    - "Per-shelf/per-section `id_prefix` on a shared card component so the same asset set can render in more than one place on the page (a favorited game also in Continue, or in both a shelf and the full browse list) without colliding DOM ids"
    - "HEEx boolean attribute values (`attr={boolean}`) render present/absent, not `\"true\"`/`\"false\"` strings — `to_string/1` is required wherever the literal string is part of the a11y contract (`aria-pressed`)"

key-files:
  created:
    - playstead-server/lib/playstead_web/live/library_live/status_slot.ex
    - playstead-server/lib/playstead_web/live/library_live/game_card.ex
    - playstead-server/lib/playstead_web/live/library_live/shelves.ex
    - playstead-server/lib/playstead_web/live/library_live/sidebar.ex
    - playstead-server/lib/playstead_web/live/collections_live.ex
    - playstead-server/test/playstead_web/live/collections_live_test.exs
  modified:
    - playstead-server/lib/playstead_web/live/library_live.ex
    - playstead-server/lib/playstead_web/router.ex
    - playstead-server/assets/css/app.css
    - playstead-server/test/playstead_web/live/library_live_test.exs
    - playstead-server/test/playstead_web/browser/palette_test.exs
    - playstead-server/test/playstead_web/browser/coherence_test.exs
    - playstead-server/test/support/browser_screens.ex

key-decisions:
  - "The status ladder's computable facts in this plan are limited to what the server actually knows: play-queue membership. Verified/pinned/downloading/missing-dependency/needs-attention are Mac-client-local read-model facts (D-21) this console has no visibility into yet, so every non-queued card is honestly `server_only` rather than guessing. `StatusSlot` implements all six card-eligible ranks (and is unit-tested against all six) so the Mac client's plan 03-07 has one proven implementation to match, but only two ranks are ever reachable from this console today."
  - "Availability filtering follows the same honesty constraint: the two chips are 'Queued' and 'On server' — the spec's 'ready offline' filter value is not offered here since nothing in this plan can compute it. Documented as a known, deliberate gap for 03-08/03-09 to close, not a bug."
  - "Queue and collection-member reordering use Move-up/Move-down buttons rather than a pointer-drag gesture. Both still name exactly two neighbours per click and issue exactly one context call (D-09) — they are the keyboard-native form of the same one-gesture-one-command contract, and QUAL-01 requires full keyboard operability regardless."
  - "Sidebar navigation query params (`?shelf=continue`, `?system=gba`) are wired as link targets and rendered as valid routes, but `LibraryLive.apply_action/3` does not yet branch on them to scroll-to or filter the target shelf — clicking a shelf-only sidebar link currently just reloads Home. Flagged here rather than silently shipped; low-risk since Home already shows every shelf."

patterns-established:
  - "Status vocabulary: exactly one ladder implementation (`StatusSlot.describe/2` and `.status_slot/1`), never re-derived locally by a caller — `GameCard`'s combined accessible name calls `StatusSlot.describe/2` rather than re-implementing the rank/sentence mapping"
  - "System identity: one frozen registry (`GameCard.system_registry/0`, `.system_order/0`, `.monogram/1`, `.system_display_name/1`), reused by `Sidebar` and the browse filter chips so no second id->name mapping can drift"

requirements-completed: [LIBR-02, LIBR-04, LIBR-05, QUAL-01]

coverage:
  - id: D1
    description: "All five curation shelves (Continue, Favorites, Collections, Queue, Recent) render on Home from Playstead.Curation context functions, with no curation query written inside the LiveView"
    requirement: "LIBR-05"
    verification:
      - kind: integration
        ref: "test/playstead_web/live/library_live_test.exs (Task 1 + Task 2 describe blocks)"
        status: pass
      - kind: unit
        ref: "grep -rn 'Repo\\.' lib/playstead_web/live/library_live.ex — no direct repository call"
        status: pass
    human_judgment: false
  - id: D2
    description: "Favoriting, enqueueing, reordering, and creating a collection from the console produce the same rows and journal entries the equivalent API calls would"
    requirement: "LIBR-05"
    verification:
      - kind: integration
        ref: "test/playstead_web/live/library_live_test.exs \"toggling the favorite control...\" and \"reordering the queue...\""
        status: pass
      - kind: integration
        ref: "test/playstead_web/live/collections_live_test.exs \"creates a collection, adds two members, reorders them, removes one...\""
        status: pass
    human_judgment: false
  - id: D3
    description: "A user can reach any imported game by system, by availability, and by free-text search from the console"
    requirement: "LIBR-05"
    verification:
      - kind: integration
        ref: "test/playstead_web/live/library_live_test.exs (Task 3 search/filter tests)"
        status: pass
    human_judgment: true
    rationale: "Automated tests prove the filter/search mechanics narrow correctly; the availability dimension is deliberately incomplete this plan (see key-decisions) and the overall find-a-game UX has not had human review."
  - id: D4
    description: "A system with zero assets is hidden until show-all-systems is activated, and the control states the hidden count; an empty curation shelf is hidden from Home while its sidebar entry remains with a one-line explainer"
    requirement: "LIBR-04"
    verification:
      - kind: integration
        ref: "test/playstead_web/live/library_live_test.exs \"a system with zero assets appears only after show-all-systems...\" and \"an empty Favorites shelf is absent...\""
        status: pass
    human_judgment: false
  - id: D5
    description: "The single status-slot component implements the full D-13 priority ladder — one indicator per card, a distinct glyph/shape/color per rank, an accessible-name sentence, and a list-view text label"
    requirement: "QUAL-01"
    verification:
      - kind: unit
        ref: "test/playstead_web/live/library_live_test.exs \"StatusSlot renders exactly one indicator...\" and \"every status variant's rendered markup contains a glyph...\""
        status: pass
      - kind: unit
        ref: "test/playstead_web/live/library_live_test.exs \"the CSS defines the system-accent and status color vocabularies with no shared value\""
        status: pass
    human_judgment: false
  - id: D6
    description: "A library of 500 asset sets renders through a LiveView stream with fixed row heights and no loading skeleton"
    requirement: "LIBR-05"
    verification:
      - kind: integration
        ref: "test/playstead_web/live/library_live_test.exs \"a library of 500 asset sets renders through a stream container...\""
        status: pass
    human_judgment: false
  - id: D7
    description: "Keyboard/controller and screen-reader accessibility floor: every toggle exposes an explicit aria-pressed state, every card's accessible name combines title/system/status, no color-only state, and the whole console is reachable by keyboard"
    requirement: "QUAL-01"
    verification:
      - kind: integration
        ref: "test/playstead_web/live/library_live_test.exs \"every card's accessible name contains the title, the system, and the status sentence\", \"the list view renders a visible text label...\", and the chip aria-pressed assertions"
        status: pass
      - kind: e2e
        ref: "test/playstead_web/browser/coherence_test.exs (icon-only-button and no-horizontal-scroll suites, all BrowserScreens screens)"
        status: pass
    human_judgment: true
    rationale: "Automated coverage proves the markup-level contract (aria-pressed, accessible names, focus-visible CSS, no horizontal scroll). Full experiential keyboard/VoiceOver walkthroughs of the console have not been performed by a human."
  - id: D8
    description: "Reduced-motion behavior: the download progress fill is retained while status-change transitions become instant/crossfade under prefers-reduced-motion"
    verification: []
    human_judgment: true
    rationale: "Backstop truth from 03-UI-SPEC.md — the CSS media query is implemented in app.css but this plan has no local downloading/verified/pinned state to drive an actual transition through, so the behavior is unexercised (see key-decisions on the ladder's current scope)."

# Metrics
duration: 95min
completed: 2026-08-30
status: complete
---

# Phase 3 Plan 05: LiveView Curation Console Summary

**The Phoenix LiveView console now browses and curates the same canonical library the API serves — five curation shelves, a shared status-vocabulary component, collections management, search/filters, and a 500-item-safe stream — all through `Playstead.Curation`, with zero duplicated queries.**

## Performance

- **Duration:** ~95 min
- **Tasks:** 3 (tracer + 2 auto)
- **Files created:** 6
- **Files modified:** 7
- **Server test suite:** 869 tests (145 browser features, 13 properties, 869 unit/integration), 0 failures (up from 846 before this plan)

## Accomplishments

- `PlaysteadWeb.LibraryLive.StatusSlot` implements the full D-13 status ladder as one component: exactly one indicator per card, a distinct glyph + badge shape + color per rank, an accessible-name sentence, and a list-view text label — with a single public `describe/2` other components (GameCard) call instead of re-deriving the ladder.
- `PlaysteadWeb.LibraryLive.GameCard` renders the three-zone card anatomy (title, meta line with system monogram, one status slot) from the frozen system-id registry, reused by the sidebar and the filter chips so system naming can't drift between surfaces.
- `PlaysteadWeb.LibraryLive.Sidebar` renders the canonical D-14 navigation order (Home, Continue, Favorites, Collections, Queue, Recent, non-empty systems in registry order, Unidentified last), with empty shelves keeping their sidebar entry and a one-line explainer instead of disappearing.
- All five curation shelves (Continue, Favorites, Collections, Queue, Recent) load on Home through their own `Playstead.Curation` function; Favoriting, enqueueing/dequeuing, queue reordering, and Continue dismissal all round-trip through the same context the API uses.
- `PlaysteadWeb.CollectionsLive` (new): `/library/collections` and `/library/collections/:id` — create, rename, delete, add/remove/reorder members, all through `Playstead.Curation`.
- Search (title + filename), system/availability filter chips, and a sortable list view (title/system/date-added) narrow the full library; a single LiveView stream renders it with fixed-height rows and no skeleton, verified against a 500-asset-set library.
- `app.css` gains the `--system-accent-*` and `--status-*` token vocabularies from 03-UI-SPEC.md, deliberately disjoint from each other and from Phase 1's four semantic roles.

## Task Commits

Each task was committed atomically:

1. **Task 1: One curation noun end-to-end — favorite toggle, shelf, and the single status-slot component** — `01a0cb1` (feat)
2. **Task 2: The remaining four shelves, the sidebar, and collections management** — `b66c2bf` (feat)
3. **Task 3: Search, filters, show-all-systems, large-library rendering, and the accessibility floor** — `baa669e` (feat)

_Note: this plan used a tracer task (Task 1) followed by two auto tasks, not TDD RED/GREEN/REFACTOR; each task's commit includes both the implementation and its tests together._

## Files Created/Modified

- `playstead-server/lib/playstead_web/live/library_live/status_slot.ex` — the single status vocabulary component
- `playstead-server/lib/playstead_web/live/library_live/game_card.ex` — the three-zone card and the system-id registry
- `playstead-server/lib/playstead_web/live/library_live/shelves.ex` — the `shelf/1` horizontal row + empty-shelf explainer
- `playstead-server/lib/playstead_web/live/library_live/sidebar.ex` — the canonical navigation order
- `playstead-server/lib/playstead_web/live/collections_live.ex` — collections management console
- `playstead-server/lib/playstead_web/live/library_live.ex` — Home shelves, search/filters/sort/view, the browse stream, all curation event handlers
- `playstead-server/lib/playstead_web/router.ex` — `/library/collections` and `/library/collections/:id` routes
- `playstead-server/assets/css/app.css` — the two new color vocabularies, card/shelf/status component styles, reduced-motion rule
- `playstead-server/test/playstead_web/live/library_live_test.exs` — Task 1/2/3 test coverage
- `playstead-server/test/playstead_web/live/collections_live_test.exs` — collections management coverage
- `playstead-server/test/playstead_web/browser/palette_test.exs`, `coherence_test.exs`, `test/support/browser_screens.ex` — extended for the two new color vocabularies, the new collections screens, and the new action-verb aria-label patterns (see Deviations)

## Decisions Made

See `key-decisions` in frontmatter: the status ladder's honestly-limited scope in this plan (queue-only), the matching availability-filter scope, keyboard-native Move-up/down reordering instead of drag, and the not-yet-wired sidebar shelf/system query params.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `Enum.at/2` with a negative index silently wrapped to the list's last element instead of meaning "no neighbour"**
- **Found during:** Task 2 (collections management browser test — a 2-item collection's "move up" hung the test suite)
- **Issue:** Both the queue and collection-member `move_neighbours/3` helpers computed `Enum.at(ids, i - 2)`; for `i = 1` (moving the second of two items up) this is `Enum.at(ids, -1)`, which `Enum.at/2` resolves as "from the end" — i.e. the *last* element, which is the item being moved itself. That handed `Curation.move_queue_item/3`/`move_collection_member/4` a neighbour identical to the moved row, and `Position.between/2`'s midpoint search looped indefinitely trying to bisect a position against itself.
- **Fix:** Added a `safe_at/2` helper that returns `nil` for any negative index instead of delegating to `Enum.at/2`.
- **Files modified:** `lib/playstead_web/live/library_live.ex`, `lib/playstead_web/live/collections_live.ex`
- **Verification:** The reorder tests in both `library_live_test.exs` and `collections_live_test.exs` pass without hanging.
- **Committed in:** `b66c2bf` (Task 2 commit)

**2. [Rule 1 - Bug] The same asset set rendering in two places at once produced duplicate DOM ids**
- **Found during:** Task 3 (full test-suite run — a favorited, unidentified asset rendered once in the Favorites shelf and once in the browse list, both under the default `game-card-{id}` prefix)
- **Issue:** `GameCard` hardcoded its element ids to `game-card-{asset_set.id}`. Any asset appearing in more than one section simultaneously (a favorited game also in Continue, or in a shelf and the full browse list) produced duplicate ids, which LiveView's test client treats as a hard error (undefined DOM-patch behavior).
- **Fix:** Added an `id_prefix` attr to `GameCard`, defaulting to `"game-card"` for backward compatibility with Task 1's assertions; `Shelves.shelf/1` scopes it to `"{shelf_id}-card"` and the browse section scopes it to `"browse-card"`, so every render site is unique.
- **Files modified:** `lib/playstead_web/live/library_live/game_card.ex`, `lib/playstead_web/live/library_live/shelves.ex`, `lib/playstead_web/live/library_live.ex`
- **Verification:** Full LiveView test suite passes with no duplicate-id runtime error; two of Task 1's own assertions were updated to the new `favorites-shelf-card-{id}` prefix to match.
- **Committed in:** `baa669e` (Task 3 commit) — the id-scoping fix and the two updated Task 1 assertions ship together since they're the same root cause.

**3. [Rule 1 - Bug] A LiveView stream toggled between two conditionally-visible containers left one permanently empty**
- **Found during:** Task 3 (list-view text-label test — after clicking "List view", the stream container existed but was empty)
- **Issue:** The initial implementation rendered the browse section as two separate `phx-update="stream"` divs, one per `@view` value, both iterating `@streams.library_assets`. LiveView delivers stream item inserts exactly once per item; once the grid container consumed them on mount, toggling `@view` to reveal the list container for the first time received no inserts, because from LiveView's perspective those items were already delivered.
- **Fix:** Refactored to one `phx-update="stream"` container whose single `:for` renders per-item content by branching on `@view` inside the loop, and made `handle_event("toggle-view", ...)` force a full re-stream (`reset: true`) so every item's markup is genuinely re-inserted under the new branch — a bare assign is not enough, since LiveView does not re-diff an already-inserted stream item's content.
- **Files modified:** `lib/playstead_web/live/library_live.ex`
- **Verification:** "the list view renders a visible text label for each status in addition to the glyph" passes; the 500-item stream test still passes.
- **Committed in:** `baa669e` (Task 3 commit)

**4. [Rule 1 - Bug] `aria-pressed={boolean}` silently omitted the attribute in the `false` state**
- **Found during:** Task 3 (filter-chip aria-pressed assertion)
- **Issue:** HEEx renders a bare boolean attribute value (`attr={true}` / `attr={false}`) as present/absent, not as the literal string `"true"`/`"false"`. Every `aria-pressed` in this plan (favorite/queue toggle, filter chips, show-all-systems) was passed a raw boolean, so the unpressed state rendered with no `aria-pressed` attribute at all — a screen reader has no toggle state to announce.
- **Fix:** Wrapped every `aria-pressed` value in `to_string/1`.
- **Files modified:** `lib/playstead_web/live/library_live.ex`, `lib/playstead_web/live/library_live/sidebar.ex`
- **Verification:** `has_element?(lv, ~s(button[aria-pressed="false"]#filter-chip-system-gba))` and the corresponding `"true"` assertion after toggling both pass.
- **Committed in:** `baa669e` (Task 3 commit)

**5. [Rule 1 - Bug] show-all-systems toggled its own label but never actually expanded the sidebar's system list**
- **Found during:** Task 3 (show-all-systems test)
- **Issue:** `Sidebar` always rendered `@systems` (present-only) regardless of `@show_all_systems`; the button's label flipped but hidden systems never appeared.
- **Fix:** Added `visible_systems/1`, which unions `systems`/`hidden_systems` back into `GameCard.system_order/0`'s frozen order when `show_all_systems` is true, and renders that instead of the raw `@systems` list.
- **Files modified:** `lib/playstead_web/live/library_live/sidebar.ex`
- **Verification:** "a system with zero assets appears only after show-all-systems is activated..." passes.
- **Committed in:** `baa669e` (Task 3 commit)

**6. [Rule 2 - Missing Critical] The sidebar's accent-colored active-item indicator violated 01-UI-SPEC's accent-reservation rule**
- **Found during:** Task 3 (full-suite browser run — `PaletteTest` flagged `#sidebar-home`'s accent text color as misuse)
- **Issue:** The initial `Sidebar.entry/1` marked the active nav item with `text-[#38BDF8]` (the accent color). 01-UI-SPEC.md (carried forward unchanged by 03-UI-SPEC.md) reserves accent for CTAs, the display code, and the focus ring only — an always-on accent-colored "Home" label is a genuine design-contract violation, not a false positive in the test.
- **Fix:** Switched the active-item indicator to a neutral background fill (`bg-[#334155]`, already in Phase 1's palette) instead of a text-color change.
- **Files modified:** `lib/playstead_web/live/library_live/sidebar.ex`
- **Verification:** `PaletteTest`'s "accent, destructive, success and warning are used only where reserved" passes on `:library` and every other screen.
- **Committed in:** `baa669e` (Task 3 commit)

**7. [Rule 2 - Missing Critical] The console layout had no responsive breakpoint and overflowed horizontally at phone widths**
- **Found during:** Task 3 (full-suite browser run — `CoherenceTest`'s no-horizontal-scroll check failed at the 390×844 phone viewport on `:library`)
- **Issue:** The sidebar+content layout was a single non-wrapping flex row with no width constraint on the sidebar, which the existing cross-phase contract test enforces on every registered screen.
- **Fix:** Stacked the layout (`flex-col`, `lg:flex-row`) and gave the sidebar a `lg:w-56 lg:shrink-0` constraint.
- **Files modified:** `lib/playstead_web/live/library_live.ex`, `lib/playstead_web/live/library_live/sidebar.ex`
- **Verification:** `CoherenceTest`'s "no horizontal scroll on desktop or phone widths" passes on `:library`, `:library_collections`, and `:library_collection_detail`.
- **Committed in:** `baa669e` (Task 3 commit)

**8. [Rule 2 - Missing Critical] The new `/library/collections` screens and Phase 3 color vocabulary/aria-label patterns were invisible to the cross-phase browser contract suites**
- **Found during:** Task 3 (full-suite browser run)
- **Issue:** `PlaysteadWeb.BrowserScreens` (the registry `CoherenceTest` cross-checks against the router), `PaletteTest`'s nine-hex allowlist, and `CoherenceTest`'s action-verb aria-label allowlist all predate this plan and had no knowledge of the new collections routes, the two new Phase 3 color vocabularies (`--system-accent-*`/`--status-*`), or the new "Add X to Favorites"/"Move X up"/"Switch to list view" style accessible names.
- **Fix:** Registered `:library_collections`/`:library_collection_detail` in `BrowserScreens` with populated fixtures; added the 16 Phase 3 hex values to `PaletteTest`'s palette (additive, since 03-UI-SPEC.md declares them a second and third vocabulary alongside — never replacing — Phase 1's); added `create-collection-submit` to the accent allowlist (a genuine primary CTA) and `delete-collection-` to the destructive prefix allowlist (a genuine confirmation-gated destructive action); extended the aria-label regex for the new action-verb-phrase patterns this plan introduces.
- **Files modified:** `test/support/browser_screens.ex`, `test/playstead_web/browser/palette_test.exs`, `test/playstead_web/browser/coherence_test.exs`
- **Verification:** Full `mix test` (869 tests, 145 browser features) passes with 0 failures.
- **Committed in:** `baa669e` (Task 3 commit)

---

**Total deviations:** 8 auto-fixed (5 bugs, 3 missing-critical). **Impact:** All fixes were necessary for correctness (reordering not hanging, no duplicate DOM ids, the list view actually rendering, screen readers getting a real toggle state, show-all-systems actually working) or for this plan to conform to the accessibility/color contracts the phase's own UI-SPEC and pre-existing cross-phase test suites enforce. No scope creep — every fix stayed within files this plan already owns or the shared browser-contract test infrastructure this plan's new surfaces are required to join.

## Issues Encountered

- **Local toolchain drift mid-session:** the pinned `erlang 28.4.1`/`elixir 1.19.5-otp-28` versions were removed from the shared `asdf` installation partway through this plan (a sibling worktree agent working concurrently in `playstead-mac/` most likely installed a newer toolchain and evicted the old one, since `asdf` installs are shared at the user level, not per-worktree). Reinstalled both versions via `asdf install` and re-ran `mix local.hex`/`mix local.rebar`/`mix deps.get` to restore the environment; no project files were affected. Documented here since it is an environment-level event, not a code change.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- The status vocabulary (`StatusSlot`), the system-id registry (`GameCard`), and the `--system-accent-*`/`--status-*` CSS tokens are the one shared implementation plan 03-07 (the Mac client's status vocabulary and game detail) must match glyph-for-glyph and color-for-color per D-17.
- The console's availability filter and status ladder are honestly incomplete pending the Mac-client-local download/pin/verify read model (03-06/03-08) — this is flagged, not hidden, and does not block those plans from proceeding.
- `LibraryLive.apply_action/3` does not yet branch on the sidebar's `?shelf=`/`?system=` query params (see key-decisions) — a low-risk follow-up, since Home already shows every shelf unfiltered.
- `mix test` (869 tests, including the full Wallaby browser suite) and `mix format --check-formatted` (scoped to this plan's files) both pass. `mix credo --strict`, named in the plan's Task 3 `<verify>` block, could not run — `credo` is not a dependency of this project (not present in `mix.exs`); this is a pre-existing gap in the project's toolchain, not something this plan introduced or could fix within its own file scope.

---
*Phase: 03-mac-offline-play-vertical-slice*
*Completed: 2026-08-30*

## Self-Check: PASSED

- All key-files (created/modified) verified present on disk.
- All 3 task commits (`01a0cb1`, `b66c2bf`, `baa669e`) verified present in `git log`.
