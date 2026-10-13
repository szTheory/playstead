#!/usr/bin/env bash
# dev-up.sh -- clean-machine-to-launched-game stand-up for Playstead.
#
# One command for what playstead-mac/docs/LOCAL-DEV.md walks through by hand:
# start the server, report what still needs a human, pair this Mac, and build
# and launch the app.
#
# The server half is containerized by default (playstead-server/Dockerfile.dev +
# docker-compose.dev.yml), so a clean machine needs Docker and nothing else for
# it -- no Elixir, no Erlang, no Postgres, no secrets to generate.
#
# The Mac half CANNOT be containerized and this script does not pretend
# otherwise: Playstead is a native SwiftUI app. It needs Xcode to build, the
# login Keychain to read its pairing credential, and a real macOS process to
# launch the emulator. That part always runs on the host.
#
# Everything here is idempotent. Re-running it on a stack that is already up
# reports state and moves on rather than rebuilding.
#
# Usage: scripts/dev-up.sh [options]
#   --native        run the server with `mix phx.server` on the host instead of
#                   in a container (needs Elixir/Erlang per
#                   playstead-server/.tool-versions and a Postgres on
#                   localhost:5432). Faster edit-reload; more prerequisites.
#   --server URL    talk to an ALREADY-RUNNING server at URL instead of the
#                   containerized dev stack (e.g. --server https://localhost:18443
#                   for the deployment stack in docker-compose.yml). Implies
#                   --no-stack: nothing is started or stopped, because that server
#                   is not this script's to manage.
#   --server-only   stand up the server; do not touch pairing or the Mac app.
#   --no-pair       skip the pairing step (it needs you to approve in a browser).
#   --xcode         open Playstead.xcodeproj instead of building and launching.
#   --reset         DESTRUCTIVE: drop the dev database before starting. Wipes the
#                   owner account, paired devices and imported library of the DEV
#                   stack only. Never touches docker-compose.yml's playstead_db.
#   --down          stop the containerized dev stack and exit.
#   --status        report what is and is not running, then exit.
#   -h, --help      this text.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="$REPO/playstead-server"
MAC_DIR="$REPO/playstead-mac"
COMPOSE_FILE="$SERVER_DIR/docker-compose.dev.yml"
TOKEN_FILE="$SERVER_DIR/.dev-setup-token"
NATIVE_LOG="$SERVER_DIR/tmp/dev-server.log"
NATIVE_PIDFILE="$SERVER_DIR/tmp/dev-server.pid"
BASE_URL="http://127.0.0.1:4000"
MANAGE_STACK=true
KEYCHAIN_SERVICE="dev.playstead.mac"
DERIVED_DATA="$MAC_DIR/build/dd"
BUILD_LOG="$MAC_DIR/build/dev-up-xcodebuild.log"
ADAPTER_DIR="$HOME/Library/Application Support/Playstead/emulators/mgba/0.10.5"

MODE=docker
DO_APP=true
DO_PAIR=true
OPEN_XCODE=false
DO_RESET=false
ACTION=up

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'
else
  B=""; DIM=""; G=""; Y=""; R=""; N=""
fi

step()  { printf '\n%s==>%s %s%s%s\n' "$B" "$N" "$B" "$*" "$N"; }
ok()    { printf '  %s+%s %s\n' "$G" "$N" "$*"; }
warn()  { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
info()  { printf '    %s%s%s\n' "$DIM" "$*" "$N"; }
die()   { printf '\n%serror:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

usage() { sed -n '/^# Usage:/,/^#   -h, --help/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# Prompts must never be the reason a non-interactive run dies. With `set -e` a
# bare `read` at EOF returns non-zero and aborts the script, so a piped or CI
# invocation would fail here rather than at anything meaningful. Returns 1 (a
# declined prompt) instead, and says why.
ask() { # ask <prompt> <answer-var>
  local __prompt="$1" __var="$2" __reply=""
  if [ ! -t 0 ]; then
    info "stdin is not a terminal -- skipping the prompt and assuming no"
    return 1
  fi
  printf '    %s ' "$__prompt"
  read -r __reply || { printf '\n'; return 1; }
  printf -v "$__var" '%s' "$__reply" 2>/dev/null || eval "$__var=\$__reply"
  return 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --server)
      [ $# -ge 2 ] || die "--server needs a URL"
      BASE_URL="$2"; MANAGE_STACK=false; shift ;;
    --server=*) BASE_URL="${1#*=}"; MANAGE_STACK=false ;;
    --native) MODE=native ;;
    --docker) MODE=docker ;;
    --server-only) DO_APP=false; DO_PAIR=false ;;
    --no-pair) DO_PAIR=false ;;
    --xcode) OPEN_XCODE=true ;;
    --reset) DO_RESET=true ;;
    --down) ACTION=down ;;
    --status) ACTION=status ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
  shift
