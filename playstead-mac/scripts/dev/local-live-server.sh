#!/usr/bin/env bash
# Local reproduction harness for the live-server fixture.
#
# Mirrors what run-mac-verification.sh's start_native_services does, then runs
# live-server.sh directly -- with stderr intact. CI sends the fixture's stderr to
# /dev/null by design (only a bounded stage token may cross the artifact
# boundary), which is exactly why every hosted failure has been opaque. Here we
# get the real error text, in about a minute instead of a 32-minute hosted run.
#
# Postgres comes from Docker by default: nothing to install, the version is
# pinned by docker-compose.yml like every other Postgres in this repo, and the
# container is disposable. The hosted runner uses Homebrew's postgresql@17
# because a macOS runner has no Docker; pass --brew to take that path locally.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PG_PORT=55432
PG_MODE=docker
WORK=""
for argument in "$@"; do
  case "$argument" in
    --brew) PG_MODE=brew ;;
    --docker) PG_MODE=docker ;;
    -*) echo "unknown option: $argument" >&2; exit 2 ;;
    *) WORK="$argument" ;;
  esac
done
[ -n "$WORK" ] || WORK="$(mktemp -d "${TMPDIR:-/tmp}/playstead-local-live.XXXXXX")"

if [ "$PG_MODE" = docker ] && ! docker info >/dev/null 2>&1; then
  echo "== docker unavailable, falling back to Homebrew postgresql@17"
  PG_MODE=brew
fi

NATIVE_ROOT="$WORK/native-services"
SERVER_ROOT="$NATIVE_ROOT/app"
CLIENT_ROOT="$WORK/client"
PG_CONTAINER="playstead-local-live-pg-$$"

