# Playstead for Mac

This is the implementation root for the native macOS reference client.

It owns pairing and Keychain credentials, catalogue browsing, selective verified caching, controller UX, emulator and BIOS adapters, launch preflight, offline operation, and persistent-save capture and recovery. SwiftUI is the default UI technology with targeted AppKit integration where the empirical Mac adapter spike required it.

The client depends only on the versioned HTTPS protocol and downloaded assets — not Phoenix LiveView internals or server implementation details.

## `Playstead.xcodeproj`

The shipping client. Separate from and does not reuse `spike/`, which stays as the throwaway probe harness from plan 03-01.

- App target `Playstead` (bundle id `dev.playstead.mac`, macOS 14.0 deployment target, SwiftUI lifecycle), plus a `PlaysteadTests` unit test target.
- **File-system-synchronized source group.** `Playstead/` (and `PlaysteadTests/`) are added to the project as an Xcode 16+ `PBXFileSystemSynchronizedRootGroup`, not a conventional `PBXGroup` of individually-listed `PBXFileReference`s. This is a deliberate, load-bearing setup choice: adding a new Swift source file to either target means writing it to disk under the matching directory — **no `project.pbxproj` edit required**. Four later plans in this phase land in two parallel waves and would otherwise all need to edit the same `project.pbxproj` concurrently, guaranteeing merge conflicts across worktrees. Xcode auto-includes every file under a synchronized root group in the target's build; there is no `PBXBuildFile`/`PBXSourcesBuildPhase` entry to add either.
- **No third-party Swift Package Manager dependency in this phase.** Local persistence uses the system `libsqlite3` through a small hand-written `SQLiteConnection` wrapper (prepare/bind/step/finalize plus a `transaction` helper) — see `Playstead/Persistence/`. This is the discretion CONTEXT.md grants for the persistence-library choice; the OS-provided library removes both the supply-chain verification burden and the nested-code-signing surface a bundled SPM package would add to notarization.
- **Signing.** Hardened runtime is enabled and the app is **not** App-Sandboxed (`com.apple.security.app-sandbox` = false in `Playstead/App/Playstead.entitlements`, per D-04 — sandbox would break launching a downloaded third-party emulator process). Local `xcodebuild build`/`test` invocations sign with the `Apple Development: REPLACE_WITH_YOUR_APPLE_ID (REPLACE_WITH_YOUR_CERT_ID)` identity, team `REPLACE_WITH_YOUR_TEAM_ID` — the same dev-signing posture plan 03-01's spike used. `scripts/build-release.sh` reads a Developer ID Application identity from the `PLAYSTEAD_DEV_ID_APP` environment variable for a distributable Release build; **notarization is deferred** per the 2026-08-30 owner decision recorded in `03-ADAPTER-PIN.json` (no paid Apple Developer Program membership yet) — `scripts/sign-and-notarize.sh` supports it unchanged once a notary keychain profile exists, but this plan does not attempt to run it.

## Cache layout

`AppPaths` centralises the cache root at `~/Library/Application Support/Playstead/` (excluded from Time Machine/iCloud backup on first creation) — never `~/Library/Caches/`, which the OS may purge and would break the pinned-offline promise (D-20). Subdirectories: `objects/<aa>/<bb>/<sha256>` (content-addressed cache), `partials/` (in-progress downloads), `launch/<asset_set_id>/` (materialized launch directories, clone/copy only — never a hard link into `objects/`), `emulators/<name>/<version>/` (downloaded, hash-verified adapter binaries, quarantine attribute always left intact). The SQLite mirror lives at `playstead.sqlite3` in the same root.

## Building

```sh
cd playstead-mac
xcodebuild build -scheme Playstead -destination 'platform=macOS'
xcodebuild test -scheme Playstead -destination 'platform=macOS'
```
