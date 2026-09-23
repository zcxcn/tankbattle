/** Browser-to-browser transport. The WebSocket carries room discovery and ICE only. */
export type MultiplayerRole = 'host' | 'guest';
export type SessionStatus = 'connecting' | 'waiting' | 'connected' | 'closed';
export type PeerStatus = 'connecting' | 'connected' | 'disconnected' | 'failed' | 'closed';
export type RouteKind = 'lan' | 'direct' | 'relay' | 'unknown';

export interface IceRoute {
  kind: RouteKind;
  rttMs: number | null;
  localCandidateType?: string;
  remoteCandidateType?: string;
}

export interface PeerConnectionInfo {
  peerId: string;
  role: MultiplayerRole;
  status: PeerStatus;
  route: IceRoute;
}

export interface RoomOptions {
  url: string;
  maxPlayers?: number;
  iceServers?: RTCIceServer[];
  iceTransportPolicy?: RTCIceTransportPolicy;
  timeoutMs?: number;
}

export interface JoinRoomOptions extends RoomOptions {
  roomCode: string;
}

interface SessionEvents {
  status: { status: SessionStatus; peerId?: string };
  locked: { roomCode: string };
  'peer-joined': { peerId: string; role: MultiplayerRole };
  'peer-ready': { peerId: string; route: IceRoute };
  'peer-left': { peerId: string; reason?: string };
  input: { peerId: string; input: unknown; sequence: number };
  snapshot: { peerId: string; snapshot: unknown; sequence: number };
  control: { peerId: string; control: unknown; sequence: number };
  error: Error;
  closed: { reason: string };
}

type Listener<K extends keyof SessionEvents> = (event: SessionEvents[K]) => void;
type SignalData =
  | { kind: 'description'; description: RTCSessionDescriptionInit }
  | { kind: 'candidate'; candidate: RTCIceCandidateInit }
  | { kind: 'restart-request' };
type ChannelKind = 'reliable' | 'realtime';
type PayloadKind = 'input' | 'snapshot' | 'control';

interface WirePayload {
  kind: PayloadKind;
  sequence: number;
  value: unknown;
}

interface PeerRuntime {
  connection: RTCPeerConnection;
  info: PeerConnectionInfo;
  reliable: RTCDataChannel | null;
  realtime: RTCDataChannel | null;
  pendingCandidates: RTCIceCandidateInit[];
  lastSequence: Partial<Record<PayloadKind, number>>;
  restartTimer: ReturnType<typeof setTimeout> | null;
  restartAttempts: number;
}

type ServerMessage = Record<string, unknown> & { type: string };
let requestCounter = 0;
const MAX_REALTIME_BUFFER = 64 * 1024;
const MAX_RELIABLE_BUFFER = 1024 * 1024;
export const MULTIPLAYER_PROTOCOL_VERSION = 1;
const DEFAULT_ICE_SERVERS: RTCIceServer[] = [
  { urls: 'stun:stun.l.google.com:19302' },
];

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function requestId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function')
    return crypto.randomUUID();
  return `${Date.now().toString(36)}-${++requestCounter}`;
}

function asError(value: unknown): Error {
  return value instanceof Error ? value : new Error(String(value));
}

function validateUrl(url: string): void {
  const parsed = new URL(url);
  if (parsed.protocol !== 'ws:' && parsed.protocol !== 'wss:')
    throw new Error('Signaling URL must use ws:// or wss://.');
  if (
    typeof window !== 'undefined' &&
    window.location.protocol === 'https:' &&
    parsed.protocol !== 'wss:'
  )
    throw new Error('An HTTPS game page requires a secure wss:// signaling URL.');
}

function candidateIsPrivate(address: unknown): boolean {
  if (typeof address !== 'string') return false;
  const normalized = address.toLowerCase();
  if (normalized.endsWith('.local') || normalized === '::1') return true;
  if (/^(10\.|192\.168\.|127\.|169\.254\.)/.test(normalized)) return true;
  const match = /^172\.(\d+)\./.exec(normalized);
  if (match && Number(match[1]) >= 16 && Number(match[1]) <= 31) return true;
  return /^(fc|fd|fe8|fe9|fea|feb)[0-9a-f]*:/.test(normalized);
}