done

compose() { docker compose --file "$COMPOSE_FILE" "$@"; }

server_responding() { curl --silent --fail --max-time 3 "$BASE_URL/healthz" >/dev/null 2>&1; }

# Empty string when nothing answers, so callers can distinguish "no server" from
# a real status code.
setup_status() { curl --silent --output /dev/null --max-time 5 --write-out '%{http_code}' "$BASE_URL/setup" 2>/dev/null || true; }

# The base URL the stored credential was issued for, or "" when there is none.
#
# Presence of a credential is NOT the same as being paired with the server this
# script is standing up, and conflating the two is a real bug this script shipped
# with: a credential pointing at https://localhost:18443 was waved through with
# "a credential is already in the login Keychain" while the dev stack had zero
# devices, so the app would have started against a server it had no credential
# for.
#
# That 18443 credential was the operator's REAL pairing to their REAL library
# (the deployment stack in docker-compose.yml, whose Caddy publishes 18443) --
# not, as an earlier version of this comment asserted, a leftover from a
# compose-smoke run. Getting that provenance wrong is exactly how this script
# came to talk someone off a working pairing, so see the pairing step below:
# a credential pointing at a server that ANSWERS must never be treated as
# stale.
#
# Read from the `gena` attribute, which pair-dev.sh writes as the JSON
# CredentialEnvelope `{"baseURL":"..."}`. Only this attribute is read -- never
# the password.
#
# `security` prints that blob in ONE OF TWO FORMS, and both must be handled. It
# emits a `0x<hex>` prefix only when the bytes need escaping; a payload that is
# plain printable ASCII is printed as a quoted string with no hex at all:
#
#   "gena"<blob>=0x7B22...227D  "{"baseURL":"https:\134/\134/localhost:18443"}"
#   "gena"<blob>="{"baseURL": "http://127.0.0.1:4000"}"
#
# Reading only the hex form -- which an earlier version did -- makes a correctly
# paired Mac report "no pairing credential in the login Keychain", the worst
# possible direction for this check to fail in. Both forms above are captured
# verbatim from real credentials on this machine and are the fixtures this
# function was tested against.
#
# Two unescapes, both load-bearing. `security` renders a literal backslash as
# octal `\134` in the quoted form, and JSON encoders routinely escape forward
# slashes, so a stored value can read `http:\/\/127.0.0.1:4000`. Skip either and
# a correctly paired credential never string-matches BASE_URL, leaving the caller
# to nag forever about re-pairing a device that was already fine.
paired_base_url() {
  local line json hex
  line="$(security find-generic-password -s "$KEYCHAIN_SERVICE" 2>/dev/null \
    | grep '"gena"<blob>=' | head -1)"
  [ -n "$line" ] || return 0

  hex="$(printf '%s' "$line" | sed -n 's/^[[:space:]]*"gena"<blob>=0x\([0-9A-Fa-f]*\).*/\1/p')"
  if [ -n "$hex" ]; then
    json="$(printf '%s' "$hex" | xxd -r -p 2>/dev/null)"
  else
    json="$(printf '%s' "$line" | sed -n 's/^[[:space:]]*"gena"<blob>=//p')"
    json="${json#\"}"
    json="${json%\"}"
    json="$(printf '%s' "$json" | sed 's/\\134/\\/g')"
  fi

  printf '%s' "$json" \
    | sed -n 's/.*"baseURL"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | sed 's|\\/|/|g' | head -1
}

# ---------------------------------------------------------------- status/down

if [ "$ACTION" = status ]; then
  step "Status"
  if server_responding; then
    ok "server responding at $BASE_URL"
    case "$(setup_status)" in
      200) warn "no owner account yet -- $BASE_URL/setup is open" ;;
      404) ok "owner account exists (/setup correctly 404s)" ;;
      *)   warn "could not read /setup" ;;
    esac
  else
    warn "no server responding at $BASE_URL"
  fi
  if docker info >/dev/null 2>&1; then
    printf '\n'
    compose ps 2>/dev/null || info "dev stack has never been started"
  else
    warn "docker is not running"
  fi
  paired_url="$(paired_base_url)"
  if [ -z "$paired_url" ]; then
    warn "no pairing credential in the login Keychain -- this Mac is not paired"
  elif [ "$paired_url" = "$BASE_URL" ]; then
    ok "paired with $BASE_URL"
  else
    warn "the stored credential is for $paired_url, not $BASE_URL -- re-pair"
  fi
  exit 0
