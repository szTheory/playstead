# Locked out? Recovering owner access without email

## Create an independent durable backup receipt

Choose a destination outside the canonical Playstead storage and on a
detectably different filesystem where possible. For example:

```bash
export PLAYSTEAD_BACKUP_HOST_PATH="$HOME/Downloads/PlaysteadBackup"
mkdir -p "$PLAYSTEAD_BACKUP_HOST_PATH"
```

Before running anything, ensure the directory is not a symlink, is not inside
the canonical blob storage, and is writable by the release image's
`nobody:nogroup` identity (UID/GID `65534:65534`). The wrapper first starts a
one-off unprivileged container that bypasses the normal entrypoint and only
inspects this mount. A same detectable filesystem is refused; if Docker cannot
detect the physical relationship, independence remains your explicit operator
attestation.

Run the first backup as a full set:

```bash
scripts/backup-live.sh --full
```

The only success criterion is `backup_published`, emitted after the durable
record is published with a verified receipt. A started job, copied directory,
or `backup_scheduled` is not a backup receipt. Retain the opaque receipt ID
from the published command output. Later incremental backups require that exact
published parent receipt; the wrapper never guesses a parent from time or disk
contents:

```bash
scripts/backup-live.sh --incremental --parent-receipt RECEIPT_ID
```

The wrapper runs Compose configuration and non-mutating preflight before it
recreates the `app` service alone. It never runs `down`, removes volumes,
recreates the database or proxy, or creates/chowns the destination. Do not put
the actual host destination into repository files, tickets, or command output.

Give Plan 05-13's retained restore procedure only the independently published
full receipt and its explicitly parent-linked incrementals. That procedure is
the next step for a verified restore; a receipt alone is not a known-playable
game proof.

## Service-data recovery after a failed upgrade

Use the recorded upgrade decision in [UPGRADE.md](UPGRADE.md). If the prior
application is not certified to read the upgraded schema, or database/blob
integrity is not green, recover both custody domains together into clean
isolated volumes with `scripts/recovery-proof.sh --restore --fixture` (CI
fixture) or the production restore wrapper. Never run a production Ecto down
migration and never restore only the database or only blobs.

## Retained isolated restore target

The disposable `scripts/recovery-proof.sh --restore --compose-fixture` drill is
not a backup-chain, game, BIOS, or known-playable proof. For a real incident or
recovery rehearsal, first select an independently stored, receipt-verified full
backup followed by each incremental backup in parent order. Do not use a
canonical project path, mount, or a previously used target directory.

Choose fresh absolute paths, then run:

```bash
mix playstead.restore --retain \
  --backup-set /absolute/independent-backups/full-set \
  --backup-set /absolute/independent-backups/incremental-set \
  --target-root /absolute/new/playstead-restore-target \
  --handoff-output /absolute/new/playstead-restore-target/server-handoff.json \
  --canonical-project playstead \
  --canonical-root /absolute/canonical/playstead-data
```

The command exits `0` only after the chain, preflight, database, CAS,
manifest, and authenticated API stages have written one verified receipt. It
exits `77` only when Docker Compose is unavailable before mutation. Any other
exit is a refusal or failed restore; retain nothing and inspect the bounded
receipt/error. A successful target has one fresh `playstead-restore-*` project,
one matching network, two matching data volumes, `restore-receipt.json`,
`caddy-root-ca.pem`, and mode-`0600` `server-handoff.json`.

The final output includes both forms below; copy one exactly rather than finding
an internal temporary path:

```bash
export PLAYSTEAD_RECOVERY_RESTORE_HANDOFF='/absolute/new/playstead-restore-target/server-handoff.json'
playstead-mac/scripts/ci/prove-recovery-known-playable.sh --prepare --fixture --no-human-observation
```

That prepares the existing clean-profile Mac procedure only. It supplies no
private ROM/BIOS material and cannot record in-game continuation: follow the
Plan 05-05 named-observer procedure after preparation, where `restore data
verified; known-playable proof pending` remains pending until the legal private
fixture has been observed continuing in-game.

After the proof, remove only that exact target with its matching handoff:

```bash
mix playstead.restore --cleanup \
  --target-root /absolute/new/playstead-restore-target \
  --handoff-output /absolute/new/playstead-restore-target/server-handoff.json
```

Cleanup rechecks the allowlisted handoff, receipt, correlation, project,
network, volumes, CA, ownership, and restrictive file modes before it asks
Compose to remove the exact target resources. Any ambiguity fails closed and
leaves resources and files intact.

Playstead never sends email (D-02). If you're locked out of the console, there are two
email-free ways back in.

## 1. The host command (works even if you've lost your password entirely)

If you have shell access to the machine running Playstead (which you do — you're
self-hosting it), run:

```
docker compose exec app bin/playstead eval 'Playstead.Release.reset_owner_password()'
```

This prints a single-use, short-lived reset URL to the terminal. Visiting it once lets
you set a new password; visiting it again (or after it expires) is rejected.

**Running this command immediately ends every existing browser session for the owner
account.** That's deliberate — if someone else had a live session, it dies the moment
you reset the password, so a stolen session can never run alongside a fresh reset.

Host access is the root of trust here — the same principle that governs the initial
setup token printed at first boot. Anyone with shell access to the container can already
read and modify everything the application can; a password reset command doesn't create
a new privilege, it just gives the legitimate operator an email-free way to use the
privilege they already have.

## 2. A recovery code

At setup, you were shown ten single-use recovery codes. If you saved them somewhere
safe, you can log in with one directly at `/log-in/recovery` instead of your password.
Each code works exactly once; once used (or if you regenerate the set from the console),
it's permanently spent.

Recovery-code submissions are rate-limited on the same fixed per-IP and per-account
limits as ordinary password login — there is no adaptive lockout, so a self-hoster can
never accidentally lock themselves out by trying a code a few times.

## If you have neither

If you never saved a recovery code and don't have shell access to the host, there is no
email-based fallback — that's the tradeoff of a private, email-free server. Host access
is the root of trust for both bootstrap and recovery; without it, or without a saved
recovery code, the account cannot be recovered.
