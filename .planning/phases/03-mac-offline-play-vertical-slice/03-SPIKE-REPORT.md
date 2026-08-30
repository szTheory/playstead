# Phase 3 Plan 1: Mac Adapter Spike Report (D-01)

**macOS product/build tested:** 26.6.2 (25G83) — recorded in `spike/out/environment.json`, produced by `scripts/sign-and-notarize.sh` at build time.

**Signing posture for this run:** Notarization **DEFERRED**. This Playstead installation is not enrolled in the paid Apple Developer Program; there is no Developer ID Application certificate and no notarytool credential profile. Per owner decision (2026-08-30), SpikeHost was dev-signed instead — `Apple Development: REPLACE_WITH_YOUR_APPLE_ID (REPLACE_WITH_YOUR_CERT_ID)`, Team ID `REPLACE_WITH_YOUR_TEAM_ID`, hardened runtime enabled, no App Sandbox. Probes 1 and 6, which the plan defines as requiring notarized evidence, are recorded **DEFERRED** below (never faked as `pass`), with a dev-signed analogue run and clearly labeled where one exists. Revisit before plan 03-10's notarized build.

## Probe Matrix

| # | Probe | Verdict | Evidence File | Finding |
|---|-------|---------|----------------|---------|
| 1 | Notarized launch | **DEFERRED** | `spike/out/probe-01.json` | SpikeHost dev-signed only (spctl: rejected, as expected for a non-notarized build). The *downloaded emulator itself* is genuinely notarized upstream (spctl: accepted, source=Notarized Developer ID) and its quarantine attribute survives the acquire-emulator.sh pipeline (curl download → simulated LSQuarantine stamp → `hdiutil` mount → `ditto` extraction) intact — this proves the install pipeline doesn't interfere with Gatekeeper, but does not prove the shipping Playstead client's own notarized launch experience. |
| 2 | Config injection | **PASS** | `spike/out/probe-02.json` | `-C savegamePath=<dir>` is honored by the shipped Qt `mGBA.app` binary (not just the SDL frontend documentation) — `savetest.sav` was created only in the injected app-managed directory. |
| 3 | Save-flush observability (D-03) | **PASS** | `spike/out/probe-03.json`, `spike/out/save-timeline.jsonl` | 8 distinct on-disk SHA-256 values observed over a 185s live-play window — a genuine periodic flush, not exit-only. Measured cadence: on-disk changes every **~24 seconds**, even though the ROM itself re-writes SRAM every ~5 seconds — mGBA's mmap-backed SRAM store batches writes before syncing to the file. `kill -9` 2 seconds after the last observed flush lost no data (pre/post-kill digests identical). |
| 4 | Exit detection | **PASS** | `spike/out/probe-04.json`, `spike/out/exit-events.jsonl` | Three mutually distinct `(terminationStatus, terminationReason)` pairs: SIGTERM→`(15, uncaughtSignal)`, SIGSEGV→`(11, uncaughtSignal)`, SIGKILL→`(9, uncaughtSignal)`. Notable finding: mGBA does **not** catch SIGTERM for a graceful quit — an external `Process.terminate()` call is indistinguishable from a crash at the signal level. The shipping adapter host cannot rely on bare SIGTERM as a "clean quit" signal; it must find another quit mechanism (e.g. a window-close/AppleEvent path) if a distinguishable clean-exit signature is required later. |
| 5 | Controller recovery | **FAIL (unproven)** | `spike/out/probe-05.json` | No physical or paired game controller hardware was present in this execution environment (`system_profiler SPUSBDataType`/`SPBluetoothDataType` found none). A physical unplug/reconnect cycle cannot be simulated in software. Recorded as a documented gap, not a pass — requires a follow-up manual test on real hardware before PLAY-04 is promised. |
| 6 | Keychain | **DEFERRED** | `spike/out/probe-06.json` | Same notarization gap as probe 1. Dev-signed analogue (hardened runtime, non-sandboxed) ran for real: `SecItemAdd`/`SecItemCopyMatching` round-tripped cleanly, `OSStatus=0` (`errSecSuccess`) for both store and read. This is dev-signed evidence, not notarization evidence. |
| 7 | BIOS handling | **PASS** (default posture) | `spike/out/probe-07.json` | No-BIOS (built-in HLE) launch: process stays alive and produces a save file — PASS, matching D-06's default posture. Operator-supplied BIOS half: no BIOS file was available in this environment (`PLAYSTEAD_GBA_BIOS` unset) — recorded FAIL/not-run with an honest reason, never faked. `scripts/run-probes.sh` never provides, locates, or links a path to acquire a BIOS (verified: `grep -rniE bios` across `spike/README.md` and `spike/scripts/` shows no acquisition hints). |

