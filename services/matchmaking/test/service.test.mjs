import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createService } from '../service.mjs';

const manifest = { build: 'mvp-ab-10', protocol: 4, content_hash: 'a'.repeat(64) };

async function fixture(t, options = {}) {
  let now = 1000;
  const workers = [];
  const service = createService({ manifest, automaticMaintenance: false, guestsPerMinute: 100, ...options }, {
    clock: () => now,
    workerFactory: async (config, onExit) => {
      const worker = {
        config: structuredClone(config), writes: [structuredClone(config)], stopped: false, ready: false, phase: 'lobby', state: 'ready', connected: [],
        onExit, statusOverride: undefined,
        async update(next) { if (this.failWrite) throw new Error('private path/secret'); this.config = structuredClone(next); this.writes.push(structuredClone(next)); },
        async status() {
          if (this.statusOverride !== undefined) return this.statusOverride;
          return this.ready ? { allocation_id: config.allocation_id, ready: true, state: this.state, phase: this.phase, connected_players: this.connected, updated_at: now } : null;
        },
        async stop() { this.stopped = true; },
      };
      workers.push(worker);
      return worker;
    },
  });
  const address = await service.listen(0);
  const base = `http://127.0.0.1:${address.port}`;
  t.after(() => service.close());
  const request = async (path, method = 'GET', body, token, extra = {}) => {
    const response = await fetch(`${base}${path}`, {
      method, headers: { ...(body === undefined ? {} : { 'Content-Type': 'application/json' }), ...(token ? { Authorization: `Bearer ${token}` } : {}), ...extra.headers },
      ...(body === undefined ? {} : { body: typeof body === 'string' ? body : JSON.stringify(body) }),
    });
    return { status: response.status, body: await response.json(), headers: response.headers };
  };
  const guest = async () => {
    const response = await request('/v1/guests', 'POST', manifest);
    assert.equal(response.status, 200);
    return response.body;
  };
  return { service, workers, request, guest, advance: seconds => { now += seconds; }, now: () => now };
}

test('health and guest enforce exact release identity and bounded authentication', async t => {
  const f = await fixture(t, { guestTtl: 30 });
  assert.deepEqual((await f.request('/healthz')).body,
    { ...manifest, region: 'arn', queue_capacities: [2, 4], active_rooms: 0, connected_players: 0, persistence: 'memory' });
  for (const change of [{ build: 'old' }, { protocol: 3 }, { content_hash: 'b'.repeat(64) }]) {
    const bad = await f.request('/v1/guests', 'POST', { ...manifest, ...change });
    assert.equal(bad.status, 409); assert.equal(bad.body.error.code, 'version_mismatch');
  }
  const guest = await f.guest();
  assert.match(guest.access_token, /^[a-f0-9]{64}$/);
  assert.equal(guest.expires_at, 1030);
  assert.equal((await f.request('/v1/membership')).status, 401);
  assert.equal((await f.request('/v1/membership', 'GET', undefined, 'a'.repeat(64))).status, 401);
  assert.deepEqual((await f.request('/v1/membership', 'GET', undefined, guest.access_token)).body, { state: 'none', region: 'arn', players: 0 });
  f.advance(31);
  assert.equal((await f.request('/v1/membership', 'GET', undefined, guest.access_token)).status, 401);
});

