import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { test } from 'node:test';
import { verifyReviewedCoreImports } from './branef_core_migration_imports.mjs';
import { validateNewMigrationTimestamps } from './validate_migration_timestamps.mjs';

const file = 'db/migrate/20261102090000_create_jrc_broker_webhook_obligations.rb';
const bytes = Buffer.from('class DurableWebhook < ActiveRecord::Migration[7.1]; end\n');
const digest = createHash('sha256').update(bytes).digest('hex');
const schema = 'ActiveRecord::Schema[7.1].define(version: 2026_11_06_190000) do\nend';
const reference = () => ({
  extensionId: 'branef-glpi', repository: 'ClaudioHideki/Jrconversas_Branef_GLPI',
  sourceCoreRepository: 'ClaudioHideki/jrc-conversas-lab2', sourceCoreSha: 'a'.repeat(40),
  sourceCoreValidationRun: 42709460841,
  reviewedCoreMigrations: [{ path: file, sha256: digest }],
});
const options = () => ({
  baseSchemaSource: schema, newPaths: [file], reference: reference(),
  assertAncestor: () => {}, readCoreFile: () => bytes, readCurrentFile: () => bytes,
});

test('adopts only the exact reviewed core migration and leaves the generic timestamp guard strict', () => {
  const checked = options(); let ancestryChecked = false;
  checked.assertAncestor = sha => { assert.equal(sha, 'a'.repeat(40)); ancestryChecked = true; };
  assert.deepEqual(verifyReviewedCoreImports(checked), [file]);
  assert.equal(ancestryChecked, true);
  assert.throws(() => validateNewMigrationTimestamps(schema, [file]), /must sort after/);
});
test('does not exempt an unlisted older migration or a new future migration', () => {
  const checked = options(); checked.newPaths = ['db/migrate/20261101010000_unreviewed.rb', 'db/migrate/20261111110000_future.rb'];
  assert.deepEqual(verifyReviewedCoreImports(checked), []);
});
test('rejects a changed imported migration even when its path is approved', () => {
  const checked = options(); checked.readCurrentFile = () => Buffer.from('changed');
  assert.throws(() => verifyReviewedCoreImports(checked), /checksum/);
});
test('rejects an incorrect source digest', () => {
  const checked = options(); checked.readCoreFile = () => Buffer.from('different core');
  assert.throws(() => verifyReviewedCoreImports(checked), /checksum/);
});
test('rejects a source that is not an ancestor', () => {
  const checked = options(); checked.assertAncestor = () => { throw new Error('not ancestor'); };
  assert.throws(() => verifyReviewedCoreImports(checked), /not ancestor/);
});
test('rejects another repository or extension and requires a reviewed core CI run', () => {
  for (const change of [{ sourceCoreRepository: 'other/repo' }, { extensionId: 'other' }, { sourceCoreValidationRun: null }, { sourceCoreSha: 'HEAD' }]) {
    const checked = options(); Object.assign(checked.reference, change);
    assert.throws(() => verifyReviewedCoreImports(checked), /reference/);
  }
});
test('rejects ambiguous or unsafe manifest paths', () => {
  for (const rows of [[{ path: '../escape.rb', sha256: digest }], [{ path: file, sha256: digest }, { path: file, sha256: digest }]]) {
    const checked = options(); checked.reference.reviewedCoreMigrations = rows;
    assert.throws(() => verifyReviewedCoreImports(checked), /manifest/);
  }
});
