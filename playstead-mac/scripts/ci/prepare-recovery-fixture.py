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


def persist_registry(record):
    descriptor, temporary = tempfile.mkstemp(prefix='.registry-', dir=REGISTRY.parent)
    try:
        with os.fdopen(descriptor, 'w') as output:
            json.dump(record, output, indent=2)
            output.write('\n')
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, REGISTRY)
    except OSError:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def cleanup_previous_retained_restore(record):
    previous = record.get('retained_restore')
    if previous is None:
        return
    if not isinstance(previous, dict):
        fail('prior_restore_cleanup')

    handoff_value = previous.get('handoff_path')
    if not isinstance(handoff_value, str) or not handoff_value:
        fail('prior_restore_cleanup')
    handoff = Path(handoff_value)

    # Older private registries recorded only the handoff path. If that file
    # has already expired, there is no safe project identity to clean up.
    # New entries persist the project identity, allowing us to fail closed if
    # its handoff disappears while Docker resources still remain.
    if not handoff.exists():
        project = previous.get('compose_project')
        if project is None:
            return
        if not isinstance(project, str) or not re.fullmatch(r'playstead-restore-[a-z0-9-]+', project):
            fail('prior_restore_cleanup')
        try:
            containers = subprocess.run(
                ['docker', 'ps', '-aq', '--filter', 'label=com.docker.compose.project=' + project],
                check=True, capture_output=True, text=True, timeout=30,
            ).stdout.strip()
            volumes = subprocess.run(
                ['docker', 'volume', 'ls', '-q', '--filter', 'label=com.docker.compose.project=' + project],
                check=True, capture_output=True, text=True, timeout=30,
            ).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            fail('prior_restore_cleanup')
        if containers or volumes:
            fail('prior_restore_cleanup')
        return

    try:
        handoff = handoff.resolve(strict=True)
        target = handoff.parent
        if target.parent != Path(tempfile.gettempdir()).resolve() or not re.fullmatch(
            r'playstead-aereven-recovery-[0-9a-f]{32}', target.name
        ) or handoff.name != 'server-handoff.json':
            fail('prior_restore_cleanup')
        private_file(handoff)
        h = json.loads(handoff.read_text())
        if not isinstance(h, dict):
            fail('prior_restore_cleanup')
        project = h.get('project')
        if h.get('schema') != 'playstead.restore-handoff.v1' or not isinstance(project, str) or not re.fullmatch(
            r'playstead-restore-[a-z0-9-]+', project
        ):
            fail('prior_restore_cleanup')
        if previous.get('compose_project') not in (None, project):
            fail('prior_restore_cleanup')
        if previous.get('target_root') not in (None, str(target)):
            fail('prior_restore_cleanup')
        if previous.get('correlation_id') not in (None, h.get('correlation_id')):
            fail('prior_restore_cleanup')

        receipt_path = target / 'restore-receipt.json'
        ca_path = target / 'caddy-root-ca.pem'
        if h.get('receipt_path') != str(receipt_path) or h.get('ca_path') != str(ca_path):
            fail('prior_restore_cleanup')
        private_file(receipt_path)
        private_file(ca_path)
        receipt = json.loads(receipt_path.read_text())
        if (
            not isinstance(receipt, dict)
            or not isinstance(receipt.get('target'), dict)
            or receipt.get('schema') != 'playstead.restore-receipt.v1'
            or receipt.get('state') != 'verified'
            or receipt.get('correlation_id') != h.get('correlation_id')
            or receipt.get('target', {}).get('project') != project
            or receipt.get('stages') != ['chain', 'preflight', 'database', 'cas', 'manifest', 'api']
        ):
            fail('prior_restore_cleanup')

        history = record.setdefault('retained_restore_history', [])
        if not isinstance(history, list):
            fail('prior_restore_cleanup')
        history_keys = {'correlation_id', 'state', 'chain_ids', 'stages', 'verified_at', 'project', 'cleanup_status'}
        if any(not isinstance(entry, dict) or set(entry) != history_keys for entry in history):
            fail('prior_restore_cleanup')
        history_entry = next((
            entry for entry in history
            if entry['correlation_id'] == receipt['correlation_id']
            and entry['project'] == project
            and entry['cleanup_status'] == 'pending'
        ), None)
        if history_entry is None:
            history.append({
                key: receipt[key]
                for key in ('correlation_id', 'state', 'chain_ids', 'stages', 'verified_at')
            } | {'project': project, 'cleanup_status': 'pending'})
            history = history[-50:]
            history_entry = history[-1]
        record['retained_restore_history'] = history
        persist_registry(record)

        command = [
            str(REPO / 'playstead-server/scripts/recovery-proof.sh'), '--restore', '--cleanup',
            '--target-root', str(target), '--handoff-output', str(handoff),
        ]
        subprocess.run(
            command, cwd=REPO / 'playstead-server', check=True,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=180,
        )
        if target.exists():
            fail('prior_restore_cleanup')
        history_entry['cleanup_status'] = 'completed'
        persist_registry(record)
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        fail('prior_restore_cleanup')


def main():
    os.umask(0o077)
    private_file(REGISTRY)
    record = json.loads(REGISTRY.read_text())
    if not isinstance(record, dict) or record.get('schema') != 'playstead.local-test-fixture.v1' or record.get('fixture_id') != 'aerevenadvance':
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
    cleanup_previous_retained_restore(record)
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
    record['retained_restore'] = {
        'handoff_path': str(handoff),
        'correlation_id': h['correlation_id'],
        'compose_project': h['project'],
        'target_root': str(target),
    }
    persist_registry(record)
    Path(logname).unlink()
    print('stage=restore outcome=verified', flush=True)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired):
        fail('fixture_preparation')
