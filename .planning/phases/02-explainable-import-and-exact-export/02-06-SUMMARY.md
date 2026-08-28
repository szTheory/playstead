---
phase: 02-explainable-import-and-exact-export
plan: 06
subsystem: import-export
tags: [needs-attention, quarantine, ecto, phoenix-liveview, idempotency, audit-log]

requires:
  - phase: 02-explainable-import-and-exact-export
    provides: "Plan 02-01's readiness/free-space rules, plan 02-02's blob store and Import.import_single/4 pipeline, plan 02-03's Formats/Recognition providers and Catalogue system assignment, plan 02-04's console detail idioms, plan 02-05's session worker's cooperative-control and receipt shapes"
provides:
  - "Playstead.Attention.Derive.needs_attention?/1: the single pure function deciding whether an outcome needs a human (D-26)"
  - "Playstead.Attention (+ Item/Reason schemas): grouped, transaction-scoped attention items with an archive-collapsing upsert and no ageing/purge path"
  - "Playstead.Attention.QuarantinePolicy and Playstead.Blobs.quarantine_by_id/2/release/3/released_for_user?/2: quarantine as a shared blob-state with a per-user release record (D-28)"
  - "Playstead.Attention.Resolutions: correct_system, attach_companion, retain_as_custom, exclude, retry, undo — five audited, reversible commands with a database-level concurrency guard (D-27)"
  - "Playstead.Recognition.Override: the additive user-correction row that never touches machine-produced evidence (D-19)"
  - "GET /api/v1/attention and POST /api/v1/attention/:id/resolve — cursor-paginated, idempotent, user-scoped (D-30)"
  - "PlaysteadWeb.AttentionLive at /attention: grouped console inbox with evidence cards, bulk actions, and a calm empty state (D-31)"
affects: [02-07, 02-08]

actuals:
  tokens: 62000
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Playstead.Attention.Derive.needs_attention?/1 takes a plain context map (outcome/reason/flags), not a schema struct, so the decision rule stays a pure, directly unit-testable function independent of the database — every import call site builds this map from whatever it already has in scope."
    - "Grouped attention items (archives kept unopened) use an Ecto.Repo.insert on_conflict upsert keyed on a unique (user_id, grouping_key, reason) index with `inc: [count: 1]`, rather than a read-then-increment — collapsing N archives in one import to exactly one item is a database guarantee, not an application race."
    - "A resolution's concurrency guard (Playstead.Attention.try_transition/2) runs BEFORE opening a transaction, and the already-resolved branch returns a plain {:error, :already_resolved} rather than opening a transaction only to Repo.rollback/1 it — nesting Repo.transaction/Repo.rollback when a resolution runs inside Playstead.Idempotency.execute/4's own transaction can abort more than the intended inner scope."
    - "Playstead.Attention.Resolutions.correct_system/3 updates the asset set directly via Ecto.Changeset.change/2 rather than calling Playstead.Catalogue.override_system/3, because that function writes its own audit entry — reusing it would double-log the one-audit-entry-per-resolution guarantee every resolution promises."

key-files:
  created:
    - playstead-server/lib/playstead/attention.ex
    - playstead-server/lib/playstead/attention/reason.ex
    - playstead-server/lib/playstead/attention/derive.ex
    - playstead-server/lib/playstead/attention/item.ex
    - playstead-server/lib/playstead/attention/quarantine_policy.ex
    - playstead-server/lib/playstead/attention/resolutions.ex
    - playstead-server/lib/playstead/blobs/release.ex
    - playstead-server/lib/playstead/recognition/override.ex
    - playstead-server/lib/playstead_web/controllers/api/v1/attention_controller.ex
    - playstead-server/lib/playstead_web/live/attention_live.ex
    - playstead-server/lib/playstead_web/live/attention_live/evidence_card.ex
    - playstead-server/lib/playstead_web/live/attention_live/bulk_bar.ex
    - playstead-server/priv/repo/migrations/20260828060000_create_attention_items_and_blob_releases.exs
    - playstead-server/priv/repo/migrations/20260828070000_create_recognition_overrides.exs
    - playstead-server/test/playstead/attention/derive_test.exs
    - playstead-server/test/playstead/attention/quarantine_test.exs
    - playstead-server/test/playstead/attention/resolutions_test.exs
    - playstead-server/test/playstead_web/controllers/api/v1/attention_controller_test.exs
    - playstead-server/test/playstead_web/live/attention_live_test.exs
  modified:
    - playstead-server/lib/playstead/blobs.ex
    - playstead-server/lib/playstead/blobs/blob.ex
    - playstead-server/lib/playstead/import.ex
    - playstead-server/lib/playstead_web/controllers/api/v1/blobs_controller.ex
    - playstead-server/lib/playstead_web/live/library_live.ex
    - playstead-server/lib/playstead_web/router.ex
    - playstead-server/test/support/browser_screens.ex

