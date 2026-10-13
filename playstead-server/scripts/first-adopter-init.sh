#!/usr/bin/env bash
# Create the private first-adopter profile without touching Docker.
set -euo pipefail
set +x
umask 077

root="$(cd "$(dirname "$0")/.." && pwd -P)"
template="$root/.env.first-adopter.example"
config_file="${PLAYSTEAD_FIRST_ADOPTER_ENV_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/playstead/first-adopter/first-adopter.env}"
data_root="${PLAYSTEAD_FIRST_ADOPTER_DATA_ROOT:-$HOME/Playstead-First-Adopter}"
lan_address=""

fail() { printf 'first_adopter_init_%s\n' "$1" >&2; exit 1; }
usage() {
  cat >&2 <<'USAGE'
usage: scripts/first-adopter-init.sh [--config PATH] [--data-root PATH] [--lan-address IPv4]

Creates a private env file and separate inbox, exports, and backups directories.
It does not run Docker. Values and paths are never printed.
USAGE
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --config) [ "$#" -ge 2 ] || usage; config_file="$2"; shift 2 ;;
    --data-root) [ "$#" -ge 2 ] || usage; data_root="$2"; shift 2 ;;
    --lan-address) [ "$#" -ge 2 ] || usage; lan_address="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

for candidate_path in "$config_file" "$data_root"; do
  case "$candidate_path" in *$'\n'*|*$'\r'*) fail path_invalid ;; esac
  [[ "$candidate_path" != *[[:space:]#\$:]* ]] || fail path_contains_unsupported_characters
done
case "$config_file" in /*) ;; *) fail config_path_must_be_absolute ;; esac
case "$data_root" in /*) ;; *) fail data_root_must_be_absolute ;; esac
[ -f "$template" ] && [ ! -L "$template" ] || fail template_unavailable
[ ! -e "$config_file" ] && [ ! -L "$config_file" ] || fail config_already_exists

# Validate paths and existing symlink components before making any directory.
path_json="$(python3 - "$root" "$config_file" "$data_root" 2>/dev/null <<'PY'
import json, os, sys
root, config, data = sys.argv[1:]
def reject_symlink_components(path):
    absolute = os.path.abspath(path)
    current = os.path.sep
    for part in absolute.split(os.path.sep):
        if not part:
            continue
        current = os.path.join(current, part)
        if os.path.islink(current):
            # macOS exposes temporary and system paths through stable aliases.
            if current in ("/var", "/tmp") and os.path.realpath(current) in ("/private/var", "/private/tmp"):
                continue
            raise SystemExit(3)
def canonical_future(path):
    absolute = os.path.abspath(path)
    parent = os.path.dirname(absolute)
    while not os.path.exists(parent):
        next_parent = os.path.dirname(parent)
        if next_parent == parent:
            break
        parent = next_parent
    return os.path.join(os.path.realpath(parent), os.path.relpath(absolute, parent))
for p in (config, os.path.dirname(config), data):
    reject_symlink_components(p)
cfg = canonical_future(config)
cfg_parent = os.path.dirname(cfg)
data_root = canonical_future(data)
checkout = os.path.realpath(root)
def overlaps(a, b):
    return a == b or a.startswith(b + os.sep) or b.startswith(a + os.sep)
if overlaps(cfg, checkout) or overlaps(data_root, checkout) or overlaps(cfg_parent, data_root):
    raise SystemExit(4)
json.dump({"config": cfg, "config_parent": cfg_parent, "data_root": data_root}, sys.stdout)
PY
)" || {
  status=$?
  case "$status" in 3) fail symlink_path ;; 4) fail paths_overlap_checkout_or_each_other ;; *) fail path_validation_failed ;; esac
}
config_file="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["config"])' "$path_json")"
config_parent="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["config_parent"])' "$path_json")"
data_root="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["data_root"])' "$path_json")"
[ ! -e "$config_file" ] && [ ! -L "$config_file" ] || fail config_already_exists
[ ! -e "$data_root" ] && [ ! -L "$data_root" ] || fail data_root_already_exists
[ -d "$(dirname "$data_root")" ] || fail data_root_parent_missing

interface_output="$(ifconfig -a 2>/dev/null)" || fail interface_discovery_failed
addresses="$(printf '%s\n' "$interface_output" | python3 -c '
import ipaddress, re, sys
found=[]
for value in re.findall(r"\binet\s+([0-9.]+)", sys.stdin.read()):
    try:
        address=ipaddress.IPv4Address(value)
    except ipaddress.AddressValueError:
        continue
    if any(address in network for network in (
        ipaddress.IPv4Network("10.0.0.0/8"),
        ipaddress.IPv4Network("172.16.0.0/12"),
        ipaddress.IPv4Network("192.168.0.0/16"),
    )) and value not in found:
        found.append(value)
print("\n".join(found))
')"
if [ -z "$lan_address" ]; then
  count="$(printf '%s\n' "$addresses" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [ "$count" -eq 1 ]; then
    lan_address="$(printf '%s\n' "$addresses" | sed -n '1p')"
  elif [ "$count" -eq 0 ]; then
    fail lan_address_required_no_private_interface_found
  elif [ -t 0 ]; then
    printf 'Choose the server Mac LAN IPv4 address:\n' >&2
    select choice in $addresses; do
      [ -n "${choice:-}" ] && lan_address="$choice" && break
    done
  else
    fail lan_address_required_multiple_private_interfaces_found
  fi
fi
printf '%s\n' "$addresses" | grep -Fxq "$lan_address" || fail lan_address_not_assigned_private_ipv4

db_password="$(openssl rand -hex 32 2>/dev/null)" || fail secret_generation_failed
secret_key="$(openssl rand -hex 64 2>/dev/null)" || fail secret_generation_failed
setup_token="$(openssl rand -hex 32 2>/dev/null)" || fail secret_generation_failed
[ "$db_password" != "$secret_key" ] && [ "$db_password" != "$setup_token" ] && [ "$secret_key" != "$setup_token" ] || fail secret_generation_collision

inbox="$data_root/inbox"
exports="$data_root/exports"
backups="$data_root/backups"
if ! env PLAYSTEAD_INIT_TEMPLATE="$template" PLAYSTEAD_INIT_CONFIG="$config_file" \
  PLAYSTEAD_INIT_INBOX="$inbox" PLAYSTEAD_INIT_EXPORTS="$exports" \
  PLAYSTEAD_INIT_BACKUPS="$backups" PLAYSTEAD_INIT_ADDRESS="$lan_address" \
  PLAYSTEAD_INIT_DB_PASSWORD="$db_password" PLAYSTEAD_INIT_SECRET_KEY="$secret_key" \
  PLAYSTEAD_INIT_SETUP_TOKEN="$setup_token" python3 - 2>/dev/null <<'PY'
import os, pathlib, re
template = pathlib.Path(os.environ["PLAYSTEAD_INIT_TEMPLATE"]).read_text()
values = {
    "POSTGRES_PASSWORD": os.environ["PLAYSTEAD_INIT_DB_PASSWORD"],
    "DATABASE_URL": "ecto://playstead_owner:" + os.environ["PLAYSTEAD_INIT_DB_PASSWORD"] + "@db/playstead_owner",
    "SECRET_KEY_BASE": os.environ["PLAYSTEAD_INIT_SECRET_KEY"],
    "PLAYSTEAD_SETUP_TOKEN": os.environ["PLAYSTEAD_INIT_SETUP_TOKEN"],
    "PHX_HOST": os.environ["PLAYSTEAD_INIT_ADDRESS"],
    "PLAYSTEAD_CADDY_SITE_ADDRESS": os.environ["PLAYSTEAD_INIT_ADDRESS"],
    "PLAYSTEAD_BIND_ADDRESS": os.environ["PLAYSTEAD_INIT_ADDRESS"],
    "PLAYSTEAD_INBOX_HOST_PATH": os.environ["PLAYSTEAD_INIT_INBOX"],
    "PLAYSTEAD_EXPORT_HOST_PATH": os.environ["PLAYSTEAD_INIT_EXPORTS"],
    "PLAYSTEAD_BACKUP_HOST_PATH": os.environ["PLAYSTEAD_INIT_BACKUPS"],
}
for key, value in values.items():
    pattern = re.compile(r"(?m)^" + re.escape(key) + r"=.*$")
    template, count = pattern.subn(lambda _: key + "=" + value, template)
    if count != 1:
        raise SystemExit(2)
path = pathlib.Path(os.environ["PLAYSTEAD_INIT_CONFIG"])
path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
os.chmod(path.parent, 0o700)
data_root = pathlib.Path(os.environ["PLAYSTEAD_INIT_INBOX"]).parent
data_root.mkdir(mode=0o700)
for directory in (pathlib.Path(os.environ["PLAYSTEAD_INIT_INBOX"]),
                  pathlib.Path(os.environ["PLAYSTEAD_INIT_EXPORTS"]),
                  pathlib.Path(os.environ["PLAYSTEAD_INIT_BACKUPS"])):
    directory.mkdir(mode=0o700)
    os.chmod(directory, 0o700)
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
try:
    with os.fdopen(fd, "w") as output:
        output.write(template)
finally:
    os.chmod(path, 0o600)
PY
then
  fail setup_write_failed
fi
printf 'first_adopter_initialized config=private data=inbox,exports,backups secrets=generated lan=selected\n'
