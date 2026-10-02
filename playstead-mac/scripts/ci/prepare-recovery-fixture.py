#!/usr/bin/env python3
"""Reuse the registered homebrew backup through the production restore CLI."""
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile
import uuid

REPO = Path(__file__).resolve().parents[3]
REGISTRY = REPO / 'playstead-mac/.local/test-fixtures/aerevenadvance.json'


def fail(stage):
    print('stage=' + stage + ' outcome=blocked', flush=True)
    raise SystemExit(77)


def private_file(path):
    meta = path.lstat()
    if not stat.S_ISREG(meta.st_mode) or meta.st_uid != os.getuid() or stat.S_IMODE(meta.st_mode) != 0o600:
        fail('fixture_registry')


def main():
    os.umask(0o077)
    private_file(REGISTRY)
    record = json.loads(REGISTRY.read_text())
    if record.get('schema') != 'playstead.local-test-fixture.v1' or record.get('fixture_id') != 'aerevenadvance':
        fail('fixture_registry')
    for key in ('game', 'persistent_save'):
        item = record[key]
        path = Path(item['path']).resolve(strict=True)
        if not path.is_file() or path.stat().st_uid != os.getuid() or path.stat().st_size != item['size_bytes']:
            fail('fixture_identity')
        if hashlib.sha256(path.read_bytes()).hexdigest() != item['sha256']:
            fail('fixture_identity')
    sets = record['recovery_backup']['sets']
    if not sets:
        fail('backup_selection')
    expected_ids = []
    backup_members = set()
    for item in sets:
        root = Path(item['path']).resolve(strict=True)
        manifest = (root / 'manifest.json').read_bytes()
        receipt = json.loads((root / 'receipt.json').read_text())
        if hashlib.sha256(manifest).hexdigest() != item['manifest_sha256'] or receipt['manifest_sha256'] != item['manifest_sha256'] or receipt['receipt_id'] != item['receipt_id']:
            fail('backup_selection')
        metadata = json.loads(manifest)
        expected_ids.append(metadata['id'])
        for entry in metadata['coverage']['entries']:
            backup_members.add((entry['sha256'], entry['size_bytes']))
    if not {(record[key]['sha256'], record[key]['size_bytes']) for key in ('game', 'persistent_save')} <= backup_members:
        fail('backup_selection')
    target = Path(tempfile.gettempdir()).resolve() / ('playstead-aereven-recovery-' + uuid.uuid4().hex)
    handoff = target / 'server-handoff.json'
    command = [str(REPO / 'playstead-server/scripts/recovery-proof.sh'), '--restore', '--retain']
    for item in sets:
        command.extend(['--backup-set', item['path']])
    command.extend(['--target-root', str(target), '--handoff-output', str(handoff),
                    '--canonical-project', 'playstead-server', '--canonical-root', str(REPO)])
    descriptor, logname = tempfile.mkstemp(prefix='.restore-private-', dir=REGISTRY.parent)
    print('stage=restore outcome=running', flush=True)
    with os.fdopen(descriptor, 'w') as log:
        result = subprocess.run(command, cwd=REPO / 'playstead-server', stdout=log, stderr=subprocess.STDOUT, timeout=1800)
    if result.returncode != 0:
        fail('restore')
    private_file(handoff)
    h = json.loads(handoff.read_text())
    receipt_path = Path(h['receipt_path'])
    private_file(receipt_path)
    r = json.loads(receipt_path.read_text())
    if r.get('state') != 'verified' or r.get('chain_ids') != expected_ids or r.get('correlation_id') != h.get('correlation_id'):
        fail('restore_receipt')
    if r.get('stages') != ['chain', 'preflight', 'database', 'cas', 'manifest', 'api']:
        fail('restore_receipt')
    record['retained_restore'] = {'handoff_path': str(handoff), 'correlation_id': h['correlation_id']}
    descriptor, temporary = tempfile.mkstemp(prefix='.registry-', dir=REGISTRY.parent)
    with os.fdopen(descriptor, 'w') as output:
        json.dump(record, output, indent=2)
        output.write('\n')
        output.flush()
        os.fsync(output.fileno())
    os.replace(temporary, REGISTRY)
    Path(logname).unlink()
    print('stage=restore outcome=verified', flush=True)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired):
        fail('fixture_preparation')