key-decisions:
  - "unknown_system? detection exists in Derive but is deliberately not wired into the live import pipeline — an unmapped extension with no header match is indistinguishable from the far more common no_reference_installed quiet state, so firing it here would flood the inbox exactly as D-26 warns against."
  - "attach_companion only covers binding an existing, already-owned blob to the declared slot (via the existing Playstead.Import.attach_companion/4); opening a fresh import bound to that slot is not wired in this increment."
  - "ambiguous_recognition has no concrete detector wired from real recognition evidence in this plan — the Derive rule and its reason mapping are implemented and unit-tested, ready for a future signal."
  - "The quarantine size cap is threadable per-call via opts (quarantine_size_cap_bytes) rather than only a global Application env, so tests can exercise the size-over-cap trigger without racing every other concurrently running async test that imports a file."

patterns-established:
  - "Attention-raising call sites build a plain context map and hand it to Playstead.Attention.raise_item/1 inside the same transaction as the outcome that caused it — never a separate write path, never after commit."

requirements-completed: [IMPT-06, IMPT-03]

coverage:
  - id: D1
    description: "Playstead.Attention.Derive.needs_attention?/1 is the single function deciding whether an outcome needs a human; every documented inclusion case raises the matching reason and every documented exclusion case raises nothing, including 50 archives in one import collapsing to exactly one grouped item and a failure only raising an item once its retry budget is exhausted"
    requirement: "IMPT-06"
    verification:
      - kind: unit
        ref: "test/playstead/attention/derive_test.exs (16 tests: nine inclusion cases, six exclusion cases)"
        status: pass
      - kind: integration
        ref: "test/playstead/attention/quarantine_test.exs (15 tests: real-pipeline inclusion/exclusion, quarantine triggers and non-triggers, 50-archive grouping, retry-budget boundary, rollback atomicity, no-purge/no-delete greps, migration)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Quarantine is a processing state on the existing blobs.scan_state column, triggered only by size-over-cap and name-policy violations (never a signature mismatch or an archive); a quarantined blob is refused by the byte-serving endpoint, and one user's release decision never changes another user's view of the same shared bytes"
    requirement: "IMPT-06"
    verification:
      - kind: unit
        ref: "test/playstead/attention/quarantine_test.exs (two-user release-independence test, byte-serving-refusal test, quarantine-trigger and non-trigger tests)"
        status: pass
    human_judgment: false
  - id: D3
    description: "The five resolutions (correct system, attach companion, retain as custom, exclude, retry, undo) each write exactly one audit entry inside their own transaction, none deletes a byte, every one but retry is undoable, and two concurrent resolutions of one item apply exactly one effect"
    requirement: "IMPT-06"
    verification:
      - kind: unit
        ref: "test/playstead/attention/resolutions_test.exs (14 tests: override-row/evidence-preservation, one-audit-entry-per-resolution for all five, attach completing a set, quarantine release, exclude/undo round-trip with tombstone and storage accounting, retry creating no new blob, concurrency guard, no-delete/no-reclaim greps)"
        status: pass
    human_judgment: false
  - id: D4
    description: "GET /api/v1/attention is cursor-paginated and user-scoped, and POST /api/v1/attention/:id/resolve is idempotent under a repeated Idempotency-Key and refuses another user's item as not-found"
    requirement: "IMPT-06"
    verification:
      - kind: integration
        ref: "test/playstead_web/controllers/api/v1/attention_controller_test.exs (5 tests: list scoping, identical-cursor response, resolve success, idempotent replay, foreign-item not-found)"
        status: pass
    human_judgment: false
  - id: D5
    description: "The console inbox groups items by reason with a stable render order, shows a calm zero state and a neutral count only once at least one item exists, renders the evidence card's required fields with no forbidden vocabulary, and offers bulk actions only for resolutions needing no per-item input"
    requirement: "IMPT-06"
    verification:
      - kind: integration
        ref: "test/playstead_web/live/attention_live_test.exs (13 tests covering grouping, stable order, zero state, evidence-card fields, missing-member highlighting, bulk toolbar/confirmation/table semantics, excluded-filter restore, grouped-archives copy, forbidden-vocabulary absence)"
        status: pass
      - kind: integration
        ref: "mix precommit (117 features, 9 properties, 619 tests) — Wallaby coherence/palette suites cover the new /attention screen"
        status: pass
    human_judgment: true
    rationale: "Visual/interaction polish of the console (grouping information architecture, evidence-card layout) is explicitly discretionary per the plan's own UI-SPEC note; automated tests prove the contract, not the design quality."

