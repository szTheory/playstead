#!/usr/bin/env bash
set -euo pipefail

server="$(cd "$(dirname "$0")/../.." && pwd -P)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/playstead-port-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/private" "$tmp/data/inbox" "$tmp/data/exports" "$tmp/data/backups"
config="$tmp/private/first-adopter.env"
cat > "$config" <<EOF
POSTGRES_USER=playstead_owner
POSTGRES_PASSWORD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
POSTGRES_DB=playstead_owner
DATABASE_URL=ecto://playstead_owner:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa@db/playstead_owner
SECRET_KEY_BASE=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
PLAYSTEAD_SETUP_TOKEN=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
PHX_HOST=192.168.10.40
PLAYSTEAD_DOMAIN=
PLAYSTEAD_CADDY_SITE_ADDRESS=192.168.10.40
PLAYSTEAD_BIND_ADDRESS=192.168.10.40
PLAYSTEAD_HTTP_PORT=8080
PLAYSTEAD_HTTPS_PORT=8443
PLAYSTEAD_INBOX_HOST_PATH=$tmp/data/inbox
PLAYSTEAD_EXPORT_HOST_PATH=$tmp/data/exports
PLAYSTEAD_BACKUP_HOST_PATH=$tmp/data/backups
EOF
chmod 600 "$config"
export FAKE_CONFIG_JSON="$tmp/compose-config.json"
export FAKE_DOCKER_LOG="$tmp/docker.log"
python3 - "$FAKE_CONFIG_JSON" <<'PY'
import json, sys
project = "playstead-first-adopter"
json.dump({
    "services": {
        "app": {}, "db": {},
        "caddy": {"ports": [
            {"host_ip": "192.168.10.40", "published": "8080", "target": 8080},
            {"host_ip": "192.168.10.40", "published": "8443", "target": 8443},
        ]},
    },
    "volumes": {}, "networks": {"default": {"name": project + "_default"}},
}, open(sys.argv[1], "w"))
PY
cat > "$tmp/bin/docker" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$FAKE_DOCKER_LOG"
case "$1 $2" in
  'compose --env-file')
    case " $* " in *' config --format json '*) cat "$FAKE_CONFIG_JSON" ;; *) exit 0 ;; esac ;;
  'compose version'|'info '|'ps -aq'|'volume ls') exit 0 ;;
  'network ls')
    case "$*" in
      *"--format {{.Name}}"*) printf 'playstead-first-adopter_default\n' ;;
      *) printf 'fake-network-id-not-name\n' ;;
    esac
    ;;
  *) exit 90 ;;
esac
SH
cat > "$tmp/bin/ifconfig" <<'SH'
#!/bin/sh
printf 'en0: flags=8863\n\tinet 192.168.10.40 netmask 0xffffff00\n'
SH
cat > "$tmp/bin/lsof" <<'SH'
#!/bin/sh
case "$FAKE_LISTENER_MODE" in
  loopback) printf 'p100\nf3\nn127.0.0.1:8080\n' ;;
  exact) printf 'p100\nf3\nn192.168.10.40:8080\n' ;;
  wildcard) printf 'p100\nf3\nn*:8080\n' ;;
  wildcard_ipv4) printf 'p100\nf3\nn0.0.0.0:8080\n' ;;
  other_port) printf 'p100\nf3\nn192.168.10.40:9000\n' ;;
  *) exit 1 ;;
esac
SH
chmod +x "$tmp/bin/docker" "$tmp/bin/ifconfig" "$tmp/bin/lsof"
export PATH="$tmp/bin:$PATH"

export FAKE_LISTENER_MODE=loopback
output="$("$server/scripts/first-adopter-compose.sh" --env-file "$config" preflight)"
[[ "$output" == preflight_ok* ]]

export FAKE_LISTENER_MODE=other_port
output="$("$server/scripts/first-adopter-compose.sh" --env-file "$config" preflight)"
[[ "$output" == preflight_ok* ]]

for mode in exact wildcard wildcard_ipv4; do
  export FAKE_LISTENER_MODE="$mode"
  if output="$("$server/scripts/first-adopter-compose.sh" --env-file "$config" preflight 2>&1)"; then
    printf 'expected %s listener to block preflight\n' "$mode" >&2
    exit 1
  fi
  [[ "$output" == first_adopter_host_port_occupied ]]
done

! grep -Eq '(^| )(up|down|run|build|rm|stop|start|restart|kill|prune|cp)( |$)' "$FAKE_DOCKER_LOG"
printf 'first-adopter-compose port tests passed\n'
