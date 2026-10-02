#!/usr/bin/env bash
# Contract fixtures only: no Docker daemon, recovery record, or backup bytes.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
export BACKUP_LIVE_TEST_ROOT="$root"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/playstead-backup-live.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

destination="$tmp/independent"
mkdir "$destination"
stub="$tmp/bin"
mkdir "$stub"
log="$tmp/docker.log"

# Build an actual OTP release with an inert backup entry point. A launcher
# echo stub cannot catch separators leaking through eval into System.argv().
cp -R "$root/scripts/tests/fixtures/backup-release" "$tmp/release-fixture"
cp "$root/.tool-versions" "$tmp/release-fixture/.tool-versions"
(cd "$tmp/release-fixture" && MIX_ENV=prod mix release playstead --quiet)
release_bin="$tmp/release-fixture/_build/prod/rel/playstead/bin"
cp "$root/rel/overlays/bin/backup" "$release_bin/backup"

assert_release_args() {
  local actual expected
  actual=$("$release_bin/backup" "$@")
  expected=''
  if [ "$#" -gt 0 ]; then expected=$(printf '<%s>\n' "$@"); fi
  if [[ "$actual" != "$expected" ]]; then
    printf 'release argv mismatch: expected <%s>, got <%s>\n' "$expected" "$actual" >&2
    exit 1
  fi
}
assert_release_args
assert_release_args --full
assert_release_args --preflight --full
assert_release_args --full --wait
assert_release_args --incremental --parent-receipt 'parent with spaces' --wait
# Preserve even invalid input exactly so the strict domain parser can reject it.
assert_release_args -- --full
assert_release_args --unknown
assert_release_args --incremental --parent-receipt ''

cat >"$stub/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$BACKUP_LIVE_TEST_LOG"
if [ "$1" = "compose" ]; then
  shift
  if [ "$1" = "--project-name" ]; then shift 2; fi
  while [ "$#" -gt 0 ] && [ "$1" = "-f" ]; do shift 2; done
  case "$1" in
    version|config|run|up) exit 0 ;;
    exec) printf '%s\n' 'backup_published kind=full receipt_id=receipt-opaque correlation_id=correlation-opaque state=published verified_at=2026-09-20T00:00:00Z independence=operator_attested'; exit 0 ;;
    ps) printf 'app-container\n'; exit 0 ;;
  esac
fi
if [ "$1" = "ps" ]; then
  if [ "$2" = "--filter" ] && [ "$3" = "label=com.docker.compose.service=app" ]; then
    if [ "${BACKUP_LIVE_TEST_ROWS+x}" = x ]; then
      if [[ "$*" == *project.config_files* ]]; then
        printf '%s\n' "$BACKUP_LIVE_TEST_ROWS"
      else
        printf '%s\n' "$BACKUP_LIVE_TEST_ROWS" | cut -d '|' -f 1
      fi
      exit 0
    fi
    if [ "${BACKUP_LIVE_TEST_PROJECTS+x}" = x ]; then
      projects="$BACKUP_LIVE_TEST_PROJECTS"
    else
      projects=canonical-live
    fi
    while IFS= read -r project; do
      [ -n "$project" ] || continue
      if [[ "$*" == *project.config_files* ]]; then
        printf '%s|%s/docker-compose.yml\n' "$project" "$BACKUP_LIVE_TEST_ROOT"
      else
        printf '%s\n' "$project"
      fi
    done <<< "$projects"
  else
    if [ "${BACKUP_LIVE_TEST_SERVICES+x}" = x ]; then
      printf '%s\n' "$BACKUP_LIVE_TEST_SERVICES"
    else
      printf '%s\n' app caddy db
    fi
  fi
  exit 0
fi
if [ "$1" = "inspect" ]; then printf 'healthy\n'; exit 0; fi
exit 91
EOF
chmod 700 "$stub/docker"

output=$(PATH="$stub:$PATH" BACKUP_LIVE_TEST_LOG="$log" PLAYSTEAD_BACKUP_HOST_PATH="$destination" \
  "$root/scripts/backup-live.sh" --full)
[[ "$output" == backup_published* ]]
[[ "$output" != *"$destination"* ]]

preflight_line=$(grep -n -- 'run --rm --no-deps --entrypoint /app/bin/backup --user 65534:65534 app --preflight --full' "$log" | cut -d: -f1)
recreate_line=$(grep -n -- 'up -d --no-deps --force-recreate app' "$log" | cut -d: -f1)
live_line=$(grep -n -- 'exec -T --user 65534:65534 app /app/bin/backup --full --wait' "$log" | cut -d: -f1)

