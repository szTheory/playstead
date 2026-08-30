# Gray Area A: Mac Adapter Spike & First Emulator

**Phase:** 3 — Mac Offline Play Vertical Slice
**Researched:** 2026-08-30
**Scope:** First system/emulator candidate matrix, distribution posture, bundling model, spike design, BIOS posture.
**Locked context honored:** native SwiftUI/AppKit client; client-side adapters; no core building; no ROM/BIOS distribution; emulator-neutral server protocol; persistent saves only; one supported combo in Phase 3.

---

## Decision Point 1: First system/emulator candidate matrix

### Option table

| Option | Launch/process control | Headless/CLI config injection | Save determinism + flush observability (Phase 4 critical) | Exit detect / recovery | Licensing | Apple Silicon maturity | Verdict |
|---|---|---|---|---|---|---|---|
| **mGBA standalone (Qt app, GBA)** | External `Process`/`posix_spawn` of `mGBA.app/Contents/MacOS/mGBA`; official signed universal mac builds | Yes: CLI accepts `-b/--bios`, ROM path, and `-C option=value` config overrides; portable mode reads `config.ini` beside binary; can point `savegamePath` at an app-managed dir | Raw `.sav` battery file (portable format). **Footgun:** save data is mmap'd; deterministic flush is guaranteed at unmap (clean exit / ROM change), not continuously — OS page flushes make mid-play file content best-effort. Crash-mid-play save loss is possible | Process termination observable via `Process.terminationHandler`; single-purpose window, honest quit | **MPL-2.0** — file-level copyleft, bundling/redistribution alongside any-licensed app is clean | Mature; active upstream; official mac universal builds | **Primary spike candidate** — decisive probe: at-exit flush observability |
| **RetroArch + mGBA core (external process)** | External process of notarized universal `RetroArch.app`; fully scriptable: `retroarch -L mgba_libretro.dylib --config <ours> --appendconfig <per-launch> <rom>` | Best-in-class: every path is a config key (`savefile_directory`, `system_directory`, `autoconfig` controller dirs); `--appendconfig` gives per-launch injection without touching user config | `.srm` (identical raw bytes to `.sav` for GBA battery saves). **`autosave_interval` flushes SRAM to disk every N seconds during play** — the strongest flush-observability story available; deterministic write on exit too | Same external-process semantics; quit hotkey configurable; content-less exit codes are weak — rely on save file state | RetroArch **GPLv3**, mGBA core MPL-2.0. Fine as a separate downloaded program (mere aggregation); do not link in-process without license review | Notarized + signed universal upstream builds (Metal); OpenGL-only cores need x86_64/Rosetta — mGBA core is fine on Metal build | **Fallback rung 1** — wins outright if mGBA-standalone flush probe fails; UX is uglier (RetroArch menus) but launch-fullscreen+quit-hotkey contains it |
| **libretro core in-process (load mGBA dylib via libretro API in our app)** | No child process: we own the frame loop, audio, video, input inside the Swift app | Total control of save timing — we call `retro_get_memory_data(SAVE_RAM)` and write bytes ourselves whenever we want | Perfect determinism *in theory*; in practice we become an emulator frontend: Metal/audio/timing/input plumbing, a large new engineering surface that Phase 3 does not need | N/A (in-process crash takes the app down — worse recovery) | Loading GPL cores in-process creates combined-work questions per core; mGBA core is MPL so OK, but posture generalizes badly | Cores are dylibs; we'd sign/notarize them inside our bundle | **Rejected for Phase 3** — violates "integration quality, not core hosting" spirit; revisit only if external-process posture fails entirely |
| **OpenEmu-style core plugins** | OpenEmu itself: stalled upstream, still Intel-only, **not notarized** (Sequoia requires "Open Anyway"); community ARM64 fork exists but is not a dependency to build on | Its XPC-helper-per-core architecture is excellent prior art for isolation, not a consumable adapter target | Its save handling is internal to its library layout | — | Mixed core licenses | Official build fails our own notarization bar | **Rejected** — study its architecture; do not integrate |
| **SameBoy standalone (GB/GBC)** | Native Cocoa mac app, MIT/Expat license, ships its own open-source boot ROMs (zero BIOS question) | Weaker CLI/config injection than mGBA/RetroArch on macOS (Cocoa frontend is GUI-oriented) | Raw `.sav`; simple | External process | MIT — cleanest possible | Excellent, actively maintained | **Fallback rung 2** — if GBA fails as a system, GB/GBC via SameBoy or RetroArch+Gambatte |
| **Snes9x / ares standalone** | Mac builds exist; ares is multi-system (accuracy-first, heavier), Snes9x mac frontend is thinner | Config injection less scriptable than RetroArch | SNES SRAM saves fine | External | Snes9x non-commercial license clause (**problem** for any future commercial posture); ares ISC | Good | **Not first** — Snes9x license footgun; ares CLI/config surface less proven on macOS |

