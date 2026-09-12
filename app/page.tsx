'use client';
import { assetUrl } from '@/lib/asset-url';
import battlefieldCover from '../web/assets/iron-embers-cover.png?url';
import { isMobileDevice, deviceState } from '@/lib/performance';
import { useState, useEffect, useRef, useCallback } from 'react';
import {
  Crosshair,
  ArrowUpRight,
  ArrowRight,
  ChevronRight,
  Shield,
  Radio,
  Volume2,
  Settings,
  Lock,
  Flag,
  Swords,
  CircleHelp,
  Layers3,
  Target,
  VolumeX,
  Check,
  Zap,
  Heart,
  RotateCcw,
  Trophy,
  Wind,
  Wrench,
} from 'lucide-react';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import {
  Dialog,
  DialogContent,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog';
import { Switch } from '@/components/ui/switch';
import {
  beginRun,
  creditRunKills,
  settleRun,
  MISSIONS,
  CHASSIS,
  UPGRADES,
  WEAPONS,
  SUPPORTS,
  MODULES,
  ENEMIES,
  loadoutStats,
  defaultSave,
  parseSave,
  SAVE_KEY,
  type Save,
} from '@/lib/campaign';
import type { BattleResult } from '@/lib/engine';
import BattleGame from '@/components/game/battle-game';
import {
  progression,
  killsForLevel,
  MAX_LEVEL,
  EVOLUTIONS,
  growthBonus,
} from '@/lib/progression';
import CareerProgress from '@/components/game/career-progress';
import GamepadController from '@/components/game/gamepad-controller';
import HangarScene from '@/components/game/hangar-scene';
import MusicControls from '@/components/game/music-controls';
import {
  GameMusic,
  type MusicScene,
  type MusicStatus,
  type AudioSettings,
} from '@/lib/music';
const chapters = MISSIONS.map((m) => m.name);
const upgradeIcons = [Shield, Target, RotateCcw, Wind, Zap, Heart];

export default function Home() {
  const [tab, setTab] = useState('campaign');
  const [save, setSaveState] = useState<Save>(defaultSave),
    [ready, setReady] = useState(false),
    [storageOk, setStorageOk] = useState(true),
    [selected, setSelected] = useState(0),
    [dialog, setDialog] = useState<'guide' | 'settings' | null>(null),
    [run, setRun] = useState<{
      mission: number;
      endless: boolean;
      id: string;
    } | null>(null),
    [result, setResult] = useState<(BattleResult & { reward: number }) | null>(
      null,
    );
  const [previewLevel, setPreviewLevel] = useState<number | null>(null);
  const saveRef = useRef(save);
  const music = useRef<GameMusic | null>(null);
  const musicPaused = useRef(false);
  const musicScene = useRef<MusicScene>('menu');
  const [musicStatus, setMusicStatus] = useState<MusicStatus>('locked');
  const setMusicPaused = useCallback((paused: boolean) => {
    musicPaused.current = paused;
    music.current?.setPaused(
      paused ||
        document.hidden ||
        deviceState.background ||
        !document.hasFocus(),
    );
  }, []);
  const setMusicScene = useCallback((scene: MusicScene) => {
    musicScene.current = scene;
    music.current?.setScene(scene);
  }, []);
  const setRadioActive = useCallback((active: boolean) => {
    music.current?.setRadioActive(active);
  }, []);
  function updateAudio(patch: Partial<AudioSettings>) {
    setSave((s) => ({ ...s, ...patch }));
    const next = { ...saveRef.current, ...patch };
    music.current?.setPreferences(
      next.music,
      next.musicVolume,
      next.musicTrack,
    );
    music.current?.unlock();
  }
  function toggleAudio() {
    const enable = !saveRef.current.sound && !saveRef.current.music;
    updateAudio({ sound: enable, music: enable });
  }
  function persistSave(next: Save) {
    try {
      localStorage.setItem(SAVE_KEY, JSON.stringify(next));
      setStorageOk(true);
    } catch {
      setStorageOk(false);
    }
  }
  // Commit outside React state updaters: several kills can arrive within one frame.
  function setSave(action: Save | ((previous: Save) => Save)) {
    const next =
      typeof action === 'function' ? action(saveRef.current) : action;
    if (next === saveRef.current) return;
    saveRef.current = next;
    if (ready) persistSave(next);
    setSaveState(next);
  }
  useEffect(() => {
    try {
      let stored = parseSave(localStorage.getItem(SAVE_KEY));
      if (isMobileDevice() && !stored.mobileConfigured)
        stored = {
          ...stored,
          fps: 30,
          quality: 'performance',
          mobileConfigured: true,
        };
      setSave(stored);
      setSelected(
        MISSIONS.map((_, i) => i).find((i) => !stored.completed.includes(i)) ??
          MISSIONS.length - 1,
      );
    } catch {
      setStorageOk(false);
    }
    setReady(true);
  }, []);
  useEffect(() => {
    if (ready) persistSave(saveRef.current);
  }, [ready]);
  useEffect(() => {
    if (!ready) return;
    const player = new GameMusic(setMusicStatus);
    music.current = player;
    player.setPreferences(
      saveRef.current.music,
      saveRef.current.musicVolume,
      saveRef.current.musicTrack,
    );
    player.setScene(musicScene.current);
    const visibility = () => setMusicPaused(musicPaused.current);
    const unlock = (event: Event) => {
      if (!event.isTrusted) return;
      visibility();
      player.unlock();
    };
    const blur = () => player.setPaused(true);
    visibility();
    window.addEventListener('pointerdown', unlock, true);
    window.addEventListener('keydown', unlock, true);
    window.addEventListener('blur', blur);
    window.addEventListener('focus', visibility);
    window.addEventListener('tank-native-state', visibility);
    document.addEventListener('visibilitychange', visibility);
    return () => {
      window.removeEventListener('pointerdown', unlock, true);
      window.removeEventListener('keydown', unlock, true);
      window.removeEventListener('blur', blur);
      window.removeEventListener('focus', visibility);
      window.removeEventListener('tank-native-state', visibility);
      document.removeEventListener('visibilitychange', visibility);
      player.dispose();
      music.current = null;
    };
  }, [ready, setMusicPaused]);
  useEffect(() => {
    music.current?.setPreferences(
      save.music,
      save.musicVolume,
      save.musicTrack,
    );
  }, [save.music, save.musicVolume, save.musicTrack]);
  useEffect(() => {
    if (run) return;
    // Fullscreen now survives leaving battle; keep the exit shortcut available in menus.
    const keydown = (event: KeyboardEvent) => {
      if (
        event.key.toLowerCase() === 'f' &&
        !event.repeat &&
        document.fullscreenElement
      ) {
        event.preventDefault();
        void document.exitFullscreen?.().catch(() => {});
      }
    };
    window.addEventListener('keydown', keydown);
    return () => window.removeEventListener('keydown', keydown);
  }, [run]);
  useEffect(() => {
    const back = () => {
      if (result) exit();
      else if (!run) setDialog(null);
    };
    window.addEventListener('tank-native-back', back);
    return () => window.removeEventListener('tank-native-back', back);
  }, [run, result]);
  const m = MISSIONS[selected],
    tank = CHASSIS[save.chassis],
    stats = loadoutStats(save),
    career = progression(save.kills),
    preview = progression(killsForLevel(previewLevel ?? career.level)),
    growth = growthBonus(save.kills);
  function start(endless = false, mission = selected) {
    setMusicScene('patrol');
    setMusicPaused(false);
    music.current?.unlock();
    setDialog(null);
    setResult(null);
    const id = crypto.randomUUID();
    setSave((s) => beginRun(s, id));
    setRun({ mission, endless, id });
  }
  function exit() {
    setMusicScene('menu');
    setMusicPaused(false);
    music.current?.unlock();
    setRun(null);
    setResult(null);
  }
  function recordProgress(id: string, kills: number) {
    setSave((s) => creditRunKills(s, id, kills));
  }
  function finish(r: BattleResult) {
    const settled = settleRun(saveRef.current, r);
    if (!settled.accepted) return;
    setMusicScene(r.won ? 'victory' : 'defeat');
    setMusicPaused(false);
    setSave(settled.save);
    setResult({ ...r, reward: settled.reward });
  }
  function upgrade(index: number) {
    setSave((s) =>
      s.points > 0 && s.upgrades[index] < 3
        ? {
            ...s,
            points: s.points - 1,
            upgrades: s.upgrades.map((v, i) => (i === index ? v + 1 : v)),
          }
        : s,
    );
  }
  useEffect(() => {
    const context = (
      document as Document & {
        modelContext?: {
          registerTool: (
            tool: unknown,
            options: { signal: AbortSignal },
          ) => void | Promise<void>;
        };
      }
    ).modelContext;
    if (!context?.registerTool) return;
    const lifecycle = new AbortController();
    const register = (tool: unknown) => {
      try {
        void Promise.resolve(
          context.registerTool(tool, { signal: lifecycle.signal }),
        ).catch(() => {});
      } catch {}
    };
    register({
      name: 'read_campaign_progress',
      description: 'Read device-local tank campaign progress and loadout.',
      inputSchema: {
        type: 'object',
        properties: {},
        additionalProperties: false,
      },
      annotations: { readOnlyHint: true },
      execute: () => ({
        completed: saveRef.current.completed.map((i) => MISSIONS[i].name),
        upgradePoints: saveRef.current.points,
        tankLevel: progression(saveRef.current.kills).level,
        evolution: progression(saveRef.current.kills).evolution.name,
        lifetimeKills: saveRef.current.kills,
        tank: CHASSIS[saveRef.current.chassis].name,
      }),
    });
    register({
      name: 'select_campaign_mission',
      description:
        'Select an unlocked campaign mission and show its briefing. Does not start combat.',
      inputSchema: {
        type: 'object',
        properties: {
          chapter: { type: 'integer', minimum: 1, maximum: MISSIONS.length },
        },
        required: ['chapter'],
        additionalProperties: false,
      },
      annotations: { readOnlyHint: false },
      execute: async (input: unknown) => {
        const n = (input as { chapter?: unknown })?.chapter;
        if (
          typeof n !== 'number' ||
          !Number.isInteger(n) ||
          n < 1 ||
          n > MISSIONS.length
        )
          throw new Error(
            `Chapter must be an integer from 1 to ${MISSIONS.length}.`,
          );
        if (n > 1 && !saveRef.current.completed.includes(n - 2))
          throw new Error('Complete the previous mission first.');
        if (run) throw new Error('Exit the current battle first.');
        setSelected(n - 1);
        setTab('campaign');
        await new Promise<void>((resolve) =>
          requestAnimationFrame(() => requestAnimationFrame(() => resolve())),
        );
        return { chapter: n, title: MISSIONS[n - 1].name };
      },
    });
    return () => lifecycle.abort();
  }, [run]);

  return (
    <main className="command-app dark">
      <header className="topbar">
        <a className="brand" href={assetUrl('/')} aria-label="钢铁余烬首页">
          <span className="brand-mark">
            <Crosshair size={24} />
          </span>
          <span>
            钢铁余烬<small>IRON EMBERS</small>
          </span>
        </a>
        <Tabs value={tab} onValueChange={setTab}>
          <TabsList className="main-tabs" variant="line">
            <TabsTrigger value="campaign">
              <Flag />
              战役行动
            </TabsTrigger>
            <TabsTrigger value="garage">
              <Layers3 />
              装甲车库
            </TabsTrigger>
            <TabsTrigger value="archive">
              <Radio />
              战地档案
            </TabsTrigger>
          </TabsList>
        </Tabs>
        <div className="top-tools">
          <GamepadController
            inBattle={!!run && !result}
            onNextMusic={() =>
              updateAudio({ musicTrack: (saveRef.current.musicTrack + 1) % 3 })
            }
            onBack={() => {
              if (result) exit();
              else if (dialog) setDialog(null);
              else setTab('campaign');
            }}
          />
          <span className="online">
            <i />
            系统就绪
          </span>
          <button
            aria-label={
              save.sound || save.music ? '关闭全部声音' : '开启全部声音'
            }
            title={
              save.sound || save.music ? '关闭音效和音乐' : '开启音效和音乐'
            }
            onClick={toggleAudio}
          >
            {save.sound || save.music ? (
              <Volume2 size={18} />
            ) : (
              <VolumeX size={18} />
            )}
          </button>
          <button aria-label="设置" onClick={() => setDialog('settings')}>
            <Settings size={18} />
          </button>
          <span className="profile">C</span>
        </div>
      </header>
      <div className="command-body">
        <div className="page-heading">
          <div>
            <div className="eyebrow">
              {tab === 'campaign'
                ? 'OPERATIONS / 战役行动'
                : tab === 'garage'
                  ? 'ARMORY / 装甲车库'
                  : 'INTELLIGENCE / 战地档案'}
            </div>
            <h1>
              {tab === 'campaign'
                ? '战役指挥中心'
                : tab === 'garage'
                  ? '整装，再出发'
                  : '来自尘湾的信号'}
              <span>
                {tab === 'campaign'
                  ? 'CAMPAIGN COMMAND'
                  : tab === 'garage'
                    ? 'PREPARE FOR THE NEXT FIGHT'
                    : 'VOICES FROM DUST BAY'}
              </span>
            </h1>
          </div>
          <div className="progress-label">
            <span>战役进度</span>
            <b>
              {String(save.completed.length).padStart(2, '0')}{' '}
              <em>/ {MISSIONS.length}</em>
            </b>
            <div className="progress-segments">
              {chapters.map((n, i) => (
                <i
                  key={n}
                  className={save.completed.includes(i) ? 'done' : ''}
                />
              ))}
            </div>
          </div>
        </div>
        {tab === 'campaign' && (
          <>
            <CareerProgress
              kills={save.kills}
              onOpen={() => {
                setPreviewLevel(null);
                setTab('garage');
              }}
            />
            <section className="mission-layout">
              <div className="keyart">
                <img
                  src={battlefieldCover}
                  alt="工业废墟中披着磨损装甲、驶过破碎路面的主战坦克"
                  fetchPriority="high"
                />
                <div className="keyart-shade" />
                <div className="art-topline">
                  <span>
                    <i />
                    尘湾战区 · 2049
                  </span>
                  <span>33° 42′ N / 117° 09′ E</span>
                </div>
                <div className="hero-title">
                  <div className="chapter-kicker">
                    <span />
                    THE 3D ARMORED WARFARE EXPERIENCE
                  </div>
                  <h2>
                    IRON
                    <br />
                    EMBERS<span>钢 铁 余 烬</span>
                  </h2>
                  <p>
                    当世界化为灰烬，
                    <br />
                    你是最后一道防线。
                  </p>
                </div>
                <div className="art-bottom">
                  <span className="tank-emblem">
                    <Shield size={27} />
                  </span>
                  <div>
                    <small>当前部署 / MAIN BATTLE TANK</small>
                    <strong>
                      {tank.model}「{tank.name}」<span>{tank.role}</span>
                    </strong>
                  </div>
                  <span className="art-badge">
                    READY TO DEPLOY <i />
                  </span>
                </div>
              </div>
              <aside className="briefing">
                <div className="briefing-top">
                  <span>
                    <Radio size={14} />
                    任务简报
                  </span>
                  <span className="live-tag">待命中</span>
                </div>
                <div className="mission-number">
                  {String(selected + 1).padStart(2, '0')}{' '}
                  <span>/ {MISSIONS.length}</span>
                  <small>
                    CHAPTER {String(selected + 1).padStart(2, '0')} · ACT{' '}
                    {Math.floor(selected / 6) + 1}
                  </small>
                </div>
                <h2>{m.name}</h2>
                <div className="mission-location">
                  第 {selected + 1} 章 · {m.location}
                </div>
                <p className="briefing-copy">
                  {m.brief}
                  <span>“{m.quote}”</span>
                </p>
                <div className="objective">
                  <Target size={18} />
                  <div>
                    <small>主要目标</small>
                    <strong>{m.objective} · 击毁本关 Boss</strong>
                  </div>
                </div>
                <div className="mission-meta">
                  <span>
                    任务类型<b>{m.tag}行动</b>
                  </span>
                  <span>
                    战备奖励
                    <b className="orange">
                      {save.completed.includes(selected)
                        ? '已领取 · 可重玩'
                        : '+ 2 升级点'}
                    </b>
                  </span>
                </div>
                <div className="briefing-loadout">
                  {WEAPONS[save.weapon].name} · {SUPPORTS[save.support].name}
                  <button onClick={() => setTab('garage')}>更换装备 →</button>
                </div>
                <div className="difficulty">
                  <span>作战难度</span>
                  <div>
                    {['新兵', '老兵', '王牌'].map((d, i) => (
                      <button
                        key={d}
                        className={save.difficulty === i ? 'selected' : ''}
                        aria-pressed={save.difficulty === i}
                        onClick={() =>
                          setSave((s) => ({ ...s, difficulty: i }))
                        }
                      >
                        {d}
                      </button>
                    ))}
                  </div>
                </div>
                <button
                  className="deploy-button"
                  onClick={() => start(false)}
                  disabled={!ready}
                >
                  <Swords size={19} />
                  开始行动
                  <ArrowRight size={21} />
                </button>
                <button
                  className="training-button"
                  onClick={() => start(true)}
                  disabled={!ready}
                >
                  <Crosshair size={15} />
                  进入无尽战场
                  <ArrowUpRight size={15} />
                </button>
                <div className="save-note">
                  <i />
                  {storageOk
                    ? '进度自动保存在此设备'
                    : '存档不可用，本次进度仅临时保留'}
                </div>
              </aside>
            </section>
            <section className="chapter-section">
              <div className="section-heading">
                <h2>
                  <span />
                  战役路线<small>THE ROAD TO DAWN</small>
                </h2>
                <span>
                  三幕战役 · 18 次行动
                  <ChevronRight size={14} />
                </span>
              </div>
              <div className="campaign-acts">
                <span>Ⅰ 尘湾之夜 · 01—06</span>
                <span>Ⅱ 失联信号 · 07—12</span>
                <span>Ⅲ 回家之路 · 13—18</span>
              </div>
              <div className="chapter-grid">
                {chapters.map((name, i) => (
                  <button
                    key={name}
                    onClick={() => setSelected(i)}
                    disabled={i > 0 && !save.completed.includes(i - 1)}
                    aria-label={`第 ${i + 1} 章 ${name}${i > 0 && !save.completed.includes(i - 1) ? '，需完成前一章' : ''}`}
                    className={
                      'chapter-card ' +
                      (i === selected
                        ? 'active'
                        : i > 0 && !save.completed.includes(i - 1)
                          ? 'locked'
                          : '')
                    }
                  >
                    <div className={'chapter-image scene-' + (i % 6)}>
                      <img src={battlefieldCover} alt="" loading="lazy" />
                      <span className="chapter-index">
                        {String(i + 1).padStart(2, '0')}
                      </span>
                      {save.completed.includes(i) ? (
                        <Check size={14} />
                      ) : i === selected ? (
                        <span className="current-label">当前任务</span>
                      ) : i > 0 && !save.completed.includes(i - 1) ? (
                        <Lock size={14} />
                      ) : null}
                    </div>
                    <div className="chapter-card-info">
                      <strong>{name}</strong>
                      <small>
                        {MISSIONS[i].tag} · {MISSIONS[i].location}
                      </small>
                      {i === selected ? (
                        <ArrowUpRight size={16} />
                      ) : save.completed.includes(i) ? (
                        <Check size={12} />
                      ) : (
                        <Lock size={12} />
                      )}
                    </div>
                  </button>
                ))}
              </div>
            </section>
          </>
        )}
        {tab === 'garage' && (
          <section className="garage-layout">
            <div className="garage-showcase">
              <img src={battlefieldCover} alt="当前装甲底盘展示" />
              <HangarScene
                chassis={save.chassis}
                level={preview.level}
                disabled={!!run}
              />
              <div className="garage-shade" />
              <div className="garage-title">
                <span>
                  {preview.level !== career.level
                    ? '形态预览 · 不改变实战等级'
                    : '当前成长形态'}{' '}
                  / LV.{String(preview.level).padStart(2, '0')}
                </span>
                <h2>{preview.evolution.name}</h2>
                <p>
                  {preview.title} · {tank.name}底盘 · {preview.evolution.detail}
                </p>
              </div>
              <div className="chassis-options">
                {CHASSIS.map((c, i) => (
                  <button
                    key={c.name}
                    className={save.chassis === i ? 'chosen' : ''}
                    aria-pressed={save.chassis === i}
                    onClick={() => setSave((s) => ({ ...s, chassis: i }))}
                  >
                    <Shield size={21} />
                    <strong>{c.name}</strong>
                    <small>{c.role}</small>
                    {save.chassis === i && <Check size={15} />}
                  </button>
                ))}
              </div>
            </div>
            <aside className="garage-stats">
              <div className="section-heading">
                <h2>
                  <span />
                  装甲参数
                </h2>
                <span>当前实战属性 · LV.{career.level}</span>
              </div>
              {['防护', '机动', '火力'].map((n, i) => (
                <div className="stat-line" key={n}>
                  <span>{n}</span>
                  <meter
                    min={0}
                    max={100}
                    value={tank.stats[i]}
                    aria-label={n}
                  />
                  <b>{tank.stats[i]}</b>
                </div>
              ))}
              <div className="spec-values">
                <div>
                  <small>装甲生命</small>
                  <strong>{stats.hp}</strong>
                </div>
                <div>
                  <small>主炮伤害</small>
                  <strong>
                    {Math.round(stats.damage)}
                    {WEAPONS[save.weapon].spread.length > 1
                      ? ` × ${WEAPONS[save.weapon].spread.length}`
                      : ''}
                  </strong>
                </div>
                <div>
                  <small>移动速度</small>
                  <strong>{Math.round(stats.speed)}</strong>
                </div>
                <div>
                  <small>装填时间</small>
                  <strong>
                    {stats.rate.toFixed(2)}
                    <small>秒</small>
                  </strong>
                </div>
              </div>
              <p>
                成长加成：装甲 +{growth.hp}、火力 +
                {Math.round((growth.damage - 1) * 100)}%、装填缩短{' '}
                {Math.round((1 - growth.rate) * 100)}%。等级在所有底盘之间共享。
              </p>
              <button
                className="deploy-button"
                onClick={() => setTab('campaign')}
              >
                <Swords size={18} />
                返回战役部署
                <ArrowRight size={18} />
              </button>
            </aside>
            <section className="career-section">
              <CareerProgress kills={save.kills} />
              <div className="section-heading">
                <h2>
                  <span />
                  30 级装甲进化<small>FROM ROOKIE TO LEGEND</small>
                </h2>
                <span>点击等级，查看对应 3D 形态</span>
              </div>
              <div className="evolution-milestones">
                {EVOLUTIONS.map((e, i) => (
                  <button
                    key={e.level}
                    aria-pressed={preview.stage === i}
                    className={
                      (career.level >= e.level ? 'unlocked ' : '') +
                      (preview.stage === i ? 'selected' : '')
                    }
                    onClick={() => setPreviewLevel(e.level)}
                  >
                    <small>LV.{String(e.level).padStart(2, '0')}</small>
                    <strong>{e.name}</strong>
                    <span>
                      {career.level >= e.level
                        ? '形态已解锁'
                        : `累计击毁 ${killsForLevel(e.level)} 辆`}
                    </span>
                  </button>
                ))}
              </div>
              <div className="rank-ladder">
                {Array.from({ length: MAX_LEVEL }, (_, i) => {
                  const level = i + 1,
                    rank = progression(killsForLevel(level));
                  return (
                    <button
                      key={level}
                      className={
                        (career.level >= level ? 'unlocked ' : '') +
                        (preview.level === level ? 'selected' : '')
                      }
                      aria-label={`等级 ${level}，${rank.title}，累计击毁 ${rank.current} 辆${career.level >= level ? '，已达到' : '，预览'}`}
                      aria-pressed={preview.level === level}
                      onClick={() => setPreviewLevel(level)}
                    >
                      <b>{String(level).padStart(2, '0')}</b>
                      <span>{rank.title}</span>
                      <small>{rank.current} 击毁</small>
                    </button>
                  );
                })}
              </div>
              <div className="rank-preview-note">
                <span>
                  正在预览 LV.{preview.level} · {preview.title}。
                  {preview.level > career.level
                    ? '继续击毁敌军，即可永久获得该等级。'
                    : '该等级已达成。'}
                </span>
                <button onClick={() => setPreviewLevel(null)}>
                  显示当前等级
                </button>
              </div>
              <p className="upgrade-tip">
                每次有效击毁自动累计，战役与无尽模式通用。战斗中达到门槛立即升级和进化；失败、重试或退出都会保留已获得的成长。
              </p>
            </section>
            <section className="loadout-section">
              <div className="section-heading">
                <h2>
                  <span />
                  武器与战术装备<small>LOADOUT</small>
                </h2>
                <span>开局加农炮 · 特殊弹药从敌车掉落中获取</span>
              </div>
              <div className="loadout-current">
                <Crosshair size={18} />
                {WEAPONS[save.weapon].name}
                <span>＋</span>
                {SUPPORTS[save.support].name}
                <span>＋</span>
                {MODULES[save.module].name}
              </div>
              {(
                [
                  {
                    key: 'weapon',
                    label: '首份弹药偏好 · 击毁首辆敌车后掉落',
                    items: WEAPONS,
                  },
                  {
                    key: 'support',
                    label: '主动支援 · Q / LT',
                    items: SUPPORTS,
                  },
                  { key: 'module', label: '被动模块', items: MODULES },
                ] as const
              ).map((group) => (
                <div className="loadout-group" key={group.key}>
                  <h3>{group.label}</h3>
                  <div className="loadout-grid">
                    {group.items.map((item, i) => (
                      <button
                        key={item.name}
                        className={
                          'loadout-card ' +
                          (save[group.key] === i ? 'equipped' : '')
                        }
                        aria-pressed={save[group.key] === i}
                        onClick={() =>
                          setSave((s) => ({ ...s, [group.key]: i }))
                        }
                      >
                        <span>
                          {save[group.key] === i ? (
                            <Check size={18} />
                          ) : (
                            <Crosshair size={18} />
                          )}
                          <strong>{item.name}</strong>
                          {'role' in item && <small>{item.role}</small>}
                        </span>
                        <p>{item.desc}</p>
                      </button>
                    ))}
                  </div>
                </div>
              ))}
            </section>
            <div className="upgrades-section">
              <div className="section-heading">
                <h2>
                  <span />
                  战备升级<small>FIELD ENGINEERING</small>
                </h2>
                <span className="points-label">
                  可用升级点 <b>{save.points}</b>
                </span>
              </div>
              <div className="upgrade-grid">
                {UPGRADES.map((u, i) => {
                  const Icon = upgradeIcons[i];
                  return (
                    <article className="upgrade-card" key={u.name}>
                      <Icon size={22} />
                      <div>
                        <h3>{u.name}</h3>
                        <p>{u.desc}</p>
                        <div className="upgrade-level">
                          {[0, 1, 2].map((v) => (
                            <i
                              key={v}
                              className={save.upgrades[i] > v ? 'filled' : ''}
                            />
                          ))}
                          <span>LV. {save.upgrades[i]} / 3</span>
                        </div>
                      </div>
                      <button
                        onClick={() => upgrade(i)}
                        disabled={!save.points || save.upgrades[i] === 3}
                        aria-label={`升级${u.name}，消耗 1 点`}
                      >
                        {save.upgrades[i] === 3 ? (
                          <Check size={17} />
                        ) : (
                          <>
                            + <span>1 点</span>
                          </>
                        )}
                      </button>
                    </article>
                  );
                })}
              </div>
              <p className="upgrade-tip">
                首次完成每章获得 2 点战备奖励。选择你的战术，打造专属坦克。
              </p>
            </div>
          </section>
        )}
        {tab === 'archive' && (
          <section className="archive-layout">
            <div className="archive-intro">
              <Radio size={28} />
              <span>TRANSMISSION 001 / 2049.10.23</span>
              <h2>
                这里是尘湾。
                <br />
                还有人听得到吗？
              </h2>
              <p>
                停战的第七年，一支自称“军团”的机械部队越过北方边境。尘湾的防线一夜崩塌，地下电台成为这座城市最后的声音。
              </p>
              <p>
                你是修理厂的试车员。你的座驾是一辆没有编号的旧坦克。黎雁是电台那头的人。你们没有援军，只有一条通往黎明的路。
              </p>
              <div className="archive-stats">
                <div>
                  <strong>{save.kills}</strong>
                  <small>累计击毁</small>
                </div>
                <div>
                  <strong>{save.best.toLocaleString()}</strong>
                  <small>最高作战评分</small>
                </div>
                <div>
                  <strong>
                    {save.completed.length} / {MISSIONS.length}
                  </strong>
                  <small>完成章节</small>
                </div>
              </div>
            </div>
            <div className="transmissions">
              {MISSIONS.map((chapter, i) => (
                <article
                  className={save.completed.includes(i) ? 'received' : ''}
                  key={chapter.name}
                >
                  <span className="transmission-index">
                    {String(i + 1).padStart(2, '0')}
                  </span>
                  <div>
                    <h3>
                      {chapter.name}
                      <small>
                        {save.completed.includes(i) ? '已收录' : '信号待解锁'}
                      </small>
                    </h3>
                    <p>
                      {save.completed.includes(i) ? chapter.end : chapter.brief}
                    </p>
                    {save.completed.includes(i) && (
                      <blockquote>“{chapter.quote}”</blockquote>
                    )}
                  </div>
                  {save.completed.includes(i) ? (
                    <Check size={16} />
                  ) : (
                    <Lock size={16} />
                  )}
                </article>
              ))}
            </div>
          </section>
        )}
        <footer className="control-footer">
          <div>
            <span>
              <kbd>W</kbd>
              <kbd>A</kbd>
              <kbd>S</kbd>
              <kbd>D</kbd>移动
            </span>
            <span>
              <Crosshair size={15} />
              鼠标瞄准 · 左键开火
            </span>
            <span>
              <kbd>SPACE</kbd>冲刺
            </span>
            <span>
              <kbd>E</kbd>电磁脉冲
            </span>
            <span>
              <kbd>C</kbd>镜头 · <kbd>F</kbd>全屏
            </span>
            <span>
              <kbd>ESC</kbd>暂停
            </span>
          </div>
          <button onClick={() => setDialog('guide')}>
            <CircleHelp size={15} />
            操作指南
          </button>
        </footer>
      </div>
      {tab === 'archive' && (
        <section className="enemy-codex">
          <div className="section-heading">
            <h2>
              <span />
              敌军识别手册
            </h2>
            <span>9 类单位 · 优先识别支援与远程威胁</span>
          </div>
          <div className="enemy-grid">
            {ENEMIES.map((e, i) => (
              <article key={e.name}>
                <span>{String(i + 1).padStart(2, '0')}</span>
                <h3>{e.name}</h3>
                <p>{e.desc}</p>
              </article>
            ))}
          </div>
        </section>
      )}
      <div className="statusbar">
        <span>
          <i /> 本地作战系统已连接
        </span>
        <span>NO RETREAT. ONLY DAWN. / 3D EDITION</span>
        <span>IRON EMBERS © 2049</span>
      </div>
      <Dialog
        open={dialog !== null}
        onOpenChange={(open) => {
          if (!open) setDialog(null);
        }}
      >
        <DialogContent className="game-dialog">
          <DialogTitle>
            {dialog === 'guide' ? '指挥官操作手册' : '作战设置'}
          </DialogTitle>
          <DialogDescription>
            {dialog === 'guide'
              ? '在真实 3D 战场中保持移动，善用掩体与镜头，不要暴露侧翼。'
              : '设置会保存在当前设备。'}
          </DialogDescription>
          {dialog === 'guide' ? (
            <div className="guide-content">
              <div>
                <kbd>W A S D / 方向键</kbd>
                <span>移动坦克，斜向移动速度相同</span>
              </div>
              <div>
                <kbd>鼠标 / 左键</kbd>
                <span>独立瞄准炮塔，按住连续射击</span>
              </div>
              <div>
                <kbd>1–7 / R / 手柄 X</kbd>
                <span>选择武器 / 循环切换；机枪、制导火箭炮等可随时换用</span>
              </div>
              <div>
                <kbd>SPACE</kbd>
                <span>战术冲刺，短暂无敌；冷却 4 秒</span>
              </div>
              <div>
                <kbd>E</kbd>
                <span>
                  电磁脉冲，瘫痪敌军并安全排除 300 范围内所有地雷；冷却 13 秒
                </span>
              </div>
              <div>
                <kbd>Q</kbd>
                <span>启用车库中装备的维修、护盾或制导火箭</span>
              </div>
              <div>
                <kbd>M / 手柄 R3</kbd>
                <span>
                  车尾布雷，1.2 秒后就绪；初始 6 枚，每击毁 3 辆补充 1 枚
                </span>
              </div>
              <p>
                <b>每关首领</b>：完成原任务并击毁本关 Boss 才能撤出。首领在 70%
                / 35%
                生命时升级攻势并呼叫护卫；红色瞄准线出现时侧移，或用脉冲打断。雷达红色菱形为敌雷，青色为我方地雷。
              </p>
              <div>
                <kbd>C / 滚轮 / F</kbd>
                <span>切换突击与战术镜头 / 缩放 / 全屏</span>
              </div>
              <div>
                <kbd>ESC</kbd>
                <span>暂停 / 继续，切换窗口也会自动暂停</span>
              </div>
              <p>
                <b>坦克成长</b>：每次有效击毁自动累计，从 LV.1 升到
                LV.30；前三级只需累计击毁 3、7
                辆。每级提升装甲、火力、装填和机动，LV.6 / 11 / 16 / 21 / 26 /
                30 发生外观进化。旧战绩自动计入，车库可预览全部形态。
              </p>
              <p>
                <b>标准手柄</b>：左摇杆移动、右摇杆瞄准、RT 开火、LB 冲刺、RB
                电磁脉冲、LT 支援装备、X 切换武器、Y 切换视角、Start
                暂停。方向键或左摇杆选择菜单，A 确认，B 返回。Xbox
                与浏览器识别为标准布局的 PlayStation
                手柄均可使用；连接后先按任意键。
              </p>
              <p>
                <b>任务规则</b>：夺点需在圈内累计驻守 8
                秒，附近有敌军时暂停接管；护送需保持在车队 260 米内，并清除 180
                米内敌军；情报回收后返回绿色撤离点；破坏任务需要炮击金色储能塔。金色雷达标记与方向箭头会引导你。
              </p>
              <p>
                触屏：左摇杆移动，右摇杆拖动瞄准并开火；按住“自动瞄准”可辅助射击。蓝牙或
                USB
                连接鼠标后，左键射击，仍可用左摇杆移动。手机横屏、竖屏均可游玩。
                点底部“换武器”展开并左右滑动选择，点右上角雷达图标查看地图；点“布雷”布雷，点“排雷”清除附近地雷。提示集中在顶部，暂停可查看任务详情。
              </p>
              <p>
                <b>战地贴士</b>{' '}
                砖墙可击碎，钢墙可挡炮。拾取绿色维修、金色装填和蓝色护盾补给。防守关卡需要保护下方的撤离信标。
              </p>
              <button className="deploy-button" onClick={() => setDialog(null)}>
                收到，指挥官
              </button>
            </div>
          ) : (
            <div className="settings-content">
              <MusicControls
                settings={save}
                onChange={updateAudio}
                status={musicStatus}
              />
              <div className="quality-setting">
                <strong>画面质量</strong>
                <p>
                  手机建议使用省电画质。标准增加阴影；电影适合电脑。温控只调整画面，不改变战斗速度。
                </p>
                <div className="quality-options">
                  {(
                    [
                      ['performance', '省电'],
                      ['balanced', '标准'],
                      ['cinematic', '电影'],
                    ] as const
                  ).map(([value, label]) => (
                    <button
                      key={value}
                      className={save.quality === value ? 'selected' : ''}
                      aria-pressed={save.quality === value}
                      onClick={() => setSave((s) => ({ ...s, quality: value }))}
                    >
                      {label}
                    </button>
                  ))}
                </div>
                <small>下次进入战场时生效</small>
              </div>
              <div className="quality-setting">
                <strong>目标帧率</strong>
                <p>
                  手机首次进入默认 30 帧省电；45 帧兼顾流畅，60
                  帧优先响应。发热或开启系统省电时会自动降档。
                </p>
                <div className="quality-options">
                  {([30, 45, 60] as const).map((fps) => (
                    <button
                      key={fps}
                      className={save.fps === fps ? 'selected' : ''}
                      aria-pressed={save.fps === fps}
                      onClick={() => setSave((s) => ({ ...s, fps }))}
                    >
                      {fps} 帧
                    </button>
                  ))}
                </div>
                <small>下次进入战场时生效；暂停、结算和后台停止战场渲染</small>
              </div>
              <label>
                <span>
                  <strong>战斗音效</strong>
                  <small>炮火、爆炸、履带与英文战术播报</small>
                </span>
                <Switch
                  checked={save.sound}
                  onCheckedChange={(sound) => updateAudio({ sound })}
                  aria-label="战斗音效"
                />
              </label>
              <label>
                <span>
                  <strong>屏幕震动</strong>
                  <small>增强命中与爆炸反馈</small>
                </span>
                <Switch
                  checked={save.shake}
                  onCheckedChange={(shake) => setSave((s) => ({ ...s, shake }))}
                  aria-label="屏幕震动"
                />
              </label>
              <p>难度在战役任务卡中选择。新兵受到的伤害更低，适合熟悉操作。</p>
              <p>
                <a
                  href="https://github.com/zcxcn/tankbattle/blob/main/web/audio/combat/README.md"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="underline underline-offset-4"
                >
                  Audio credits · 音效来源与授权
                </a>
              </p>
            </div>
          )}
        </DialogContent>
      </Dialog>
      {run && (
        <BattleGame
          key={run.id}
          mission={run.mission}
          endless={run.endless}
          save={save}
          runId={run.id}
          onProgress={recordProgress}
          onFinish={finish}
          onExit={exit}
          onRetry={() => start(run.endless, run.mission)}
          onMusicScene={setMusicScene}
          onMusicPause={setMusicPaused}
          onRadioActive={setRadioActive}
          onAudioChange={updateAudio}
        />
      )}
      <Dialog
        open={!!result}
        onOpenChange={(open) => {
          if (!open) exit();
        }}
      >
        <DialogContent
          className="game-dialog result-dialog"
          showCloseButton={false}
        >
          <div className="result-emblem">
            {result?.won ? <Trophy size={38} /> : <Shield size={38} />}
          </div>
          <span className="result-kicker">
            {result?.won ? 'MISSION ACCOMPLISHED' : 'END OF OPERATION'}
          </span>
          <DialogTitle>
            {result?.won
              ? result.mission === MISSIONS.length - 1
                ? '黎明，终于到来'
                : '行动成功'
              : result?.endless
                ? '每一次坚持，都有意义'
                : '信号中断，战斗尚未结束'}
          </DialogTitle>
          <DialogDescription>
            {result?.won
              ? MISSIONS[result.mission].end
              : result?.endless
                ? '这一次的记录已经保存。整装待发，下一次走得更远。'
                : '检查装甲配置，利用掩体躲避炮弹。尘湾还在等你，指挥官。'}
          </DialogDescription>
          <div className="result-stats">
            <div>
              <small>作战评分</small>
              <strong>{result?.score.toLocaleString()}</strong>
            </div>
            <div>
              <small>击毁敌军</small>
              <strong>{result?.kills}</strong>
            </div>
            <div>
              <small>作战用时</small>
              <strong>
                {Math.floor(result?.time ?? 0)}
                <em>秒</em>
              </strong>
            </div>
          </div>
          {result && (
            <div className="result-growth">
              <strong>
                {progression(result.totalKills).level >
                progression(result.startingKills).level
                  ? `晋升 LV.${progression(result.startingKills).level} → LV.${progression(result.totalKills).level}`
                  : `坦克等级 LV.${progression(result.totalKills).level}`}{' '}
                · {progression(result.totalKills).title}
              </strong>
              <span>
                本次成长 +{result.kills} 击毁 ·{' '}
                {storageOk
                  ? '已保存，战败也不会丢失'
                  : '当前仅保留在本次会话，设备存档不可用'}
              </span>
            </div>
          )}
          {!!result?.reward && (
            <p className="reward-line">
              <Zap size={16} />
              获得 {result.reward} 点战备升级奖励
            </p>
          )}
          {result?.won && result.mission < MISSIONS.length - 1 ? (
            <button
              className="deploy-button"
              onClick={() => {
                const next = result.mission + 1;
                setSelected(next);
                exit();
                setTab('garage');
              }}
            >
              <Wrench size={18} />
              整备坦克 · 继续战役
              <ArrowRight size={18} />
            </button>
          ) : (
            <button
              className="deploy-button"
              onClick={() => {
                if (result) start(result.endless, result.mission);
              }}
            >
              <RotateCcw size={18} />
              {result?.won ? '再战一次' : '重新挑战'}
              <ArrowRight size={18} />
            </button>
          )}
          <button
            className="text-button"
            onClick={() => {
              if (result?.won && result.mission < MISSIONS.length - 1)
                setSelected(result.mission + 1);
              exit();
            }}
          >
            返回指挥中心
          </button>
        </DialogContent>
      </Dialog>
    </main>
  );
}
