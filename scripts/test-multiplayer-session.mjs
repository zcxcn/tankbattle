import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import ts from 'typescript';

const tmp = await fs.mkdtemp(path.join(os.tmpdir(), 'tankbattle-multiplayer-'));
const source = await fs.readFile(new URL('../lib/multiplayer/session.ts', import.meta.url), 'utf8');
await fs.writeFile(path.join(tmp, 'session.mjs'), ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 },
}).outputText);

class FakeSocket {
  static OPEN = 1;
  static clients = new Map();
  static nextPeer = 1;
  static locked = false;
  static roomCode = 'ABCD23';
  static signalCount = 0;
  listeners = new Map();
  readyState = 0;
  id = '';
  constructor(url) {
    assert.equal(url, 'ws://127.0.0.1:8787');
    queueMicrotask(() => { this.readyState = 1; this.emit('open', {}); });
  }
  addEventListener(name, callback) {
    const listeners = this.listeners.get(name) ?? [];
    listeners.push(callback);
    this.listeners.set(name, listeners);
  }
  emit(name, event) { for (const listener of this.listeners.get(name) ?? []) listener(event); }
  receive(data) { queueMicrotask(() => this.emit('message', { data: JSON.stringify(data) })); }
  send(raw) {
    const message = JSON.parse(raw);
    if (message.type === 'create') {
      assert.equal(message.version, 1);
      this.id = `p${FakeSocket.nextPeer++}`;
      FakeSocket.clients.set(this.id, this);
      this.receive({ type: 'created', requestId: message.requestId, roomCode: FakeSocket.roomCode,
        peerId: this.id, hostId: this.id, peers: [], maxPlayers: message.maxPlayers });
    } else if (message.type === 'join') {
      assert.equal(message.version, 1);
      if (FakeSocket.locked) {
        this.receive({ type: 'error', requestId: message.requestId, code: 'room-locked', message: 'Room locked.' });
        return;
      }
      if (message.roomCode !== FakeSocket.roomCode) throw new Error('Wrong room code in test.');
      this.id = `p${FakeSocket.nextPeer++}`;
      const peers = [...FakeSocket.clients.keys()].map((peerId) => ({ peerId, role: peerId === 'p1' ? 'host' : 'guest' }));
      FakeSocket.clients.set(this.id, this);
      this.receive({ type: 'joined', requestId: message.requestId, roomCode: FakeSocket.roomCode,
        peerId: this.id, hostId: 'p1', peers });
    } else if (message.type === 'ready') {
      for (const client of FakeSocket.clients.values())
        if (client !== this) client.receive({ type: 'peer-joined', peerId: this.id, role: 'guest' });
    } else if (message.type === 'signal') {
      FakeSocket.signalCount++;
      FakeSocket.clients.get(message.to)?.receive({ type: 'signal', from: this.id, data: message.data });
    } else if (message.type === 'lock') {
      const actualPeers = [...FakeSocket.clients.keys()].filter((peerId) => peerId !== 'p1').sort((a, b) => a.localeCompare(b));
      if (!Array.isArray(message.expectedPeers) ||
          JSON.stringify([...message.expectedPeers].sort((a, b) => a.localeCompare(b))) !== JSON.stringify(actualPeers)) {
        this.receive({ type: 'error', requestId: message.requestId, code: 'roster-changed', message: 'Room roster changed.' });
        return;
      }
      FakeSocket.locked = true;
      for (const client of FakeSocket.clients.values())
        client.receive({ type: 'locked', roomCode: FakeSocket.roomCode,
          ...(client === this ? { requestId: message.requestId } : {}) });
    } else if (message.type === 'leave') {
      FakeSocket.clients.delete(this.id);
      if (this.id === 'p1')
        for (const client of FakeSocket.clients.values()) client.receive({ type: 'room-closed', reason: 'host-left' });
      else for (const client of FakeSocket.clients.values())
        client.receive({ type: 'peer-left', peerId: this.id });
    }
  }
  close() { if (this.readyState === 3) return; this.readyState = 3; this.emit('close', {}); }
}

class FakeChannel {
  readyState = 'connecting';
  bufferedAmount = 0;
  partner = null;
  onopen = null;
  onclose = null;
  onmessage = null;
  constructor(label, ordered = true, maxRetransmits = null) {
    this.label = label;
    this.ordered = ordered;
    this.maxRetransmits = maxRetransmits;
  }
  open() { this.readyState = 'open'; this.onopen?.(); }
  send(data) {
    assert.equal(this.readyState, 'open');
    queueMicrotask(() => this.partner?.onmessage?.({ data }));
  }
  close() { this.readyState = 'closed'; this.onclose?.(); }
}

