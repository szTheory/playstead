# Release: Signing and Notarization

How a distributable `Playstead.app` is built, signed, and (when a paid
Apple Developer Program membership is available) notarized.

## Current posture: dev-signed only, notarization DEFERRED

**Owner decision, 2026-08-30 (binding):** this installation has no
Developer ID Application certificate and no `notarytool` keychain
profile — notarization is deferred pending paid Apple Developer Program
enrollment. `scripts/build-release.sh`/`scripts/sign-and-notarize.sh`
below are written to run the **full** notarized path unchanged the
moment `PLAYSTEAD_DEV_ID_APP`/`PLAYSTEAD_NOTARY_PROFILE` point at real
credentials — nothing about that path is simulated or stubbed. Until
then, running these scripts produces a dev-signed, hardened-runtime,
non-notarized build, and `sign-and-notarize.sh` skips every
notarization-dependent verification step (Developer ID identity check,
`notarytool submit`, `stapler staple`, the Gatekeeper "accepted"
assertion) rather than faking them. See `docs/SUPPORT-MATRIX.md` for
exactly which claims this posture allows and which it does not.

## Prerequisites

| For | Requires |
|---|---|
| Dev-signed build (current posture) | An "Apple Development: ..." signing identity already provisioned in Xcode/Keychain Access |
| Notarized build (future, once enrolled) | A "Developer ID Application: ..." certificate and a `notarytool` keychain profile created via `xcrun notarytool store-credentials` |

## Environment variables

| Variable | Required for | Example |
|---|---|---|
| `PLAYSTEAD_DEV_ID_APP` | `build-release.sh` (always) | `Developer ID Application: Example LLC (TEAMID1234)` — or, in the current dev-signed posture, an `Apple Development: ...` identity |
| `PLAYSTEAD_TEAM_ID` | `build-release.sh` (always) | `TEAMID1234` |
| `PLAYSTEAD_NOTARY_PROFILE` | `sign-and-notarize.sh`, only to run the notarization branch | A profile name created via `xcrun notarytool store-credentials <profile-name> --apple-id <email> --team-id <team> --password <app-specific-password>` |

`PLAYSTEAD_NOTARY_PROFILE` left unset (the current posture) is what
routes `sign-and-notarize.sh` into its deferred branch — this is
intentional, not a missing-configuration error.

## Exact commands

```bash
export PLAYSTEAD_DEV_ID_APP="Developer ID Application: Example LLC (TEAMID1234)"
export PLAYSTEAD_TEAM_ID="TEAMID1234"
# Only once notarization is available:
export PLAYSTEAD_NOTARY_PROFILE="playstead-notary"

cd playstead-mac
./scripts/build-release.sh        # archive + export -> build/Release/Playstead.app
./scripts/sign-and-notarize.sh    # verify signature, notarize (if configured), assert Gatekeeper
```

## Verification step

```bash
spctl --assess --type execute --verbose build/Release/Playstead.app
```

- **Notarized posture (once enrolled):** exits 0 and prints `accepted`
  with `source=Notarized Developer ID`. `sign-and-notarize.sh` itself
  fails loudly (non-zero exit) if this does not hold — it never reports
  success on an unaccepted build.
- **Current dev-signed posture:** `sign-and-notarize.sh` runs this same
  command informationally (never asserted as a pass/fail gate in this
  branch) and prints its result for manual inspection; a dev-signed,
  unnotarized build is expected to differ from `source=Notarized
  Developer ID`.

`sign-and-notarize.sh` additionally asserts, in both postures:

- The hardened runtime flag (`flags=0x10000(runtime)`) is set.
- The app is not App-Sandboxed (D-04).
- No nested `.app` bundle exists inside the exported bundle (T-03-28) —
  the emulator is installed separately at runtime by design, never
  bundled, so a nested copy would incorrectly couple this app's
  notarization to a third party's release cadence.