## D-02 Ladder Adjudication

**Rung 1 — mGBA standalone (GBA), external process — PINNED.**

The four candidate-specific probes (2, 3, 4, 7) all **pass** against mGBA standalone. Probe 3 is the decisive D-03 owner-ruling gate ("a candidate passes the save probe only if an on-disk flush can be observed periodically or on-demand during play, not solely at clean exit") — mGBA standalone demonstrates a genuine periodic flush (~24s cadence, evidenced by 8 distinct on-disk digests over a 185s window), so **no fallback to rung 2 (RetroArch + mGBA core) is required**.

Probes 1 and 6 (deferred, notarization-dependent) and probe 5 (unproven, hardware-dependent) are properties of the **distribution posture and host environment**, not of the mGBA candidate specifically — per the plan's own adjudication rule, these results carry over unchanged and do not trigger ladder advancement. Every rung in the D-02 ladder (RetroArch+mGBA, SameBoy, RetroArch+SNES) would face the identical notarization gap and identical controller-hardware absence in this environment; advancing the ladder would not resolve either.

No other rungs were attempted. **mGBA standalone 0.10.5 is the pinned adapter.**

## Save Contract (Phase 4 SAVE-01 input)

- **Artifact:** `{saveDir}/{romBaseName}.sav`, injected via `-C savegamePath={path}`.
- **Format:** raw 32KB SRAM battery-save file (32768 bytes observed for `savetest.gba`'s `SRAM_V113` marker).
- **Flush trigger:** periodic, in-process, **not** solely at clean exit. Observed cadence ~24 seconds between on-disk digest changes during continuous play, independent of how often the game itself re-writes SRAM (~5s here).
- **On-demand flush:** not proven supported in this run — mGBA standalone exposes no CLI/hotkey-triggered manual-save mechanism that was probed. `on_demand_flush_supported: false` in `03-ADAPTER-PIN.json`.
- **Worst-case data-loss window under `kill -9`:** **24 seconds** — derived directly from the maximum observed interval between on-disk digest changes in `spike/out/save-timeline.jsonl` (indices 0→1s, then every 24s thereafter: 1, 25, 49, 73, 97, 121, 145, 169). Not an estimate.
- **Clean-quit caveat:** SIGTERM (`Process.terminate()`) does not produce a distinguishable graceful-exit signature — it is indistinguishable from a crash at the signal level (probe 4). Phase 4's flush-then-exit design should not assume a SIGTERM-triggered flush completes before the process dies; it should rely on the periodic on-disk flush cadence above as the durability floor, and treat any exit (clean, crashed, or killed) as potentially losing up to the same ~24s window.

## Consequences for Phase 3 Plans

- **03-03 (shipping Mac client scaffold):** Must build the real Xcode-project-based SwiftUI/AppKit app (this spike deliberately used a Swift Package executable + manual `.app` bundle assembly instead of a hand-authored `.xcodeproj`, appropriate for a throwaway harness but not for the shipping client — see Deviations in `03-01-SUMMARY.md`). The adapter host's process-launch and exit-detection code can port `AdapterProbeHost`'s pattern directly, but must NOT assume SIGTERM alone yields a clean-quit signature (probe 4 finding).
- **03-09 (preflight / launch chrome, presumed adapter-touching plan):** Must read `03-ADAPTER-PIN.json`'s `launch`/`config_injection` keys rather than restating `-C savegamePath=...` independently, and must design its readiness/preflight copy around probe 5's unresolved status — controller-connected preflight cannot claim disconnect-recovery is verified until a real-hardware follow-up test exists.
- **03-10 (notarized build / distribution):** This is the plan that must re-run probes 1 and 6 for real once a paid Apple Developer Program membership and notarytool credentials are available, replacing the `deferred` verdicts in `03-ADAPTER-PIN.json` with genuine `pass`/`fail` evidence before PLAY-05 (launch from a signed/notarized build) can be honestly promised.

## Known Gaps Requiring Follow-Up

1. **Probes 1 and 6 (notarization).** Blocked on paid Apple Developer Program enrollment. Owner-approved deferral for this run; must resolve before 03-10 ships.
2. **Probe 5 (controller recovery).** Blocked on physical game controller hardware being present at test time. No software simulation exists for a physical HID disconnect. Must be exercised manually on real hardware before PLAY-04 is promised.
3. **Fresh-macOS-user-account Gatekeeper test.** Not run — a dev-signed build cannot meaningfully prove the notarized Gatekeeper posture the real test requires (App Translocation, "Open Anyway" absence), so this is folded into the probe-1 deferral rather than run separately against the wrong signing posture.
