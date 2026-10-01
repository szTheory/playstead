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
grep -Eq 'PLAYSTEAD_RECOVERY_RESTORE_HANDOFF=' lib/playstead/recovery/restore.ex
grep -Eq 'prove-recovery-known-playable\.sh --prepare' lib/playstead/recovery/restore.ex
grep -Fq 'Path.join(target, "server-handoff.json")' lib/playstead/recovery/restore.ex
grep -Eq 'cleanup_refused' lib/playstead/recovery/restore.ex
python3 - lib/playstead/recovery/restore.ex <<'PY'
import sys

source = open(sys.argv[1], encoding="utf-8").read()
marker = source.find('"--remove-orphans"')
start = source.rfind("args = [", 0, marker) if marker >= 0 else -1
end = source.find("]", marker) if marker >= 0 else -1
block = source[start:end] if start >= 0 and end >= 0 else ""
required = ['"down"', '"--volumes"', '"--remove-orphans"']
positions = [block.find(value) for value in required]
if start < 0 or end < 0 or any(position < 0 for position in positions) or positions != sorted(positions):
    raise SystemExit("cleanup command must include volume and orphan removal")
PY

echo "retained recovery command-contract fixtures passed (not recovery or playability evidence)"
