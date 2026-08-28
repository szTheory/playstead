---
phase: 2
slug: explainable-import-and-exact-export
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-28
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (Elixir stdlib) with `Ecto.Adapters.SQL.Sandbox`; Wallaby 0.31.0 for the browser suite; `stream_data` for property tests — added test-only by plan 02-01 |
| **Config file** | `playstead-server/config/test.exs`, `playstead-server/test/support/` |
| **Quick run command** | `cd playstead-server && mix test <scoped paths> --max-failures 1` |
| **Full suite command** | `cd playstead-server && mix precommit` (compile with warnings as errors, unused-dep check, format check, full `mix test`) |
| **Estimated runtime** | Scoped runs a few seconds; full suite dominated by the browser suite |

Note: the `test` alias runs `ecto.create --quiet` and `ecto.migrate --quiet` before the suite, so every plan that adds an Ecto migration has that migration exercised by its own `mix test` verify command. A migration that fails cannot pass verification. `SCHEMA_PUSH_REQUIRED=false` — no ORM schema-push pattern from the detector table is present in this Elixir/Ecto project.

---

## Sampling Rate

- **After every task commit:** the scoped `mix test` command in that task's `<verify><automated>` block
- **After every plan wave:** `cd playstead-server && mix precommit`
- **Before `/gsd-verify-work`:** full suite green
- **Max feedback latency:** scoped runs target under 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 2-01-01 | 01 | 0 | IMPT-03 | T-02-06 | Test-only dependency; single problem-code registry | unit | `mix test test/playstead_web/error_codes_registry_test.exs test/playstead/import/scaffold_test.exs` | ❌ W0 | ⬜ pending |
| 2-01-02 | 01 | 0 | IMPT-01 | T-02-03 / T-02-04 / T-02-05 | Same-volume rename check; integer free-space margin; no content in health messages | unit + property | `mix test test/playstead/readiness_test.exs` | ✅ | ⬜ pending |
| 2-01-03 | 01 | 0 | IMPT-01 | T-02-01 / T-02-02 | Read-only inbox mount; pre-chowned export mount | integration | `mix test test/playstead/readiness_test.exs test/playstead/docker_build_context_test.exs` + compose grep assertions | ✅ | ⬜ pending |
| 2-02-01 | 02 | 1 | IMPT-02, IMPT-03 | T-02-08 / T-02-09 / T-02-10 / T-02-13 | Constraint-authoritative CAS commit; verified atomic write path; per-write free-space preflight | unit + concurrency | `mix test test/playstead/blobs/ test/playstead/import/outcome_test.exs` | ❌ W0 | ⬜ pending |
| 2-02-02 | 02 | 1 | IMPT-02, IMPT-03 | T-02-07 / T-02-12 / T-02-14 / T-02-15 / T-02-16 / T-02-17 | Digest verification; no cross-user disclosure; ceilings and upload concurrency; opaque archives | contract | `mix test test/playstead_web/controllers/api/v1/imports_controller_test.exs test/playstead_web/controllers/api/v1/blobs_controller_test.exs` | ❌ W0 | ⬜ pending |
| 2-02-03 | 02 | 1 | PORT-02 | T-02-11 | Path sanitization at every write; never touch a foreign file | contract + property | `mix test test/playstead/import/tracer_round_trip_test.exs` | ❌ W0 | ⬜ pending |
| 2-03-01 | 03 | 2 | IMPT-03 | T-02-18 / T-02-19 / T-02-20 / T-02-21 | Bounded pure validators that never raise; archives opaque; descriptor name rules | unit + property + adversarial fixtures | `mix test test/playstead/formats/` | ❌ W0 | ⬜ pending |
| 2-03-02 | 03 | 2 | IMPT-03 | T-02-23 / T-02-24 / T-02-25 | Header outranks extension; append-only evidence; sanitized display titles | unit | `mix test test/playstead/recognition/` | ❌ W0 | ⬜ pending |
| 2-03-03 | 03 | 2 | IMPT-04 | T-02-22 | Catalogue payload carries no path, legacy hash, or provenance | unit + integration | `mix test test/playstead/import/multi_file_set_test.exs test/playstead/import/catalogue_payload_test.exs test/playstead/sync/` | ❌ W0 | ⬜ pending |
| 2-04-01 | 04 | 3 | IMPT-01 | T-02-26 / T-02-29 | Ceiling enforced before writing; aborted upload leaves nothing | unit | `mix test test/playstead/import/hashing_writer_test.exs` | ❌ W0 | ⬜ pending |
| 2-04-02 | 04 | 3 | IMPT-01 | T-02-26 / T-02-30 | Boundary at and above the ceiling; outcome rendered from the stored code | LiveView + unit | `mix test test/playstead/import/preview_test.exs test/playstead_web/live/import_live_test.exs test/playstead_web/live/copy_contract_test.exs` | ❌ W0 | ⬜ pending |
| 2-04-03 | 04 | 3 | IMPT-02 | T-02-27 / T-02-28 / T-02-31 | Scope-only library views; escaped rendering; provenance labelled as a claim | LiveView | `mix test test/playstead_web/live/library_live_test.exs test/playstead_web/live/copy_contract_test.exs` | ❌ W0 | ⬜ pending |
| 2-05-01 | 05 | 4 | IMPT-05 | T-02-32 / T-02-34 / T-02-39 | Link-not-following scan; session cap; inbox provably unmodified | unit | `mix test test/playstead/import/inbox_test.exs test/playstead/import/staging_test.exs` | ❌ W0 | ⬜ pending |
| 2-05-02 | 05 | 4 | IMPT-05 | T-02-33 / T-02-35 / T-02-36 | Session-level disk-full pause; per-session cooperative control; crash recovery | integration (Oban manual mode) | `mix test test/playstead/import/session_worker_test.exs test/playstead/import/reconcile_test.exs` | ❌ W0 | ⬜ pending |
| 2-05-03 | 05 | 4 | IMPT-05, IMPT-03 | T-02-37 / T-02-38 / T-02-40 | Throttled journal entries; user-scoped reads; audited control actions | contract + LiveView | `mix test test/playstead/import/progress_test.exs test/playstead_web/live/import_sessions_live_test.exs test/playstead_web/controllers/api/v1/import_sessions_controller_test.exs test/playstead/sync/` | ❌ W0 | ⬜ pending |
| 2-06-01 | 06 | 5 | IMPT-06 | T-02-43 / T-02-44 / T-02-48 | Quarantine blocks inspection and serving; per-user release; grouped archives | unit | `mix test test/playstead/attention/derive_test.exs test/playstead/attention/quarantine_test.exs` | ❌ W0 | ⬜ pending |
| 2-06-02 | 06 | 5 | IMPT-06 | T-02-41 / T-02-42 / T-02-45 / T-02-46 | Scoped resolution; single-apply under concurrency; audited and additive | unit + contract | `mix test test/playstead/attention/resolutions_test.exs test/playstead_web/controllers/api/v1/attention_controller_test.exs` | ❌ W0 | ⬜ pending |
| 2-06-03 | 06 | 5 | IMPT-06 | T-02-47 | Escaped rendering of user-derived strings | LiveView | `mix test test/playstead_web/live/attention_live_test.exs test/playstead_web/live/copy_contract_test.exs test/playstead_web/live/library_live_test.exs` | ❌ W0 | ⬜ pending |
| 2-07-01 | 07 | 6 | PORT-02 | T-02-49 / T-02-57 | Single sanitizer with root-anchored join; quarantined content placed separately | property + unit | `mix test test/playstead/export/sanitize_test.exs test/playstead/export/layout_test.exs test/playstead/export/bagit_writer_test.exs` | ❌ W0 | ⬜ pending |
| 2-07-02 | 07 | 6 | PORT-02 | T-02-50 / T-02-51 / T-02-53 / T-02-54 / T-02-56 / T-02-58 | Target confinement; never touch foreign files; write-then-verify; resumable | integration + contract | `mix test test/playstead/export/worker_test.exs test/playstead/export/verify_test.exs test/playstead_web/controllers/api/v1/exports_controller_test.exs test/playstead_web/live/exports_live_test.exs` | ❌ W0 | ⬜ pending |
| 2-07-03 | 07 | 6 | PORT-02 | T-02-52 / T-02-55 | Identity from re-hashed bytes, never from a sidecar identifier | contract | `mix test test/playstead/export/round_trip_test.exs` | ❌ W0 | ⬜ pending |
| 2-08-01 | 08 | 7 | IMPT-03 | T-02-59 / T-02-60 / T-02-61 / T-02-62 / T-02-63 / T-02-66 | Entity-safe capped parser; pinned audited dependency; recorded provenance; no acquisition path | unit + adversarial fixtures + property | `mix test test/playstead/recognition/dat_pack_importer_test.exs test/playstead/recognition/logiqx_security_test.exs test/playstead/dependency_pin_test.exs` | ❌ W0 | ⬜ pending |
| 2-08-02 | 08 | 7 | IMPT-03 | T-02-64 / T-02-65 | Append-only upgrade; digest-based matching; override still wins | unit | `mix test test/playstead/recognition/reference_match_test.exs test/playstead/attention/` | ❌ W0 | ⬜ pending |
| 2-08-03 | 08 | 7 | IMPT-06 | T-02-63 / T-02-66 | Provenance displayed; no download or fetch path | LiveView | `mix test test/playstead_web/live/reference_packs_live_test.exs test/playstead_web/live/library_live_test.exs test/playstead_web/live/copy_contract_test.exs` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

