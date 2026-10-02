#!/usr/bin/env bash
# Guarded local profile for personal first-adopter data. Never targets other
# Compose projects and intentionally has no volume-removal or prune command.
set -euo pipefail
set +x

root="$(cd "$(dirname "$0")/.." && pwd -P)"
project="playstead-first-adopter"
env_file="${PLAYSTEAD_FIRST_ADOPTER_ENV_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/playstead/first-adopter/first-adopter.env}"
command_name=""

fail() {
  printf 'first_adopter_%s\n' "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
usage: scripts/first-adopter-compose.sh [--env-file PRIVATE_FILE] COMMAND

Commands: preflight, up, ps, logs [SERVICE...], root-ca OUTPUT_FILE, down, backup --full,
          backup --incremental --parent-receipt RECEIPT_ID
The project identity is fixed to playstead-first-adopter.
USAGE
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env-file)
      [ "$#" -ge 2 ] || usage
      env_file="$2"
      shift 2
      ;;
    preflight|up|ps|logs|root-ca|down|backup)
      [ -z "$command_name" ] || usage
      command_name="$1"
      shift
      break
      ;;
    *) usage ;;
  esac
done
[ -n "$command_name" ] || usage

case "$env_file" in
  /*) ;;
  *) fail env_file_must_be_absolute ;;
esac
[ -f "$env_file" ] && [ ! -L "$env_file" ] || fail env_file_missing_or_symlink
env_real="$(cd "$(dirname "$env_file")" && pwd -P)/$(basename "$env_file")"
case "$env_real" in
  "$root"|"$root"/*) fail env_file_must_be_outside_checkout ;;
esac
mode="$(stat -f '%Lp' "$env_real" 2>/dev/null)" || fail env_file_mode_unavailable
(( (8#$mode & 077) == 0 )) || fail env_file_permissions_too_open

# Do not source the secret-bearing file. Docker Compose reads it directly.
for key in POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB DATABASE_URL SECRET_KEY_BASE \
  PLAYSTEAD_SETUP_TOKEN PHX_HOST PLAYSTEAD_CADDY_SITE_ADDRESS PLAYSTEAD_BIND_ADDRESS \
  PLAYSTEAD_HTTP_PORT PLAYSTEAD_HTTPS_PORT PLAYSTEAD_INBOX_HOST_PATH \
  PLAYSTEAD_EXPORT_HOST_PATH PLAYSTEAD_BACKUP_HOST_PATH; do
  value="$(sed -n "s/^${key}=//p" "$env_real" | tail -n 1)"
  [ -n "$value" ] || fail required_setting_missing
  case "$value" in
    *REPLACE*|*CHANGEME*|*EXAMPLE*) fail unresolved_example_setting ;;
  esac
done

compose=(docker compose --env-file "$env_real" --project-name "$project" \
  -f "$root/docker-compose.yml" -f "$root/docker-compose.backup.yml")

check_project_resources() {
  expected_config="$root/docker-compose.yml,$root/docker-compose.backup.yml"
  containers="$(docker ps -aq --filter "label=com.docker.compose.project=$project" 2>/dev/null)" || fail resource_inspection_failed
  for id in $containers; do
    [ -n "$id" ] || continue
    labels="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project" }}|{{ index .Config.Labels "com.docker.compose.project.config_files" }}|{{ index .Config.Labels "com.docker.compose.service" }}' "$id" 2>/dev/null)" || fail resource_inspection_failed
    case "$labels" in
      "$project|$expected_config|app"|"$project|$expected_config|db"|"$project|$expected_config|caddy") ;;
      *) fail unexpected_project_container ;;
    esac
  done
  for kind in volume network; do
    resources="$(docker "$kind" ls --format '{{.Name}}' --filter "label=com.docker.compose.project=$project" 2>/dev/null)" || fail resource_inspection_failed
    while IFS= read -r resource; do
      [ -n "$resource" ] || continue
      case "$kind:$resource" in
        volume:"$project"_playstead_db|volume:"$project"_playstead_blobs|volume:"$project"_caddy_data|volume:"$project"_caddy_config|network:"$project"_default) ;;
        *) fail unexpected_project_resource ;;
      esac
    done <<< "$resources"
  done
}

read_only_preflight() {
  docker compose version >/dev/null 2>&1 || fail compose_unavailable
  docker info >/dev/null 2>&1 || fail docker_unavailable

  bind_address="$(sed -n 's/^PLAYSTEAD_BIND_ADDRESS=//p' "$env_real" | tail -n 1)"
  [[ "$bind_address" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || fail bind_address_invalid
  phx_host="$(sed -n 's/^PHX_HOST=//p' "$env_real" | tail -n 1)"
  caddy_address="$(sed -n 's/^PLAYSTEAD_CADDY_SITE_ADDRESS=//p' "$env_real" | tail -n 1)"
  domain="$(sed -n 's/^PLAYSTEAD_DOMAIN=//p' "$env_real" | tail -n 1)"
  [ "$phx_host" = "$bind_address" ] && [ "$caddy_address" = "$bind_address" ] && [ -z "$domain" ] || fail lan_tls_identity_mismatch
  if ! ifconfig -a 2>/dev/null | awk '$1 == "inet" {print $2}' | grep -Fxq "$bind_address"; then
    fail bind_address_not_assigned_locally
  fi

  for port_key in PLAYSTEAD_HTTP_PORT PLAYSTEAD_HTTPS_PORT; do
    port="$(sed -n "s/^${port_key}=//p" "$env_real" | tail -n 1)"
    [[ "$port" =~ ^[0-9]{1,5}$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || fail port_invalid
    if ! command -v lsof >/dev/null 2>&1; then fail lsof_unavailable; fi
    # A listener on another specific address (for example 127.0.0.1) does
    # not occupy this LAN bind. A wildcard listener does occupy every address.
    listeners="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN -F n 2>/dev/null || true)"
    while IFS= read -r listener; do
      case "$listener" in
        "n$bind_address:$port"|"n*:$port"|"n0.0.0.0:$port") fail host_port_occupied ;;
      esac
    done <<< "$listeners"
  done

  for path_key in PLAYSTEAD_INBOX_HOST_PATH PLAYSTEAD_EXPORT_HOST_PATH PLAYSTEAD_BACKUP_HOST_PATH; do
    path="$(sed -n "s/^${path_key}=//p" "$env_real" | tail -n 1)"
    case "$path" in /*) ;; *) fail host_path_must_be_absolute ;; esac
    [ -d "$path" ] && [ ! -L "$path" ] || fail host_path_missing_or_symlink
    path_real="$(cd "$path" && pwd -P)"
    case "$path_real" in
      "$root"|"$root"/*) fail host_path_inside_checkout ;;
    esac
  done

  inbox="$(cd "$(sed -n 's/^PLAYSTEAD_INBOX_HOST_PATH=//p' "$env_real" | tail -n 1)" && pwd -P)"
  exports="$(cd "$(sed -n 's/^PLAYSTEAD_EXPORT_HOST_PATH=//p' "$env_real" | tail -n 1)" && pwd -P)"
  backups="$(cd "$(sed -n 's/^PLAYSTEAD_BACKUP_HOST_PATH=//p' "$env_real" | tail -n 1)" && pwd -P)"
  [ "$inbox" != "$exports" ] && [ "$inbox" != "$backups" ] && [ "$exports" != "$backups" ] || fail host_paths_must_be_distinct
  paths_overlap() {
    case "$1" in "$2"|"$2"/*) return 0 ;; esac
    case "$2" in "$1"|"$1"/*) return 0 ;; esac
    return 1
  }
  paths_overlap "$inbox" "$exports" && fail host_paths_must_not_nest
  paths_overlap "$inbox" "$backups" && fail host_paths_must_not_nest
  paths_overlap "$exports" "$backups" && fail host_paths_must_not_nest
  for path in "$inbox" "$exports" "$backups"; do
    case "$path" in "$root/inbox"|"$root/exports"|"$root"/*) fail host_path_overlaps_checkout_data ;; esac
  done

  # Compare against mounts from existing Playstead QA/dev/recovery projects
  # without printing their source paths. This remains a read-only Docker query.
  other_containers="$(docker ps -aq 2>/dev/null)" || fail resource_inspection_failed
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    mounts="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project" }}{{range .Mounts}}{{printf "\n%s" .Source}}{{end}}' "$id" 2>/dev/null)" || fail resource_inspection_failed
    owner="${mounts%%$'\n'*}"
    case "$owner" in playstead|playstead-*) ;; *) continue ;; esac
    [ "$owner" = "$project" ] && continue
    [ "$mounts" = "$owner" ] && continue
    rest="${mounts#*$'\n'}"
    while IFS= read -r source; do
      [ -n "$source" ] || continue
      source_real="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$source" 2>/dev/null)" || fail resource_inspection_failed
      paths_overlap "$inbox" "$source_real" && fail host_path_overlaps_existing_playstead_mount
      paths_overlap "$exports" "$source_real" && fail host_path_overlaps_existing_playstead_mount
      paths_overlap "$backups" "$source_real" && fail host_path_overlaps_existing_playstead_mount
    done <<< "$rest"
  done <<< "$other_containers"

  resolved="$("${compose[@]}" config --format json 2>/dev/null)" || fail compose_configuration_invalid
  if ! printf '%s' "$resolved" | env \
    PLAYSTEAD_INBOX_HOST_PATH="$inbox" \
    PLAYSTEAD_EXPORT_HOST_PATH="$exports" \
    PLAYSTEAD_BACKUP_HOST_PATH="$backups" \
    PLAYSTEAD_BIND_ADDRESS="$bind_address" \
    PLAYSTEAD_HTTP_PORT="$(sed -n 's/^PLAYSTEAD_HTTP_PORT=//p' "$env_real" | tail -n 1)" \
    PLAYSTEAD_HTTPS_PORT="$(sed -n 's/^PLAYSTEAD_HTTPS_PORT=//p' "$env_real" | tail -n 1)" \
    python3 -c '
import json, os, sys
cfg=json.load(sys.stdin)
expected={"app", "db", "caddy"}
if set(cfg.get("services", {})) != expected: raise SystemExit(1)
project="playstead-first-adopter"
root=os.path.realpath(sys.argv[1])
paths={os.path.realpath(os.environ[k]) for k in ("PLAYSTEAD_INBOX_HOST_PATH", "PLAYSTEAD_EXPORT_HOST_PATH", "PLAYSTEAD_BACKUP_HOST_PATH")}
for service in cfg["services"].values():
    for mount in service.get("volumes", []):
        if mount.get("type") == "bind":
            source=os.path.realpath(mount["source"])
            if source == os.path.realpath(root + "/Caddyfile"): continue
            if source == root or source.startswith(root + os.sep): raise SystemExit(2)
            if source not in paths: raise SystemExit(4)
for vol in cfg.get("volumes", {}).values():
    name=vol.get("name", "")
    if not name.startswith(project + "_"): raise SystemExit(5)
for net in cfg.get("networks", {}).values():
    name=net.get("name", "")
    if not name.startswith(project + "_"): raise SystemExit(6)
for svc in cfg["services"].values():
    for published in svc.get("ports", []):
        if published.get("host_ip") != os.environ["PLAYSTEAD_BIND_ADDRESS"]: raise SystemExit(7)
        if str(published.get("published")) != str(published.get("target")): raise SystemExit(8)
        if str(published.get("published")) not in (os.environ["PLAYSTEAD_HTTP_PORT"], os.environ["PLAYSTEAD_HTTPS_PORT"]): raise SystemExit(9)
' "$root" 2>/dev/null; then
    fail resolved_config_not_isolated
  fi

  # Existing resources are accepted only when they belong to this exact
  # project and expected Compose identity; unknown/stale resources fail closed.
  check_project_resources

  printf 'preflight_ok project=%s services=app,db,caddy paths=external-distinct ports=available bind=local-lan\n' "$project"
}

case "$command_name" in
  preflight)
    [ "$#" -eq 0 ] || usage
    read_only_preflight
    ;;
  up)
    [ "$#" -eq 0 ] || usage
    read_only_preflight
    "${compose[@]}" up -d
    ;;
  ps)
    [ "$#" -eq 0 ] || usage
    "${compose[@]}" ps
    ;;
  logs)
    "${compose[@]}" logs --no-color --tail 100 "$@" 2>&1 |
      sed -E 's/.*[Ss]etup token.*/[REDACTED setup token log line]/; s/(PLAYSTEAD_SETUP_TOKEN=)[^[:space:]]+/\1[REDACTED]/'
    ;;
  root-ca)
    [ "$#" -eq 1 ] || usage
    check_project_resources
    destination="$1"
    case "$destination" in /*) ;; *) fail ca_destination_must_be_absolute ;; esac
    [ ! -e "$destination" ] && [ ! -L "$destination" ] || fail ca_destination_already_exists
    destination_parent="$(cd "$(dirname "$destination")" 2>/dev/null && pwd -P)" || fail ca_destination_parent_missing
    case "$destination_parent" in "$root"|"$root"/*) fail ca_destination_must_be_outside_checkout ;; esac
    caddy_id="$("${compose[@]}" ps -q caddy 2>/dev/null)" || fail caddy_not_running
    [ -n "$caddy_id" ] || fail caddy_not_running
    caddy_labels="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project" }}|{{ index .Config.Labels "com.docker.compose.service" }}' "$caddy_id" 2>/dev/null)" || fail caddy_not_running
    [ "$caddy_labels" = "$project|caddy" ] || fail unexpected_caddy_container
    umask 077
    "${compose[@]}" cp caddy:/data/caddy/pki/authorities/local/root.crt "$destination" >/dev/null 2>&1 || fail caddy_root_not_available
    printf 'root_ca_exported project=%s destination=redacted\n' "$project"
    ;;
  down)
    [ "$#" -eq 0 ] || usage
    check_project_resources
    "${compose[@]}" down
    ;;
  backup)
    [ "$#" -gt 0 ] || usage
    PLAYSTEAD_BACKUP_PROJECT="$project" PLAYSTEAD_BACKUP_ENV_FILE="$env_real" \
      PLAYSTEAD_BACKUP_HOST_PATH="$(sed -n 's/^PLAYSTEAD_BACKUP_HOST_PATH=//p' "$env_real" | tail -n 1)" \
      "$root/scripts/backup-live.sh" --project "$project" "$@"
    ;;
esac
