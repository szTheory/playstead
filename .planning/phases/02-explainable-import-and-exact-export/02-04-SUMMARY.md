---
phase: 02-explainable-import-and-exact-export
plan: 04
subsystem: import-export
tags: [phoenix-liveview, upload-writer, content-addressed-storage, live-view-uploads, console-ui]

requires:
  - phase: 02-explainable-import-and-exact-export
    provides: "Plan 02-02's write path (Playstead.Blobs, Playstead.Blobs.Store/LocalDisk, import_single/4), plan 02-03's format validators, recognition provider, and display-title/system-assignment rules"
provides:
  - "Playstead.Import.HashingWriter: the Phoenix.LiveView.UploadWriter that hashes a browser upload while streaming it to a temp file, read exactly once"
  - "Playstead.Blobs.Store.adopt_temp_file/2 (+ LocalDisk impl, + Blobs delegate): the seam that hands the writer's completed temp file into the CAS commit path without re-streaming its bytes"
  - "Playstead.Import.Preview.for_upload/2: the IMPT-01 pre-copy answer computed from what is knowable before bytes move, with no duplicate verdict and an extension-derived format guess"
  - "Playstead.Import.import_upload/3 and Playstead.Import.list_receipts/2"
  - "PlaysteadWeb.ImportLive at /import: preview, confirm, and the outcome-coded receipt list"
  - "Playstead.Catalogue.list_assets/2 and get_asset_detail/2 (scope-taking, strictly user-scoped)"
  - "PlaysteadWeb.LibraryLive at /library and /library/:id: the asset list with a quiet unidentified badge and the IMPT-02 evidence detail view"
affects: [02-05, 02-06, 02-07, 02-08]

actuals:
  tokens: 18238
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "The browser upload writer manages its own temp file directly (open/write/fsync/close under the blob volume's tmp/ dir) rather than delegating chunk-by-chunk to the Store's WriteRef machinery, so a completed-but-unconfirmed upload leaves an inspectable, byte-exact temp file rather than an already-committed blob row; the console's confirm action then hands that finished file to Blobs.adopt_temp_file/2 for a single rename-based commit into the CAS — the bytes are read from the network exactly once, and read back from disk once more only for the existing D-11 verification pass."
    - "A LiveView `:validator` function (not the writer) enforces the free-space margin at preflight, before any chunk is ever sent — the browser ceiling is enforced twice, once via LiveView's own `max_file_size` and again defensively inside the writer's own `init/1`, so the ceiling check holds even when the writer is driven directly in its own unit tests."
    - "Catalogue.list_assets/2 and get_asset_detail/2 take a %Scope{} (Phase 1's convention) rather than a bare user_id, even though the rest of the Phase 2 import/export context functions take user_id directly — the plan calls these two 'scope-taking' explicitly, and they are the console's own read surface rather than part of the import pipeline's internal call chain."

key-files:
  created:
    - playstead-server/lib/playstead/import/hashing_writer.ex
    - playstead-server/lib/playstead/import/preview.ex
    - playstead-server/lib/playstead_web/live/import_live.ex
    - playstead-server/lib/playstead_web/live/import_live/preview_panel.ex
    - playstead-server/lib/playstead_web/live/import_live/receipt_row.ex
    - playstead-server/lib/playstead_web/live/library_live.ex
    - playstead-server/lib/playstead_web/live/library_live/asset_detail.ex
    - playstead-server/test/playstead/import/hashing_writer_test.exs
    - playstead-server/test/playstead/import/preview_test.exs
    - playstead-server/test/playstead_web/live/import_live_test.exs
    - playstead-server/test/playstead_web/live/library_live_test.exs
  modified:
    - playstead-server/lib/playstead/blobs.ex
    - playstead-server/lib/playstead/blobs/store.ex
    - playstead-server/lib/playstead/blobs/store/local_disk.ex
    - playstead-server/lib/playstead/catalogue.ex
    - playstead-server/lib/playstead/import.ex
    - playstead-server/lib/playstead_web/router.ex
    - playstead-server/lib/playstead_web/components/layouts/root.html.heex
    - playstead-server/config/test.exs
    - playstead-server/test/support/browser_screens.ex
    - playstead-server/test/playstead_web/browser/palette_test.exs
    - playstead-server/test/playstead_web/live/copy_contract_test.exs