Every task above carries an `<automated>` verify command. There are no `MISSING` references and no three consecutive tasks without an automated verify.

---

## Wave 0 Requirements

Delivered by plan 02-01 (wave 0):

- [ ] `playstead-server/test/playstead/import/` — created with `.keep`; destination for IMPT-02, IMPT-03, IMPT-04, and IMPT-05 tests
- [ ] `playstead-server/test/playstead/export/` — created with `.keep`; destination for PORT-02 tests
- [ ] `playstead-server/test/playstead/formats/validators/` — created with `.keep`; destination for the Tier A/B validator tests
- [ ] `playstead-server/test/playstead/recognition/` — created with `.keep`; destination for provider and reference-pack tests
- [ ] `playstead-server/test/playstead/attention/` — created with `.keep`; destination for IMPT-06 tests
- [ ] `playstead-server/test/support/fixtures/roms/` — binary fixture directory for valid and adversarially malformed headers
- [ ] `playstead-server/test/support/fixtures/import_fixtures.ex` — `Playstead.ImportFixtures`: deterministic byte generation, temp-file-with-known-digest helper, zero-byte helper, and a literal known-digest constant
- [ ] `{:stream_data, "~> 1.1", only: [:test]}` in `mix.exs` with the resolved version in `mix.lock` — required for the never-raises validator properties, the CUE parser, the export sanitizer, and the free-space arithmetic
- [ ] `test/playstead_web/error_codes_registry_test.exs` and `test/playstead/import/scaffold_test.exs` — the first tests proving the new directories are on the `mix test` path

Directories created later by their own plans (not wave 0 blockers, since each plan creates its own file alongside the code it tests): `test/playstead/blobs/` (plan 02-02), `test/support/fixtures/dat/` (plan 02-08).

---

## Manual-Only Verifications

All phase behaviors have automated verification. No `checkpoint:human-verify` task is planned anywhere in this phase, per the owner's standing zero-manual-verification preference.

Two items are worth recording as deliberate substitutions rather than gaps:

| Behavior | Requirement | Substitution |
|----------|-------------|--------------|
| Package legitimacy of the one new runtime dependency | IMPT-03 (plan 02-08 task 1) | The research-phase manual audit returned an approved verdict; RESEARCH.md recommended a blocking human checkpoint on procedural grounds because the automated legitimacy tool does not cover this package registry. Substituted with `test/playstead/dependency_pin_test.exs`, which fails if the pinned version or its lockfile checksum diverges from the audited values. Recorded in plan 02-08's scope note and threat register entry T-02-62. |
| Container mount ownership and read-only enforcement | IMPT-01 (plan 02-01 task 3) | Asserted by `scripts/compose-smoke.sh` (inbox listable but not writable, export path writable) rather than by a human running `docker compose up`. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 2s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
