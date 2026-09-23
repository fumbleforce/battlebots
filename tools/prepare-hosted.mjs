// Prepare matching release workers and clients without a PowerShell dependency.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

const { values } = parseArgs({ options: { godot: { type: 'string', default: 'godot' } } });
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const project = path.join(root, 'battlebots');
const exportsRoot = path.join(project, 'exports');
const diagnostics = /SCRIPT ERROR:|Parse Error:|^ERROR:|CrashHandlerException:|Program crashed|END OF C\+\+ BACKTRACE/m;
function run(binary, args, echo = false) {
  const result = spawnSync(binary, args, { cwd: root, encoding: 'utf8',
    timeout: 900000, maxBuffer: 64 * 1024 * 1024, shell: false });
  const output = (result.stdout ?? '') + (result.stderr ?? '');
  if (echo || result.error || result.status !== 0) process.stdout.write(output);
  assert.ifError(result.error);
  assert.equal(result.status, 0, `${binary} failed (${result.signal ?? result.status})`);
  return output;
}
function engine(args, marker) {
  const output = run(values.godot, ['--headless', '--path', project, ...args], true);
  assert.ok(!diagnostics.test(output), 'Godot emitted an error or native crash diagnostic');
  if (marker) assert.ok(output.split(/\r?\n/).includes(marker), `Missing ${marker}`);
}
const version = run(values.godot, ['--version']).trim();
assert.match(version, /^4\.7\.2\.stable/, 'Godot 4.7.2 stable is required');
const commit = run('git', ['rev-parse', 'HEAD']).trim();
function assertClean() {
  assert.equal(run('git', ['status', '--porcelain']).trim(), '',
    'Commit source changes before preparing a coordinated release');
  assert.equal(run('git', ['rev-parse', 'HEAD']).trim(), commit,
    'Source commit changed during release preparation');
}
assertClean();
mkdirSync(exportsRoot, { recursive: true });
writeFileSync(path.join(exportsRoot, '.gdignore'), '');
engine(['--editor', '--import', '--quit']);
engine(['--script', 'res://tests/baseline_smoke.gd'], 'BASELINE PASS');
const targets = [
  ['Linux Server', 'hosted-server', 'battlebots-server.x86_64', 'battlebots-server.pck'],
  ['Linux Client', 'linux-client', 'battlebots.x86_64', 'battlebots.pck'],
  ['Windows Client', 'windows-client', 'battlebots.exe', 'battlebots.pck'],
];
for (const [, directory] of targets) {
  rmSync(path.join(exportsRoot, directory, 'build-record.json'), { force: true });
}
const serverDirectory = path.join(exportsRoot, 'hosted-server');
mkdirSync(serverDirectory, { recursive: true });
engine(['--script', 'res://tools/write_service_manifest.gd', '--',
  `--output=${path.join(serverDirectory, 'manifest.json')}`], 'SERVICE MANIFEST PASS');
const manifest = readFileSync(path.join(serverDirectory, 'manifest.json'));
const records = [];
for (const [preset, directory, binary, pack] of targets) {
  const destination = path.join(exportsRoot, directory);
  mkdirSync(destination, { recursive: true });
  engine(['--export-release', preset, path.join(destination, binary)]);
  writeFileSync(path.join(destination, 'manifest.json'), manifest);
  const record = { commit, dirty: false, engine: version,
    prepared_utc: new Date().toISOString(), preset,
    files: [binary, pack, 'manifest.json'].map(name => ({ name,
      sha256: createHash('sha256').update(readFileSync(path.join(destination, name))).digest('hex') })) };
  records.push([destination, record]);
}
assertClean();
// Publish records only after every target succeeded from the same clean commit.
for (const [destination, record] of records) {
  writeFileSync(path.join(destination, 'build-record.json'), JSON.stringify(record, null, 2) + '\n');
}
console.log(`MATCHING CLIENT/SERVER RELEASE PREPARED: ${commit}\n${exportsRoot}`);