### Why GBA first (system choice)

- Single-file ROM (Tier A validated in Phase 2, `gba` id already frozen in D-14), no CUE/BIN manifest complexity, no proprietary BIOS required (HLE covers ~99%), battery `.sav` is the simplest persistent-save artifact in the whole seven-system registry, and abundant legally redistributable homebrew exists **with battery-save support** (required — many homebrews never write SRAM; pick one that does, e.g., Anguna or a save-exercising test ROM).
- PSX (BIOS-required, multi-file) and SNES (copier headers, Snes9x licensing) are strictly worse first probes.

### Lens notes

- **macOS platform engineer:** external-process posture keeps emulator crashes out of our process; `Process` + termination handler + file presence/hash observation is all AppKit-clean. Watch for App Translocation/quarantine on the downloaded emulator (see DP3).
- **Phase-4 save architect:** the *decisive* probe is flush observability. mGBA standalone mmap-at-exit vs RetroArch `autosave_interval` is the real fork in this decision. SAVE-01 says "after a proven safe flush" — an at-exit-only flush is *provable* (exit event → settle debounce → hash) but loses crash-mid-play progress; periodic autosave gives revision opportunities and crash resilience. Both are acceptable contracts; the spike must pick one empirically and record it as the adapter's declared flush protocol.
- **Legal/licensing:** MPL-2.0 (mGBA) is bundling-safe; GPLv3 (RetroArch) is fine as a separately-installed/downloaded unmodified program with a source pointer; Snes9x's non-commercial clause is a landmine given PROJECT.md's possible future hosted business.
- **QA:** RetroArch's config-file-only surface is far easier to make reproducible in CI-adjacent spike scripts; mGBA Qt config override via CLI needs verification per-version (flag surface differs between mgba-sdl and mgba-qt binaries — probe explicitly).
- **Product/UX:** mGBA's window/menus look like a normal Mac app (accessibility, Cmd-Q); RetroArch's RGUI is alien to a "beautifully designed console" ethos — mitigate by launching fullscreen with content, hiding its menu behind a configured hotkey, and treating its UI as out-of-experience.

## Decision Point 2: Distribution posture

| Option | External emulator launch | Keychain | Game Controller fw | Files/bookmarks | Sparkle later | Verdict |
|---|---|---|---|---|---|---|
| **Developer ID, notarized, hardened runtime, NOT sandboxed** | Unrestricted `Process`/`NSWorkspace` launch of a separately-signed emulator; child runs under its own identity | Full | Full | Ordinary file access; still use app-managed Application Support for cache/saves by discipline | Fully supported | **Choose** |
| App Sandbox (direct-distributed) | **Blocking:** a child process spawned by a sandboxed app inherits the sandbox; a downloaded third-party emulator cannot function under our inherited container (its own config/save paths, JIT, dylib loading break). `NSWorkspace.open` of a separate .app escapes inheritance but forfeits argument/config control and process ownership | Works | Works | Security-scoped bookmarks required for BIOS/ROM drag-in — fine but friction | Sandbox-compatible with care | Reject for Phase 3; revisit only if Apple policy forces it |
| Mac App Store | Sandbox mandatory + review policy history is hostile to emulator-launcher apps; JIT entitlements gated | — | — | — | Prohibited (MAS updates only) | Reject |

