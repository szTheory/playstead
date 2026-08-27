#!/usr/bin/env bash
# OPER-01 evidence path that ExUnit cannot reach: brings the compose
# stack up, waits for all three services to report healthy, curls
# /healthz and /api/v1/capabilities through Caddy, restarts the stack,
# and re-asserts that the playstead_db volume still holds data.
#
# Exits non-zero on any failure. Run from playstead-server/.
set -euo pipefail

cd "$(dirname "$0")/.."

COMPOSE="docker compose"
TIMEOUT_SECS="${SMOKE_TIMEOUT:-120}"
INTERVAL_SECS=3
HTTPS_PORT="${PLAYSTEAD_HTTPS_PORT:-443}"
BASE_URL="https://localhost:${HTTPS_PORT}"

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

curl_ok() {
  local url="$1"
  local status
  status=$(curl -k -s -o /dev/null -w '%{http_code}' "$url") || fail "curl to $url failed"

  if [ "$status" != "200" ]; then
    fail "$url returned status $status, expected 200"
  fi

  log "$url -> 200"
}

log "bringing the stack up"
$COMPOSE up -d

wait_for_healthy

curl_ok "${BASE_URL}/healthz"
curl_ok "${BASE_URL}/api/v1/capabilities"

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
log "SUCCESS"