/** Path classification is based on the selected ICE candidate pair, not Wi-Fi identity. */
export function routeFromStats(report: RTCStatsReport): IceRoute {
  let selected: Record<string, unknown> | undefined;
  for (const raw of report.values()) {
    const stat = raw as unknown as Record<string, unknown>;
    if (stat.type === 'transport' && typeof stat.selectedCandidatePairId === 'string') {
      const pair = report.get(stat.selectedCandidatePairId);
      if (pair) selected = pair as unknown as Record<string, unknown>;
      break;
    }
  }
  if (!selected) {
    for (const raw of report.values()) {
      const stat = raw as unknown as Record<string, unknown>;
      if (stat.type === 'candidate-pair' && (stat.selected === true || (stat.nominated === true && stat.state === 'succeeded'))) {
        selected = stat;
        break;
      }
    }
  }
  if (!selected) return { kind: 'unknown', rttMs: null };
  const local = typeof selected.localCandidateId === 'string'
    ? report.get(selected.localCandidateId) as unknown as Record<string, unknown> | undefined
    : undefined;
  const remote = typeof selected.remoteCandidateId === 'string'
    ? report.get(selected.remoteCandidateId) as unknown as Record<string, unknown> | undefined
    : undefined;
  const localType = typeof local?.candidateType === 'string' ? local.candidateType : undefined;
  const remoteType = typeof remote?.candidateType === 'string' ? remote.candidateType : undefined;
  let kind: RouteKind = 'unknown';
  if (localType === 'relay' || remoteType === 'relay') kind = 'relay';
  else if (localType && remoteType) {
    kind = localType === 'host' && remoteType === 'host' &&
      candidateIsPrivate(local?.address ?? local?.ip) &&
      candidateIsPrivate(remote?.address ?? remote?.ip)
      ? 'lan' : 'direct';
  }
  const seconds = selected.currentRoundTripTime;
  return {
    kind,
    rttMs: typeof seconds === 'number' && Number.isFinite(seconds)
      ? Math.round(seconds * 1000) : null,
    localCandidateType: localType,
    remoteCandidateType: remoteType,
  };
}

export class MultiplayerSession {
  readonly peers = new Map<string, PeerConnectionInfo>();
  readonly role: MultiplayerRole;
  readonly iceServers: RTCIceServer[];
  readonly iceTransportPolicy: RTCIceTransportPolicy;
  peerId = '';
  hostId = '';
  roomCode = '';
  locked = false;
  status: SessionStatus = 'connecting';
  private readonly socket: WebSocket;
  private readonly runtimes = new Map<string, PeerRuntime>();
  private readonly listeners = new Map<keyof SessionEvents, Set<(payload: never) => void>>();
  private readonly sequence: Record<PayloadKind, number> = { input: 0, snapshot: 0, control: 0 };
  private readyResolve: ((session: MultiplayerSession) => void) | null = null;
  private readyReject: ((error: Error) => void) | null = null;
  private request = '';
  private openTimer: ReturnType<typeof setTimeout> | null = null;
  private statsTimer: ReturnType<typeof setInterval> | null = null;
  private lockPending: {
    requestId: string;
    resolve: () => void;
    reject: (error: Error) => void;
    timer: ReturnType<typeof setTimeout>;
  } | null = null;
  private closed = false;

  private constructor(socket: WebSocket, role: MultiplayerRole, iceServers: RTCIceServer[], iceTransportPolicy: RTCIceTransportPolicy) {
    this.socket = socket;
    this.role = role;
    this.iceServers = iceServers;
    this.iceTransportPolicy = iceTransportPolicy;
    socket.addEventListener('message', (event) => this.onSignalingMessage(event));
    socket.addEventListener('error', () => this.failSignaling(new Error('Signaling connection failed.')));
    socket.addEventListener('close', () => this.failSignaling(new Error('Signaling connection closed.')));
  }

  static connect(options: RoomOptions, role: MultiplayerRole, roomCode?: string): Promise<MultiplayerSession> {
    validateUrl(options.url);
    if (role === 'guest' && !roomCode?.trim())
      return Promise.reject(new Error('Enter a room code.'));
    if (typeof WebSocket === 'undefined' || typeof RTCPeerConnection === 'undefined')
      return Promise.reject(new Error('This browser does not support WebRTC multiplayer.'));
    const socket = new WebSocket(options.url);
    const session = new MultiplayerSession(socket, role, options.iceServers ?? DEFAULT_ICE_SERVERS, options.iceTransportPolicy ?? 'all');
    session.request = requestId();
    return new Promise<MultiplayerSession>((resolve, reject) => {
      session.readyResolve = resolve;
      session.readyReject = reject;
      session.openTimer = setTimeout(() => {
        session.failSignaling(new Error('Timed out connecting to the room service.'));
      }, options.timeoutMs ?? 12000);
      socket.addEventListener('open', () => {
        if (session.closed) return;
        socket.send(JSON.stringify(role === 'host'
          ? { type: 'create', requestId: session.request, version: MULTIPLAYER_PROTOCOL_VERSION,
              maxPlayers: Math.min(4, Math.max(2, options.maxPlayers ?? 4)) }
          : { type: 'join', requestId: session.request, version: MULTIPLAYER_PROTOCOL_VERSION,
              roomCode: roomCode!.trim().toUpperCase() }));
      });
    });
  }

