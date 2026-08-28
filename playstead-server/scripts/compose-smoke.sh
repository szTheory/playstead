#!/usr/bin/env bash
# OPER-01 evidence path that ExUnit cannot reach: brings the compose
# stack up, waits for all three services to report healthy, curls
# /healthz and /api/v1/capabilities through Caddy, restarts the stack,
# and re-asserts that the playstead_db volume still holds data.
#
# `--fresh` turns this into the cold-start test (UAT "Cold Start Smoke
# Test"): the named volumes are destroyed first, so the run proves a
# from-scratch boot — migrations at boot, the single-use setup token
# printed to the app's stdout, /setup open before and after a restart.
# Because `docker compose down -v` destroys a real library, `--fresh` is
# refused unless CI=true or SMOKE_ALLOW_FRESH=1 is set.
#
# Env: PLAYSTEAD_HTTP_PORT / PLAYSTEAD_HTTPS_PORT (host ports), SMOKE_TIMEOUT,
# COMPOSE_FILE (e.g. "docker-compose.yml:docker-compose.ci.yml" to reuse a
# prebuilt image), POSTGRES_USER / POSTGRES_DB.
#
# Exits non-zero on any failure. Run from playstead-server/.
set -euo pipefail

cd "$(dirname "$0")/.."

COMPOSE="docker compose"
TIMEOUT_SECS="${SMOKE_TIMEOUT:-120}"
INTERVAL_SECS=3
HTTPS_PORT="${PLAYSTEAD_HTTPS_PORT:-443}"
BASE_URL="https://localhost:${HTTPS_PORT}"
FRESH=0

for arg in "$@"; do
  case "$arg" in
    --fresh) FRESH=1 ;;
    *) echo "usage: $0 [--fresh]" >&2; exit 2 ;;
  esac
done

if [ "$FRESH" = "1" ] && [ "${CI:-}" != "true" ] && [ "${SMOKE_ALLOW_FRESH:-}" != "1" ]; then
  echo "[compose-smoke] REFUSED: --fresh runs 'docker compose down -v', which destroys the" >&2
  echo "[compose-smoke] playstead_db and playstead_blobs volumes — THIS IS YOUR LIBRARY." >&2
  echo "[compose-smoke] Set SMOKE_ALLOW_FRESH=1 (or CI=true) if this really is a throwaway stack." >&2
  exit 2
fi

if [ "${CI:-}" = "true" ]; then
  trap 'status=$?; if [ $status -ne 0 ]; then docker compose logs --no-color || true; fi; docker compose down --remove-orphans || true' EXIT
fi

log() {
  echo "[compose-smoke] $*"
}

fail() {
  echo "[compose-smoke] FAIL: $*" >&2
  $COMPOSE logs --no-color || true
  exit 1
}

wait_for_healthy() {
  local elapsed=0

  while true; do
    local unhealthy
    unhealthy=$($COMPOSE ps --format '{{.Service}} {{.Health}}' | awk '$2 != "healthy" && $2 != "" {print $1}')
    local pending
    pending=$($COMPOSE ps --format '{{.Service}} {{.Health}}' | wc -l)

    if [ -z "$unhealthy" ] && [ "$pending" -ge 3 ]; then
      log "all services healthy"
      return 0
    fi

    if [ "$elapsed" -ge "$TIMEOUT_SECS" ]; then
      fail "services did not become healthy within ${TIMEOUT_SECS}s: $unhealthy"
    fi

    sleep "$INTERVAL_SECS"
    elapsed=$((elapsed + INTERVAL_SECS))
  done
}

# Caddy reports healthy the moment its process is up, a beat before it
# accepts TLS connections; retry briefly instead of failing on that race.
curl_ok() {
  local url="$1"
  local status="000"
  local attempt=0

  while [ "$attempt" -lt 10 ]; do
    status=$(curl -k -s -o /dev/null -w '%{http_code}' "$url" || echo "000")
    [ "$status" = "200" ] && break
    attempt=$((attempt + 1))
    sleep 1
  done

  if [ "$status" != "200" ]; then
    fail "$url returned status $status, expected 200"
  fi

  log "$url -> 200"
}

assert_setup_token_banner() {
  # A fresh install (no owner) prints exactly one single-use setup token to
  # the app's stdout at boot; the wizard at /setup must be open.
  local token
  token=$($COMPOSE logs --no-color app 2>/dev/null \
    | sed -n '/Playstead setup token (use once, in the setup wizard at \/setup):/{n;n;p;}' \
    | tr -d ' \r' | head -1)

  if [ -z "$token" ] || [ "${#token}" -lt 32 ]; then
    fail "expected the single-use setup token banner in 'docker compose logs app' on a fresh install"
  fi

  log "setup token banner present (${#token} chars)"
  curl_ok "${BASE_URL}/setup"
}

if [ "$FRESH" = "1" ]; then
  log "--fresh: destroying named volumes for a true cold start"
  $COMPOSE down -v --remove-orphans
fi

log "bringing the stack up"
$COMPOSE up -d

wait_for_healthy

curl_ok "${BASE_URL}/healthz"
curl_ok "${BASE_URL}/api/v1/capabilities"

if [ "$FRESH" = "1" ]; then
  assert_setup_token_banner
fi

log "asserting /app/blobs is writable by the app container's runtime user"
$COMPOSE exec -T app sh -c 'touch /app/blobs/.smoke-write-test && rm /app/blobs/.smoke-write-test' \
  || fail "/app/blobs is not writable inside the app container"
log "/app/blobs is writable"

log "recording a marker row so we can prove the volume survives a restart"
$COMPOSE exec -T db psql -U "${POSTGRES_USER:-playstead}" -d "${POSTGRES_DB:-playstead}" \
  -c "CREATE TABLE IF NOT EXISTS compose_smoke_marker (id serial primary key, created_at timestamptz default now());" \
  -c "INSERT INTO compose_smoke_marker DEFAULT VALUES;" \
  >/dev/null

log "restarting the stack"
$COMPOSE down
$COMPOSE up -d

wait_for_healthy

curl_ok "${BASE_URL}/healthz"
curl_ok "${BASE_URL}/api/v1/capabilities"

log "re-asserting the playstead_db volume survived the restart"
MARKER_COUNT=$($COMPOSE exec -T db psql -U "${POSTGRES_USER:-playstead}" -d "${POSTGRES_DB:-playstead}" \
  -tAc "SELECT count(*) FROM compose_smoke_marker;")

if [ "${MARKER_COUNT:-0}" -lt 1 ]; then
  fail "expected marker row(s) in playstead_db to survive 'docker compose down' + 'up -d', found none"
fi

log "playstead_db volume survived restart with $MARKER_COUNT marker row(s)"

if [ "$FRESH" = "1" ]; then
  # No owner was ever created, so the wizard must still be open after the
  # restart (re-minting the setup token at boot must not have broken boot).
  curl_ok "${BASE_URL}/setup"
fi

log "SUCCESS"
