#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
manifest="${PLAYSTEAD_EXUNIT_MANIFEST:-$root/scripts/ci/phase-04-7-exunit-manifest.tsv}"
target="${1:?usage: require-exunit-target.sh test/path.exs}"
[[ "$target" != /* && "$target" != *..* ]] || { echo "target must be a repository-relative test path" >&2; exit 2; }
[[ -s "$manifest" ]] || { echo "missing ExUnit manifest: $manifest" >&2; exit 2; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/playstead-exunit-target.XXXXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT
log="$tmp/exunit.log"
if ! cd "$root"; then exit 2; fi
if [[ ! -f "$target" ]]; then echo "missing exact ExUnit target file: $target" >&2; exit 2; fi

PLAYSTEAD_EXUNIT_MANIFEST="$manifest" PLAYSTEAD_EXUNIT_LOG="$log" PLAYSTEAD_EXUNIT_TARGET="$target" \
python3 - <<'PY'
import os, pathlib, sys

manifest = pathlib.Path(os.environ['PLAYSTEAD_EXUNIT_MANIFEST'])
target = os.environ['PLAYSTEAD_EXUNIT_TARGET']
rows = []
for number, raw in enumerate(manifest.read_text().splitlines(), 1):
    if not raw or raw.startswith('#'):
        continue
    fields = raw.split('\t')
    if len(fields) != 2 or not all(fields):
        raise SystemExit(f'{manifest}:{number}: expected test_file<TAB>exact identity')
    rows.append(tuple(fields))
if len({row for row in rows}) != len(rows):
    raise SystemExit('duplicate file/identity in ExUnit manifest')
selected = [identity for file, identity in rows if file == target]
if not selected:
    raise SystemExit(f'target has no exact ExUnit identities in manifest: {target}')
print('\n'.join(selected))
PY

set +e
mix test --trace "$target" >"$log" 2>&1
mix_status=$?
set -e
cat "$log"
python3 - "$manifest" "$target" "$log" "$mix_status" <<'PY'
import pathlib, re, sys

manifest_path, target, log_path, status = sys.argv[1:]
status = int(status)
expected = []
for number, raw in enumerate(pathlib.Path(manifest_path).read_text().splitlines(), 1):
    if not raw or raw.startswith('#'):
        continue
    fields = raw.split('\t')
    if len(fields) != 2 or not all(fields):
        raise SystemExit(f'{manifest_path}:{number}: malformed manifest row')
    if fields[0] == target:
        expected.append(fields[1])
if not expected:
    raise SystemExit(f'no exact targets registered for {target}')
if len(set(expected)) != len(expected):
    raise SystemExit(f'duplicate exact target identities registered for {target}')

text = pathlib.Path(log_path).read_text(errors='replace').replace('\r', '\n')
started = {}
skipped = set()
current_module = None
for line in text.splitlines():
    module_header = re.match(r'^\s*([A-Z][A-Za-z0-9_.]+) \[test/.*\]\s*$', line)
    if module_header:
        current_module = module_header.group(1)
        continue
    match = re.match(r'^\s*\* (test .+) \[L#\d+\]\s*$', line)
    if match:
        if current_module:
            identity = f'{current_module}::{match.group(1)[5:]}'
            started[identity] = started.get(identity, 0) + 1
    skip = re.match(r'^\s*[-*] test (.+?) \(skipped\)', line)
    if skip:
        # ExUnit emits the test-start line before reporting a skip.
        for identity in expected:
            _module, title = identity.split('::', 1)
            if title in skip.group(1):
                skipped.add(identity)

missing = [identity for identity in expected if started.get(identity, 0) == 0]
duplicate = [identity for identity in expected if started.get(identity, 0) > 1]
if status != 0:
    print(f'ExUnit exited with status {status}; exact target gate fails', file=sys.stderr)
    raise SystemExit(status)
if missing:
    print('missing/zero-discovery exact identities: ' + '; '.join(missing), file=sys.stderr)
    raise SystemExit(1)
if duplicate:
    print('duplicate exact identity execution: ' + '; '.join(duplicate), file=sys.stderr)
    raise SystemExit(1)
if skipped:
    print('skipped exact identities: ' + '; '.join(sorted(skipped)), file=sys.stderr)
    raise SystemExit(1)
summary = re.findall(r'^\s*(\d+) tests?, (\d+) failures?(?:, .*?)?\s*$', text, re.M)
if not summary:
    print('ExUnit summary missing; exact target gate fails', file=sys.stderr)
    raise SystemExit(1)
executed, failures = map(int, summary[-1])
if executed == 0 or failures != 0:
    print(f'ExUnit result invalid: {executed} tests, {failures} failures', file=sys.stderr)
    raise SystemExit(1)
print(f'exact ExUnit identities passed: {len(expected)} required; {executed} discovered/executed; 0 failures')
PY
