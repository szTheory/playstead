# Release: Signing and Notarization

How a distributable `Playstead.app` is built, signed, and notarized.

## Current posture: notarized (as of 2026-09-11)

**Owner enrolled in the Apple Developer Program** (paid, annual) and
installed a Developer ID Application certificate plus a `notarytool`
keychain profile, lifting the notarization deferral recorded on
2026-08-30. `scripts/build-release.sh`/`scripts/sign-and-notarize.sh` run
the full notarized path unchanged — nothing about it is simulated or
stubbed. See
`.planning/phases/03-mac-offline-play-vertical-slice/03-NOTARIZATION-EVIDENCE.md`
for the verbatim proof (submission id, `Accepted` status, staple
validation, `spctl` Gatekeeper acceptance, code signature detail, and the
`RelaunchTests` run against the notarized artifact), and
`docs/SUPPORT-MATRIX.md` for exactly which claims this posture allows.

## The one-command release proof

```bash
export PLAYSTEAD_TEAM_ID="<your Team ID>"
export PLAYSTEAD_DEV_ID_APP="Developer ID Application: <Your Name> (<Team ID>)"
export PLAYSTEAD_NOTARY_PROFILE="<your notarytool keychain profile name>"

cd playstead-mac
scripts/verify-notarized-release.sh
```

This single command runs, in order: a preflight check of the three
environment variables above plus the Developer ID identity and notary
credential profile; `build-release.sh`; `sign-and-notarize.sh` in strict
mode (`PLAYSTEAD_REQUIRE_NOTARIZATION=1`, which turns any notarization
gap into a hard failure rather than a graceful degrade); `xcrun stapler
validate`; a Gatekeeper re-assertion requiring `source=Notarized
Developer ID`; the `RelaunchTests` suite run against the exported
notarized artifact; and a launch/exit/relaunch cycle of that same
artifact. Every failure path exits non-zero and prints exactly one of
`NO_TEAM_ID`, `NO_DEVELOPER_ID_IDENTITY`, `NO_NOTARY_PROFILE`,
`NOT_STAPLED`, or `GATEKEEPER_REJECTED` to stderr — never a credential, a
profile's contents, or an app-specific password.

Run only the preflight (identity/credential checks, no build) with:

```bash
scripts/verify-notarized-release.sh --preflight-only
```

## Prerequisites

| For | Requires |
|---|---|
| Notarized build (current posture) | A paid Apple Developer Program membership, a "Developer ID Application: ..." certificate, and a `notarytool` keychain profile created via `xcrun notarytool store-credentials` |
| Dev-signed build (local `xcodebuild build`/`test` only) | An "Apple Development: ..." signing identity already provisioned in Xcode/Keychain Access |

## Environment variables

| Variable | Required for | Example |
|---|---|---|
| `PLAYSTEAD_TEAM_ID` | `build-release.sh`, `verify-notarized-release.sh` preflight (always) | `TEAMID1234` |
| `PLAYSTEAD_DEV_ID_APP` | `build-release.sh` (always) | `Developer ID Application: Example LLC (TEAMID1234)` |
| `PLAYSTEAD_NOTARY_PROFILE` | `sign-and-notarize.sh`, `verify-notarized-release.sh` preflight | A profile name created via `xcrun notarytool store-credentials <profile-name> --apple-id <email> --team-id <team> --password <app-specific-password>` |

`PLAYSTEAD_REQUIRE_NOTARIZATION=1` (set automatically by
`verify-notarized-release.sh`) turns `sign-and-notarize.sh`'s old
graceful-degrade-to-dev-signed branch into a hard failure — a missing
notary profile is `FATAL: NO_NOTARY_PROFILE`, not an informational
deferral. Unset (the default when calling `sign-and-notarize.sh`
directly), behavior is unchanged from before this flag existed: a
missing `PLAYSTEAD_NOTARY_PROFILE` produces a dev-signed,
non-notarized build for local iteration.

## Verification step

```bash
spctl --assess --type execute --verbose build/Release/Playstead.app
```

Exits 0 and prints `accepted` with `source=Notarized Developer ID` for
the current, notarized posture. `sign-and-notarize.sh` in strict mode
fails loudly (non-zero exit, `FATAL: GATEKEEPER_REJECTED`) if this exact
source line is not present — a locally-signed build accepted for some
other reason is never reported as a pass.

`sign-and-notarize.sh` additionally asserts, in every posture:

- The hardened runtime flag (`flags=0x10000(runtime)`) is set.
- The app is not App-Sandboxed (D-04).
- No nested `.app` bundle exists inside the exported bundle (T-03-28) —
  the emulator is installed separately at runtime by design, never
  bundled, so a nested copy would incorrectly couple this app's
  notarization to a third party's release cadence.