fi

if [ "$ACTION" = down ] && [ "$MANAGE_STACK" = false ]; then
  die "--down refuses to run with --server: $BASE_URL is not this script's stack to stop"
fi

if [ "$ACTION" = down ]; then
  step "Stopping the dev stack"
  if [ -f "$NATIVE_PIDFILE" ] && kill -0 "$(cat "$NATIVE_PIDFILE")" 2>/dev/null; then
    kill "$(cat "$NATIVE_PIDFILE")" && rm -f "$NATIVE_PIDFILE"
    ok "stopped the native mix server"
  fi
  if docker info >/dev/null 2>&1; then
    # `down` without -v: the dev_db volume survives, so your owner account and
    # imported library are still there next time. --reset is the way to discard.
    compose down
    ok "containers stopped; the dev_db volume was kept (use --reset to discard it)"
  else
    warn "docker is not running; nothing to stop"
  fi
  exit 0
fi

# ------------------------------------------------------------------ preflight

step "Preflight"

[ -d "$SERVER_DIR" ] || die "$SERVER_DIR not found -- run this from the playstead repo"

if [ "$MANAGE_STACK" = false ]; then
  # --server: that server is someone else's to run. Require only that it answers,
  # and never start, stop or reset anything.
  ok "targeting $BASE_URL (not managing any stack)"
  server_responding || die "nothing is answering $BASE_URL/healthz -- start that server first"
  ok "$BASE_URL/healthz is answering"
elif [ "$MODE" = docker ]; then
  command -v docker >/dev/null 2>&1 || die "docker not found. Install Docker Desktop, or use --native."
  docker info >/dev/null 2>&1 || die "docker is installed but not running. Start Docker Desktop, or use --native."
  ok "docker is running"
else
  command -v mix >/dev/null 2>&1 || die "mix not found. Install Elixir per playstead-server/.tool-versions, or drop --native."
  # Resolved from inside SERVER_DIR on purpose: version managers pick a version
  # per directory, and playstead-server/.tool-versions pins 1.19.5 while the repo
  # root may resolve to something else entirely (it resolved to 1.17.3 here).
  # Reporting the root's version would name a version this run does not use.
  ok "elixir $( (cd "$SERVER_DIR" && elixir --version 2>/dev/null | tail -1 | sed 's/Elixir //') )"
  # Fail here with the real cause rather than letting Ecto report a connection
  # refused several steps later.
  (exec 3<>/dev/tcp/127.0.0.1/5432) 2>/dev/null \
    || die "no Postgres on localhost:5432. The native path needs one (postgres/postgres); the default containerized path does not -- drop --native."
  ok "postgres is reachable on localhost:5432"
fi

if [ "$DO_APP" = true ] || [ "$OPEN_XCODE" = true ]; then
  if xcodebuild -version >/dev/null 2>&1; then
    ok "$(xcodebuild -version 2>/dev/null | head -1)"
  else
    warn "xcodebuild unavailable -- skipping the Mac app. Install Xcode + Command Line Tools."
    DO_APP=false; OPEN_XCODE=false
  fi
fi

# A server already on 4000 that is NOT ours would be silently shadowed by
# everything below, so name it instead of racing it.
ALREADY_UP=false
if [ "$MANAGE_STACK" = false ]; then
  ALREADY_UP=true
elif server_responding; then
  # Our own stack. A --reset is about to stop it, so this is not a conflict --
  # an earlier version tested `lsof` in this case too and died claiming port 4000
  # "does not answer /healthz" about a container that had just answered it.
  if [ "$DO_RESET" = true ]; then
    info "a server is running at $BASE_URL; --reset will stop it first"
  else
    ok "a server is already responding at $BASE_URL -- reusing it"
    ALREADY_UP=true
  fi
elif lsof -ti tcp:4000 >/dev/null 2>&1; then
  # Something holds the port but is not Playstead, or is a Playstead that failed
  # to boot. Either way everything below would silently talk past it.
  die "something is listening on port 4000 but does not answer $BASE_URL/healthz. Stop it first: lsof -ti tcp:4000 | xargs kill"