test('private room withholds endpoint until fresh ready and publishes only ticket hashes to worker', async t => {
  const f = await fixture(t);
  const guest = await f.guest();
  const created = await f.request('/v1/rooms', 'POST', { mode: 'teams', capacity: 2 }, guest.access_token);
  assert.equal(created.body.state, 'starting'); assert.equal(created.body.assignment, undefined);
  assert.match(created.body.code, /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$/);
  assert.equal((await f.request('/healthz')).body.active_rooms, 1, 'An occupied room blocks automated deploys');
  const worker = f.workers[0];
  assert.equal(worker.config.port, 24570); assert.equal(worker.config.bind_address, '127.0.0.1');
  assert.equal(worker.config.schema, 1); assert.equal(worker.config.lease_expires_at, 1030);
  worker.ready = true;
  const ready = (await f.request('/v1/membership', 'GET', undefined, guest.access_token)).body;
  assert.equal(ready.state, 'ready'); assert.equal(ready.assignment.room_id, created.body.room_id);
  assert.equal(ready.assignment.address, '127.0.0.1');
  const ticket = ready.assignment.admission_ticket;
  assert.equal(worker.config.slots[0].ticket_hash, createHash('sha256').update(ticket, 'utf8').digest('hex'));
  assert.equal(JSON.stringify(worker.config).includes(ticket), false);
  assert.equal(worker.config.slots[0].player_id, guest.player_id);
  assert.equal(worker.config.slots[0].slot, 0);
  assert.match(worker.config.slots[0].reservation_id, /^[a-f0-9]{32}$/);
  assert.deepEqual((await f.request('/v1/membership', 'GET', undefined, guest.access_token)).body.assignment, ready.assignment);
  worker.statusOverride = { allocation_id: 'wrong', ready: true, state: 'ready', phase: 'lobby', connected_players: [], updated_at: f.now() };
  assert.equal((await f.request('/v1/membership', 'GET', undefined, guest.access_token)).body.assignment, undefined);
  f.advance(11);
  const failed = (await f.request('/v1/membership', 'GET', undefined, guest.access_token)).body;
  assert.equal(failed.state, 'failed'); assert.equal(worker.stopped, true);
});

test('private room capacity, stable slots, cancellation, and no active-match admission', async t => {
  const f = await fixture(t);
  const [a, b, c] = await Promise.all([f.guest(), f.guest(), f.guest()]);
  const room = (await f.request('/v1/rooms', 'POST', { mode: 'teams', capacity: 2 }, a.access_token)).body;
  f.workers[0].ready = true;
  assert.equal((await f.request('/v1/rooms/join', 'POST', { code: room.code }, b.access_token)).body.players, 2);
  assert.equal((await f.request('/v1/rooms/join', 'POST', { code: room.code }, c.access_token)).body.error.code, 'room_full');
  assert.equal((await f.request('/v1/queue', 'POST', {}, a.access_token)).body.error.code, 'already_member');
  await f.request('/v1/membership', 'DELETE', undefined, a.access_token);
  assert.equal(f.workers[0].config.slots[0].player_id, b.player_id);
  assert.equal(f.workers[0].config.slots[0].slot, 1);
  assert.equal((await f.request('/v1/rooms/join', 'POST', { code: room.code }, c.access_token)).status, 200);
  assert.equal(f.workers[0].config.slots.find(slot => slot.player_id === c.player_id).slot, 0);
  const previousReservation = f.workers[0].config.slots.find(slot => slot.player_id === c.player_id).reservation_id;
  await f.request('/v1/membership', 'DELETE', undefined, c.access_token);
  await f.request('/v1/rooms/join', 'POST', { code: room.code }, c.access_token);
  assert.notEqual(f.workers[0].config.slots.find(slot => slot.player_id === c.player_id).reservation_id, previousReservation);
  await f.request('/v1/membership', 'DELETE', undefined, c.access_token);
  f.workers[0].state = 'active'; f.workers[0].phase = 'active';
  assert.equal((await f.request('/v1/rooms/join', 'POST', { code: room.code }, a.access_token)).body.error.code, 'room_unavailable');
  await f.request('/v1/membership', 'DELETE', undefined, b.access_token);
  assert.equal(f.workers[0].stopped, true);
});

