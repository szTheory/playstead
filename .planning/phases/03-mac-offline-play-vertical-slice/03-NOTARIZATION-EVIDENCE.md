# Notarization Evidence — PLAY-05

Verbatim tool output from a real, complete run of
`playstead-mac/scripts/verify-notarized-release.sh` against a genuinely
Developer-ID-signed, Apple-notarized `Playstead.app`. Nothing below is
hand-written, paraphrased, simulated, or replayed — every fenced block is
copied directly from the command's own stdout/stderr.

**Run date:** 2026-09-11 (UTC) / 2026-09-10 22:26–22:27 local (America/New_York)
**macOS build tested:** 26.6.2 (25G83) — matches `docs/SUPPORT-MATRIX.md`
**Xcode version:** Xcode 26.6, Build version 17F113
**Team:** `6CH9Y797RU` (Apple Developer Program, Individual — Johnathan Bryan)
**Certificate:** Developer ID Application: Johnathan Bryan (6CH9Y797RU)
**Notarization submission ID:** `8465f74d-5468-4b73-9885-fb0ea1dafcdd`

## Sanitization note

`scripts/ci/sanitize-evidence.sh` is built around this repo's fixed
`evidence/` directory layout (`environment-fingerprint.json`, `*-tests.json`,
snapshot triplets, etc.) and does not accept a single freeform transcript as
input — its `--input ROOT --output DIRECTORY` contract requires that
directory shape. Its sanitization *policy* was applied by hand instead: every
absolute local filesystem path (`/Users/...`, `/private/...`, `/var/folders/...`)
below has been replaced with `[PATH]` or a repo-relative path, and every
block was reviewed against the sensitive-key/credential vocabulary the
sanitizer enforces (`authorization`, `bearer`, `token`, `password`,
`api_key`, `secret`, `.keychain`, credential URLs). None of these scripts
ever print `PLAYSTEAD_NOTARY_PROFILE`'s stored credentials or an
app-specific password — the notary keychain profile is referenced only by
name (`playstead-notary`) throughout, per its design.

## 1. notarytool submit --wait (embedded in `sign-and-notarize.sh`, via `verify-notarized-release.sh`)

```
==> Creating submission archive for notarytool
==> Submitting for notarization (profile: playstead-notary)
Conducting pre-submission checks for playstead-notarize-Iz4ZQc.zip and initiating connection to the Apple notary service...
Submission ID received
  id: 8465f74d-5468-4b73-9885-fb0ea1dafcdd
Successfully uploaded file
  id: 8465f74d-5468-4b73-9885-fb0ea1dafcdd
  path: [PATH]/playstead-notarize-Iz4ZQc.zip
Waiting for processing to complete.
Current status: In Progress...Current status: In Progress....Current status: Accepted.....Processing complete
  id: 8465f74d-5468-4b73-9885-fb0ea1dafcdd
  status: Accepted
```

## 2. notarytool info (post-hoc confirmation)

```
Successfully received submission info
  createdDate: 2026-09-11T02:26:41.984Z
  id: 8465f74d-5468-4b73-9885-fb0ea1dafcdd
  name: playstead-notarize-Iz4ZQc.zip
  status: Accepted
```

## 3. notarytool log (full notary service log)

