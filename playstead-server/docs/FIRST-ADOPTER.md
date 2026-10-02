# First-adopter local server

This profile is for the owner's personal first-use library. It is isolated from
the default `playstead` deployment and the `playstead-dev` and recovery stacks.
It has the fixed Compose project `playstead-first-adopter`, separate named
volumes, a private environment file, distinct host inbox/export/backup
directories, and explicitly selected ports and LAN bind address.

The first-adopter trial runs the server, web console, and Mac app on one
personal Mac. A second device is optional future coverage, not a prerequisite.
This trial does not prove that the collection is safe as its only copy. Keep
the original ROMs and another copy of anything important while using Playstead.
A local backup can support basic use, but a backup receipt does not prove that
a clean restore has succeeded. A backup on the same physical disk is not an
independent backup.

## Automated private setup

The tracked example contains placeholders only. Do not put personal ROM names,
host paths, LAN addresses, hashes, credentials, BIOS details, or CA fingerprints
in the repository. The initializer writes the env file to
~/.config/playstead/first-adopter/first-adopter.env and creates a new data root
at ~/Playstead-First-Adopter by default. Both locations are outside the
checkout; the env file and directories are restricted to the current account.

From playstead-server, run:

    scripts/first-adopter-init.sh

The initializer generates separate database, app, and setup secrets; keeps the
database URL password synchronized; discovers a private LAN IPv4 address; and
creates distinct inbox, exports, and backups directories. It never prints
owner-specific paths or secret values and never invokes Docker. If more than
one private IPv4 address is present, select one explicitly:

    scripts/first-adopter-init.sh --lan-address 192.168.1.20

Replace that example with the address selected on the server Mac. The script
validates that it is currently assigned. If the default data root already
exists, initialization stops to avoid reusing existing personal or QA data.
Choose a new, empty data root and config path for a deliberate fresh setup;
do not delete or reuse an existing root as a workaround.

You can change the private config and data locations while initializing:

    scripts/first-adopter-init.sh --config "$HOME/.config/playstead/first-adopter/first-adopter.env" --data-root "$HOME/Playstead-First-Adopter"

The environment variable PLAYSTEAD_FIRST_ADOPTER_ENV_FILE changes the default
config path for all three first-adopter commands. The initial setup command
prints only a generic success message; it does not expose the selected address.
Reserve that address in the router's DHCP settings if possible. The
192.0.2.10 value in the tracked example is TEST-NET documentation space, not a
real server address.

The example uses host ports 8080 and 8443 so it can coexist with QA stacks
that use 80 and 443. Caddy listens on those same ports in the container, so its
HTTP-to-HTTPS redirect points to :8443. The profile binds both published ports
only to the configured LAN address. It does not bind all interfaces or require
public DNS, router port forwarding, or Tailscale.

## Automated configuration QA and start

From playstead-server, run the redacted static configuration QA:

    scripts/first-adopter-qa.sh config

This mode validates the private env and resolves the fixed
playstead-first-adopter Compose project without requiring running services.
It checks distinct external mounts and LAN-only port binding. It does not
establish that Docker resources are running, that HTTPS is trusted, or that
the application is ready.

Then run the existing, read-only deployment preflight:

    scripts/first-adopter-compose.sh preflight

That checks the selected LAN address, port availability, Docker daemon,
resource identity, and mount isolation. Both reports redact owner-specific
values. Resolve a conflict manually; never remove or prune QA/recovery
resources to make preflight pass.

Only after both preflights pass, the owner can start the personal project:

    scripts/first-adopter-compose.sh up
    scripts/first-adopter-compose.sh ps

up targets only the fixed first-adopter project and is intended for initial
start or after stopping this profile. It fails closed if either requested host
port is occupied, including when this profile is already running. Use ps and
logs while it is running. To stop only this profile while preserving volumes:

    scripts/first-adopter-compose.sh down

There is deliberately no down -v, prune, or cross-project cleanup command in
this entrypoint. Do not substitute commands that remove volumes.

### Claim the owner account (once)