cleanup() {
  [ -n "${PHOENIX_PID:-}" ] && kill "$PHOENIX_PID" 2>/dev/null || true
  rm -f "${LOCAL_FIXTURE:-/nonexistent}"
  if [ "$PG_MODE" = docker ]; then
    docker rm -f "$PG_CONTAINER" >/dev/null 2>&1 || true
  else
    "${PG_BIN:-/nonexistent}/pg_ctl" -D "$NATIVE_ROOT/postgres" -m immediate stop >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "== work dir: $WORK"
# Same layout the hosted runner builds: the runner owns the root and creates
# mac-client-control, so the fixture only ever writes files into it.
mkdir -m 0700 "$NATIVE_ROOT"
mkdir -p "$SERVER_ROOT/inbox" "$SERVER_ROOT/blobs" "$SERVER_ROOT/exports" \
  "$SERVER_ROOT/mac-client-control"
chmod 0700 "$NATIVE_ROOT" "$SERVER_ROOT" "$SERVER_ROOT/mac-client-control"
mkdir -m 0700 -p "$CLIENT_ROOT"

start_postgres_docker() {
  # One pinned Postgres version for the whole repo: read it off the compose file
  # rather than introducing a second place to bump.
  local pg_image ready
  pg_image="postgres:$(sed -n 's/^[[:space:]]*image: postgres:\(.*\)$/\1/p' \
    "$REPO/playstead-server/docker-compose.yml" | head -1)"
  [ "$pg_image" != "postgres:" ] || pg_image="postgres:17"
  echo "== start postgres ($pg_image, container $PG_CONTAINER)"
  docker run -d --name "$PG_CONTAINER" \
    -e POSTGRES_HOST_AUTH_METHOD=trust \
    -e POSTGRES_DB=playstead_mac_ci \
    -p "127.0.0.1:$PG_PORT:5432" "$pg_image" >/dev/null || return 1
  ready=false
  for _ in $(seq 1 60); do
    if docker exec "$PG_CONTAINER" pg_isready -U postgres -d playstead_mac_ci >/dev/null 2>&1; then
      ready=true; break
    fi
    [ -n "$(docker ps -q --filter "name=$PG_CONTAINER")" ] || break
    sleep 1
  done
  [ "$ready" = true ] && return 0
  # Most often the Docker VM's disk is full, which shows up as an initdb
  # ENOSPC rather than anything about Postgres. Show it and let the caller
  # fall back rather than dead-ending a debugging session on host state.
  echo "== postgres container did not come up:"
  docker logs "$PG_CONTAINER" 2>&1 | tail -8 | sed 's/^/   /'
  docker rm -f "$PG_CONTAINER" >/dev/null 2>&1 || true
  return 1
}

if [ "$PG_MODE" = docker ] && ! start_postgres_docker; then
  echo "== falling back to Homebrew postgresql@17"
  PG_MODE=brew
fi

if [ "$PG_MODE" = docker ]; then
  pg_user=postgres
else
  PG_BIN="$(brew --prefix postgresql@17 2>/dev/null)/bin"
  [ -x "$PG_BIN/initdb" ] || { echo "postgresql@17 is not installed (brew install postgresql@17)"; exit 1; }
  echo "== initdb + start postgres (homebrew)"
  "$PG_BIN/initdb" -D "$NATIVE_ROOT/postgres" --auth=trust --no-locale --encoding=UTF8 >/dev/null
  "$PG_BIN/pg_ctl" -D "$NATIVE_ROOT/postgres" -l "$NATIVE_ROOT/postgres.log" \
    -o "-h 127.0.0.1 -p $PG_PORT" -w start >/dev/null
  "$PG_BIN/createdb" -h 127.0.0.1 -p "$PG_PORT" playstead_mac_ci
  pg_user="$(id -un)"
fi

export MIX_ENV=mac_ci
export PORT=4010
export PLAYSTEAD_MAC_CI_ROOT="$SERVER_ROOT"
export PLAYSTEAD_LIVE_SERVER_STAGE_ROOT="$SERVER_ROOT"
export PLAYSTEAD_LIVE_SERVER_STAGE_FILE="$SERVER_ROOT/live-server-failure-stage"
export MAC_CI_DATABASE_URL="ecto://${pg_user}@127.0.0.1:${PG_PORT}/playstead_mac_ci"

echo "== bootstrap phoenix (deps + migrate)"
( cd "$REPO/playstead-server" && mix deps.get && mix ecto.migrate ) \
  >"$NATIVE_ROOT/bootstrap.log" 2>&1 || { tail -40 "$NATIVE_ROOT/bootstrap.log"; exit 1; }

echo "== start phoenix"
( cd "$REPO/playstead-server" && exec mix phx.server ) >"$NATIVE_ROOT/phoenix.log" 2>&1 &
PHOENIX_PID=$!
ready=false
for _ in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1; then ready=true; break; fi
  sleep 1
done
[ "$ready" = true ] || { echo "phoenix never became ready"; tail -40 "$NATIVE_ROOT/phoenix.log"; exit 1; }
echo "   phoenix healthy on :$PORT"

# The shipped fixture silences its own stderr so only a bounded token escapes.
# Strip that one line for local debugging; everything else runs verbatim.
# Must live beside the original: the fixture resolves playstead-server from its
# own BASH_SOURCE, so a copy anywhere else breaks resolve-server-root.
LOCAL_FIXTURE="$REPO/playstead-mac/scripts/ci/.live-server.local.sh"
grep -v '^exec 2>/dev/null$' "$REPO/playstead-mac/scripts/ci/live-server.sh" >"$LOCAL_FIXTURE"
: >"$PLAYSTEAD_LIVE_SERVER_STAGE_FILE"; chmod 0600 "$PLAYSTEAD_LIVE_SERVER_STAGE_FILE"

run_stage() {
  echo "== run: live-server.sh $1 (stderr visible)"
  set +e
  bash "$LOCAL_FIXTURE" "$@"
  local status=$?
  set -e
  echo "== $1 exit=$status  stage=$(cat "$PLAYSTEAD_LIVE_SERVER_STAGE_FILE" 2>/dev/null || echo '<none>')"
  return "$status"
}

run_stage prepare "$CLIENT_ROOT" "$SERVER_ROOT"
run_stage second "$CLIENT_ROOT" "$SERVER_ROOT"

echo "== artifacts"
ls -la "$CLIENT_ROOT/control"
[ -f "$CLIENT_ROOT/credential-handoff.json" ] &&
  echo "   credential-handoff.json present (mode $(stat -f '%Lp' "$CLIENT_ROOT/credential-handoff.json"))"
echo "== FIXTURE OK"