  on<K extends keyof SessionEvents>(event: K, listener: Listener<K>): () => void {
    let set = this.listeners.get(event);
    if (!set) {
      set = new Set();
      this.listeners.set(event, set);
    }
    set.add(listener as (payload: never) => void);
    return () => set?.delete(listener as (payload: never) => void);
  }

  private emit<K extends keyof SessionEvents>(event: K, payload: SessionEvents[K]): void {
    for (const listener of this.listeners.get(event) ?? [])
      (listener as Listener<K>)(payload);
  }

  private setStatus(status: SessionStatus, peerId?: string): void {
    if (this.status === status && !peerId) return;
    this.status = status;
    this.emit('status', { status, peerId });
  }

  private onSignalingMessage(event: MessageEvent): void {
    let message: ServerMessage;
    try {
      const parsed: unknown = JSON.parse(String(event.data));
      if (!isRecord(parsed) || typeof parsed.type !== 'string') return;
      message = parsed as ServerMessage;
    } catch {
      this.emit('error', new Error('Invalid message from room service.'));
      return;
    }
    if (message.type === 'created' || message.type === 'joined') {
      if (message.requestId !== this.request || this.peerId) return;
      if (typeof message.peerId !== 'string' || typeof message.roomCode !== 'string' || typeof message.hostId !== 'string') {
        this.failSignaling(new Error('Room service returned an incomplete reply.'));
        return;
      }
      this.peerId = message.peerId;
      this.roomCode = message.roomCode;
      this.hostId = message.hostId;
      for (const entry of Array.isArray(message.peers) ? message.peers : []) {
        if (!isRecord(entry) || typeof entry.peerId !== 'string' || entry.peerId === this.peerId) continue;
        const role: MultiplayerRole = entry.role === 'host' ? 'host' : 'guest';
        this.addPeer(entry.peerId, role);
      }
      // Across two sockets, sending the join ACK before the host notification does
      // not guarantee the guest receives it first. The server waits for this ACK.
      if (message.type === 'joined' && this.socket.readyState === WebSocket.OPEN)
        this.socket.send(JSON.stringify({ type: 'ready' }));
      if (this.openTimer) clearTimeout(this.openTimer);
      this.openTimer = null;
      this.setStatus('waiting');
      this.statsTimer = setInterval(() => { void this.refreshRoutes(); }, 2000);
      this.readyResolve?.(this);
      this.readyResolve = null;
      this.readyReject = null;
      return;
    }
    if (message.type === 'error') {
      const error = new Error(typeof message.message === 'string' ? message.message : 'Room service error.');
      if (message.requestId === this.request && this.readyReject) this.failSignaling(error);
      else if (this.lockPending && message.requestId === this.lockPending.requestId) {
        const pending = this.lockPending;
        this.lockPending = null;
        clearTimeout(pending.timer);
        pending.reject(error);
      }
      else this.emit('error', error);
      return;
    }
    if (!this.peerId || this.closed) return;
    if (message.type === 'peer-joined' && typeof message.peerId === 'string') {
      const peerId = message.peerId;
      if (this.peers.has(peerId)) return;
      this.addPeer(peerId, 'guest');
      this.emit('peer-joined', { peerId, role: 'guest' });
      // All room members are visible in the lobby. Only the host connects to
      // each guest; guests do not create a full mesh of game data channels.
      if (this.role === 'host') void this.offerTo(peerId);
    } else if (message.type === 'peer-left' && typeof message.peerId === 'string') {
      this.removePeer(message.peerId, 'left room');
    } else if (message.type === 'room-closed') {
      this.close('Host left the room.');
    } else if (message.type === 'locked') {
      this.locked = true;
      if (this.lockPending && message.requestId === this.lockPending.requestId) {
        const pending = this.lockPending;
        this.lockPending = null;
        clearTimeout(pending.timer);
        pending.resolve();
      }
      this.emit('locked', { roomCode: this.roomCode });
    } else if (message.type === 'signal' && typeof message.from === 'string' && isRecord(message.data)) {
      void this.onPeerSignal(message.from, message.data);
    }
  }

