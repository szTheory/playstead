---
phase: 02-explainable-import-and-exact-export
plan: 08
subsystem: recognition
tags: [saxy, xml-security, xxe, dat-pack, no-intro, logiqx, liveview]

requires:
  - phase: 02-explainable-import-and-exact-export
    provides: "Playstead.Recognition.Provider behaviour, HeaderEvidence, append-only recognitions/attention_items schemas, Blob legacy digests + BlobFingerprint headerless-offset schema, AuditLog, ChangeJournal (02-01 through 02-07)"
provides:
  - "The one pinned, audited dependency (saxy 1.6.1) guarded by an automated supply-chain test"
  - "A streaming, entity-safe, capped, never-raising Logiqx DAT-pack parser with a hostile fixture corpus"
  - "Full reference-pack provenance (source, retrieval time, upstream version, file hash, licence claim + note, transform version), recorded and displayed, with no bundling and no acquisition path"
  - "Digest-based reference matching (Playstead.Recognition.ReferenceMatch, Recognition.reidentify/2) that upgrades identification confidence to exact, resolves settleable ambiguity, and rewrites no receipt or existing evidence row"
  - "The /reference-packs console: supply a pack, review provenance, see newly-identified counts, remove a pack"
affects: [attention, catalogue, library-console]

actuals:
  tokens: 22017
  tasks: 3
  commits: 3

tech-stack:
  added: ["saxy 1.6.1 (pinned, hex.pm, manually audited per RESEARCH.md)"]
  patterns:
    - "Untrusted-XML defense in depth: a byte-level DOCTYPE/ENTITY pre-scan on already-size-capped bytes, ahead of the SAX parser, rather than relying solely on the library's own safe defaults"
    - "Configurable hard caps via Application env (logiqx_max_bytes/logiqx_max_entries) so a cap-exceeded path is testable without constructing a multi-hundred-thousand-entry fixture"
    - "A later-run re-identification pass (Recognition.reidentify/2) as a distinct entry point from the live import pipeline, dispatching through the same Provider behaviour rather than adding a second pipeline"