key-decisions:
  - "adopt_temp_file/2 is a new Playstead.Blobs.Store behaviour callback (not anticipated in the plan's own files_modified list), implemented in LocalDisk by reusing the existing verify_on_disk/place_and_record helpers commit/2 already has — needed because the writer's completed file must be handed to the same CAS commit path the API upload uses without a second full read/write of the bytes; without it, the only alternative was re-streaming the finished file through Blobs.put_stream/2, which would read+write the bytes a second time and contradict the 'read once' truth this plan requires."
  - "LocalDisk.capacity_bytes/1 made public (was private) so Playstead.Import.Preview can compute the same free-space-margin arithmetic Playstead.Readiness.required_bytes/2 uses, without duplicating the df-based capacity probe in a second module."
  - "config/test.exs caps PLAYSTEAD_MAX_BROWSER_UPLOAD_BYTES to 1 MiB (mirroring the existing PLAYSTEAD_MAX_UPLOAD_BYTES test override) so the browser-ceiling boundary (exactly-at-ceiling accepted, one-byte-over refused) can be exercised with real byte content in LiveViewTest rather than requiring multi-gigabyte fixtures."
  - "The free-space-margin refusal ('a file exceeding the free-space margin is refused before any bytes are written') is proven at the Playstead.Import.Preview unit level rather than through a full LiveView upload, since LiveViewTest's file_input/4 helper requires declared size and actual byte content to match exactly — exercising this end-to-end would require allocating a real multi-terabyte binary in the test."

requirements-completed: [IMPT-01, IMPT-02]

coverage:
  - id: D1
    description: "Browser uploads stream once, hash in flight via a custom UploadWriter, fsync on completion, and leave nothing behind if interrupted"
    requirement: "IMPT-01"
    verification:
      - kind: unit
        ref: "test/playstead/import/hashing_writer_test.exs (10 tests: multi-chunk digest equality, uneven chunk sizes, successful/non-success/error close, unopenable path, browser-ceiling boundary, temp path location)"
        status: pass
    human_judgment: false
  - id: D2
    description: "The pre-copy preview states exact size, free space, storage cost, managed-copy semantics, and untouched-source semantics, and claims nothing it cannot know (no duplicate verdict, format label marked as a guess)"
    requirement: "IMPT-01"
    verification:
      - kind: unit
        ref: "test/playstead/import/preview_test.exs (8 tests)"
        status: pass
      - kind: integration
        ref: "test/playstead_web/live/import_live_test.exs (10 tests: preview contents, exact-ceiling/one-byte-over, receipt-on-confirm, failed-import correlation id, markup-filename escaping, reload persistence)"
        status: pass
      - kind: integration
        ref: "test/playstead_web/live/copy_contract_test.exs (import console describe block: primary-action copy, forbidden-vocabulary negative check)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Receipts and asset evidence are rendered from durable records, keyed off outcome codes, never inventing an outcome the receipt does not carry"
    requirement: "IMPT-02"
    verification:
      - kind: integration
        ref: "test/playstead_web/live/import_live_test.exs#a successful copy renders a receipt row chosen by the receipt's outcome code"
        status: pass
      - kind: integration
        ref: "test/playstead_web/live/library_live_test.exs#a receipt whose asset has since been identified still displays the outcome recorded at import"
        status: pass
    human_judgment: false
  - id: D4
    description: "A user can open any imported asset and read the exact bytes' identity — hash, size, format evidence, members, and provenance — without the console overstating what is known or revealing anything about another user's library"
    requirement: "IMPT-02"
    verification:
      - kind: integration
        ref: "test/playstead_web/live/library_live_test.exs (12 tests: full SHA-256, exact byte size, client-claimed provenance, signature-only header fields, missing-member marking, quiet unidentified badge, single library-level hint, two-user isolation, forbidden-vocabulary negative check)"
        status: pass
    human_judgment: false
  - id: D5
    description: "No wording anywhere in the import/library console implies the source file is moved, cleaned up, or removed, and no forbidden vocabulary describes user content"
    verification:
      - kind: unit
        ref: "grep -rhv '^\\s*#' import_live.ex import_live/ | grep -Eic 'move your file|moves your file|relocate|tidy up|clean up your' -> 0"
        status: pass
      - kind: unit
        ref: "grep -rhv '^\\s*#' library_live.ex library_live/ | grep -Eic 'illegal|corrupt file|disposable|virus' -> 0"
        status: pass
    human_judgment: false