test('solo queue needs four, cancellation refills same pre-match worker, second group gets another worker', async t => {
  const f = await fixture(t);
  const guests = await Promise.all(Array.from({ length: 9 }, () => f.guest()));
  for (let i = 0; i < 3; ++i) {
    const result = (await f.request('/v1/queue', 'POST', {}, guests[i].access_token)).body;
    assert.equal(result.state, 'waiting'); assert.equal(result.players, i + 1); assert.equal(result.assignment, undefined);
  }
  assert.equal(f.workers.length, 0);
  await f.request('/v1/membership', 'DELETE', undefined, guests[1].access_token);
  assert.equal((await f.request('/v1/queue', 'POST', {}, guests[3].access_token)).body.players, 3);
  const allocated = (await f.request('/v1/queue', 'POST', {}, guests[4].access_token)).body;
  assert.equal(allocated.state, 'starting'); assert.equal(allocated.capacity, 4); assert.equal(allocated.mode, 'teams');
  assert.equal(f.workers.length, 1); assert.equal(f.workers[0].config.slots.length, 4);
  await f.request('/v1/membership', 'DELETE', undefined, guests[0].access_token);
  const replacement = (await f.request('/v1/queue', 'POST', {}, guests[5].access_token)).body;
  assert.equal(replacement.room_id, allocated.room_id); assert.equal(f.workers.length, 1);
  for (const i of [0, 1, 6, 7]) await f.request('/v1/queue', 'POST', {}, guests[i].access_token);
  assert.equal(f.workers.length, 2);
  assert.notEqual(f.workers[0].config.port, f.workers[1].config.port);
});

test('duel queue allocates one two-slot worker and shares its ready assignment', async t => {
  const f = await fixture(t);
  const [a, b] = await Promise.all([f.guest(), f.guest()]);
  const waiting = await f.request('/v1/queue', 'POST', { capacity: 2 }, a.access_token);
  assert.equal(waiting.status, 200);
  assert.equal(waiting.body.state, 'waiting');
  assert.equal(waiting.body.capacity, 2);
  assert.equal(waiting.body.players, 1);
  assert.equal(waiting.body.assignment, undefined);
  assert.equal(f.workers.length, 0);
  const allocated = await f.request('/v1/queue', 'POST', { capacity: 2 }, b.access_token);
  assert.equal(allocated.status, 200);
  assert.equal(allocated.body.room_id, waiting.body.room_id);
  assert.equal(allocated.body.state, 'starting');
  assert.equal(allocated.body.code, '');
  assert.equal(f.workers.length, 1);
  const worker = f.workers[0];
  assert.equal(worker.config.capacity, 2);
  assert.equal(worker.config.mode, 'teams');
  assert.deepEqual(worker.config.slots.map(slot => slot.player_id).sort(), [a.player_id, b.player_id].sort());
  assert.deepEqual(worker.config.slots.map(slot => slot.slot), [0, 1]);
  worker.ready = true;
  const assignments = await Promise.all([a, b].map(guest => f.request('/v1/membership', 'GET', undefined, guest.access_token)));
  for (const result of assignments) {
    assert.equal(result.body.state, 'ready');
    assert.equal(result.body.assignment.room_id, waiting.body.room_id);
    assert.equal(result.body.assignment.port, worker.config.port);
  }
  assert.notEqual(assignments[0].body.assignment.admission_ticket, assignments[1].body.assignment.admission_ticket);
  await f.service.maintenance();
  assert.equal(f.workers.length, 1);
});

test('duel, explicit four and legacy queues stay isolated by capacity', async t => {
  const f = await fixture(t);
  const guests = await Promise.all(Array.from({ length: 6 }, () => f.guest()));
  const duel = (await f.request('/v1/queue', 'POST', { capacity: 2 }, guests[0].access_token)).body;
  const four = (await f.request('/v1/queue', 'POST', { capacity: 4 }, guests[1].access_token)).body;
  const legacy = (await f.request('/v1/queue', 'POST', {}, guests[2].access_token)).body;
  assert.notEqual(duel.room_id, four.room_id);
  assert.equal(legacy.room_id, four.room_id);
  assert.equal(legacy.players, 2);
  assert.equal(f.workers.length, 0);
  const fullDuel = (await f.request('/v1/queue', 'POST', { capacity: 2 }, guests[3].access_token)).body;
  assert.equal(fullDuel.room_id, duel.room_id);
  assert.equal(f.workers.length, 1);
  assert.equal(f.workers[0].config.capacity, 2);
  for (const guest of guests.slice(4)) await f.request('/v1/queue', 'POST', {}, guest.access_token);
  assert.equal(f.workers.length, 2);
  assert.equal(f.workers[1].config.capacity, 4);
  assert.equal(f.workers[1].config.slots.length, 4);
  assert.equal(f.workers[1].config.slots.some(slot => [guests[0].player_id, guests[3].player_id].includes(slot.player_id)), false);
});

