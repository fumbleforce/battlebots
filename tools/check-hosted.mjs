// Exercise the real HTTP allocator, separate Godot server and real ENet clients.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, writeFile, readFile, mkdir } from 'node:fs/promises';
import { createWriteStream } from 'node:fs';
import { Transform } from 'node:stream';
import { finished } from 'node:stream/promises';
import { StringDecoder } from 'node:string_decoder';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
function option(name) {
  const index = args.indexOf(name);
  return index < 0 ? '' : args[index + 1];
}
const godot = option('--godot');
if (!godot) throw new Error('Required: --godot <Godot 4.7.2 executable>');
const serverBinary = option('--server-binary');
const run = await mkdtemp(path.join(os.tmpdir(), 'battlebots-hosted-'));
const children = [];
const crashPatterns = [
  ['SCRIPT ERROR', /SCRIPT ERROR/], ['Parse Error', /Parse Error/],
  ['ERROR', /(?:^|[\r\n])ERROR/], ['CrashHandlerException', /CrashHandlerException/],
  ['Program crashed', /Program crashed/], ['END OF C++ BACKTRACE', /END OF C\+\+ BACKTRACE/],
];
function monitoredLog(child, output) {
  const decoder = new StringDecoder('utf8');
  let scanTail = '';
  let scanTailAtStart = true;
  let line = '';
  let droppingLine = false;
  const monitor = new Transform({
    transform(chunk, _encoding, callback) {
      const text = decoder.write(chunk);
      // A truncated overlap is not the beginning of a stream or a new line.
      const combined = scanTail + text;
      const scan = (scanTailAtStart ? '' : '\0') + combined;
      for (const [signature, pattern] of crashPatterns) {
        if (pattern.test(scan)) child.crashSignature ??= signature;
      }
      // Enough overlap for every signature, including signatures split between writes.
      scanTailAtStart = scanTailAtStart && combined.length <= 128;
      scanTail = combined.slice(-128);
      for (const part of text.split(/(?<=\n)/)) {
        if (!droppingLine) line += part;
        if (line.length > 8192) {
          this.push('[oversized log line omitted]\n');
          line = ''; droppingLine = true;
        }
        if (part.endsWith('\n')) {
          if (!droppingLine) this.push(line.replace(/[a-f0-9]{64}/gi, '[redacted]'));
          line = ''; droppingLine = false;
        }
      }
      callback();
    },
    flush(callback) {
      line += decoder.end();
      if (!droppingLine && line) this.push(line.replace(/[a-f0-9]{64}/gi, '[redacted]'));
      callback();
    },
  });
  monitor.pipe(output);
  return monitor;
}
function launch(label, binary, parameters, env = process.env) {
  const child = spawn(binary, parameters, { cwd: root, env, shell: false, windowsHide: true,
    stdio: ['ignore', 'pipe', 'pipe'] });
  const output = createWriteStream(path.join(run, `${label}.out.log`));
  const errors = createWriteStream(path.join(run, `${label}.err.log`));
  child.stdout.pipe(monitoredLog(child, output));
  child.stderr.pipe(monitoredLog(child, errors));
  const flushed = Promise.all([finished(output), finished(errors)]).then(() => true, () => false);
  let spawnFailed = false;
  child.completed = new Promise(resolve => {
    child.once('error', () => { spawnFailed = true; });
    // exit can precede the last stdout/stderr bytes. close plus flushed logs makes
    // even an exit-zero crash diagnostic part of this check's result.
    child.once('close', async (code, signal) => resolve({ code: spawnFailed ? -1 : code, signal,
      crash: child.crashSignature, logs_flushed: await flushed }));
  });
  children.push(child);
  return child;
}
async function completed(child, timeout = 75000) {
  const result = await Promise.race([child.completed, delay(timeout, undefined, { ref: false }).then(() => ({ timeout: true }))]);
  assert.equal(result.code, 0, `Child failed: ${JSON.stringify(result)}; logs: ${run}`);
  assert.equal(result.crash, undefined, `Godot diagnostic: ${result.crash}; logs: ${run}`);
  assert.equal(result.logs_flushed, true, `Unable to flush child logs; logs: ${run}`);
}
async function until(action, seconds = 60) {
  const end = Date.now() + seconds * 1000;
  while (Date.now() < end) {
    const value = await action();
    if (value) return value;
    await delay(1000);
  }
  throw new Error(`Bounded wait expired; logs: ${run}`);
}
const port = await new Promise(resolve => {
  const probe = net.createServer();
  probe.listen(0, '127.0.0.1', () => {
    const chosen = probe.address().port;
    probe.close(() => resolve(chosen));
  });
});
const base = `http://127.0.0.1:${port}`;
async function request(route, guest, method = 'GET', body) {
  const response = await fetch(base + route, { method, signal: AbortSignal.timeout(5000),
    headers: { 'Content-Type': 'application/json', ...(guest ? { Authorization: `Bearer ${guest.access_token}` } : {}) },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
  const value = await response.json();
  assert.ok(response.ok, `HTTP ${response.status} on ${route}`);
  return value;
}
try {
  const manifest = path.join(run, 'manifest.json');
  await completed(launch('manifest', godot, ['--headless', '--path', path.join(root, 'battlebots'),
    '--script', 'res://tools/write_service_manifest.gd', '--', `--output=${manifest}`]));
  const compatibility = JSON.parse(await readFile(manifest, 'utf8'));
  const stateDirectory = path.join(run, 'state');
  await mkdir(stateDirectory);
  const service = launch('service', process.execPath, ['services/matchmaking/index.mjs'], {
    ...process.env, HOST: '127.0.0.1', PORT: String(port), PUBLIC_ADDRESS: '127.0.0.1',
    BIND_ADDRESS: '127.0.0.1', REGION: 'local-test', STATE_DIRECTORY: stateDirectory,
    GODOT_PATH: serverBinary || godot, GODOT_PROJECT_PATH: serverBinary ? '' : path.join(root, 'battlebots'),
    BUILD_MANIFEST_PATH: manifest,
  });
  await until(async () => {
    if (service.exitCode !== null) throw new Error(`Service exited; logs: ${run}`);
    try { return await request('/healthz'); } catch { return null; }
  });
  async function guest() { return request('/v1/guests', null, 'POST', compatibility); }
  async function exercise(label, count) {
    const guests = [];
    for (let index = 0; index < count; index++) guests.push(await guest());
    if (label === 'private') {
      const created = await request('/v1/rooms', guests[0], 'POST', { mode: 'teams', capacity: count });
      assert.match(created.code, /^[A-Z0-9]{8}$/);
      for (const member of guests.slice(1)) await request('/v1/rooms/join', member, 'POST', { code: created.code });
    } else {
      for (const member of guests) await request('/v1/queue', member, 'POST', {});
    }
    const assignments = [];
    for (const member of guests) {
      const membership = await until(async () => {
        const view = await request('/v1/membership', member);
        assert.notEqual(view.state, 'failed', 'Allocation failed');
        return view.state === 'ready' && view.assignment ? view : null;
      });
      assignments.push(membership.assignment);
    }
    assert.equal(new Set(assignments.map(value => value.room_id)).size, 1);
    assert.equal(new Set(assignments.map(value => value.admission_ticket)).size, count);
    const peers = [];
    for (let index = 0; index < count; index++) {
      const config = path.join(run, `${label}-${index}.config.json`);
      const output = path.join(run, `${label}-${index}.json`);
      await writeFile(config, JSON.stringify({ ...assignments[index], output }), { mode: 0o600 });
      peers.push(launch(`${label}-${index}`, godot, ['--headless', '--path', path.join(root, 'battlebots'),
        '--max-fps', '60', '--script', 'res://tests/services/hosted_playtest_peer.gd', '--', `--peer-config=${config}`]));
    }
    await Promise.all(peers.map(peer => completed(peer)));
    const evidence = [];
    for (let index = 0; index < count; index++) {
      const report = JSON.parse(await readFile(path.join(run, `${label}-${index}.json`), 'utf8'));
      assert.equal(report.valid, true);
      assert.equal(report.players, count);
      evidence.push(report);
    }
    // Wait for worker disconnect status before cancelling reserved memberships.
    await delay(1500);
    for (const member of guests) await request('/v1/membership', member, 'DELETE');
    console.log(`HOSTED ${label.toUpperCase()} PASS: ${count} independent clients reached active and drove`);
    return evidence;
  }
  const evidence = { private: await exercise('private', 2), queue: await exercise('queue', 4),
    build: compatibility.build, exported_server: Boolean(serverBinary) };
  await writeFile(path.join(run, 'report.json'), JSON.stringify(evidence, null, 2));
  assert.equal(service.crashSignature, undefined, `Service diagnostic: ${service.crashSignature}; logs: ${run}`);
  console.log(`HOSTED END TO END PASS: ${run}`);
} finally {
  // Kill only processes owned by this check; the supervisor owns its workers.
  for (const child of children.reverse()) {
    if (child.exitCode === null && child.signalCode === null) {
      child.kill('SIGTERM');
      await Promise.race([child.completed, delay(3000, undefined, { ref: false })]);
      if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL');
    }
    await Promise.race([child.completed, delay(3000, undefined, { ref: false })]);
  }
}