fi

# -------------------------------------------------------------- setup token

# Generated once and reused, so the /setup link this script prints keeps working
# across restarts. Not a secret worth protecting -- it only gates creating the
# owner account on a loopback-only dev server -- but gitignored regardless.
if [ ! -f "$TOKEN_FILE" ]; then
  # Subshell so the tightened umask applies to this file alone -- umask is
  # process-wide, and leaking it would silently change the mode of the native
  # log and exports/ created further down.
  ( umask 077 && openssl rand -hex 32 > "$TOKEN_FILE" )
fi
SETUP_TOKEN="$(cat "$TOKEN_FILE")"
export PLAYSTEAD_DEV_SETUP_TOKEN="$SETUP_TOKEN"

# ----------------------------------------------------------------- the server

if [ "$DO_RESET" = true ] && [ "$MANAGE_STACK" = false ]; then
  die "--reset refuses to run with --server: $BASE_URL is not this script's stack to drop"
fi

if [ "$DO_RESET" = true ]; then
  step "Resetting the dev database"
  warn "this discards the DEV owner account, paired devices and imported library"
  info "docker-compose.yml's playstead_db volume -- the deployment one -- is untouched"
  confirmation=""
  ask 'type "reset" to confirm:' confirmation || true
  [ "$confirmation" = "reset" ] || die "not confirmed; nothing was changed"
  if [ "$MODE" = docker ]; then
    compose down
    # Both, not just the database: blob rows are the only way to reach blob
    # bytes, so keeping dev_blobs after dropping dev_db leaves orphaned content
    # that nothing can address and the next import cannot deduplicate against.
    docker volume rm playstead-dev_dev_db playstead-dev_dev_blobs >/dev/null 2>&1 || true
    ok "dev_db and dev_blobs volumes removed"
  else
    # Stop our own server first: `ecto.drop` cannot drop a database that still
    # has open connections, and the one this script started is exactly that.
    # The docker branch above gets this for free from `compose down`.
    if [ -f "$NATIVE_PIDFILE" ] && kill -0 "$(cat "$NATIVE_PIDFILE")" 2>/dev/null; then
      kill "$(cat "$NATIVE_PIDFILE")" && rm -f "$NATIVE_PIDFILE"
      info "stopped the running native server so the database can be dropped"
      # Give the VM a moment to close its pool before ecto.drop asks.
      for _ in 1 2 3 4 5; do server_responding || break; sleep 1; done
    fi
    (cd "$SERVER_DIR" && MIX_ENV=dev mix ecto.drop) \
      || die "mix ecto.drop failed -- another client may hold a connection to playstead_dev"
    # Same reasoning as the docker branch: the rows that address these bytes are
    # gone, so the bytes go too.
    rm -rf "$SERVER_DIR/blobs"
    ok "playstead_dev dropped and blobs/ cleared"
  fi
  # A reset invalidates any credential paired against the old device rows.
  if security find-generic-password -s "$KEYCHAIN_SERVICE" >/dev/null 2>&1; then
    warn "the Keychain still holds a credential for the devices you just dropped"
    info "pair-dev.sh purges it on its next run, so no action is needed"
  fi
  ALREADY_UP=false
fi