  private addPeer(peerId: string, role: MultiplayerRole): void {
    if (this.peers.has(peerId)) return;
    this.peers.set(peerId, { peerId, role, status: 'connecting', route: { kind: 'unknown', rttMs: null } });
  }

  private runtime(peerId: string, role: MultiplayerRole): PeerRuntime {
    const existing = this.runtimes.get(peerId);
    if (existing) return existing;
    this.addPeer(peerId, role);
    const connection = new RTCPeerConnection({ iceServers: this.iceServers, iceTransportPolicy: this.iceTransportPolicy });
    const runtime: PeerRuntime = {
      connection,
      info: this.peers.get(peerId)!,
      reliable: null,
      realtime: null,
      pendingCandidates: [],
      lastSequence: {},
      restartTimer: null,
      restartAttempts: 0,
    };
    this.runtimes.set(peerId, runtime);
    connection.onicecandidate = (event) => {
      if (event.candidate)
        this.sendSignal(peerId, { kind: 'candidate', candidate: event.candidate.toJSON() });
    };
    connection.onconnectionstatechange = () => {
      if (this.closed || !this.runtimes.has(peerId)) return;
      if (connection.connectionState === 'connected') {
        runtime.restartAttempts = 0;
        if (runtime.restartTimer) clearTimeout(runtime.restartTimer);
        runtime.restartTimer = null;
        // An ICE restart can recover with already-open data channels. The
        // channels will not emit another open event, so restore peer readiness.
        this.checkReady(peerId);
        void this.refreshRoute(peerId);
      } else if (connection.connectionState === 'disconnected') {
        runtime.info.status = 'disconnected';
        this.emit('status', { status: this.status, peerId });
        this.scheduleRestart(peerId, 4000);
      } else if (connection.connectionState === 'failed') {
        runtime.info.status = 'failed';
        this.emit('status', { status: this.status, peerId });
        this.scheduleRestart(peerId, 0);
      } else if (connection.connectionState === 'closed') {
        runtime.info.status = 'closed';
      }
    };
    connection.ondatachannel = (event) => {
      if (event.channel.label === 'reliable' || event.channel.label === 'realtime')
        this.attachChannel(peerId, event.channel.label, event.channel);
      else event.channel.close();
    };
    return runtime;
  }

  private attachChannel(peerId: string, kind: ChannelKind, channel: RTCDataChannel): void {
    const runtime = this.runtimes.get(peerId);
    if (!runtime) return;
    if (kind === 'reliable') runtime.reliable = channel;
    else runtime.realtime = channel;
    channel.onopen = () => this.checkReady(peerId);
    channel.onclose = () => {
      if (this.closed || !this.runtimes.has(peerId)) return;
      runtime.info.status = 'disconnected';
      this.emit('status', { status: this.status, peerId });
    };
    channel.onmessage = (event) => this.onData(peerId, event);
    if (channel.readyState === 'open') this.checkReady(peerId);
  }

  private checkReady(peerId: string): void {
    const runtime = this.runtimes.get(peerId);
    if (!runtime || runtime.info.status === 'connected') return;
    if (runtime.reliable?.readyState !== 'open' || runtime.realtime?.readyState !== 'open') return;
    runtime.info.status = 'connected';
    this.setStatus('connected', peerId);
    void this.refreshRoute(peerId);
    this.emit('peer-ready', { peerId, route: runtime.info.route });
  }

  private onData(peerId: string, event: MessageEvent): void {
    let data: unknown;
    try { data = JSON.parse(String(event.data)); }
    catch { return; }
    if (!isRecord(data) || !['input', 'snapshot', 'control'].includes(String(data.kind)) ||
      !Number.isSafeInteger(data.sequence) || Number(data.sequence) <= 0) return;
    const kind = data.kind as PayloadKind;
    if ((kind === 'input' && this.role !== 'host') || (kind === 'snapshot' && this.role !== 'guest')) return;
    const runtime = this.runtimes.get(peerId);
    if (!runtime) return;
    const sequence = data.sequence as number;
    if (sequence <= (runtime.lastSequence[kind] ?? 0)) return;
    runtime.lastSequence[kind] = sequence;
    if (kind === 'input') this.emit('input', { peerId, input: data.value, sequence });
    else if (kind === 'snapshot') this.emit('snapshot', { peerId, snapshot: data.value, sequence });
    else this.emit('control', { peerId, control: data.value, sequence });
  }