duration: 3h40min
completed: 2026-08-28
status: complete
---

# Phase 2 Plan 4: Streaming Browser Upload, Pre-Copy Preview, and the Import/Library Console Summary

Ships the browser's whole custody promise end to end: a custom `Phoenix.LiveView.UploadWriter` that hashes a file exactly once while streaming it to disk, a pre-copy preview that states only what is knowable before bytes move, an import console whose receipts are rendered strictly from stored outcome codes, and a library console whose asset detail view lets a user read back the exact SHA-256, byte size, format evidence, and client-claimed provenance of anything they've imported — all without ever revealing a trace of another user's holdings.

## Performance

- **Duration:** 3h40min
- **Started:** 2026-08-28
- **Completed:** 2026-08-28
- **Tasks:** 3 completed
- **Files modified:** 22 (11 created, 11 modified)

## Accomplishments

- `Playstead.Import.HashingWriter` implements `Phoenix.LiveView.UploadWriter`'s four callbacks against a temp file under the blob volume's `tmp/` directory: each chunk is written and folded into the same `Playstead.Blobs.MultiHash` accumulator, a successful close fsyncs and reports the finalized digests while leaving the file in place, and any other close removes it — proven by 10 direct unit tests including a real "unopenable path" case via dependency injection (no shared-directory chmod, no OS env mutation) and a browser-ceiling boundary check. A new `Playstead.Blobs.Store.adopt_temp_file/2` callback hands the writer's finished file into the same CAS commit path (`Playstead.Blobs.Store.LocalDisk`'s existing verify-on-disk-and-rename logic) the API upload already uses, so the bytes are read from the network exactly once.
- `Playstead.Import.Preview.for_upload/2` computes the IMPT-01 pre-copy answer — exact size, free space, the space the copy will use, browser-ceiling fit, and an extension-derived (never magic-byte) format guess — with no duplicate-verdict field at all, since the browser cannot hash before confirming. `PlaysteadWeb.ImportLive` at `/import` follows the devices-console idiom exactly: a LiveView `:validator` refuses insufficient free space before the writer ever engages, `max_file_size` enforces the browser ceiling with inbox-folder guidance in the refusal copy, and every event handler reloads its receipt list fresh from `Playstead.Import.list_receipts/2` rather than patching assigns.
- `Playstead.Catalogue.list_assets/2` and `get_asset_detail/2` (both scope-taking) back `PlaysteadWeb.LibraryLive` at `/library` and `/library/:id`: an asset with no reference match gets a quiet, never-error-styled "Not yet identified" badge, a single dismissible reference-pack hint appears once at the library level, and the asset detail view renders the full SHA-256 with a copy affordance, exact byte size, format/magic evidence (header fields shown only for a signature-validated match), the ordered member list with missing members marked, and the source provenance explicitly labelled as a claim made by the submitting client. A later reference-pack identification never rewrites a receipt's recorded outcome — the receipt view shows both "at import" and "now" when they differ.

## Task Commits

Each task was committed atomically:

1. **Task 1: The streaming hashing upload writer for the browser path** - `5d353c6` (feat)
2. **Task 2: The pre-copy preview and the import console surface** - `3c3444d` (feat)
3. **Task 3: The library and asset detail surface where hash, size, and provenance are inspectable** - `a9f0184` (feat)

**Plan metadata:** pending (this commit)

## Files Created/Modified

- `playstead-server/lib/playstead/import/hashing_writer.ex` — the D-01a browser upload writer
- `playstead-server/lib/playstead/blobs.ex`, `blobs/store.ex`, `blobs/store/local_disk.ex` — `adopt_temp_file/2` (new Store callback + LocalDisk impl + Blobs delegate), `LocalDisk.capacity_bytes/1` made public
- `playstead-server/lib/playstead/import/preview.ex` — the IMPT-01 pre-copy preview
- `playstead-server/lib/playstead/import.ex` — `import_upload/3`, `list_receipts/2`
- `playstead-server/lib/playstead_web/live/import_live.ex`, `import_live/preview_panel.ex`, `import_live/receipt_row.ex` — the import console
- `playstead-server/lib/playstead/catalogue.ex` — `list_assets/2`, `get_asset_detail/2`
- `playstead-server/lib/playstead_web/live/library_live.ex`, `library_live/asset_detail.ex` — the library console and evidence card
- `playstead-server/lib/playstead_web/router.ex`, `components/layouts/root.html.heex` — `/import`, `/library`, `/library/:id` routes and nav links
- `playstead-server/config/test.exs` — `PLAYSTEAD_MAX_BROWSER_UPLOAD_BYTES` capped to 1 MiB for cheap ceiling-boundary testing
- `playstead-server/test/support/browser_screens.ex`, `test/playstead_web/browser/palette_test.exs` — new console screens registered in the Wallaby coherence/palette suites, with the accent-color allowlist extended for the new confirm-import CTA
- Test files: `hashing_writer_test.exs`, `preview_test.exs`, `import_live_test.exs`, `library_live_test.exs`; extended `copy_contract_test.exs`

## Decisions Made

