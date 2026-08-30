# Playstead Mac Adapter Spike (D-01)

**This is a throwaway probe harness. It is NOT the shipping Playstead Mac client.**
The real SwiftUI/AppKit client is created in plan `03-03` after this spike pins an
adapter. Nothing here is reused as production code — only the *evidence* it produces
(`03-SPIKE-REPORT.md`, `03-ADAPTER-PIN.json`) carries forward.

## What this proves

Seven pass/fail probes (D-01) that documentation alone cannot answer:

1. Notarized/signed launch acceptance (Gatekeeper)
2. Config injection (save dir, BIOS path, controller mapping) into the shipped
   `mGBA.app` Qt binary
3. Save-flush observability, including `kill -9` behavior (D-03 owner ruling)
4. Exit detection/recovery (clean quit / crash / force-kill)
5. Controller unplug/reconnect recovery
6. Keychain access from a hardened-runtime, non-sandboxed build
7. BIOS-less (HLE) launch and operator-supplied BIOS drag-in launch

## Notarization posture for this run (2026-08-30 owner decision)

This Playstead installation is **not enrolled in the paid Apple Developer Program**.
There is no Developer ID Application certificate and no notarytool credential
profile. The owner explicitly decided to **defer notarization** and dev-sign the
spike instead, using the free development identity already present in the login
keychain:

- Signing identity: `Apple Development: REPLACE_WITH_YOUR_APPLE_ID (REPLACE_WITH_YOUR_CERT_ID)`
- Team ID: `REPLACE_WITH_YOUR_TEAM_ID`

Probes 1 and 6 as originally specified require *notarized* Developer ID evidence.
Under this decision they are recorded in `03-SPIKE-REPORT.md` and
`03-ADAPTER-PIN.json` with an explicit **`deferred`** status (never `pass`), with a
dev-signed analogue run and labeled as such where one exists. See
`03-SPIKE-REPORT.md` for the exact evidence and the revisit trigger (plan `03-10`'s
notarized build).

`scripts/sign-and-notarize.sh` runs the full notarytool submit/staple/spctl path
unchanged whenever `PLAYSTEAD_NOTARY_PROFILE` is set in the environment — so this
spike is forward-compatible with a future paid-membership run without a rewrite.

## Layout

- `SpikeHost/` — the probe host: a real signed, hardened-runtime, non-sandboxed
  Swift Package executable macOS app (`.app` bundle assembled by
  `scripts/sign-and-notarize.sh`, not an Xcode project — see
  `03-01-SUMMARY.md` deviations for why). Every probe is driven by a CLI
  subcommand (`environment`, `keychain-store`, `keychain-read`, `launch`,
  `launch-and-kill9`, `launch-and-segv`) so scripts can automate it end-to-end;
  with no subcommand it shows a minimal SwiftUI window.
- `scripts/acquire-emulator.sh` — downloads, hash-verifies, and installs a
  candidate emulator into the app-managed emulators directory, leaving the
  quarantine xattr intact.
- `scripts/sign-and-notarize.sh` — builds, bundles, signs (and notarizes when a
  profile is configured) SpikeHost.
- `scripts/run-probes.sh` — orchestrates probes 2-7 against the pinned
  candidate.
- `scripts/watch-save.sh` — polls a save file's size/mtime/sha256 into a JSONL
  timeline (probe 3, D-03).
- `out/` — every probe's evidence file (`probe-NN.json`, `environment.json`,
  `exit-events.jsonl`, `save-timeline.jsonl`). Git-ignored; regenerated per run.

## BIOS posture

No probe, script, or document in this directory provides, locates, or links a
path to acquire a proprietary BIOS image. Probe 7 requires the operator to
supply their own `gba_bios.bin` as a local path argument; only its byte length
and SHA-256 are ever recorded.

## Running the spike end-to-end

```bash
export PLAYSTEAD_DEV_ID_APP="Apple Development: REPLACE_WITH_YOUR_APPLE_ID (REPLACE_WITH_YOUR_CERT_ID)"
export PLAYSTEAD_TEAM_ID="REPLACE_WITH_YOUR_TEAM_ID"
# PLAYSTEAD_NOTARY_PROFILE intentionally left unset — notarization deferred.

cd playstead-mac/spike
./scripts/sign-and-notarize.sh
./scripts/acquire-emulator.sh mgba 0.10.5
./scripts/run-probes.sh 2 3 4 7
./scripts/run-probes.sh 5
```

Results land in `out/probe-01.json` through `out/probe-07.json`, then get
synthesized into `../../.planning/phases/03-mac-offline-play-vertical-slice/03-SPIKE-REPORT.md`
and `03-ADAPTER-PIN.json`.
