#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" ]]; then ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; fi
INVENTORY="$ROOT/playstead-server/priv/recovery/parser-fixture-inventory.json"
SELF_TEST=false
SELF_TEST_INVENTORY=""
OUTPUT=""
SUBJECT_SHA=""
while (($#)); do
  case "$1" in
    --self-test) SELF_TEST=true; shift ;;
    --self-test-inventory) SELF_TEST_INVENTORY="${2:?--self-test-inventory requires a path}"; shift 2 ;;
    --output) OUTPUT="${2:?--output requires a path}"; shift 2 ;;
    --subject-sha256) SUBJECT_SHA="${2:?--subject-sha256 requires a digest}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -n "$SELF_TEST_INVENTORY" ]]; then
  [[ "$SELF_TEST" == true ]] || { echo "--self-test-inventory requires --self-test" >&2; exit 2; }
  INVENTORY="$SELF_TEST_INVENTORY"
fi

cd "$ROOT"
python3 - "$INVENTORY" <<'PY'
import json, pathlib, re, sys
inventory = json.loads(pathlib.Path(sys.argv[1]).read_text())
formats = pathlib.Path('playstead-server/lib/playstead/formats.ex').read_text()
archive = pathlib.Path('playstead-server/lib/playstead/formats/archive.ex').read_text()
# Each registered parser has one explicitly reviewed adversarial test contract.
# Adding a parser requires adding its exact category, file, test name, and the
# parser call that the selected test must exercise here as well as in inventory.
contracts = {
    'archive': ('malformed-container-signatures', 'test/playstead/formats/archive_test.exs',
                'does not match empty input', r'Archive\.detect\(<<>>\)\s*==\s*:no_match'),
    'gba': ('malformed-header-and-checksum', 'test/playstead/formats/validators/gba_test.exs',
            'does not match a correct logo with a wrong checksum',
            r'Gba\.recognize\(RomFixtures\.bad_checksum_gba\(\)\)\s*==\s*:no_match'),
    'gb_gbc': ('malformed-header-and-checksum', 'test/playstead/formats/validators/gb_test.exs',
               'does not match a correct logo with a wrong checksum',
               r'Gb\.recognize\(RomFixtures\.bad_checksum_gb\(\)\)\s*==\s*:no_match'),
    'nes': ('malformed-truncated-header', 'test/playstead/formats/validators/nes_test.exs',
            'does not match input truncated before the header ends',
            r'Nes\.recognize\(RomFixtures\.truncated_nes\(\)\)\s*==\s*:no_match'),
    'md': ('malformed-truncated-header', 'test/playstead/formats/validators/md_test.exs',
           'does not match input truncated before the header ends',
           r'Md\.recognize\(RomFixtures\.truncated_md\(\)\)\s*==\s*:no_match'),
    'snes': ('malformed-truncated-header', 'test/playstead/formats/validators/snes_test.exs',
             'does not match input truncated before the header ends',
             r'Snes\.recognize\(binary_part\(RomFixtures\.valid_snes_lorom\(\), 0, 100\)\)\s*==\s*:no_match'),
    'psx_cue': ('path-traversal-and-malformed-descriptor', 'test/playstead/formats/validators/psx_cue_test.exs',
                'rejects a referenced name containing a parent-directory segment',
                r'PsxCue\.recognize\(RomFixtures\.cue_with_parent_traversal\(\)\)\s*==\s*:no_match'),
}
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
if type(inventory.get('schema_version')) is not int or inventory['schema_version'] != 1 or not isinstance(entries, list) or not entries:
    raise SystemExit('empty or malformed parser inventory')
mapped = {}
for entry in entries:
    if not isinstance(entry, dict):
        raise SystemExit('parser inventory entries must be objects')
    if set(entry) != {'id','category','test_file','test_identity'}:
        raise SystemExit('inventory entries must use only id/category/test_file/test_identity')
    if not all(isinstance(entry[k], str) and entry[k] for k in entry):
        raise SystemExit('empty parser inventory field')
    if entry['id'] in mapped:
        raise SystemExit(f'duplicate inventory entry: {entry["id"]}')
    mapped[entry['id']] = entry
    test = pathlib.Path('playstead-server') / entry['test_file']
    contract = contracts.get(entry['id'])
    if contract is None:
        raise SystemExit(f'missing explicit parser fixture contract for {entry["id"]}')
    category, expected_file, expected_identity, assertion = contract
    if (entry['category'], entry['test_file'], entry['test_identity']) != (category, expected_file, expected_identity):
        raise SystemExit(f'parser fixture contract mismatch for {entry["id"]}')
    if not test.is_file():
        raise SystemExit(f'missing parser fixture test file for {entry["id"]}')
    test_source = test.read_text()
    identity = re.search(r'\btest\s+"' + re.escape(expected_identity) + r'"\s+do(.*?)\n\s+end', test_source, re.S)
    if not identity or not re.search(assertion, identity.group(1)):
        raise SystemExit(f'parser fixture test does not exercise {entry["id"]}')
if registered != set(mapped):
    raise SystemExit(f'parser inventory drift: enabled={sorted(registered)}, mapped={sorted(mapped)}')
PY

cd "$ROOT/playstead-server"
mapfile -t test_files < <(python3 - "$INVENTORY" <<'PY'
import json, pathlib, sys
inventory = json.loads(pathlib.Path(sys.argv[1]).read_text())
for entry in inventory['parsers']:
    print(entry['test_file'])
PY
)
(( ${#test_files[@]} > 0 )) || { echo "zero parser fixture test files discovered" >&2; exit 1; }
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
