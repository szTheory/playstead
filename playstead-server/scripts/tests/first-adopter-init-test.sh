#!/usr/bin/env bash
set -euo pipefail

server="$(cd "$(dirname "$0")/../.." && pwd -P)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/playstead-init-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
fake_bin="$tmp/fake-bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/ifconfig" <<'SH'
#!/bin/sh
cat "$FAKE_IFCONFIG_OUTPUT"
SH
cat > "$fake_bin/openssl" <<'SH'
#!/bin/sh
[ "$1" = rand ] && [ "$2" = -hex ] || exit 90
state="$FAKE_SECRET_STATE"
n=0
[ ! -f "$state" ] || n="$(cat "$state")"
n=$((n + 1))
printf '%s' "$n" > "$state"
case "$n" in 1) char=a ;; 2) char=b ;; 3) char=c ;; *) char=z ;; esac
length=$(( $3 * 2 ))
i=0
while [ "$i" -lt "$length" ]; do printf '%s' "$char"; i=$((i + 1)); done
printf '\n'
SH
cat > "$fake_bin/docker" <<'SH'
#!/bin/sh
printf 'docker was called\n' >> "$FAKE_DOCKER_LOG"
exit 99
SH
chmod +x "$fake_bin/ifconfig" "$fake_bin/openssl" "$fake_bin/docker"

export PATH="$fake_bin:$PATH"
export FAKE_IFCONFIG_OUTPUT="$tmp/interfaces"
export FAKE_SECRET_STATE="$tmp/secret-state"
export FAKE_DOCKER_LOG="$tmp/docker-log"
printf 'en0: flags=8863\n    inet 192.168.10.40 netmask 0xffffff00\n    inet 127.0.0.1 netmask 0xff000000\n' > "$FAKE_IFCONFIG_OUTPUT"

config="$tmp/private/config/first-adopter.env"
data="$tmp/private-data"
output="$("$server/scripts/first-adopter-init.sh" --config "$config" --data-root "$data")"
[[ "$output" == first_adopter_initialized* ]]
[[ "$output" != *"$tmp"* ]]
[[ -f "$config" && -d "$data/inbox" && -d "$data/exports" && -d "$data/backups" ]]
python3 - "$config" "$data" <<'PY'
import os, pathlib, sys
config, data = map(pathlib.Path, sys.argv[1:])
assert os.stat(config).st_mode & 0o777 == 0o600
assert os.stat(config.parent).st_mode & 0o777 == 0o700
assert os.stat(data).st_mode & 0o777 == 0o700
values = dict(line.split("=", 1) for line in config.read_text().splitlines() if "=" in line and not line.startswith("#"))
assert values["POSTGRES_PASSWORD"] == values["DATABASE_URL"].split("://playstead_owner:", 1)[1].split("@", 1)[0]
assert len(values["POSTGRES_PASSWORD"]) == 64
assert len(values["SECRET_KEY_BASE"]) == 128
assert len(values["PLAYSTEAD_SETUP_TOKEN"]) == 64
assert len({values["POSTGRES_PASSWORD"], values["SECRET_KEY_BASE"], values["PLAYSTEAD_SETUP_TOKEN"]}) == 3
assert values["PHX_HOST"] == values["PLAYSTEAD_CADDY_SITE_ADDRESS"] == values["PLAYSTEAD_BIND_ADDRESS"] == "192.168.10.40"
assert values["PLAYSTEAD_INBOX_HOST_PATH"] == os.path.realpath(data / "inbox")
assert values["PLAYSTEAD_EXPORT_HOST_PATH"] == os.path.realpath(data / "exports")
assert values["PLAYSTEAD_BACKUP_HOST_PATH"] == os.path.realpath(data / "backups")
PY

before="$(shasum -a 256 "$config" | awk '{print $1}')"
if "$server/scripts/first-adopter-init.sh" --config "$config" --data-root "$tmp/second" >/dev/null 2>&1; then
  echo 'expected repeat-run refusal' >&2; exit 1
fi
after="$(shasum -a 256 "$config" | awk '{print $1}')"
[[ "$before" == "$after" ]]

mkdir "$tmp/existing-data"
if "$server/scripts/first-adopter-init.sh" --config "$tmp/no-config/first-adopter.env" --data-root "$tmp/existing-data" >/dev/null 2>&1; then
  echo 'expected existing data root refusal' >&2; exit 1
fi
[[ ! -e "$tmp/no-config" ]]

if "$server/scripts/first-adopter-init.sh" --config "$tmp/collision.env" --data-root "$server" >/dev/null 2>&1; then
  echo 'expected checkout collision refusal' >&2; exit 1
fi
[[ ! -e "$tmp/collision.env" ]]

mkdir "$tmp/symlink-target"
ln -s "$tmp/symlink-target" "$tmp/symlink-parent"
if "$server/scripts/first-adopter-init.sh" --config "$tmp/symlink-config.env" --data-root "$tmp/symlink-parent/symlink-data" >/dev/null 2>&1; then
  echo 'expected symlink data root refusal' >&2; exit 1
fi
[[ ! -e "$tmp/symlink-config.env" ]]

if "$server/scripts/first-adopter-init.sh" --config "$tmp/invalid-address.env" --data-root "$tmp/invalid-address-data" --lan-address 203.0.113.22 >/dev/null 2>&1; then
  echo 'expected unassigned address refusal' >&2; exit 1
fi
[[ ! -e "$tmp/invalid-address-data" ]]

printf 'en0: inet 192.168.10.40\nen1: inet 10.0.0.8\n' > "$FAKE_IFCONFIG_OUTPUT"
if "$server/scripts/first-adopter-init.sh" --config "$tmp/ambiguous.env" --data-root "$tmp/ambiguous-data" >/dev/null 2>&1; then
  echo 'expected ambiguous address refusal in noninteractive mode' >&2; exit 1
fi
[[ ! -e "$tmp/ambiguous-data" ]]

printf 'en0: inet 127.0.0.1\n' > "$FAKE_IFCONFIG_OUTPUT"
if "$server/scripts/first-adopter-init.sh" --config "$tmp/no-private.env" --data-root "$tmp/no-private-data" >/dev/null 2>&1; then
  echo 'expected no-private-address refusal' >&2; exit 1
fi
[[ ! -e "$tmp/no-private-data" ]]

[[ ! -e "$FAKE_DOCKER_LOG" ]]
printf 'first-adopter-init isolated tests passed\n'
