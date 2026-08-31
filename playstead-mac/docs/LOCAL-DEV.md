# Running Playstead locally, end to end

This is the clean-machine-to-launched-game path for running Playstead on your
own Mac. It covers the server, importing ROMs, pairing this Mac to the server,
building and running the app, installing the emulator adapter, and playing.

Every command here was verified against the source. Where something has **not**
been proven end to end in a real run, it says so explicitly — see
[What is still unproven](#what-is-still-unproven) before you assume a step will
work first try.

---

## 0. Prerequisites

| Need | Why |
|---|---|
| macOS 14.0+ | `MACOSX_DEPLOYMENT_TARGET = 14.0` |
| Xcode (with Command Line Tools) | building the Mac app; also supplies `swift`, `xcodebuild` |
| Elixir 1.19.5 / Erlang 28.4.1 | `playstead-server/.tool-versions` (mix.exs only requires `~> 1.17`) |
| A local PostgreSQL you can reach on `localhost:5432` | the dev server expects one; see below |
| `curl`, `python3` | used by `scripts/pair-dev.sh` |

---

## 1. Start the server

There are two paths. **For local development, use the native `mix` path.**

### Why the `mix` path (recommended)

- **No secrets to generate.** `config/dev.exs` hardcodes `secret_key_base`, and
  every "you must set a real secret" guard in `lib/playstead/application.ex` and
  `config/runtime.exs` is behind `if config_env() == :prod`. The Docker path
  requires you to generate and paste a `SECRET_KEY_BASE` and a
  `POSTGRES_PASSWORD` into `.env` before anything boots.
- **Plain HTTP on loopback, so no TLS trust setup.** Dev binds
  `http://127.0.0.1:4000` (`config/dev.exs` sets `http: [ip: {127,0,0,1}]`;
  `config/runtime.exs` sets the port from `PORT`, default `4000`). The Docker
  path fronts everything with Caddy using its *internal* CA, whose root your Mac
  does not trust — `curl` and the Mac app both reject that certificate until you
  install the root into the System keychain. See
  [A note on TLS](#a-note-on-tls).
- **Code reloading**, `/dev/dashboard`, and readable stack traces.

Use the Docker path (`playstead-server/docs/DEPLOY.md`) when you want to
rehearse a *real deployment* — it is the production topology (postgres 17.2 +
app + caddy, named volumes, TLS). It is the wrong tool for iterating on code.

### Commands

```sh
cd playstead-server

# One time. Creates the DB, migrates, and installs the esbuild/tailwind
# binaries (this first run needs network access).
mix setup

# The inbox/export paths default to the *container* paths /app/inbox and
# /app/exports even in dev, which do not exist on a Mac. Point them at real
# local directories or the import UI will silently show an empty folder.
mkdir -p inbox exports
export PLAYSTEAD_INBOX_PATH="$PWD/inbox"
export PLAYSTEAD_EXPORT_PATH="$PWD/exports"

mix phx.server
```

The server is up when `curl http://127.0.0.1:4000/healthz` returns
`{"status":"ok"}`.

> **Postgres is not provided for you.** `docker-compose.yml` defines a `db`
> service only on the internal compose network with no published port, so it
> does not serve the dev path. Bring your own local Postgres reachable as
> `postgres`/`postgres` @ `localhost:5432`.

### Create the owner account

On first boot, `Playstead.Setup.mint_token/0` prints an unmissable banner to the
`mix phx.server` terminal:

```
============================================================
Playstead setup token (use once, in the setup wizard at /setup):

<token>

============================================================
```

Copy that token, open <http://localhost:4000/setup>, and walk the four-step
wizard: setup token → owner credentials → recovery codes (**shown once — save
them**) → readiness summary. `Finish setup` redirects you to `/log-in`.

Two things that will confuse you:

- **The banner only prints when no owner exists yet.** If an owner already
  exists, `mint_token/0` is a no-op and `/setup` returns a permanent **404**
  (by design — `RequireSetupOpen`). To start over:
  `mix ecto.reset`, then restart the server.
- You can skip the banner entirely by exporting `PLAYSTEAD_SETUP_TOKEN=...`
  before starting the server; that value is adopted silently and never printed.

---

## 2. Import ROMs

1. **Put files in the inbox.** Copy ROMs into the directory you set as
   `PLAYSTEAD_INBOX_PATH` (above, `playstead-server/inbox/`). Under Docker this
   is `./inbox`, mounted read-only at `/app/inbox`.

2. **Stage them.** Go to <http://localhost:4000/import/sessions>, click
   **Preview inbox folder**. You get a readout like
   `12 files, 4194304 bytes` / `10 recognized, 1 unknown, 1 archives`. The
   **Stage this folder** button only appears *after* the preview renders.

### ⚠️ Archives are kept opaque and are NOT playable

**Unzip your ROMs before importing them.** A `.zip`, `.7z`, or `.rar` is
imported as an opaque blob and cannot be launched.

This is deliberate, not a bug. `Playstead.Formats.Archive` detects archives by
**magic bytes, never by file extension**, and stops the instant a signature
matches — *"nothing is listed, no central directory is read, no byte is
decompressed."* `Playstead.Formats` then short-circuits:

```elixir
case Archive.detect(bounded) do
  {:match, kind} -> {:unknown, :container, %{archive_kind: kind, reason: :archive_not_opened}}
  :no_match      -> identify_rom(bounded, filename)
end
```

Detected kinds: zip, 7z, rar, gzip, xz, zstd. These land in **`/attention`**
under the heading **Archives kept unopened**, which tells you:

> "An archive was kept exactly as it is. It can't be played until archive
> support ships — extracting it first makes it playable."

Your only options there are `Retain as custom` or `Exclude`. Extract the archive
outside Playstead and re-import the bare ROM.

### Supported systems

From `Playstead.Formats.SystemId` — a frozen, closed registry (D-14):

```
gba  gb  gbc  nes  snes  md  psx  unknown
```

That is seven systems plus `unknown`. **Only GBA has a shipping adapter**, so
GBA is the only thing you can actually play today (see step 5).

### Related pages

- **`/reference-packs`** — DAT-based identification. Load a reference pack to
  get titles and confident matches instead of raw filenames.
  (Note: this is a top-level route. It is *not* `/library/reference-packs`.)
- **`/attention`** — everything unresolved: archives kept unopened, unknown
  files, anything needing a decision from you.

---

## 3. Pair this Mac to the server

The Mac app does not yet ship a pairing UI — `KeychainStore.storeCredential`
has no in-app caller. Until it does, use the dev script, which performs exactly
the ceremony the server implements and writes the credential where the app
reads it.

```sh
cd playstead-mac
./scripts/pair-dev.sh --server http://127.0.0.1:4000 --label "My Mac"
```

Both flags are optional; the server defaults to `http://127.0.0.1:4000` and the
label to this Mac's name.

The script prints a pairing code and waits:

```
  ┌──────────────────────────────────────────────┐
     Pairing code:  BHLL-NDXP
  └──────────────────────────────────────────────┘
```

**What you do, in the browser:** log in, go to <http://localhost:4000/devices>.
Under **Pairing requests** you will see a card showing that same code in large
type, with the hint *"Only approve if this code matches the one on your Mac's
screen."* Check that it matches what the script printed, then click **Approve**.
(The other button is **Deny**.) You have ~10 minutes; the card shows a live
`Expires in …` countdown.

The script then redeems the request and writes the credential to your login
Keychain, and finishes with:

```
Authenticated request to /api/v1/devices/me returned HTTP 200.
Done. Launch the Playstead app; it will find this credential in the Keychain.
```

Notes:

- **The credential is never printed.** Only the display code is.
- **Re-running is safe.** Each run pairs a *new* device with a new
  `device_id`, so the script purges every existing item on the
  `dev.playstead.mac` service before writing. This matters:
  `KeychainStore.loadCredential()` queries by service alone with
  `kSecMatchLimitOne` and no account predicate, so a leftover item from an
  earlier pairing could otherwise be picked instead of the current one. Old
  devices stay listed at `/devices` until you revoke them there.
- The item is written with `security add-generic-password -A`, meaning any
  application may read it without an ACL prompt. **That is a development
  convenience and not how the shipping app should store a credential.** If
  macOS does prompt when the app first reads it, choose **Always Allow**.

<details>
<summary>What the script writes, exactly</summary>

A `kSecClassGenericPassword` item matching `KeychainStore.loadCredential()`'s query:

| Attribute | Value |
|---|---|
| service (`svce`) | `dev.playstead.mac` |
| account (`acct`) | the server-issued `device_id` |
| password data | the bearer credential |
| generic (`gena`) | `{"baseURL": "http://127.0.0.1:4000"}` — decoded as `CredentialEnvelope` |

</details>

### A note on TLS

`APIClient` uses the platform's **default** trust evaluation unless
`AppPaths.root/pinned-ca.der` exists, and nothing currently writes that file.
So:

- **`http://127.0.0.1:4000` (the `mix` path) just works.** `Info.plist` already
  carries an App Transport Security exception for `localhost` and `127.0.0.1`
  (`NSExceptionAllowsInsecureHTTPLoads`, `NSIncludesSubdomains` false), so
  plain-HTTP loopback is permitted. **This is the supported local path and the
  script's default.**
- **The Docker/Caddy path will fail** at the first request until you export
  Caddy's internal CA root and add it to your System keychain as trusted —
  the app has no pinned certificate to fall back on and the default evaluator
  will reject it.

Use loopback HTTP locally. Certificate pinning is a later phase's job.

---

## 4. Build and run the Mac app

```sh
cd playstead-mac
xcodebuild build -scheme Playstead -destination 'platform=macOS'
xcodebuild test  -scheme Playstead -destination 'platform=macOS'
```

Or just open `Playstead.xcodeproj` in Xcode and hit Run. (`Playstead` is
Xcode's autocreated implicit scheme — there is no checked-in `.xcscheme`, so
the scheme appears on first open.)

**You do not need notarization.** Notarization and stapling are *distribution*
concerns — they matter when someone else downloads your `.dmg` and Gatekeeper
checks it. A build you compile and run on your own machine, signed with your
local `Apple Development` identity (`CODE_SIGN_STYLE = Automatic`), runs
without any of it. `docs/RELEASE.md` covers the signing/notarization path for
when you actually ship; ignore it for now.

---

## 5. Install the emulator adapter

Playstead does not bundle an emulator. It downloads a **pinned** release and
verifies it against a recorded digest.

In the app, either:

- click **Adapter** in the library toolbar, or
- hit **Play** on a title that is blocked, then **What's needed** → the adapter
  remedy.

You will see a capability card for **GBA** naming the emulator and version, its
digest, what it accepts, and its BIOS/save posture. Click **Install the pinned
adapter** (it reads **Reinstall the pinned adapter** once installed). The other
button, **Choose an installed application…**, opens a file picker if you already
have a copy on disk.

What happens under the hood (`AdapterInstaller`): downloads the DMG, hashes it
and compares to the pin **before** expanding anything, then `hdiutil attach
-nobrowse -readonly`, `ditto` the `.app` into
`~/Library/Application Support/Playstead/emulators/<emulator>/<version>/`, then
`hdiutil detach`. The quarantine xattr is deliberately preserved. If the digest
does not match you get:

> "The downloaded file did not match the pinned release. Expected …, got ….
> Nothing was installed."

The pin lives in `Playstead/Adapter/AdapterPin.json`:

| Field | Value |
|---|---|
| emulator / system | `mgba` / `gba` |
| version | `0.10.5` |
| download URL | `https://github.com/mgba-emu/mgba/releases/download/0.10.5/mGBA-0.10.5-macos.dmg` |
| sha256 | `443b490ec728293dfcde1cb9db160f73d94c457cb1864f3ce0407e60e174b09c` |

This step needs network access to GitHub. See
[What is still unproven](#what-is-still-unproven).

---

## 6. Download and play

Pick a GBA title in the library and press **Play**.

Play is gated by `ReadinessEngine`, which runs six checks and disables the
button unless every one passes (`Play` carries the accessibility label *"Play
is unavailable until every readiness check passes."*). When it is blocked,
**What's needed** opens a report listing each failing check with a remedy
button:

| Check | When it blocks | Remedy button |
|---|---|---|
| `gameAssets` | required files not downloaded yet | **Download missing files** |
| `cacheVerification` | a local copy didn't match what was expected (replaced automatically) | **Redownload the affected file** |
| `emulator` | adapter not installed / files missing / digest mismatch | **Install adapter** |
| `bios` | adapter requires a BIOS that hasn't been validated — **not applicable to GBA**, where `biosRequired == false` | **Drop in a BIOS file** |
| `controllerAndInput` | no controller or keyboard available | **Open input settings** |
| `saveDirectory` | Playstead can't write to its save directory | **Repair save directory** |

Rows sort blocked-first. Work top-down until Play enables.

> Do not confuse this with the **server's** readiness (`Playstead.Readiness`:
> database, volumes, https, inbox, exports, blob volume atomicity), which is what
> the `/setup` wizard's last step and the server console show.

---

## What is still unproven

Be skeptical of these; they are the places reality is most likely to diverge
from what the test suite asserts.

1. **The pinned mGBA DMG has never actually been downloaded in this
   environment.** Installs were exercised against a *stubbed* archive. The URL
   and digest above are what the code will use, but the real download →
   digest-check → `hdiutil` → `ditto` sequence has not run against the genuine
   0.10.5 DMG. If the digest mismatches, the release asset changed and the pin
   needs updating — do not work around it by disabling the check.
2. **No real ROM has ever been launched.** `/bin/echo` stood in for the
   emulator in every test. The process-launch plumbing is tested; mGBA actually
   starting, finding the ROM, and writing a save to the expected directory is
   not.
3. **`BiosStore` has no production reference digests.** Harmless for GBA
   (`biosRequired == false`, so the `bios` check never blocks), but any system
   that needs a BIOS will not validate one today.
4. **Controller behavior is unproven on real hardware.** The
   `controllerAndInput` check and the input path have not been exercised with a
   physical controller.
5. **Pairing UI does not exist in the app.** Step 3's script is the only way to
   pair. It has been run end to end against a live dev server (request →
   approve → redeem → Keychain write → authenticated `GET /api/v1/devices/me`
   returning 200), including a re-run to confirm it replaces rather than
   duplicates the credential.
6. **The native `mix` dev path is not documented upstream.**
   `playstead-server/README.md` is a stub; everything in step 1 was derived from
   `config/dev.exs`, `config/runtime.exs`, and `mix.exs` and then verified by
   actually booting the server.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `pair-dev.sh`: "Could not reach the server" | Server not running, or wrong `--server`. Check `curl http://127.0.0.1:4000/healthz`. |
| `pair-dev.sh`: "expired before it was approved" | 10-minute limit elapsed. Just re-run it. |
| `pair-dev.sh`: "the owner denied this pairing request" | You clicked **Deny** at `/devices`. Re-run. |
| `pair-dev.sh`: "Could not write the credential to the login Keychain" | Login keychain locked (`security unlock-keychain`), or an access dialog was dismissed. The device *is* paired server-side — revoke it at `/devices` before re-running. |
| Authenticated request returns 401 | Device was revoked at `/devices`. Re-pair. |
| `/setup` returns 404 | An owner already exists. `mix ecto.reset` to start over. |
| "Preview inbox folder" shows `0 files, 0 bytes` | `PLAYSTEAD_INBOX_PATH` unset, so it defaults to the container path `/app/inbox`. Export it and restart the server. |
| App can't reach the server over https | Expected — see [A note on TLS](#a-note-on-tls). Use loopback HTTP. |
| A ROM imported but won't play | It is probably an archive. Check `/attention` → **Archives kept unopened**. Extract it and re-import. |
