---
phase: 02-explainable-import-and-exact-export
plan: 03
subsystem: import-export
tags: [rom-formats, gbatek, pan-docs, nesdev, no-intro, jsonb, ecto, cas-concurrency]

requires:
  - phase: 02-explainable-import-and-exact-export
    provides: "Plan 02-02's write path (Playstead.Blobs), single-file import pipeline (Playstead.Import.import_single/3), member_fingerprint/1, blobs/source_files/asset_sets/asset_members/import_receipts schemas, and Playstead.ImportFixtures"
provides:
  - "Playstead.Formats.SystemId, Playstead.Formats.Archive, and six format validators (Gba, Gb, Nes, Snes, Md, PsxCue): the frozen seven-plus-unknown system registry and never-raising, 64 KiB-bounded byte recognition"
  - "Playstead.Formats.identify/2: the single entry point dispatching bytes to validators/archive detection"
  - "Playstead.Recognition.Provider behaviour, Playstead.Recognition.HeaderEvidence (the built-in no-reference provider), and the append-only recognitions table/Evidence schema"
  - "Playstead.Recognition.NoIntroName: release-filename parsing into title plus region/language/version/dev-status tags"
  - "Playstead.Catalogue.display_title/1, extension_guess/1, assign_system/3, override_system/3, sanitize_title/1: D-19/D-22 system assignment and title derivation"
  - "Playstead.Import.import_descriptor_set/5 and attach_companion/4: ordered multi-file manifests with incomplete-set receipts and CAS-based later completion"
  - "Playstead.Catalogue.Payload.build/1: the frozen catalogue change-journal payload; Playstead.Catalogue.exclude_set/2 (tombstone); Playstead.Sync.Snapshot's new catalogue branch"
affects: [02-04, 02-05, 02-06, 02-07, 02-08]

actuals:
  tokens: 41000
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Never-raises tagged-tuple validator contract (recognize/1 wrapped in rescue, bounded binary_part reads) reused identically across all six format validators, matching Playstead.CommandId's existing idiom"
    - "Provider stays pure/DB-free; the calling context (Playstead.Recognition) precomputes alias/variant signals from the database and hands them to the provider as ordinary facts — keeps Playstead.Recognition.HeaderEvidence unit-testable without a database"
    - "Guarded UPDATE ... WHERE blob_id IS NULL as the CAS collision authority for completing an incomplete asset member, mirroring the existing insert_all/on_conflict pattern used for asset-set lookup-or-create"
    - "Optional opt-in seam (import_single/4's opts[:format_bytes]) lets plan 02-03 wire recognition into the existing pipeline without changing behavior for callers that omit it"

key-files:
  created:
    - playstead-server/lib/playstead/formats.ex
    - playstead-server/lib/playstead/formats/system_id.ex
    - playstead-server/lib/playstead/formats/archive.ex
    - playstead-server/lib/playstead/formats/validators/gba.ex
    - playstead-server/lib/playstead/formats/validators/gb.ex
    - playstead-server/lib/playstead/formats/validators/nes.ex
    - playstead-server/lib/playstead/formats/validators/snes.ex
    - playstead-server/lib/playstead/formats/validators/md.ex
    - playstead-server/lib/playstead/formats/validators/psx_cue.ex
    - playstead-server/lib/playstead/recognition.ex
    - playstead-server/lib/playstead/recognition/provider.ex
    - playstead-server/lib/playstead/recognition/evidence.ex
    - playstead-server/lib/playstead/recognition/header_evidence.ex
    - playstead-server/lib/playstead/recognition/no_intro_name.ex
    - playstead-server/lib/playstead/catalogue/payload.ex
    - playstead-server/priv/repo/migrations/20260828020000_create_recognitions.exs
    - playstead-server/priv/repo/migrations/20260828030000_add_asset_member_ordinal_unique_index.exs
    - playstead-server/test/support/fixtures/roms/rom_fixtures.ex
    - playstead-server/test/playstead/formats/validators/gba_test.exs
    - playstead-server/test/playstead/formats/validators/gb_test.exs
    - playstead-server/test/playstead/formats/validators/nes_test.exs
    - playstead-server/test/playstead/formats/validators/snes_test.exs
    - playstead-server/test/playstead/formats/validators/md_test.exs
    - playstead-server/test/playstead/formats/validators/psx_cue_test.exs
    - playstead-server/test/playstead/formats/archive_test.exs
    - playstead-server/test/playstead/recognition/header_evidence_test.exs
    - playstead-server/test/playstead/recognition/no_intro_name_test.exs
    - playstead-server/test/playstead/import/multi_file_set_test.exs
    - playstead-server/test/playstead/import/catalogue_payload_test.exs
  modified:
    - playstead-server/lib/playstead/catalogue.ex
    - playstead-server/lib/playstead/catalogue/asset_member.ex
    - playstead-server/lib/playstead/import.ex
    - playstead-server/lib/playstead/sync/snapshot.ex

