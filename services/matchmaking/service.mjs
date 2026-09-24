import http from 'node:http';
import { isIP } from 'node:net';
import { createHash, randomBytes, randomInt } from 'node:crypto';
import { openIdentityStore, validRefreshToken } from './identity.mjs';

const digest = value => createHash('sha256').update(value, 'utf8').digest('hex');
const secret = () => randomBytes(32).toString('hex');
const roomId = () => randomBytes(16).toString('hex');
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const FRIEND_CODE = /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$/;
const none = region => ({ state: 'none', region, players: 0 });
const count = value => Number.isInteger(value) && value >= 0 && value <= 1_000_000;
// A worker's match result (#16 Step B, record only), bounded and exact. Only
// players still seated in that room are recorded (see inspectWorker).
function validResult(result, room) {
  const players = result?.players;
  return result && typeof result === 'object' && typeof result.match_id === 'string' && /^[a-f0-9]{24}$/.test(result.match_id)
    && ['teams', 'ffa'].includes(result.mode) && typeof result.arena === 'string' && /^[a-z]{1,16}$/.test(result.arena)
    && typeof result.build === 'string' && result.build.length <= 64
    && Array.isArray(players) && players.length >= 1 && players.length <= room.capacity
    && new Set(players.map(player => player?.player)).size === players.length
    && players.every(player => player && typeof player === 'object' && typeof player.player === 'string' && /^[a-f0-9]{32}$/.test(player.player)
      && Number.isInteger(player.team) && player.team >= 0 && player.team <= 16 && typeof player.won === 'boolean'
      && count(player.damage) && count(player.eliminations) && count(player.assists) && count(player.credits));
}
class ApiError extends Error {
  constructor(status, code, message) { super(message); this.status = status; this.code = code; }
}
function reject(status, code, message) { throw new ApiError(status, code, message); }
function exactKeys(body, keys) {
  if (!body || typeof body !== 'object' || Array.isArray(body) || Object.keys(body).some(key => !keys.includes(key))) {
    reject(400, 'invalid_request', 'Invalid request fields.');
  }
}