class FakePeerConnection {
  static nextId = 1;
  static offers = new Map();
  static instances = [];
  connectionState = 'new';
  remoteDescription = null;
  localDescription = null;
  channels = [];
  onicecandidate = null;
  onconnectionstatechange = null;
  ondatachannel = null;
  partner = null;
  constructor(config) {
    assert.equal(config.iceTransportPolicy, 'all');
    this.config = config;
    FakePeerConnection.instances.push(this);
  }
  createDataChannel(label, options = {}) {
    const channel = new FakeChannel(label, options.ordered, options.maxRetransmits ?? null);
    this.channels.push(channel);
    return channel;
  }
  async createOffer() {
    const sdp = `offer-${FakePeerConnection.nextId++}`;
    FakePeerConnection.offers.set(sdp, this);
    return { type: 'offer', sdp };
  }
  async createAnswer() { return { type: 'answer', sdp: `answer-${this.remoteDescription.sdp}` }; }
  async setLocalDescription(description) {
    this.localDescription = description;
    this.onicecandidate?.({ candidate: { toJSON: () => ({ candidate: 'fake-candidate' }) } });
  }
  async setRemoteDescription(description) {
    this.remoteDescription = description;
    if (description.type === 'offer') {
      const host = FakePeerConnection.offers.get(description.sdp);
      assert(host);
      this.partner = host;
      host.partner = this;
      for (const hostChannel of host.channels) {
        const guestChannel = new FakeChannel(hostChannel.label, hostChannel.ordered, hostChannel.maxRetransmits);
        hostChannel.partner = guestChannel;
        guestChannel.partner = hostChannel;
        this.channels.push(guestChannel);
        this.ondatachannel?.({ channel: guestChannel });
      }
    } else if (description.type === 'answer') {
      for (const pc of [this, this.partner]) {
        pc.connectionState = 'connected';
        pc.onconnectionstatechange?.();
        for (const channel of pc.channels) channel.open();
      }
    }
  }
  async addIceCandidate() {}
  async getStats() {
    const pair = { id: 'pair', type: 'candidate-pair', nominated: true, state: 'succeeded',
      localCandidateId: 'local', remoteCandidateId: 'remote', currentRoundTripTime: 0.013 };
    return new Map([
      ['transport', { type: 'transport', selectedCandidatePairId: 'pair' }],
      ['pair', pair],
      ['local', { type: 'local-candidate', candidateType: 'host', address: '192.168.31.12' }],
      ['remote', { type: 'remote-candidate', candidateType: 'host', address: '192.168.31.13' }],
    ]);
  }
  close() { this.connectionState = 'closed'; this.onconnectionstatechange?.(); }
}

globalThis.WebSocket = FakeSocket;
globalThis.RTCPeerConnection = FakePeerConnection;
const { createRoom, joinRoom, routeFromStats } = await import(pathToFileURL(path.join(tmp, 'session.mjs')));
const tick = () => new Promise((resolve) => setTimeout(resolve, 0));

assert.equal(routeFromStats(await new FakePeerConnection({ iceTransportPolicy: 'all' }).getStats()).kind, 'lan');
const host = await createRoom({ url: 'ws://127.0.0.1:8787', maxPlayers: 3 });
assert.equal(host.roomCode, FakeSocket.roomCode);
assert.equal(host.role, 'host');
const ready = new Promise((resolve) => host.on('peer-ready', resolve));
const guest = await joinRoom({ url: 'ws://127.0.0.1:8787', roomCode: 'abcd23' });
await ready;
await tick();
assert.equal(host.peers.get(guest.peerId).status, 'connected');
assert.equal(guest.peers.get(host.peerId).status, 'connected');
assert.equal(host.peers.get(guest.peerId).route.kind, 'lan');
  assert.equal(host.peers.get(guest.peerId).route.rttMs, 13);
  const hostRtc = FakePeerConnection.instances.find((pc) => pc.channels.some((channel) => channel.label === 'reliable'));
  assert(hostRtc);
  let recovered = 0;
  const stopRecovery = host.on('peer-ready', () => recovered++);
  hostRtc.connectionState = 'disconnected';
  hostRtc.onconnectionstatechange?.();
  assert.equal(host.peers.get(guest.peerId).status, 'disconnected');
  hostRtc.connectionState = 'connected';
  hostRtc.onconnectionstatechange?.();
  assert.equal(host.peers.get(guest.peerId).status, 'connected', 'open channels recover readiness after ICE reconnect');
  assert.equal(recovered, 1, 'host can resend a full snapshot when the link recovers');
  stopRecovery();
