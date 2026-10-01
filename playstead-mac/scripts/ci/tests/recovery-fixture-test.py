#!/usr/bin/env python3
"""Synthetic contract tests; never open an operator's game or server."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock
import contextlib
import importlib.util
import io

HELPER = Path(__file__).resolve().parents[1] / 'recovery-fixture.py'


class RecoveryFixtureTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='playstead-fixture-contract-')
        self.root = Path(self.temporary.name)
        self.profile = self.root / 'profile'
        self.profile.mkdir(mode=0o700)
        self.game = self.root / 'synthetic.gba'
        self.game.write_bytes(b'x' * 512)
        self.save = self.root / 'synthetic.sav'
        self.save.write_bytes(b'y' * 32768)
        backup = self.root / 'backup'
        backup.mkdir()
        manifest = json.dumps({'schema': 'playstead.backup-set.v1', 'id': 'set-one', 'coverage': {
            'entries': [{'sha256': hashlib.sha256(p.read_bytes()).hexdigest(), 'size_bytes': p.stat().st_size}
                        for p in (self.game, self.save)]}}).encode()
        (backup / 'manifest.json').write_bytes(manifest)
        digest = hashlib.sha256(manifest).hexdigest()
        self.write(backup / 'receipt.json', {'receipt_id': 'set-one', 'manifest_sha256': digest})
        self.handoff = self.root / 'server-handoff.json'
        self.write(self.handoff, {'correlation_id': 'test-correlation', 'receipt_path': str(self.root / 'restore-receipt.json')})
        self.write(self.root / 'restore-receipt.json', {'chain_ids': ['set-one'], 'correlation_id': 'test-correlation'})
        def item(path):
            return {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'size_bytes': path.stat().st_size}
        self.record = {
            'schema': 'playstead.local-test-fixture.v1', 'fixture_id': 'aerevenadvance',
            'system_id': 'gba', 'provenance': 'owner_supplied_preexisting',
            'validated_at': '2026-09-27T00:00:00Z', 'game': item(self.game),
            'persistent_save': dict(item(self.save), save_kind='battery', medium_id='sram_32k'),
            'evidence': ['local-evidence.md'],
            'recovery_backup': {'sets': [{'path': str(backup), 'receipt_id': 'set-one', 'manifest_sha256': digest}]},
            'retained_restore': {'handoff_path': str(self.handoff), 'correlation_id': 'test-correlation'},
        }
        self.registry = self.root / 'registry.json'
        self.write(self.registry, self.record)

    def tearDown(self):
        self.temporary.cleanup()

    def write(self, path, data):
        path.write_text(json.dumps(data))
        path.chmod(0o600)

    def run_helper(self, stage=False):
        command = ['python3', str(HELPER), str(self.registry), str(self.handoff)]
        if stage:
            command.append(str(self.profile))
        return subprocess.run(command, capture_output=True, text=True)

    def assert_refused(self):
        result = self.run_helper(stage=True)
        self.assertEqual(result.returncode, 77)
        self.assertNotIn(str(self.root), result.stdout + result.stderr)
        self.assertFalse((self.profile / 'recovery-fixture.json').exists())

    def test_writes_only_expected_identity_without_source_paths_or_payload(self):
        self.assertEqual(self.run_helper().returncode, 0)
        result = self.run_helper(stage=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        path = self.profile / 'recovery-fixture.json'
        data = json.loads(path.read_text())
        self.assertEqual(set(data), {'schema', 'fixture_id', 'system_id', 'rom_sha256', 'rom_size_bytes', 'save_sha256', 'save_size_bytes'})
        self.assertEqual(data['schema'], 'playstead.recovery-ui-fixture.v1')
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertNotIn(str(self.root), path.read_text() + result.stdout + result.stderr)
        self.assertEqual(len(list(self.profile.iterdir())), 1)

    def test_rejects_modified_source(self):
        self.game.write_bytes(b'z' * 512)
        self.assert_refused()

    def test_rejects_broad_registry_mode(self):
        self.registry.chmod(0o644)
        self.assert_refused()

    def test_rejects_registry_symlink(self):
        destination = self.registry.with_name('actual.json')
        self.registry.rename(destination)
        self.registry.symlink_to(destination)
        self.assert_refused()

    def test_rejects_different_target(self):
        self.record['retained_restore']['correlation_id'] = 'other'
        self.write(self.registry, self.record)
        self.assert_refused()

    def test_rejects_different_chain(self):
        self.write(self.root / 'restore-receipt.json', {'chain_ids': ['other'], 'correlation_id': 'test-correlation'})
        self.assert_refused()

    def test_rejects_unrecognized_fields(self):
        self.record['password'] = 'never-copy'
        self.write(self.registry, self.record)
        self.assert_refused()

    def test_rejects_validly_pinned_backup_that_lacks_the_selected_save(self):
        backup = Path(self.record['recovery_backup']['sets'][0]['path'])
        manifest = json.loads((backup / 'manifest.json').read_text())
        manifest['coverage']['entries'].pop()
        raw = json.dumps(manifest).encode()
        (backup / 'manifest.json').write_bytes(raw)
        digest = hashlib.sha256(raw).hexdigest()
        self.write(backup / 'receipt.json', {'receipt_id': 'set-one', 'manifest_sha256': digest})
        self.record['recovery_backup']['sets'][0]['manifest_sha256'] = digest
        self.write(self.registry, self.record)
        self.assert_refused()

    def test_never_overwrites_an_existing_run_contract(self):
        self.assertEqual(self.run_helper(stage=True).returncode, 0)
        self.assertEqual(self.run_helper(stage=True).returncode, 77)

    def preparation_module(self):
        spec = importlib.util.spec_from_file_location('fixture_prepare', HELPER.with_name('prepare-recovery-fixture.py'))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        module.REGISTRY = self.registry
        module.REPO = self.root / 'workspace'
        return module

    def test_preparation_uses_existing_backup_and_records_only_verified_new_target(self):
        module = self.preparation_module()
        calls = []
        def restore(command, **kwargs):
            calls.append(command)
            self.assertIn('--retain', command)
            self.assertEqual(command[command.index('--backup-set') + 1], self.record['recovery_backup']['sets'][0]['path'])
            target = Path(command[command.index('--target-root') + 1])
            self.assertFalse(target.exists())
            target.mkdir(mode=0o700)
            handoff = target / 'server-handoff.json'
            self.write(handoff, {'receipt_path': str(target / 'restore-receipt.json'), 'correlation_id': 'fresh-correlation'})
            self.write(target / 'restore-receipt.json', {
                'state': 'verified', 'chain_ids': ['set-one'], 'correlation_id': 'fresh-correlation',
                'stages': ['chain', 'preflight', 'database', 'cas', 'manifest', 'api'],
            })
            return subprocess.CompletedProcess(command, 0)
        output = io.StringIO()
        with mock.patch.object(module.tempfile, 'gettempdir', return_value=str(self.root)), \
             mock.patch.object(module.subprocess, 'run', side_effect=restore), contextlib.redirect_stdout(output):
            module.main()
        updated = json.loads(self.registry.read_text())
        self.assertEqual(len(calls), 1)
        self.assertEqual(updated['retained_restore']['correlation_id'], 'fresh-correlation')
        self.assertEqual(updated['game'], self.record['game'])
        self.assertEqual(updated['persistent_save'], self.record['persistent_save'])
        self.assertNotIn(str(self.root), output.getvalue())

    def test_failed_restore_preserves_existing_registry(self):
        module = self.preparation_module()
        before = self.registry.read_bytes()
        with mock.patch.object(module.tempfile, 'gettempdir', return_value=str(self.root)), \
             mock.patch.object(module.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1)), \
             contextlib.redirect_stdout(io.StringIO()), self.assertRaises(SystemExit) as stopped:
            module.main()
        self.assertEqual(stopped.exception.code, 77)
        self.assertEqual(self.registry.read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
