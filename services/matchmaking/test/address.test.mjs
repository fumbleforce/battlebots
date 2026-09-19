import test from 'node:test';
import assert from 'node:assert/strict';
import { resolveGameAddress } from '../address.mjs';

test('literal public IPv4 bypasses DNS, including the local test endpoint', async () => {
  assert.equal(await resolveGameAddress('127.0.0.1', () => { throw new Error('DNS must not run'); }), '127.0.0.1');
});

test('public hostname resolves explicitly to IPv4 for ENet assignment', async () => {
  const resolved = await resolveGameAddress('game.example.test', async (hostname, options) => {
    assert.equal(hostname, 'game.example.test');
    assert.deepEqual(options, { family: 4 });
    return { address: '192.0.2.17', family: 4 };
  });
  assert.equal(resolved, '192.0.2.17');
});

test('missing, IPv6, and failed DNS endpoints fail with redacted errors', async () => {
  for (const input of ['', '::1', 'https://game.example.test', 'bad host']) {
    await assert.rejects(() => resolveGameAddress(input), { message: 'Invalid public game address' });
  }
  await assert.rejects(() => resolveGameAddress('private.example.test', async () => {
    throw new Error('resolver details including private.example.test');
  }), { message: 'Public game IPv4 address unavailable' });
  await assert.rejects(() => resolveGameAddress('game.example.test', async () => ({ address: '::1', family: 6 })), {
    message: 'Public game IPv4 address unavailable',
  });
});