key-decisions:
  - "The single-file tracer's member role was renamed from \"rom\" (plan 02-02) to \"primary\", the closest fit in D-15's frozen role vocabulary (descriptor|track|primary|disc|patch|parent|companion) that Playstead.Catalogue.AssetMember now validates every insert against — \"rom\" was never a registered role."
  - "During an incomplete set's lifetime, member_fingerprint is computed over (role, sha256) pairs including missing members as (role, nil); this is deterministic across racing concurrent descriptor imports (all see the same known/missing bytes) and is recomputed via Catalogue.recompute_member_state/1 whenever membership changes, so the fingerprint is never stale once a companion attaches."
  - "attach_companion/4 uses a guarded UPDATE ... WHERE blob_id IS NULL (not a read-then-write check) as the concurrency collision authority for completing a missing member: the loser's guarded update affects zero rows, and if the bytes it was attaching match what the winner already attached, it reports success without creating a second row."
  - "Recognition's alias/possible-variant detection lives in Playstead.Recognition (the calling context), not in Playstead.Recognition.HeaderEvidence itself, so the provider stays pure and DB-free per the behaviour's intent, while still fully exercised by header_evidence_test.exs via the context's recognize_and_record/3."

requirements-completed: [IMPT-03, IMPT-04]

coverage:
  - id: D1
    description: "Seven frozen system identifiers, six never-raising bounded validators, and magic-byte archive detection that keeps containers opaque"
    requirement: "IMPT-03"
    verification:
      - kind: unit
        ref: "test/playstead/formats/validators/*_test.exs (property tests over arbitrary binaries)"
        status: pass
      - kind: unit
        ref: "test/playstead/formats/archive_test.exs"
        status: pass
    human_judgment: false
  - id: D2
    description: "A recognition provider behaviour with an append-only evidence store and a built-in provider that works with no reference data installed"
    requirement: "IMPT-03"
    verification:
      - kind: unit
        ref: "test/playstead/recognition/header_evidence_test.exs#recognising the same blob twice produces two rows and updates neither"
        status: pass
      - kind: unit
        ref: "test/playstead/recognition/header_evidence_test.exs#a first-time recognition with no reference data is not classified as a failure"
        status: pass
    human_judgment: false
  - id: D3
    description: "Honest display titles derived from the user's own filename, with the original name retained byte-exact"
    requirement: "IMPT-03"
    verification:
      - kind: unit
        ref: "test/playstead/recognition/header_evidence_test.exs#the original filename is byte-identical after import"
        status: pass
      - kind: unit
        ref: "test/playstead/recognition/no_intro_name_test.exs"
        status: pass
    human_judgment: false
  - id: D4
    description: "Ordered multi-file manifests with explicit required members and an incomplete-set path that completes later without duplication"
    requirement: "IMPT-04"
    verification:
      - kind: integration
        ref: "test/playstead/import/multi_file_set_test.exs"
        status: pass
      - kind: integration
        ref: "test/playstead/import/multi_file_set_test.exs (MultiFileConcurrencyTest, real Postgres connections)#two concurrent imports that each complete the same set result in one set with exactly one row per ordinal"
        status: pass
    human_judgment: false
  - id: D5
    description: "The catalogue journal payload frozen to exactly its specified fields, appended inside the mutation transaction, with a snapshot branch"
    requirement: "IMPT-04"
    verification:
      - kind: unit
        ref: "test/playstead/import/catalogue_payload_test.exs#Payload.build/1 returns exactly the frozen key set"
        status: pass
      - kind: integration
        ref: "test/playstead/import/catalogue_payload_test.exs#the snapshot returns a catalogue branch and its as-of cursor from one transaction"
        status: pass
    human_judgment: false