if [ "$ALREADY_UP" = false ]; then
  if [ "$MODE" = docker ]; then
    step "Starting the containerized server"
    info "first run compiles every dependency inside the container -- minutes, once"
    compose up --build --detach
    ok "containers started"
  else
    step "Preparing the native server"
    # blobs/ matters as much as exports/: Playstead.Readiness and
    # Blobs.Store.LocalDisk both default PLAYSTEAD_BLOB_PATH to the CONTAINER
    # path /app/blobs, which on a Mac does not exist and cannot be created. Left
    # unset, the setup wizard's last step reports "/app/blobs is not writable: no
    # such file or directory" and no blob can ever be stored. LOCAL-DEV.md's
    # native step set PLAYSTEAD_EXPORT_PATH for the same reason but missed this.
    mkdir -p "$SERVER_DIR/tmp" "$SERVER_DIR/exports" "$SERVER_DIR/blobs"

    # `mix setup` MUST run to completion in its own process, separately from
    # `mix phx.server`. Chaining them as `mix do setup + phx.server` looks
    # equivalent and is not: `mix do` runs every task in ONE VM, `ecto.setup`'s
    # `mix run priv/repo/seeds.exs` boots the application, and `phx.server` sets
    # `serve_endpoints` only for an application it starts itself. Chained, the
    # endpoint comes up with `server: false` -- the VM stays alive and looks
    # healthy, the log shows migrations and asset builds succeeding, and nothing
    # ever listens on the port. Verified: chained, no listener on 4000 for ten
    # minutes; `mix phx.server` alone binds it in seconds.
    info "deps, database and assets (quiet unless something fails)"
    if ! (
      cd "$SERVER_DIR"
      MIX_ENV=dev \
      PLAYSTEAD_EXPORT_PATH="$SERVER_DIR/exports" \
      PLAYSTEAD_BLOB_PATH="$SERVER_DIR/blobs" \
        mix setup >"$NATIVE_LOG" 2>&1
    ); then
      printf '\n'
      tail -30 "$NATIVE_LOG" >&2
      die "mix setup failed -- full log: ${NATIVE_LOG#"$REPO"/}"
    fi
    ok "setup complete"

    step "Starting the native server"
    (
      cd "$SERVER_DIR"
      MIX_ENV=dev \
      PLAYSTEAD_EXPORT_PATH="$SERVER_DIR/exports" \
      PLAYSTEAD_BLOB_PATH="$SERVER_DIR/blobs" \
      PLAYSTEAD_SETUP_TOKEN="$SETUP_TOKEN" \
        nohup mix phx.server >>"$NATIVE_LOG" 2>&1 &
      echo $! > "$NATIVE_PIDFILE"
    )
    ok "started (pid $(cat "$NATIVE_PIDFILE")), logging to ${NATIVE_LOG#"$REPO"/}"
  fi

  step "Waiting for the server"
  # 10 minutes: a first containerized boot compiles the whole dependency tree.
  deadline=$((SECONDS + 600))
  until server_responding; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      printf '\n'
      if [ "$MODE" = docker ]; then
        die "server did not come up within 10 minutes. Logs: docker compose -f ${COMPOSE_FILE#"$REPO"/} logs app"
      else
        die "server did not come up within 10 minutes. Logs: tail -50 ${NATIVE_LOG#"$REPO"/}"
      fi
    fi
    # A container that has already exited will never answer; stop waiting on it.
    if [ "$MODE" = docker ] && [ "$(compose ps --status exited --quiet app 2>/dev/null | wc -l | tr -d ' ')" != "0" ]; then
      printf '\n'
      die "the app container exited. Logs: docker compose -f ${COMPOSE_FILE#"$REPO"/} logs app"
    fi
    if [ "$MODE" = native ] && ! kill -0 "$(cat "$NATIVE_PIDFILE" 2>/dev/null)" 2>/dev/null; then
      printf '\n'
      die "the mix server exited. Logs: tail -50 ${NATIVE_LOG#"$REPO"/}"
    fi
    printf '.'
    sleep 2
  done
  printf '\n'
fi
ok "$BASE_URL/healthz is answering"

# ------------------------------------------------------------ owner account

step "Owner account"
case "$(setup_status)" in
  404)
    ok "an owner already exists -- log in at $BASE_URL/log-in"
    ;;
  200)
    warn "no owner yet. Open this and walk the four-step wizard:"
    printf '\n      %s%s/setup%s\n' "$B" "$BASE_URL" "$N"
    printf '      %ssetup token:%s %s\n\n' "$B" "$N" "$SETUP_TOKEN"
    info "the token is pre-set, so no banner is printed -- this is it"
    info "step 3 shows your recovery codes ONCE; save them"
    ;;
  *)
    warn "could not read $BASE_URL/setup -- check the server logs"
    ;;
esac

# -------------------------------------------------------------------- inbox

step "Library"
INBOX="$SERVER_DIR/inbox"
# Mirrors Playstead.Import.Inbox.scan/1 exactly: skip dot-entries (files and
# directories alike), report every other regular file. Matching the server's own
# rule is the point -- a count here that disagreed with what "Preview inbox
# folder" reports would be worse than no count, and an earlier version excluded
# README.md by name, which would now hide a README the OPERATOR put there while
# the server went on reporting it.
rom_count="$(find "$INBOX" -type f -not -path '*/.*' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$rom_count" = "0" ]; then
  warn "inbox is empty: ${INBOX#"$REPO"/}"
  info "copy UNZIPPED ROMs there, then stage them at $BASE_URL/import/sessions"
  info "archives are detected by magic bytes and kept unopened -- a .zip imports but never plays"
  info "only GBA has a shipping adapter, so GBA is the only thing playable today"
