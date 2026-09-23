import { randomBytes } from 'node:crypto';
import { createServer } from 'node:http';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { WebSocket, WebSocketServer } from 'ws';

const ROOM_ALPHABET = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
const ROOM_LENGTH = 10;
const PROTOCOL_VERSION = 1;
const MAX_MESSAGE_BYTES = 64 * 1024;
const DEFAULT_ORIGINS = [
  'https://zcxcn.github.io',
  'http://127.0.0.1:5173',
  'http://localhost:5173',
];

function randomRoomCode() {
  const bytes = randomBytes(ROOM_LENGTH);
  return [...bytes].map((byte) => ROOM_ALPHABET[byte % ROOM_ALPHABET.length]).join('');
}

function randomPeerId() {
  return randomBytes(12).toString('base64url');
}

function safeRequestId(value) {
  return typeof value === 'string' && value.length > 0 && value.length <= 64
    ? value
    : undefined;
}

function send(ws, message) {
  if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(message));
}

function roomSummary(room, session, requestId, type) {
  return {
    type,
    ...(requestId ? { requestId } : {}),
    roomCode: room.code,
    version: PROTOCOL_VERSION,
    peerId: session.peerId,
    hostId: room.hostId,
    maxPlayers: room.maxPlayers,
    locked: room.locked,
    peers: [...room.peers.values()]
      .filter((peer) => peer !== session)
      .map((peer) => ({ peerId: peer.peerId, role: peer.peerId === room.hostId ? 'host' : 'guest' })),
  };
}

/**
 * Starts a room directory and WebRTC signaling relay. Game traffic never passes
 * through this server. The returned close() method is for tests and shutdown.
 */
