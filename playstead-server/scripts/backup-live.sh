#!/usr/bin/env bash
# Run one durable backup against an explicitly mounted, independent host path.
# This wrapper deliberately never tears down the stack or operates on db/caddy.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

fail() {
  printf '%s\n' "backup_$1" >&2
  exit 1
}

usage() {
  printf '%s\n' 'usage: scripts/backup-live.sh [--project PROJECT] --full | [--project PROJECT] --incremental --parent-receipt RECEIPT_ID' >&2
  exit 2
}

kind=""
parent=""
explicit_project=""
if [ "${1:-}" = "--project" ]; then
  [ "$#" -ge 3 ] || usage
  explicit_project="$2"
  shift 2
  [[ "$explicit_project" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || fail source_project_invalid
fi

case "$#" in
  1)
    [ "$1" = "--full" ] || usage
    kind="full"
    ;;
  3)
    [ "$1" = "--incremental" ] && [ "$2" = "--parent-receipt" ] && [ -n "$3" ] || usage
    kind="incremental"
    parent="$3"
    ;;
  *) usage ;;
esac

[ -n "${PLAYSTEAD_BACKUP_HOST_PATH:-}" ] || fail destination_missing
[ -d "$PLAYSTEAD_BACKUP_HOST_PATH" ] || fail destination_missing
[ ! -L "$PLAYSTEAD_BACKUP_HOST_PATH" ] || fail destination_symlink
backup_real="$(cd "$PLAYSTEAD_BACKUP_HOST_PATH" && pwd -P)"
case "$backup_real" in
  "$root"|"$root"/*) fail destination_inside_checkout ;;
esac

docker compose version >/dev/null 2>&1 || fail compose_unavailable

# Never let Compose infer a project from this checkout. A project-name mismatch
# can otherwise make `run` create a new network and app container while leaving
# the canonical library untouched. Discover the running source by Compose's
# own labels and the exact configuration this wrapper can recreate. Retained
# restores also have app/db/caddy services but use an additional restore overlay;
# unrelated checkouts and unknown overrides must not become backup sources.
# Then require its complete live service set before invoking any
# Compose subcommand that could create or recreate a container.
source_projects=$(docker ps \
  --filter 'label=com.docker.compose.service=app' \
  --format '{{.Label "com.docker.compose.project"}}|{{.Label "com.docker.compose.project.config_files"}}' 2>/dev/null |
  while IFS='|' read -r project config_files; do
    if [ "$config_files" = "$root/docker-compose.yml" ] ||
      [ "$config_files" = "$root/docker-compose.yml,$root/docker-compose.backup.yml" ]; then
      printf '%s\n' "$project"
    fi
  done | LC_ALL=C sort -u) ||
  fail source_discovery_failed

source_project_count=$(printf '%s\n' "$source_projects" | awk 'NF { count += 1 } END { print count + 0 }')
[ "$source_project_count" -gt 0 ] || fail source_project_missing
if [ -n "$explicit_project" ]; then
  printf '%s\n' "$source_projects" | grep -Fxq "$explicit_project" || fail source_project_missing
  source_project="$explicit_project"
else
  [ "$source_project_count" -eq 1 ] || fail source_project_ambiguous
  source_project="$(printf '%s\n' "$source_projects" | awk 'NF { print; exit }')"
fi

case "$source_project" in
  [a-z0-9][a-z0-9_-]*) ;;
  *) fail source_project_invalid ;;
esac

source_services=$(docker ps \
  --filter "label=com.docker.compose.project=$source_project" \
  --format '{{.Label "com.docker.compose.service"}}' 2>/dev/null | LC_ALL=C sort) ||
  fail source_service_discovery_failed

[ "$source_services" = "$(printf '%s\n' app caddy db)" ] || fail source_project_services_invalid

if [ -n "$explicit_project" ]; then
  [ "$explicit_project" = "playstead-first-adopter" ] || fail source_project_invalid
  [ -n "${PLAYSTEAD_BACKUP_ENV_FILE:-}" ] && [ -f "$PLAYSTEAD_BACKUP_ENV_FILE" ] && [ ! -L "$PLAYSTEAD_BACKUP_ENV_FILE" ] || fail env_file_invalid
  expected_config="$root/docker-compose.yml,$root/docker-compose.backup.yml"
  actual_config=$(docker ps --filter "label=com.docker.compose.project=$source_project" \
    --format '{{.Label "com.docker.compose.project.config_files"}}' 2>/dev/null | LC_ALL=C sort -u) || fail source_config_discovery_failed
  [ "$actual_config" = "$expected_config" ] || fail source_config_mismatch
  [ "${PLAYSTEAD_BACKUP_PROJECT:-}" = "$explicit_project" ] || fail source_project_mismatch
  env_mode="$(stat -f '%Lp' "$PLAYSTEAD_BACKUP_ENV_FILE" 2>/dev/null)" || fail env_file_invalid
  (( (8#$env_mode & 077) == 0 )) || fail env_file_permissions_too_open
  app_id=$(docker ps -q --filter "label=com.docker.compose.project=$source_project" --filter 'label=com.docker.compose.service=app' 2>/dev/null) || fail source_service_discovery_failed
  [ -n "$app_id" ] || fail source_project_services_invalid
  live_mounts=$(docker inspect --format '{{range .Mounts}}{{printf "%s|%s\n" .Destination .Source}}{{end}}' "$app_id" 2>/dev/null) || fail source_mount_discovery_failed
  mounted_backup=$(printf '%s\n' "$live_mounts" | awk -F '|' '$1 == "/app/backups" { print $2 }')
  [ -n "$mounted_backup" ] || fail source_backup_mount_missing
  mounted_backup_real="$(cd "$mounted_backup" 2>/dev/null && pwd -P)" || fail source_backup_mount_missing
  [ "$mounted_backup_real" = "$backup_real" ] || fail source_backup_mount_mismatch
  inbox_source=$(printf '%s\n' "$live_mounts" | awk -F '|' '$1 == "/app/inbox" { print $2 }')
  export_source=$(printf '%s\n' "$live_mounts" | awk -F '|' '$1 == "/app/exports" { print $2 }')
  if [ -n "$inbox_source" ]; then
    inbox_real="$(cd "$inbox_source" 2>/dev/null && pwd -P)" || fail source_mount_discovery_failed
    case "$backup_real" in "$inbox_real"|"$inbox_real"/*) fail backup_destination_overlaps_inbox ;; esac
    case "$inbox_real" in "$backup_real"|"$backup_real"/*) fail backup_destination_overlaps_inbox ;; esac
  fi
  if [ -n "$export_source" ]; then
    export_real="$(cd "$export_source" 2>/dev/null && pwd -P)" || fail source_mount_discovery_failed
    case "$backup_real" in "$export_real"|"$export_real"/*) fail backup_destination_overlaps_exports ;; esac
    case "$export_real" in "$backup_real"|"$backup_real"/*) fail backup_destination_overlaps_exports ;; esac
  fi
fi

compose=(docker compose --project-name "$source_project" -f docker-compose.yml -f docker-compose.backup.yml)
if [ -n "$explicit_project" ]; then
  compose=(docker compose --env-file "$PLAYSTEAD_BACKUP_ENV_FILE" --project-name "$source_project" -f docker-compose.yml -f docker-compose.backup.yml)
fi
"${compose[@]}" config --quiet >/dev/null 2>&1 || fail compose_configuration_invalid

# `run --entrypoint` bypasses rel/entrypoint.sh. The preflight is therefore
# unprivileged and cannot mkdir/chown the bind mount as a side effect.
"${compose[@]}" run --rm --no-deps --entrypoint /app/bin/backup --user 65534:65534 app --preflight --full \
  >/dev/null 2>&1 || fail preflight_failed

# Preflight is the only gate before this availability-impacting operation.
"${compose[@]}" up -d --no-deps --force-recreate app >/dev/null 2>&1 || fail app_recreate_failed

deadline=$((SECONDS + ${PLAYSTEAD_BACKUP_HEALTH_TIMEOUT_SECONDS:-120}))
while true; do
  container_id=$("${compose[@]}" ps -q app 2>/dev/null || true)
  health=$(docker inspect --format '{{.State.Health.Status}}' "$container_id" 2>/dev/null || true)
  [ "$health" = "healthy" ] && break
  [ "$SECONDS" -lt "$deadline" ] || fail app_health_timeout
  sleep 2
done

if [ "$kind" = "full" ]; then
  output=$("${compose[@]}" exec -T --user 65534:65534 app /app/bin/backup --full --wait 2>/dev/null) ||
    fail backup_failed
else
  output=$("${compose[@]}" exec -T --user 65534:65534 app /app/bin/backup --incremental --parent-receipt "$parent" --wait 2>/dev/null) ||
    fail backup_failed
fi

receipt_output_pattern='^backup_published kind=(full|incremental) receipt_id=[[:alnum:]-]+ correlation_id=[[:alnum:]-]+ state=published verified_at=[0-9T:.+Z-]+ independence=(operator_attested|detected)$'
if [[ "$output" =~ $receipt_output_pattern ]]; then
  printf '%s\n' "$output"
else
  fail backup_output_invalid
fi