else
  ok "$rom_count file(s) in the inbox"
  # Extension-sniffing here is a hint for the developer, not the importer's
  # decision: Playstead.Formats.Archive detects archives by magic bytes and
  # ignores extensions entirely. A correct-looking name proves nothing.
  if find "$INBOX" -type f \( -iname '*.zip' -o -iname '*.7z' -o -iname '*.rar' \) 2>/dev/null | grep -q .; then
    warn "some look like archives -- those import as opaque blobs and cannot be launched"
    info "extract them outside Playstead and re-import; check $BASE_URL/attention"
  fi
  info "stage them at $BASE_URL/import/sessions -> Preview inbox folder -> Stage this folder"
fi

# ------------------------------------------------------------------ pairing

if [ "$DO_PAIR" = true ]; then
  step "Pairing this Mac"
  PAIRED_URL="$(paired_base_url)"
  if [ -n "$PAIRED_URL" ] && [ "$PAIRED_URL" = "$BASE_URL" ]; then
    ok "already paired with $BASE_URL"
    info "re-pair only if the app reports 401 (the device was revoked at $BASE_URL/devices)"
  elif [ -n "$PAIRED_URL" ] && curl --silent --fail --max-time 3 "$PAIRED_URL/healthz" >/dev/null 2>&1; then
    # The credential points somewhere else AND that somewhere else is LIVE. Do
    # not offer to re-pair, and do not call it stale: re-pairing would strand the
    # app's local read model against a server that does not have its library.
    #
    # This is not hypothetical. It happened: the operator's app was correctly
    # paired to their real library at https://localhost:18443 (the deployment
    # stack, up and healthy the whole time), this script called that credential
    # stale, and re-pairing to the empty dev stack left a phantom catalogue of 6
    # titles whose every download 404'd -- because the sync cursor is not scoped
    # to server identity, so the incremental sync silently converged on nothing.
    warn "this Mac is paired to a DIFFERENT server, and that server is up:"
    info "  paired to: $PAIRED_URL   (answering /healthz)"
    info "  this run:  $BASE_URL"
    info "Leaving the pairing alone. Re-pairing here would strand the app's local"
    info "catalogue: it would still list $PAIRED_URL's titles, and every download"
    info "would 404 because this server has never seen those blobs."
    info ""
    info "To use the library it is already paired to:  scripts/dev-up.sh --server $PAIRED_URL"
    info "To deliberately move it here anyway:        playstead-mac/scripts/pair-dev.sh --server $BASE_URL"
  elif [ -n "$PAIRED_URL" ]; then
    warn "the stored credential is for $PAIRED_URL, which is not answering"
    info "pair-dev.sh replaces the stale item; the app would fail against this server"
    answer=""
    ask 'pair with this server now? [y/N]' answer || true
    case "$answer" in
      [yY]*) "$MAC_DIR/scripts/pair-dev.sh" --server "$BASE_URL" \
               || warn "pairing did not complete -- see playstead-mac/docs/LOCAL-DEV.md troubleshooting" ;;
      *) info "later: playstead-mac/scripts/pair-dev.sh --server $BASE_URL" ;;
    esac
  elif [ "$(setup_status)" = "200" ]; then
    warn "skipping: pairing needs an owner account to approve the request"
    info "finish the wizard above, then re-run this script -- it will pick up here"
  else
    warn "this Mac is not paired. The app ships no pairing UI, so the dev script does it."
    info "it prints a code and waits; approve the matching one at $BASE_URL/devices"
    answer=""
    ask 'run it now? [y/N]' answer || true
    case "$answer" in
      [yY]*)
        "$MAC_DIR/scripts/pair-dev.sh" --server "$BASE_URL" \
          || warn "pairing did not complete -- see playstead-mac/docs/LOCAL-DEV.md troubleshooting"
        ;;
      *)
        info "later: playstead-mac/scripts/pair-dev.sh --server $BASE_URL"
        ;;
    esac
  fi
fi

# ------------------------------------------------------------------ Mac app

if [ "$OPEN_XCODE" = true ]; then
  step "Opening Xcode"
  open "$MAC_DIR/Playstead.xcodeproj"
  ok "Playstead.xcodeproj opened -- hit Run"
