#!/usr/bin/env python3
"""Validate a private fixture/restore binding and stage only expected identities.

Usage: recovery-fixture.py REGISTRY HANDOFF [NEW_PROFILE]
The coordinator independently validates the complete handoff, live target and
trust contract. This helper additionally binds the chosen fixture to its exact
published backup chain, without copying ROM/save payload into the Mac profile.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys


def require(condition):
    if not condition:
        raise ValueError('invalid fixture')


def private_json(path):
    path = Path(path)
    require(path.is_absolute())
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, 'r') as stream:
        metadata = os.fstat(stream.fileno())
        require(stat.S_ISREG(metadata.st_mode) and metadata.st_uid == os.getuid())
        require(stat.S_IMODE(metadata.st_mode) == 0o600 and 0 < metadata.st_size <= 65536)
        value = json.load(stream)
    require(isinstance(value, dict))
    return value


def digest(value):
    return isinstance(value, str) and re.fullmatch(r'[0-9a-f]{64}', value) is not None


def validate_source(item, save=False):
    keys = {'path', 'sha256', 'size_bytes'} | ({'save_kind', 'medium_id'} if save else set())
    require(isinstance(item, dict) and set(item) == keys)
    require(digest(item['sha256']) and type(item['size_bytes']) is int)
    require(item['size_bytes'] == 32768 if save else 192 <= item['size_bytes'] <= 32 * 1024 * 1024)
    require(isinstance(item['path'], str) and '\x00' not in item['path'] and '\n' not in item['path'])
    path = Path(item['path'])
    require(path.is_absolute())
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, 'rb') as stream:
        metadata = os.fstat(stream.fileno())
        require(stat.S_ISREG(metadata.st_mode) and metadata.st_uid == os.getuid())
        require(metadata.st_size == item['size_bytes'])
        require(hashlib.sha256(stream.read(metadata.st_size + 1)).hexdigest() == item['sha256'])
    if save:
        require(item['save_kind'] == 'battery' and item['medium_id'] == 'sram_32k')


def projection(registry, handoff_path):
    record = private_json(registry)
    require(set(record) == {'schema', 'fixture_id', 'system_id', 'provenance', 'validated_at',
                            'game', 'persistent_save', 'evidence', 'recovery_backup', 'retained_restore'})
    require(record['schema'] == 'playstead.local-test-fixture.v1')
    require(record['fixture_id'] == 'aerevenadvance' and record['system_id'] == 'gba')
    require(record['provenance'] == 'owner_supplied_preexisting')
    require(isinstance(record['validated_at'], str) and isinstance(record['evidence'], list))
    require(all(isinstance(item, str) for item in record['evidence']))
    validate_source(record['game'])
    validate_source(record['persistent_save'], save=True)
    handoff = private_json(handoff_path)
    binding = record['retained_restore']
    require(isinstance(binding, dict) and set(binding) == {'handoff_path', 'correlation_id'})
    require(Path(binding['handoff_path']).resolve() == Path(handoff_path).resolve())
    require(binding['correlation_id'] == handoff['correlation_id'])
    receipt_path = Path(handoff['receipt_path'])
    require(receipt_path.parent.resolve() == Path(handoff_path).parent.resolve())
    receipt = private_json(receipt_path)
    require(receipt['correlation_id'] == handoff['correlation_id'])
    backup = record['recovery_backup']
    require(isinstance(backup, dict) and set(backup) == {'sets'})
    require(isinstance(backup['sets'], list) and 0 < len(backup['sets']) <= 100)
    chain = []
    backup_members = set()
    for item in backup['sets']:
        require(isinstance(item, dict) and set(item) == {'path', 'receipt_id', 'manifest_sha256'})
        require(digest(item['manifest_sha256']) and isinstance(item['receipt_id'], str))
        root = Path(item['path'])
        require(root.is_absolute() and not root.is_symlink())
        raw = (root / 'manifest.json').read_bytes()
        require(hashlib.sha256(raw).hexdigest() == item['manifest_sha256'])
        manifest = json.loads(raw)
        published = json.loads((root / 'receipt.json').read_text())
        require(manifest['id'] == published['receipt_id'] == item['receipt_id'])
        require(published['manifest_sha256'] == item['manifest_sha256'])
        entries = manifest['coverage']['entries']
        require(isinstance(entries, list))
        for entry in entries:
            require(isinstance(entry, dict) and digest(entry.get('sha256')) and type(entry.get('size_bytes')) is int)
            backup_members.add((entry['sha256'], entry['size_bytes']))
        chain.append(item['receipt_id'])
    require(receipt['chain_ids'] == chain)
    require({(record[key]['sha256'], record[key]['size_bytes']) for key in ('game', 'persistent_save')} <= backup_members)
    return {'schema': 'playstead.recovery-ui-fixture.v1', 'fixture_id': record['fixture_id'],
            'system_id': record['system_id'], 'rom_sha256': record['game']['sha256'],
            'rom_size_bytes': record['game']['size_bytes'],
            'save_sha256': record['persistent_save']['sha256'],
            'save_size_bytes': record['persistent_save']['size_bytes']}


def main():
    require(len(sys.argv) in (3, 4))
    data = projection(sys.argv[1], sys.argv[2])
    if len(sys.argv) == 4:
        root = Path(sys.argv[3])
        metadata = root.lstat()
        require(root.is_absolute() and stat.S_ISDIR(metadata.st_mode))
        require(metadata.st_uid == os.getuid() and stat.S_IMODE(metadata.st_mode) == 0o700)
        # Open through a verified directory descriptor so a concurrent path
        # replacement cannot redirect the expected-identity contract elsewhere.
        directory = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            fd = os.open('recovery-fixture.json', os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                         0o600, dir_fd=directory)
            with os.fdopen(fd, 'w') as stream:
                json.dump(data, stream, sort_keys=True)
                stream.write('\n')
                stream.flush()
                os.fsync(stream.fileno())
        finally:
            os.close(directory)
    print('RECOVERY_FIXTURE stage=fixture_validation outcome=ready')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, OverflowError):
        print('RECOVERY_FIXTURE stage=fixture_validation outcome=blocked', file=sys.stderr)
        raise SystemExit(77)
