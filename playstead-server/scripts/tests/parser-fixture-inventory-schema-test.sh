#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
validator="$root/playstead-server/scripts/parser-fixture-inventory.sh"
source_inventory="$root/playstead-server/priv/recovery/parser-fixture-inventory.json"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/playstead-parser-inventory-test.XXXXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT

python3 - "$source_inventory" "$tmp/inventory.json" <<'PY'
import json, pathlib, sys
inventory = json.loads(pathlib.Path(sys.argv[1]).read_text())
inventory["schema_version"] = True
pathlib.Path(sys.argv[2]).write_text(json.dumps(inventory))
PY

if "$validator" --self-test --self-test-inventory "$tmp/inventory.json" >"$tmp/stdout" 2>"$tmp/stderr"; then
  echo "boolean parser inventory schema version must be rejected" >&2
  exit 1
fi

[[ ! -s "$tmp/stdout" ]] || { echo "invalid inventory emitted stdout" >&2; exit 1; }
grep -Fx 'empty or malformed parser inventory' "$tmp/stderr" >/dev/null
! grep -q 'Traceback' "$tmp/stderr"
