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
| BIOS posture | Optional. mGBA's own built-in high-level implementation launches without a BIOS; a validated BIOS file is a fidelity upgrade, never a launch requirement. |
| Persistent save support | `.sav` files under the app-managed save directory. The emulator flushes periodically during play (observed roughly every 24 seconds) and does **not** distinguish a graceful `SIGTERM`-based quit from a crash — the shipping adapter host never assumes a clean-quit save flush beyond what periodic flushing already provides. |
| Worst-case save-loss window | 24 seconds — the observed periodic-flush interval. There is no on-demand flush command this adapter exposes. |
| macOS build tested | 26.6.2 (25G83) |

## Signing and distribution posture

**Notarization is DEFERRED — requires paid Apple Developer Program
enrollment (owner decision, 2026-08-30).** This installation has no
Developer ID Application certificate and no `notarytool` credential
profile. Every build produced in this environment is dev-signed
(`Apple Development: REPLACE_WITH_YOUR_APPLE_ID (REPLACE_WITH_YOUR_CERT_ID)`, team
`REPLACE_WITH_YOUR_TEAM_ID`) with the hardened runtime enabled and is **not**
notarized. The following criteria this plan's own `must_haves` name are
therefore recorded honestly as unproven in this environment, not
faked:

- Gatekeeper accepting the distributed build with no additional user
  interaction (`spctl --assess` reporting a `Notarized Developer ID`
  source).
- A signed-and-notarized build's launch/exit/relaunch cycle, run from
  an actual notarized artifact.

Everything that does not depend on notarization — the dev-signed build,
its hardened-runtime and non-sandboxed entitlements, the absence of a
nested application bundle, and the full relaunch-after-restart proof
(`RelaunchTests`, exercised against `LocalStore`/`CASManager` directly,
independent of code signing) — is proven and covered by automated
tests. See `docs/RELEASE.md` for the exact commands and the paid-membership
path this posture will convert to once available.

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