[ -n "$preflight_line" ] && [ -n "$recreate_line" ] && [ -n "$live_line" ]
[ "$preflight_line" -lt "$recreate_line" ] && [ "$recreate_line" -lt "$live_line" ]
! grep -Eq '(^| )(down|rm|restart)( |$)' "$log"
grep -Fq 'compose --project-name canonical-live -f docker-compose.yml -f docker-compose.backup.yml config --quiet' "$log"
grep -Fq 'ps --filter label=com.docker.compose.service=app --format {{.Label "com.docker.compose.project"}}' "$log"
grep -Fq 'ps --filter label=com.docker.compose.project=canonical-live --format {{.Label "com.docker.compose.service"}}' "$log"

if PATH="$stub:$PATH" BACKUP_LIVE_TEST_LOG="$log" PLAYSTEAD_BACKUP_HOST_PATH="$tmp/missing" \
  "$root/scripts/backup-live.sh" --full >/dev/null 2>&1; then
  echo "expected missing destination refusal" >&2
  exit 1
fi

if PATH="$stub:$PATH" BACKUP_LIVE_TEST_LOG="$log" PLAYSTEAD_BACKUP_HOST_PATH="$destination" \
  "$root/scripts/backup-live.sh" --incremental >/dev/null 2>&1; then
  echo "expected explicit parent refusal" >&2
  exit 1
fi

: >"$log"
if missing_source_output=$(PATH="$stub:$PATH" BACKUP_LIVE_TEST_LOG="$log" PLAYSTEAD_BACKUP_HOST_PATH="$destination" \
  BACKUP_LIVE_TEST_PROJECTS='' "$root/scripts/backup-live.sh" --full 2>&1); then
  echo "expected missing source project refusal" >&2
  exit 1
fi
[[ "$missing_source_output" == *backup_source_project_missing* ]]
grep -Fq 'ps --filter label=com.docker.compose.service=app' "$log"
! grep -Eq 'compose .* (config|run|up|exec)( |$)' "$log"

: >"$log"
if ambiguous_source_output=$(PATH="$stub:$PATH" BACKUP_LIVE_TEST_LOG="$log" PLAYSTEAD_BACKUP_HOST_PATH="$destination" \
  BACKUP_LIVE_TEST_PROJECTS=$'canonical-live\nother-live' "$root/scripts/backup-live.sh" --full 2>&1); then
  echo "expected ambiguous source project refusal" >&2
  exit 1
fi
[[ "$ambiguous_source_output" == *backup_source_project_ambiguous* ]]
! grep -Eq 'compose .* (config|run|up|exec)( |$)' "$log"

: >"$log"
if incomplete_services_output=$(PATH="$stub:$PATH" BACKUP_LIVE_TEST_LOG="$log" PLAYSTEAD_BACKUP_HOST_PATH="$destination" \
  BACKUP_LIVE_TEST_SERVICES=$'app\ndb' "$root/scripts/backup-live.sh" --full 2>&1); then
  echo "expected incomplete source service refusal" >&2
  exit 1
fi
[[ "$incomplete_services_output" == *backup_source_project_services_invalid* ]]
grep -Fq 'ps --filter label=com.docker.compose.project=canonical-live' "$log"
! grep -Eq 'compose .* (config|run|up|exec)( |$)' "$log"

# Names are deliberately uninformative: provenance must decide eligibility.
for canonical_config in "$root/docker-compose.yml" "$root/docker-compose.yml,$root/docker-compose.backup.yml"; do
  : >"$log"
  rows=$(printf '%s\n' "canonical-live|$canonical_config" \
    "ordinary-name|$root/docker-compose.yml,/tmp/compose.restore.yml" \
    "other-checkout|/other/docker-compose.yml" "missing-label|")
  output=$(PATH="$stub:$PATH" BACKUP_LIVE_TEST_LOG="$log" PLAYSTEAD_BACKUP_HOST_PATH="$destination" \
    BACKUP_LIVE_TEST_ROWS="$rows" "$root/scripts/backup-live.sh" --full)
  [[ "$output" == backup_published* ]]
  grep -Fq 'compose --project-name canonical-live ' "$log"
  ! grep -Eq 'compose --project-name (ordinary-name|other-checkout|missing-label) ' "$log"
done

for rejected_config in "$root/docker-compose.yml,/tmp/compose.restore.yml" \
  "$root/docker-compose.yml,$root/docker-compose.backup.yml,/tmp/compose.restore.yml" \
  '/other/docker-compose.yml' '' "$root/docker-compose.backup.yml"; do
  : >"$log"
  if output=$(PATH="$stub:$PATH" BACKUP_LIVE_TEST_LOG="$log" PLAYSTEAD_BACKUP_HOST_PATH="$destination" \
    BACKUP_LIVE_TEST_ROWS="canonical-live|$rejected_config" "$root/scripts/backup-live.sh" --full 2>&1); then
    echo "expected unproven source refusal" >&2
    exit 1
  fi
  [[ "$output" == *backup_source_project_missing* ]]
  ! grep -Eq 'compose .* (config|run|up|exec)( |$)' "$log"
done

echo "backup live wrapper command-contract fixtures passed (not backup evidence)"
