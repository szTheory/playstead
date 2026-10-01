#!/usr/bin/env bash
# Command-contract regression only. It fabricates no backup, recovery, game,
# BIOS, save, or named-human evidence.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/playstead-retained-contract.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# Unknown and cross-mode arguments must be refused before Docker is selected.
if mix playstead.restore --retain --compose-fixture >/dev/null 2>&1; then
  echo "expected retained fixture selection refusal" >&2
  exit 1
fi

if mix playstead.restore --cleanup --unknown >/dev/null 2>&1; then
  echo "expected unknown cleanup option refusal" >&2
  exit 1
fi

# The public task reports Docker as an unavailable precondition before mutation.
stub="$tmp/bin"
mkdir -p "$stub"
cat >"$stub/docker" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod 700 "$stub/docker"

set +e
PATH="$stub:$PATH" mix playstead.restore --retain \
  --backup-set "$tmp/not-a-backup" \
  --target-root "$tmp/target" \
  --handoff-output "$tmp/target/server-handoff.json" \
  --canonical-project playstead \
  --canonical-root "$tmp/canonical" >/dev/null 2>&1
status=$?
set -e

if [ "$status" -ne 77 ] || [ -e "$tmp/target" ]; then
  echo "expected Docker precondition exit 77 before retained mutation" >&2
  exit 1
fi

# The following static checks keep emitted handoff forms and exact cleanup
# boundaries visible without representing any recovery evidence.
rg -q 'PLAYSTEAD_RECOVERY_RESTORE_HANDOFF=' lib/playstead/recovery/restore.ex
rg -q 'prove-recovery-known-playable\.sh --prepare' lib/playstead/recovery/restore.ex
rg -q 'Path\.join\(root, "server-handoff\.json"\)' lib/playstead/recovery/restore.ex
rg -q 'cleanup_refused' lib/playstead/recovery/restore.ex
rg -q '"down", "--volumes", "--remove-orphans"' lib/playstead/recovery/restore.ex

echo "retained recovery command-contract fixtures passed (not recovery or playability evidence)"
