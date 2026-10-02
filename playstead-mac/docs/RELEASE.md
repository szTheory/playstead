# Release: Signing and Notarization

## Recovery known-playable evidence

The server and Mac evidence chain has two distinct automated outcomes and one
separate human observation. First, run the Plan 05-11 unattended Compose
fixture from `playstead-server`:

```bash
scripts/recovery-proof.sh --restore --compose-fixture
```

For that server command, **exit 0 is verified recovery**, **exit 77 is an
unmet Docker precondition**, and **any other exit is failure**. Its temporary
fixture validates the database/CAS/manifest/authenticated-API restore chain;
it tears down its target and is never a Mac target or a known-playable claim.

A real retained isolated restore target prints a mode-`0600`
`server-handoff.json` pathname plus both of the following copy-paste forms.
Only that Plan 05-13 handoff can start Mac preparation:

```bash
export PLAYSTEAD_RECOVERY_RESTORE_HANDOFF='/absolute/path/to/playstead-restore-target/server-handoff.json'
scripts/ci/prove-recovery-known-playable.sh --prepare --fixture --no-human-observation
```

Or copy the command's single emitted chained invocation directly. Do not search
for a temporary path, and do not substitute the disposable Compose fixture.

The handoff is mode `0600` and has exactly six allowlisted fields:
`schema` (`playstead.restore-handoff.v1`), `correlation_id`, `project`, `url`,
`receipt_path`, and `ca_path`. It is accepted only when the local receipt has
the matching opaque correlation, `state: verified`, all six completed stages
(`chain`, `preflight`, `database`, `cas`, `manifest`, `api`), a fresh isolated
`playstead-restore-*` Compose identity, matching localhost HTTPS port, and
the adjacent CA/receipt files. Unknown or secret-bearing fields, stale,
incomplete, mismatched, missing, or non-isolated evidence is refused before a
clean profile is created or the target is contacted.

The command health-checks that exact target, creates a clean profile, and uses
the real Mac app's UI-test target to launch, request TLS pairing, exit, and
relaunch. It does not have an owner credential: the restore handoff never
carries one. Therefore the automated receipt records pairing requested in the
app, while approval, authenticated convergence, capability/adapter identity,
cached bytes, and save lineage remain explicitly pending. A parser fixture is validation mechanics only;
it is not recovery or known-playable evidence.
Likewise, `restore data verified; known-playable proof pending` is not a
known-playable pass.

The pending receipt is the correlation-linked input to the named observation
procedure, which remains the only human observation gate. On the isolated target, an authorized owner must complete pairing;
then a named observer uses the legal homebrew fixture to confirm the compatible
save continues beyond the recorded pre-save point, exits, and relaunches.
Only then complete that same receipt with observer name and UTC timestamp:

```bash
scripts/ci/prove-recovery-known-playable.sh \
  --fixture --record-human-continuation \
  --receipt /path/to/pending-receipt.json \
  --observer 'named observer' \
  --observed-at-utc '2026-01-02T03:04:05Z'
```

Run the script on a Mac with Xcode installed and an Apple Development signing
identity. If exactly one such identity is installed, the recovery driver uses
it locally. Otherwise select it explicitly without committing personal signing
data:

```bash
export PLAYSTEAD_MAC_DEV_SIGNING_IDENTITY='Apple Development: <name> (<team>)'
export PLAYSTEAD_TEAM_ID='<team>'
scripts/ci/prove-recovery-known-playable.sh --prepare --fixture --no-human-observation
```

The recovery-only command verifies the selected certificate's subject OU against
the configured team, uses its non-sandboxed, no-virtual-device test entitlement,
and never uses ad-hoc signing or asks to bypass Gatekeeper. Exit 77 is an unmet
Xcode/signing precondition. The observer name, receipt path, and signing values
are private operational evidence and must not be committed.

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
mkdir -p release-evidence
scripts/verify-notarized-release.sh \
  --evidence-output release-evidence/notarization.log
```

This single command runs, in order: a preflight check of the three
environment variables above plus the Developer ID identity and notary
credential profile; `build-release.sh`; `sign-and-notarize.sh` in strict
mode (`PLAYSTEAD_REQUIRE_NOTARIZATION=1`, which turns any notarization
gap into a hard failure rather than a graceful degrade); `xcrun stapler
validate`; a Gatekeeper re-assertion requiring `source=Notarized
Developer ID`; the `RelaunchTests` suite run against the exported
notarized artifact; and a launch/exit/relaunch cycle of that same
artifact. Every failure path exits non-zero with a bounded diagnostic. The
principal release-gate tokens are
`NO_EVIDENCE_OUTPUT`, `NO_TEAM_ID`, `NO_DEVELOPER_ID_IDENTITY`,
`NO_NOTARY_PROFILE`, `NOT_STAPLED`, or `GATEKEEPER_REJECTED` to stderr —
never a credential, a profile's contents, or an app-specific password.

Full mode captures all build, signing, notarization, validation, test, and
launch output in a private temporary directory. The repository evidence
sanitizer redacts secret-bearing lines and local paths before atomically
publishing `--evidence-output`. Only that sanitized destination is suitable
for review or commit; raw temporary output is deleted and must not be copied.

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
