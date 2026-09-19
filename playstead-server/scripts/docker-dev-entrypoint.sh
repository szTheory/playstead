#!/usr/bin/env bash
# Entrypoint for the dev container defined by ../Dockerfile.dev.
#
# Read from the bind-mounted repo at runtime, not baked into the image, so
# editing it takes effect on the next `docker compose up` with no rebuild.
#
# Every step here is idempotent, because this runs on every container start and
# the _build/deps volumes persist between them: `deps.get` is a no-op when
# mix.lock is satisfied, `ecto.create` reports an existing database and moves on,
# `ecto.migrate` applies only what is pending, and priv/repo/seeds.exs is empty.
# The first run pays for a full dependency compile; later runs start in seconds.
set -euo pipefail

PGHOST="${PGHOST:-db}"
PGUSER="${PGUSER:-postgres}"
PGDATABASE="${PGDATABASE:-playstead_dev}"

log() { printf '[dev-entrypoint] %s\n' "$*"; }

# Compose already gates this container on `db` being service_healthy, so this
# loop normally passes on its first iteration. It stays because a healthy
# Postgres container and a Postgres ready to accept THIS database's connections
# are not the same instant, and the failure mode without it is an Ecto
# connection-refused crash loop rather than a named wait.
log "waiting for postgres at ${PGHOST}"
deadline=$((SECONDS + 60))
until pg_isready --host "$PGHOST" --username "$PGUSER" --quiet; do
  if [ "$SECONDS" -ge "$deadline" ]; then
    log "FAIL: postgres at ${PGHOST} did not become ready within 60s"
    exit 1
  fi
  sleep 1
done
log "postgres is ready"

# Fail loudly rather than booting a half-configured server. Compose sets this;
# an empty value means dev.exs would silently fall back to `hostname: localhost`,
# which inside this container is the container itself -- there is no Postgres
# there, and the resulting error would point at the wrong thing entirely.
if [ -z "${PLAYSTEAD_DEV_DATABASE_URL:-}" ]; then
  log "FAIL: PLAYSTEAD_DEV_DATABASE_URL is empty. Without it config/dev.exs"
  log "      falls back to hostname \"localhost\", which in this container is"
  log "      the container itself and has no Postgres. Check docker-compose.dev.yml."
  exit 1
fi

# Same class of check for the bind override. Without it the server listens on the
# container's own loopback, Docker's published port forwards to nothing, and the
# only symptom is a connection refused on the host with a perfectly healthy
# container -- the single most confusing way this stack can fail.
if [ "${PLAYSTEAD_DEV_BIND_ALL:-}" != "true" ]; then
  log "FAIL: PLAYSTEAD_DEV_BIND_ALL must be \"true\" in the dev container."
  log "      Otherwise Phoenix binds the container's own loopback and the"
  log "      published port reaches nothing. Check docker-compose.dev.yml."
  exit 1
fi

log "fetching dependencies"
mix deps.get

# Installs the Linux esbuild/tailwind binaries. Verified to land in
# /app/_build (esbuild-linux-arm64, tailwind-linux-arm64-4.3.0), which is a
# container-private named volume -- so they never appear in the bind-mounted
# checkout next to the host's macOS ones, and the host tree stays clean. The
# repo's .gitignore covers /esbuild-* and /tailwind-* anyway, so a future
# version that did install to the project root would still not dirty the tree.
log "installing asset tooling"
mix assets.setup

log "creating and migrating the database"
mix ecto.create
mix ecto.migrate

log "building assets"
mix assets.build

log "starting phoenix on port ${PORT:-4000}"
exec mix phx.server
