import { createHash } from 'node:crypto';
import { validateNewMigrationTimestamps } from './validate_migration_timestamps.mjs';

const migration = /^db\/migrate\/(\d{14})_[^/\\]+\.rb$/;
const digest = bytes => createHash('sha256').update(Buffer.from(bytes).toString('utf8').replaceAll('\r\n', '\n')).digest('hex');

// Extension-only adoption of existing, reviewed core files. This never changes
// their timestamps and does not relax the generic guard for new migrations.
export function verifyReviewedCoreImports({ baseSchemaSource, newPaths, reference, assertAncestor, readCoreFile, readCurrentFile }) {
  if (reference.extensionId !== 'branef-glpi' || reference.repository !== 'ClaudioHideki/Jrconversas_Branef_GLPI' ||
      reference.sourceCoreRepository !== 'ClaudioHideki/jrc-conversas-lab2' || !/^[a-f0-9]{40}$/.test(reference.sourceCoreSha) ||
      !Number.isSafeInteger(reference.sourceCoreValidationRun) || reference.sourceCoreValidationRun < 1) {
    throw new Error('Invalid reviewed core reference.');
  }
  const rows = reference.reviewedCoreMigrations;
  if (!Array.isArray(rows) || rows.length > 100) throw new Error('Invalid reviewed migration manifest.');
  const approved = new Map();
  for (const row of rows) {
    if (!migration.test(row.path) || !/^[a-f0-9]{64}$/.test(row.sha256) || approved.has(row.path)) {
      throw new Error('Invalid or ambiguous reviewed migration manifest.');
    }
    approved.set(row.path, row.sha256);
  }
  assertAncestor(reference.sourceCoreSha);
  const { baseSchemaVersion } = validateNewMigrationTimestamps(baseSchemaSource, []);
  return [...new Set(newPaths)].filter(file => {
    const timestamp = migration.exec(file)?.[1];
    if (!timestamp || timestamp > baseSchemaVersion || !approved.has(file)) return false;
    const expected = approved.get(file);
    if (digest(readCoreFile(reference.sourceCoreSha, file)) !== expected || digest(readCurrentFile(file)) !== expected) {
      throw new Error('Reviewed core migration checksum mismatch: ' + file);
    }
    return true;
  });
}