duration: 3h10min
completed: 2026-08-28
status: complete
---

# Phase 2 Plan 3: Format Validators, Header Recognition, and Multi-File Manifests Summary

Gives the custody pipeline eyes: seven pure, bounded, never-raising format validators (GBA/GB/GBC signature-confirmed, NES iNES/NES-2.0, SNES structural, PSX CUE) with adversarial fixtures and `stream_data` property tests, a header-evidence recognition provider that works with zero reference data installed, No-Intro filename-derived display titles, and ordered multi-file asset manifests so a two-file PlayStation game is one game with a missing part rather than two mystery files — closed out by the frozen `catalogue` change-journal payload.

## Performance

- **Duration:** 3h10min
- **Tasks:** 3 completed
- **Files modified:** 32 (28 created, 4 modified)

## Accomplishments
- `Playstead.Formats.SystemId` freezes the seven-plus-unknown system registry (copying `Playstead.Sync.EntityKind`'s shape exactly); six validator modules under `lib/playstead/formats/validators/` read at most 64 KiB, use pure Elixir binary pattern matching with no NIF/port/external command, and never raise for any input — proven by adversarial fixtures (truncated headers, bad checksums, cross-system extension confusion) and a `stream_data` property test per validator over arbitrary binaries. `Playstead.Formats.Archive` detects zip/7z/rar/gzip/xz/zstd by magic bytes only, never by extension, and `Playstead.Formats.identify/2` is the single dispatch entry point.
- `Playstead.Recognition.Provider` is a behaviour (`name/0`, `version/0`, `recognize/2`) implemented by the built-in `Playstead.Recognition.HeaderEvidence`, which treats "no reference data installed" as an ordinary quiet state, detects IPS/UPS/BPS patch signatures (never applying them), and reports possible-variant/alias matches computed by the calling `Playstead.Recognition` context against the append-only `recognitions` table. `Playstead.Recognition.NoIntroName` parses the standard release-naming convention into title plus region/language/version/dev-status tags; `Playstead.Catalogue.display_title/1` prefers the parsed title, falls back to a sanitized filename stem, and never uses the cartridge header title, while `assign_system/3` implements D-19's extension → header → user-override precedence with a `confirmation_needed` result on contradiction.
- `Playstead.Import.import_descriptor_set/5` turns a parsed CUE track table into an ordered manifest (descriptor + track members, missing companions recorded as required members with no blob and an `incomplete_set` receipt naming them); `attach_companion/4` completes a set later via a guarded `UPDATE ... WHERE blob_id IS NULL` compare-and-swap, proven convergent under genuinely concurrent Postgres connections. `Playstead.Catalogue.Payload.build/1` freezes the exact `catalogue` journal payload key set (no source path, no legacy digest, no provenance), wired into `Playstead.Sync.Snapshot`'s new catalogue branch read in the same transaction as the existing device page.

## Task Commits

Each task was committed atomically:

1. **Task 1: The frozen system registry, six pure format validators, and opaque archive detection** - `b5c7eb3` (feat)
2. **Task 2: Recognition provider behaviour, header evidence, filename parsing, and system assignment with recorded provenance** - `e923d9d` (feat)
3. **Task 3: Ordered multi-file manifests, incomplete sets, and the frozen catalogue journal payload** - `4647e87` (feat)

**Plan metadata:** pending (this commit)

## Files Created/Modified

- `playstead-server/lib/playstead/formats/system_id.ex`, `formats/archive.ex`, `formats.ex` — the frozen registry, archive detection, and dispatch entry point
- `playstead-server/lib/playstead/formats/validators/{gba,gb,nes,snes,md,psx_cue}.ex` — the six never-raising, 64 KiB-bounded format validators
- `playstead-server/test/support/fixtures/roms/rom_fixtures.ex` — the adversarial + valid header fixture corpus every validator test builds on
- `playstead-server/lib/playstead/recognition.ex`, `recognition/{provider,evidence,header_evidence,no_intro_name}.ex` — the recognition provider behaviour, append-only evidence schema, built-in provider, and filename parser
- `playstead-server/lib/playstead/catalogue.ex` — display-title derivation, extension/system assignment with provenance, user overrides, member-fingerprint recompute, and set exclusion
- `playstead-server/lib/playstead/catalogue/payload.ex` — the frozen `catalogue` journal payload builder
- `playstead-server/lib/playstead/catalogue/asset_member.ex` — the frozen role vocabulary and its `(asset_set_id, ordinal)` unique constraint
- `playstead-server/lib/playstead/import.ex` — `import_descriptor_set/5`, `attach_companion/4`, and the opt-in `format_bytes` recognition seam on `import_single/4`
- `playstead-server/lib/playstead/sync/snapshot.ex` — the new catalogue branch read inside the existing snapshot transaction
- Two migrations: `create_recognitions.exs`, `add_asset_member_ordinal_unique_index.exs`

## Decisions Made

See `key-decisions` in the frontmatter — summarized: (1) the tracer's single-file member role changed from the unregistered `"rom"` to `"primary"` now that role is DB-validated against D-15's frozen vocabulary, (2) an incomplete set's fingerprint includes missing members as `(role, nil)` pairs so concurrent descriptor imports converge deterministically and is recomputed whenever membership changes, (3) companion completion uses a guarded CAS update rather than a read-then-write check, and (4) alias/variant detection queries live in the `Playstead.Recognition` context rather than the provider itself, keeping the provider pure and unit-testable.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Tracer member role `"rom"` was never a registered D-15 role**
- **Found during:** Task 3 verification (adding the frozen-role `validate_inclusion` to `AssetMember.create_changeset/2` broke every existing single-file import test, since plan 02-02's tracer used the unregistered role `"rom"`)
- **Issue:** `Playstead.Import`'s single-file path hardcoded `@tracer_member_role "rom"`, which is not one of D-15's frozen roles (`descriptor|track|primary|disc|patch|parent|companion`). This only became a live bug once task 3 added DB-level role validation.
- **Fix:** Changed the constant to `"primary"`, the frozen vocabulary's closest fit for a single-file game's sole member. Fingerprints computed with the old constant during a test run are internal-only (no persisted production data existed), so no migration/backfill was needed.
- **Files modified:** `playstead-server/lib/playstead/import.ex`
- **Verification:** Full `mix precommit` (472 tests) passes clean, including all plan 02-02 single-file import and reimport/export round-trip tests.
- **Committed in:** `4647e87`

---

**Total deviations:** 1 auto-fixed (Rule 1 — a bug the plan's own task 3 requirement surfaced).
**Impact on plan:** No scope creep. The fix is an internal correctness correction (an unregistered role string) with zero effect on any published contract — the role vocabulary itself, the receipt outcome codes, and the catalogue payload shape are all exactly as specified.

## Issues Encountered

None beyond the deviation above.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

Ready for `02-04`. The format validators, recognition provider seam, display-title/system-assignment rules, and multi-file manifest shape are final, production forms — not prototypes — for the rest of Phase 2 to build on: plan 02-08's DAT-pack provider is a drop-in `Playstead.Recognition.Provider` implementation: the Needs Attention inbox (02-06) surfaces `confirmation_needed` system contradictions and `incomplete_set` receipts directly; and the full BagIt export (02-04/02-05) can walk `Playstead.Catalogue.Payload.build/1`'s member list to write ordered multi-file bags.

No blockers.

---
*Phase: 02-explainable-import-and-exact-export*
*Completed: 2026-08-28*

## Self-Check: PASSED

All 28 key created files verified present on disk; all three task commit hashes (`b5c7eb3`, `e923d9d`, `4647e87`) verified present in `git log`. Full `mix precommit` (472 tests, 9 properties) passes clean.