test('concurrent duel joins fill disjoint pairs without duplicate allocation or port reuse', async t => {
  const f = await fixture(t, { portCount: 3 });
  const guests = await Promise.all(Array.from({ length: 7 }, () => f.guest()));
  const responses = await Promise.all(guests.map(guest => f.request('/v1/queue', 'POST', { capacity: 2 }, guest.access_token)));
  assert.equal(responses.every(response => response.status === 200), true);
  assert.equal(f.workers.length, 3);
  assert.equal(new Set(f.workers.map(worker => worker.config.port)).size, 3);
  assert.equal(new Set(f.workers.flatMap(worker => worker.config.slots.map(slot => slot.player_id))).size, 6);
  assert.equal(f.workers.every(worker => worker.config.capacity === 2 && worker.config.slots.length === 2), true);
  const rooms = new Map();
  for (const { body } of responses) rooms.set(body.room_id, (rooms.get(body.room_id) ?? 0) + 1);
  assert.deepEqual([...rooms.values()].sort(), [1, 2, 2, 2]);
  await f.service.maintenance();
  assert.equal(f.workers.length, 3);
});

test('invalid duel queue parameters cannot allocate or create membership', async t => {
  const f = await fixture(t);
  const a = await f.guest();
  for (const body of [null, [], { capacity: null }, { capacity: 2.5 }, { capacity: 3 }, { capacity: 10 },
    { capacity: '2' }, { capacity: true }, { capacity: 0 }, { capacity: 2, mode: 'teams' }, { unknown: 2 }]) {
    const result = await f.request('/v1/queue', 'POST', body, a.access_token);
    assert.equal(result.status, 400, JSON.stringify(body));
    assert.equal((await f.request('/v1/membership', 'GET', undefined, a.access_token)).body.state, 'none');
    assert.equal(f.workers.length, 0);
  }
  const valid = await f.request('/v1/queue', 'POST', { capacity: 2 }, a.access_token);
  assert.equal(valid.status, 200);
  assert.equal(valid.body.players, 1);
});

test('a full duel waiting for a worker acquires the released port during maintenance', async t => {
  const f = await fixture(t, { portCount: 1 });
  const [owner, a, b] = await Promise.all([f.guest(), f.guest(), f.guest()]);
  await f.request('/v1/rooms', 'POST', { mode: 'teams', capacity: 2 }, owner.access_token);
  for (const guest of [a, b]) await f.request('/v1/queue', 'POST', { capacity: 2 }, guest.access_token);
  assert.equal(f.workers.length, 1);
  const waiting = (await f.request('/v1/membership', 'GET', undefined, a.access_token)).body;
  assert.equal(waiting.state, 'waiting');
  assert.equal(waiting.players, 2);
  assert.equal(waiting.assignment, undefined);
  await f.request('/v1/membership', 'DELETE', undefined, owner.access_token);
  await f.service.maintenance();
  assert.equal(f.workers[0].stopped, true);
  assert.equal(f.workers.length, 2);
  assert.equal(f.workers[1].config.port, f.workers[0].config.port);
  assert.equal(f.workers[1].config.capacity, 2);
  assert.equal(f.workers[1].config.slots.length, 2);
  assert.equal((await f.request('/v1/membership', 'GET', undefined, b.access_token)).body.room_id, waiting.room_id);
});

