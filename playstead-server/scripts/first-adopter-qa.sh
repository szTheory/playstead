#!/usr/bin/env bash
# Redacted first-adopter configuration and live-stack QA. Never mutates Docker.
set -euo pipefail
set +x

root="$(cd "$(dirname "$0")/.." && pwd -P)"
project="playstead-first-adopter"
env_file="${PLAYSTEAD_FIRST_ADOPTER_ENV_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/playstead/first-adopter/first-adopter.env}"
ca_file=""
mode="config"
failures=0

fail() { printf 'first_adopter_qa configuration_isolation=FAIL reason=%s\n' "$1"; exit 1; }
usage() {
  cat >&2 <<'USAGE'
usage: scripts/first-adopter-qa.sh [--env-file PRIVATE_FILE] [--ca-file PUBLIC_CA_FILE] [config|live]

config validates the private env and resolved Compose isolation without requiring
running services. live additionally inspects the exact running profile and checks
app health and HTTPS using the supplied public Caddy root certificate.
All reported owner-specific values are redacted. Docker is queried read-only.
USAGE
  exit 2
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --env-file) [ "$#" -ge 2 ] || usage; env_file="$2"; shift 2 ;;
    --ca-file) [ "$#" -ge 2 ] || usage; ca_file="$2"; shift 2 ;;
    config|live) [ "$mode" = config ] || usage; mode="$1"; shift ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

