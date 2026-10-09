#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
validator="$root/playstead-server/scripts/parser-fixture-inventory.sh"
source_inventory="$root/playstead-server/priv/recovery/parser-fixture-inventory.json"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/playstead-parser-inventory-test.XXXXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT

python3 - "$source_inventory" "$tmp" <<'PY'
import json, pathlib, sys
inventory = json.loads(pathlib.Path(sys.argv[1]).read_text())
target = pathlib.Path(sys.argv[2])
boolean_version = dict(inventory, schema_version=True)
(target / "boolean-version.json").write_text(json.dumps(boolean_version))
for name, malformed in (("null-entry", None), ("list-entry", []), ("string-entry", "not-an-object")):
    malformed_inventory = dict(inventory, parsers=[malformed])
    (target / f"{name}.json").write_text(json.dumps(malformed_inventory))
PY

for case in boolean-version null-entry list-entry string-entry; do
  if "$validator" --self-test --self-test-inventory "$tmp/$case.json" >"$tmp/stdout" 2>"$tmp/stderr"; then
    echo "$case parser inventory must be rejected" >&2
    exit 1
  fi

  [[ ! -s "$tmp/stdout" ]] || { echo "$case inventory emitted stdout" >&2; exit 1; }
  expected='empty or malformed parser inventory'
  [[ "$case" == *-entry ]] && expected='parser inventory entries must be objects'
  grep -Fx "$expected" "$tmp/stderr" >/dev/null || {
    echo "$case inventory did not produce the controlled validation error" >&2
    cat "$tmp/stderr" >&2
    exit 1
  }
  ! grep -q 'Traceback' "$tmp/stderr" || {
    echo "$case inventory emitted a traceback" >&2
    cat "$tmp/stderr" >&2
    exit 1
  }
done