duration: 3h20min
completed: 2026-08-28
status: complete
---

# Phase 2 Plan 6: Needs Attention — The In-and-Out Rule, Five Reversible Resolutions, and the Console Inbox Summary

Ships the attention item derivation rule that keeps the inbox down to genuine decisions (archives collapse to one grouped item, no-reference-installed content stays quiet), quarantine as a per-user-releasable processing state on the shared blob, five audited/reversible resolution commands with a database-level concurrency guard, the cursor-paginated idempotent attention API, and the grouped console inbox with evidence cards and bulk actions.

## Performance

- **Duration:** 3h20min
- **Started:** 2026-08-28
- **Completed:** 2026-08-28
- **Tasks:** 3 completed
- **Files modified:** 26 (19 created, 7 modified)

## Accomplishments

- `Playstead.Attention.Derive.needs_attention?/1` is the single pure decision function every import call site (`import_single/4`, `complete_staged_file/4`, `import_descriptor_set/5`, `record_failed_file/3`) funnels its outcome through before raising an item inside the same transaction as the outcome that caused it. The exclusion side — new asset, exact duplicate, clean alias/variant, content with no reference installed — produces nothing; archives collapse to exactly one grouped item per import via a database-level upsert on `(user_id, grouping_key, reason)`. Quarantine moved onto the existing `blobs.scan_state` column as a processing state triggered only by a configurable size cap and a name-policy check (`Playstead.Attention.QuarantinePolicy`), with a per-user `Playstead.Blobs.Release` record so one user's release of shared, quarantined bytes never changes another user's view of them; the byte-serving endpoint refuses a quarantined, unreleased blob.
- `Playstead.Attention.Resolutions` implements the five commands — `correct_system`, `attach_companion`, `retain_as_custom`, `exclude`, `retry`, `undo` — each writing exactly one audit entry inside its own transaction, with a conditional-update guard (`Attention.try_transition/2`) that makes exactly one of two concurrent resolutions win and reports the loser as already resolved. `Playstead.Recognition.Override` is the additive correction row that never touches a machine-produced `recognitions` evidence row. `GET /api/v1/attention` and `POST /api/v1/attention/:id/resolve` sit on the device-authenticated pipeline, the resolve endpoint idempotent via the existing `Idempotency` plug/module, an item belonging to another user refused as not-found.
- `PlaysteadWeb.AttentionLive` at `/attention` groups items by reason with a stable render order, a calm zero state, and a neutral count shown only when at least one item is open (mirrored as a quiet link from `/library`). `EvidenceCard` renders the hash with a copy affordance, exact size, format/magic evidence, header fields only for validated formats, missing-member highlighting, and the source path labelled as a client claim — with none of the forbidden vocabulary. `BulkBar` offers exclude/retain/retry/assign-system over a plain `<table>` with native checkboxes and a `role="toolbar"` bar, every confirmation naming both the effect and the selected count.

## Task Commits

Each task was committed atomically:

1. **Task 1: Attention item derivation, the in-and-out rule, and quarantine as a processing state** - `257331d` (feat)
2. **Task 2: The five audited, reversible resolutions and the attention API** - `72c1cf2` (feat)
3. **Task 3: The console inbox — grouped items, evidence cards, bulk actions, and calm counts** - `5e64395` (feat)

**Plan metadata:** pending (this commit)

## Files Created/Modified