case "$env_file" in /*) ;; *) fail private_config_path_invalid ;; esac
[ -f "$env_file" ] && [ ! -L "$env_file" ] || fail private_config_missing
env_real="$(cd "$(dirname "$env_file")" && pwd -P)/$(basename "$env_file")"
case "$env_real" in "$root"|"$root"/*) fail private_config_inside_checkout ;; esac
python3 - "$env_real" <<'PY' || fail private_config_permissions_too_open
import os, pathlib, sys
if os.stat(sys.argv[1]).st_mode & 0o077:
    raise SystemExit(1)
PY

get_value() { sed -n "s/^$1=//p" "$env_real" | tail -n 1; }
for key in POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB DATABASE_URL SECRET_KEY_BASE \
  PLAYSTEAD_SETUP_TOKEN PHX_HOST PLAYSTEAD_CADDY_SITE_ADDRESS PLAYSTEAD_BIND_ADDRESS \
  PLAYSTEAD_HTTP_PORT PLAYSTEAD_HTTPS_PORT PLAYSTEAD_INBOX_HOST_PATH \
  PLAYSTEAD_EXPORT_HOST_PATH PLAYSTEAD_BACKUP_HOST_PATH; do
  value="$(get_value "$key")"
  [ -n "$value" ] || fail required_setting_missing
  case "$value" in *REPLACE*|*CHANGEME*|*EXAMPLE*) fail unresolved_example_setting ;; esac
done
bind_address="$(get_value PLAYSTEAD_BIND_ADDRESS)"
http_port="$(get_value PLAYSTEAD_HTTP_PORT)"
https_port="$(get_value PLAYSTEAD_HTTPS_PORT)"
[[ "$bind_address" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || fail bind_address_invalid
[[ "$http_port" =~ ^[0-9]{1,5}$ ]] && [ "$http_port" -ge 1 ] && [ "$http_port" -le 65535 ] || fail http_port_invalid
[[ "$https_port" =~ ^[0-9]{1,5}$ ]] && [ "$https_port" -ge 1 ] && [ "$https_port" -le 65535 ] || fail https_port_invalid
[ "$(get_value PHX_HOST)" = "$bind_address" ] && \
  [ "$(get_value PLAYSTEAD_CADDY_SITE_ADDRESS)" = "$bind_address" ] && \
  [ -z "$(get_value PLAYSTEAD_DOMAIN)" ] || fail lan_tls_identity_mismatch

inbox="$(get_value PLAYSTEAD_INBOX_HOST_PATH)"
exports="$(get_value PLAYSTEAD_EXPORT_HOST_PATH)"
backups="$(get_value PLAYSTEAD_BACKUP_HOST_PATH)"
for path in "$inbox" "$exports" "$backups"; do
  case "$path" in /*) ;; *) fail host_path_not_absolute ;; esac
  [ -d "$path" ] && [ ! -L "$path" ] || fail host_path_missing_or_symlink
  real="$(cd "$path" && pwd -P)"
  case "$real" in "$root"|"$root"/*) fail host_path_inside_checkout ;; esac
done
python3 - "$inbox" "$exports" "$backups" <<'PY' || fail host_paths_overlap
import os, sys
paths=[os.path.realpath(p) for p in sys.argv[1:]]
if len(set(paths)) != 3:
    raise SystemExit(1)
for i, a in enumerate(paths):
    for b in paths[i+1:]:
        if a.startswith(b + os.sep) or b.startswith(a + os.sep):
            raise SystemExit(1)
PY

compose=(docker compose --env-file "$env_real" --project-name "$project" \
  -f "$root/docker-compose.yml" -f "$root/docker-compose.backup.yml")
resolved="$("${compose[@]}" config --format json 2>/dev/null)" || fail compose_configuration_unavailable
if ! printf '%s' "$resolved" | env \
  PLAYSTEAD_QA_ROOT="$root" PLAYSTEAD_QA_INBOX="$inbox" \
  PLAYSTEAD_QA_EXPORTS="$exports" PLAYSTEAD_QA_BACKUPS="$backups" \
  PLAYSTEAD_QA_ADDRESS="$bind_address" PLAYSTEAD_QA_HTTP_PORT="$http_port" \
  PLAYSTEAD_QA_HTTPS_PORT="$https_port" python3 -c '
import json, os, sys
cfg=json.load(sys.stdin)
expected={"app", "db", "caddy"}
if set(cfg.get("services", {})) != expected: raise SystemExit(1)
root=os.path.realpath(os.environ["PLAYSTEAD_QA_ROOT"])
binds={
 "app": {os.path.realpath(os.environ["PLAYSTEAD_QA_INBOX"]):"/app/inbox",os.path.realpath(os.environ["PLAYSTEAD_QA_EXPORTS"]):"/app/exports",os.path.realpath(os.environ["PLAYSTEAD_QA_BACKUPS"]):"/app/backups"},
 "db": {},
 "caddy": {os.path.realpath(os.path.join(root,"Caddyfile")):"/etc/caddy/Caddyfile"},
}
volumes={
 "app": {"playstead_blobs":"/app/blobs","caddy_data":"/caddy_data"},
 "db": {"playstead_db":"/var/lib/postgresql/data"},
 "caddy": {"caddy_data":"/data","caddy_config":"/config"},
}
for name, service in cfg["services"].items():
    actual_binds={os.path.realpath(m["source"]):m["target"] for m in service.get("volumes",[]) if m.get("type")=="bind"}
    actual_volumes={m["source"]:m["target"] for m in service.get("volumes",[]) if m.get("type")=="volume"}
    if actual_binds != binds[name] or actual_volumes != volumes[name]: raise SystemExit(2)
resolved_volumes={item.get("name","") for item in cfg.get("volumes",{}).values()}
if resolved_volumes != {"playstead-first-adopter_"+name for name in ("playstead_db","playstead_blobs","caddy_data","caddy_config")}: raise SystemExit(3)
resolved_networks={item.get("name","") for item in cfg.get("networks",{}).values()}
if resolved_networks != {"playstead-first-adopter_default"}: raise SystemExit(4)
ports=[]
for name,service in cfg["services"].items():
    for port in service.get("ports",[]):
        if name != "caddy": raise SystemExit(5)
        if port.get("host_ip") != os.environ["PLAYSTEAD_QA_ADDRESS"]: raise SystemExit(6)
        if str(port.get("published")) != str(port.get("target")): raise SystemExit(7)
        ports.append(str(port.get("published")))
if sorted(ports) != sorted((os.environ["PLAYSTEAD_QA_HTTP_PORT"],os.environ["PLAYSTEAD_QA_HTTPS_PORT"])): raise SystemExit(8)
' 2>/dev/null; then
  fail resolved_compose_isolation_mismatch
fi
printf 'first_adopter_qa configuration_isolation=PASS evidence=automated project=%s\n' "$project"
if [ "$mode" = config ]; then
  printf 'first_adopter_qa profile_resource_identity=NOT_RUN evidence=automated mode=config\n'
  printf 'first_adopter_qa app_readiness=NOT_RUN evidence=automated mode=config\n'
  printf 'first_adopter_qa https_response=NOT_RUN evidence=automated mode=config\n'
  printf 'first_adopter_qa cli_tls_chain_validation=NOT_RUN evidence=automated mode=config\n'
  printf 'first_adopter_qa macOS_keychain_trust=NOT_RUN reason=mode_config\n'
  exit 0
fi

container_ids="$("${compose[@]}" ps -q app db caddy 2>/dev/null)" || {
  printf 'first_adopter_qa profile_resource_identity=FAIL evidence=automated\n'; exit 1;
}
if [ -z "$container_ids" ]; then
  printf 'first_adopter_qa profile_resource_identity=NOT_RUN reason=profile_stopped_or_not_started\n'
  printf 'first_adopter_qa app_readiness=NOT_RUN reason=profile_stopped_or_not_started\n'
  printf 'first_adopter_qa https_response=NOT_RUN reason=profile_stopped_or_not_started\n'
  printf 'first_adopter_qa cli_tls_chain_validation=NOT_RUN reason=profile_stopped_or_not_started\n'
  printf 'first_adopter_qa macOS_keychain_trust=NOT_RUN reason=profile_stopped_or_not_started\n'
  exit 3
fi
ids_file="$(mktemp "${TMPDIR:-/tmp}/playstead-first-adopter-qa.XXXXXX")"
trap 'rm -f "$ids_file"' EXIT
printf '%s\n' "$container_ids" | sed '/^$/d' > "$ids_file"
count="$(wc -l < "$ids_file" | tr -d ' ')"
[ "$count" -eq 3 ] || { printf 'first_adopter_qa profile_resource_identity=FAIL evidence=automated\n'; exit 1; }

profile_ok=1
app_ready=0
for service in app db caddy; do
  id="$("${compose[@]}" ps -q "$service" 2>/dev/null)" || profile_ok=0
  [ -n "$id" ] || { profile_ok=0; continue; }
  detail="$(docker inspect --format '{{json .}}' "$id" 2>/dev/null)" || { profile_ok=0; continue; }
if printf '%s' "$detail" | env PLAYSTEAD_QA_PROJECT="$project" PLAYSTEAD_QA_SERVICE="$service" \
    PLAYSTEAD_QA_APP_ID="$id" PLAYSTEAD_QA_ROOT="$root" \
    PLAYSTEAD_QA_INBOX="$inbox" PLAYSTEAD_QA_EXPORTS="$exports" PLAYSTEAD_QA_BACKUPS="$backups" \
    python3 -c '
import json, os, sys
x=json.load(sys.stdin)
labels=x.get("Config",{}).get("Labels",{}) or {}
if labels.get("com.docker.compose.project") != os.environ["PLAYSTEAD_QA_PROJECT"]: raise SystemExit(1)
if labels.get("com.docker.compose.service") != os.environ["PLAYSTEAD_QA_SERVICE"]: raise SystemExit(1)
expected=os.path.realpath(os.path.join(os.environ["PLAYSTEAD_QA_ROOT"],"docker-compose.yml"))+","+os.path.realpath(os.path.join(os.environ["PLAYSTEAD_QA_ROOT"],"docker-compose.backup.yml"))
if labels.get("com.docker.compose.project.config_files") != expected: raise SystemExit(1)
state=x.get("State",{})
if state.get("Status") != "running": raise SystemExit(1)
service=os.environ["PLAYSTEAD_QA_SERVICE"]
if service == "app":
    expected_binds={os.path.realpath(os.environ["PLAYSTEAD_QA_INBOX"]):"/app/inbox",os.path.realpath(os.environ["PLAYSTEAD_QA_EXPORTS"]):"/app/exports",os.path.realpath(os.environ["PLAYSTEAD_QA_BACKUPS"]):"/app/backups"}
    expected_volumes={"playstead-first-adopter_playstead_blobs":"/app/blobs","playstead-first-adopter_caddy_data":"/caddy_data"}
elif service == "db":
    expected_binds={}
    expected_volumes={"playstead-first-adopter_playstead_db":"/var/lib/postgresql/data"}
else:
    expected_binds={os.path.realpath(os.path.join(os.environ["PLAYSTEAD_QA_ROOT"],"Caddyfile")):"/etc/caddy/Caddyfile"}
    expected_volumes={"playstead-first-adopter_caddy_data":"/data","playstead-first-adopter_caddy_config":"/config"}
def host_source(path):
    # Docker Desktop for macOS may expose a host path as /host_mnt/<host-path>
    # in `docker inspect`, while Compose config reports the native Mac path.
    if path.startswith("/host_mnt/"):
        path=path[len("/host_mnt"):]
    return os.path.realpath(path)
binds={host_source(m.get("Source","")):m.get("Destination") for m in x.get("Mounts",[]) if m.get("Type")=="bind"}
volumes={m.get("Name"):m.get("Destination") for m in x.get("Mounts",[]) if m.get("Type")=="volume"}
if binds != expected_binds or volumes != expected_volumes: raise SystemExit(2)
' >/dev/null 2>&1; then
  :
else
    profile_ok=0
  fi
done
app_id="$("${compose[@]}" ps -q app 2>/dev/null)" || profile_ok=0
if [ -n "$app_id" ]; then
  app_detail="$(docker inspect --format '{{json .}}' "$app_id" 2>/dev/null)" || profile_ok=0
  if printf '%s' "$app_detail" | python3 -c 'import json,sys; raise SystemExit(0 if json.load(sys.stdin).get("State",{}).get("Health",{}).get("Status")=="healthy" else 1)' >/dev/null 2>&1; then
    app_ready=1
  fi
fi
if [ "$profile_ok" -eq 1 ]; then
  printf 'first_adopter_qa profile_resource_identity=PASS evidence=automated services=app,db,caddy\n'
else
  printf 'first_adopter_qa profile_resource_identity=FAIL evidence=automated\n'
fi
if [ "$app_ready" -eq 1 ]; then
  printf 'first_adopter_qa app_readiness=PASS evidence=automated health=healthy\n'
else
  printf 'first_adopter_qa app_readiness=FAIL evidence=automated\n'
fi
if [ "$profile_ok" -ne 1 ]; then
  printf 'first_adopter_qa https_response=NOT_RUN reason=profile_resource_identity_failed\n'
  printf 'first_adopter_qa cli_tls_chain_validation=NOT_RUN reason=profile_resource_identity_failed\n'
  printf 'first_adopter_qa macOS_keychain_trust=NOT_RUN reason=profile_resource_identity_failed\n'
  exit 1
fi

if [ "$app_ready" -ne 1 ] || [ -z "$ca_file" ] || [ ! -f "$ca_file" ] || [ -L "$ca_file" ]; then
  printf 'first_adopter_qa https_response=NOT_RUN reason=app_unhealthy_or_ca_unavailable\n'
  printf 'first_adopter_qa cli_tls_chain_validation=NOT_RUN reason=app_unhealthy_or_ca_unavailable\n'
  printf 'first_adopter_qa macOS_keychain_trust=NOT_RUN reason=app_unhealthy_or_ca_unavailable\n'
  [ "$profile_ok" -eq 1 ] && [ "$app_ready" -eq 1 ] && exit 3
  exit 1
fi
case "$ca_file" in /*) ;; *) printf 'first_adopter_qa https_response=FAIL reason=ca_path_invalid\n'; exit 1 ;; esac
case "$ca_file" in "$root"|"$root"/*) printf 'first_adopter_qa https_response=FAIL reason=ca_inside_checkout\n'; exit 1 ;; esac
fingerprint="$(openssl x509 -in "$ca_file" -noout -fingerprint -sha256 2>/dev/null)" || fingerprint=""
if [ -z "$fingerprint" ]; then
  printf 'first_adopter_qa cli_tls_chain_validation=FAIL evidence=automated\n'
  printf 'first_adopter_qa macOS_keychain_trust=NOT_RUN reason=ca_fingerprint_unavailable\n'
  printf 'first_adopter_qa https_response=NOT_RUN reason=ca_fingerprint_unavailable\n'
  exit 1
fi
curl_ok=0
if status="$(curl --noproxy '*' --silent --show-error --output /dev/null --write-out '%{http_code}' \
  --connect-timeout 3 --max-time 8 --cacert "$ca_file" \
  "https://${bind_address}:${https_port}/healthz" 2>/dev/null)"; then
  curl_ok=1
else
  status=""
fi
if [ "$status" = 200 ]; then
  printf 'first_adopter_qa https_response=PASS evidence=automated status=200\n'
else
  printf 'first_adopter_qa https_response=FAIL evidence=automated\n'
fi
if [ "$curl_ok" -eq 1 ]; then
  printf 'first_adopter_qa cli_tls_chain_validation=PASS evidence=automated fingerprint=available_redacted\n'
else
  printf 'first_adopter_qa cli_tls_chain_validation=FAIL evidence=automated\n'
fi
keychain_ok=0
if command -v security >/dev/null 2>&1; then
  if security verify-cert "https://${bind_address}:${https_port}/healthz" >/dev/null 2>&1; then
    keychain_ok=1
    printf 'first_adopter_qa macOS_keychain_trust=PASS evidence=automated\n'
  else
    printf 'first_adopter_qa macOS_keychain_trust=FAIL evidence=automated\n'
  fi
else
  printf 'first_adopter_qa macOS_keychain_trust=NOT_RUN reason=macos_security_unavailable\n'
fi
if [ "$status" != 200 ] || [ "$curl_ok" -ne 1 ] || { command -v security >/dev/null 2>&1 && [ "$keychain_ok" -ne 1 ]; }; then
  exit 1
fi
