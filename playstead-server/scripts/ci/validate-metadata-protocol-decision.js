#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');

const REQUIRED_FIELDS = [
  'choice', 'entity_kind', 'payload_version', 'identity_key', 'revision', 'tombstone',
  'selection_resource', 'media_resource', 'capability', 'snapshot_branch',
  'reset_behavior', 'old_client_behavior', 'migration_policy',
];

function parseDecision(markdown) {
  const matches = [...markdown.matchAll(/```protocol-decision\s*\n([\s\S]*?)\n```/g)];
  if (matches.length !== 1) throw new Error('expected exactly one fenced protocol-decision JSON object');
  let value;
  try { value = JSON.parse(matches[0][1]); }
  catch { throw new Error('protocol-decision block is not valid JSON'); }
  if (!value || Array.isArray(value) || typeof value !== 'object') {
    throw new Error('protocol-decision must be a JSON object');
  }
  return value;
}

function validate(value) {
  const keys = Object.keys(value).sort();
  const expectedKeys = [...REQUIRED_FIELDS].sort();
  if (keys.length !== expectedKeys.length || keys.some((key, index) => key !== expectedKeys[index])) {
    const missing = expectedKeys.filter((key) => !(key in value));
    const unknown = keys.filter((key) => !expectedKeys.includes(key));
    throw new Error(`decision fields mismatch; missing=[${missing.join(',')}], unknown=[${unknown.join(',')}]`);
  }
  for (const key of REQUIRED_FIELDS) {
    if (value[key] === null || value[key] === undefined || value[key] === '') {
      throw new Error(`${key} must have a concrete value`);
    }
  }
  if (value.choice !== 'metadata-kind') throw new Error('choice must be metadata-kind');
  if (value.entity_kind !== 'metadata') throw new Error('entity_kind must be metadata');
  if (value.payload_version !== 1) throw new Error('payload_version must be integer 1');
  if (value.identity_key !== 'asset_set_id') throw new Error('identity_key must be asset_set_id');
  if (typeof value.revision !== 'string' || value.revision !== 'owner_monotonic_revision') {
    throw new Error('revision must be owner_monotonic_revision');
  }
  if (typeof value.tombstone !== 'string' || value.tombstone !== 'deleted_at') {
    throw new Error('tombstone must be deleted_at');
  }
  if (!value.selection_resource || value.selection_resource.method !== 'POST' ||
      value.selection_resource.path !== '/api/v1/metadata/:asset_set_id') {
    throw new Error('selection_resource must be POST /api/v1/metadata/:asset_set_id');
  }
  if (!value.media_resource || value.media_resource.method !== 'GET' ||
      value.media_resource.path !== '/api/v1/metadata/:asset_set_id/media/:media_id' ||
      value.media_resource.status !== 'reserved_until_media_plan') {
    throw new Error('media_resource must reserve the typed private-media GET route for a later plan');
  }
  if (!value.capability || value.capability.namespace !== 'app' ||
      value.capability.feature !== 'metadata_selection' ||
      value.capability.version !== '1.1.0' || value.capability.required !== false) {
    throw new Error('capability must be optional app 1.1.0 metadata_selection');
  }
  if (value.snapshot_branch !== 'metadata') throw new Error('snapshot_branch must be metadata');
  if (value.reset_behavior !== 'reconstruct_at_snapshot_cursor') {
    throw new Error('reset_behavior must reconstruct_at_snapshot_cursor');
  }
  if (value.old_client_behavior !== 'ignore_optional_kind') {
    throw new Error('old_client_behavior must be ignore_optional_kind');
  }
  if (value.migration_policy !== 'additive_optional_kind_and_snapshot_branch') {
    throw new Error('migration_policy must be additive_optional_kind_and_snapshot_branch');
  }
}

function selfTest() {
  const valid = {
    choice: 'metadata-kind', entity_kind: 'metadata', payload_version: 1,
    identity_key: 'asset_set_id', revision: 'owner_monotonic_revision', tombstone: 'deleted_at',
    selection_resource: { method: 'POST', path: '/api/v1/metadata/:asset_set_id' },
    media_resource: { method: 'GET', path: '/api/v1/metadata/:asset_set_id/media/:media_id', status: 'reserved_until_media_plan' },
    capability: { namespace: 'app', feature: 'metadata_selection', version: '1.1.0', required: false },
    snapshot_branch: 'metadata', reset_behavior: 'reconstruct_at_snapshot_cursor',
    old_client_behavior: 'ignore_optional_kind',
    migration_policy: 'additive_optional_kind_and_snapshot_branch',
  };
  validate(valid);
  const cases = [
    null,
    Object.fromEntries(Object.entries(valid).filter(([key]) => key !== 'reset_behavior')),
    { ...valid, unknown: true },
    { ...valid, choice: 'catalogue-change' },
    { ...valid, payload_version: null },
    { ...valid, identity_key: 'rom_sha256' },
    { ...valid, old_client_behavior: 'reject_unknown_kind' },
    { ...valid, reset_behavior: 'reconstruct_at_latest_cursor' },
    { ...valid, capability: { namespace: 'app', feature: 'metadata_selection', version: '1.1.0', required: true } },
  ];
  for (const testCase of cases) {
    let rejected = false;
    try { validate(testCase); } catch { rejected = true; }
    if (!rejected) throw new Error('self-test accepted an incomplete or incompatible decision');
  }
}

function main() {
  const args = process.argv.slice(2);
  if (args.length === 1 && args[0] === '--self-test') {
    selfTest();
    process.stdout.write('metadata protocol decision validator self-test passed\n');
    return;
  }
  if (args.length > 2 || (args.length === 2 && args[0] !== '--file')) {
    throw new Error('usage: validate-metadata-protocol-decision.js [--file PATH | --self-test]');
  }
  const file = args.length === 2
    ? path.resolve(args[1])
    : path.resolve(__dirname, '../../../.planning/phases/04.7-optional-game-artwork-and-metadata-sync/04.7-PROTOCOL-DECISION.md');
  const decision = parseDecision(fs.readFileSync(file, 'utf8'));
  validate(decision);
  process.stdout.write(`validated ${path.basename(file)}: metadata kind v1 keyed by asset_set_id\n`);
}

try { main(); }
catch (error) {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
}