```json
{
  "logFormatVersion": 1,
  "jobId": "8465f74d-5468-4b73-9885-fb0ea1dafcdd",
  "status": "Accepted",
  "statusSummary": "Ready for distribution",
  "statusCode": 0,
  "archiveFilename": "playstead-notarize-Iz4ZQc.zip",
  "uploadDate": "2026-09-11T02:26:43.376Z",
  "sha256": "9ccd0dcfce39dce7640503b2bfd3eec76ed2dd760e3448a2c8bdb040006e5009",
  "ticketContents": [
    {
      "path": "playstead-notarize-Iz4ZQc.zip/Playstead.app",
      "digestAlgorithm": "SHA-256",
      "cdhash": "b8b9f5b3ec3a4e86e48034e5c31415d2e3aa01fc",
      "arch": "x86_64"
    },
    {
      "path": "playstead-notarize-Iz4ZQc.zip/Playstead.app",
      "digestAlgorithm": "SHA-256",
      "cdhash": "5c82cffecb2f6e7356a6a00d1af98807664420df",
      "arch": "arm64"
    },
    {
      "path": "playstead-notarize-Iz4ZQc.zip/Playstead.app/Contents/MacOS/Playstead",
      "digestAlgorithm": "SHA-256",
      "cdhash": "b8b9f5b3ec3a4e86e48034e5c31415d2e3aa01fc",
      "arch": "x86_64"
    },
    {
      "path": "playstead-notarize-Iz4ZQc.zip/Playstead.app/Contents/MacOS/Playstead",
      "digestAlgorithm": "SHA-256",
      "cdhash": "5c82cffecb2f6e7356a6a00d1af98807664420df",
      "arch": "arm64"
    }
  ],
  "issues": null
}
```

## 4. Stapling (`xcrun stapler staple` and `xcrun stapler validate`)

```
==> Stapling notarization ticket
Processing: [PATH]/build/Release/Playstead.app
Processing: [PATH]/build/Release/Playstead.app
The staple and validate action worked!
```

Independent re-validation after the run completed:

```
=== stapler validate ===
Processing: [PATH]/build/Release/Playstead.app
The validate action worked!
```

## 5. Gatekeeper assessment (`spctl --assess --type execute --verbose`)

From inside `verify-notarized-release.sh`, immediately after stapling:

```
==> Asserting Gatekeeper acceptance
[PATH]/build/Release/Playstead.app: accepted
source=Notarized Developer ID
```

And again as the script's own independent re-assertion step:

```
==> Re-asserting Gatekeeper acceptance names a notarized source
[PATH]/build/Release/Playstead.app: accepted
source=Notarized Developer ID
```

And a third, fully independent invocation run after the script exited:

```
=== spctl assess ===
build/Release/Playstead.app: accepted
source=Notarized Developer ID
```

`source=Notarized Developer ID` is the exact string strict mode in
`sign-and-notarize.sh` requires (`grep -q 'source=Notarized Developer ID'`)
— a locally-signed, non-notarized build cannot produce this line.

## 6. Code signature detail (`codesign -dvvv --deep --strict`)

```
=== codesign -dvvv ===
Executable=[PATH]/build/Release/Playstead.app/Contents/MacOS/Playstead
Identifier=dev.playstead.mac
Format=app bundle with Mach-O universal (x86_64 arm64)
CodeDirectory v=20500 size=3997 flags=0x10000(runtime) hashes=114+7 location=embedded
Hash type=sha256 size=32
CandidateCDHash sha256=5c82cffecb2f6e7356a6a00d1af98807664420df
CandidateCDHashFull sha256=5c82cffecb2f6e7356a6a00d1af98807664420df55a4d4dfb57210082b22e82d
Hash choices=sha256
CMSDigest=5c82cffecb2f6e7356a6a00d1af98807664420df55a4d4dfb57210082b22e82d
CMSDigestType=2
CDHash=5c82cffecb2f6e7356a6a00d1af98807664420df
Signature size=9049
Authority=Developer ID Application: Johnathan Bryan (6CH9Y797RU)
Authority=Developer ID Certification Authority
Authority=Apple Root CA
Timestamp=Sep 10, 2026 at 10:26:40 PM
Notarization Ticket=stapled
Info.plist entries=20
TeamIdentifier=6CH9Y797RU
Runtime Version=26.5.0
Sealed Resources version=2 rules=13 files=1
Internal requirements count=1 size=212
```