Open `https://<server-LAN-IPv4>:8443/setup` on this Mac. Paste the one-time
`PLAYSTEAD_SETUP_TOKEN` from the private file at
`~/.config/playstead/first-adopter/first-adopter.env`, continue, and create the
owner account. Keep the token and account credentials on this Mac; do not paste
them into chat or add them to Git. The guarded `scripts/first-adopter-compose.sh
logs` command intentionally redacts setup-token log lines.

## HTTPS on the server Mac

The simplest private-LAN option is Caddy's internal CA. Caddy serves IP
addresses with a locally issued certificate; the profile leaves
`PLAYSTEAD_DOMAIN` empty so Playstead identifies the transport as its internal
CA and can show the CA fingerprint for native pairing. Caddy stores its unique
CA under this project's own `caddy_data` volume. The CA root is public
certificate material; its private signing key stays in that volume.

Use the explicit URL `https://<server-LAN-IPv4>:8443` from the same Mac. After
Caddy has started and created its CA, export the public root certificate to a
file outside the repository on that Mac:

```sh
scripts/first-adopter-compose.sh root-ca "$HOME/Playstead-First-Adopter/caddy-root.crt"
openssl x509 -in "$HOME/Playstead-First-Adopter/caddy-root.crt" -noout -fingerprint -sha256
```

Trust the root certificate for SSL in this Mac's login Keychain before entering
setup, account, or pairing credentials:

```sh
security add-trusted-cert -r trustRoot -p ssl -k "$HOME/Library/Keychains/login.keychain-db" "$HOME/Playstead-First-Adopter/caddy-root.crt"
```

This trusts certificates signed by this Playstead instance's local CA, so keep
the certificate tied to this server and remove its trust if the server data is
retired. The native Playstead app also has its own pairing flow that pins the
CA fingerprint; follow the fingerprint shown by Playstead during pairing
rather than disabling certificate checks.

If you prefer Keychain Access, open the `.crt` file, add it to the `login`
keychain, open the added certificate, expand `Trust`, choose `Always Trust` for
SSL, and close the dialog. macOS may ask for the account password to change the
login Keychain. Then open `https://<server-LAN-IPv4>:8443` in a browser on this
Mac and confirm there is no certificate warning.

If you later choose to test a second personal device, transfer the same public
certificate privately, compare its fingerprint locally, and trust it in that
device's login Keychain. A work-managed Mac is not needed for this trial.

A private hostname is also possible if the LAN has local DNS, but it must
resolve to the server on every client. A DHCP-reserved IP avoids that extra
DNS/hosts setup for this single-Mac test. Tailscale remains optional.