export async function createSignalingServer({
  host = process.env.SIGNAL_HOST || '127.0.0.1',
  port = Number(process.env.SIGNAL_PORT || 8787),
  allowedOrigins = (process.env.SIGNAL_ALLOWED_ORIGINS || DEFAULT_ORIGINS.join(','))
    .split(',').map((origin) => origin.trim()).filter(Boolean),
  heartbeatMs = 30_000,
  maxRooms = 1024,
  maxClients = 4096,
} = {}) {
  const rooms = new Map();
  const clients = new Set();
  const recentCreates = new Map();
  const originSet = new Set(allowedOrigins);
  const server = createServer((request, response) => {
    if (request.method === 'GET' && request.url === '/health') {
      response.writeHead(200, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
      response.end(JSON.stringify({ ok: true, rooms: rooms.size, peers: clients.size }));
      return;
    }
    response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
    response.end('Not found');
  });
  const wss = new WebSocketServer({ noServer: true, maxPayload: MAX_MESSAGE_BYTES, perMessageDeflate: false });

  function error(ws, code, message, requestId) {
    send(ws, { type: 'error', ...(requestId ? { requestId } : {}), code, message });
  }

  function leave(session) {
    const { room } = session;
    if (!room) return;
    session.room = undefined;
    room.peers.delete(session.peerId);
    if (session.peerId === room.hostId) {
      rooms.delete(room.code);
      for (const peer of room.peers.values()) {
        peer.room = undefined;
        send(peer.ws, { type: 'room-closed', reason: 'host-left' });
      }
      room.peers.clear();
    } else if (session.ready) {
      for (const peer of room.peers.values()) {
        if (peer.ready) send(peer.ws, { type: 'peer-left', peerId: session.peerId });
      }
    }
  }

  function handleMessage(session, raw) {
    const now = Date.now();
    if (now - session.windowStart >= 10_000) {
      session.windowStart = now;
      session.messageCount = 0;
    }
    if (++session.messageCount > 120) {
      session.ws.close(1008, 'Rate limit');
      return;
    }

    let message;
    try {
      message = JSON.parse(raw.toString());
    } catch {
      error(session.ws, 'invalid-json', 'Message must be valid JSON.');
      return;
    }
    if (!message || typeof message !== 'object' || Array.isArray(message)) {
      error(session.ws, 'invalid-message', 'Message must be an object.');
      return;
    }
    const requestId = safeRequestId(message.requestId);

    if (message.type === 'create') {
      if (message.version !== PROTOCOL_VERSION) {
        error(session.ws, 'version-mismatch', `Protocol version ${PROTOCOL_VERSION} required.`, requestId);
        return;
      }
      if (session.room) {
        error(session.ws, 'already-in-room', 'Leave the current room first.', requestId);
        return;
      }
      if (rooms.size >= maxRooms) {
        error(session.ws, 'server-full', 'Room capacity reached.', requestId);
        return;
      }
      const maxPlayers = message.maxPlayers ?? 4;
      if (!Number.isInteger(maxPlayers) || maxPlayers < 2 || maxPlayers > 4) {
        error(session.ws, 'invalid-capacity', 'maxPlayers must be 2–4.', requestId);
        return;
      }
      const prior = (recentCreates.get(session.ip) || []).filter((time) => now - time < 60_000);
      if (prior.length >= 6) {
        recentCreates.set(session.ip, prior);
        error(session.ws, 'create-rate-limit', 'Too many rooms created from this address.', requestId);
        return;
      }
      prior.push(now);
      recentCreates.set(session.ip, prior);
      let code;
      do { code = randomRoomCode(); } while (rooms.has(code));
      const room = { code, hostId: session.peerId, maxPlayers, locked: false, peers: new Map([[session.peerId, session]]) };
      rooms.set(code, room);
      session.room = room;
      session.ready = true;
      send(session.ws, roomSummary(room, session, requestId, 'created'));
      return;
    }

    if (message.type === 'join') {
      if (message.version !== PROTOCOL_VERSION) {
        error(session.ws, 'version-mismatch', `Protocol version ${PROTOCOL_VERSION} required.`, requestId);
        return;
      }
      if (session.room) {
        error(session.ws, 'already-in-room', 'Leave the current room first.', requestId);
        return;
      }
      const code = typeof message.roomCode === 'string' ? message.roomCode.trim().toUpperCase() : '';
      if (code.length !== ROOM_LENGTH || [...code].some((char) => !ROOM_ALPHABET.includes(char))) {
        error(session.ws, 'invalid-room-code', 'Enter a valid 10-character room code.', requestId);
        return;
      }
      const room = rooms.get(code);
      if (!room) {
        error(session.ws, 'room-not-found', 'The room is offline or expired.', requestId);
        return;
      }
      if (room.locked) {
        error(session.ws, 'room-locked', 'This match has already started.', requestId);
        return;
      }
      if (room.peers.size >= room.maxPlayers) {
        error(session.ws, 'room-full', 'The room is full.', requestId);
        return;
      }
      session.room = room;
      session.ready = false;
      send(session.ws, roomSummary(room, session, requestId, 'joined'));
      room.peers.set(session.peerId, session);
      return;
    }

    // Acknowledges receipt of joined. Without this step, a host offer can race
    // the joined response across two independent WebSocket connections.
    if (message.type === 'ready') {
      const room = session.room;
      if (!room) {
        error(session.ws, 'not-in-room', 'Join a room first.', requestId);
        return;
      }
      if (!session.ready) {
        session.ready = true;
        for (const peer of room.peers.values()) {
          if (peer !== session && peer.ready) {
            send(peer.ws, { type: 'peer-joined', peerId: session.peerId, role: 'guest' });
          }
        }
      }
      return;
    }

    if (message.type === 'signal') {
      const room = session.room;
      if (!room) {
        error(session.ws, 'not-in-room', 'Join a room before signaling.', requestId);
        return;
      }
      if (!session.ready) {
        error(session.ws, 'not-ready', 'Acknowledge joined before signaling.', requestId);
        return;
      }
      if (typeof message.to !== 'string' || !room.peers.has(message.to) || message.to === session.peerId) {
        error(session.ws, 'unknown-peer', 'Signal target is not in this room.', requestId);
        return;
      }
      if (!message.data || typeof message.data !== 'object' || Array.isArray(message.data)) {
        error(session.ws, 'invalid-signal', 'Signal data must be an object.', requestId);
        return;
      }
      const target = room.peers.get(message.to);
      if (!target.ready) {
        error(session.ws, 'peer-not-ready', 'Signal target is still joining.', requestId);
        return;
      }
      send(target.ws, { type: 'signal', from: session.peerId, data: message.data });
      return;
    }

    if (message.type === 'lock') {
      const room = session.room;
      if (!room || room.hostId !== session.peerId) {
        error(session.ws, 'host-only', 'Only the host can lock the room.', requestId);
        return;
      }
      if ([...room.peers.values()].some((peer) => !peer.ready)) {
        error(session.ws, 'join-in-progress', 'Wait for all players to finish joining.', requestId);
        return;
      }
      const expectedPeers = message.expectedPeers;
      if (!Array.isArray(expectedPeers) || expectedPeers.length > 3 ||
          expectedPeers.some((peerId) => typeof peerId !== 'string' || !peerId) ||
          new Set(expectedPeers).size !== expectedPeers.length) {
        error(session.ws, 'invalid-roster', 'expectedPeers must list each guest once.', requestId);
        return;
      }
      const actualPeers = [...room.peers.keys()].filter((peerId) => peerId !== room.hostId);
      if (expectedPeers.length !== actualPeers.length ||
          expectedPeers.some((peerId) => !room.peers.has(peerId))) {
        error(session.ws, 'roster-changed', 'Player list changed; retry with the current room.', requestId);
        return;
      }
      room.locked = true;
      for (const peer of room.peers.values()) {
        send(peer.ws, {
          type: 'locked', roomCode: room.code,
          ...(peer === session && requestId ? { requestId } : {}),
        });
      }
      return;
    }

    if (message.type === 'leave') {
      leave(session);
      send(session.ws, { type: 'left', ...(requestId ? { requestId } : {}) });
      return;
    }

    error(session.ws, 'unsupported-type', 'Unsupported message type.', requestId);
  }

  server.on('upgrade', (request, socket, head) => {
    let path;
    try {
      path = new URL(request.url || '/', 'http://localhost').pathname;
    } catch {
      socket.write('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n');
      socket.destroy();
      return;
    }
    const origin = request.headers.origin;
    if ((path !== '/' && path !== '/ws') || (origin && !originSet.has(origin))) {
      socket.write('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n');
      socket.destroy();
      return;
    }
    if (clients.size >= maxClients) {
      socket.write('HTTP/1.1 503 Service Unavailable\r\nConnection: close\r\n\r\n');
      socket.destroy();
      return;
    }
    wss.handleUpgrade(request, socket, head, (ws) => {
      const session = {
        ws,
        ip: request.socket.remoteAddress || 'unknown',
        peerId: randomPeerId(),
        room: undefined,
        ready: false,
        alive: true,
        windowStart: Date.now(),
        messageCount: 0,
      };
      clients.add(session);
      ws.on('pong', () => { session.alive = true; });
      ws.on('message', (raw) => handleMessage(session, raw));
      ws.on('close', () => {
        leave(session);
        clients.delete(session);
      });
      ws.on('error', () => { /* close event performs cleanup */ });
    });
  });

  const heartbeat = setInterval(() => {
    for (const session of clients) {
      if (!session.alive) {
        session.ws.terminate();
        continue;
      }
      session.alive = false;
      session.ws.ping();
    }
    const now = Date.now();
    for (const [ip, times] of recentCreates) {
      const fresh = times.filter((time) => now - time < 60_000);
      if (fresh.length) recentCreates.set(ip, fresh);
      else recentCreates.delete(ip);
    }
  }, heartbeatMs);
  heartbeat.unref();

  try {
    await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(port, host, resolve);
    });
  } catch (cause) {
    clearInterval(heartbeat);
    throw cause;
  }

  return {
    address: server.address(),
    get roomCount() { return rooms.size; },
    get peerCount() { return clients.size; },
    async close() {
      clearInterval(heartbeat);
      for (const session of clients) session.ws.terminate();
      await new Promise((resolve) => wss.close(resolve));
      await new Promise((resolve, reject) => server.close((cause) => cause ? reject(cause) : resolve()));
    },
  };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  createSignalingServer().then(({ address }) => {
    console.log(`Signaling listening on ${address.address}:${address.port}`);
  }).catch((cause) => {
    console.error(cause);
    process.exitCode = 1;
  });
}
