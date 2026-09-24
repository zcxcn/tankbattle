'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import { Copy, Globe2, Link2, Radio, Shield, Swords, Users, Wifi } from 'lucide-react';
import type { BattlefieldId } from '@/lib/battlefields';
import type { Save } from '@/lib/campaign';
import { createClientId } from '@/lib/client-id';
import {
  createRoom,
  joinRoom,
  type MultiplayerSession,
} from '@/lib/multiplayer/session';

const VERSION = 1;
const ROOM_CODE = /^[2-9A-HJ-NP-Z]{10}$/;
export type CoopLoadout = Pick<
  Save,
  'weapon' | 'support' | 'module' | 'upgrades' | 'chassis' | 'difficulty' | 'kills'
>;

export type MultiplayerRun = {
  session: MultiplayerSession;
  runId: string;
  battlefield: BattlefieldId;
  roster: Record<string, number>;
  localTankId: number;
  loadout: CoopLoadout;
};

type StartMessage = {
  type: 'start';
  version: number;
  runId: string;
  battlefield: BattlefieldId;
  roster: Record<string, number>;
  loadout: CoopLoadout;
};

function isStartMessage(value: unknown): value is StartMessage {
  if (!value || typeof value !== 'object') return false;
  const message = value as Partial<StartMessage>;
  const loadout = message.loadout;
  return (
    message.type === 'start' &&
    message.version === VERSION &&
    typeof message.runId === 'string' &&
    message.runId.length <= 64 &&
    message.battlefield === 'city' &&
    !!message.roster &&
    typeof message.roster === 'object' &&
    Object.values(message.roster).every((id) => Number.isSafeInteger(id) && id <= 0 && id >= -12) &&
    !!loadout &&
    Number.isInteger(loadout.weapon) &&
    Number.isInteger(loadout.support) &&
    Number.isInteger(loadout.module) &&
    Number.isInteger(loadout.chassis) &&
    Number.isInteger(loadout.difficulty) &&
    Number.isSafeInteger(loadout.kills) &&
    Array.isArray(loadout.upgrades) &&
    loadout.upgrades.length === 6 &&
    loadout.upgrades.every((level) => Number.isInteger(level) && level >= 0 && level <= 3)
  );
}

function initialFields() {
  if (typeof window === 'undefined') return { url: '', code: '' };
  const query = new URLSearchParams(window.location.search);
  const configured = (
    import.meta as ImportMeta & { env?: { VITE_SIGNAL_URL?: string } }
  ).env?.VITE_SIGNAL_URL;
  return {
    url:
      query.get('signal') ||
      configured ||
      window.localStorage.getItem('iron-embers-signal-url') ||
      (window.location.protocol === 'http:'
        ? `ws://${window.location.hostname}:8787`
        : ''),
    code: query.get('room')?.toUpperCase() || '',
  };
}

