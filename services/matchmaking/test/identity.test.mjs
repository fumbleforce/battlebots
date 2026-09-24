import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { openIdentityStore, SCHEMA_VERSION } from '../identity.mjs';

test('identities on disk survive a restart; raw tokens are never stored', t => {
  const dir = mkdtempSync(path.join(tmpdir(), 'identity-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const file = path.join(dir, 'players.db');
  const first = openIdentityStore({ path: file });
  assert.equal(first.durable, true);
  const player = first.createPlayer(1000);
  first.close();
  const raw = new DatabaseSync(file);
  const hashes = raw.prepare('SELECT hash FROM refresh_tokens').all().map(row => row.hash);
  assert.equal(hashes.includes(player.refreshToken), false);
  assert.equal(raw.prepare('SELECT version FROM schema_version').get().version, SCHEMA_VERSION);
  raw.close();
  const second = openIdentityStore({ path: file });
  const resumed = second.rotate(player.refreshToken, 1010);
  assert.equal(resumed.playerId, player.playerId);
  assert.equal(second.playerCount(), 1);
  second.close();
});

test('a database from a newer service is refused, and the overlap is bounded', t => {
  const dir = mkdtempSync(path.join(tmpdir(), 'identity-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const file = path.join(dir, 'players.db');
  openIdentityStore({ path: file }).close();
  const raw = new DatabaseSync(file);
  raw.prepare('UPDATE schema_version SET version = ?').run(SCHEMA_VERSION + 1);
  raw.close();
  assert.throws(() => openIdentityStore({ path: file }), /newer/);
  const store = openIdentityStore({ overlap: 5 });
  const player = store.createPlayer(0);
  const next = store.rotate(player.refreshToken, 10);
  assert.ok(store.rotate(player.refreshToken, 14), 'retired token works inside the overlap');
  assert.equal(store.rotate(player.refreshToken, 16), null, 'and never after it');
  assert.ok(store.rotate(next.refreshToken, 16));
  assert.equal(store.rotate('not-a-token', 16), null);
  store.close();
});