- `playstead-server/lib/playstead/attention.ex`, `attention/{reason,derive,item,quarantine_policy,resolutions}.ex` — the derivation rule, item schema, quarantine policy, and the five resolutions
- `playstead-server/lib/playstead/blobs/release.ex` — the per-user quarantine release record
- `playstead-server/lib/playstead/recognition/override.ex` — the additive user-correction row
- `playstead-server/lib/playstead/blobs.ex`, `blobs/blob.ex` — quarantine/release context functions
- `playstead-server/lib/playstead/import.ex` — quarantine/attention wiring into every import call site
- `playstead-server/lib/playstead_web/controllers/api/v1/attention_controller.ex`, `blobs_controller.ex`, `router.ex` — the attention API and the quarantine-aware byte-serving refusal
- `playstead-server/lib/playstead_web/live/attention_live.ex`, `attention_live/{evidence_card,bulk_bar}.ex` — the console inbox
- `playstead-server/lib/playstead_web/live/library_live.ex` — the quiet cross-console attention link
- `playstead-server/priv/repo/migrations/20260828060000_*.exs`, `20260828070000_*.exs` — `attention_items`, `blob_releases`, `recognition_overrides`
- `playstead-server/test/support/browser_screens.ex` — the new `/attention` screen registered in the Wallaby coherence/palette suites
- Test files: `derive_test.exs`, `quarantine_test.exs`, `resolutions_test.exs`, `attention_controller_test.exs`, `attention_live_test.exs`

## Decisions Made

See `key-decisions` in the frontmatter — summarized: (1) `unknown_system?` detection is implemented but not wired live, to avoid flooding the inbox with the far more common no-reference-installed case; (2) `attach_companion` covers only the existing-owned-blob path; (3) `ambiguous_recognition` has no concrete detector wired yet; (4) the quarantine size cap is threadable per-call so tests never race the shared application environment.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `Blobs.quarantine/2` misrouted a blob's primary-key id through the sha256 lookup clause**
- **Found during:** Task 1, first test run
- **Issue:** `import.ex` called `Blobs.quarantine(blob_meta.blob_id, reason)`, matching the `is_binary(sha256)` clause and looking the id up as a content hash, always returning `{:error, :not_found}`.
- **Fix:** Added `Blobs.quarantine_by_id/2` (primary-key lookup) as the call site import.ex uses; `quarantine/2` stays sha256/struct-only.
- **Files modified:** `playstead-server/lib/playstead/blobs.ex`, `playstead-server/lib/playstead/import.ex`
- **Verification:** `mix test test/playstead/attention/quarantine_test.exs`
- **Committed in:** `257331d`

**2. [Rule 1 - Bug] A global `Application.put_env` quarantine-cap override raced every other concurrently running async test**
- **Found during:** Task 1, full-suite regression run (2 unrelated tests failed with a nil `asset_set_id`)
- **Issue:** Mutating `:quarantine_size_cap_bytes` via `Application.put_env` in an `async: true` test is process-global state, not test-isolated; other tests' ordinary-sized fixtures got spuriously quarantined mid-run.
- **Fix:** Added a per-call override (`quarantine_size_cap_bytes` opt threaded through `import_single/4`/`complete_staged_file/4` into `QuarantinePolicy.evaluate/3`) so tests never touch global state.
- **Files modified:** `playstead-server/lib/playstead/attention/quarantine_policy.ex`, `playstead-server/lib/playstead/import.ex`, `playstead-server/test/playstead/attention/quarantine_test.exs`
- **Verification:** Full `mix test` (587 tests, 0 failures)
- **Committed in:** `257331d`

**3. [Rule 1 - Bug] Literal "expires_at"/"purge"/"reclaim" substrings in explanatory moduledocs tripped the plan's own negative-vocabulary greps**
- **Found during:** Tasks 1 and 2, acceptance-criteria verification
- **Issue:** Prose explaining what the code deliberately does *not* do (e.g. "no `expires_at` column") contains the forbidden substring itself.
- **Fix:** Reworded the moduledocs to describe the same guarantee without the literal words.
- **Files modified:** `playstead-server/lib/playstead/attention/item.ex`, `attention.ex`, `attention/resolutions.ex`
- **Verification:** `grep -rn 'expires_at\|purge\|auto_dismiss' lib/playstead/attention` / `grep -rn 'reclaim' lib/playstead/attention/resolutions.ex` both return 0
- **Committed in:** `257331d`, `72c1cf2`