key-files:
  created:
    - playstead-server/lib/playstead/recognition/dat_pack.ex
    - playstead-server/lib/playstead/recognition/dat_pack_importer.ex
    - playstead-server/lib/playstead/recognition/logiqx_handler.ex
    - playstead-server/lib/playstead/recognition/reference_entry.ex
    - playstead-server/lib/playstead/recognition/reference_match.ex
    - playstead-server/lib/playstead_web/live/reference_packs_live.ex
    - playstead-server/test/playstead/dependency_pin_test.exs
    - playstead-server/test/playstead/recognition/dat_pack_importer_test.exs
    - playstead-server/test/playstead/recognition/logiqx_security_test.exs
    - playstead-server/test/playstead/recognition/reference_match_test.exs
    - playstead-server/test/playstead_web/live/reference_packs_live_test.exs
    - playstead-server/test/support/fixtures/dat/*.dat
    - playstead-server/priv/repo/migrations/20260828230000_create_dat_packs_and_reference_entries.exs
    - playstead-server/priv/repo/migrations/20260828231500_widen_recognitions_inserted_at_precision.exs
  modified:
    - playstead-server/mix.exs / mix.lock (saxy 1.6.1)
    - playstead-server/lib/playstead/recognition.ex (reidentify/2)
    - playstead-server/lib/playstead/recognition/evidence.ex (utc_datetime_usec)
    - playstead-server/lib/playstead/attention.ex (resolve_for_asset_set/2)
    - playstead-server/lib/playstead_web/live/library_live.ex (install-hint link)
    - playstead-server/lib/playstead_web/router.ex
    - playstead-server/lib/playstead_web/components/layouts/root.html.heex (nav link)
    - playstead-server/test/support/browser_screens.ex, test/playstead_web/browser/palette_test.exs, test/playstead_web/live/copy_contract_test.exs

key-decisions:
  - "Substituted an automated pinned-version-and-checksum test for the package-legitimacy protocol's recommended human checkpoint, per the project owner's zero-manual-verification preference — recorded as a deliberate, visible deviation in the plan's own scope note"
  - "Refuse any DOCTYPE/ENTITY declaration outright via a byte-level pre-scan before Saxy ever parses, rather than relying on Saxy's own DTD-skipping default — a stricter posture than strictly necessary but one that does not depend on trusting a third-party library's exact internal behavior"
  - "Reference matching runs as a separate, later-run Recognition.reidentify/2 pass rather than being wired into the live import pipeline's recognize_and_record/3 — matches D-18's framing of pack installation as an upgrade event distinct from import"
  - "Widened recognitions.inserted_at to utc_datetime_usec (Rule 1 bug fix) after discovering second-precision timestamps make 'the latest evidence row for a blob' ambiguous when a reference match runs within the same second as the evidence it supersedes"

requirements-completed: [IMPT-03, IMPT-06]

coverage:
  - id: D1
    description: "The saxy dependency is pinned to its audited version and guarded by an automated version+checksum test"
    requirement: IMPT-06
    verification:
      - kind: unit
        ref: "test/playstead/dependency_pin_test.exs"
        status: pass
    human_judgment: false
  - id: D2
    description: "A streaming, entity-safe, capped, never-raising parser refuses every hostile fixture (DOCTYPE, external entity, recursive entity, oversized, entry-flooded, truncated, mutated) without exception, external read, or unbounded memory growth"
    requirement: IMPT-06
    verification:
      - kind: unit
        ref: "test/playstead/recognition/logiqx_security_test.exs"
        status: pass
    human_judgment: false
  - id: D3
    description: "Full pack provenance (source, retrieved_at, upstream_version, file hash, licence claim + note, transform version) is recorded on import and displayed on the console; the same pack imported twice does not duplicate entries"
    requirement: IMPT-06
    verification:
      - kind: unit
        ref: "test/playstead/recognition/dat_pack_importer_test.exs"
        status: pass
      - kind: unit
        ref: "test/playstead_web/live/reference_packs_live_test.exs"
        status: pass
    human_judgment: false
  - id: D4
    description: "Reference matching upgrades identification confidence to exact using only already-stored digests (including headerless-offset fingerprints), resolves settleable attention items, emits a catalogue journal entry only for changed assets, and never touches a receipt outcome or an existing evidence row"
    requirement: IMPT-03
    verification:
      - kind: unit
        ref: "test/playstead/recognition/reference_match_test.exs"
        status: pass
    human_judgment: false
  - id: D5
    description: "The /reference-packs console supplies a pack, reports newly-identified counts, displays provenance, removes a pack (audited, no evidence touched), and offers no download/search/browse acquisition path"
    requirement: IMPT-06
    verification:
      - kind: unit
        ref: "test/playstead_web/live/reference_packs_live_test.exs"
        status: pass
      - kind: e2e
        ref: "test/playstead_web/browser/palette_test.exs, test/playstead_web/browser/coherence_test.exs (:reference_packs screen)"
        status: pass
    human_judgment: false

duration: ~2h
completed: 2026-08-28
status: complete
---

# Phase 02 Plan 08: Reference Pack Import and Digest-Based Matching Summary

An administrator can now supply their own Logiqx-style DAT reference pack through `/reference-packs`, and Playstead names any already-imported files whose digests match — using only the CRC32/MD5/SHA-1 and headerless-offset fingerprints computed at original import time, never re-reading a byte from disk — while every existing receipt and evidence row stays exactly as it was.

## Performance

- **Duration:** ~2h
- **Tasks:** 3 completed
- **Files:** 30 changed (14 created, 16 modified)
- **Commits:** 3 task commits (`bcd934a`, `4a5bfd8`, `57cf336`)

## Accomplishments

- Added the one new dependency this phase needs (`saxy` 1.6.1), pinned to the version RESEARCH.md's Package Legitimacy Audit approved, guarded by `test/playstead/dependency_pin_test.exs` asserting both the resolved version and its lockfile checksum — an automated substitute for the recommended human checkpoint, per the project owner's standing zero-manual-verification preference (documented as a deliberate deviation in the plan's own scope note).
- `Playstead.Recognition.LogiqxHandler`: reads a pack in fixed chunks, refusing before the file is fully read once a hard size cap is exceeded; refuses any document declaring a DOCTYPE or ENTITY outright via a byte-level pre-scan run before Saxy ever parses (so no external resource a hostile declaration names is ever a live code path, independent of Saxy's own safe defaults); enforces a hard rom-entry cap via Saxy's `:stop` halt; and never raises for any input. A full hostile fixture corpus (DOCTYPE, external entity, recursive entity, oversized, entry-flooded, truncated, empty, implausible declared size, and a mutation property test) proves it.
- `Playstead.Recognition.DatPack`/`ReferenceEntry`: full provenance (source, retrieval time, upstream version, the pack's own file hash, a closed-vocabulary licence claim with a free-text note, transform version) and per-entry digests/sizes, sizes stored strictly as metadata. `DatPackImporter.import_pack/3` is idempotent on the pack's own hash and writes an audit entry; a refused pack stores nothing at all.
- `Playstead.Recognition.ReferenceMatch` implements the existing `Provider` behaviour rather than a second pipeline. `Recognition.reidentify/2` re-scans not-yet-matched blobs, appends new exact-confidence evidence (promoting a possible-variant reading to a certain one only on a match), emits a catalogue journal entry only for assets that actually changed, and resolves the two attention reasons (`ambiguous_recognition`, `signature_mismatch`) a reference match can genuinely settle — content that stays unmatched gains nothing.
- `PlaysteadWeb.ReferencePacksLive` at `/reference-packs`: upload a pack, see the import result and how many library assets were newly identified, review every installed pack's provenance and licence claim, remove a pack (confirmed, audited, no evidence touched). No download, search, or browse-a-catalogue anywhere on the page. The library's dismissible install hint now links here; the screen is registered in the router, the shared console nav, and the Wallaby palette/coherence screen suites.

## Task Commits

1. **Task 1: The pinned audited dependency and the safe, capped, streaming reference-pack parser** - `bcd934a` (feat)
2. **Task 2: Digest-based reference matching that upgrades confidence without rewriting history** - `4a5bfd8` (feat)
3. **Task 3: The reference packs console** - `57cf336` (feat)

**Plan metadata:** (this commit)

## Files Created/Modified

- `lib/playstead/recognition/logiqx_handler.ex` - The streaming, capped, entity-safe DAT parser
- `lib/playstead/recognition/dat_pack.ex`, `reference_entry.ex` - Provenance and per-entry digest schemas
- `lib/playstead/recognition/dat_pack_importer.ex` - Hash-keyed idempotent import/removal, audited
- `lib/playstead/recognition/reference_match.ex` - Digest-based matching provider
- `lib/playstead/recognition.ex` - `reidentify/2`, the later-run re-scan entry point
- `lib/playstead/recognition/evidence.ex` - Widened to `utc_datetime_usec` (see Deviations)
- `lib/playstead/attention.ex` - `resolve_for_asset_set/2`
- `lib/playstead_web/live/reference_packs_live.ex` - The console surface
- `lib/playstead_web/live/library_live.ex`, `router.ex`, `components/layouts/root.html.heex` - Wiring the new screen in
- `test/support/fixtures/dat/*.dat` - The hostile + valid fixture corpus
- `test/playstead/dependency_pin_test.exs`, `test/playstead/recognition/{dat_pack_importer,logiqx_security,reference_match}_test.exs`, `test/playstead_web/live/reference_packs_live_test.exs` - Full coverage
- `priv/repo/migrations/20260828230000_*`, `20260828231500_*` - Schema + the ordering-precision fix

## Decisions Made

See `key-decisions` in frontmatter. The most consequential: reference matching is a **separate, later-run pass** (`Recognition.reidentify/2`), not wired into the live import pipeline — matching D-18's framing that installing a pack is an upgrade event, never a re-run of import itself.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Widened `recognitions.inserted_at` to microsecond precision**
- **Found during:** Task 2, writing the "possible-variant becomes certain variant" test
- **Issue:** `Playstead.Recognition.Evidence` (created in plan 02-02/02-03) used the app-wide `:utc_datetime` (second precision) for `inserted_at`. Every "the latest evidence row for a blob" read (`Playstead.Recognition`, `Playstead.Catalogue.Payload`) orders on this column alone; two evidence rows for the same blob written inside the same second — exactly what a reference match does when it runs immediately after the header-evidence provider, as in an automated re-identification pass — made that ordering genuinely ambiguous at the database level, not just flaky in tests.
- **Fix:** Migration `20260828231500` widens the column to `utc_datetime_usec`; the schema's `timestamps/1` call now matches.
- **Files modified:** `lib/playstead/recognition/evidence.ex`, `priv/repo/migrations/20260828231500_widen_recognitions_inserted_at_precision.exs`
- **Verification:** `test/playstead/recognition/reference_match_test.exs` ("a possible-variant reading becomes a certain variant only on a reference match") failed deterministically before the fix and passes after; full `mix precommit` (723 tests) passes with the migration applied.
- **Committed in:** `4a5bfd8`

### Scope Reductions

**Catalogue and attention_live.ex left untouched.** The plan's `files_modified` frontmatter listed `lib/playstead/catalogue.ex` and `lib/playstead_web/live/attention_live.ex` for tasks 2 and 3. Neither needed a change: `reidentify/2` only ever emits a journal entry for an asset that produced a new match (by construction, not by diffing an identification-state delta), so no new read from `Catalogue` was needed beyond the already-public `Catalogue.Payload.build/1`; and attention resolution needed only one new function on `Playstead.Attention` (`resolve_for_asset_set/2`) — `AttentionLive` itself needed no code change since resolved items simply stop appearing on its next load, which its existing render already handles.

**No producer of `Playstead.Blobs.BlobFingerprint` rows exists yet anywhere in the codebase.** D-20/D-18's "already computed at import time" premise for headerless-offset fingerprints (NES skip-16, SNES copier skip-512) is not yet wired into the write path — this schema was created in 02-02 "so the storage shape settles" but no earlier plan populated it. `ReferenceMatch.match/2` and `Recognition.reidentify/2` fully implement and test the *consumption* side (a manually-inserted fingerprint row is proven to produce a match a full-file digest alone would miss), but a real NES/SNES ROM imported today will not yet get a headerless fingerprint row written for it to match against. This is a gap in an earlier plan's scope, not this one's — logged below rather than silently fixed, since backfilling the write path is a nontrivial addition to `Playstead.Blobs.MultiHash`/the import pipeline that this plan's file list does not include.

---

**Total deviations:** 1 auto-fixed (Rule 1 - correctness bug in evidence ordering).
**Impact on plan:** The timestamp-precision fix was necessary for the reference-match feature to behave correctly under realistic timing (not just under test); no scope creep. The two scope reductions above shipped less code than the plan's file list anticipated without weakening any acceptance criterion — `mix precommit` (723 tests) and every task's `<verify>` command pass.

## Known Stubs

None — every deliverable this plan claims is fully wired and tested. The `BlobFingerprint` write-path gap noted above is not a stub introduced by this plan; it is a pre-existing absence in an earlier plan's scope that this plan's consumer code correctly anticipates and is ready for once populated.

## Issues Encountered

None beyond the timestamp-precision bug documented above.

## User Setup Required

None — no external service configuration required. An administrator supplies their own reference pack file directly through the console; Playstead never fetches, bundles, or redistributes one.

## Next Phase Readiness

This is the last plan in Phase 2 and the phase's deliberately droppable one, per its own objective — everything built in 02-01 through 02-07 works with no reference data installed at all. Phase 2 is now complete pending `/gsd-verify-work`.

**Follow-up recommended for a future plan:** wire `Playstead.Blobs.MultiHash`/the import write path to actually populate `blob_fingerprints` for headered systems (NES skip-16, SNES copier skip-512) at original import time, per D-20 — `ReferenceMatch` is ready to consume these rows the moment they exist, but nothing in the codebase writes them yet.

---
*Phase: 02-explainable-import-and-exact-export*
*Completed: 2026-08-28*

## Self-Check: PASSED

All 13 key files confirmed present on disk; all 3 task commits (`bcd934a`, `4a5bfd8`, `57cf336`) confirmed in git history. `mix precommit` (723 tests, 0 failures) passes with this plan's changes applied.
