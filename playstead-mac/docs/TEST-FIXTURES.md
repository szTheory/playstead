# Local test fixtures and automation defaults

## Established playable fixture

**AerevenAdvance** is the owner-supplied, already approved homebrew GBA fixture. Reuse it for applicable playable-game, persistent-save, recovery, integration, and smoke journeys. The owner reaffirmed this choice on 2026-09-27. A new test profile or a restore containing only synthetic QA sentinels does not require the owner to pick a new game.

The private local registry is `.local/test-fixtures/aerevenadvance.json`, relative to `playstead-mac`. It is ignored by Git and mode 600 inside mode-700 directories. It records the existing local ROM and recorded persistent-save sources and their verified identities. Treat sources as immutable; use isolated working copies and production data paths. Registry absence or staleness calls for discovery using the evidence below before asking the owner for files. Do not publish paths, hashes, ROM/save bytes, credentials, CA material, or native captures in execution receipts.

The saved fixture uses a battery `.sav`. Emulator save states are a separate capability. A fresh AerevenAdvance run shows New game; Continue appears after persistent progress exists. Match the intended game's asset identity and save lineage explicitly; a first-row selector or a save belonging to another game cannot establish this fixture's recovery.

### Existing evidence to consult

- `.planning/notes/2026-09-22-aerevenadvance-fresh-save-menu.md`: initial menu behavior.
- `.planning/notes/2026-09-22-aerevenadvance-fresh-save-menu-2.md`: owner observed Continue resuming at the world map, then another save/quit/Continue cycle resuming in the next town. Server revisions and drained local uploads were checked for those fresh-save runs.
- `.planning/debug/resolved/restored-save-not-materialized.md`: corrected restored-save snapshot/prefetch path, verified isolated source import, independently read backup, fresh restore, exact ROM/save materialization, clean exit and Continue menu across two launches. The owner accepted the restored Continue-menu criterion; restored in-game entry was not observed.
- `.planning/debug/resolved/restored-save-materialization-handoff-20260924.md`: historical source identities and cautions. Its paused state is superseded by the resolved debug record; do not restart completed imports or obsolete manual setup.

These records establish fixture availability and previous evidence, not an automatic pass for a new recovery run. Revalidate the actual local bytes, selected backup/restore and production journey. The self-authored `spike/testrom/savetest.gba` remains useful for SRAM/flush probes; its current implementation resets its counter on startup, so it cannot prove restoring AerevenAdvance's Continue state.

### Repeatable local recovery preparation

On this configured Mac, the ignored mode-700 `playstead-mac/.local/run-recovery.sh` is the one-command entry point. It reuses the fixture registry and ignored signing configuration, refreshes a stale restore, prepares trust and the disposable owner when needed, and enables the already authorized exact-request approval. The original temporary launcher remains usable during this execution; the ignored local copy survives temporary-directory cleanup.

Once the local registry exists, `scripts/ci/prepare-recovery-fixture.py` revalidates the registered originals and published backup identities, then invokes the production retained-restore command into a newly generated isolated target. It records the new correlated handoff and exact Compose project privately in the registry. When replacing a prior registered target, it first validates the private handoff and verified receipt, preserves a compact receipt history, then calls the production cleanup command for that exact target. If the old handoff is missing while its recorded Docker resources remain, preparation fails closed instead of starting another stack. It does not reimport the ROM or mutate canonical/personal stacks. Restore output remains in a private log until success; public output is reduced to stage/outcome. A retained receipt older than the coordinator's freshness window requires this preparation again.

Set `PLAYSTEAD_RECOVERY_FIXTURE_RECORD` to the local registry when invoking `recovery-e2e.sh`. The coordinator's `recovery-fixture.py` helper verifies the registry's source identities, exact backup chain, and selected handoff before creating a clean profile. It writes only the expected game/save identity into a mode-600 per-run contract. The client must obtain the actual bytes through production sync and download. This keeps the existing fixture discoverable while preserving a genuinely clean client.

## Disposable test accounts and approval

The owner authorized automated setup for disposable isolated recovery tests. Prefer the supported test-owner helper and local private state before requesting personal login or manual pairing:

1. Validate the retained target's handoff, resource identity, isolation, and trust.
2. Use `scripts/ci/recovery-test-owner.sh check`, or the explicitly authorized `prepare` action when setup is needed. A restored single-owner clone uses its supported password recovery flow; it does not require creating a second owner.
3. Use `PLAYSTEAD_RECOVERY_TEST_OWNER_APPROVAL=1` for the disposable recovery runner. Approval must match the fresh request actually emitted by that run's clean Mac.
4. Reuse ignored `.env.local` signing configuration and verified local trust. Keep passwords and keys out of repository and public output.

See `RECOVERY-TEST-OWNER.md` and `RECOVERY-BROWSER-TRUST.md` for the implemented contracts. Interactive OS authorization or genuinely missing external input may still require the owner; first establish the specific missing capability using existing automation.

## Lesson from the Phase 06 execution

The runner selected a synthetic QA restore, and the executor incorrectly treated its lack of playable content as proof that the owner had not supplied a fixture. It also initially asked for personal login despite the owner's authorization to prepare disposable test identity. Before any prerequisite question, consult this guide, the local registry, supported setup tools, and the resolved evidence. Record actual missing capabilities only after those checks.

Match fixture members using the production protocol: the single-file importer emits the frozen role `primary`. A test-only `rom` role wrongly reports this existing game as missing. Type-check changed XCTest helpers before the full clean build; Swift parsing alone does not catch missing arguments or imports.

Close emulator children before deleting a disposable profile. Match the run's exact executable, bundle and launch identity; never quit by application name alone. Aborted-run cleanup is not evidence of a clean save flush. Native app discovery can launch an application implicitly, so inventory running apps before selecting one for inspection.

The private joined journey belongs to the serial `Recovery.xctestplan`; hosted
`LiveServer` has no access to its retained target and must not select that test.
Require the launched app to be foreground before toolbar interaction. The local
launcher retains only a sanitized latest receipt for subsequent qualification.
See [CONTINUATION-PROTOCOL.md](CONTINUATION-PROTOCOL.md) for the separate in-game
oracle gate and its current capability limit.

## Authored GB/GBC continuity aliases

The aliases `gb-mbc1-8k`, `gbc-mbc5-32k`, and `gbc-mbc3-rtc` identify only the
tracked self-authored fixtures generated by
`.planning/spikes/001-bios-free-gameplay/build_fixture.py`. Their registry
pins each ROM digest and mapper/save declaration. The packaged continuity
runner imports through the existing private Mac CI fixture task, then uses
separate source and target profiles against one disposable live-server
composition. Use `scripts/ci/gb-gbc-save-e2e.sh --local-no-hid --all-cases`
for all registered aliases or `--case <alias>` for one. Raw ROM/save data,
local registry paths, screenshots, and detailed readback receipts remain
private. Public CI carries sanitized outcomes and exact required test identities.
Both full and focused runners supply a mode-700 private output directory through
`PLAYSTEAD_GB_GBC_SAVE_EVIDENCE_DIRECTORY`; this is independent of the optional
save-reliability lane and its output setting.

For the AerevenAdvance case, the runner verifies the registered ROM and save
hashes and sizes, then copies both originals into its mode-700, per-run fixture
directory with mode 600. Its temporary registry points only to those verified
copies; production import and save custody still use the ordinary server and
client paths. The original registry and source files remain unchanged.

The bounded restore regression qualifies the exact pinned mGBA child PID, path,
digest, and runtime bundle, then polls its unique XCTest game-window capture for
both Continue and New game on the first launch and after the app relaunch. The
menu-only check does not claim GBA in-game readback. XCTest retains the child
window frame and OCR text in the ignored local result bundle.

GB/GBC game readback opens Tools → Scripting through XCTest menu actions on
that same verified child. It uses the UI testing service and does not call raw
Accessibility APIs or change system permissions. Keep the compiled no-HID
controller source enabled: the adapter creates a private controller config at
launch, which overrides an inherited `XDG_CONFIG_HOME`; a separately seeded Qt
shortcut is therefore unsuitable for this oracle. Disabling the controller
source would also change the qualified launch composition.

In an isolated checkout, point `PLAYSTEAD_CI_BUILD_ROOT` at the existing ignored
build cache and retain the validated authored alias registry. Rebuild test
products when changing source composition. Require each selected game/readback
test to be discovered and executed exactly once, with no failures or skips;
CI registration alone does not establish a passing hosted journey. The source
and fresh target must still prove real game RAM, rendered pixels, immutable
save transfer, and exact emulator identity.