export function createService(options, { workerFactory, identity = null, clock = () => Date.now() / 1000, log = () => {} } = {}) {
  const config = {
    region: 'arn', publicAddress: '127.0.0.1', bindAddress: '127.0.0.1',
    firstPort: 24570, portCount: 4, guestTtl: 7200, ticketTtl: 120,
    roomTtl: 7200, idleTtl: 600, codeTtl: 600, queueTtl: 600,
    startupTimeout: 45, statusTtl: 10, leaseTtl: 30, leaseRefresh: 5,
    maxGuests: 1024, maxRooms: 128, requestsPerMinute: 180,
    guestsPerMinute: 12, maxRateEntries: 4096, ...options,
  };
  if (!config.manifest || typeof config.manifest.build !== 'string' || !Number.isInteger(config.manifest.protocol)
      || !/^[a-f0-9]{64}$/.test(config.manifest.content_hash ?? '')) throw new Error('Invalid build manifest');
  if (typeof workerFactory !== 'function') throw new Error('workerFactory is required');
  if (!Number.isInteger(config.firstPort) || !Number.isInteger(config.portCount) || config.firstPort < 1024
      || config.portCount < 1 || config.portCount > 16 || config.firstPort + config.portCount > 65536) throw new Error('Invalid worker port pool');
  for (const key of ['guestTtl', 'ticketTtl', 'roomTtl', 'idleTtl', 'codeTtl', 'queueTtl', 'startupTimeout', 'statusTtl', 'leaseTtl', 'leaseRefresh', 'maxGuests', 'maxRooms', 'requestsPerMinute', 'guestsPerMinute', 'maxRateEntries']) {
    if (!Number.isFinite(config[key]) || config[key] <= 0) throw new Error(`Invalid ${key}`);
  }
  // Durable players (#16): in memory unless the caller passes a store on disk.
  const identities = identity ?? openIdentityStore();
  const guests = new Map(); // Token hashes only; the access token is returned once.
  const players = new Map();
  const rooms = new Map();
  const codes = new Map();
  const rates = new Map();
  const ports = new Set();
  let closed = false;
  let sequence = Promise.resolve();
  let pending = 0;
  const serialized = fn => {
    ++pending;
    const result = sequence.then(fn);
    sequence = result.catch(() => {}).finally(() => { --pending; });
    return result;
  };
  const rateLimit = (key, limit) => {
    const now = clock();
    let bucket = rates.get(key);
    if (!bucket || now >= bucket.reset) {
      if (!bucket && rates.size >= config.maxRateEntries) {
        for (const [oldKey, old] of rates) if (now >= old.reset) rates.delete(oldKey);
        if (rates.size >= config.maxRateEntries) reject(429, 'rate_limited', 'Please try again later.');
      }
      bucket = { reset: now + 60, count: 0 };
      rates.set(key, bucket);
    }
    if (++bucket.count > limit) reject(429, 'rate_limited', 'Please try again later.');
  };
  const workerConfig = room => ({
    schema: 1, allocation_id: room.id, ...config.manifest,
    port: room.port, bind_address: config.bindAddress, mode: room.mode, capacity: room.capacity,
    lease_expires_at: Math.floor(clock() + config.leaseTtl),
    slots: [...room.members.values()].map(member => ({
      slot: member.slot, player_id: member.playerId, reservation_id: member.reservationId, ticket_hash: member.ticketHash,
      expires_at: Math.floor(member.ticketExpires),
    })),
  });
  const refreshConfig = async room => {
    if (!room.worker || room.state === 'failed') return;
    await room.worker.update(workerConfig(room));
    room.lastLease = clock();
  };
  const stopWorker = async room => {
    const worker = room.worker;
    room.worker = null;
    if (worker) {
      try { await worker.stop(); } catch { log('worker_stop_failed'); }
    }
    if (room.port !== null) ports.delete(room.port);
    room.port = null;
  };
  const failRoom = async (room, reason) => {
    if (room.state === 'failed') return;
    room.state = 'failed';
    room.failure = reason;
    codes.delete(room.code);
    await stopWorker(room);
  };
  const destroyRoom = async room => {
    codes.delete(room.code);
    rooms.delete(room.id);
    for (const member of room.members.values()) {
      const guest = players.get(member.playerId);
      if (guest?.roomId === room.id) guest.roomId = null;
    }
    await stopWorker(room);
  };
  const allocate = async room => {
    if (closed || room.worker || room.state === 'failed') return;
    let port;
    for (let candidate = config.firstPort; candidate < config.firstPort + config.portCount; ++candidate) {
      if (!ports.has(candidate)) { port = candidate; break; }
    }
    if (port === undefined) return;
    ports.add(port);
    room.port = port;
    room.state = 'starting';
    room.started = clock();
    room.lastLease = clock();
    try {
      room.worker = await workerFactory(workerConfig(room), () => {
        void serialized(async () => {
          if (rooms.get(room.id) === room && room.worker) await failRoom(room, 'server_unavailable');
        });
      });
    } catch {
      log('worker_start_failed');
      await failRoom(room, 'server_unavailable');
    }
  };
  const roomJoinable = room => room.state !== 'failed' && !room.startedMatch
    && clock() < room.created + config.roomTtl && (room.isQueue || clock() < room.codeExpires);
  const addMember = async (room, guest) => {
    if (!roomJoinable(room)) reject(409, 'room_unavailable', 'This room is no longer accepting players.');
    if (room.members.size >= room.capacity) reject(409, 'room_full', 'This room is full.');
    let slot = 0;
    const occupied = new Set([...room.members.values()].map(member => member.slot));
    while (occupied.has(slot)) ++slot;
    // Invalid, unknowable placeholder until the worker is ready. No endpoint or ticket is exposed yet.
    room.members.set(guest.id, { slot, playerId: guest.id, reservationId: roomId(), ticket: null, ticketHash: digest(secret()), ticketExpires: clock() + config.ticketTtl });
    guest.roomId = room.id;
    room.lastActivity = clock();
    try { await refreshConfig(room); } catch { await failRoom(room, 'server_unavailable'); }
  };
  const removeMember = async guest => {
    const room = rooms.get(guest.roomId);
    guest.roomId = null;
    if (!room) return;
    room.members.delete(guest.id);
    if (room.members.size === 0) await destroyRoom(room);
    else {
      try { await refreshConfig(room); } catch { await failRoom(room, 'server_unavailable'); }
    }
  };
  const inspectWorker = async room => {
    if (!room.worker || room.state === 'failed') return;
    let status;
    try { status = await room.worker.status(); } catch { status = null; }
    const now = clock();
    const valid = status && status.allocation_id === room.id && status.ready === true
      && ['ready', 'active', 'draining'].includes(status.state)
      && Number.isFinite(status.updated_at) && status.updated_at <= now + 2 && status.updated_at >= now - config.statusTtl
      && Array.isArray(status.connected_players) && status.connected_players.length <= room.capacity
      && status.connected_players.every(id => typeof id === 'string' && id.length <= 128)
      && typeof status.phase === 'string' && status.phase.length <= 32;
    if (valid) {
      if (status.state === 'draining') { await failRoom(room, 'server_draining'); return; }
      room.lastStatus = status.updated_at;
      room.status = status;
      if (status.state === 'active' || !['offline', 'lobby'].includes(status.phase)) room.startedMatch = true;
      if (status.connected_players.length) room.lastActivity = now;
      room.state = 'ready';
      if (status.result !== undefined && status.result?.match_id !== room.recorded) {
        if (validResult(status.result, room)) {
          room.recorded = status.result.match_id;
          const seated = { ...status.result, players: status.result.players.filter(player => room.members.has(player.player)) };
          try { identities.recordMatch(seated, now); } catch { log(JSON.stringify({ event: 'result_record_failed', room_id: room.id })); }
        } else log(JSON.stringify({ event: 'result_rejected', room_id: room.id }));
      }
    } else if ((room.lastStatus !== null && now - room.lastStatus > config.statusTtl)
      || (room.lastStatus === null && now - room.started > config.startupTimeout)) {
      await failRoom(room, 'server_unavailable');
    } else room.state = 'starting';
  };
  const membership = async guest => {
    const room = rooms.get(guest.roomId);
    if (!room) { guest.roomId = null; return none(config.region); }
    await inspectWorker(room);
    const result = {
      state: room.state, room_id: room.id, code: room.isQueue ? '' : room.code,
      capacity: room.capacity, mode: room.mode, region: config.region, players: room.members.size,
    };
    if (room.state === 'failed') result.error = room.failure;
    if (room.state === 'ready') {
      const member = room.members.get(guest.id);
      if (!member.ticket || member.ticketExpires <= clock() + 10) {
        member.ticket = secret();
        member.ticketHash = digest(member.ticket);
        member.ticketExpires = Math.min(clock() + config.ticketTtl, guest.expires);
        try { await refreshConfig(room); } catch {
          await failRoom(room, 'server_unavailable');
          result.state = 'failed'; result.error = room.failure; return result;
        }
      }
      result.assignment = { address: config.publicAddress, port: room.port, admission_ticket: member.ticket, room_id: room.id };
    }
    return result;
  };
  const makeRoom = (mode, capacity, isQueue = false) => {
    if (rooms.size >= config.maxRooms) reject(503, 'capacity_unavailable', 'All rooms are busy. Please try again later.');
    let code;
    do { code = Array.from({ length: 8 }, () => CODE_ALPHABET[randomInt(CODE_ALPHABET.length)]).join(''); } while (codes.has(code));
    const room = {
      id: roomId(), code, mode, capacity, isQueue, state: 'waiting', members: new Map(),
      created: clock(), codeExpires: clock() + config.codeTtl, lastActivity: clock(),
      worker: null, port: null, lastStatus: null, status: null, startedMatch: false,
    };
    rooms.set(room.id, room);
    if (!isQueue) codes.set(code, room.id);
    return room;
  };
  const maintain = async () => {
    const now = clock();
    for (const [tokenHash, guest] of guests) {
      if (guest.expires <= now) {
        await removeMember(guest); guests.delete(tokenHash);
        if (players.get(guest.id) === guest) players.delete(guest.id);
      }
    }
    for (const room of [...rooms.values()]) {
      if (now >= room.codeExpires) codes.delete(room.code);
      if (room.state === 'failed') {
        if (now - room.created >= config.roomTtl) await destroyRoom(room);
        continue;
      }
      if (now - room.created >= config.roomTtl || now - room.lastActivity >= config.idleTtl
          || (room.isQueue && !room.worker && now - room.created >= config.queueTtl)) {
        await failRoom(room, 'room_expired'); continue;
      }
      await inspectWorker(room);
      if (room.worker && now - room.lastLease >= config.leaseRefresh) {
        try { await refreshConfig(room); } catch { await failRoom(room, 'server_unavailable'); }
      }
      if (room.isQueue && room.state === 'waiting' && room.members.size === room.capacity) await allocate(room);
    }
    for (const [key, rate] of rates) if (now >= rate.reset) rates.delete(key);
  };
  const auth = req => {
    const header = req.headers.authorization;
    if (typeof header !== 'string' || !/^Bearer [a-f0-9]{64}$/.test(header)) reject(401, 'unauthorized', 'Sign in again to continue.');
    const guest = guests.get(digest(header.slice(7)));
    if (!guest || guest.expires <= clock()) reject(401, 'unauthorized', 'Sign in again to continue.');
    rateLimit(`player:${guest.id}`, config.requestsPerMinute);
    return guest;
  };
  const route = async (req, body, pathname) => {
    if (closed) reject(503, 'unavailable', 'Service is shutting down.');
    const method = req.method;
    if (method === 'GET' && pathname === '/healthz') {
      // Occupancy lets automated deploys wait for a playtest break: a restart
      // ends every room on this single Machine.
      const occupied = [...rooms.values()].filter(room => room.members.size > 0);
      const connected = occupied.reduce((total, room) => total + (room.status?.connected_players?.length ?? 0), 0);
      return { ...config.manifest, region: config.region, queue_capacities: [2, 4],
        active_rooms: occupied.length, connected_players: connected,
        persistence: identities.degraded ? 'degraded' : (identities.durable ? 'disk' : 'memory') };
    }
    // Enable only behind Fly's trusted HTTP proxy. Never honor arbitrary X-Forwarded-For.
    const flyAddress = req.headers['fly-client-ip'];
    const address = config.trustFlyProxy === true && typeof flyAddress === 'string' && isIP(flyAddress)
      ? flyAddress : req.socket.remoteAddress;
    rateLimit(`ip:${address}`, config.requestsPerMinute * 4);
    if (method === 'POST' && ['/v1/guests', '/v1/players', '/v1/sessions'].includes(pathname)) {
      rateLimit(`guest:${address}`, config.guestsPerMinute);
      const fields = ['build', 'protocol', 'content_hash'];
      exactKeys(body, pathname === '/v1/sessions' ? [...fields, 'refresh_token'] : fields);
      if (body.build !== config.manifest.build || body.protocol !== config.manifest.protocol || body.content_hash !== config.manifest.content_hash) {
        reject(409, 'version_mismatch', 'Update the game to join this service.');
      }
      await maintain();
      let playerId = roomId();
      let refreshToken = null;
      if (pathname === '/v1/sessions') {
        if (!validRefreshToken(body.refresh_token)) reject(400, 'invalid_request', 'Invalid request fields.');
        const resumed = identities.rotate(body.refresh_token, clock());
        if (!resumed) reject(401, 'invalid_refresh', 'Your saved online identity could not be restored.');
        ({ playerId, refreshToken } = resumed);
      }
      // A resumed player keeps its live session (and any room); its old
      // access token stops working.
      let guest = players.get(playerId);
      if (!guest && guests.size >= config.maxGuests) reject(503, 'capacity_unavailable', 'Service is busy. Please try again later.');
      if (pathname === '/v1/players') ({ playerId, refreshToken } = identities.createPlayer(clock()));
      if (guest) guests.delete(guest.tokenHash);
      else guest = { id: playerId, roomId: null };
      const token = secret();
      guest.tokenHash = digest(token);
      guest.expires = Math.floor(clock() + config.guestTtl);
      guests.set(guest.tokenHash, guest); players.set(guest.id, guest);
      const reply = { player_id: guest.id, access_token: token, expires_at: guest.expires, region: config.region };
      return refreshToken === null ? reply : { ...reply, refresh_token: refreshToken };
    }
    const guest = auth(req);
    if (pathname === '/v1/me' && method === 'GET') {
      return { player_id: guest.id, matches: identities.recentMatches(guest.id) };
    }
    if (pathname === '/v1/membership' && method === 'GET') return membership(guest);
    if (pathname === '/v1/membership' && method === 'DELETE') { await removeMember(guest); return none(config.region); }
    if (method !== 'POST') reject(404, 'not_found', 'Route not found.');
    if (!['/v1/rooms', '/v1/rooms/join', '/v1/queue'].includes(pathname)) reject(404, 'not_found', 'Route not found.');
    rateLimit(`mutation:${guest.id}`, 30);
    if (guest.roomId && rooms.has(guest.roomId)) reject(409, 'already_member', 'Leave the current room or queue first.');
    if (pathname === '/v1/rooms') {
      exactKeys(body, ['mode', 'capacity']);
      if (!Number.isInteger(body.capacity) || !((body.mode === 'teams' && [2, 4, 10].includes(body.capacity))
        || (body.mode === 'ffa' && body.capacity >= 4 && body.capacity <= 8))) reject(400, 'invalid_room', 'Choose a supported mode and player count.');
      if (ports.size >= config.portCount) reject(503, 'capacity_unavailable', 'All game servers are busy. Please try again later.');
      const room = makeRoom(body.mode, body.capacity);
      await addMember(room, guest);
      await allocate(room);
      return membership(guest);
    }
    if (pathname === '/v1/rooms/join') {
      exactKeys(body, ['code']);
      if (typeof body.code !== 'string' || !FRIEND_CODE.test(body.code)) reject(400, 'invalid_code', 'Enter the eight-character room code.');
      const room = rooms.get(codes.get(body.code));
      if (!room || !roomJoinable(room)) reject(404, 'room_unavailable', 'This room code is unavailable or expired.');
      await inspectWorker(room);
      await addMember(room, guest);
      return membership(guest);
    }
    exactKeys(body, ['capacity']);
    const capacity = Object.hasOwn(body, 'capacity') ? body.capacity : 4;
    if (!Number.isInteger(capacity) || ![2, 4].includes(capacity)) reject(400, 'invalid_queue', 'Choose a supported queue size.');
    let room = [...rooms.values()].find(candidate => candidate.isQueue && candidate.capacity === capacity
      && roomJoinable(candidate) && candidate.members.size < candidate.capacity);
    if (!room) room = makeRoom('teams', capacity, true);
    await inspectWorker(room);
    // A status refresh can reveal a match started since the previous request.
    if (!roomJoinable(room)) room = makeRoom('teams', capacity, true);
    await addMember(room, guest);
    if (room.members.size === room.capacity) await allocate(room);
    return membership(guest);
  };
  const server = http.createServer(async (req, res) => {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    try {
      if (pending >= 256) reject(503, 'busy', 'Please try again later.');
      if ((req.url?.length ?? 0) > 256) reject(414, 'invalid_request', 'Request URL is too long.');
      const url = new URL(req.url, 'http://localhost');
      if (url.search) reject(400, 'invalid_request', 'Query parameters are not supported.');
      const chunks = [];
      let length = 0;
      if (Number(req.headers['content-length']) > 16_384) reject(413, 'body_too_large', 'Request is too large.');
      for await (const chunk of req) {
        length += chunk.length;
        if (length > 16_384) reject(413, 'body_too_large', 'Request is too large.');
        chunks.push(chunk);
      }
      let body = {};
      if (req.method === 'POST') {
        if (!(req.headers['content-type'] ?? '').toLowerCase().startsWith('application/json')) reject(415, 'invalid_content_type', 'Use application/json.');
        try { body = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
        catch { reject(400, 'invalid_json', 'Request body must be valid JSON.'); }
      } else if (length) reject(400, 'invalid_request', 'This request must not include a body.');
      const result = await serialized(() => route(req, body, url.pathname));
      res.writeHead(200); res.end(JSON.stringify(result));
    } catch (error) {
      const known = error instanceof ApiError;
      if (!known) log('request_failed');
      if (!res.headersSent) res.writeHead(known ? error.status : 503);
      res.end(JSON.stringify({ error: { code: known ? error.code : 'server_unavailable', message: known ? error.message : 'The game service is temporarily unavailable.' } }));
    }
  });
  server.requestTimeout = 10_000;
  server.headersTimeout = 10_000;
  server.keepAliveTimeout = 5000;
  server.maxConnections = 256;
  server.maxRequestsPerSocket = 300;
  server.on('clientError', (_error, socket) => { socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n'); });
  const timer = options?.automaticMaintenance === false ? null : setInterval(() => {
    void serialized(maintain).catch(() => log('maintenance_failed'));
  }, 1000);
  timer?.unref();
  return {
    server,
    maintenance: () => serialized(maintain),
    async listen(port = 8080, host = '127.0.0.1') {
      await new Promise((resolve, rejectListen) => {
        server.once('error', rejectListen);
        server.listen(port, host, () => { server.off('error', rejectListen); resolve(); });
      });
      return server.address();
    },
    async close() {
      clearInterval(timer);
      await serialized(async () => {
        closed = true;
        for (const room of [...rooms.values()]) await destroyRoom(room);
      });
      await new Promise(resolve => server.close(resolve));
      if (!identity) identities.close();
    },
  };
}