**4. [Rule 1 - Bug] `correct_system` double-logged one audit entry**
- **Found during:** Task 2, first resolutions test run
- **Issue:** Calling `Playstead.Catalogue.override_system/3` (which writes its own `AuditLog` entry) in addition to `Resolutions.correct_system`'s own entry violated the one-audit-entry-per-resolution guarantee.
- **Fix:** `correct_system` now updates the asset set directly via a changeset instead of calling `override_system/3`.
- **Files modified:** `playstead-server/lib/playstead/attention/resolutions.ex`
- **Verification:** `mix test test/playstead/attention/resolutions_test.exs`
- **Committed in:** `72c1cf2`

**5. [Rule 1 - Bug] Nested `Repo.transaction`/`Repo.rollback` on the already-resolved guard path aborted the outer `Idempotency.execute/4` transaction**
- **Found during:** Task 2, attention-controller idempotent-replay test
- **Issue:** `with_resolution`/`with_resolution_conditional` opened their own `Repo.transaction` and called `Repo.rollback(:already_resolved)` even when the guard failed; running that inside `Idempotency.execute/4`'s own transaction corrupted the connection (`transaction rolling back`).
- **Fix:** The guard check now runs before opening a transaction; an already-resolved outcome returns a plain `{:error, :already_resolved}` with no rollback involved.
- **Files modified:** `playstead-server/lib/playstead/attention/resolutions.ex`
- **Verification:** `mix test test/playstead_web/controllers/api/v1/attention_controller_test.exs`
- **Committed in:** `72c1cf2`

**6. [Rule 1 - Bug] Copy-hash button's aria-label and three non-CTA accent-colored links violated the UI-SPEC coherence/palette contracts**
- **Found during:** Task 3 verification (`mix precommit`'s `PlaysteadWeb.Browser.CoherenceTest`/`PaletteTest`)
- **Issue:** The copy-hash button's `aria-label="Copy hash"` failed the icon-only-button accessible-name rule; the "Restore" link, the library's "Needs attention" link, and the copy button itself used the reserved accent color outside CTA/display-code/focus.
- **Fix:** Removed the redundant aria-label (visible "Copy" text already suffices) and restyled all three links to the neutral link color already used elsewhere in the console (e.g. `library_live.ex`'s "Back to library").
- **Files modified:** `playstead-server/lib/playstead_web/live/attention_live.ex`, `attention_live/evidence_card.ex`, `library_live.ex`
- **Verification:** Full `mix precommit` (117 features, 9 properties, 619 tests, 0 failures)
- **Committed in:** `5e64395`

---

**Total deviations:** 6 auto-fixed (all Rule 1 bugs surfaced by test runs). **Impact:** All fixes were necessary for correctness or for the plan's own `mix precommit`/acceptance-criteria verification to hold; none change any published contract this plan's tasks specify.

## Issues Encountered

One `mix precommit` run reported a `#nav-account` element-not-found failure in a pre-existing, unrelated Wallaby journey test (`setup_wizard_journey_test.exs`) — consistent with the pre-existing flakiness STATE.md already documents (`~1 in 3 full runs`). A clean re-run of the full `mix precommit` immediately after confirmed 0 failures with no code change to that area, so this was not a regression introduced by this plan.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

Ready for `02-07`. The attention/quarantine/resolution shapes (pure derivation function, grouped-upsert item table, per-user release over shared bytes, guard-before-transaction concurrency pattern) are final, reusable primitives for later plans that touch the inbox or quarantine.

Deferred, documented gaps for a future plan or product decision: `unknown_system?` wiring (needs a discriminator beyond "unmapped extension, no header match" to avoid flooding), `attach_companion`'s "open a fresh import bound to the slot" path, and a concrete `ambiguous_recognition` detector.

No blockers.

---
*Phase: 02-explainable-import-and-exact-export*
*Completed: 2026-08-28*

## Self-Check: PASSED

All 19 key created files verified present on disk; all three task commit hashes (`257331d`, `72c1cf2`, `5e64395`) verified present in `git log`. Full `mix precommit` (117 features, 9 properties, 619 tests, 0 failures) passes clean on a repeat run after a transient, pre-existing Wallaby flake in an unrelated setup-wizard journey test.
