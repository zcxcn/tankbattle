import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';
import WebSocket from 'ws';
import { createSignalingServer } from '../server.mjs';

const active = [];

afterEach(async () => {
  while (active.length) await active.pop().close();
});

async function start(options = {}) {
  const server = await createSignalingServer({ host: '127.0.0.1', port: 0, ...options });
  active.push(server);
  return `ws://127.0.0.1:${server.address.port}/ws`;
}

async function connect(url, origin = 'https://zcxcn.github.io') {
  const ws = new WebSocket(url, { origin });
  const inbox = [];
  const waiters = [];
  ws.on('message', (bytes) => {
    const message = JSON.parse(bytes.toString());
    const waiter = waiters.shift();
    if (waiter) waiter(message);
    else inbox.push(message);
  });
  await new Promise((resolve, reject) => {
    ws.once('open', resolve);
    ws.once('error', reject);
  });
  return {
    ws,
    send(message) { ws.send(JSON.stringify(message)); },
    next() {
      if (inbox.length) return Promise.resolve(inbox.shift());
      return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => reject(new Error('Timed out waiting for signal')), 1200);
        waiters.push((message) => {
          clearTimeout(timeout);
          resolve(message);
        });
      });
    },
  };
}

test('host creates a room; guests join, exchange signals, and leave', async () => {
  const url = await start();
  const host = await connect(url);
  host.send({ type: 'create', requestId: 'create-1', version: 1, maxPlayers: 3 });
  const created = await host.next();
  assert.equal(created.type, 'created');
  assert.equal(created.requestId, 'create-1');
  assert.match(created.roomCode, /^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{10}$/);
  assert.equal(created.hostId, created.peerId);
  assert.equal(created.version, 1);
  assert.deepEqual(created.peers, []);

  const guest = await connect(url);
  guest.send({ type: 'join', requestId: 'join-1', version: 1, roomCode: created.roomCode.toLowerCase() });
  const joined = await guest.next();
  assert.equal(joined.type, 'joined');
  assert.equal(joined.hostId, created.peerId);
  assert.deepEqual(joined.peers, [{ peerId: created.peerId, role: 'host' }]);
  guest.send({ type: 'ready' });
  assert.deepEqual(await host.next(), { type: 'peer-joined', peerId: joined.peerId, role: 'guest' });

  host.send({ type: 'signal', to: joined.peerId, data: { type: 'offer', sdp: 'test-offer' } });
  assert.deepEqual(await guest.next(), { type: 'signal', from: created.peerId, data: { type: 'offer', sdp: 'test-offer' } });
  guest.send({ type: 'signal', to: created.peerId, data: { type: 'candidate', candidate: 'test-ice' } });
  assert.deepEqual(await host.next(), { type: 'signal', from: joined.peerId, data: { type: 'candidate', candidate: 'test-ice' } });

  guest.send({ type: 'leave', requestId: 'leave-1' });
  assert.deepEqual(await guest.next(), { type: 'left', requestId: 'leave-1' });
  assert.deepEqual(await host.next(), { type: 'peer-left', peerId: joined.peerId });
  host.ws.close();
  guest.ws.close();
});

test('room capacity, host-only lock, and host disconnect are enforced', async () => {
  const url = await start();
  const host = await connect(url);
  host.send({ type: 'create', version: 1, maxPlayers: 2 });
  const created = await host.next();
  const guest = await connect(url);
  guest.send({ type: 'join', version: 1, roomCode: created.roomCode });
  const joined = await guest.next();
  guest.send({ type: 'ready' });
  await host.next();

  const extra = await connect(url);
  extra.send({ type: 'join', version: 1, roomCode: created.roomCode });
  assert.equal((await extra.next()).code, 'room-full');

  guest.send({ type: 'lock' });
  assert.equal((await guest.next()).code, 'host-only');
  host.send({ type: 'lock', requestId: 'lock-1', expectedPeers: [joined.peerId] });
  assert.deepEqual(await host.next(), { type: 'locked', roomCode: created.roomCode, requestId: 'lock-1' });
  assert.deepEqual(await guest.next(), { type: 'locked', roomCode: created.roomCode });
  extra.send({ type: 'join', version: 1, roomCode: created.roomCode });
  assert.equal((await extra.next()).code, 'room-locked');

  host.ws.close();
  assert.deepEqual(await guest.next(), { type: 'room-closed', reason: 'host-left' });
  extra.send({ type: 'join', version: 1, roomCode: created.roomCode });
  assert.equal((await extra.next()).code, 'room-not-found');
  guest.ws.close();
  extra.ws.close();
  assert.notEqual(joined.peerId, created.peerId);
});

