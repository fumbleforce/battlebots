// Deploy the prepared hosted server to Fly during a playtest break, prove the
// live release matches this commit, and roll back if acceptance fails.
// Requires: `node tools/prepare-hosted.mjs` output, flyctl on PATH, FLY_API_TOKEN.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

const { values } = parseArgs({ options: {
  godot: { type: 'string', default: 'godot' },
  app: { type: 'string', default: 'battlebots-fumbleforce' },
  endpoint: { type: 'string', default: 'https://battlebots-fumbleforce.fly.dev' },
  // A restart ends every running match on the single Machine: wait for a break.
  'break-timeout-minutes': { type: 'string', default: '45' },
  'skip-acceptance': { type: 'boolean', default: false },
} });
const BREAK_POLL_SECONDS = 30;
const HEALTH_TIMEOUT_SECONDS = 300;
const HEALTH_POLL_SECONDS = 10;
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const serverDirectory = path.join(root, 'battlebots', 'exports', 'hosted-server');
const manifest = JSON.parse(readFileSync(path.join(serverDirectory, 'manifest.json'), 'utf8'));
const record = JSON.parse(readFileSync(path.join(serverDirectory, 'build-record.json'), 'utf8'));
const sleep = seconds => new Promise(resolve => setTimeout(resolve, seconds * 1000));

function run(binary, args, { capture = false } = {}) {
  const result = spawnSync(binary, args, { cwd: root, encoding: 'utf8', shell: false,
    stdio: capture ? ['ignore', 'pipe', 'inherit'] : 'inherit', maxBuffer: 64 * 1024 * 1024 });
  assert.ifError(result.error);
  assert.equal(result.status, 0, `${binary} ${args[0]} failed (${result.signal ?? result.status})`);
  return result.stdout ?? '';
}

async function health() {
  try {
    const response = await fetch(`${values.endpoint}/healthz`, { signal: AbortSignal.timeout(10000) });
    return response.ok ? await response.json() : null;
  } catch { return null; }
}

const matches = live => live && live.build === manifest.build && live.protocol === manifest.protocol
  && live.content_hash === manifest.content_hash;

function describe(live) {
  return live ? `${live.build} protocol ${live.protocol} hash ${String(live.content_hash).slice(0, 12)}` : 'unreachable';
}

async function waitForBreak() {
  const deadline = Date.now() + Number(values['break-timeout-minutes']) * 60000;
  for (;;) {
    const live = await health();
    if (live && live.active_rooms === undefined) {
      console.log('Live service predates occupancy reporting; deploying without a break check.');
      return;
    }
    if (!live || live.active_rooms === 0) return;
    assert.ok(Date.now() < deadline,
      `Playtest still running (${live.active_rooms} rooms, ${live.connected_players} players); not restarting it.`);
    console.log(`Waiting for a playtest break: ${live.active_rooms} rooms, ${live.connected_players} players connected.`);
    await sleep(BREAK_POLL_SECONDS);
  }
}

function deploy(image) {
  const args = ['deploy', '.', '--app', values.app, '--config', 'services/matchmaking/fly.toml',
    '--ha=false', '--strategy', 'immediate', '--yes'];
  if (image) args.push('--image', image);
  else args.push('--dockerfile', 'services/matchmaking/Dockerfile', '--ignorefile', '.dockerignore', '--remote-only');
  run('flyctl', args);
}

async function waitForRelease() {
  const deadline = Date.now() + HEALTH_TIMEOUT_SECONDS * 1000;
  let live = null;
  while (Date.now() < deadline) {
    live = await health();
    if (matches(live)) return live;
    await sleep(HEALTH_POLL_SECONDS);
  }
  throw new Error(`Live service did not report this release; it reports ${describe(live)}`);
}

const before = await health();
console.log(`Deploying ${manifest.build} protocol ${manifest.protocol} from ${record.commit}; live: ${describe(before)}`);
if (matches(before)) {
  console.log('HOSTED RELEASE ALREADY LIVE');
  process.exit(0);
}
const machines = JSON.parse(run('flyctl', ['machine', 'list', '--app', values.app, '--json'], { capture: true }));
assert.equal(machines.length, 1, 'The allocator must run on exactly one Machine');
const previousImage = machines[0].config.image;
console.log(`Rollback image: ${previousImage}`);
await waitForBreak();
deploy();
try {
  const live = await waitForRelease();
  console.log(`Live release matches: ${describe(live)}`);
  if (!values['skip-acceptance']) {
    run(process.execPath, ['tools/check-hosted.mjs', '--godot', values.godot, '--endpoint', values.endpoint, '--duel-only']);
  }
} catch (error) {
  console.error(`Hosted acceptance failed: ${error.message}. Rolling back to ${previousImage}.`);
  deploy(previousImage);
  throw error;
}
console.log(`HOSTED RELEASE DEPLOYED: ${manifest.build} protocol ${manifest.protocol} from ${record.commit}`);