assert(FakeSocket.signalCount >= 4, 'offer, answer, and ICE candidates passed via signaling');
const input = new Promise((resolve) => host.on('input', resolve));
assert(guest.sendInput({ x: 1, fire: true }));
assert.deepEqual((await input).input, { x: 1, fire: true });
const snapshot = new Promise((resolve) => guest.on('snapshot', resolve));
assert(host.sendSnapshot({ tanks: [{ x: 42 }] }));
assert.deepEqual((await snapshot).snapshot, { tanks: [{ x: 42 }] });
const control = new Promise((resolve) => guest.on('control', resolve));
assert(host.sendControl({ type: 'start', seed: 77 }));
assert.deepEqual((await control).control, { type: 'start', seed: 77 });
const secondGuestJoined = new Promise((resolve) => guest.on('peer-joined', resolve));
const secondGuestReady = new Promise((resolve) => host.on('peer-ready', resolve));
const secondGuest = await joinRoom({ url: 'ws://127.0.0.1:8787', roomCode: 'ABCD23' });
assert.equal((await secondGuestJoined).peerId, secondGuest.peerId);
await secondGuestReady;
assert(guest.peers.has(secondGuest.peerId), 'first guest sees later teammate in the room roster');
assert(secondGuest.peers.has(guest.peerId), 'later guest sees existing teammate in join reply');
assert.equal(guest.peers.get(secondGuest.peerId).route.kind, 'unknown', 'guests do not build an unnecessary mesh');
const secondGuestLeft = new Promise((resolve) => guest.on('peer-left', resolve));
secondGuest.close();
assert.equal((await secondGuestLeft).peerId, secondGuest.peerId);
assert(!guest.peers.has(secondGuest.peerId), 'departed teammate is removed from guest roster');
await assert.rejects(host.lockRoom([]), /roster changed/i, 'server refuses a stale start roster');
assert.equal(host.locked, false);
await host.lockRoom([guest.peerId]);
await tick();
assert(host.locked && guest.locked);
await assert.rejects(joinRoom({ url: 'ws://127.0.0.1:8787', roomCode: 'ABCD23' }), /Room locked/);
const closed = new Promise((resolve) => guest.on('closed', resolve));
host.close();
assert.match((await closed).reason, /Host left/);
assert.equal(guest.status, 'closed');
assert.equal(FakeSocket.clients.size, 0);

// Exhausting ICE restart attempts must not leave a phantom allied tank in the
// host simulation or a guest waiting forever for authoritative snapshots.
FakeSocket.locked = false;
FakeSocket.nextPeer = 1;
const timeoutHost = await createRoom({ url: 'ws://127.0.0.1:8787' });
const timeoutReady = new Promise((resolve) => timeoutHost.on('peer-ready', resolve));
const timeoutGuest = await joinRoom({ url: 'ws://127.0.0.1:8787', roomCode: 'ABCD23' });
await timeoutReady;
const lostPeer = new Promise((resolve) => timeoutHost.on('peer-left', resolve));
const hostRuntime = timeoutHost.runtimes.get(timeoutGuest.peerId);
hostRuntime.restartAttempts = 3;
hostRuntime.connection.connectionState = 'failed';
timeoutHost.scheduleRestart(timeoutGuest.peerId, 0);
assert.match((await lostPeer).reason, /timed out/);
assert(!timeoutHost.peers.has(timeoutGuest.peerId), 'host removes an unrecoverable guest tank');
const guestClosed = new Promise((resolve) => timeoutGuest.on('closed', resolve));
const guestRuntime = timeoutGuest.runtimes.get(timeoutHost.peerId);
guestRuntime.restartAttempts = 3;
guestRuntime.connection.connectionState = 'failed';
timeoutGuest.scheduleRestart(timeoutHost.peerId, 0);
assert.match((await guestClosed).reason, /timed out/);
assert.equal(timeoutGuest.status, 'closed');
timeoutHost.close();
console.log('PASS multiplayer room, four-player roster events, dual WebRTC channels, ICE recovery/timeout, atomic room lock, host departure');