An owned public DNS name can use a publicly trusted certificate instead. The
HTTP-01 and TLS-ALPN-01 validation methods require the public service to be
reachable on their expected ports. Let's Encrypt DNS-01 proves domain control
through a DNS TXT record and can work without exposing the server, but automated
renewal requires DNS-provider API integration. This deployment's bundled Caddy
image does not include a configured DNS provider, so that path needs separate
setup. Since January 2026, Let's Encrypt also generally issues IPv4/IPv6
address certificates, but these last only 160 hours and require the
short-lived ACME profile. IP validation is HTTP-01 or TLS-ALPN-01, which needs
the public IP to be reachable for validation; DNS-01 cannot validate IP
identifiers. A private LAN IP is not publicly reachable, and attempting a
short-lived public-IP certificate would add frequent renewal requirements.
The local internal CA is simplest for this single-Mac trial. Our bundled Caddy
configuration does not select the short-lived profile for public IP
certificates.
[Caddy Automatic HTTPS](https://caddyserver.com/docs/automatic-https),
[Let's Encrypt challenge types](https://letsencrypt.org/docs/challenge-types/),
[Let's Encrypt IP and short-lived certificate announcement](https://letsencrypt.org/2026/01/15/6day-and-ip-general-availability).

## First backup and basic one-Mac loop

After importing a small, replaceable selection from the first-adopter inbox,
create an initial full backup:

```sh
scripts/first-adopter-compose.sh backup --full
```

This explicitly targets the running `playstead-first-adopter` project and the
external backup directory from the private env file. It does not select a
project by guessing among QA/recovery stacks. A backup destination on the same
disk is useful for beginning the basic trial but does not protect against loss
of that disk. A published receipt confirms the backup operation's evidence; it
does not establish a clean restore.

For the single-Mac smoke use pattern:

1. Keep the original and another copy of any user-supplied game; import a
   replaceable selection through the web console on this Mac.
2. Pair the Mac app with the local server using the pinned Caddy CA flow.
3. Confirm the game downloads, launches offline, and a normal in-game save is
   captured and uploaded. Use keyboard/pointer input; Virtual HID approval is
   not part of this basic loop.
4. Relaunch the game and confirm its saved progress is still available. Run a
   full backup and retain the original and independent copy while confidence
   grows.

This profile provides a convenient local backup, but independent full and
incremental backup verification and a clean restore remain separate readiness
work. Do not treat it as the sole storage location for irreplaceable data until
those stronger checks are complete.

## Repeatable QA stages and evidence

Keep a short evidence note outside the repository or in a private owner record.
It should contain the date, app build/version identifier, repository revision,
fixed profile name, automated QA results, owner-observed outcomes, and defect
references. Do not record the server address, account/device names, ROM title,
ROM hash, CA fingerprint, or credentials in Git. The automated command output
is designed to be redacted.

Automated checks:

1. Run first-adopter-init.sh once to create a new private config and data root.
2. Run first-adopter-qa.sh config to verify the resolved Compose service set,
   exact bind and named-volume mounts, fixed project identity, and LAN-only
   Caddy port binding.
3. Run first-adopter-compose.sh preflight to check local address assignment,
   port availability, Docker daemon, and existing project resources.
4. After the owner starts the profile and exports its public CA file, run:

       scripts/first-adopter-qa.sh --ca-file "$HOME/Playstead-First-Adopter/caddy-root.crt" live

   Live mode checks exact service labels and mount sources, app health, an
   HTTPS health response, and certificate-chain validation using that CA. It
   redacts the host address, paths, and fingerprint. It never starts, stops,
   copies, or removes Docker resources. A stopped or incomplete profile is
   reported as NOT_RUN and exits nonzero rather than counting as a pass.

Owner-observed checks that require this Mac and a legally held test game:

1. Open the HTTPS URL in a browser without a certificate warning. The
   automated live QA checks the macOS system trust chain. Record the browser's
   visual no-warning observation as manual evidence.
2. Pair the Mac app, import one replaceable user-owned game through the web
   console, download it, disconnect optional networking, launch it offline,
   make a normal game save, and confirm the save uploads and remains available
   after relaunch.
3. Record pass, fail, or not run for each observation and link defects by
   tracker ID. Do not include the game title, content hash, server address, or
   certificate fingerprint.

Second-device pairing and save convergence are optional follow-up coverage;
they do not block this single-Mac first-adopter trial.

Use this privacy-safe evidence checklist in a private note:

- Date: YYYY-MM-DD
- App build/version and repository revision:
- Profile: playstead-first-adopter
- Static configuration QA: PASS / FAIL / NOT RUN
- Compose preflight: PASS / FAIL / NOT RUN
- Live profile, health, HTTPS, and CLI TLS chain: PASS / FAIL / NOT RUN
- This Mac Keychain, pairing, offline launch, and save upload: PASS / FAIL / NOT RUN
- Optional second-device pairing and save convergence: PASS / FAIL / NOT RUN
- Defect references:

A healthy endpoint and trusted TLS chain do not prove launch behavior, offline
play, or save capture. A local backup receipt is evidence that a backup
operation completed; it is not a restore drill.
Independent-backup and clean-restore requirements remain separate readiness
work. Keep source ROMs and another copy while confidence grows.

## QA and recovery resource retirement

Existing canonical `playstead`, development `playstead-dev`, and every
`playstead-restore-*` QA/recovery project and volume remain untouched. The
first-adopter entrypoint never searches for other projects to stop or remove,
and it has no volume deletion or pruning path. Do not use broad Docker cleanup.
Classify the owner and evidence for each old project and volume individually;
retire one only through a separately reviewed, explicit removal plan.