  private async offerTo(peerId: string, restart = false): Promise<void> {
    try {
      const runtime = this.runtime(peerId, 'guest');
      if (!runtime.reliable) this.attachChannel(peerId, 'reliable', runtime.connection.createDataChannel('reliable'));
      if (!runtime.realtime) this.attachChannel(peerId, 'realtime', runtime.connection.createDataChannel('realtime', { ordered: false, maxRetransmits: 0 }));
      const offer = await runtime.connection.createOffer(restart ? { iceRestart: true } : undefined);
      await runtime.connection.setLocalDescription(offer);
      this.sendSignal(peerId, { kind: 'description', description: offer });
    } catch (error) { this.emit('error', asError(error)); }
  }

  private async onPeerSignal(peerId: string, value: Record<string, unknown>): Promise<void> {
    if (this.role === 'guest' && peerId !== this.hostId) return;
    if (this.role === 'host' && !this.peers.has(peerId)) return;
    try {
      if (value.kind === 'description' && isRecord(value.description) &&
        (value.description.type === 'offer' || value.description.type === 'answer') &&
        typeof value.description.sdp === 'string') {
        const description: RTCSessionDescriptionInit = {
          type: value.description.type,
          sdp: value.description.sdp,
        };
        if (description.type === 'offer' && this.role === 'guest') {
          const runtime = this.runtime(peerId, 'host');
          await runtime.connection.setRemoteDescription(description);
          await this.flushCandidates(runtime);
          const answer = await runtime.connection.createAnswer();
          await runtime.connection.setLocalDescription(answer);
          this.sendSignal(peerId, { kind: 'description', description: answer });
        } else if (description.type === 'answer' && this.role === 'host') {
          const runtime = this.runtimes.get(peerId);
          if (!runtime) return;
          await runtime.connection.setRemoteDescription(description);
          await this.flushCandidates(runtime);
        }
      } else if (value.kind === 'candidate' && isRecord(value.candidate)) {
        const runtime = this.runtime(peerId, this.role === 'host' ? 'guest' : 'host');
        const candidate = value.candidate as RTCIceCandidateInit;
        if (runtime.connection.remoteDescription) await runtime.connection.addIceCandidate(candidate);
        else runtime.pendingCandidates.push(candidate);
      } else if (value.kind === 'restart-request' && this.role === 'host') {
        await this.offerTo(peerId, true);
      }
    } catch (error) { this.emit('error', asError(error)); }
  }

  private async flushCandidates(runtime: PeerRuntime): Promise<void> {
    for (const candidate of runtime.pendingCandidates.splice(0))
      await runtime.connection.addIceCandidate(candidate);
  }

  private scheduleRestart(peerId: string, delay: number): void {
    const runtime = this.runtimes.get(peerId);
    if (!runtime || runtime.restartTimer) return;
    runtime.restartTimer = setTimeout(() => {
      runtime.restartTimer = null;
      if (this.closed || !this.runtimes.has(peerId) || runtime.connection.connectionState === 'connected') return;
      if (++runtime.restartAttempts > 3) {
        this.emit('error', new Error(`Connection to ${peerId} could not be restored.`));
        // The host must stop simulating a permanently absent tank. A guest
        // cannot keep playing without authoritative snapshots from the host.
        if (this.role === 'host') this.removePeer(peerId, 'connection timed out');
        else this.close('Connection to host timed out.');
        return;
      }
      if (this.role === 'host') void this.offerTo(peerId, true);
      else this.sendSignal(peerId, { kind: 'restart-request' });
      this.scheduleRestart(peerId, 5000);
    }, delay);
  }

  private sendSignal(to: string, data: SignalData): void {
    if (this.socket.readyState === WebSocket.OPEN && !this.closed)
      this.socket.send(JSON.stringify({ type: 'signal', to, data }));
  }

