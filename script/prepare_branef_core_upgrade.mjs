import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const destination = path.resolve(process.argv[2] || '');
if (!process.argv[2] || !process.env.RUNNER_TEMP || destination !== path.resolve(process.env.RUNNER_TEMP, 'branef-core-upgrade')) {
  throw new Error('The named disposable CI fixture directory is required.');
}
const reference = JSON.parse(fs.readFileSync('deploy/jrc/EXTENSION-REFERENCE.json', 'utf8'));
const baseline = reference.extensionBaselineSha;
if (reference.extensionId !== 'branef-glpi' || !/^[a-f0-9]{40}$/.test(baseline)) throw new Error('Reviewed Branef baseline required.');
execFileSync('git', ['merge-base', '--is-ancestor', baseline, 'HEAD']);
const schema = execFileSync('git', ['show', `${baseline}:db/schema.rb`]);
const files = execFileSync('git', ['ls-tree', '-r', '--name-only', baseline, '--', 'db/migrate']).toString().split('\n');
const versions = files.map(file => /^db\/migrate\/(\d{14})_[^/]+\.rb$/.exec(file)?.[1]).filter(Boolean);
if (!versions.length || new Set(versions).size !== versions.length) throw new Error('Invalid reviewed baseline migration inventory.');
fs.mkdirSync(destination, { recursive: true });
fs.writeFileSync(path.join(destination, 'schema.rb'), schema);
fs.writeFileSync(path.join(destination, 'baseline.json'), JSON.stringify({ baseline, versions }, null, 2) + '\n');
console.log(JSON.stringify({ baseline, migrationVersions: versions.length, source: 'committed Git schema, not customer data' }));