elif [ "$DO_APP" = true ]; then
  step "Building the Mac app"
  # The project commits DEVELOPMENT_TEAM = REPLACE_WITH_YOUR_TEAM_ID on purpose,
  # so no contributor's real team ID lands in the repo. A plain `xcodebuild
  # build` therefore fails with `No "Mac Development" signing certificate
  # matching team ID "REPLACE_WITH_YOUR_TEAM_ID"` even on a machine with valid
  # identities -- it is looking for a team that does not exist.
  #
  # Default to the same ad-hoc override every CI test layer in this repo already
  # uses (run-mac-verification.sh: CODE_SIGN_IDENTITY=-). It needs no Apple
  # account, no team, and no provisioning profile, so it works on a clean
  # machine. The tradeoff, which Xcode states outright: "Disabling hardened
  # runtime with ad-hoc codesigning." Fine for a local dev run, and not the
  # posture to test D-04 against -- scripts/build-release.sh is that path.
  #
  # Set PLAYSTEAD_DEV_TEAM to a team ID you hold to build with a real Apple
  # Development identity and keep hardened runtime on. `security find-identity
  # -v -p codesigning` lists yours; the team is the parenthesised code.
  if [ -n "${PLAYSTEAD_DEV_TEAM:-}" ]; then
    info "signing with team $PLAYSTEAD_DEV_TEAM (hardened runtime enabled)"
    signing=(CODE_SIGN_STYLE=Automatic "DEVELOPMENT_TEAM=$PLAYSTEAD_DEV_TEAM")
  else
    info "ad-hoc signed, as CI builds it -- no Apple team needed"
    info "hardened runtime is off in this build; set PLAYSTEAD_DEV_TEAM to keep it on"
    signing=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=)
  fi
  # Output to a log, surfaced only on failure. `-quiet` still lets every Swift
  # compiler warning through, and this target emits enough of them to bury the
  # one line that matters -- a successful build should say so in one line, and a
  # failed one should show the errors without the warnings scrolling them away.
  #
  # arch pinned so xcodebuild stops warning that it picked the first of two
  # matching macOS destinations.
  mkdir -p "$MAC_DIR/build"
  if xcodebuild build \
       -project "$MAC_DIR/Playstead.xcodeproj" \
       -scheme Playstead \
       -destination "platform=macOS,arch=$(uname -m)" \
       -derivedDataPath "$DERIVED_DATA" \
       "${signing[@]}" \
       -quiet >"$BUILD_LOG" 2>&1; then
    APP="$DERIVED_DATA/Build/Products/Debug/Playstead.app"
    if [ -d "$APP" ]; then
      ok "built ${APP#"$REPO"/}"

      # `open` on an ALREADY-RUNNING app just activates it -- it does not
      # relaunch, so the process keeps running the previous binary and, worse,
      # the credential it read from the Keychain at ITS launch. After a re-pair
      # that means the app goes on talking to the old server with a credential
      # that no longer exists, issues no sync at all, and the script cheerfully
      # prints "launched". Observed exactly that: same pid across a re-pair,
      # zero /api/v1/changes requests reaching the newly paired server.
      #
      # Quit via AppleScript rather than `pkill`, so the app runs its ordinary
      # termination path (the one that flushes state) instead of being killed.
      # Falls back to a TERM signal, then gives up rather than escalating to
      # KILL -- losing an unflushed save to force a relaunch is not a trade this
      # script gets to make.
      if pgrep -x Playstead >/dev/null 2>&1; then
        old_pid="$(pgrep -x Playstead | head -1)"
        info "an instance is already running (pid $old_pid) -- quitting it so the"
        info "new build and the current credential are the ones that load"
        osascript -e 'quit app "Playstead"' >/dev/null 2>&1 || kill "$old_pid" 2>/dev/null || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
          pgrep -x Playstead >/dev/null 2>&1 || break
          sleep 1
        done
        if pgrep -x Playstead >/dev/null 2>&1; then
          warn "it is still running -- quit Playstead by hand, then re-run this script"
          warn "NOT killing it: an unflushed save is worth more than an automatic relaunch"
        fi
      fi

      if pgrep -x Playstead >/dev/null 2>&1; then
        info "skipped launching; the existing instance is still up"
      else
        open "$APP"
        # Confirm rather than assert: `open` returning 0 only means it was
        # handed off to LaunchServices.
        sleep 2
        if new_pid="$(pgrep -x Playstead | head -1)" && [ -n "$new_pid" ]; then
          ok "launched (pid $new_pid)"
        else
          warn "open succeeded but no Playstead process appeared -- check Console.app"
        fi
      fi
    else
      warn "build reported success but no app at ${APP#"$REPO"/}"
      info "log: ${BUILD_LOG#"$REPO"/}"
    fi
  else
    warn "build failed -- errors only:"
    # Just the error/failure lines. The full log keeps everything.
    grep -E "error:|BUILD FAILED|No signing certificate|xcodebuild: error" "$BUILD_LOG" \
      | head -15 | sed 's/^/      /' || info "      (no error: lines matched; read the log)"
    info "full log: ${BUILD_LOG#"$REPO"/}"
    info "or open it in Xcode: open $MAC_DIR/Playstead.xcodeproj"
  fi

  # Broken window #8. The single most confusing failure on the Play path, and it
  # looks exactly like a hang: AdapterInstaller deliberately preserves the
  # quarantine xattr, Gatekeeper leaves the bundle suspended before it ever
  # runs, and AdapterHost.launch cannot tell that apart from a running emulator
  # -- so the app waits forever with no error. Detect and name it; do not strip
  # the attribute here, because preserving it is a deliberate security posture
  # and clearing it is the operator's call, made once, in Finder.
  #
  # Reports all three outcomes rather than only the bad one. An earlier version
  # printed nothing at all when the emulator was installed and NOT quarantined,
  # which is the good case -- but silence there is indistinguishable from the
  # check never having run, and this is the one advisory most worth trusting.
  step "Emulator adapter"
  mgba_app=""
  [ -d "$ADAPTER_DIR" ] && \
    mgba_app="$(find "$ADAPTER_DIR" -maxdepth 2 -name '*.app' -type d 2>/dev/null | head -1)"

  if [ -z "$mgba_app" ]; then
    warn "not installed -- in the app: Adapter -> Install the pinned adapter"
    info "it downloads mGBA 0.10.5 and checks the DMG against the pin before expanding it"
  elif xattr -p com.apple.quarantine "$mgba_app" >/dev/null 2>&1; then
    warn "installed but STILL QUARANTINED -- Play will appear to hang, with no error"
    info "clear it once by hand in Finder: right-click -> Open -> Open"
    info "$mgba_app"
    info "tracked as broken window #8; see playstead-mac/docs/LOCAL-DEV.md"
  else
    ok "installed and not quarantined -- Play can launch it"
    # The installer records the digest of the archive it verified. Comparing it
    # to the pin turns "something is installed" into "the pinned release is
    # installed", which is the claim that actually matters.
    verify_file="$ADAPTER_DIR/.install-verify.json"
    pin_file="$MAC_DIR/Playstead/Adapter/AdapterPin.json"
    if [ -f "$verify_file" ] && [ -f "$pin_file" ]; then
      installed_digest="$(sed -n 's/.*"archive_sha256"[[:space:]]*:[[:space:]]*"\([0-9a-f]*\)".*/\1/p' "$verify_file" | head -1)"
      pinned_digest="$(sed -n 's/.*"sha256"[[:space:]]*:[[:space:]]*"\([0-9a-f]*\)".*/\1/p' "$pin_file" | head -1)"
      if [ -n "$installed_digest" ] && [ "$installed_digest" = "$pinned_digest" ]; then
        ok "verified archive digest matches AdapterPin.json"
      elif [ -n "$installed_digest" ] && [ -n "$pinned_digest" ]; then
        warn "installed from a DIFFERENT archive than the pin names -- reinstall the pinned adapter"
        info "installed: $installed_digest"
        info "pinned:    $pinned_digest"
      fi
    fi
  fi
fi

# ------------------------------------------------------------------- summary

step "Ready"
printf '  console   %s\n' "$BASE_URL"
printf '  import    %s/import/sessions\n' "$BASE_URL"
printf '  devices   %s/devices\n' "$BASE_URL"
if [ "$MANAGE_STACK" = false ]; then
  printf '  note      this script did not start %s and will not stop it\n' "$BASE_URL"
elif [ "$MODE" = docker ]; then
  printf '  logs      docker compose -f %s logs -f app\n' "${COMPOSE_FILE#"$REPO"/}"
  printf '  stop      scripts/dev-up.sh --down\n'
else
  printf '  logs      tail -f %s\n' "${NATIVE_LOG#"$REPO"/}"
  printf '  stop      scripts/dev-up.sh --down\n'
fi
printf '  state     scripts/dev-up.sh --status\n'
printf '\n'