test('duel cancellation replaces pre-match slots but never admits into a started match', async t => {
  const f = await fixture(t);
  const [a, b, c, d] = await Promise.all([f.guest(), f.guest(), f.guest(), f.guest()]);
  const first = (await f.request('/v1/queue', 'POST', { capacity: 2 }, a.access_token)).body;
  await f.request('/v1/queue', 'POST', { capacity: 2 }, b.access_token);
  const worker = f.workers[0];
  const original = worker.config.slots.find(slot => slot.player_id === a.player_id);
  await f.request('/v1/membership', 'DELETE', undefined, a.access_token);
  const replacement = (await f.request('/v1/queue', 'POST', { capacity: 2 }, c.access_token)).body;
  assert.equal(replacement.room_id, first.room_id);
  assert.equal(f.workers.length, 1);
  const next = worker.config.slots.find(slot => slot.player_id === c.player_id);
  assert.equal(next.slot, original.slot);
  assert.notEqual(next.reservation_id, original.reservation_id);
  await f.request('/v1/membership', 'DELETE', undefined, c.access_token);
  worker.ready = true; worker.state = 'active'; worker.phase = 'active';
  const newQueue = (await f.request('/v1/queue', 'POST', { capacity: 2 }, d.access_token)).body;
  assert.notEqual(newQueue.room_id, first.room_id);
  assert.equal(newQueue.state, 'waiting');
  assert.equal(worker.config.slots.some(slot => slot.player_id === d.player_id), false);
  await f.request('/v1/membership', 'DELETE', undefined, b.access_token);
  assert.equal(worker.stopped, true);
  await f.request('/v1/membership', 'DELETE', undefined, d.access_token);
  assert.equal((await f.request('/v1/membership', 'GET', undefined, d.access_token)).body.state, 'none');
});

test('full worker pool never overallocates; waiting queue acquires released port', async t => {
  const f = await fixture(t, { portCount: 1 });
  const a = await f.guest();
  await f.request('/v1/rooms', 'POST', { mode: 'teams', capacity: 2 }, a.access_token);
  const guests = await Promise.all(Array.from({ length: 4 }, () => f.guest()));
  assert.equal((await f.request('/v1/rooms', 'POST', { mode: 'teams', capacity: 4 }, guests[0].access_token)).status, 503);
  for (const guest of guests) await f.request('/v1/queue', 'POST', {}, guest.access_token);
  assert.equal(f.workers.length, 1);
  assert.equal((await f.request('/v1/membership', 'GET', undefined, guests[0].access_token)).body.state, 'waiting');
  await f.request('/v1/membership', 'DELETE', undefined, a.access_token);
  await f.service.maintenance();
  assert.equal(f.workers.length, 2); assert.equal(f.workers[0].stopped, true);
  assert.equal(f.workers[1].config.port, 24570);
});

test('supported capacities only, bounded JSON input, and strict request shape', async t => {
  const f = await fixture(t);
  const a = await f.guest();
  for (const body of [{ mode: 'teams', capacity: 3 }, { mode: 'ffa', capacity: 9 }, { mode: 'ffa', capacity: 3 }, { mode: 'ranked', capacity: 4 }, { mode: 'teams', capacity: '4' }, { mode: 'teams', capacity: 4, executable: 'bad' }]) {
    assert.equal((await f.request('/v1/rooms', 'POST', body, a.access_token)).status, 400);
  }
  assert.equal((await f.request('/v1/guests', 'POST', '{')).status, 400);
  assert.equal((await f.request('/v1/guests', 'POST', 'x'.repeat(17_000))).status, 413);
  assert.equal((await f.request('/v1/guests', 'POST', manifest, undefined, { headers: { 'Content-Type': 'text/plain' } })).status, 415);
  assert.equal((await f.request('/v1/queue', 'POST', [], a.access_token)).status, 400);
  assert.equal((await f.request('/v1/membership?token=bad', 'GET', undefined, a.access_token)).status, 400);
  for (const [mode, capacity] of [['teams', 2], ['teams', 4], ['teams', 10], ['ffa', 4], ['ffa', 5], ['ffa', 6], ['ffa', 7], ['ffa', 8]]) {
    assert.equal((await f.request('/v1/rooms', 'POST', { mode, capacity }, a.access_token)).status, 200);
    await f.request('/v1/membership', 'DELETE', undefined, a.access_token);
  }
});

