#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" ]]; then ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; fi
INVENTORY="$ROOT/playstead-server/priv/recovery/parser-fixture-inventory.json"
SELF_TEST=false
OUTPUT=""
SUBJECT_SHA=""
while (($#)); do
  case "$1" in
    --self-test) SELF_TEST=true; shift ;;
    --output) OUTPUT="${2:?--output requires a path}"; shift 2 ;;
    --subject-sha256) SUBJECT_SHA="${2:?--subject-sha256 requires a digest}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

cd "$ROOT"
python3 - "$INVENTORY" <<'PY'
import json, pathlib, re, sys
inventory = json.loads(pathlib.Path(sys.argv[1]).read_text())
formats = pathlib.Path('playstead-server/lib/playstead/formats.ex').read_text()
archive = pathlib.Path('playstead-server/lib/playstead/formats/archive.ex').read_text()
registered = set(re.findall(r'\{:(\w+),\s*&\w+\.recognize/1\}', formats))
if 'Archive.detect(bounded)' not in formats or '@signatures [' not in archive:
    raise SystemExit('archive detector is not registered from production Formats code')
registered.add('archive')
if 'PsxCue.recognize(bounded,)' in formats:
    registered.add('psx_cue')
elif re.search(r'PsxCue\.recognize\(bounded\)', formats):
    registered.add('psx_cue')
registered = {'gb_gbc' if key == 'gb' else key for key in registered}
entries = inventory.get('parsers')
if inventory.get('schema_version') != 1 or not isinstance(entries, list) or not entries:
    raise SystemExit('empty or malformed parser inventory')
mapped = {}
for entry in entries:
    if set(entry) != {'id','category','test_file','test_identity'}:
        raise SystemExit('inventory entries must use only id/category/test_file/test_identity')
    if not all(isinstance(entry[k], str) and entry[k] for k in entry):
        raise SystemExit('empty parser inventory field')
    if entry['id'] in mapped:
        raise SystemExit(f'duplicate inventory entry: {entry["id"]}')
    mapped[entry['id']] = entry
    test = pathlib.Path('playstead-server') / entry['test_file']
    if not test.is_file() or not re.search(r'\btest\s+"' + re.escape(entry['test_identity']) + r'"', test.read_text()):
        raise SystemExit(f'missing discoverable test identity for {entry["id"]}')
if registered != set(mapped):
    raise SystemExit(f'parser inventory drift: enabled={sorted(registered)}, mapped={sorted(mapped)}')
PY

cd "$ROOT/playstead-server"
test_files=(test/playstead/formats/archive_test.exs test/playstead/formats/validators/{gba,gb,nes,md,snes,psx_cue}_test.exs)
test_output="$(mix test "${test_files[@]}" --trace 2>&1)" || { printf '%s\n' "$test_output"; exit 1; }
printf '%s\n' "$test_output"
count="$(printf '%s\n' "$test_output" | sed -nE 's/^([0-9]+ properties, )?([0-9]+) tests?, [0-9]+ failures?$/\2/p' | tail -1)"
[[ "$count" =~ ^[1-9][0-9]*$ ]] || { echo "zero or unreported parser fixture tests" >&2; exit 1; }

if [[ "$SELF_TEST" == true ]]; then exit 0; fi
[[ "$SUBJECT_SHA" =~ ^[0-9a-f]{64}$ ]] || { echo "valid --subject-sha256 is required" >&2; exit 2; }
python3 - "$INVENTORY" "$SUBJECT_SHA" "$count" "$OUTPUT" <<'PY'
import json, pathlib, sys
inventory = json.loads(pathlib.Path(sys.argv[1]).read_text())
digest, count, output = sys.argv[2], int(sys.argv[3]), sys.argv[4]
result = {
  'status':'passed', 'subject_sha256':digest,
  'discovered':len(inventory['parsers']), 'mapped':len(inventory['parsers']),
  'tests_discovered':count, 'tests_passed':count,
  'parsers':[{**entry,'result':'passed'} for entry in inventory['parsers']],
}
pathlib.Path(output).write_text(json.dumps(result, sort_keys=True, separators=(',', ':')) + '\n')
PY
