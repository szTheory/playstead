# Support Matrix

Exactly one supported combination — nothing broader than what
`.planning/phases/03-mac-offline-play-vertical-slice/03-ADAPTER-PIN.json`
and the plan 03-01 spike actually proved. A support matrix that promises
a category rather than a proven combination is the specific dishonesty
this project's constraints forbid.

| Fact | Value |
|---|---|
| System | Game Boy Advance (`gba`) |
| Emulator | mGBA |
| Pinned version | 0.10.5 |
| Pinned SHA-256 digest | `443b490ec728293dfcde1cb9db160f73d94c457cb1864f3ce0407e60e174b09c` |
| Accepted content | `.gba` ROM files only |
| BIOS posture | Optional. mGBA's own built-in high-level implementation launches without a BIOS; a validated BIOS file is a fidelity upgrade, never a launch requirement. A production reference for the pinned `gba` system is now pinned at `.planning/phases/03-mac-offline-play-vertical-slice/03-BIOS-PIN.json`, with its provenance recorded in that file's `provenance` array. This product offers no acquisition path for BIOS content — the pin file's own `acquisition_path` field states that explicitly. Open BIOS replacements remain undeclared in v1 (03-CONTEXT.md D-06). What is proven automatically: the reference is wired all the way from the pin file through `BiosReferences.production` into the app's composition root (`BiosProductionReferenceTests`), and a correctly-sized non-matching candidate is refused for its contents rather than for having no reference at all. What still needs an operator with a real, legally-owned file: acceptance of genuine BIOS bytes, checkable in one command via `scripts/verify-bios-reference.sh <path>`. |
| Persistent save support | `.sav` files under the app-managed save directory. The emulator flushes periodically during play (observed roughly every 24 seconds) and does **not** distinguish a graceful `SIGTERM`-based quit from a crash — the shipping adapter host never assumes a clean-quit save flush beyond what periodic flushing already provides. |
| Worst-case save-loss window | 24 seconds — the observed periodic-flush interval. There is no on-demand flush command this adapter exposes. |
| macOS build tested | 26.6.2 (25G83) |

## Signing and distribution posture

**Notarized as of 2026-09-11.** The Apple Developer Program enrollment
deferred on 2026-08-30 was lifted once the owner enrolled and installed a
Developer ID Application certificate and a `notarytool` credential
profile (`playstead-notary`). The build is signed with `Developer ID
Application: Johnathan Bryan (6CH9Y797RU)`, submitted to and accepted by
Apple's notary service (submission `8465f74d-5468-4b73-9885-fb0ea1dafcdd`,
status `Accepted`), and the notarization ticket is stapled into the
exported bundle. Gatekeeper accepts the notarized artifact with **no user
interaction**:

```
build/Release/Playstead.app: accepted
source=Notarized Developer ID
```

Verbatim tool output — the notarytool submission log, the stapler
validation, three independent `spctl --assess` confirmations, the
`codesign -dvvv` signature detail, and the `RelaunchTests` run against
this exact notarized artifact — is recorded in
`.planning/phases/03-mac-offline-play-vertical-slice/03-NOTARIZATION-EVIDENCE.md`.

The full relaunch-after-restart proof (`RelaunchTests`, exercised against
`LocalStore`/`CASManager` directly and, in this run, against the
notarized/stapled exported `.app`) and the hardened-runtime,
non-sandboxed, no-nested-bundle assertions all pass. See
`docs/RELEASE.md` for the one-command release proof
(`scripts/verify-notarized-release.sh`).

## Save restore support

| Fact | Value |
|---|---|
| Save kinds supported | Persistent battery saves only. **Save states are not supported** and are not captured, synced, restored, or exported. |
| Backup media recognised | SRAM 32 KB (`sram_32k`) — the only medium observed and proven by the plan 03-01 spike. EEPROM 512 B / 8 KB and Flash 64 KB / 128 KB are **declared in the adapter pin and captured, but no restore of them has been proven on real hardware in this environment.** |
| Restore requires | Same system, same save kind, same backup medium and exact byte size, and either the exact same game file the save was made with, or a different copy of the same game confirmed by an installed reference pack. |
| Restore across different copies of a game | Permitted **only** with an installed reference pack that identifies both copies as the same title with certainty, and only behind an explicit confirmation. Never automatic. |
| Restore across emulators | A GBA battery save is written by the game, not the emulator, so these files are portable in principle. Playstead does not claim, and has not tested, restore into any emulator other than the pinned one. |
| Restore from a physical cartridge | Not supported. No cartridge hardware path exists. |
| Integrity | Every save revision is verified by full SHA-256 re-hash at restore time, and the written file is re-hashed before it is put in place. |
| Overwrite behaviour | Restore never overwrites in place. The save currently on this Mac is captured as its own revision first; if that capture fails, the restore does not run. |

## Controller support

The controller lifecycle (`ControllerHost`, `ControllerMapping`,
`ControllerSettingsView`, `ControllerTestView`) is built and fully
tested against an injectable `ControllerInputSource` abstraction. Real
controller hardware itself remains **unproven** — the plan 03-01 spike
recorded this FAIL/unproven for lack of any physical or paired
controller in the execution environment (03-SPIKE-REPORT.md, probe 5).
This support matrix does not claim controller hardware support beyond
"the logic is correct and tested against a simulated controller
source" until a real device is verified against a build produced from
this codebase.