test('code expiry prevents new joins without dropping current room member', async t => {
  const f = await fixture(t, { codeTtl: 10 });
  const [a, b] = await Promise.all([f.guest(), f.guest()]);
  const room = (await f.request('/v1/rooms', 'POST', { mode: 'ffa', capacity: 8 }, a.access_token)).body;
  f.workers[0].ready = true;
  f.advance(11); await f.service.maintenance();
  assert.equal((await f.request('/v1/rooms/join', 'POST', { code: room.code }, b.access_token)).status, 404);
  assert.equal((await f.request('/v1/membership', 'GET', undefined, a.access_token)).body.state, 'ready');
});

test('crashed and stalled workers fail membership and reclaim ports', async t => {
  const f = await fixture(t, { portCount: 1, startupTimeout: 5 });
  const a = await f.guest();
  await f.request('/v1/rooms', 'POST', { mode: 'teams', capacity: 2 }, a.access_token);
  f.workers[0].onExit();
  const crashed = (await f.request('/v1/membership', 'GET', undefined, a.access_token)).body;
  assert.equal(crashed.state, 'failed'); assert.equal(crashed.assignment, undefined);
  assert.equal(f.workers[0].stopped, true);
  await f.request('/v1/membership', 'DELETE', undefined, a.access_token);
  await f.request('/v1/rooms', 'POST', { mode: 'teams', capacity: 2 }, a.access_token);
  f.advance(6); await f.service.maintenance();
  assert.equal((await f.request('/v1/membership', 'GET', undefined, a.access_token)).body.state, 'failed');
  assert.equal(f.workers[1].stopped, true);
});

test('leases refresh, tickets rotate near expiry, idle and total lifetime are bounded', async t => {
  const f = await fixture(t, { idleTtl: 150, roomTtl: 180 });
  const a = await f.guest();
  await f.request('/v1/rooms', 'POST', { mode: 'teams', capacity: 2 }, a.access_token);
  const worker = f.workers[0]; worker.ready = true;
  const first = (await f.request('/v1/membership', 'GET', undefined, a.access_token)).body;
  const reservation = worker.config.slots[0].reservation_id;
  f.advance(5); await f.service.maintenance();
  assert.equal(worker.config.lease_expires_at, 1035);
  f.advance(106);
  const second = (await f.request('/v1/membership', 'GET', undefined, a.access_token)).body;
  assert.notEqual(second.assignment.admission_ticket, first.assignment.admission_ticket);
  assert.equal(worker.config.slots[0].reservation_id, reservation);
  worker.connected = [a.player_id]; worker.state = 'active'; worker.phase = 'active';
  f.advance(40); await f.service.maintenance();
  // No connected heartbeat was sampled for the entire idle timeout, so the room expires.
  assert.equal((await f.request('/v1/membership', 'GET', undefined, a.access_token)).body.state, 'failed');
  await f.request('/v1/membership', 'DELETE', undefined, a.access_token);
  await f.request('/v1/rooms', 'POST', { mode: 'teams', capacity: 2 }, a.access_token);
  const next = f.workers[1]; next.ready = true; next.connected = [a.player_id]; next.state = 'active'; next.phase = 'active';
  for (let i = 0; i < 3; ++i) { f.advance(50); await f.service.maintenance(); }
  assert.equal((await f.request('/v1/membership', 'GET', undefined, a.access_token)).body.state, 'ready');
  f.advance(31); await f.service.maintenance();
  assert.equal((await f.request('/v1/membership', 'GET', undefined, a.access_token)).body.state, 'failed');
});

