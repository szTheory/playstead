---
gsd_state_version: 1.0
milestone: v1.0
current_phase: 03
current_phase_name: Mac Offline Play Vertical Slice
status: executing
stopped_at: Phase 04.5 complete, ready to plan Phase 3
last_updated: "2026-09-10T15:18:56.612Z"
last_activity: 2026-09-10
last_activity_desc: Phase 04.5 complete, transitioned to Phase 3
state_head: 9baa1360b6c6eabec006553d9a7d97f3b333fea4
progress:
  total_phases: 7
  completed_phases: 5
  total_plans: 71
  completed_plans: 69
milestone_name: milestone
---

# Project State

## Project Reference

See: `.planning/PROJECT.md` (updated 2026-08-30)

**Core value:** A locally available game and its progress remain effortless to play, safe, understandable, synchronized, and fully under the user's control.
**Current focus:** Phase 04.5 — Mac Pairing Ceremony

## Current Position

Phase: 03 (Mac Offline Play Vertical Slice) — READY TO EXECUTE
Plan: Not started
Status: Ready to execute
Last activity: 2026-09-10 — Phase 04.5 complete, transitioned to Phase 3

**04.5-04-PLAN.md is COMPLETE.** The operator ran the sudo-gated ceremony
proof (`prove-pairing-ceremony.sh`) at a real terminal; `PairingCeremonyTests`
passed twice against the real TLS-terminating mac_ci Phoenix (Task 1 and the
post-WR-01 re-run at Task 3), WR-01/WR-02 are closed, and the evidence is
quoted verbatim in `.planning/phases/04.5-mac-pairing-ceremony/04.5-04-SUMMARY.md`.
One must-have is recorded as partially met, not silently passed:
`SaveEndToEndTests` stays red over https, proven by A/B to be pre-existing and
transport-independent, and filed at
`.planning/todos/pending/save-e2e-duplicate-revision-409.md`. `PROT-01` is
intentionally left unmarked in REQUIREMENTS.md — that belongs to 04.5-05.
Only 04.5-05-PLAN.md remains in this phase.

Progress: [█████████░] 90% (Phase 03.5)

## Performance Metrics

**Velocity:**

- Total plans completed: 34
- Average duration: —
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| — | — | — | — |
| 01 | 8 | - | - |
| 02 | 10 | - | - |
| 03.5 | 10 | - | - |
| 04.5 | 6 | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

**Per-Plan Metrics:**

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 01 P01 | 55 min | 3 tasks | 27 files |
| Phase 01 P02 | 70min | 2 tasks | 29 files |
| Phase 01-private-custody-and-durable-protocol P03 | 90 min | 2 tasks | 31 files |
| Phase 01 P04 | 55min | 3 tasks | 22 files |
| Phase 01 P05 | 45min | 2 tasks | 10 files |
| Phase 01 P06 | 80min | 3 tasks | 28 files |
| Phase 01 P07 | 65min | 3 tasks | 17 files |
| Phase 01 P08 | 33min | 3 tasks | 5 files |
| Phase 02 P01 | 70 min | 3 tasks | 22 files |
| Phase 02-explainable-import-and-exact-export P02 | 4h30min | 3 tasks | 37 files |
| Phase 02-explainable-import-and-exact-export P03 | 3h10min | 3 tasks | 32 files |
| Phase 02 P04 | 3h40min | 3 tasks | 22 files |
| Phase 02-explainable-import-and-exact-export P05 | 3h05min | 3 tasks | 23 files |
| Phase 02 P06 | 3h20min | 3 tasks | 26 files |
| Phase 02 P07 | n/a | 3 tasks | 27 files |
| Phase 02-explainable-import-and-exact-export P08 | 2h | 3 tasks | 30 files |
| Phase 02 P09 | ~2h | 2 tasks | 16 files |
| Phase 02 P10 | 1h40min | 2 tasks | 15 files |
| Phase 03.5 P10 | 190m | 3 tasks | 11 files |
| Phase 03.5-mac-verification-automation P02 | 17 min | 2 tasks | 14 files |
| Phase 03.5 P03 | 16 min | 2 tasks | 12 files |
| Phase 03.5-mac-verification-automation P04 | 9 min | 2 tasks | 10 files |
| Phase 03.5 P05 | 256 min | 2 tasks | 29 files |
| Phase 03.5 P06 | 12m22s | 2 tasks | 8 files |
| Phase 03.5 P07 | 12h10m | 3 tasks | 19 files |
| Phase 03.5 P08 | 4h37m | 2 tasks | 10 files |
| Phase 04-persistent-save-continuity P01 | 25min | 2 tasks | 5 files |
| Phase 04 P02 | 32min | 3 tasks | 12 files |
| Phase 04 P03 | 20min | 3 tasks | 8 files |
| Phase 04 P04 | 90min | 3 tasks | 24 files |
| Phase 04 P05 | 70min | 3 tasks | 13 files |
| Phase 04 P06 | 65min | 3 tasks | 10 files |
| Phase 04 P07 | 26min | 3 tasks | 10 files |
| Phase 04 P08 | 40min | 3 tasks | 12 files |
| Phase 04-persistent-save-continuity P09 | 55min | 3 tasks | 21 files |
| Phase 04 P10 | 130min | 3 tasks | 14 files |
| Phase 04-persistent-save-continuity P11 | 45min | 3 tasks | 15 files |
| Phase 04-persistent-save-continuity P12 | 50min | 2 tasks | 11 files |
| Phase 04 P14 | 50min | 2 tasks | 7 files |
| Phase 04-persistent-save-continuity P15 | 55min | 2 tasks | 11 files |
| Phase 04-persistent-save-continuity P16 | 95min | 3 tasks | 9 files |
| Phase 04-persistent-save-continuity P17 | 20min | 3 tasks | 8 files |
| Phase 04-persistent-save-continuity P18 | 70min | 2 tasks | 13 files |
| Phase 04 P19 | 75min | 4 tasks | 9 files |
| Phase 04 P20 | 35m | 3 tasks | 8 files |
| Phase 04 P21 | 55min | 3 tasks | 7 files |
| Phase 04 P22 | ~50min | 3 tasks | 13 files |
| Phase 04 P23 | 45 min | 3 tasks | 10 files |
| Phase 04 P24 | 15min | 2 tasks | 7 files |
| Phase 04 P25 | 55min | 2 tasks | 2 files |
| Phase 04.5 P01 | 95min | 6 tasks | 18 files |
| Phase 04.5-mac-pairing-ceremony P2 | 42min | 3 tasks | 7 files |
| Phase 04.5 P3 | 28min | 2 tasks | 3 files |
| Phase 04.5 P05 | 35min | 3 tasks | 3 files |
| Phase 04.5 P06 | 25min | 3 tasks | 8 files |

