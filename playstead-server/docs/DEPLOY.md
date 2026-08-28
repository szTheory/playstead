# Deploying Playstead

This document is the one supported, documented path to a self-hosted
Playstead server. Following it end to end is the acceptance test for
OPER-01.

## Prerequisites

- A machine with Docker and Docker Compose installed (`docker compose version`).
- `openssl` on the machine you use to generate secrets (most systems already have it).
- Optionally, a domain name pointed at this machine if you want a
  publicly trusted certificate instead of Caddy's internal CA.

## 1. Copy the environment file and generate secrets

```bash
cp .env.example .env
```

Generate a real `SECRET_KEY_BASE`:

```bash
mix phx.gen.secret
```

(If you don't have Elixir installed on the host, run this inside the
built image instead: `docker compose run --rm app bin/playstead eval 'IO.puts(Base.encode64(:crypto.strong_rand_bytes(64)))'`.)

Generate a real `POSTGRES_PASSWORD`:

```bash
openssl rand -base64 32
```

Paste both generated values into `.env`, replacing the
`REPLACE_WITH_GENERATED_SECRET_KEY_BASE` and `REPLACE_WITH_STRONG_PASSWORD`
placeholders — including inside `DATABASE_URL`, which embeds the same
password. **The application refuses to boot if either placeholder is
still present.**

If you have a domain pointed at this machine, set `PLAYSTEAD_DOMAIN` in
`.env` to it. Otherwise leave it blank and Caddy will serve `localhost`
with its own internal, locally-trusted certificate authority.

## 2. Start the stack

```bash
docker compose up -d
```

This starts three services: `db` (Postgres), `app` (the Phoenix
release), and `caddy` (TLS termination and reverse proxy). Only
`caddy` publishes host ports; `db` and `app` are reachable only on the
internal compose network.

## 3. Retrieve the setup token

The server prints a single-use setup token to its logs while it is
unclaimed:

```bash
docker compose logs app | grep -A2 "Playstead setup token"
```

## 4. Complete setup in the console

Visit `https://localhost/setup` (or `https://<PLAYSTEAD_DOMAIN>/setup`
if you set a domain), paste in the setup token, and follow the wizard
to create your owner account.

## Import and export folders

Two more host folders appear alongside the named volumes, starting in
Phase 2:

```
./inbox/     # stage files here to import a collection
./exports/   # exported game folders are written here
```

Copy files into `./inbox` to stage a "Stage a collection" import from
the console. Playstead never modifies or removes anything under
`./inbox` — the folder is mounted read-only inside the container, so
that is a guarantee your operating system enforces, not just something
the application promises to do.

`./exports` is where exported folders are written when you export your
library as ordinary files. **A copy in `./exports` on the same disk is
not a backup.** If the disk fails, the live library and the exported
copy are gone together — see `docs/UPGRADE.md` for the backup
procedure before any upgrade.

## Named volumes — this is your library

```
playstead_db      # Postgres data directory
playstead_blobs   # blob storage (created now, used starting Phase 2)
```

**Never run `docker compose down -v`.** The `-v` flag deletes these
named volumes and everything in them — your entire library and every
persistent save. `docker compose down` (without `-v`) is safe and
preserves both volumes.

**A copy of these volumes on the same disk is not a backup.** If the
disk fails, both the live data and the "backup" copy are gone
together. See `docs/UPGRADE.md` for the backup procedure before any
upgrade.

## Supported alternative deployment adapters

These are documented, supported alternatives to the bundled Caddy —
not the default, and not automatically verified by the compose smoke
script.

### Tailscale

If this machine is on a Tailscale network, you can obtain a certificate
for its Tailscale hostname with:

```bash
tailscale cert <your-machine>.<your-tailnet>.ts.net
```

and point your own reverse proxy (or a modified Caddyfile) at the
`app` service's internal port instead of using the bundled Caddy's
automatic HTTPS.

### Bring-your-own reverse proxy (`PLAYSTEAD_PROXY=external`)

Set `PLAYSTEAD_PROXY=external` in `.env` and run your own reverse
proxy (e.g. an existing nginx/Traefik instance) in front of the `app`
service instead of the bundled Caddy. In this mode, TLS termination and
certificate management are entirely your responsibility.

**Plain-HTTP and external-proxy honesty:** A deployment served over
plain HTTP, or fronted by an external proxy via `PLAYSTEAD_PROXY=external`,
provides no guarantee about transport confidentiality or certificate
validity beyond whatever you configure in your own proxy — Playstead
makes no claim about it either way. Describe concretely, in your own
documentation or console messaging, what protection is and is not in
place (e.g. "traffic between this proxy and the Playstead app is
unencrypted on the internal Docker network, which is not exposed to
the host network") rather than reaching for a one-word label for
either configuration.

## External Postgres (override, not the happy path)

The bundled `db` service is the supported default. If you already run
a Postgres instance you'd rather use, you can override `DATABASE_URL`
in `.env` to point at it and remove the `db` service from your compose
override file. You are then responsible for that instance's backups,
version compatibility, and network exposure — this is an advanced
override, not a documented first-class path, and the compose smoke
script does not exercise it.