export default function MultiplayerLobby({
  active,
  save,
  onStart,
}: {
  active: boolean;
  save: Save;
  onStart: (run: MultiplayerRun) => void;
}) {
  const [fields] = useState(initialFields);
  const [signalUrl, setSignalUrl] = useState(fields.url);
  const [roomCode, setRoomCode] = useState(fields.code);
  const battlefield: BattlefieldId = 'city';
  const [maxPlayers, setMaxPlayers] = useState(4);
  const [session, setSession] = useState<MultiplayerSession | null>(null);
  const [status, setStatus] = useState('选择创建房间或输入房间码加入');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const sessionRef = useRef<MultiplayerSession | null>(null);
  const started = useRef(false);
  const [, setRevision] = useState(0);

  useEffect(() => {
    return () => sessionRef.current?.close();
  }, []);

  useEffect(() => {
    if (!session) return;
    const refresh = () => setRevision((value) => value + 1);
    const remove = [
      session.on('peer-joined', refresh),
      session.on('peer-ready', () => {
        setStatus('队友已直连，可以部署');
        refresh();
      }),
      session.on('peer-left', () => {
        setStatus('队友已离开房间');
        refresh();
      }),
      session.on('status', refresh),
      session.on('error', (detail) => {
        setError(String(detail));
        refresh();
      }),
      session.on('closed', () => {
        if (!started.current) {
          setStatus('房间已关闭');
          setSession(null);
          sessionRef.current = null;
        }
      }),
      session.on('control', ({ peerId, control }) => {
        if (session.role !== 'guest' || peerId !== session.hostId) return;
        if (!isStartMessage(control)) return;
        const localTankId = control.roster[session.peerId];
        if (!Number.isSafeInteger(localTankId) || localTankId >= 0) {
          setError('房间的玩家名单无效');
          return;
        }
        started.current = true;
        onStart({
          session,
          runId: control.runId,
          battlefield: control.battlefield,
          roster: control.roster,
          localTankId,
          loadout: control.loadout,
        });
      }),
    ];
    return () => remove.forEach((unsubscribe) => unsubscribe());
  }, [session, onStart]);

  const invite = useMemo(() => {
    if (!session || typeof window === 'undefined') return '';
    const url = new URL(window.location.href);
    url.searchParams.set('room', session.roomCode);
    url.searchParams.set('signal', signalUrl.trim());
    return url.toString();
  }, [session, signalUrl]);

  function validateUrl() {
    let url: URL;
    try {
      url = new URL(signalUrl.trim());
    } catch {
      throw new Error('请输入有效的协商服务器地址');
    }
    if (url.protocol !== 'ws:' && url.protocol !== 'wss:')
      throw new Error('协商地址应以 ws:// 或 wss:// 开头');
    if (window.location.protocol === 'https:' && url.protocol !== 'wss:')
      throw new Error('当前网页是 HTTPS，协商地址必须使用 wss://');
    window.localStorage.setItem('iron-embers-signal-url', url.toString());
    return url.toString();
  }

  async function connect(role: 'host' | 'guest') {
    setError('');
    setBusy(true);
    try {
      const url = validateUrl();
      const joined =
        role === 'host'
          ? await createRoom({ url, maxPlayers })
          : await joinRoom({ url, roomCode: roomCode.trim().toUpperCase() });
      sessionRef.current = joined;
      setSession(joined);
      setRoomCode(joined.roomCode);
      setStatus(
        role === 'host'
          ? '房间已创建，分享邀请链接，等待队友连接'
          : '已加入房间，正在连接房主',
      );
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : '连接失败，请检查网络');
    } finally {
      setBusy(false);
    }
  }

  function leave() {
    sessionRef.current?.close();
    sessionRef.current = null;
    setSession(null);
    setStatus('已离开房间');
  }

  async function start() {
    if (!session || session.role !== 'host' || active || busy) return;
    const peers = [...session.peers.keys()];
    if (!peers.length || !peers.every((peerId) => session.peers.get(peerId)?.status === 'connected')) {
      setError('至少一名队友完成直连后才能开始');
      return;
    }
    setBusy(true);
    setError('');
    let roomLocked = false;
    try {
      // The server atomically freezes this exact roster before a start packet
      // can be sent. A concurrent join is rejected instead of entering a room
      // without a tank assignment.
      await session.lockRoom(peers);
      roomLocked = true;
      if (peers.some((peerId) => session.peers.get(peerId)?.status !== 'connected'))
        throw new Error('队友连接中断，请等待重连');
      const roster: Record<string, number> = { [session.peerId]: 0 };
      peers.sort().forEach((peerId, index) => (roster[peerId] = -10 - index));
      const runId = createClientId();
      const message: StartMessage = {
        type: 'start',
        version: VERSION,
        runId,
        battlefield,
        roster,
        loadout: {
          weapon: save.weapon,
          support: save.support,
          module: save.module,
          upgrades: [...save.upgrades],
          chassis: save.chassis,
          difficulty: save.difficulty,
          kills: save.kills,
        },
      };
      for (const peerId of peers) {
        if (!session.sendControl(message, peerId))
          throw new Error('队友连接中断，请等待重连');
      }
      started.current = true;
      onStart({ session, runId, battlefield, roster, localTankId: 0, loadout: message.loadout });
    } catch (reason) {
      // A start packet may already have reached one teammate. Closing the
      // room brings everyone back to the lobby instead of stranding that
      // teammate in a match without an authoritative host.
      if (roomLocked) session.close('Room start failed.');
      setError(reason instanceof Error ? reason.message : '无法开始战斗');
    } finally {
      setBusy(false);
    }
  }

  async function copy(text: string) {
    try {
      await navigator.clipboard.writeText(text);
      setStatus('邀请链接已复制');
    } catch {
      setError('复制失败，请手动复制邀请链接');
    }
  }

  return (
    <section className="multiplayer-lobby" aria-label="联机协作大厅">
      <div className="multiplayer-hero">
        <div className="multiplayer-emblem"><Swords size={30} /></div>
        <div>
          <span>COOPERATIVE OPERATIONS</span>
          <h2>组建装甲小队</h2>
          <p>2–4 人合作清除敌军与 Boss。房主计算战斗，队友通过 WebRTC 直接同步。</p>
        </div>
      </div>
      <div className="multiplayer-grid">
        <div className="multiplayer-panel">
          <h3><Globe2 size={18} /> 房间连接</h3>
          <label>
            协商服务器 WSS 地址
            <input
              value={signalUrl}
              onChange={(event) => setSignalUrl(event.target.value)}
              disabled={!!session || busy}
              placeholder="wss://signal.example.com"
              spellCheck={false}
              autoCapitalize="none"
            />
          </label>
          {!session && (
            <div className="multiplayer-entry">
              <div>
                <label>
                  房间码
                  <input
                    value={roomCode}
                    onChange={(event) => setRoomCode(event.target.value.toUpperCase())}
                    maxLength={10}
                    placeholder="输入队友发来的房间码"
                    autoCapitalize="characters"
                  />
                </label>
                <button disabled={busy || !ROOM_CODE.test(roomCode)} onClick={() => void connect('guest')}>
                  加入房间
                </button>
              </div>
              <span>或</span>
              <div>
                <label>
                  房间人数
                  <select value={maxPlayers} onChange={(event) => setMaxPlayers(Number(event.target.value))}>
                    <option value={2}>2 人</option>
                    <option value={3}>3 人</option>
                    <option value={4}>4 人</option>
                  </select>
                </label>
                <button className="multiplayer-primary" disabled={busy} onClick={() => void connect('host')}>
                  创建房间
                </button>
              </div>
            </div>
          )}
          {session && (
            <div className="multiplayer-room">
              <div className="multiplayer-code"><small>ROOM CODE</small><strong>{session.roomCode}</strong></div>
              <button onClick={() => void copy(invite)} title="复制邀请链接"><Copy size={17} /> 复制邀请链接</button>
              <input aria-label="邀请链接" readOnly value={invite} onFocus={(event) => event.target.select()} />
              <div className="multiplayer-members">
                <span><Shield size={15} /> 房主 <b>{session.role === 'host' ? '你' : `${session.hostId.slice(0, 8)} · ${session.peers.get(session.hostId)?.status === 'connected' ? '已连接' : '连接中'}`}</b></span>
                {[...session.peers].filter(([peerId]) => peerId !== session.hostId).map(([peerId, info]) => (
                  <span key={peerId}>
                    <Wifi size={15} /> 队友 {peerId.slice(0, 8)}
                    <b>{session.role === 'guest' ? '房间内' : info.status === 'connected' ? `${info.route.kind === 'lan' ? '局域网' : info.route.kind === 'relay' ? '中继' : info.route.kind === 'direct' ? '直连' : '已连接'}${info.route.rttMs == null ? '' : ` · ${Math.round(info.route.rttMs)}ms`}` : '连接中'}</b>
                  </span>
                ))}
              </div>
              {session.role === 'host' && (
                <>
                  <button className="multiplayer-primary" disabled={busy || !session.peers.size || [...session.peers.values()].some((peer) => peer.status !== 'connected')} onClick={() => void start()}>
                    <Swords size={18} /> 全队出击
                  </button>
                </>
              )}
              {session.role === 'guest' && <p className="multiplayer-wait">等待房主部署战斗…</p>}
              {!active && <button className="multiplayer-leave" onClick={leave}>离开房间</button>}
            </div>
          )}
          <output className="multiplayer-status"><Radio size={14} /> {busy ? '正在连接…' : status}</output>
          {!!error && <p className="multiplayer-error" role="alert">{error}</p>}
        </div>
        <aside className="multiplayer-notes">
          <h3><Users size={18} /> 联机说明</h3>
          <p>优先使用局域网或跨网直连；若网络无法直连，需要协商服务提供 TURN 中继。实际路线会显示在队友列表。</p>
          <p>房主离开或关闭浏览器会结束战斗。联机战绩不会写入单人战役存档。</p>
          <p><Link2 size={14} /> 邀请链接包含房间码与协商地址，可直接发给队友。</p>
        </aside>
      </div>
    </section>
  );
}