  private send(kind: PayloadKind, value: unknown, toPeerId?: string): boolean {
    if (this.closed || (kind === 'input' && this.role !== 'guest') ||
      (kind === 'snapshot' && this.role !== 'host')) return false;
    const channelKind: ChannelKind = kind === 'control' ? 'reliable' : 'realtime';
    const data: WirePayload = { kind, sequence: ++this.sequence[kind], value };
    let serialized: string;
    try { serialized = JSON.stringify(data); }
    catch { return false; }
    let sent = false;
    for (const [peerId, runtime] of this.runtimes) {
      if (toPeerId && peerId !== toPeerId) continue;
      const channel = runtime[channelKind];
      if (channel?.readyState !== 'open') continue;
      if (channel.bufferedAmount > (channelKind === 'realtime' ? MAX_REALTIME_BUFFER : MAX_RELIABLE_BUFFER)) continue;
      try { channel.send(serialized); sent = true; }
      catch (error) { this.emit('error', asError(error)); }
    }
    return sent;
  }

  sendInput(input: unknown): boolean { return this.send('input', input, this.hostId); }
  sendSnapshot(snapshot: unknown, toPeerId?: string): boolean { return this.send('snapshot', snapshot, toPeerId); }
  sendControl(control: unknown, toPeerId?: string): boolean { return this.send('control', control, toPeerId); }

  lockRoom(expectedPeers: string[]): Promise<void> {
    if (this.role !== 'host' || this.closed || this.socket.readyState !== WebSocket.OPEN)
      return Promise.reject(new Error('Room is not connected.'));
    if (this.locked) return Promise.resolve();
    if (this.lockPending) return Promise.reject(new Error('Room is already locking.'));
    const id = requestId();
    return new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => {
        if (this.lockPending?.requestId !== id) return;
        this.lockPending = null;
        reject(new Error('Timed out locking the room.'));
      }, 8000);
      this.lockPending = { requestId: id, resolve, reject, timer };
      try {
        this.socket.send(JSON.stringify({ type: 'lock', requestId: id, expectedPeers }));
      } catch (error) {
        this.lockPending = null;
        clearTimeout(timer);
        reject(asError(error));
      }
    });
  }

  private async refreshRoute(peerId: string): Promise<void> {
    const runtime = this.runtimes.get(peerId);
    if (!runtime || runtime.connection.connectionState !== 'connected') return;
    try {
      runtime.info.route = routeFromStats(await runtime.connection.getStats());
      this.emit('status', { status: this.status, peerId });
    } catch { /* Stats support varies; transport remains usable. */ }
  }

  private async refreshRoutes(): Promise<void> {
    for (const peerId of this.runtimes.keys()) await this.refreshRoute(peerId);
  }

  private removePeer(peerId: string, reason: string): void {
    const runtime = this.runtimes.get(peerId);
    if (runtime?.restartTimer) clearTimeout(runtime.restartTimer);
    runtime?.reliable?.close();
    runtime?.realtime?.close();
    runtime?.connection.close();
    this.runtimes.delete(peerId);
    if (!this.peers.delete(peerId)) return;
    this.emit('peer-left', { peerId, reason });
    if (!this.runtimes.size) this.setStatus('waiting');
    if (peerId === this.hostId && this.role === 'guest') this.close('Host left the room.');
  }

  private failSignaling(error: Error): void {
    if (this.closed) return;
    const pending = this.readyReject;
    this.readyReject = null;
    this.readyResolve = null;
    if (pending) pending(error);
    else this.emit('error', error);
    this.close(error.message);
  }

  close(reason = 'Room closed.'): void {
    if (this.closed) return;
    this.closed = true;
    if (this.lockPending) {
      const pending = this.lockPending;
      this.lockPending = null;
      clearTimeout(pending.timer);
      pending.reject(new Error(reason));
    }
    if (this.openTimer) clearTimeout(this.openTimer);
    if (this.statsTimer) clearInterval(this.statsTimer);
    if (this.readyReject) this.readyReject(new Error(reason));
    this.readyReject = null;
    this.readyResolve = null;
    for (const peerId of this.peers.keys()) this.removePeer(peerId, reason);
    if (this.socket.readyState === WebSocket.OPEN) {
      try { this.socket.send(JSON.stringify({ type: 'leave' })); } catch { /* Closing. */ }
    }
    this.socket.close();
    this.setStatus('closed');
    this.emit('closed', { reason });
  }
}

export function createRoom(options: RoomOptions): Promise<MultiplayerSession> {
  return MultiplayerSession.connect(options, 'host');
}

export function joinRoom(options: JoinRoomOptions): Promise<MultiplayerSession> {
  return MultiplayerSession.connect(options, 'guest', options.roomCode);
}
