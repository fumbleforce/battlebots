// Exercise the real HTTP allocator, separate Godot server and real ENet clients.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, writeFile, readFile, mkdir, rm } from 'node:fs/promises';
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
const endpoint = option('--endpoint');
const localService = option('--local-service');
assert.ok(!args.includes('--endpoint') || endpoint, '--endpoint requires an HTTPS origin');
assert.ok(!args.includes('--local-service') || localService, '--local-service requires an HTTP loopback origin');
assert.ok(!(endpoint && localService), '--endpoint and --local-service are mutually exclusive');
const managedService = Boolean(endpoint || localService);
assert.ok(!managedService || !serverBinary, '--server-binary applies only when this check starts the service');
const duelOnly = managedService || args.includes('--duel-only');
if (localService) {
  assert.match(localService, /^http:\/\/127\.0\.0\.1:[0-9]+\/?$/,
    'Local service must use http://127.0.0.1:<port> without credentials or a path');
  const url = new URL(localService);
  assert.ok(Number(url.port || 80) > 0, 'Local service port must be positive');
}
if (endpoint) {
  const url = new URL(endpoint);
  assert.equal(url.protocol, 'https:', 'External endpoint must use HTTPS');
  assert.ok(!url.username && !url.password && !url.search && !url.hash && url.pathname === '/',
    'External endpoint must be an HTTPS origin without credentials');
}
const run = await mkdtemp(path.join(os.tmpdir(), 'battlebots-hosted-'));
const children = [];
const ownedGuests = [];
const credentialFiles = [];
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
const base = managedService ? new URL(endpoint || localService).origin : `http://127.0.0.1:${port}`;
async function request(route, guest, method = 'GET', body) {
  const response = await fetch(base + route, { method, redirect: 'error', signal: AbortSignal.timeout(5000),
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
  const service = managedService ? null : launch('service', process.execPath, ['services/matchmaking/index.mjs'], {
    ...process.env, HOST: '127.0.0.1', PORT: String(port), PUBLIC_ADDRESS: '127.0.0.1',
    BIND_ADDRESS: '127.0.0.1', REGION: 'local-test', STATE_DIRECTORY: stateDirectory,
    GODOT_PATH: serverBinary || godot, GODOT_PROJECT_PATH: serverBinary ? '' : path.join(root, 'battlebots'),
    BUILD_MANIFEST_PATH: manifest,
  });
  await until(async () => {
    if (service && service.exitCode !== null) throw new Error(`Service exited; logs: ${run}`);
    try { return await request('/healthz'); } catch { return null; }
  });
  async function guest() {
    const created = await request('/v1/guests', null, 'POST', compatibility);
    ownedGuests.push(created);
    return created;
  }
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
    if (endpoint) {
      for (const assignment of assignments) {
        assert.ok(net.isIPv4(assignment.address), 'External worker must supply an IPv4 address');
        const [a, b] = assignment.address.split('.').map(Number);
        assert.ok(a !== 0 && a !== 10 && a !== 127 && a < 224
          && !(a === 169 && b === 254) && !(a === 172 && b >= 16 && b <= 31)
          && !(a === 192 && b === 168) && !(a === 100 && b >= 64 && b <= 127),
        'External check must not accept a local/private worker address');
      }
    }
    assert.equal(new Set(assignments.map(value => value.room_id)).size, 1);
    assert.equal(new Set(assignments.map(value => value.admission_ticket)).size, count);
    const peers = [];
    for (let index = 0; index < count; index++) {
      const config = path.join(run, `${label}-${index}.config.json`);
      const output = path.join(run, `${label}-${index}.json`);
      credentialFiles.push(config);
      await writeFile(config, JSON.stringify({ ...assignments[index], output,
        duel_lifecycle: count === 2, forfeit_peer: index === 0 }), { mode: 0o600 });
      peers.push(launch(`${label}-${index}`, godot, ['--headless', '--path', path.join(root, 'battlebots'),
        '--max-fps', '60', '--script', 'res://tests/services/hosted_playtest_peer.gd', '--', `--peer-config=${config}`]));
    }
    await Promise.all(peers.map(peer => completed(peer)));
    const evidence = [];
    for (let index = 0; index < count; index++) {
      const report = JSON.parse(await readFile(path.join(run, `${label}-${index}.json`), 'utf8'));
      assert.equal(report.valid, true);
      assert.equal(report.players, count);
      if (count === 2) {
        assert.equal(report.results_received, true);
        assert.equal(report.rematch_active, true);
        assert.equal(report.completed_rounds, 2);
        assert.equal(report.participants, 2);
      }
      evidence.push(report);
    }
    if (count === 2) {
      assert.equal(evidence[0].completed_match, evidence[1].completed_match);
      assert.deepEqual(evidence[0].scores, evidence[1].scores);
      assert.equal(evidence[0].winner, evidence[1].winner);
      assert.ok([0, 1].includes(evidence[0].team));
      assert.equal(evidence[1].team, 1 - evidence[0].team);
      assert.equal(evidence[0].winner, evidence[1].team, 'The peer that did not forfeit must win');
      assert.equal(evidence[0].scores[evidence[0].team], 0);
      assert.equal(evidence[0].scores[evidence[1].team], 2);
      assert.equal(evidence[0].rematch_id, evidence[1].rematch_id);
    }
    // Wait for worker disconnect status before cancelling reserved memberships.
    await delay(1500);
    for (const member of guests) await request('/v1/membership', member, 'DELETE');
    console.log(`HOSTED ${label.toUpperCase()} PASS: ${count} independent clients reached active and drove${count === 2 ? '; two public forfeit votes resolved rounds, results agreed and rematch became active (not natural combat acceptance)' : ''}`);
    return evidence;
  }
  const evidence = { private: await exercise('private', 2),
    ...(duelOnly ? {} : { queue: await exercise('queue', 4) }),
    build: compatibility.build, exported_server: managedService ? null : Boolean(serverBinary),
    service_origin: base, managed_service: managedService, external_endpoint: endpoint ? base : null };
  await writeFile(path.join(run, 'report.json'), JSON.stringify(evidence, null, 2));
  assert.equal(service?.crashSignature, undefined, `Service diagnostic: ${service?.crashSignature}; logs: ${run}`);
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
  // A failed check against a separately managed service must release its own reservations too. Never print
  // bearer tokens or keep admission files with the non-secret evidence bundle.
  if (managedService) {
    const cleanup = await Promise.allSettled(ownedGuests.map(member => request('/v1/membership', member, 'DELETE')));
    if (cleanup.some(result => result.status === 'rejected')) console.warn('Some test memberships could not be released; service leases will expire.');
  }
  const removed = await Promise.allSettled(credentialFiles.map(file => rm(file, { force: true })));
  if (removed.some(result => result.status === 'rejected')) console.warn('A temporary admission file could not be removed.');
}
