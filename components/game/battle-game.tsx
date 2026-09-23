'use client';
import { useEffect, useRef, useState } from 'react';
import {
  Pause,
  Play,
  ArrowLeft,
  RotateCcw,
  Crosshair,
  Zap,
  Wind,
  Shield,
  Radio,
  Radar,
  Volume2,
  Music2,
  VolumeX,
  Camera,
  Maximize,
  Rocket,
  Target,
  Flame,
  Snowflake,
  Gauge,
  ChevronsRight,
  CircleDot,
  Users,
  Wifi,
} from 'lucide-react';
import {
  Dialog,
  DialogContent,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog';
import {
  Battle,
  W,
  H,
  ENEMY_REGION,
  type Objective,
  type Input,
  type BattleResult,
  type SoundEvent,
} from '@/lib/engine';
import type {
  Renderer3D,
  CameraMode,
  RendererProgress,
} from '@/lib/three/renderer3d';
import { battlefieldFor, OPERATIONS } from '@/lib/battlefields';
import { preloadRenderer } from '@/lib/three/renderer-loader';
import {
  FramePacer,
  AdaptiveResolution,
  renderPolicy,
  isMobileDevice,
  deviceState,
} from '@/lib/performance';
import { FixedStep } from '@/lib/fixed-step';
import { GameAudio } from '@/lib/audio';
import { TacticalRadioDirector, type RadioCue } from '@/lib/tactical-radio';
import { MUSIC_TRACKS, type MusicScene, type AudioSettings } from '@/lib/music';
import MusicControls from './music-controls';
import { progression } from '@/lib/progression';
import type { PadFrame } from '@/lib/gamepad';
import type { MultiplayerRun } from './multiplayer-lobby';
import {
  CHASSIS,
  MISSIONS,
  SUPPORTS,
  WEAPONS,
  loadoutStats,
  bossName,
  type Save,
} from '@/lib/campaign';
const clock = (s: number) =>
  `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(Math.floor(s % 60)).padStart(2, '0')}`;
const WEAPON_ICONS = [
  Target,
  Gauge,
  Crosshair,
  ChevronsRight,
  Flame,
  Snowflake,
  Rocket,
];
const WEAPON_LABELS = ['加农', '机枪', '霰弹', '磁轨', '榴弹', '脉冲', '火箭'];

type OneShotAction =
  | { type: 'action'; action: 'dash' | 'emp' | 'support' | 'mine' | 'nextWeapon' }
  | { type: 'action'; action: 'weapon'; weapon: number };
type NetworkSnapshot = ReturnType<Battle['createSnapshot']> & { networkSequence: number };

function createNetworkSnapshot(battle: Battle, sequence: { current: number }): NetworkSnapshot {
  return { ...battle.createSnapshot(), networkSequence: ++sequence.current };
}

function snapshotSequenceOf(raw: unknown): number | null {
  if (!raw || typeof raw !== 'object') return null;
  const sequence = (raw as { networkSequence?: unknown }).networkSequence;
  return Number.isSafeInteger(sequence) && (sequence as number) > 0 ? sequence as number : null;
}

/** Clear a one-shot only after the reliable channel accepted it. */
function sendGuestActions(input: Input, send: (action: OneShotAction) => boolean): void {
  if (input.weapon !== undefined) {
    if (!send({ type: 'action', action: 'weapon', weapon: input.weapon })) return;
    input.weapon = undefined;
  }
  for (const action of ['nextWeapon', 'dash', 'emp', 'support', 'mine'] as const) {
    if (input[action] !== true) continue;
    if (!send({ type: 'action', action })) return;
    input[action] = false;
  }
}

function parseRemoteAction(raw: unknown): OneShotAction | null {
  if (!raw || typeof raw !== 'object') return null;
  const data = raw as Record<string, unknown>;
  if (data.type !== 'action') return null;
  if (data.action === 'weapon')
    return Number.isInteger(data.weapon) && (data.weapon as number) >= 0 &&
      (data.weapon as number) < WEAPONS.length
      ? { type: 'action', action: 'weapon', weapon: data.weapon as number }
      : null;
  if (['nextWeapon', 'dash', 'emp', 'support', 'mine'].includes(String(data.action)))
    return { type: 'action', action: data.action as 'nextWeapon' | 'dash' | 'emp' | 'support' | 'mine' };
  return null;
}

/** Take a FIFO prefix. Weapon selection and cycling need separate fixed steps. */
function mergeQueuedActions(base: Input, queue: OneShotAction[]): { input: Input; count: number } {
  const input = { ...base };
  const taken = new Set<string>();
  let count = 0;
  for (const action of queue) {
    const key = action.action === 'weapon' || action.action === 'nextWeapon'
      ? 'weapon' : action.action;
    if (taken.has(key)) break;
    taken.add(key);
    if (action.action === 'weapon') input.weapon = action.weapon;
    else input[action.action] = true;
    count++;
  }
  return { input, count };
}
type Props = {
  runId: string;
  multiplayer?: MultiplayerRun;
  onProgress: (runId: string, kills: number) => void;
  mission: number;
  endless: boolean;
  save: Save;
  onFinish: (r: BattleResult) => void;
  onExit: () => void;
  onRetry: () => void;
  onMusicScene: (scene: MusicScene) => void;
  onMusicPause: (paused: boolean) => void;
  onRadioActive?: (active: boolean) => void;
  onAudioChange: (patch: Partial<AudioSettings>) => void;
};
export default function BattleGame({
  runId,
  multiplayer,
  onProgress,
  mission,
  endless,
  save,
  onFinish,
  onExit,
  onRetry,
  onMusicScene,
  onMusicPause,
  onRadioActive,
  onAudioChange,
}: Props) {
  const field = battlefieldFor(mission, save.battlefield);
  const operation = OPERATIONS.find(
    (operation) => operation.id === save.operation,
  );
  const scenario =
    save.battlefield !== 'campaign' || save.operation !== 'campaign';
  const canvas = useRef<HTMLCanvasElement>(null),
    engine = useRef<Battle | null>(null),
    renderer = useRef<Renderer3D | null>(null),
    sound = useRef<GameAudio | null>(null),
    callback = useRef(onFinish);
  callback.current = onFinish;
  const progressCallback = useRef(onProgress);
  progressCallback.current = onProgress;
  const musicCallback = useRef(onMusicScene);
  musicCallback.current = onMusicScene;
  const [gamepad, setGamepad] = useState(false);
  const [weaponRackOpen, setWeaponRackOpen] = useState(false);
  const [radarOpen, setRadarOpen] = useState(false);
  const [radioCue, setRadioCue] = useState<RadioCue | null>(null);
  const radioCallback = useRef(onRadioActive);
  radioCallback.current = onRadioActive;
  const mouseFire = useRef(false);
  const renderDirty = useRef(true);
  const aimSource = useRef<'mouse' | 'pad' | 'touch'>('mouse');
  const stickPointers = useRef<{ move: number | null; aim: number | null }>({
    move: null,
    aim: null,
  });
  const touchAim = useRef({ x: 0, y: -1, fire: false });
  const [performanceLabel, setPerformanceLabel] = useState('');
  const [connectionNotice, setConnectionNotice] = useState('');
  const [connectionError, setConnectionError] = useState('');
  const firingPointer = useRef<number | null>(null);
  const pointerScreen = useRef<{ x: number; y: number } | null>(null);
  const snapshotSequence = useRef(0);
  const pendingStateSnapshots = useRef(new Map<string, NetworkSnapshot>());
  const errorRef = useRef('');
  const clearInput = useRef<() => void>(() => {});
  const [loadProgress, setLoadProgress] = useState<RendererProgress>({
    progress: 0,
    label: '装载 3D 引擎',
  });
  const [loading, setLoading] = useState(true),
    [loadError, setLoadError] = useState(''),
    [cameraMode, setCameraMode] = useState<CameraMode>('assault');
  errorRef.current = loadError;
  function switchCamera() {
    if (renderer.current) {
      setCameraMode(renderer.current.toggleCamera());
      renderDirty.current = true;
    }
  }
  function fullscreen() {
    // Dialog portals live under body; fullscreen must include them and survive battle retries.
    const element = document.documentElement;
    if (!document.fullscreenElement)
      void element.requestFullscreen?.().catch(() => {});
    else void document.exitFullscreen?.().catch(() => {});
  }

  const controls = useRef<Input>({
      x: 0,
      y: 0,
      aim: null,
      fire: false,
      dash: false,
      emp: false,
    }),
    touch = useRef({ x: 0, y: 0 });
  const [paused, setPaused] = useState(false),
    [hud, setHud] = useState({
      hp: loadoutStats(save).hp,
      max: loadoutStats(save).hp,
      kills: 0,
      career: progression(save.kills),
      levelUp: 0,
      score: 0,
      time: 0,
      dash: 0,
      emp: 0,
      support: 0,
      mineCd: 0,
      mineAmmo: 6,
      mines: [] as { id: number; x: number; y: number; enemy: boolean }[],
      bossPhase: 0,
      bossWarning: false,
      weapon: 0,
      ammo: WEAPONS.map((_, i) => (i === 0 ? Infinity : 0)),
      supplies: [] as { x: number; y: number; weapon: number }[],
      reload: 0,
      objective:
        operation?.description ?? (MISSIONS[mission].objective as string),
      objectives: [] as Objective[],
      convoy: null as { x: number; y: number } | null,
      route: [] as { x: number; y: number }[],
      nav: null as { x: number; y: number; label: string } | null,
      base: 340,
      notice: '加农炮弹药无限 · 击毁敌车拾取特殊弹药',
      boss: 0,
      bossMax: 0,
      rapid: 0,
      shield: 0,
      wave: 1,
      radarEnemies: [] as { x: number; y: number; boss: boolean }[],
      radarPlayer: { x: W / 2, y: H - 185, angle: -Math.PI / 2 },
    });
  function flushStateSnapshots() {
    if (multiplayer?.session.role !== 'host') return;
    for (const [peerId, snapshot] of pendingStateSnapshots.current) {
      if (!multiplayer.session.peers.has(peerId) ||
        multiplayer.session.sendControl({ type: 'state-snapshot', snapshot }, peerId))
        pendingStateSnapshots.current.delete(peerId);
    }
  }
  function queueStateSnapshot(battle: Battle, peerIds: Iterable<string> | undefined = multiplayer?.session.peers.keys()) {
    if (multiplayer?.session.role !== 'host' || !peerIds) return;
    const snapshot = createNetworkSnapshot(battle, snapshotSequence);
    for (const peerId of peerIds) pendingStateSnapshots.current.set(peerId, snapshot);
    flushStateSnapshots();
  }
  function pause(v: boolean) {
    const b = engine.current;
    if (!b || b.result || (!v && errorRef.current)) return;
    if (multiplayer?.session.role === 'guest') {
      clearInput.current();
      if (v) sound.current?.suspend();
      setConnectionNotice('只有房主能暂停或继续全队');
      return;
    }
    b.paused = v;
    if (multiplayer?.session.role === 'host')
      queueStateSnapshot(b);
    if (v) sound.current?.suspend();
    else sound.current?.unlock();
    clearInput.current();
    mouseFire.current = false;
    controls.current.x = 0;
    controls.current.y = 0;
    touch.current = { x: 0, y: 0 };
    setPaused(v);
  }
  useEffect(() => {
    onMusicPause(paused || loading || !!loadError);
  }, [paused, loading, loadError, onMusicPause]);
  useEffect(() => {
    if (sound.current) {
      sound.current.enabled = save.sound;
      sound.current.setMotion(0, false);
    }
  }, [save.sound]);
  useEffect(() => {
    const seed =
      Array.from(runId).reduce(
        (value, letter) => Math.imul(value ^ letter.charCodeAt(0), 16777619),
        2166136261,
      ) >>> 0;
    const b = new Battle(mission, endless, save, seed, runId);
    if (!multiplayer)
      b.onProgress = (kills) => progressCallback.current(b.runId, kills);
    if (multiplayer) {
      for (const playerId of Object.values(multiplayer.roster))
        if (playerId !== 0) b.addPlayer(playerId);
      b.viewPlayerId = multiplayer.localTankId;
    }
    engine.current = b;
    const mobile = isMobileDevice();
    const pacer = new FramePacer(),
      adaptive = new AdaptiveResolution();
    let nextBudget = 0;
    let policy = renderPolicy(save.fps, mobile, deviceState);
    const fixed = new FixedStep(),
      radio = new TacticalRadioDirector(),
      a = new GameAudio(setRadioCue, (active) =>
        radioCallback.current?.(active),
      );
    a.enabled = save.sound;
    // Start audio fetch/decode after graphics; the first combat input unlocks
    // a suspended browser context and procedural sounds remain available.
    sound.current = a;
    b.onSound = (event, weapon) => {
      a.play(event, weapon);
      if (multiplayer?.session.role === 'host')
        multiplayer.session.sendControl({ type: 'sound', event, weapon });
    };
    const remoteInputs = new Map<number, { input: Input; receivedAt: number }>();
    const remoteActions = new Map<number, OneShotAction[]>();
    const listeners: (() => void)[] = [];
    let nextInput = 0;
    let nextSnapshot = 0;
    let finalSnapshot: NetworkSnapshot | null = null;
    let finalSnapshotApplied = false;
    let lastAppliedSnapshot = 0;
    const finalRecipients = new Set<string>();
    const publishFinalSnapshot = () => {
      if (!b.result || multiplayer?.session.role !== 'host') return;
      finalSnapshot ??= createNetworkSnapshot(b, snapshotSequence);
      for (const peerId of multiplayer.session.peers.keys()) {
        if (finalRecipients.has(peerId)) continue;
        if (multiplayer.session.sendControl({ type: 'final-snapshot', snapshot: finalSnapshot }, peerId))
          finalRecipients.add(peerId);
      }
    };
    if (multiplayer) {
      const { session, roster } = multiplayer;
      if (session.role === 'host') {
        listeners.push(
          session.on('input', ({ peerId, input }) => {
            const tankId = roster[peerId];
            if (!Number.isInteger(tankId) || tankId >= 0) return;
            const value = input as Partial<Input> | null;
            if (!value || typeof value !== 'object') return;
            const finite = (n: unknown) => typeof n === 'number' && Number.isFinite(n);
            const axis = (n: unknown) => finite(n) ? Math.max(-1, Math.min(1, n as number)) : 0;
            const aim = value.aim && finite(value.aim.x) && finite(value.aim.y)
              ? { x: Math.max(0, Math.min(W, value.aim.x)), y: Math.max(0, Math.min(H, value.aim.y)) }
              : null;
            remoteInputs.set(tankId, {
              input: {
                x: axis(value.x), y: axis(value.y), aim,
                fire: value.fire === true, dash: false, emp: false,
              },
              receivedAt: performance.now(),
            });
          }),
          session.on('control', ({ peerId, control }) => {
            const tankId = roster[peerId];
            if (!Number.isInteger(tankId) || tankId >= 0 || !session.peers.has(peerId)) return;
            const action = parseRemoteAction(control);
            if (!action) return;
            const queue = remoteActions.get(tankId) ?? [];
            if (queue.length >= 64) return;
            queue.push(action);
            remoteActions.set(tankId, queue);
          }),
          session.on('peer-ready', ({ peerId }) => {
            if (b.result) {
              finalRecipients.delete(peerId);
              publishFinalSnapshot();
            } else queueStateSnapshot(b, [peerId]);
          }),
          session.on('peer-left', ({ peerId }) => {
            pendingStateSnapshots.current.delete(peerId);
            const tankId = roster[peerId];
            if (Number.isInteger(tankId) && tankId < 0) {
              remoteInputs.delete(tankId);
              remoteActions.delete(tankId);
              b.removePlayer(tankId);
              queueStateSnapshot(b);
            }
            setConnectionNotice('一名队友已离开战斗');
          }),
        );
      } else {
        const applyHostSnapshot = (snapshot: unknown, final = false) => {
          if (finalSnapshotApplied) return;
          const sequence = snapshotSequenceOf(snapshot);
          if (sequence === null) {
            setConnectionError('战斗同步数据无效，请退出房间后重试。');
            return;
          }
          if (sequence <= lastAppliedSnapshot) return;
          if (final &&
            (snapshot as { result?: BattleResult }).result?.runId !== b.runId) {
            setConnectionError('终局同步数据无效，请退出房间后重试。');
            return;
          }
          try {
            const wasPaused = b.paused;
            b.applySnapshot(snapshot as ReturnType<Battle['createSnapshot']>);
            if (final && !b.result) throw new Error('Missing final result');
            lastAppliedSnapshot = sequence;
            if (final) finalSnapshotApplied = true;
            if (wasPaused !== b.paused) {
              if (b.paused) a.suspend();
              else if (!document.hidden) a.unlock();
            }
            setPaused(b.paused);
            renderDirty.current = true;
          } catch {
            setConnectionError(final ? '终局同步失败，请退出房间后重试。' :
              '战斗同步失败，请退出房间后重试。');
          }
        };
        listeners.push(
          session.on('control', ({ peerId, control }) => {
            if (peerId !== session.hostId || !control || typeof control !== 'object') return;
            const cue = control as { type?: unknown; event?: unknown; weapon?: unknown };
            const sounds: SoundEvent[] = ['fire', 'enemyfire', 'explosion', 'hit', 'emp', 'pickup', 'dash', 'levelup'];
            if (cue.type === 'sound' && sounds.includes(cue.event as SoundEvent))
              a.play(cue.event as SoundEvent,
                Number.isInteger(cue.weapon) ? Math.max(0, Math.min(6, cue.weapon as number)) : 0);
            if (cue.type === 'state-snapshot' || cue.type === 'final-snapshot')
              applyHostSnapshot((control as { snapshot?: unknown }).snapshot,
                cue.type === 'final-snapshot');
          }),
          session.on('snapshot', ({ peerId, snapshot }) => {
            if (peerId === session.hostId) applyHostSnapshot(snapshot);
          }),
        );
      }
      listeners.push(
        session.on('closed', ({ reason }) => {
          b.paused = true;
          setConnectionError(`房间连接已结束：${reason}`);
        }),
        session.on('error', (error) => setConnectionNotice(error.message)),
        session.on('status', () => {
          const route = session.peers.get(session.role === 'guest' ? session.hostId : [...session.peers.keys()][0])?.route;
          if (route) setConnectionNotice(
            `${route.kind === 'lan' ? '局域网直连' : route.kind === 'relay' ? '中继' : route.kind === 'direct' ? '跨网直连' : '连接中'}${route.rttMs == null ? '' : ` · ${route.rttMs} ms`}`,
          );
        }),
      );
    }
    let disposed = false,
      frame = 0,
      previous = performance.now(),
      nextHud = 0,
      reported = false,
      finaleStarted = 0,
      initialized = false;
    let r: Renderer3D | null = null,
      resize: ResizeObserver | undefined;
    const keys = new Set<string>();
    let pad: PadFrame | null = null;
    let padAim = { x: 0, y: -1 };
    const onPad = (event: Event) => {
      const frame = (event as CustomEvent<PadFrame>).detail;
      pad = frame;
      setGamepad((old) => (old === frame.connected ? old : frame.connected));
      if (frame.disconnected) {
        pause(true);
        pad = null;
        return;
      }
      if (errorRef.current || !initialized || b.result) return;
      if (frame.pause) pause(!b.paused);
      if (b.paused) return;
      if (frame.camera) switchCamera();
      if (frame.dash) controls.current.dash = true;
      if (frame.emp) controls.current.emp = true;
      if (frame.support) controls.current.support = true;
      if (frame.mine) controls.current.mine = true;
      if (frame.weapon) controls.current.nextWeapon = true;
      if (frame.aimX || frame.aimY) {
        padAim = { x: frame.aimX, y: frame.aimY };
        aimSource.current = 'pad';
      } else if (frame.fire && aimSource.current !== 'pad') {
        padAim = { x: Math.cos(b.viewPlayer.turret), y: Math.sin(b.viewPlayer.turret) };
        aimSource.current = 'pad';
      }
      if (frame.active) a.unlock();
    };
    const resume = () => pause(false);
    window.addEventListener('tank-gamepad', onPad);
    window.addEventListener('tank-gamepad-resume', resume);
    const clear = () => {
      keys.clear();
      mouseFire.current = false;
      pad = null;
      controls.current = {
        x: 0,
        y: 0,
        aim: controls.current.aim,
        fire: false,
        dash: false,
        emp: false,
      };
      touch.current = { x: 0, y: 0 };
      firingPointer.current = null;
      touchAim.current.fire = false;
      stickPointers.current = { move: null, aim: null };
      document.querySelectorAll<HTMLElement>('.touch-stick').forEach((el) => {
        el.style.setProperty('--sx', '0px');
        el.style.setProperty('--sy', '0px');
      });
      fixed.reset();
      pacer.reset();
    };
    clearInput.current = clear;
    const keydown = (event: KeyboardEvent) => {
      const k = event.key.toLowerCase();
      // Dialogs own their keyboard defaults (including Space on buttons).
      // Reject inactive combat before preventing browser/UI key handling.
      if (event.defaultPrevented || b.paused || b.result || !initialized)
        return;
      if (
        event.target instanceof Element &&
        event.target.closest(
          'input, textarea, select, [contenteditable=""], [contenteditable="true"], [role="dialog"], [role="alertdialog"]',
        )
      )
        return;
      if (
        [
          'w',
          'a',
          's',
          'd',
          'arrowup',
          'arrowdown',
          'arrowleft',
          'arrowright',
          ' ',
          'e',
          'q',
          'c',
          'f',
          'escape',
          'r',
          'm',
          '1',
          '2',
          '3',
          '4',
          '5',
          '6',
          '7',
        ].includes(k)
      )
        event.preventDefault();
      if (k === 'escape') {
        if (!event.repeat) pause(!b.paused);
        return;
      }
      if (k === 'c' && !event.repeat) {
        switchCamera();
        return;
      }
      if (k === 'f' && !event.repeat) {
        fullscreen();
        return;
      }
      keys.add(k);
      if (!event.repeat && k === ' ') controls.current.dash = true;
      if (!event.repeat && k === 'e') controls.current.emp = true;
      if (!event.repeat && k === 'q') controls.current.support = true;
      if (!event.repeat && k === 'm') controls.current.mine = true;
      if (!event.repeat && k === 'r') controls.current.nextWeapon = true;
      if (!event.repeat && /^[1-7]$/.test(k))
        controls.current.weapon = Number(k) - 1;
      a.unlock();
    };
    const keyup = (event: KeyboardEvent) =>
      keys.delete(event.key.toLowerCase());
    const blur = () => {
      pause(true);
      a.suspend();
    };
    const nativeState = () => {
      if (deviceState.background) {
        pause(true);
        a.suspend();
      }
      nextBudget = 0;
    };
    const nativeBack = () => {
      if (!b.result) pause(!b.paused);
    };
    window.addEventListener('tank-native-state', nativeState);
    window.addEventListener('tank-native-back', nativeBack);
    const hidden = () => {
      if (document.hidden) {
        pause(true);
        a.suspend();
      }
    };
    const up = (event: PointerEvent) => {
      if (event.pointerId === firingPointer.current) {
        mouseFire.current = false;
        firingPointer.current = null;
      }
    };
    const wheel = (event: WheelEvent) => {
      event.preventDefault();
      r?.setZoom(event.deltaY);
      renderDirty.current = true;
    };
    window.addEventListener('keydown', keydown);
    window.addEventListener('keyup', keyup);
    window.addEventListener('blur', blur);
    window.addEventListener('pointerup', up);
    window.addEventListener('pointercancel', up);
    // A rotated/resized viewport invalidates the thumb positions and capture.
    window.addEventListener('resize', clear);
    document.addEventListener('visibilitychange', hidden);
    canvas.current?.addEventListener('wheel', wheel, { passive: false });
    const contextLost = (event: Event) => {
      event.preventDefault();
      a.suspend();
      errorRef.current = '图形设备连接已中断，请重新进入战场。';
      initialized = false;
      b.paused = true;
      clear();
      setPaused(false);
      setLoadError(errorRef.current);
      cancelAnimationFrame(frame);
      r?.dispose();
    };
    canvas.current?.addEventListener('webglcontextlost', contextLost);
    const oldOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    const surface = canvas.current;
    const loop = (now: number) => {
      if (disposed || !r) return;
      frame = requestAnimationFrame(loop);
      if (multiplayer?.session.role === 'host') {
        if (b.result) {
          pendingStateSnapshots.current.clear();
          publishFinalSnapshot();
        } else flushStateSnapshots();
      }
      if (
        b.result &&
        !reported &&
        !document.hidden &&
        !deviceState.background &&
        !errorRef.current
      ) {
        // Let the final blast unfold without advancing combat or its score clock.
        if (!finaleStarted)
          musicCallback.current(b.result.won ? 'victory' : 'defeat');
        finaleStarted ||= now;
        const age = (now - finaleStarted) / 1000;
        if (pacer.take(now, policy.fps))
          r.draw(b, null, b.elapsed + Math.min(0.85, age));
        if (age >= (mobile ? 0.25 : 0.85) && (!a.radioBusy || age >= 4)) {
          reported = true;
          callback.current(b.result);
        }
        return;
      }
      if (b.paused || b.result || document.hidden || deviceState.background) {
        previous = now;
        fixed.reset();
        pacer.reset();
        if (
          renderDirty.current &&
          !document.hidden &&
          !deviceState.background &&
          !errorRef.current
        ) {
          r.draw(b, controls.current.aim);
          renderDirty.current = false;
        }
        return;
      }
      if (!pacer.take(now, policy.fps)) return;
      const dt = Math.min(0.15, (now - previous) / 1000);
      previous = now;
      if (initialized && mobile) adaptive.sample(dt * 1000, policy.fps);
      if (now >= nextBudget) {
        policy = renderPolicy(
          save.fps,
          mobile,
          deviceState,
          mobile ? adaptive.pressure : 0,
        );
        if (mobile) r.setBudget(policy.scale, policy.effects);
        setPerformanceLabel(policy.label);
        nextBudget = now + 1000;
      }
      const horizontal =
        Number(keys.has('d') || keys.has('arrowright')) -
          Number(keys.has('a') || keys.has('arrowleft')) ||
        touch.current.x ||
        pad?.x ||
        0;
      const vertical =
        Number(keys.has('s') || keys.has('arrowdown')) -
          Number(keys.has('w') || keys.has('arrowup')) ||
        touch.current.y ||
        pad?.y ||
        0;
      controls.current.x = horizontal;
      controls.current.y = vertical;
      controls.current.fire =
        mouseFire.current || touchAim.current.fire || !!pad?.fire;
      if (aimSource.current === 'touch') {
        controls.current.aim = {
          x: b.viewPlayer.x + touchAim.current.x * 650,
          y: b.viewPlayer.y + touchAim.current.y * 650,
        };
      } else if (aimSource.current === 'pad') {
        const len = Math.hypot(padAim.x, padAim.y) || 1;
        controls.current.aim = {
          x: b.viewPlayer.x + (padAim.x / len) * 650,
          y: b.viewPlayer.y + (padAim.y / len) * 650,
        };
      } else if (pointerScreen.current) {
        const picked = r.pointer(
          pointerScreen.current.x,
          pointerScreen.current.y,
        );
        if (picked) controls.current.aim = picked;
      }
      const oldX = b.viewPlayer.x,
        oldY = b.viewPlayer.y,
        oldAngle = b.viewPlayer.angle,
        oldTime = b.elapsed;
      if (initialized) {
        if (multiplayer?.session.role === 'guest') {
          sendGuestActions(controls.current, (action) => multiplayer.session.sendControl(action));
          if (now >= nextInput) {
            multiplayer.session.sendInput({
              x: controls.current.x,
              y: controls.current.y,
              aim: controls.current.aim,
              fire: controls.current.fire,
            });
            nextInput = now + 33;
          }
        } else {
          const liveInputs: Record<number, Input> = {};
          const selectedActions: { queue: OneShotAction[]; count: number }[] = [];
          if (multiplayer) {
            for (const [peerId, playerId] of Object.entries(multiplayer.roster)) {
              if (playerId >= 0 || !multiplayer.session.peers.has(peerId)) continue;
              const remote = remoteInputs.get(playerId);
              const base = remote && now - remote.receivedAt <= 200
                ? remote.input
                : { x: 0, y: 0, aim: null, fire: false, dash: false, emp: false };
              const queue = remoteActions.get(playerId) ?? [];
              const merged = mergeQueuedActions(base, queue);
              liveInputs[playerId] = merged.input;
              if (merged.count) selectedActions.push({ queue, count: merged.count });
            }
          }
          const steps = fixed.advance(b, dt, controls.current, liveInputs);
          if (steps > 0)
            for (const selected of selectedActions) selected.queue.splice(0, selected.count);
          if (multiplayer && b.result) publishFinalSnapshot();
          else if (multiplayer && now >= nextSnapshot) {
            multiplayer.session.sendSnapshot(createNetworkSnapshot(b, snapshotSequence));
            nextSnapshot = now + 100;
          }
        }
      }
      const stepTime = b.elapsed - oldTime;
      // Drive sound from simulation displacement so a blocked tank does not clatter at full speed.
      if (stepTime > 0 || !initialized || b.result)
        a.setMotion(
          stepTime > 0
            ? Math.hypot(b.viewPlayer.x - oldX, b.viewPlayer.y - oldY) /
                stepTime /
                b.viewPlayer.speed
            : 0,
          initialized && !b.paused && !b.result,
          stepTime > 0
            ? Math.abs(
                Math.atan2(
                  Math.sin(b.viewPlayer.angle - oldAngle),
                  Math.cos(b.viewPlayer.angle - oldAngle),
                ),
              ) /
                stepTime /
                4
            : 0,
        );
      if (initialized) {
        const cue = radio.update(b);
        if (cue) a.announce(cue);
      }
      r.draw(b, controls.current.aim);
      renderDirty.current = false;
      // The finale stops simulation/HUD polling. Publish its final state even
      // when the decisive hit lands between the usual 100/150 ms updates.
      if (now > nextHud || b.result) {
        nextHud = now + (mobile ? 150 : 100);
        musicCallback.current(
          b.viewPlayer.hp / b.viewPlayer.maxHp < 0.3
            ? 'danger'
            : b.boss
              ? 'boss'
              : b.enemies.some(
                    (e) =>
                      e.hp > 0 &&
                      e.spawn <= 0 &&
                      Math.hypot(e.x - b.viewPlayer.x, e.y - b.viewPlayer.y) < 650,
                  )
                ? 'battle'
                : 'patrol',
        );
        setHud({
          hp: b.viewPlayer.hp,
          max: b.viewPlayer.maxHp,
          kills: b.kills,
          career: b.career,
          levelUp: b.levelUpTime,
          score: b.score,
          time: b.elapsed,
          dash: b.viewPlayer.kit?.dashCd ?? b.dashCd,
          emp: b.viewPlayer.kit?.empCd ?? b.empCd,
          support: b.viewPlayer.kit?.supportCd ?? b.supportCd,
          mineCd: b.viewPlayer.kit?.mineCd ?? b.mineCd,
          mineAmmo: b.mineAmmoFor(b.viewPlayerId),
          mines: b.mines.map((m) => ({
            id: m.id,
            x: m.x,
            y: m.y,
            enemy: m.enemy,
          })),
          bossPhase: b.bossThreshold,
          bossWarning: (b.boss?.attackWindup ?? 0) > 0,
          weapon: b.weaponFor(b.viewPlayerId),
          ammo: [...b.ammoFor(b.viewPlayerId)],
          supplies: b.pickups
            .filter((s) => s.kind === 3)
            .map((s) => ({ x: s.x, y: s.y, weapon: s.weapon ?? 1 })),
          reload: Math.max(0, b.viewPlayer.cooldown),
          objective: b.objectiveText,
          objectives: b.objectives.map((o) => ({ ...o })),
          convoy: b.protectsBase ? { x: b.base.x, y: b.base.y } : null,
          route: b.route,
          nav: b.protectsBase
            ? {
                x: b.base.x,
                y: b.base.y,
                label: b.type === 'escort' ? '护送车' : '信标',
              }
            : b.type === 'breakthrough' && b.objectives.some((o) => !o.done)
              ? { ...b.objectives.find((o) => !o.done)!, label: '下一路标' }
              : b.objectives.find(
                    (o) =>
                      !o.done &&
                      (o.kind !== 'exit' ||
                        b.objectives
                          .filter((v) => v.kind === 'intel')
                          .every((v) => v.done)),
                  )
                ? {
                    ...b.objectives
                      .filter(
                        (o) =>
                          !o.done &&
                          (o.kind !== 'exit' ||
                            b.objectives
                              .filter((v) => v.kind === 'intel')
                              .every((v) => v.done)),
                      )
                      .sort(
                        (a, c) =>
                          Math.hypot(a.x - b.viewPlayer.x, a.y - b.viewPlayer.y) -
                          Math.hypot(c.x - b.viewPlayer.x, c.y - b.viewPlayer.y),
                      )[0],
                    label: '任务目标',
                  }
                : b.enemies.length
                  ? {
                      ...b.enemies
                        .slice()
                        .sort(
                          (a, c) =>
                            Math.hypot(a.x - b.viewPlayer.x, a.y - b.viewPlayer.y) -
                            Math.hypot(c.x - b.viewPlayer.x, c.y - b.viewPlayer.y),
                        )[0],
                      label: '敌军',
                    }
                  : null,
          base: b.base.hp,
          notice: b.noticeTime > 0 ? b.notice : '',
          boss: b.boss?.hp ?? 0,
          bossMax: b.boss?.maxHp ?? 0,
          rapid: b.viewPlayer.kit?.rapid ?? b.rapid,
          shield: b.viewPlayer.kit?.shield ?? b.shield,
          wave: b.wave,
          radarEnemies: b.enemies.map((e) => ({
            x: e.x,
            y: e.y,
            boss: e.kind === 3,
          })),
          radarPlayer: { x: b.viewPlayer.x, y: b.viewPlayer.y, angle: b.viewPlayer.angle },
        });
      }
      // The fixed step can finish the battle after the early result guard above.
      const result = b.result as BattleResult | null;
      if (result && !reported) {
        musicCallback.current(result.won ? 'victory' : 'defeat');
        finaleStarted = now;
        clear();
      }
    };
    void preloadRenderer()
      .then(async ({ Renderer3D }) => {
        if (disposed || !surface) return;
        try {
          setLoadProgress({ progress: 8, label: '3D 引擎已装载' });
          // The deployment overlay must paint before WebGL allocates resources.
          await new Promise<void>((resolve) =>
            requestAnimationFrame(() => setTimeout(resolve, 0)),
          );
          if (disposed || errorRef.current) return;
          r = new Renderer3D(surface, b, {
            quality: save.quality,
            mobile,
            onProgress: ({ progress, label }) => {
              if (!disposed && !errorRef.current)
                setLoadProgress({
                  progress: Math.min(99, Math.floor(8 + progress * 0.92)),
                  label,
                });
            },
          });
          renderer.current = r;
          resize = new ResizeObserver(() => {
            r?.resize();
            renderDirty.current = true;
          });
          resize.observe(surface);
          r.resize();
          await r.ready;
          if (disposed || errorRef.current) return;
          // Publish readiness only after a complete frame, then start simulation.
          r.draw(b, controls.current.aim);
          initialized = true;
          previous = performance.now();
          fixed.reset();
          setLoadProgress({ progress: 100, label: '战场已就绪' });
          setLoading(false);
          frame = requestAnimationFrame(loop);
          if (save.sound) {
            a.unlock();
            a.prepareRadio();
            if (b.paused) a.suspend();
          }
        } catch (error) {
          if (!disposed && !errorRef.current) {
            setLoading(false);
            errorRef.current =
              '3D 战场未能初始化。请检查连接或降低画质后重试。';
            resize?.disconnect();
            setLoadError(
              error instanceof Error
                ? '3D 战场未能初始化。请开启浏览器硬件加速，或尝试降低画质后重新进入。'
                : '3D 场景加载失败，请重新进入。',
            );
            cancelAnimationFrame(frame);
            r?.dispose();
            r = null;
            renderer.current = null;
          }
        }
      })
      .catch(() => {
        if (!disposed) {
          setLoading(false);
          errorRef.current = '3D 引擎加载失败，请检查连接后重新进入。';
          setLoadError(errorRef.current);
        }
      });
    return () => {
      disposed = true;
      listeners.forEach((unsubscribe) => unsubscribe());
      cancelAnimationFrame(frame);
      window.removeEventListener('tank-gamepad', onPad);
      window.removeEventListener('tank-gamepad-resume', resume);
      resize?.disconnect();
      window.removeEventListener('keydown', keydown);
      window.removeEventListener('keyup', keyup);
      window.removeEventListener('blur', blur);
      window.removeEventListener('tank-native-state', nativeState);
      window.removeEventListener('tank-native-back', nativeBack);
      window.removeEventListener('pointerup', up);
      window.removeEventListener('pointercancel', up);
      window.removeEventListener('resize', clear);
      document.removeEventListener('visibilitychange', hidden);
      surface?.removeEventListener('wheel', wheel);
      surface?.removeEventListener('webglcontextlost', contextLost);
      document.body.style.overflow = oldOverflow;
      a.dispose();
      r?.dispose();
      renderer.current = null;
      engine.current = null;
      clearInput.current = () => {};
    };
  }, []);
  const toggleMute = () => {
    const enable = !save.sound && !save.music;
    onAudioChange({ sound: enable, music: enable });
    sound.current?.unlock();
  };
  const stick = (e: React.PointerEvent<HTMLDivElement>, aiming = false) => {
    const key = aiming ? 'aim' : 'move';
    if (
      paused ||
      loading ||
      loadError ||
      stickPointers.current[key] !== e.pointerId
    )
      return;
    const r = e.currentTarget.getBoundingClientRect();
    const dx = (e.clientX - r.left - r.width / 2) / (r.width * 0.35);
    const dy = (e.clientY - r.top - r.height / 2) / (r.height * 0.35);
    const magnitude = Math.hypot(dx, dy);
    const len = Math.max(1, magnitude);
    if (aiming) {
      if (magnitude > 0.18) {
        touchAim.current = { x: dx / magnitude, y: dy / magnitude, fire: true };
        aimSource.current = 'touch';
      } else touchAim.current.fire = false;
    } else {
      // Ignore resting-thumb jitter, then smoothly recover the full speed range.
      const speed = Math.min(1, Math.max(0, (magnitude - 0.12) / 0.88));
      touch.current =
        magnitude > 0
          ? { x: (dx / magnitude) * speed, y: (dy / magnitude) * speed }
          : { x: 0, y: 0 };
    }
    e.currentTarget.style.setProperty(
      '--sx',
      `${(dx / len) * r.width * 0.24}px`,
    );
    e.currentTarget.style.setProperty(
      '--sy',
      `${(dy / len) * r.height * 0.24}px`,
    );
  };
  const stickStart = (
    e: React.PointerEvent<HTMLDivElement>,
    aiming = false,
  ) => {
    const key = aiming ? 'aim' : 'move';
    if (paused || loading || loadError || stickPointers.current[key] !== null)
      return;
    stickPointers.current[key] = e.pointerId;
    e.currentTarget.setPointerCapture(e.pointerId);
    sound.current?.unlock();
    stick(e, aiming);
  };
  const stickEnd = (e: React.PointerEvent<HTMLDivElement>, aiming = false) => {
    const key = aiming ? 'aim' : 'move';
    if (stickPointers.current[key] !== e.pointerId) return;
    stickPointers.current[key] = null;
    if (aiming) touchAim.current.fire = false;
    else touch.current = { x: 0, y: 0 };
    e.currentTarget.style.setProperty('--sx', '0px');
    e.currentTarget.style.setProperty('--sy', '0px');
  };
  // One quiet edge message; the aiming area stays free of banners.
  const mobileStatus =
    hud.hp > 0 && hud.hp < hud.max * 0.3
      ? 'ARMOR CRITICAL · 装甲危急'
      : hud.levelUp > 0
        ? `LV.${hud.career.level} · ${hud.career.title}`
        : radioCue?.text || hud.notice || '';
  const bossNearby = hud.radarEnemies.some(
    (enemy) =>
      enemy.boss &&
      Math.hypot(enemy.x - hud.radarPlayer.x, enemy.y - hud.radarPlayer.y) <
        900,
  );
  return (
    <section
      className={'battle-screen ' + (hud.hp < hud.max * 0.3 ? 'critical' : '')}
      aria-label="坦克战场"
      data-radar-open={radarOpen}
    >
      <header className="battle-hud">
        <div className="hud-player">
          <span className="hud-level-badge">
            <small>LV</small>
            {hud.career.level}
          </span>
          <div>
            <strong>
              {CHASSIS[save.chassis].model}「{CHASSIS[save.chassis].name}」
            </strong>
            <div className="health-row">
              <meter
                min={0}
                max={hud.max}
                value={hud.hp}
                aria-label="装甲生命"
              />
              <span>
                {Math.ceil(hud.hp)} / {hud.max}
              </span>
            </div>
          </div>
        </div>

        <div className="hud-mission">
          <span>
            {endless
              ? '无尽战场 / ENDLESS'
              : scenario
                ? `${field.name} / ${operation?.title ?? MISSIONS[mission].name}`
                : `CHAPTER ${String(mission + 1).padStart(2, '0')} / ${MISSIONS[mission].name}`}
          </span>
          <strong>{hud.objective}</strong>
        </div>
        <div className="hud-right">
          {multiplayer && (
            <button onClick={onExit} aria-label="离开联机战斗" title="离开房间">
              <Users size={18} />
            </button>
          )}
          <button
            className="mobile-radar-toggle"
            aria-label={radarOpen ? '收起战术雷达' : '展开战术雷达'}
            aria-expanded={radarOpen}
            aria-controls="battle-tactical-radar"
            onClick={() => {
              setRadarOpen((open) => !open);
              setWeaponRackOpen(false);
            }}
          >
            <Radar size={19} />
          </button>
          <div className="hud-score">
            <strong>{String(hud.score).padStart(5, '0')}</strong>
            <span>{clock(hud.time)}</span>
          </div>
          <button
            aria-label="切换战斗配乐"
            title={`下一首配乐 · ${MUSIC_TRACKS[save.musicTrack].name}（N / 手柄 View）`}
            onClick={() =>
              onAudioChange({
                musicTrack: (save.musicTrack + 1) % MUSIC_TRACKS.length,
              })
            }
          >
            <Music2 size={18} />
          </button>
          <button
            onClick={switchCamera}
            aria-label="切换镜头"
            title={`${cameraMode === 'assault' ? '突击视角' : '战术俯瞰'} · C 切换 · 滚轮缩放`}
          >
            <Camera size={19} />
          </button>
          <button onClick={fullscreen} aria-label="全屏游戏" title="F · 全屏">
            <Maximize size={18} />
          </button>
          <button
            onClick={toggleMute}
            aria-label={
              save.sound || save.music ? '关闭全部声音' : '开启全部声音'
            }
            title="音乐音量可在暂停菜单调节"
          >
            {save.sound || save.music ? (
              <Volume2 size={19} />
            ) : (
              <VolumeX size={19} />
            )}
          </button>
          <button onClick={() => pause(true)} aria-label="暂停游戏" title={multiplayer?.session.role === 'guest' ? '只有房主能暂停全队' : '暂停游戏'}>
            <Pause size={20} />
          </button>
        </div>
      </header>
      <div className="canvas-wrap">
        {multiplayer && (
          <output className="multiplayer-link-status">
            <Wifi size={13} /> 房间 {multiplayer.session.roomCode}
            {connectionNotice && <span> · {connectionNotice}</span>}
          </output>
        )}
        {connectionError && (
          <div className="multiplayer-disconnected" role="alert">
            <strong>联机已中断</strong>
            <p>{connectionError}</p>
            <button onClick={onExit}>返回联机大厅</button>
          </div>
        )}
        {!!mobileStatus && !paused && (
          <output className="combat-status" data-alert={hud.hp < hud.max * 0.3}>
            <Radio size={12} aria-hidden="true" />
            <span>{mobileStatus}</span>
          </output>
        )}
        {(loading || loadError) && (
          <div
            className="engine-loading"
            role="status"
            data-gamepad-menu={loadError ? 'error' : 'loading'}
          >
            {loadError ? <Shield size={35} /> : <Shield size={35} />}
            <strong>{loadError ? '战场连接中断' : '正在部署 3D 战场'}</strong>
            <p>{loadError || loadProgress.label}</p>
            {!loadError && (
              <div className="engine-load-meter">
                <div className="engine-load-status" aria-hidden="true">
                  <span>部署进度</span>
                  <b>{loadProgress.progress}%</b>
                </div>
                <progress
                  className="engine-load-track"
                  aria-label="战场部署进度"
                  value={loadProgress.progress}
                  max={100}
                  aria-valuenow={loadProgress.progress}
                  aria-valuetext={`${loadProgress.progress}% · ${loadProgress.label}`}
                >
                  {loadProgress.progress}%
                </progress>
              </div>
            )}
            <div className="engine-load-actions">
              {loadError && (
                <button className="gold-button" onClick={onRetry}>
                  重新部署
                </button>
              )}
              <button className="outline-button" onClick={onExit}>
                {loadError ? '返回指挥中心' : '取消部署'}
              </button>
            </div>
          </div>
        )}
        <canvas
          ref={canvas}
          aria-label="使用 WASD 或左摇杆移动，鼠标或右摇杆瞄准，RT 开火，1到7选择武器，R或手柄X切换武器，空格冲刺，E 电磁脉冲，Q 支援装备"
          onContextMenu={(e) => e.preventDefault()}
          onPointerMove={(e) => {
            if (
              (e.pointerType === 'touch' &&
                firingPointer.current !== e.pointerId) ||
              (firingPointer.current !== null &&
                firingPointer.current !== e.pointerId)
            )
              return;
            aimSource.current = 'mouse';
            pointerScreen.current = { x: e.clientX, y: e.clientY };
          }}
          onPointerDown={(e) => {
            if (
              e.button !== 0 ||
              paused ||
              loading ||
              loadError ||
              firingPointer.current !== null
            )
              return;
            aimSource.current = 'mouse';
            e.currentTarget.setPointerCapture(e.pointerId);
            firingPointer.current = e.pointerId;
            sound.current?.unlock();
            pointerScreen.current = { x: e.clientX, y: e.clientY };
            mouseFire.current = true;
          }}
          onPointerUp={(e) => {
            if (firingPointer.current === e.pointerId) {
              mouseFire.current = false;
              firingPointer.current = null;
            }
          }}
          onPointerCancel={(e) => {
            if (firingPointer.current === e.pointerId) {
              mouseFire.current = false;
              firingPointer.current = null;
            }
          }}
          onLostPointerCapture={(e) => {
            if (firingPointer.current === e.pointerId) {
              mouseFire.current = false;
              firingPointer.current = null;
            }
          }}
        />
        {hud.bossMax > 0 && (
          <div className="boss-hud" data-nearby={bossNearby}>
            <span>{bossName(mission)}</span>
            <meter
              min={0}
              max={hud.bossMax}
              value={hud.boss}
              aria-label="首领生命"
            />
          </div>
        )}
        <div
          className="tactical-radar"
          id="battle-tactical-radar"
          aria-label="战术雷达：蓝色为我方，橙色为敌军，彩色方块为弹药"
        >
          <div>
            <span>战术雷达</span>
            <small>SECTOR {String(mission + 1).padStart(2, '0')}</small>
          </div>
          <svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label="战场敌我位置">
            <rect
              x="24"
              y="24"
              width={W - 48}
              height={H - 48}
              fill="#17281bbb"
              stroke="#748063"
              strokeWidth="5"
            />
            {engine.current?.walls
              .filter((w) => w.hp > 0)
              .map((w, i) => (
                <rect
                  key={i}
                  x={w.x}
                  y={w.y}
                  width={w.w}
                  height={w.h}
                  fill={
                    w.kind === 'water'
                      ? '#458da5'
                      : w.kind === 'hill'
                        ? '#a5a28b'
                        : w.kind === 'boundary'
                          ? '#e4b766'
                          : w.steel
                            ? '#89917d'
                            : '#52604b'
                  }
                />
              ))}
            <rect
              x={ENEMY_REGION.x}
              y={ENEMY_REGION.y}
              width={ENEMY_REGION.w}
              height={ENEMY_REGION.h}
              fill="#ff755714"
              stroke="#ff7557"
              strokeWidth="6"
              strokeDasharray="24 18"
            >
              <title>敌军增援区域 · 随机部署</title>
            </rect>
            {hud.supplies.map((s, i) => (
              <rect
                key={'ammo-' + i}
                x={s.x - 32}
                y={s.y - 32}
                width="64"
                height="64"
                fill={WEAPONS[s.weapon].color}
                stroke="#fff"
                strokeWidth="8"
              >
                <title>{WEAPONS[s.weapon].name}补给</title>
              </rect>
            ))}
            {hud.mines.map((m) => (
              <path
                key={'mine-' + m.id}
                d={`M${m.x} ${m.y - 30} L${m.x + 30} ${m.y} L${m.x} ${m.y + 30} L${m.x - 30} ${m.y} Z`}
                fill={m.enemy ? '#ff5145' : '#66ddcc'}
                stroke="#101a16"
                strokeWidth="8"
              >
                <title>{m.enemy ? '敌方地雷 · E 脉冲排除' : '我方地雷'}</title>
              </path>
            ))}
            {hud.radarEnemies.map((e, i) => (
              <circle
                key={i}
                cx={e.x}
                cy={e.y}
                r={e.boss ? 42 : 24}
                fill="#ef995d"
              />
            ))}
            {hud.route.length > 0 && (
              <polyline
                points={hud.route.map((p) => `${p.x},${p.y}`).join(' ')}
                fill="none"
                stroke="#82c1bd"
                strokeWidth="10"
                strokeDasharray="24 15"
              />
            )}
            {hud.convoy && (
              <rect
                x={hud.convoy.x - 30}
                y={hud.convoy.y - 30}
                width="60"
                height="60"
                fill="#82c1bd"
              />
            )}
            {hud.objectives.map((o) => (
              <g key={o.id}>
                <circle
                  cx={o.x}
                  cy={o.y}
                  r={o.kind === 'capture' ? 115 : 48}
                  fill={o.done ? '#82c1bd44' : '#f6bf4933'}
                  stroke={
                    o.done ? '#82c1bd' : o.contested ? '#fa6060' : '#ffd064'
                  }
                  strokeWidth="9"
                />
                <text
                  x={o.x}
                  y={o.y + 14}
                  fontSize="45"
                  textAnchor="middle"
                  fill="#fff"
                >
                  {o.kind === 'exit' ? '撤' : o.done ? '✓' : o.id + 1}
                </text>
              </g>
            ))}
            <g
              transform={`translate(${hud.radarPlayer.x} ${hud.radarPlayer.y}) rotate(${(hud.radarPlayer.angle * 180) / Math.PI + 90})`}
            >
              <circle r="38" fill="none" stroke="#b2ead2" strokeWidth="4" />
              <path d="M 0 -28 L 19 23 L 0 12 L -19 23 Z" fill="#b3f0d9" />
            </g>
          </svg>
        </div>
        {hud.nav && (
          <div className="objective-wayfinder">
            <span
              style={{
                transform: `rotate(${(Math.atan2(hud.nav.y - hud.radarPlayer.y, hud.nav.x - hud.radarPlayer.x) * 180) / Math.PI + 90}deg)`,
              }}
            >
              ↑
            </span>
            {hud.nav.label} ·{' '}
            {Math.round(
              Math.hypot(
                hud.nav.x - hud.radarPlayer.x,
                hud.nav.y - hud.radarPlayer.y,
              ),
            )}{' '}
            m
          </div>
        )}
        <div className="battle-abilities">
          <button
            onClick={() => (controls.current.dash = true)}
            disabled={
              paused || loading || !!loadError || hud.hp <= 0 || hud.dash > 0
            }
            title="空格：冲刺"
            aria-label="战术冲刺"
            data-touch-label="冲刺"
          >
            <Wind />
            <span>战术冲刺</span>
            <kbd data-ready={hud.dash <= 0}>
              {hud.dash > 0
                ? hud.dash.toFixed(1) + 's'
                : gamepad
                  ? 'LB'
                  : 'SPACE'}
            </kbd>
          </button>
          <button
            onClick={() => (controls.current.emp = true)}
            disabled={
              paused || loading || !!loadError || hud.hp <= 0 || hud.emp > 0
            }
            title="E：电磁脉冲，排除 300 范围内所有地雷"
            aria-label="脉冲排雷"
            data-touch-label="排雷"
          >
            <Zap />
            <span>脉冲排雷</span>
            <kbd data-ready={hud.emp <= 0}>
              {hud.emp > 0 ? hud.emp.toFixed(1) + 's' : gamepad ? 'RB' : 'E'}
            </kbd>
          </button>
          <button
            onClick={() => {
              controls.current.support = true;
            }}
            disabled={
              paused || loading || !!loadError || hud.hp <= 0 || hud.support > 0
            }
            title="Q：支援装备"
            aria-label={SUPPORTS[save.support].name}
            data-touch-label="支援"
          >
            <Shield />
            <span>{SUPPORTS[save.support].name}</span>
            <kbd data-ready={hud.support <= 0}>
              {hud.support > 0
                ? hud.support.toFixed(1) + 's'
                : gamepad
                  ? 'LT'
                  : 'Q'}
            </kbd>
          </button>
          <button
            className="mine-control"
            data-touch-label="布雷"
            aria-label={`布设地雷，剩余 ${hud.mineAmmo} 枚`}
            onClick={() => {
              controls.current.mine = true;
            }}
            disabled={
              paused ||
              loading ||
              !!loadError ||
              hud.hp <= 0 ||
              hud.mineCd > 0 ||
              hud.mineAmmo <= 0
            }
            title="M / 右摇杆按下：车尾布雷。每击毁 3 辆补充 1 枚，上限 8 枚。"
          >
            <CircleDot size={20} />
            <span>布设地雷</span>
            <b>{hud.mineAmmo}</b>
            <kbd data-ready={hud.mineCd <= 0}>
              {hud.mineCd > 0
                ? hud.mineCd.toFixed(1) + 's'
                : gamepad
                  ? 'R3'
                  : 'M'}
            </kbd>
          </button>
        </div>
        <div className="buffs">
          {hud.rapid > 0 && <span>超频 {Math.ceil(hud.rapid)}s</span>}
          {hud.shield > 1 && <span>护盾 {Math.ceil(hud.shield)}s</span>}
        </div>
        <div
          className="touch-stick"
          aria-label="拖动移动摇杆"
          onPointerDown={(e) => stickStart(e)}
          onPointerMove={(e) => stick(e)}
          onPointerUp={(e) => stickEnd(e)}
          onPointerCancel={(e) => stickEnd(e)}
          onLostPointerCapture={(e) => stickEnd(e)}
        >
          <span />
          <i>移动</i>
        </div>
        <div
          className="touch-stick touch-aim"
          aria-label="拖动右摇杆瞄准并开火"
          onPointerDown={(e) => stickStart(e, true)}
          onPointerMove={(e) => stick(e, true)}
          onPointerUp={(e) => stickEnd(e, true)}
          onPointerCancel={(e) => stickEnd(e, true)}
          onLostPointerCapture={(e) => stickEnd(e, true)}
        >
          <span />
          <i>瞄准 · 开火</i>
        </div>
        <section
          className="weapon-rack"
          aria-label="战斗武器切换"
          data-expanded={weaponRackOpen}
        >
          <button
            type="button"
            className="weapon-rack-toggle"
            aria-label={weaponRackOpen ? '收起武器栏' : '展开武器栏'}
            aria-expanded={weaponRackOpen}
            aria-controls="battle-weapon-slots"
            onClick={() => {
              setWeaponRackOpen((open) => !open);
              setRadarOpen(false);
            }}
          >
            <span>
              {weaponRackOpen
                ? '收起武器'
                : `${WEAPON_LABELS[hud.weapon]} ${hud.weapon === 0 ? '∞' : hud.ammo[hud.weapon]}`}
            </span>
            <small>
              {hud.reload > 0.05 ? `装填 ${hud.reload.toFixed(1)}s` : '换武器'}
            </small>
          </button>
          <div className="weapon-rack-status">
            <strong>{WEAPONS[hud.weapon].name}</strong>
            <small>{WEAPONS[hud.weapon].features}</small>
          </div>
          <div className="weapon-ammo-status">
            <b>
              {hud.weapon === 0 ? '弹药 ∞' : `备弹 ${hud.ammo[hud.weapon]}`}
            </b>
            <span>
              {hud.reload > 0.05 ? `装填 ${hud.reload.toFixed(1)}s` : '就绪'}
            </span>
          </div>
          <div className="weapon-rack-slots" id="battle-weapon-slots">
            {WEAPONS.map((weapon, index) => {
              const Icon = WEAPON_ICONS[index];
              return (
                <button
                  key={weapon.name}
                  type="button"
                  aria-label={`切换到${weapon.name}`}
                  aria-pressed={hud.weapon === index}
                  title={`${index + 1} · ${weapon.name}：${weapon.desc} ${index > 0 ? `备弹 ${hud.ammo[index]}，击毁敌车后拾取补充` : '弹药无限'}`}
                  data-empty={hud.ammo[index] === 0}
                  disabled={paused || loading || !!loadError || hud.hp <= 0}
                  onPointerDown={(event) => {
                    if (event.pointerType === 'mouse') event.preventDefault();
                  }}
                  onClick={() => {
                    controls.current.weapon = index;
                    setWeaponRackOpen(false);
                    sound.current?.unlock();
                  }}
                >
                  <kbd>{index + 1}</kbd>
                  <Icon size={19} />
                  <span>{WEAPON_LABELS[index]}</span>
                  <em>{index === 0 ? '∞' : hud.ammo[index] || '待拾取'}</em>
                </button>
              );
            })}
            <button
              type="button"
              className="cycle-weapon"
              aria-label="切换下一件武器"
              title="R / 手柄 X · 下一件武器"
              disabled={paused || loading || !!loadError || hud.hp <= 0}
              onPointerDown={(event) => event.preventDefault()}
              onClick={() => {
                controls.current.nextWeapon = true;
                sound.current?.unlock();
              }}
            >
              <kbd>{gamepad ? 'X' : 'R'}</kbd>
              <RotateCcw size={18} />
              <span>切换</span>
            </button>
          </div>
        </section>
        <button
          className="touch-fire"
          aria-label="按住自动瞄准开火"
          onPointerDown={(e) => {
            if (
              paused ||
              loading ||
              loadError ||
              firingPointer.current !== null
            )
              return;
            aimSource.current = 'mouse';
            e.currentTarget.setPointerCapture(e.pointerId);
            firingPointer.current = e.pointerId;
            pointerScreen.current = null;
            controls.current.aim = null;
            mouseFire.current = true;
            sound.current?.unlock();
          }}
          onPointerUp={(e) => {
            if (firingPointer.current === e.pointerId) {
              mouseFire.current = false;
              firingPointer.current = null;
            }
          }}
          onPointerCancel={(e) => {
            if (firingPointer.current === e.pointerId) {
              mouseFire.current = false;
              firingPointer.current = null;
            }
          }}
          onLostPointerCapture={(e) => {
            if (firingPointer.current === e.pointerId) {
              mouseFire.current = false;
              firingPointer.current = null;
            }
          }}
        >
          <Crosshair />
          自动瞄准
        </button>
      </div>
      <footer className="battle-footer">
        <span>
          <i />
          3D 战场 · {['新兵', '老兵', '王牌'][save.difficulty]}
        </span>
        <span>
          {gamepad
            ? '左杆移动 · 右杆瞄准 · RT 开火 · X 换武器 · LB 冲刺 · RB 脉冲 · LT 支援'
            : 'WASD 移动 · 鼠标开火 · 1–7 / R 换武器 · 空格冲刺 · E 脉冲 · Q 支援'}
        </span>
        <span>敌军在北侧红色区域分散增援</span>
      </footer>
      <Dialog open={paused} onOpenChange={(v) => pause(v)}>
        <DialogContent className="game-dialog pause-dialog">
          <DialogTitle>战场已暂停</DialogTitle>
          <DialogDescription>
            喘口气，指挥官。所有人都在等你的命令。
          </DialogDescription>
          <div className="mobile-pause-details">
            <strong>{hud.objective}</strong>
            <p>{mobileStatus}</p>
            <span>
              LV.{hud.career.level} · {hud.career.title} · {performanceLabel}
            </span>
            <div className="mobile-pause-tools">
              <button className="outline-button" onClick={fullscreen}>
                <Maximize size={18} />
                全屏
              </button>
              <button className="outline-button" onClick={toggleMute}>
                {save.sound || save.music ? '静音' : '开启声音'}
              </button>
            </div>
          </div>
          <MusicControls settings={save} onChange={onAudioChange} />
          <button className="deploy-button" onClick={() => pause(false)}>
            <Play size={18} />
            继续行动
            <ArrowLeft size={18} />
          </button>
          <button className="outline-button" onClick={onRetry}>
            <RotateCcw size={17} />
            重新挑战
          </button>
          <button className="text-button" onClick={onExit}>
            返回指挥中心
          </button>
        </DialogContent>
      </Dialog>
    </section>
  );
}