test('guest expiry revokes slot, queue expiry is visible, and shutdown owns cleanup', async t => {
  const f = await fixture(t, { guestTtl: 30, queueTtl: 10 });
  const a = await f.guest();
  await f.request('/v1/queue', 'POST', {}, a.access_token);
  f.advance(11); await f.service.maintenance();
  assert.equal((await f.request('/v1/membership', 'GET', undefined, a.access_token)).body.error, 'room_expired');
  await f.request('/v1/membership', 'DELETE', undefined, a.access_token);
  await f.request('/v1/rooms', 'POST', { mode: 'teams', capacity: 2 }, a.access_token);
  f.advance(20); await f.service.maintenance();
  assert.equal(f.workers[0].stopped, true);
  const b = await f.guest();
  await f.request('/v1/rooms', 'POST', { mode: 'teams', capacity: 2 }, b.access_token);
  await f.service.close();
  assert.equal(f.workers[1].stopped, true);
});

test('rate and storage limits reject cleanly without exposing secrets', async t => {
  const f = await fixture(t, { guestsPerMinute: 2, maxGuests: 2 });
  await f.guest(); await f.guest();
  const limited = await f.request('/v1/guests', 'POST', manifest);
  assert.equal(limited.status, 429); assert.equal(limited.body.error.code, 'rate_limited');
  f.advance(61);
  assert.equal((await f.request('/v1/guests', 'POST', manifest)).status, 503);
  assert.equal(limited.headers.get('cache-control'), 'no-store');
});

test('worker update failures are redacted and never yield a stale assignment', async t => {
  const f = await fixture(t);
  const a = await f.guest();
  await f.request('/v1/rooms', 'POST', { mode: 'teams', capacity: 2 }, a.access_token);
  f.workers[0].ready = true; f.workers[0].failWrite = true;
  const result = (await f.request('/v1/membership', 'GET', undefined, a.access_token)).body;
  assert.equal(result.state, 'failed'); assert.equal(result.assignment, undefined);
  assert.equal(JSON.stringify(result).includes('private'), false);
  assert.equal(f.workers[0].stopped, true);
});

test('Fly client address is trusted only with explicit proxy configuration', async t => {
  for (const trusted of [false, true]) {
    const f = await fixture(t, { trustFlyProxy: trusted, guestsPerMinute: 1 });
    const first = await f.request('/v1/guests', 'POST', manifest, undefined, { headers: { 'Fly-Client-IP': '192.0.2.1', 'X-Forwarded-For': '192.0.2.99' } });
    assert.equal(first.status, 200);
    const second = await f.request('/v1/guests', 'POST', manifest, undefined, { headers: { 'Fly-Client-IP': '192.0.2.2' } });
    assert.equal(second.status, trusted ? 200 : 429);
    const spoof = await f.request('/v1/guests', 'POST', manifest, undefined, { headers: { 'Fly-Client-IP': '192.0.2.1', 'X-Forwarded-For': '192.0.2.100' } });
    assert.equal(spoof.status, 429);
  }
});