Notes: hardened runtime is required for notarization anyway; we need **no** risky entitlement exceptions (we are not injecting code into the emulator — it's a separate signed program). Keychain works identically for Developer ID apps. The sandbox decision was deliberately deferred to this spike (WEB-AND-CLIENT-ARCHITECTURE §First Mac Client); evidence now points firmly at direct notarized non-sandboxed, but the spike still *demonstrates* it from an actual notarized build (stapled ticket, first-run on a clean machine/VM).

## Decision Point 3: Bundling model

| Option | Integrity | Licensing | "Exact version" display (PLAY-01) | Update coupling | Verdict |
|---|---|---|---|---|---|
| **Download-on-demand from official upstream release, version-pinned + SHA-256 verified, installed into app-managed location** | We pin `(emulator, version, arch, sha256)` per adapter release; verify before first launch; re-verify at preflight | Distributing nothing ourselves at build time; MPL/GPL obligations satisfied by pointing at upstream source; record a third-party notices file anyway | Perfect — the adapter declares exactly what it fetched and verified | Emulator updates are an explicit adapter-version bump, never silent | **Primary** ("install" half of PLAY-01) |
| Detect user-installed emulator ("select") | Hash-check the selected binary against known-version table; unknown version → honest "unverified version — supported: X" state | User's own copy; zero distribution questions | Displayed as user-supplied with verified/unverified badge | User may update it under us — preflight re-hash catches drift | **Secondary** (the "select" half of PLAY-01); cheap to include, keeps power users happy |
| Bundle inside Playstead.app | Nested-code signing: every nested binary must be signed for notarization; re-shipping mGBA.app inside our bundle couples our notarization and release cadence to theirs | MPL fine, GPLv3 RetroArch would ride inside our artifact (aggregation defensible but noisier) | Fixed per app release | Every emulator fix requires a full app release | Reject for v1; acceptable later for an offline-first installer story |

Footguns: the downloaded emulator carries the quarantine xattr → Gatekeeper evaluates it on first launch (upstream mGBA/RetroArch builds are signed/notarized, so this passes — *verify in the spike*; never strip quarantine programmatically, that is malware behavior and may trip notarization/review heuristics). App Translocation applies to quarantined apps run from ~/Downloads-style paths — installing into `~/Library/Application Support/Playstead/emulators/<name>/<version>/` and launching from there avoids translocation surprises. CACH-04/offline: once installed+verified, launch must not require network — download is install-time only, and the pinned artifact hash lives in the adapter, not the server.

## Decision Point 4: Spike design

**Sequencing: spike-first.** The ROADMAP gate is explicit ("do not promise ... until this passes") and the adapter's proven save artifact/flush is Phase 4's foundation. Run the spike as Phase 3's first plan (Wave 0/1), producing artifacts the remaining plans consume. Library/cache/LiveView plans that don't touch the adapter can be *planned* in parallel but adapter-dependent plans (preflight, launch, controller mapping, BIOS validation) wait for the spike report.

**Pass/fail probes (each yields evidence, not vibes):**

1. **Notarized launch** — Developer ID + hardened-runtime build, notarized and stapled; on a clean macOS user account it downloads, hash-verifies, and launches the pinned emulator with a homebrew GBA ROM. PASS = gameplay visible, no Gatekeeper dead-end.
2. **Config injection** — save dir, BIOS dir, controller mapping, fullscreen injected per-launch into an app-managed directory; emulator writes nothing outside it. PASS = all artifacts appear only under our paths.
3. **Save flush observability** — play a save-exercising homebrew title, save in-game, then (a) clean-quit: `.sav` appears/changes with a hashable settle point; (b) `kill -9` mid-play after an in-game save: record what survives. PASS = a documented, reproducible flush protocol (event + debounce + hash) exists; record data-loss window honestly.
4. **Exit detection/recovery** — termination handler fires for quit, crash, and force-kill; relaunch works after app restart and after server-down (offline). PASS = adapter state machine covers all three.
5. **Controller recovery** — Game Controller framework: connect, play, pull the controller mid-game, reconnect; emulator keeps accepting input (or the documented re-plumb path works); keyboard fallback never breaks. PASS = no stuck-input state without remedy.
6. **Keychain** — device credential read/write from the notarized non-sandboxed build (correct access group/ACL behavior after re-sign). PASS = no interactive Keychain prompt regression.
7. **BIOS handling** — launch without BIOS (HLE) and with a drag-in user BIOS validated by digest; emulator picks up the materialized BIOS path. PASS = both modes work; fidelity difference recorded.

**Artifacts produced:** `03-SPIKE-REPORT.md` (probe matrix with evidence), the chosen `(system, emulator, version, sha256)` pin, the **adapter save contract** (artifact path/format/flush signal/loss window — Phase 4's input), the distribution-posture record (entitlements file, notarization log), and a fallback decision if any probe failed.

**Fallback ladder (in order, stop at first full pass):**
1. mGBA standalone (GBA) — fails only if CLI/config injection or flush observability is inadequate.
2. RetroArch + mGBA core, external process (GBA) — same system, adds `autosave_interval`; fails only on launch/notarization/UX-blocking grounds.
3. SameBoy standalone or RetroArch + Gambatte (GB/GBC) — change system, keep zero-BIOS posture (`gb`/`gbc` are frozen D-14 ids).
4. RetroArch + Snes9x/bsnes core (SNES) — external-process RetroArch only (avoid Snes9x standalone license).
5. Full stop: reassess posture (in-process libretro or sandboxed helper architecture) — treat as a roadmap event, not a quiet pivot.

## Decision Point 5: BIOS posture (GBA/mGBA)

- **Default: no BIOS required.** mGBA ships an HLE BIOS covering ~99% of software; caveats are the boot logo and edge-case SWI behavior. Preflight shows "Playable without BIOS (built-in compatible replacement); add an official BIOS for maximum fidelity" — honest, non-blocking.
- **PLAY-03 drag-in:** validate a user-supplied `gba_bios.bin` by size (16 KiB) + digest match (reuse the Phase 2 DAT hash-match primitive; the official GBA BIOS digests are well-known reference values recorded in the adapter's BIOS table). Store in the private BIOS namespace; materialize only into the local emulator system dir at launch. Never link, name sources, or fetch.
- **Open replacements:** the Cult-of-GBA open-source BIOS exists (MIT); mGBA's own HLE makes shipping it unnecessary for v1. If ever declared, follow the TECHNICAL-RISKS rule: adapter declares `open-replacement` with upstream license/revision/caveats, visibly distinct from verified original firmware, after per-system legal review.
- **Fidelity display:** the adapter capability card (PLAY-01) lists three BIOS states: `built-in HLE (default)`, `verified original (user-supplied)`, `unverified file (digest mismatch — kept, not used)`.

## Prior art lessons

- **OpenEmu:** great adapter isolation (per-core XPC helpers) and library polish; cautionary tale on notarization/Apple Silicon neglect — an unmaintained signing posture kills a Mac product regardless of emulation quality. Do not depend on it; do imitate its process isolation instinct.
- **RetroArch macOS:** proves a notarized universal emulator distribution exists to download against; its config-file-everything design is exactly the injection surface an adapter wants; its UX is the anti-pattern for our surface layer.
- **Delta/AltStore:** platform-policy risk is real for emulator-adjacent apps; direct distribution keeps us out of store review. Also: users forgive emulator quirks, never save loss.
- **EmuDeck / Steam ROM Manager:** wrapping third-party emulators with injected config is a proven model at scale; their pain points are version drift of the wrapped emulator (→ our hash pinning) and path assumptions breaking on emulator updates (→ preflight re-verification).
- **Dolphin:** abandoned its own Mac App Store ambitions over sandbox/JIT constraints — corroborates DP2.
- **Provenance:** years lost to store-policy fights; ship value on the posture you control.

## Adversarial pass

1. **"mGBA CLI flags work" is manpage-verified for the SDL binary, not necessarily the Qt mac app.** The spike's probe 2 must run against the actual shipped `mGBA.app` binary; if Qt ignores `-C savegamePath=...`, portable-mode config.ini beside a private copy of the binary is the workaround — test both before declaring failure.
2. **mmap save loss window.** If the owner judges at-exit-only flush unacceptable for priority #2 (reliable saves), rung 2 (RetroArch autosave) should win even if mGBA passes — make this an explicit owner ruling in the spike report, not a silent engineering call.
3. **Homebrew without SRAM saves invalidates probe 3.** Select the test title *for* battery-save behavior first; verify it writes non-trivial `.sav` bytes on real hardware/emulator before building probes on it.
4. **Upstream release disappearance/re-tag.** Hash-pinned download breaks if upstream re-uploads; cache the verified artifact server-side? No — that edges toward redistribution of GPL/MPL binaries (legal: actually permissible with source offer, but adds obligations). v1: fail preflight honestly with "pinned version unavailable; select an installed emulator" remedy.
5. **Gatekeeper policy drift** (macOS majors keep tightening first-launch UX for downloaded apps). The spike must run on the current macOS and the report must note the exact OS build; treat "user must click Open Anyway" as a FAIL for the happy path.
6. **Controller hot-unplug behavior belongs to the emulator, not us.** If mGBA/RetroArch handles reconnection poorly, our "controller recovery" promise (PLAY-04) must be scoped to what the child process can do — probe 5 defines the honest boundary, and the readiness card copy must match it.
7. **Version-display honesty:** if the user "selects" an arbitrary emulator build, PLAY-01's "exact version support" display must show unverified status rather than implying support — don't let the select path silently widen the compatibility promise.

## Sources

- mGBA README / manpage (CLI flags, config override, portable mode, XDG config): https://github.com/mgba-emu/mgba/blob/master/README.md , https://man.archlinux.org/man/mgba.6.en
- mGBA FAQ (HLE BIOS, save behavior): https://mgba.io/faq.html
- mGBA license (MPL-2.0): https://github.com/mgba-emu/mgba/blob/master/LICENSE
- mGBA savedata mmap/unmap flush: https://github.com/mgba-emu/mgba/blob/master/src/gba/savedata.c
- libretro mGBA core docs (BIOS optional, "works for 99% of games", gba_bios.bin 16KB): https://docs.libretro.com/library/mgba/
- RetroArch macOS install docs (codesigned + notarized builds; Metal vs OpenGL/Rosetta): https://docs.libretro.com/guides/install-macos/
- Apple notarization: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- App Sandbox / security-scoped bookmarks: https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html
- Apple Game Controller framework: https://developer.apple.com/documentation/gamecontroller
- OpenEmu status (stalled, Intel-only, not notarized; community Silicon fork): https://github.com/OpenEmu-Silicon/OpenEmu-Silicon , https://retrolauncher.fr/openemu-alternative.html
- MPL 2.0 FAQ (combining with other licenses): https://www.mozilla.org/en-US/MPL/2.0/FAQ/
- Prior-art corpus: OpenEmu, RetroArch, EmuDeck, Steam ROM Manager, Dolphin, Delta/AltStore, Provenance (ecosystem knowledge; revalidate any load-bearing claim at implementation).

**Confidence:** HIGH on posture/licensing structure; MEDIUM on mGBA Qt CLI-flag fidelity and at-exit flush semantics (exactly what the spike exists to prove); facts dated 2026-08-30.