## Accumulated Context

### Decisions

- The MVP is a five-phase Mac-to-server custody and continuity proof; the first active phase establishes the durable private-server and HTTPS protocol contracts.
- All native client recovery flows must converge through the versioned API; LiveView is the first-party console, never the client protocol.
- The first adapter, macOS distribution posture, parser depth, and persistent-save behavior are empirical gates, not pre-approved platform promises.
- [Phase 01]: Router-level call/2 wrapper (not Plug.ErrorHandler verbatim) for RFC 9457 exception/404 handling, since ConnTest cannot observe Plug.ErrorHandler's mandatory re-raise for Phoenix.Router.NoRouteError
- [Phase 01]: Caddyfile site address derived via Compose localhost into CADDY_SITE_ADDRESS, since Compose always sets a listed env key (even empty) but Caddy's own {$VAR:default} only falls back on truly-unset vars
- [Phase 01]: [Phase 01]: Setup-token consumption uses a guarded UPDATE ... WHERE consumed_at IS NULL inside claim/2's Ecto.Multi, relying on Postgres row-level serialization instead of an explicit SELECT FOR UPDATE, to guarantee exactly one owner from concurrent claims
- [Phase 01]: [Phase 01]: Login screen keeps the generated Email field alongside Password since D-02's no-email constraint is about mail delivery, not the login identifier
- [Phase 01]: [Phase 01]: revoke_device/2 keeps device_credentials rows (only sets revoked_at) rather than deleting them, since deletion would make a revoked device's next request indistinguishable from unauthorized, breaking the PROT-02 device_revoked contract
- [Phase 01]: [Phase 01]: pairing_requests uses utc_datetime_usec (not the app-wide utc_datetime default) so pending-queue eviction's oldest-request selection is deterministic under a fast request burst
- [Phase 01]: Per-action sudo freshness check (Accounts.sudo_mode?/1) instead of a whole-route gate for /devices, so the read-only approval queue and device list stay reachable without forcing re-authentication on every visit
- [Phase 01]: Console-triggered credential rotation UI deliberately not built in plan 01-05 — D-10 rotation already ships as a device-initiated action via /api/v1/devices/me/rotate, a stronger auth factor than owner sudo with an actual delivery path
- [Phase 01]: Added a read-only caddy_data volume mount to the app service in docker-compose.yml so Playstead.TlsTrust can read Caddy's internal-CA root certificate for pairing-time client pinning
- [Phase 01]: [Phase 01]: on_conflict convergence detection required {:replace, [:updated_at]} not :nothing, since Ecto client-generates binary_id primary keys before INSERT, making :nothing's returned struct identical between insert and no-op conflict
- [Phase 01]: [Phase 01]: Only the protocol capability namespace is required for a compatible negotiation verdict; app/cache/transfer/adapter/save mismatches degrade to compatible_with_limits, never incompatible
- [Phase 01]: Commit-order fencing for the change journal uses a write-side pg_advisory_xact_lock rather than read-side xact-id/snapshot-xmin filtering, since the latter is untestable under Ecto Sandbox's shared-transaction test harness
- [Phase 01]: Stage docs/ in the Docker builder stage before RUN mix compile (not relocating RECOVERY.md under priv/, not reading it at runtime) to fix OPER-01's docker compose build failure
- [Phase 01]: Added a generic ExUnit build-context guard (Playstead.DockerBuildContextTest) deriving required staged resources from Application.spec(:playstead, :modules) so any future compile-time embed is covered without hardcoding
- [Phase 01]: Runner-stage /app/blobs must be mkdir+chown'd to nobody before USER nobody, since Docker creates named-volume mount points root:root; scripts/compose-smoke.sh now asserts blob writability
- [Phase 02]: [Phase 02]: Escalated the Readiness :exports row to a new :error state (alongside existing :ok/:warning) since D-33 requires the export mount to be genuinely writable before any export job can run
- [Phase 02]: [Phase 02]: free_bytes/1 shells out to df -Pk (portable across the Linux release container and macOS dev) instead of adding a NIF for a raw statvfs call; required_bytes/2's margin arithmetic stays pure integer math
- [Phase 02]: Repo.insert_all/on_conflict replaces Repo.insert+catch for lookup-or-create under a unique constraint nested inside Idempotency.execute's Ecto.Multi — A failed constrained Repo.insert aborts the ambient Postgres transaction for any later query in that same transaction once nested one level deeper
- [Phase 02]: Upload concurrency uses a dedicated ETS counter (UploadSlots), not Hammer/RateLimiter — Hammer's fixed-window limiter has no decrement and cannot represent how many uploads are in flight right now
- [Phase ?]: Recognition provider stays pure/DB-free; the calling context precomputes alias/possible-variant signals from the database — Keeps HeaderEvidence unit-testable without a database and matches the behaviour contract
- [Phase 02]: adopt_temp_file/2 added to Playstead.Blobs.Store so the browser writer's finished temp file joins the CAS commit path without re-streaming its bytes — Preserves the read-once guarantee: put_stream/2 would re-read the writer's already-written file, and commit/2 assumes a live open WriteRef the writer no longer has after close
- [Phase 02]: Catalogue.list_assets/2 and get_asset_detail/2 take a Scope, unlike the rest of Phase 2's import/export context functions — These are the console's own read surface (Phase 1 convention), not part of the import pipeline's internal call chain
- [Phase 02]: SessionWorker self-chains one bounded batch per perform/1 (not a loop to completion) so the cooperative pause/cancel check is exercisable one batch at a time — Bounds a single job's runtime and makes control-check semantics directly testable
- [Phase 02]: Oban uniqueness on the session job excludes :executing so the worker's own self-chained continuation insert is never swallowed as a duplicate of the job it is chaining from — Self-chaining inserts a new job while the current one is still executing
- [Phase 02]: Attention Derive is a pure context-map function; unknown_system detection deliberately not wired live to avoid inbox flooding — D-26's exclusion side (quiet library) is the stronger design guarantee than the literal unknown-system inclusion bullet
- [Phase 02]: [Phase 02]: Sanitize.component/1 rewrites unsafe export filenames rather than rejecting them; a separate strict check (Sanitize.safe?/1) validates caller-supplied export targets
- [Phase 02]: [Phase 02]: Per-set and root export sidecars are written as BagIt tag files (tags/), not payload, so manifest-sha256.txt stays exactly the exported game bytes
- [Phase 02]: [Phase 02]: Export resumability comes from re-hash-before-write inside BagitWriter itself, not a separate per-member checkpoint table
- [Phase 02]: [Phase 02]: The D-40 'not a backup' disclosure is read at runtime from priv/static/export-readme.txt rather than an Elixir string literal, satisfying the source-level vocabulary grep gate
- [Phase 02]: Resolve format_bytes once inside Playstead.Import (not at three call sites); no_reference_installed vs no_match decided by whether any pack is installed (schema has no per-system coverage column)
- [Phase 02]: [Phase 02]: An ambiguous reference-entry conflict raises its evidence row under ReferenceMatch's own provider_name (not a distinct one) — unmatched_candidates/1's existing already-matched exclusion then settles the blob quietly until a human resolves it, so no new grouping or exclusion logic is needed
- [Phase 02]: [Phase 02]: digest_from_offset/2 is a storage-seam callback (not an object_path accessor) so headerless fingerprints stay computable by a future object-store adapter via a ranged GET, per D-12
- [Phase 03.5]: Accept hosted adoption only from exact run 33456009811 at SHA fcadbb3aca4db711d67b65eefdfc5bee1302b0c4. — Machine validation and explicit human approval both cited the same immutable run URL.
- [Phase 03.5]: Keep SnapshotTesting internal baselines hidden and publish only the reference/actual/diff triplet. — Bounded evidence stays reviewable without leaking calibration internals into the adoption artifact.
- [Phase 03.5]: Scope verifier temporary cleanup to a subshell EXIT trap. — A RETURN trap leaked beyond the verifier function and failed a hosted run after validation succeeded.
- [Phase 03.5]: Assign every Mac acceptance test to one explicit serial Unit, Rendering, UI, or LiveServer plan. — Disjoint ownership keeps result bundles authoritative and lets later plans extend the platform without runtime filtering overlap.
- [Phase 03.5]: Select hosted launch canary roots before constructing AppEnvironment. — Launch and focus mechanism checks must never initialize APIClient or consult the developer login Keychain.
- [Phase 03.5]: Stage failure evidence from an allowlist instead of sanitizing raw build trees. — Raw xcresults and DerivedData may carry paths, credentials, databases, or content metadata that should never enter the upload boundary.
- [Phase 03.5]: UI_TESTING is enabled only for Debug app/unit-test products; Release compiles no profile/bootstrap route.
- [Phase 03.5]: Deterministic profiles accept one finite name and generate their own isolated temporary root.
- [Phase 03.5]: Profile composition reuses the seeded LocalStore and blocks credential lookup and network synchronization.
- [Phase 03.5]: Accessibility IDs encode roles only; the shared focus ring is focus-owned and locked to #38BDF8.
- [Phase 03.5]: All project image assertions enter through PlaysteadSnapshot with one fixed rendering environment and calibrated tolerance.
- [Phase 03.5]: Card/status priority truth is independently authored and exhaustively checked across all 127 nonempty combinations.
- [Phase 03.5]: Library references use only fixed synthetic fixtures and role-based control identifiers.
- [Phase 03.5]: Unit and Rendering XCTest hosts select an inert DEBUG-only root before AppEnvironment construction; local UI and LiveServer layers remain default-deny.
- [Phase 03.5]: Deterministic UI profiles require explicit mode plus a finite profile and inject a credential-free environment rather than falling back to the login Keychain.
- [Phase 03.5]: Public accessibility audits fail closed for the named production root and actual descendants while excluding only application wrappers outside that structural subtree.
- [Phase 03.5]: Hosted failure artifacts contain only bounded canonical test/audit identity and outcomes; raw logs, xcresults, paths, messages, and attachments stay excluded.
- [Phase 03.5]: Plan 03.5-06: Drag and keyboard reorder converge on one settleMove production path per curation surface.
- [Phase 03.5]: Plan 03.5-06: Persisted UI relaunch profiles accept only UUID tokens resolved beneath a fixed temporary parent.
- [Phase 03.5]: Plan 03.5-06: Compile-gated curation evidence is bounded to synthetic row IDs, outbox count, and sorted catalogue digests.
- [Phase 03.5]: Plan 03.5-06 follow-up: EXIT traps own globally initialized keyboard-mode state and restore only after capture, preserving underlying early hosted failures.
- [Phase 03.5]: Hosted curation proof uses separate shelf, drag-durability, and full keyboard-durability identifiers; the full keyboard stage retains drag and two relaunches, and drag uses the deterministic last-row-to-first boundary.
- [Phase 03.5]: Persisted curation bootstrap relies on makeFixture's fresh-seed versus reopened-inventory validation; hosted evidence separates profile, sidebar, each shelf, drag, and keyboard into nine exact identifiers.
- [Phase 03.5]: Populated curation UI automation targets nodes that own semantics: the collapsed library.card for Favorites and a stable collection-row button for selection/routing; root and child evidence use separate hosted IDs.
- [Phase 03.5]: Hosted curation selectors attach identity after accessibility collapse and initiate reorder gestures on enclosing List cells; drag mutation and relaunch durability publish separate exact IDs.
- [Phase 03.5]: Curation hosted evidence publishes independent route, drag-owner, mutation/effect, direct keyboard focus, persisted reorder, relaunch, and full drag-keyboard outcomes; drag uses slow velocity with a bounded hold.
- [Phase 03.5]: Mac curation UI drag uses XCUIElement click(forDuration:thenDragTo:) and focusContainedAction is the sole Space activation; tests never double-dispatch a reorder input.
- [Phase 03.5]: focusContainedAction performs focus only; curation tests send one Space afterward and independently verify Move Up availability, click effect, keyboard effect, and held macOS drag.
- [Phase 03.5]: Local quota admission precedes credential/network admission so deterministic offline UI profiles expose real reclaim decisions without external I/O.
- [Phase 03.5]: macOS List keyboard download uses exact selection plus one selection-scoped Command-D action routed through the same quota-gated GameRow method as direct Download.
- [Phase 03.5]: Canonical game summary identity is contained separately from sibling action nodes, preserving both exact catalogue and Download accessibility evidence.
- [Phase 03.5]: Plan 03.5-07 acceptance is exact hosted run 33540648269 at bb28bba with Unit 271, Rendering 20, UI 87, and LiveServer 1 all green.
- [Phase 03.5]: Plan 03.5-08: Public pairing, exact approval, normal snapshot convergence, and scoped Keychain relaunch are the native Mac acceptance path; no private endpoint or credential override.
- [Phase 03.5]: Plan 03.5-08: Dynamic native-service values enter XCUITest through explicit LiveServer test-plan build-setting expansion, not incidental Xcode environment inheritance.
- [Phase 03.5]: Plan 03.5-08: Hosted fixture failures publish only an allowlisted stage token from a fixed mode-0600 runner-owned file.
- [Phase 03.5]: Plan 03.5-09: The live fixture's PLAYSTEAD_MAC_CI_ROOT and PLAYSTEAD_LIVE_SERVER_STAGE_ROOT must resolve to one directory; an inherited environment is trusted only when self-consistent, otherwise the materialized runtime config is authoritative.
- [Phase 03.5]: Plan 03.5-09: mac-client-control belongs to the native server root's layout and is created by the runner that owns that root, not by the fixture.
- [Phase 03.5]: Plan 03.5-09: When a bounded stage token cannot identify the failing statement, split the stage into finer bounded sub-stages rather than guessing; seven consecutive fix attempts preceded doing so.
- [Phase 03.5]: Plan 03.5-09: validate-phase-3-uat-evidence.py's AUTOMATED_MAPPINGS (23 identifiers) is authoritative over 03.5-09-PLAN.md's stale mapping table.
- [Phase 03.5]: Plan 03.5-09: Every gate must be exercised against the real file it guards; a fixture-only contract passes its own suite while being unable to accept production input.
- [Phase 03.5]: Phase close found FOUR fail-open gates, all correctly written and none protecting anything: ten static guards unreachable from ci.yml; a guard depending on Homebrew ripgrep absent from the runner image; a validator's fixture meta-test unwired; and the hosted-evidence validator itself unwired. The hazard is never a bad check, it is a check that does not execute.
- [Phase 03.5]: A missing command exits 127, and `if cmd ...; then fail` reads 127 as "clean" — so a guard whose tooling is absent passes vacuously. Guards depend only on stdlib and preinstalled tooling (python3/POSIX; no ripgrep, no PyYAML), and every guard carries a negative control asserting it catches a known-bad input before being trusted.
- [Phase 03.5]: A gate's wiring is itself guarded and mutation-tested (delete each marker, confirm failure); the contract gate enumerates tests/*.sh from the directory rather than a hand-kept list, so a new guard is picked up by existing. Beware scanning a file for a marker that also appears in its own comments — that made the first wiring guard fail-open.
- [Phase 03.5]: A claimed control must match the enforced control. T-03.5-22/23/24 name human observation as their mitigation, so human execution IS the control; T-03.5-01/20 described an automated fail-closed validator with no human carve-out, so an opt-in CLI was strictly weaker than promised and had to be wired (verify-hosted-evidence.yml, proven on run 33717728601).
- [Phase 04]: Combined inode_stability and mtime_fidelity measurement into one shared set of mutation rounds rather than two passes
- [Phase 04]: post_death_writeback spawns the writer child as a fresh swift --writer-child process rather than raw fork(), avoiding Swift runtime/fork hazards
- [Phase 04]: Clear-then-exclude ordering in AppPaths.init: clearStaleRootBackupExclusion always runs before excludeReconstructableDirectoriesFromBackup, so a pre-D-63 install's stale root flag can never re-inherit onto a directory whose own flag this same pass sets — Prevents a repaired install from re-inheriting a stale exclusion flag mid-migration
- [Phase 04]: AdapterHost.launch takes a required assetSetID parameter to key the new per-game launch mutex, updated across all call sites — D-65 mutex is per-assetSetID, not global; the key must be explicit at every call site
- [Phase 04]: reserve: :critical bypasses only the general free-space margin, never the 64 MiB physical floor (D-64) — A 32 KB save write is the one artifact that cannot be reconstructed elsewhere; open_write/2 keeps required_bytes/2 untouched for every other caller
- [Phase 04]: Save-lane limit constants and key derivation added to Playstead.Blobs rather than a new Playstead.Saves module — Playstead.Saves does not exist until plan 04-04; reuses UploadSlots/RateLimiter unchanged under a save: namespace
- [Phase 04]: SaveUploadLane mints a fresh UUIDv7 per upload attempt for command_id (never revision.id), since CommandId.cast/1 requires UUIDv7 and Foundation's UUID() is v4 — A shipped bug found before it shipped: reusing revision.id would have made every real save upload fail invalid_command_id
- [Phase 04]: Branches.heads/2 retires a revision only via parent_revision_id or a role: chosen edge; a role: acknowledged edge never retires its parent — A role-blind retirement rule would make a resolved fork's non-chosen head vanish immediately, breaking D-49's permanent Continue-from-this-one promise and independent-resolution convergence
- [Phase 04]: Keep both (acknowledge_divergence/3) is a ChangeJournal marker, never a save_revision_parents row — Any row in that table disqualifies its parent from head status, so acknowledging inside the DAG was structurally impossible without breaking heads stay heads (D-52)
- [Phase 04]: [Phase 04]: SaveCapturePoller's observe()/settle() keep returning captures on the same reads 04-04's tests exercise (now tagged tier: .staged), with a new promote() as the distinct D-04 session-end step -- landed the two-tier model with zero changes to 04-04's shipped test file
- [Phase 04]: [Phase 04]: SaveSessionRecovery derives "sessions left open" purely from save_revision's tier/session_id columns (a staged row with no matching promoted row) instead of a dedicated open-session table, staying within the plan's declared files and needing no new migration
- [Phase 04]: [Phase 04]: The 256 MiB save reserve (D-29) is folded into QuotaManager's free-space floor check, not the logical quota, since it is specifically about physical disk headroom a future save capture needs
- [Phase 04]: [Phase 04]: SaveCompatibilityGate.evaluate(candidate:target:) takes two plain SaveBinding value objects rather than a distinct LocalGameIdentity type -- both sides are denormalized facts the caller already has, keeping the gate testable with zero fixture-building layer
- [Phase 04]: [Phase 04]: LaunchSavePlanner never silently restores on a same_title verdict -- only exact widens the launch path's silent auto-restore; same_title's explicit acknowledgement belongs to a later save-timeline action, not a launch-time write
- [Phase 04]: SavesPlan takes an already-DAG-resolved revision_input (branch_key/is_head precomputed) rather than performing DAG traversal itself, keeping the export planner pure and testable standalone ahead of real Saves->Export data wiring
- [Phase 04]: A missing-bytes save revision's manifest entry uses sha256: nil, reusing BagitWriter's existing manifest_lines filter that already excludes members with no blob, rather than a new exclusion path
- [Phase 04]: SaveStateModel expresses D-35's axes as independent facts; SaveRollup/readiness Save row/SaveHistorySheet all derive copy from one shared vocabulary asserted exhaustive on both Mac and console
- [Phase 04]: A saves-owned attention source (own table/vocabulary) unions into the shared inbox at read time rather than widening Playstead.Attention.Reason — Attention.Reason is a frozen, nine-member, import-recognition-scoped vocabulary; widening it to carry save-domain meaning is the infrastructure-leaks-into-domain error the boundary rule exists to prevent
- [Phase 04-persistent-save-continuity]: Fork disposition suppression uses exact sorted-head-id-set matching, mirroring the server's fork_acknowledged?/3 rule — Keeps client/server agreement on which fork is disposed and cleanly separates head-set-scoped suppression from action-scoped no-op idempotency
- [Phase 04-persistent-save-continuity]: SaveOutbox is a sibling durable outbox inside Outbox.swift with its own table/kind vocabulary rather than widening CurationIntentKind — CurationIntent's wire shape has no natural home for a two-case save-resolution intent, and widening it would blur two distinct bounded contexts
- [Phase 04]: [Phase 04] OnlyCopyEscalationInput carries no date/elapsed-time field at all, so the escalated tier is structurally unable to escalate on duration or count (D-40)
- [Phase 04]: [Phase 04] Unpair, sign out, and delete game have no production entry point yet; only remove-local-copy and eviction are wired to OnlyCopyInterruptionGate (WINDOWS #35)
- [Phase 04]: content_key for save lines is the ROM's own sha256 (never assetSetID), matching the server's Playstead.Saves.Save schema verbatim
- [Phase 04]: CR-01 fix: resolve_parent/2 scoped to save_line_id (threaded from commit_revision's Multi), backstopped by a composite (parent_revision_id, save_line_id) DB FK; refusal reuses save_parent_unknown (409). — History is append-only so a cross-line parent link is unrecoverable once committed; app-only scoping is a single point of failure.
- [Phase 04]: CR-02 fix: D-33's save-revision rate limit and namespaced upload-concurrency slot are now invoked; UploadSlots reworked to a (bucket, unique_key) dedup model so the save route's replay (off :idempotency, D-16) dedupes on command_id instead of consuming a second slot. — Constants existed but were never called (WINDOWS #37 shape); the plan's own design point required a deliberate replay-safety decision, recorded rather than papered over.
- [Phase 04]: MC-01..MC-06 fix (plan 04-16): AppEnvironment now constructs a single shared SaveStore/SaveOutbox/SaveConflictResolver, feeding real only-copy counts into ReclaimPromptView/StorageView, a working console export deep link, the card's divergence badge, a real saveReadiness: closure on ReadinessEngine, and real ConflictComparisonSheet/OnlyCopyEscalationPanel call sites in ReadinessSheetView. — All six defects shared one root cause: tests constructed the leaf component directly and never asserted a user action reaches it; the fix is wiring at AppEnvironment's composition-root seam, backstopped by 18 new tests that drive that exact seam.
- [Phase 04]: MC-05/WR-04 scope boundary: the escalated panel's four unfixable reasons (revoked auth, capability skew, server refusal, compatibility rejection) still cannot fire because SaveUploadLane has no wired failure-classification output — a distinct, pre-existing gap recorded in WINDOWS.md, not rebuilt inside the 04-16 wiring pass.
- [Phase 04]: WR-02 fixed with rename(2) directly (matching SavePlanExecutor.renameIntoPlaceDurably), not FileManager.replaceItemAt — Consistent with existing durable-write primitive in the codebase; no new abstraction
- [Phase 04]: WR-01 fixed at the JournalApplier.applySave call site (carry forward existing local-only columns) rather than SQL COALESCE alone — tier/origin are NOT NULL with non-optional Swift defaults, so excluded.col is never actually NULL from a caller that doesn't know the true value -- COALESCE alone can't detect that case
- [Phase 04]: WS-01 fixed by exempting fork_acknowledged journal entries from Compaction.run/0 by payload shape, and updating oldest_surviving_seq/0 in lockstep — Acknowledgment markers share entity_kind with ordinary save entries; the 410 boundary must not be pulled backward by an entry exempted from deletion
- [Phase 04]: 04-19: SaveSessionCoordinator is a fresh instance per play session, not a shared singleton -- D-04's exactly-one-promotion-per-session is per-session state
- [Phase 04]: 04-19: SaveUploadLane constructed eagerly with the non-optional client (SyncEngine/OutboxWorker pattern), not lazily -- an unpaired client throws .notPaired before opening a connection, leaving the revision queued and retryable per D-32
- [Phase 04]: 04-19: capture blobs live in save-captures/<assetSetID>/, never the adapter-owned saves/<assetSetID>/ artifact directory
- [Phase 04]: 04-19: SaveUploadLane.classify escalates only genuinely unfixable server outcomes (D-22 machine codes); transport loss, 5xx, 408/429 and notPaired stay .none because escalating a self-healing condition is what D-40 forbids
- [Phase 04]: CAS commit failure surfaces as a D-31 blockage but still records the revision row — its localPath bytes are durable and uploadable, so dropping the row would turn a durability improvement into save loss (04-20)
- [Phase 04]: branch_key is the fork root's own immutable UUID (not a derived hash/counter); SavesPlan.assign_branch_letters/1 already turns a stable key into a stable letter. — Minimal correct choice; avoids new stability logic in SavesPlan.
- [Phase 04]: [Phase 04-22]: restored_here_at's upsert COALESCE order preserves the EXISTING value over incoming, opposite of manifest_digest/session_id, so restore-provenance is immutable once set
- [Phase 04]: [Phase 04-22]: SaveHistorySheet.summary defaults to nil so every pre-existing snapshot fixture renders byte-identically after giving SaveRollup its first production caller
- [Phase 04]: SaveOutboxDrainTrigger self-serializes drain passes (awaits previous task) rather than relying on actor isolation, since SaveOutbox is a plain class — SaveOutbox.drainOnce is not actor-isolated the way OutboxWorker.drainOnce is
- [Phase 04]: SaveCaptureBytesCommitter extracted from SaveSessionCoordinator and shared with SaveSessionRecovery so live and crash-recovery capture paths cannot drift apart — Two implementations of a content-addressed commit is how the two paths drifted apart in the first place (WINDOWS #52)
- [Phase 04]: WINDOWS #32 closed as stale (resolved by plan 04-16 commit c223218 before the ledger entry was written), not as fixed-by-this-plan — 04-VERIFICATION confirmed the wiring directly in source; the ledger should record why it closed, not merely that it closed
- [Phase 04]: 04-24: id chosen as {recorded_at, id} tiebreaker for revision ordering (not a stored sequence column), following attention_source.ex precedent — recorded_at remains sole ordering semantics (D-15); id is immutable and reproducible, never exposed as causal order
- [Phase 04.5]: Reused LibraryShellView's existing ShellSurface sheet mechanism for pairing rather than a new presentation path; added a CI-fixture-only approve-sole mix task instead of touching production pairing routes; AppEnvironment now threads a pairingKeychain matched to whichever Keychain apiClient reads from.
- [Phase 04.5]: PROT-01 left in progress rather than re-marked complete: the live-server pairing proof has not genuinely executed against a real server in this session.
- [Phase 04.5]: Task 3 generation token: waitForEntry() polls rather than blocking synchronously, since the coordinator's poll/redeem work is MainActor-isolated and a raw synchronous wait would starve it of its turn on the shared executor.
- [Phase 04.5]: 04.5-04: https promoted (not add-alongside) as the sole mac_ci scheme; SaveEndToEndTests A/B'd and filed as a pre-existing, transport-independent bug rather than treated as caused by TLS or silently dropped.
- [Phase 04.5]: 04.5-06: pinned trust wired at both real APIClient construction sites via AppPaths.pinnedCertificate; secure-by-default parameter instead of non-optional to avoid churning ~18 stub-backed unit tests.

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 3 must pass the Mac adapter spike (signing/notarization or sandbox posture, controller, BIOS, launch/recovery, and safe save flush) before a supported adapter is promised.
- Phase 2 must pass an adversarial archive-security gate before enabling archive extraction or deep inspection.
- ⚠️ [Phase 01] Open code-review findings (01-REVIEW.md, status issues_found): CR-01 recovery codes / reset & setup tokens not in Phoenix's parameter log filter; WR-01/05 no throttle on pairing redemption, setup-token verification, or password reset; WR-02 X-Forwarded-For trusted unconditionally; WR-06 build-context guard compares only top-level path segments. Address before exposing the server beyond a trusted LAN.
- ⚠️ [Phase 01] `mix test` is intermittently flaky (~1 in 3 full runs): `System.put_env("PLAYSTEAD_PROXY", ...)` in tls_trust_test.exs / setup_live_test.exs races async tests in devices_live_test.exs. Fix test isolation before relying on CI as a gate.
- ⚠️ [Phase 01] Volumes provisioned against a pre-01-08 image keep a root-owned /app/blobs; docs/UPGRADE.md has no note on the symptom or the one-line remediation (`docker compose exec -u root app chown nobody /app/blobs`).
- ⚠️ [Phase 01] Readiness panel is only visible inside the one-shot setup wizard; recovery codes cannot be regenerated from the console (both added to PROJECT.md Active requirements).
- ⚠️ [Phase 03.5] Plan 03.5-09 Task 3 is gated on one green hosted run. All four Mac layers plus both Linux jobs must pass; as of 18413b1 only live-server had ever failed.
- ⚠️ [Phase 03.5] Two local gates are dormant and unreachable from CI: wave-0-topology-test.sh (stale `server: true` literal, superseded by plan 08) and plan-05-surface-contract-test.sh (identity drift from plan 09 plus launch-env drift from plans 06/07). Neither has protected anything since ~plan 06. Fix and wire into the mac job after 03.5 closes.
- ⚠️ [Phase 03.5] ci.yml uses `concurrency: ci-${{ github.ref }}` with cancel-in-progress. Any push — including a docs-only commit — cancels a run in flight. Commit locally and push after the run you need has landed.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260826-tqx | Adopt Playstead as the project identity, update the planning corpus, establish workspace subproject folders, and rename the parent workspace | 2026-08-26 | 1fd0dbe | [260826-tqx-adopt-playstead-as-the-project-identity-](./quick/260826-tqx-adopt-playstead-as-the-project-identity-/) |

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Platform expansion | Second client/adapter, browser play, and broad compatibility matrices | v2 / separate spike | 2026-08-26 |
| Storage and transfer | S3-compatible storage and direct/multipart resumable upload | v2 / separate spike | 2026-08-26 |
| Optional services | Hosted storage, achievements, recommendations, and metadata/artwork expansion | v2 / separate review | 2026-08-26 |

## Session Continuity

Last session: 2026-09-10T03:22:38.424Z
Stopped at: Phase 04.5 complete, ready to plan Phase 3
Resume file: None