test('durable players resume with rotating refresh tokens and keep their room (#16)', async t => {
  const f = await fixture(t, { guestTtl: 30 });
  const created = await f.request('/v1/players', 'POST', manifest);
  assert.equal(created.status, 200);
  assert.match(created.body.refresh_token, /^[a-f0-9]{64}$/);
  assert.match(created.body.access_token, /^[a-f0-9]{64}$/);
  assert.notEqual(created.body.refresh_token, created.body.access_token);
  const first = created.body;
  const room = await f.request('/v1/rooms', 'POST', { mode: 'teams', capacity: 2 }, first.access_token);
  assert.equal(room.status, 200);
  const resume = refresh => f.request('/v1/sessions', 'POST', { ...manifest, refresh_token: refresh });
  const resumed = await resume(first.refresh_token);
  assert.equal(resumed.status, 200);
  assert.equal(resumed.body.player_id, first.player_id);
  assert.notEqual(resumed.body.refresh_token, first.refresh_token);
  assert.equal((await f.request('/v1/membership', 'GET', undefined, first.access_token)).status, 401, 'Old access token is revoked');
  const membership = await f.request('/v1/membership', 'GET', undefined, resumed.body.access_token);
  assert.equal(membership.status, 200);
  assert.equal(membership.body.code, room.body.code, 'Resuming keeps the live room');
  // A lost response: the retired token still works briefly, then never again.
  assert.equal((await resume(first.refresh_token)).status, 200);
  f.advance(61);
  const stale = await resume(first.refresh_token);
  assert.equal(stale.status, 401); assert.equal(stale.body.error.code, 'invalid_refresh');
  assert.equal((await resume('f'.repeat(64))).status, 401);
  for (const bad of [{ ...manifest }, { ...manifest, refresh_token: 'short' }, { ...manifest, refresh_token: resumed.body.refresh_token, extra: 1 }]) {
    assert.equal((await f.request('/v1/sessions', 'POST', bad)).status, 400);
  }
  assert.equal((await f.request('/v1/sessions', 'POST', { ...manifest, build: 'old', refresh_token: resumed.body.refresh_token })).status, 409);
  // After the access token expires, the refresh token still restores the same player.
  f.advance(31);
  const later = await resume(resumed.body.refresh_token);
  assert.equal(later.status, 200); assert.equal(later.body.player_id, first.player_id);
  assert.equal(JSON.stringify(later.body).includes(resumed.body.refresh_token), false, 'Used refresh token is never echoed');
});

test('hosted results are recorded once for seated durable players and shown by /v1/me (#16)', async t => {
  const f = await fixture(t);
  const a = (await f.request('/v1/players', 'POST', manifest)).body;
  const b = await f.guest();
  await f.request('/v1/queue', 'POST', { capacity: 2 }, a.access_token);
  await f.request('/v1/queue', 'POST', { capacity: 2 }, b.access_token);
  const worker = f.workers[0];
  worker.ready = true;
  const stats = { damage: 120, eliminations: 1, assists: 0, credits: 40 };
  const result = { match_id: 'c'.repeat(24), mode: 'teams', arena: 'foundry', build: manifest.build, players: [
    { player: a.player_id, team: 0, won: true, ...stats },
    { player: b.player_id, team: 1, won: false, ...stats, damage: 30 }] };
  const publish = value => {
    worker.statusOverride = { allocation_id: worker.config.allocation_id, ready: true, state: 'active', phase: 'results',
      connected_players: [], updated_at: f.now(), result: value };
  };
  const me = async token => (await f.request('/v1/me', 'GET', undefined, token)).body;
  assert.deepEqual((await me(a.access_token)).matches, [], 'Nothing is recorded before results');
  for (const bad of [{ ...result, match_id: 'x' }, { ...result, mode: 'duel' },
    { ...result, players: [{ ...result.players[0], damage: -1 }] }, { ...result, players: [result.players[0], result.players[0]] }]) {
    publish(bad);
    await f.service.maintenance();
  }
  assert.deepEqual((await me(a.access_token)).matches, [], 'Malformed results are rejected');
  publish(result);
  await f.service.maintenance();
  await f.service.maintenance();
  const recorded = await me(a.access_token);
  assert.equal(recorded.player_id, a.player_id);
  assert.equal(recorded.matches.length, 1, 'One result per match, however often it is polled');
  assert.deepEqual(recorded.matches[0], { match_id: result.match_id, mode: 'teams', arena: 'foundry', ended_at: f.now(),
    team: 0, won: true, ...stats });
  assert.deepEqual((await me(b.access_token)).matches, [], 'Anonymous guests have no durable record');
  // A worker cannot credit someone without a seat in its room.
  publish({ ...result, match_id: 'e'.repeat(24), players: [{ ...result.players[0], player: 'd'.repeat(32) }] });
  await f.service.maintenance();
  assert.equal((await me(a.access_token)).matches.length, 1, 'Unseated players are never recorded');
  assert.equal((await f.request('/v1/me')).status, 401);
});