See `key-decisions` in the frontmatter — summarized: (1) a new `Store.adopt_temp_file/2` callback lets the writer's finished file join the existing CAS commit path without a second full read/write of the bytes, (2) `LocalDisk.capacity_bytes/1` is now public so the preview can reuse the same free-space arithmetic, (3) the test-env browser upload ceiling is capped to 1 MiB so boundary tests use real bytes instead of multi-gigabyte fixtures, and (4) the free-space-margin refusal is proven at the `Preview` unit level rather than end-to-end, since `LiveViewTest.file_input/4` requires declared size and actual content to match byte-for-byte.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] No commit path existed for an already-written, already-hashed temp file**
- **Found during:** Task 1 design (before any code was written) — the plan's own `key_links` describe the writer's temp file being "handed to the same context commit path the API upload uses," but no such entry point existed on `Playstead.Blobs`/`Playstead.Blobs.Store`; the only existing paths either streamed fresh bytes (`put_stream/2`, which would re-read the writer's finished file, contradicting the "read once" truth) or assumed a live, still-open `WriteRef` (`commit/2`).
- **Fix:** Added `Playstead.Blobs.Store.adopt_temp_file/2` to the `Store` behaviour, implemented in `LocalDisk` by reusing the existing `verify_on_disk/2` and `place_and_record/2` private helpers `commit/2` already relies on, and exposed via `Playstead.Blobs.adopt_temp_file/2`.
- **Files modified:** `playstead-server/lib/playstead/blobs.ex`, `blobs/store.ex`, `blobs/store/local_disk.ex`
- **Verification:** `mix test test/playstead/blobs/ test/playstead/import/` (52 tests, 0 failures); full `mix precommit`.
- **Committed in:** `5d353c6`

**2. [Rule 1 - Bug] Two `<button>` elements and one `<label>` violated the UI-SPEC accent-color contract**
- **Found during:** Task 3 verification (`mix precommit`'s `PlaysteadWeb.Browser.PaletteTest`, run as part of the plan's own `mix precommit` verification requirement)
- **Issue:** The "Choose a file" trigger (`import_live.ex`), the per-member "Copy" SHA-256 button, and the library's "Dismiss" hint button all used the reserved accent blue (`#38BDF8`) outside the palette contract's allowed CTA/display-code/focus positions.
- **Fix:** Restyled the choose-file trigger as a neutral bordered control (matching the console's secondary-action idiom) and the two text buttons to the neutral `#F1F5F9`; added a `confirm-import-` prefix to the palette test's accent-allowed CTA-id regex, since the actual primary "Copy into my library" confirm button is a legitimate new CTA the allowlist did not yet cover.
- **Files modified:** `playstead-server/lib/playstead_web/live/import_live.ex`, `library_live.ex`, `library_live/asset_detail.ex`, `test/playstead_web/browser/palette_test.exs`
- **Verification:** `mix test test/playstead_web/browser/palette_test.exs` (19 features, 0 failures); full `mix precommit` (103 features, 9 properties, 514 tests, 0 failures).
- **Committed in:** `a9f0184`

**3. [Rule 3 - Blocking issue] New console screens were absent from the Wallaby screen registry the phase's own coherence suite requires**
- **Found during:** Task 3 verification (`mix precommit`'s `PlaysteadWeb.Browser.CoherenceTest` failed: "console routes changed — add the new screen to `PlaysteadWeb.BrowserScreens`")
- **Issue:** `/import`, `/library`, and `/library/:id` are new `GET` console routes; the coherence test asserts the router and the browser-screen registry agree, by design, so a new screen literally cannot ship without joining the registry.
- **Fix:** Registered `:import`, `:library`, and `:library_detail` in `PlaysteadWeb.BrowserScreens` with populated-state `open/2` fixtures (an imported asset for the two library screens).
- **Files modified:** `playstead-server/test/support/browser_screens.ex`
- **Verification:** `mix test test/playstead_web/browser/coherence_test.exs` (31 features, 1 test, 0 failures); full `mix precommit`.
- **Committed in:** `a9f0184`

---

**Total deviations:** 3 auto-fixed (1 Rule 2 — missing critical functionality the plan's own design implied but did not name a concrete seam for; 2 Rule 1/3 — bugs and a blocking pre-existing test contract surfaced only once this plan's new screens existed).
**Impact on plan:** No scope creep. All three fixes are necessary for correctness (the writer must not re-read bytes it already streamed) or for the plan's own stated `mix precommit` verification requirement to hold; none change any published contract this plan's tasks specify.

## Issues Encountered

None beyond the deviations above.

## User Setup Required

None — no external service configuration required. The one test-only configuration change (`PLAYSTEAD_MAX_BROWSER_UPLOAD_BYTES` capped to 1 MiB in `config/test.exs`) has no effect on `dev`/`prod`, which keep the 4 GiB default from `config/runtime.exs`.

## Next Phase Readiness

Ready for `02-05`. The browser upload writer, the CAS-adoption seam (`Blobs.adopt_temp_file/2`), the pre-copy preview, and the console's read surfaces (`Import.list_receipts/2`, `Catalogue.list_assets/2`/`get_asset_detail/2`) are final, production forms for the rest of Phase 2 to build on: the staged-collection inbox scan (02-05) reuses the same `Playstead.Import` context functions and outcome-coded receipt rendering; the Needs Attention inbox (02-06) extends the library console's quiet-badge/dismissible-hint idiom to its five audited resolutions.

No blockers.

---
*Phase: 02-explainable-import-and-exact-export*
*Completed: 2026-08-28*

## Self-Check: PASSED

All 11 key created files verified present on disk; all three task commit hashes (`5d353c6`, `3c3444d`, `a9f0184`) verified present in `git log`. Full `mix precommit` (103 features, 9 properties, 514 tests, 0 failures) passes clean.
