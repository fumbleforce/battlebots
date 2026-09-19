import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, readdir, writeFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { EventEmitter } from 'node:events';
import { processWorkerFactory } from '../worker.mjs';

test('process adapter writes private atomic config, bounds status, reports spawn error, and cleans its directory', async t => {
  const root = await mkdtemp(join(tmpdir(), 'battlebots-worker-test-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  let resolveExit;
  const exited = new Promise(resolve => { resolveExit = resolve; });
  const factory = processWorkerFactory({ executable: join(root, 'does-not-exist'), workDirectory: root });
  const config = { allocation_id: 'a'.repeat(32), schema: 1, lease_expires_at: 1000, slots: [] };
  const worker = await factory(config, resolveExit);
  await exited;
  const directory = join(root, config.allocation_id);
  assert.deepEqual(JSON.parse(await readFile(join(directory, 'config.json'), 'utf8')), config);
  await worker.update({ ...config, lease_expires_at: 2000 });
  assert.equal(JSON.parse(await readFile(join(directory, 'config.json'), 'utf8')).lease_expires_at, 2000);
  assert.equal((await readdir(directory)).some(path => path.endsWith('.tmp')), false);
  assert.equal(await worker.status(), null);
  await writeFile(join(directory, 'status.json'), '{broken');
  assert.equal(await worker.status(), null);
  await writeFile(join(directory, 'status.json'), JSON.stringify({ ready: true }));
  assert.deepEqual(await worker.status(), { ready: true });
  await writeFile(join(directory, 'status.json'), 'x'.repeat(16_385));
  assert.equal(await worker.status(), null);
  await worker.stop();
  assert.deepEqual(await readdir(root), []);
});

test('process configuration rejects relative executable/project and path traversal allocation IDs', async t => {
  assert.throws(() => processWorkerFactory({ executable: 'godot', workDirectory: tmpdir() }));
  assert.throws(() => processWorkerFactory({ executable: process.execPath, projectPath: '../project', workDirectory: tmpdir() }));
  const factory = processWorkerFactory({ executable: process.execPath, workDirectory: tmpdir() });
  await assert.rejects(() => factory({ allocation_id: '../escape' }, () => {}));
});

test('source and exported workers use ordinary app startup without the editor-only script override', async t => {
  const root = await mkdtemp(join(tmpdir(), 'battlebots-worker-args-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  for (const projectPath of [undefined, join(root, 'source project')]) {
    let captured;
    const factory = processWorkerFactory({ executable: process.execPath, projectPath, workDirectory: root }, {
      spawnProcess(executable, args, options) {
        captured = { executable, args, options };
        const child = new EventEmitter();
        child.kill = () => { child.emit('exit', 0, 'SIGTERM'); return true; };
        return child;
      },
    });
    const config = { allocation_id: 'b'.repeat(32), schema: 1, slots: [] };
    const worker = await factory(config, () => assert.fail('intentional stop must not report a crash'));
    assert.equal(captured.executable, process.execPath);
    assert.deepEqual(captured.options, { shell: false, windowsHide: true, stdio: 'ignore' });
    const expected = ['--headless', '--max-fps', '60'];
    if (projectPath) expected.push('--path', projectPath);
    expected.push('--', `--allocation-config=${join(root, config.allocation_id, 'config.json')}`);
    assert.deepEqual(captured.args, expected);
    assert.equal(captured.args.includes('--script'), false);
    assert.equal(captured.args.some(value => value.includes('res://')), false);
    await worker.stop();
  }
});