This confirms all four PLAY-05 conditions on one artifact: a Developer ID
Application signature (`Authority=Developer ID Application: ...`), the
hardened runtime flag (`flags=0x10000(runtime)`), and `Notarization
Ticket=stapled`.

## 7. RelaunchTests against the notarized, exported artifact

```
Test Suite 'Selected tests' started at 2026-09-10 22:27:32.090.
Test Suite 'PlaysteadTests.xctest' started at 2026-09-10 22:27:32.091.
Test Suite 'RelaunchTests' started at 2026-09-10 22:27:32.091.
Test Case '-[PlaysteadTests.RelaunchTests testPreviouslyLaunchableGameStillEvaluatesLaunchableAfterClosingAndReopeningEveryStoreWithNetworkStubbedToFail]' started.
Test Case '-[PlaysteadTests.RelaunchTests testPreviouslyLaunchableGameStillEvaluatesLaunchableAfterClosingAndReopeningEveryStoreWithNetworkStubbedToFail]' passed (0.047 seconds).
Test Case '-[PlaysteadTests.RelaunchTests testRegisteredAdapterProcessIsTerminatedWhenApplicationTerminationHandlerRuns]' started.
Test Case '-[PlaysteadTests.RelaunchTests testRegisteredAdapterProcessIsTerminatedWhenApplicationTerminationHandlerRuns]' passed (0.054 seconds).
Test Suite 'RelaunchTests' passed at 2026-09-10 22:27:32.193.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.101 (0.102) seconds
Test Suite 'PlaysteadTests.xctest' passed at 2026-09-10 22:27:32.193.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.101 (0.102) seconds
Test Suite 'Selected tests' passed at 2026-09-10 22:27:32.193.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.101 (0.103) seconds

** TEST SUCCEEDED **
```

Both `RelaunchTests` methods that exist in
`playstead-mac/PlaysteadTests/AdapterTests/RelaunchTests.swift` ran and
passed — this is the full class, not a partial match (see Deviations in
`03-12-SUMMARY.md` for why the `-only-testing` identifier had to be
corrected first).

## 8. Launch / exit / relaunch against the exported, notarized `.app`

`verify-notarized-release.sh` opens the notarized app, confirms via `pgrep`
that its process exists, quits it via `osascript`, confirms via `pgrep`
that the process is gone, reopens it, and confirms via `pgrep` a second
time — each of the three checks would print one of `FATAL: notarized app
failed to launch`, `FATAL: notarized app failed to exit cleanly`, or
`FATAL: notarized app failed to relaunch` to stderr and exit non-zero if it
failed. No such line appears anywhere in the run's stderr, and the script's
final line only prints on the success path:

```
==> Launching the exported, notarized app to confirm clean exit and relaunch
==> Done: [PATH]/build/Release/Playstead.app is signed, notarized, stapled, Gatekeeper-accepted, and relaunch-proven.
```

## 9. Overall script exit status

`scripts/verify-notarized-release.sh` (`set -euo pipefail`) ran to its final
`echo` line with no `FATAL:` token anywhere in its combined stdout/stderr
and exited 0. `scripts/ci/tests/notarization-preflight-test.sh` was
re-verified immediately afterward and still passes both directions:

```
ASSERT: verify-notarized-release.sh exists and is executable
ASSERT: preflight exits non-zero with no Developer ID identity available
ASSERT: refusal stderr names NO_DEVELOPER_ID_IDENTITY
ASSERT: preflight exits 0 with a stubbed Developer ID identity and credential profile
notarization-preflight-test: 4 assertions ran
PASS: preflight refuses to certify an unnotarized build
```

The full `PlaysteadTests`/`PlaysteadUITests` suite (629 tests) was also
re-run in full after the script edits described in `03-12-SUMMARY.md`'s
Deviations section, to confirm nothing else regressed:

```
	 Executed 629 tests, with 0 failures (0 unexpected) in 69.764 (69.943) seconds
** TEST SUCCEEDED **
```