test('rejects cross-room signals, malformed input, invalid origins, and oversize frames', async () => {
  const url = await start();
  const hostA = await connect(url);
  const hostB = await connect(url);
  hostA.send({ type: 'create', version: 1 });
  hostB.send({ type: 'create', version: 1 });
  const a = await hostA.next();
  const b = await hostB.next();
  hostA.send({ type: 'signal', to: b.peerId, data: { type: 'offer' } });
  assert.equal((await hostA.next()).code, 'unknown-peer');
  hostA.ws.send('{');
  assert.equal((await hostA.next()).code, 'invalid-json');

  await assert.rejects(connect(url, 'https://evil.example'));
  const oversized = await connect(url);
  oversized.ws.send('x'.repeat(65 * 1024));
  assert.equal(await new Promise((resolve) => oversized.ws.once('close', resolve)), 1009);
  hostA.ws.close();
  hostB.ws.close();
});

test('health reports active rooms and peers', async () => {
  const url = await start();
  const host = await connect(url);
  host.send({ type: 'create', version: 1 });
  await host.next();
  const response = await fetch(url.replace('ws:', 'http:').replace('/ws', '/health'));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { ok: true, rooms: 1, peers: 1 });
  host.ws.close();
});

test('version mismatch and joined acknowledgement protect an offer race', async () => {
  const url = await start();
  const host = await connect(url);
  host.send({ type: 'create', version: 2, requestId: 'old-version' });
  assert.deepEqual(await host.next(), {
    type: 'error', requestId: 'old-version', code: 'version-mismatch',
    message: 'Protocol version 1 required.',
  });
  host.send({ type: 'create', version: 1 });
  const created = await host.next();
  const guest = await connect(url);
  guest.send({ type: 'join', version: 1, roomCode: created.roomCode });
  const joined = await guest.next();
  guest.send({ type: 'signal', to: created.peerId, data: { type: 'offer' } });
  assert.equal((await guest.next()).code, 'not-ready');
  host.send({ type: 'signal', to: joined.peerId, data: { type: 'offer' } });
  assert.equal((await host.next()).code, 'peer-not-ready');
  guest.send({ type: 'ready' });
  assert.equal((await host.next()).type, 'peer-joined');
  host.send({ type: 'signal', to: joined.peerId, data: { type: 'offer' } });
  assert.equal((await guest.next()).type, 'signal');
  guest.ws.close();
  host.ws.close();
});

test('room lock waits for joining guests and matches the host roster atomically', async () => {
  const url = await start();
  const host = await connect(url);
  host.send({ type: 'create', version: 1 });
  const created = await host.next();
  const guest = await connect(url);
  guest.send({ type: 'join', version: 1, roomCode: created.roomCode });
  const joined = await guest.next();

  host.send({ type: 'lock', requestId: 'early', expectedPeers: [] });
  assert.deepEqual(await host.next(), {
    type: 'error', requestId: 'early', code: 'join-in-progress',
    message: 'Wait for all players to finish joining.',
  });
  guest.send({ type: 'ready' });
  assert.equal((await host.next()).type, 'peer-joined');

  host.send({ type: 'lock', requestId: 'stale', expectedPeers: [] });
  assert.equal((await host.next()).code, 'roster-changed');
  host.send({ type: 'lock', requestId: 'exact', expectedPeers: [joined.peerId] });
  assert.deepEqual(await host.next(), { type: 'locked', roomCode: created.roomCode, requestId: 'exact' });
  assert.deepEqual(await guest.next(), { type: 'locked', roomCode: created.roomCode });
  host.ws.close();
  guest.ws.close();
});
