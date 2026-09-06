import { StreetNavigation } from './navigation';
import {
  ARENA_MARGIN,
  boundaryWalls,
  cityLayout,
  enemyEntrances,
  type Road,
  type Structure,
} from './terrain';
import { progression } from './progression';
import {
  MISSIONS,
  WEAPONS,
  SUPPORTS,
  loadoutStats,
  bossName,
  type Save,
} from './campaign';
export const W = 3840,
  H = 2400;
export const ENEMY_GATES = enemyEntrances(W);
export const ENEMY_SPAWN_DISTANCE = 700;
export type Vec = { x: number; y: number };
export type Tank = Vec & {
  id: number;
  angle: number;
  turret: number;
  hp: number;
  maxHp: number;
  radius: number;
  speed: number;
  damage: number;
  rate: number;
  cooldown: number;
  kind: number;
  flash: number;
  stun: number;
  turn: number;
  decision: number;
  spawn: number;
  slow?: number;
  mineReadyAt?: number;
  attackWindup?: number;
};
export type Mine = Vec & {
  id: number;
  enemy: boolean;
  owner: number;
  armedAt: number;
  expiresAt: number;
  damage: number;
};
export type Wall = {
  kind?: Structure['kind'];
  height?: number;
  x: number;
  y: number;
  w: number;
  h: number;
  hp: number;
  maxHp: number;
  steel: boolean;
};
export const muzzleDistance = (radius: number) => radius + 12;
export const muzzleHeight = (radius: number) => radius * 1.06;
export type Bullet = Vec & {
  weapon?: number;
  height?: number;
  splash?: number;
  pierce?: number;
  slow?: number;
  hits?: number[];
  homing?: number;
  salvo?: number;
  vx: number;
  vy: number;
  damage: number;
  enemy: boolean;
  life: number;
};
export type Pickup = Vec & {
  kind: number;
  life: number;
  weapon?: number;
  amount?: number;
};
export const enemyWeapon = (kind: number, phase = 0): number =>
  kind === 3
    ? [0, 4, 6][Math.min(2, phase)]
    : ([0, 1, 4, 0, 2, 3, 0, 5, 6][kind] ?? 0);

export type Particle = Vec & {
  vx: number;
  vy: number;
  life: number;
  max: number;
  size: number;
  color: string;
  smoke: boolean;
};
export type Explosion = Vec & {
  id: number;
  bornAt: number;
  scale: number;
  kind: 'armor' | 'shell' | 'masonry' | 'fuel' | 'impact';
  weapon?: number;
};
export type Input = {
  x: number;
  y: number;
  aim: Vec | null;
  fire: boolean;
  dash: boolean;
  emp: boolean;
  support?: boolean;
  weapon?: number;
  nextWeapon?: boolean;
  mine?: boolean;
};
export type Objective = Vec & {
  id: number;
  kind: 'capture' | 'intel' | 'facility' | 'exit';
  progress: number;
  hp: number;
  maxHp: number;
  done: boolean;
  contested: boolean;
};
export type BattleResult = {
  runId: string;
  startingKills: number;
  totalKills: number;
  won: boolean;
  kills: number;
  score: number;
  time: number;
  mission: number;
  endless: boolean;
  hp: number;
};
export type SoundEvent =
  | 'fire'
  | 'enemyfire'
  | 'explosion'
  | 'hit'
  | 'emp'
  | 'pickup'
  | 'dash'
  | 'levelup';
const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));
const distance = (a: Vec, b: Vec) => Math.hypot(a.x - b.x, a.y - b.y);
export function seeded(seed: number) {
  let t = seed | 0;
  return () => {
    t += 0x6d2b79f5;
    let x = t;
    x = Math.imul(x ^ (x >>> 15), x | 1);
    x ^= x + Math.imul(x ^ (x >>> 7), x | 61);
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
}
export function segmentCircle(
  a: Vec,
  b: Vec,
  c: Vec,
  r: number,
): number | null {
  const dx = b.x - a.x,
    dy = b.y - a.y,
    fx = a.x - c.x,
    fy = a.y - c.y;
  const A = dx * dx + dy * dy;
  if (A === 0) return distance(a, c) < r ? 0 : null;
  const B = 2 * (fx * dx + fy * dy),
    C = fx * fx + fy * fy - r * r,
    D = B * B - 4 * A * C;
  if (C <= 0) return 0;
  if (D < 0) return null;
  const t = (-B - Math.sqrt(D)) / (2 * A);
  return t >= 0 && t <= 1 ? t : null;
}
export function segmentRect(a: Vec, b: Vec, r: Wall): number | null {
  let lo = 0,
    hi = 1;
  for (const [p, d, min, max] of [
    [a.x, b.x - a.x, r.x, r.x + r.w],
    [a.y, b.y - a.y, r.y, r.y + r.h],
  ]) {
    if (Math.abs(d) < 0.00001) {
      if (p < min || p > max) return null;
    } else {
      let x = (min - p) / d,
        y = (max - p) / d;
      if (x > y) [x, y] = [y, x];
      lo = Math.max(lo, x);
      hi = Math.min(hi, y);
      if (lo > hi) return null;
    }
  }
  return lo;
}
export class Battle {
  mission: number;
  endless: boolean;
  save: Save;
  weapon: number;
  ammo = WEAPONS.map((_, i) => (i === 0 ? Infinity : 0));
  private weaponReadyAt = WEAPONS.map(() => 0);
  private pendingReinforcements: number[] = [];
  private reinforcementRetry = 0;
  random: () => number;
  player: Tank;
  enemies: Tank[] = [];
  walls: Wall[] = [];
  roads: Road[] = [];
  bullets: Bullet[] = [];
  particles: Particle[] = [];
  explosions: Explosion[] = [];
  pickups: Pickup[] = [];
  mines: Mine[] = [];
  mineAmmo = 6;
  mineCd = 0;
  bossSpawned = false;
  bossDefeated = false;
  scars: (Vec & { r: number })[] = [];
  tracks: (Vec & { angle: number; life: number })[] = [];
  base = { x: W / 2, y: H - 84, hp: 340, maxHp: 340 };
  objectives: Objective[] = [];
  route: Vec[] = [];
  routeIndex = 1;
  supportCd = 0;
  elapsed = 0;
  kills = 0;
  score = 0;
  spawned = 0;
  wave = 1;
  spawnTimer = 1.5;
  paused = false;
  result: BattleResult | null = null;
  dashCd = 0;
  empCd = 0;
  dashTime = 0;
  shield = 0;
  rapid = 0;
  shake = 0;
  pulse = 0;
  notice = '加农炮弹药无限 · 击毁敌车，拾取特殊弹药';
  noticeTime = 4;
  bossThreshold = 0;
  private navigation = new StreetNavigation(W, H, (x, y, radius) =>
    this.canOccupy(x, y, radius),
  );
  private nextId = 1;
  private nextExplosionId = 1;
  private nextSalvo = 1;
  private hitSalvo = -1;
  private hitSalvoUntil = 0;
  private trackTimer = 0;
  readonly runId: string;
  readonly startingKills: number;
  level: number;
  levelUpTime = 0;
  onProgress?: (kills: number) => void;
  onSound?: (s: SoundEvent, weapon?: number) => void;
  constructor(
    mission: number,
    endless: boolean,
    save: Save,
    seed = 2049,
    runId = '',
  ) {
    this.mission = clamp(Math.floor(mission), 0, MISSIONS.length - 1);
    this.endless = endless;
    this.runId = runId;
    this.startingKills = save.kills;
    this.level = progression(save.kills).level;
    this.save = save;
    this.weapon = 0;
    this.random = seeded(seed);
    const stats = loadoutStats(save, save.kills, 0);
    this.player = {
      id: 0,
      x: W / 2,
      y: H - 185,
      angle: -Math.PI / 2,
      turret: -Math.PI / 2,
      hp: stats.hp,
      maxHp: stats.hp,
      radius: 20,
      speed: stats.speed,
      damage: stats.damage,
      rate: stats.rate,
      cooldown: 0,
      kind: -1,
      flash: 0,
      stun: 0,
      turn: 0,
      decision: 0,
      spawn: 0,
    };
    this.createObjectives();
    this.createArena();
    if (this.isBoss) {
      this.spawnEnemy(3);
      this.notice = `警告：${bossName(this.mission)}已启动 · 注意齐射与增援`;
    } else {
      if (!this.endless) this.spawnEnemy(3);
      this.spawnEnemy(0);
      this.spawnEnemy(0);
    }
  }
  get career() {
    return progression(this.startingKills + this.kills);
  }
  private applyGrowth() {
    const career = this.career;
    if (career.level <= this.level) return;
    this.level = career.level;
    const stats = loadoutStats(
        this.save,
        this.startingKills + this.kills,
        this.weapon,
      ),
      p = this.player;
    if (p.hp > 0)
      p.hp = Math.min(stats.hp, p.hp + Math.max(0, stats.hp - p.maxHp));
    p.maxHp = stats.hp;
    p.damage = stats.damage;
    p.rate = stats.rate;
    p.speed = stats.speed;
    this.levelUpTime = 3.2;
    this.notice = `晋升 LV.${career.level} · ${career.title} · ${career.evolution.name}`;
    this.noticeTime = 3.2;
    this.burst(p.x, p.y, 35, 100, career.evolution.accent);
    this.onSound?.('levelup');
  }
  get isDefend() {
    return !this.endless && MISSIONS[this.mission].type === 'defend';
  }
  get isBoss() {
    return !this.endless && MISSIONS[this.mission].type === 'boss';
  }
  get target() {
    return MISSIONS[this.mission].count;
  }
  get boss() {
    return this.enemies.find((e) => e.kind === 3 && e.hp > 0);
  }
  get type() {
    return this.endless ? 'endless' : MISSIONS[this.mission].type;
  }
  get protectsBase() {
    return this.isDefend || this.type === 'escort';
  }
  get fieldMission() {
    return ['capture', 'escort', 'extract', 'sabotage'].includes(this.type);
  }
  get objectiveText() {
    return (
      this.primaryObjectiveText +
      (this.endless
        ? ''
        : this.bossDefeated
          ? ' · Boss 已击毁'
          : ' · 击毁本关 Boss')
    );
  }
  get primaryObjectiveText() {
    const done = this.objectives.filter(
      (o) => o.kind !== 'exit' && o.done,
    ).length;
    if (this.endless) return `第 ${this.wave} 波 · 已击毁 ${this.kills} 辆`;
    if (this.type === 'capture') {
      const active = this.objectives.find(
        (o) => !o.done && distance(o, this.player) < 115,
      );
      return `中继站 ${done}/3${active ? (active.contested ? ' · 敌军争夺中' : ` · 接管 ${Math.floor((active.progress / 8) * 100)}%`) : ' · 进入金色圆圈驻守'}`;
    }
    if (this.type === 'escort')
      return `护送路标 ${Math.min(this.routeIndex, this.route.length)}/${this.route.length} · 车体 ${Math.ceil((this.base.hp / this.base.maxHp) * 100)}% · ${distance(this.base, this.player) > 260 ? '靠近运输车' : '清除车队周围敌军'}`;
    if (this.type === 'extract')
      return done < 3
        ? `情报 ${done}/3 · 驶近金色标记回收`
        : '情报齐备 · 返回南侧绿色撤离点';
    if (this.type === 'sabotage') return `设施 ${done}/3 · 炮击金色储能塔`;
    if (this.isDefend)
      return `守护信标 ${Math.max(0, Math.ceil(MISSIONS[this.mission].duration - this.elapsed))} 秒 · 完整度 ${Math.ceil((this.base.hp / this.base.maxHp) * 100)}%`;
    if (this.isBoss) return `击毁「${bossName(this.mission)}」· 注意增援`;
    return `清除敌军 ${Math.min(this.target, this.spawned - this.enemies.filter((e) => e.hp > 0 && e.kind !== 3).length)}/${this.target}`;
  }
  createObjectives() {
    if (this.endless) return;
    const type = this.type;
    if (type === 'escort') {
      this.route = [
        { x: W / 2, y: H - 250 },
        { x: W / 2, y: H * 0.64 },
        { x: W * 0.78, y: H * 0.64 },
        { x: W * 0.78, y: 300 },
        { x: W / 2, y: 300 },
        { x: W / 2, y: 180 },
      ];
      Object.assign(this.base, this.route[0], { hp: 560, maxHp: 560 });
    }
    if (['capture', 'extract', 'sabotage'].includes(type)) {
      this.objectives = [
        { x: W * 0.22, y: H * 0.3 },
        { x: W * 0.5, y: H * 0.18 },
        { x: W * 0.78, y: H * 0.4 },
      ].map((v, i) => ({
        ...v,
        id: i,
        kind:
          type === 'capture'
            ? 'capture'
            : type === 'extract'
              ? 'intel'
              : 'facility',
        progress: 0,
        hp: 260,
        maxHp: 260,
        done: false,
        contested: false,
      }));
      if (type === 'extract')
        this.objectives.push({
          id: 3,
          kind: 'exit',
          x: W / 2,
          y: H - 120,
          progress: 0,
          hp: 1,
          maxHp: 1,
          done: false,
          contested: false,
        });
    }
  }
  updateObjectives(dt: number) {
    const p = this.player;
    for (const o of this.objectives) {
      if (o.done) continue;
      o.contested = this.enemies.some(
        (e) => e.hp > 0 && e.spawn <= 0 && distance(e, o) < 150,
      );
      if (o.kind === 'capture' && distance(p, o) < 115 && !o.contested) {
        o.progress = Math.min(8, o.progress + dt);
        if (o.progress >= 8) {
          o.done = true;
          this.score += 350;
          this.onSound?.('pickup');
        }
      }
      if (o.kind === 'intel' && distance(p, o) < 65) {
        o.done = true;
        this.score += 250;
        this.onSound?.('pickup');
      }
      if (
        o.kind === 'exit' &&
        this.objectives
          .filter((v) => v.kind === 'intel')
          .every((v) => v.done) &&
        distance(p, o) < 100
      )
        o.done = true;
      if (o.kind === 'facility' && o.hp <= 0) {
        o.done = true;
        this.score += 400;
        this.burst(o.x, o.y, 65, 180);
        this.explode(o.x, o.y, 1.8, 'fuel');
        this.onSound?.('explosion');
      }
    }
    if (
      this.type === 'escort' &&
      this.routeIndex < this.route.length &&
      distance(p, this.base) < 260 &&
      !this.enemies.some((e) => e.hp > 0 && distance(e, this.base) < 180)
    ) {
      const next = this.route[this.routeIndex],
        d = distance(this.base, next),
        travel = Math.min(d, 78 * dt);
      if (d > 0) {
        this.base.x += ((next.x - this.base.x) / d) * travel;
        this.base.y += ((next.y - this.base.y) / d) * travel;
      }
      if (d <= travel) this.routeIndex++;
    }
  }
  useSupport() {
    if (this.paused || this.result || this.supportCd > 0 || this.player.hp <= 0)
      return;
    const support = SUPPORTS[this.save.support],
      p = this.player;
    this.supportCd = support.cooldown;
    if (this.save.support === 0) p.hp = Math.min(p.maxHp, p.hp + 65);
    if (this.save.support === 1) this.shield = Math.max(this.shield, 4);
    if (this.save.support === 2) {
      if (this.ammo[6] <= 0) {
        this.supportCd = 0;
        this.notice = '火箭弹药不足 · 击毁敌车拾取火箭补给';
        this.noticeTime = 2;
        return;
      }
      const targets = this.enemies
        .filter(
          (e) =>
            e.hp > 0 &&
            e.spawn <= 0 &&
            distance(e, p) < 950 &&
            !this.walls.some((w) => w.hp > 0 && segmentRect(p, e, w) !== null),
        )
        .sort((a, b) => distance(a, p) - distance(b, p))
        .slice(0, Math.min(3, this.ammo[6]));
      if (!targets.length) {
        this.supportCd = 0;
        this.notice = '火箭待命 · 950 米内没有可直视的目标';
        this.noticeTime = 2;
        return;
      }
      this.ammo[6] -= targets.length;
      if (this.weapon === 6 && this.ammo[6] === 0) this.selectWeapon(0);
      this.onSound?.('fire', 6);
      for (const e of targets) {
        const a = Math.atan2(e.y - p.y, e.x - p.x);
        this.bullets.push({
          x: p.x + Math.cos(a) * 32,
          y: p.y + Math.sin(a) * 32,
          vx: Math.cos(a) * 560,
          vy: Math.sin(a) * 560,
          damage: 85,
          enemy: false,
          life: 3.5,
          splash: 70,
          homing: e.id,
          weapon: 6,
          height: muzzleHeight(p.radius),
        });
      }
    }
    this.burst(p.x, p.y, 20, 55, '#82eac4');
    this.notice = support.name + ' · 已启动';
    this.noticeTime = 2;
    this.onSound?.('pickup');
  }
  createArena() {
    const city = cityLayout(this.mission, W, H);
    this.roads = city.roads;
    this.walls = city.structures;
    // Keep deployments, objectives and the convoy corridor reachable.
    const clear = [
      this.player,
      this.base,
      { x: W / 2, y: 200 },
      ...this.objectives,
    ];
    this.walls = this.walls.filter(
      (w) =>
        !clear.some(
          (v) =>
            Math.hypot(
              v.x - clamp(v.x, w.x, w.x + w.w),
              v.y - clamp(v.y, w.y, w.y + w.h),
            ) < 145,
        ) &&
        !this.route.slice(1).some(
          (v, i) =>
            segmentRect(this.route[i], v, {
              ...w,
              x: w.x - 80,
              y: w.y - 80,
              w: w.w + 160,
              h: w.h + 160,
            }) !== null,
        ),
    );
    // Perimeter collision is permanent, including beside the protected south base.
    this.walls.push(...boundaryWalls(W, H));
  }
  spawnEnemy(kind?: number) {
    if (
      !this.endless &&
      !this.isBoss &&
      !this.fieldMission &&
      this.spawned >= this.target &&
      kind !== 3 &&
      !this.pendingReinforcements.length
    )
      return false;
    const roster = this.endless
      ? [0, 1, 2, 4, 5, 6, 7, 8]
      : this.mission < 2
        ? [0, 0, 1]
        : this.mission < 4
          ? [0, 1, 2]
          : this.mission < 6
            ? [0, 1, 2, 4]
            : [0, 1, 2, 4, 5, 6, 7, 8];
    const k = kind ?? roster[Math.floor(this.random() * roster.length)];
    const data = [
      [65, 75, 16, 1.9, 19],
      [38, 123, 3.5, 0.36, 17],
      [120, 49, 28, 2.6, 23],
      [820, 36, 25, 2.05, 45],
      [165, 58, 20, 1.7, 24],
      [62, 65, 40, 3.6, 18],
      [38, 160, 58, 99, 16],
      [95, 72, 10, 2.7, 20],
      [90, 55, 17, 3.2, 22],
    ][k];
    let x = 0,
      y = 0,
      valid = false;
    const first = k === 3 ? 1 : Math.floor(this.random() * ENEMY_GATES.length);
    const offsets = [
      [0, 0],
      [-14, 65],
      [14, 130],
      [0, 195],
    ];
    for (let i = 0; i < ENEMY_GATES.length * offsets.length; i++) {
      const gate =
        ENEMY_GATES[
          (first + Math.floor(i / offsets.length)) % ENEMY_GATES.length
        ];
      const offset = offsets[i % offsets.length];
      x = gate.x + offset[0];
      y = gate.y + offset[1];
      if (
        this.canOccupy(x, y, data[4]) &&
        distance({ x, y }, this.player) >= ENEMY_SPAWN_DISTANCE &&
        (!this.protectsBase || distance({ x, y }, this.base) > data[4] + 40) &&
        this.enemies.every(
          (e) => distance({ x, y }, e) > e.radius + data[4] + 10,
        )
      ) {
        valid = true;
        break;
      }
    }
    if (!valid) return false;
    const mult =
      [0.8, 1, 1.2][this.save.difficulty] *
      (k === 3 ? 1 : 1.12 + this.mission * 0.025);
    const health =
      k === 3
        ? this.isBoss
          ? 1150 + this.mission * 65
          : 470 + this.mission * 58
        : data[0];
    this.enemies.push({
      id: this.nextId++,
      x,
      y,
      angle: Math.PI / 2,
      turret: Math.PI / 2,
      hp: health * mult,
      maxHp: health * mult,
      speed:
        data[1] *
        (this.endless
          ? Math.min(1.5, 1 + this.wave * 0.025)
          : k === 3
            ? 1.65
            : 1.13),
      damage:
        data[2] *
        [0.65, 1, 1.25][this.save.difficulty] *
        (1.12 + this.mission * 0.014),
      rate: data[3] / ([0.85, 1, 1.14][this.save.difficulty] * 1.14),
      radius: data[4],
      kind: k,
      cooldown: 1.8 + this.random(),
      flash: 0,
      stun: 0,
      turn: this.random() > 0.5 ? 1 : -1,
      decision: 1,
      spawn: 1.2,
      mineReadyAt: this.elapsed + (k === 3 ? 6 : 8 + this.random() * 7),
    });
    if (k === 3) this.bossSpawned = true;
    if (k !== 3) this.spawned++;
    return true;
  }
  canOccupy(x: number, y: number, r: number) {
    return (
      x >= r + ARENA_MARGIN &&
      x <= W - r - ARENA_MARGIN &&
      y >= r + ARENA_MARGIN &&
      y <= H - r - ARENA_MARGIN &&
      !this.objectives.some(
        (o) =>
          o.kind === 'facility' &&
          !o.done &&
          o.hp > 0 &&
          Math.hypot(x - o.x, y - o.y) < r + 36,
      ) &&
      !this.walls.some(
        (w) =>
          w.hp > 0 &&
          Math.hypot(
            x - clamp(x, w.x, w.x + w.w),
            y - clamp(y, w.y, w.y + w.h),
          ) < r,
      )
    );
  }
  move(t: Tank, dx: number, dy: number) {
    const ox = t.x,
      oy = t.y;
    const steps = Math.max(1, Math.ceil(Math.hypot(dx, dy) / 8));
    for (let i = 0; i < steps; i++) {
      if (this.canOccupy(t.x + dx / steps, t.y, t.radius)) t.x += dx / steps;
      if (this.canOccupy(t.x, t.y + dy / steps, t.radius)) t.y += dy / steps;
    }
    return Math.hypot(t.x - ox, t.y - oy);
  }
  burst(
    x: number,
    y: number,
    count: number,
    power: number,
    color = '#ffa64c',
    smoke = false,
  ) {
    for (let i = 0; i < count; i++) {
      const a = this.random() * Math.PI * 2,
        s = (0.15 + this.random()) * power,
        life = smoke ? 0.6 + this.random() * 1.1 : 0.18 + this.random() * 0.6;
      this.particles.push({
        x,
        y,
        vx: Math.cos(a) * s,
        vy: Math.sin(a) * s,
        life,
        max: life,
        size: smoke ? 10 + this.random() * 20 : 1 + this.random() * 4,
        color,
        smoke,
      });
    }
    if (this.particles.length > 650)
      this.particles.splice(0, this.particles.length - 650);
  }
  /** Visual descriptors never consume combat randomness or apply extra damage. */
  explode(x: number, y: number, scale = 1, kind: Explosion['kind'] = 'armor') {
    this.explosions.push({
      id: this.nextExplosionId++,
      x,
      y,
      bornAt: this.elapsed,
      scale: clamp(scale, 0.35, 2.8),
      kind,
    });
    if (this.explosions.length > 32) this.explosions.shift();
  }
  selectWeapon(index: number) {
    if (
      this.paused ||
      this.result ||
      this.player.hp <= 0 ||
      !Number.isInteger(index) ||
      index < 0 ||
      index >= WEAPONS.length ||
      index === this.weapon
    )
      return false;
    if (this.ammo[index] <= 0) {
      this.notice = WEAPONS[index].name + ' · 弹药不足，击毁敌车拾取补给';
      this.noticeTime = 2;
      return false;
    }
    this.weapon = index;
    const stats = loadoutStats(
      this.save,
      this.startingKills + this.kills,
      index,
    );
    this.player.damage = stats.damage;
    this.player.rate = stats.rate;
    this.player.cooldown = Math.max(
      0.25,
      this.weaponReadyAt[index] - this.elapsed,
    );
    this.notice = WEAPONS[index].name + ' · ' + WEAPONS[index].role;
    this.noticeTime = 1.4;
    return true;
  }
  shoot(t: Tank, enemy: boolean) {
    if (this.paused || this.result || t.hp <= 0 || t.spawn > 0) return;
    const index = enemy
      ? enemyWeapon(
          t.kind,
          t.hp / t.maxHp <= 0.35 ? 2 : t.hp / t.maxHp <= 0.7 ? 1 : 0,
        )
      : this.weapon;
    const weapon = WEAPONS[index];
    if (!enemy && this.ammo[index] <= 0) {
      this.selectWeapon(0);
      return;
    }
    const rocketTarget =
      !enemy && index === 6 ? this.rocketTarget(t, t.turret) : undefined;
    const speed = enemy
      ? index === 3
        ? 760
        : index === 1
          ? 470
          : index === 6
            ? 270
            : 330
      : (620 + this.save.upgrades[4] * 90) * weapon.speed;
    const angles: readonly number[] =
      enemy && t.kind === 3
        ? this.mission >= 12
          ? [-0.32, -0.16, 0, 0.16, 0.32]
          : [-0.24, 0, 0.24]
        : enemy && t.kind === 8
          ? [-0.18, 0, 0.18]
          : weapon.spread;
    const salvo = enemy && index === 2 ? this.nextSalvo++ : undefined;
    for (const offset of angles) {
      const a = t.turret + offset;
      this.bullets.push({
        x: t.x + Math.cos(a) * muzzleDistance(t.radius),
        y: t.y + Math.sin(a) * muzzleDistance(t.radius),
        vx: Math.cos(a) * speed,
        vy: Math.sin(a) * speed,
        damage: t.damage * (enemy && index === 2 ? 0.4 : 1),
        weapon: index,
        enemy,
        height: muzzleHeight(t.radius),
        life: index === 2 ? 0.85 : index === 6 ? 5 : 3.5,
        splash: enemy
          ? index === 4
            ? 85
            : index === 6
              ? 70
              : 0
          : weapon.splash,
        pierce: enemy ? 0 : weapon.pierce,
        slow: enemy ? (index === 5 ? 1.2 : 0) : weapon.slow,
        hits: [],
        homing: rocketTarget?.id,
        salvo,
      });
    }
    t.cooldown =
      t.rate *
      (t.kind === 3 && t.hp < t.maxHp / 2 ? 0.7 : 1) *
      (!enemy && this.rapid > 0 ? 0.5 : 1);
    t.flash = 0.14;
    if (!enemy) this.weaponReadyAt[index] = this.elapsed + t.cooldown;
    this.burst(
      t.x + Math.cos(t.turret) * (t.radius + 16),
      t.y + Math.sin(t.turret) * (t.radius + 16),
      index === 1 ? 3 : 6,
      60,
      weapon.color,
    );
    this.onSound?.(enemy ? 'enemyfire' : 'fire', index);
    if (!enemy) {
      this.shake = Math.max(
        this.shake,
        index === 1 ? 0.5 : index === 3 || index === 6 ? 3 : 2,
      );
      if (index > 0 && --this.ammo[index] === 0) {
        this.selectWeapon(0);
        this.notice = weapon.name + ' 弹药耗尽 · 已切回加农炮';
        this.noticeTime = 2.5;
      }
    }
  }
  private rocketTarget(origin: Vec, angle: number) {
    return this.enemies
      .filter((e) => {
        const d = distance(origin, e);
        return (
          e.hp > 0 &&
          e.spawn <= 0 &&
          d > 0 &&
          d < 1100 &&
          ((e.x - origin.x) * Math.cos(angle) +
            (e.y - origin.y) * Math.sin(angle)) /
            d >
            0.65 &&
          !this.walls.some(
            (w) => w.hp > 0 && segmentRect(origin, e, w) !== null,
          )
        );
      })
      .sort((a, b) => distance(origin, a) - distance(origin, b))[0];
  }
  private playerHit(damage: number, bullet?: Bullet) {
    const sameSalvo =
      bullet?.salvo !== undefined &&
      bullet.salvo === this.hitSalvo &&
      this.elapsed <= this.hitSalvoUntil &&
      this.shield <= 0.22;
    if ((this.shield > 0 && !sameSalvo) || this.player.hp <= 0) return;
    if (!sameSalvo) {
      this.hitSalvo = bullet?.salvo ?? -1;
      this.hitSalvoUntil = this.elapsed + 0.08;
    }
    const p = this.player;
    p.hp = Math.max(0, p.hp - damage);
    p.slow = Math.max(p.slow ?? 0, bullet?.slow ?? 0);
    this.shield = 0.22;
    this.shake = Math.max(this.shake, 8);
    this.impact(bullet?.x ?? p.x, bullet?.y ?? p.y, bullet?.weapon ?? 0, 0.65);
    if (!sameSalvo) this.onSound?.('hit', bullet?.weapon ?? 0);
  }
  private impact(x: number, y: number, weapon: number, scale = 0.45) {
    this.explode(x, y, scale, 'impact');
    this.explosions[this.explosions.length - 1].weapon = weapon;
    this.burst(
      x,
      y,
      weapon === 1 ? 4 : 10,
      95,
      WEAPONS[weapon]?.color ?? '#ffcc75',
    );
  }
  hitEnemy(t: Tank, damage: number) {
    if (t.hp <= 0) return;
    t.hp = Math.max(0, t.hp - damage);
    t.flash = 0.09;
    if (t.hp === 0) {
      if (t.kind === 3) this.bossDefeated = true;
      this.kills++;
      if (this.kills % 3 === 0) this.mineAmmo = Math.min(8, this.mineAmmo + 1);
      this.applyGrowth();
      this.onProgress?.(this.kills);
      this.score +=
        t.kind === 3 ? 1500 : t.kind === 2 || t.kind === 4 ? 180 : 100;
      if (this.player.hp > 0)
        this.player.hp = Math.min(
          this.player.maxHp,
          this.player.hp +
            this.save.upgrades[5] * 4 +
            (this.save.module === 3 ? 3 : 0),
        );
      this.burst(t.x, t.y, t.kind === 3 ? 90 : 40, 180, '#ffae51');
      this.burst(t.x, t.y, 16, 40, '#4d4b43', true);
      this.explode(t.x, t.y, t.kind === 3 ? 2.3 : t.radius / 20);
      this.scars.push({ x: t.x, y: t.y, r: t.radius * 1.7 });
      this.shake = t.kind === 3 ? 18 : 8;
      this.onSound?.('explosion');
      const preferred = this.kills === 1 ? this.save.weapon : 0;
      const profile = enemyWeapon(t.kind);
      const weapon =
        preferred > 0
          ? preferred
          : profile > 0
            ? profile
            : 1 + ((this.kills - 1) % 6);
      this.pickups.push({
        x: t.x,
        y: t.y,
        kind: 3,
        weapon,
        amount: WEAPONS[weapon].supply,
        life: 65,
      });
      if (this.random() < 0.38 || this.kills % 3 === 0)
        this.pickups.push({
          x: t.x + 36,
          y: t.y,
          kind:
            this.player.hp < this.player.maxHp * 0.5
              ? 0
              : Math.floor(this.random() * 3),
          life: 18,
        });
      this.pickups = this.pickups.slice(-48);
      if (this.scars.length > 55) this.scars.shift();
    }
  }
  /** Mines are friendly-safe, arm visibly, and never appear inside scenery. */
  layMine(tank = this.player, enemy = false) {
    if (this.paused || this.result || tank.hp <= 0 || tank.spawn > 0)
      return false;
    if (!enemy && (this.mineAmmo <= 0 || this.mineCd > 0)) return false;
    if (
      this.mines.length >= 32 ||
      this.mines.filter((m) => m.owner === tank.id).length >= 8
    )
      return false;
    const x = tank.x - Math.cos(tank.angle) * (tank.radius + 22);
    const y = tank.y - Math.sin(tank.angle) * (tank.radius + 22);
    if (
      !this.canOccupy(x, y, 12) ||
      this.mines.some((m) => distance(m, { x, y }) < 34)
    )
      return false;
    this.mines.push({
      id: this.nextId++,
      x,
      y,
      enemy,
      owner: tank.id,
      armedAt: this.elapsed + 1.2,
      expiresAt: this.elapsed + 90,
      damage: enemy ? (tank.kind === 3 ? 105 : 75) : 220 + this.level * 3,
    });
    if (!enemy) {
      this.mineAmmo--;
      this.mineCd = 2;
      this.notice = '地雷已布设 · 1.2 秒后就绪 · 每击毁 3 辆补充 1 枚';
      this.noticeTime = 3;
      this.onSound?.('pickup');
    }
    return true;
  }
  private updateMines(previous: Map<number, Vec>) {
    const survivors: Mine[] = [];
    for (const mine of this.mines) {
      if (mine.expiresAt <= this.elapsed) continue;
      const targets = mine.enemy
        ? [
            this.player,
            ...(this.protectsBase
              ? [{ ...this.base, id: -2, radius: 30, spawn: 0 }]
              : []),
          ]
        : this.enemies;
      const triggered =
        this.elapsed >= mine.armedAt &&
        targets.some(
          (t) =>
            t.hp > 0 &&
            t.spawn <= 0 &&
            segmentCircle(previous.get(t.id) ?? t, t, mine, t.radius + 18) !==
              null &&
            !this.walls.some(
              (w) => w.hp > 0 && segmentRect(mine, t, w) !== null,
            ),
        );
      if (!triggered) {
        survivors.push(mine);
        continue;
      }
      this.explode(mine.x, mine.y, 1.3, 'shell');
      this.burst(mine.x, mine.y, 30, 145);
      this.scars.push({ x: mine.x, y: mine.y, r: 24 });
      this.onSound?.('explosion');
      const exposed = (t: Vec) =>
        distance(t, mine) < 125 &&
        !this.walls.some((w) => w.hp > 0 && segmentRect(mine, t, w) !== null);
      if (mine.enemy) {
        if (exposed(this.player)) this.playerHit(mine.damage);
        if (this.protectsBase && exposed(this.base))
          this.base.hp = Math.max(0, this.base.hp - mine.damage);
      } else
        for (const e of this.enemies) {
          if (e.hp > 0 && e.spawn <= 0 && exposed(e)) {
            this.hitEnemy(e, mine.damage);
            e.stun = Math.max(e.stun, 1.1);
          }
        }
    }
    this.mines = survivors;
    this.scars = this.scars.slice(-55);
  }
  step(rawDt: number, input: Input) {
    if (this.paused || this.result) return;
    const previousPositions = new Map<number, Vec>(
      [this.player, ...this.enemies].map((t) => [t.id, { x: t.x, y: t.y }]),
    );
    previousPositions.set(-2, { x: this.base.x, y: this.base.y });
    const dt = Math.min(0.05, Math.max(0, rawDt));
    this.elapsed += dt;
    this.explosions = this.explosions.filter(
      (e) => this.elapsed - e.bornAt < 5.5,
    );
    this.levelUpTime = Math.max(0, this.levelUpTime - dt);
    this.spawnTimer -= dt;
    this.reinforcementRetry -= dt;
    this.noticeTime = Math.max(0, this.noticeTime - dt);
    this.dashCd = Math.max(0, this.dashCd - dt);
    this.empCd = Math.max(0, this.empCd - dt);
    this.supportCd = Math.max(0, this.supportCd - dt);
    this.mineCd = Math.max(0, this.mineCd - dt);
    this.shield = Math.max(0, this.shield - dt);
    this.rapid = Math.max(0, this.rapid - dt);
    this.dashTime = Math.max(0, this.dashTime - dt);
    this.shake = Math.max(0, this.shake - dt * 25);
    this.pulse = Math.max(0, this.pulse - dt * 1.3);
    const p = this.player;
    p.cooldown -= dt;
    if (input.weapon !== undefined) this.selectWeapon(input.weapon);
    else if (input.nextWeapon) {
      for (let i = 1; i < WEAPONS.length; i++) {
        const next = (this.weapon + i) % WEAPONS.length;
        if (this.ammo[next] > 0) {
          this.selectWeapon(next);
          break;
        }
      }
    }
    p.slow = Math.max(0, (p.slow ?? 0) - dt);
    if (input.support) this.useSupport();
    if (input.mine) this.layMine();
    p.flash = Math.max(0, p.flash - dt);
    if (input.emp && this.empCd <= 0) {
      const beforeMines = this.mines.length;
      this.mines = this.mines.filter((m) => distance(m, p) > 300);
      this.empCd = 13;
      this.pulse = 1;
      this.shake = 9;
      for (const e of this.enemies) {
        if (distance(e, p) < 280) {
          e.stun = 3;
          e.attackWindup = 0;
          e.cooldown = Math.max(e.cooldown, 1.2);
          this.hitEnemy(e, 65);
        }
      }
      this.bullets = this.bullets.filter(
        (b) => !b.enemy || distance(b, p) > 300,
      );
      this.notice = '电磁脉冲 · 周围敌军瘫痪 3 秒';
      if (beforeMines > this.mines.length)
        this.notice += ` · 已排除 ${beforeMines - this.mines.length} 枚地雷`;
      this.noticeTime = 2;
      this.onSound?.('emp');
    }
    let mx = input.x,
      my = input.y,
      len = Math.hypot(mx, my);
    if (len > 1) {
      mx /= len;
      my /= len;
    }
    if (input.dash && this.dashCd <= 0) {
      this.dashCd = 4;
      this.dashTime = 0.25;
      this.shield = Math.max(this.shield, 0.4);
      this.onSound?.('dash');
    }
    if (this.dashTime > 0 && len === 0) {
      mx = Math.cos(p.angle);
      my = Math.sin(p.angle);
      len = 1;
    }
    if (len > 0) {
      p.angle = Math.atan2(my, mx);
      this.move(
        p,
        mx *
          p.speed *
          dt *
          (this.dashTime > 0 ? 3.4 : (p.slow ?? 0) > 0 ? 0.55 : 1),
        my *
          p.speed *
          dt *
          (this.dashTime > 0 ? 3.4 : (p.slow ?? 0) > 0 ? 0.55 : 1),
      );
      this.trackTimer -= dt;
      if (this.trackTimer <= 0) {
        this.tracks.push({ x: p.x, y: p.y, angle: p.angle, life: 9 });
        this.trackTimer = 0.085;
      }
    }
    if (input.aim) p.turret = Math.atan2(input.aim.y - p.y, input.aim.x - p.x);
    else if (input.fire) {
      const nearest = this.enemies
        .filter(
          (e) =>
            e.hp > 0 &&
            e.spawn <= 0 &&
            !this.walls.some((w) => w.hp > 0 && segmentRect(p, e, w) !== null),
        )
        .sort((a, b) => distance(a, p) - distance(b, p))[0];
      p.turret = nearest
        ? Math.atan2(nearest.y - p.y, nearest.x - p.x)
        : p.angle;
    }
    if (input.fire && p.cooldown <= 0) this.shoot(p, false);
    // A blocked deployment is retried; an absent Boss can never grant victory.
    if (!this.endless && !this.bossSpawned && this.reinforcementRetry <= 0) {
      this.spawnEnemy(3);
      this.reinforcementRetry = 0.6;
    }
    const alive = this.enemies.filter((e) => e.hp > 0 && e.kind !== 3);
    const limit = this.isBoss
      ? 3
      : this.endless
        ? Math.min(9, 3 + Math.floor(this.elapsed / 30))
        : Math.min(6, 3 + Math.floor(this.mission / 2));
    if (this.spawnTimer <= 0 && alive.length < limit) {
      if (
        this.endless ||
        (!this.isBoss && (this.fieldMission || this.spawned < this.target))
      ) {
        const spawned = this.spawnEnemy();
        this.spawnTimer = !spawned
          ? 0.6
          : this.isDefend
            ? MISSIONS[this.mission].duration / this.target
            : 2.8;
      }
    }
    this.wave = 1 + Math.floor(this.elapsed / 25);
    const boss = this.boss;
    if (
      boss &&
      boss.hp / boss.maxHp < (this.bossThreshold === 0 ? 0.7 : 0.35) &&
      this.bossThreshold < 2
    ) {
      this.bossThreshold++;
      this.pendingReinforcements.push(
        this.mission >= 6 ? 7 : 1,
        this.mission >= 12 ? 8 : 1,
      );
      this.reinforcementRetry = 0;
      this.notice = `${bossName(this.mission)}呼叫增援 · 优先压制护卫`;
      this.noticeTime = 3;
    }
    if (
      boss &&
      this.pendingReinforcements.length &&
      this.reinforcementRetry <= 0
    ) {
      while (this.pendingReinforcements.length) {
        if (!this.spawnEnemy(this.pendingReinforcements[0])) break;
        this.pendingReinforcements.shift();
      }
      this.reinforcementRetry = 0.6;
    }
    const navigationRevision =
      this.walls.filter((w) => w.hp > 0).length +
      this.objectives.filter((o) => o.kind === 'facility' && o.hp > 0).length;
    for (const e of this.enemies) {
      if (e.hp <= 0) continue;
      e.flash = Math.max(0, e.flash - dt);
      e.spawn = Math.max(0, e.spawn - dt);
      if (e.spawn > 0) continue;
      e.slow = Math.max(0, (e.slow ?? 0) - dt);
      e.stun = Math.max(0, e.stun - dt);
      if (e.stun > 0) continue;
      if (this.elapsed >= (e.mineReadyAt ?? Infinity) && distance(e, p) < 680) {
        if (this.layMine(e, true))
          e.mineReadyAt = this.elapsed + (e.kind === 3 ? 6 : 13);
        else e.mineReadyAt = this.elapsed + 1;
      }
      e.cooldown -= dt;
      e.decision -= dt;
      const wounded =
        e.kind === 7
          ? this.enemies
              .filter((v) => v.id !== e.id && v.hp > 0 && v.hp < v.maxHp)
              .sort((a, b) => distance(e, a) - distance(e, b))[0]
          : undefined;
      const target =
        wounded ??
        (this.protectsBase && e.id % 3 !== 0 && distance(e, p) > 180
          ? this.base
          : p);
      if (e.kind === 7) {
        for (const ally of this.enemies)
          if (ally.id !== e.id && ally.hp > 0 && distance(e, ally) < 190)
            ally.hp = Math.min(ally.maxHp, ally.hp + 12 * dt);
      }
      if (e.kind === 6 && distance(e, target) < 65) {
        e.hp = 0;
        this.burst(e.x, e.y, 45, 160);
        this.explode(e.x, e.y, 1.35, 'fuel');
        this.onSound?.('explosion');
        if (distance(e, p) < 110) this.playerHit(e.damage);
        if (this.protectsBase && distance(e, this.base) < 110)
          this.base.hp = Math.max(0, this.base.hp - e.damage);
        continue;
      }
      const lead =
        target === p && dt > 0 ? Math.min(0.45, distance(e, p) / 700) / dt : 0;
      const oldPlayer = previousPositions.get(0)!;
      const aimAngle = Math.atan2(
        target.y + (p.y - oldPlayer.y) * lead - e.y,
        target.x + (p.x - oldPlayer.x) * lead - e.x,
      );
      const angle = Math.atan2(target.y - e.y, target.x - e.x);
      const difference =
        ((aimAngle - e.turret + Math.PI * 3) % (Math.PI * 2)) - Math.PI;
      if (!(e.kind === 3 && (e.attackWindup ?? 0) > 0))
        e.turret += clamp(difference, -dt * 2.2, dt * 2.2);
      const dist = distance(e, target);
      const range =
        e.kind === 6
          ? 20
          : e.kind === 5
            ? 610
            : e.kind === 7 && wounded
              ? 130
              : e.kind === 8
                ? 440
                : e.kind === 3
                  ? 320
                  : e.kind === 2
                    ? 380
                    : 200;
      const blocked = this.walls.some(
        (w) =>
          w.hp > 0 &&
          segmentRect(e, target, {
            ...w,
            x: w.x - e.radius - 3,
            y: w.y - e.radius - 3,
            w: w.w + e.radius * 2 + 6,
            h: w.h + e.radius * 2 + 6,
          }) !== null,
      );
      if ((dist > range || blocked) && !((e.attackWindup ?? 0) > 0)) {
        const waypoint = blocked
          ? this.navigation.guide(e, target, e.radius, navigationRevision)
          : null;
        let moveAngle = waypoint
          ? Math.atan2(waypoint.y - e.y, waypoint.x - e.x)
          : angle;
        const probe = {
          x: e.x + Math.cos(moveAngle) * 35,
          y: e.y + Math.sin(moveAngle) * 35,
        };
        if (!waypoint && !this.canOccupy(probe.x, probe.y, e.radius)) {
          moveAngle += (e.turn * Math.PI) / 2;
          if (e.decision <= 0) {
            e.turn *= -1;
            e.decision = 2 + this.random() * 2;
          }
        }
        const moved = this.move(
          e,
          Math.cos(moveAngle) * e.speed * dt * ((e.slow ?? 0) > 0 ? 0.4 : 1),
          Math.sin(moveAngle) * e.speed * dt * ((e.slow ?? 0) > 0 ? 0.4 : 1),
        );
        e.angle = moveAngle;
        if (moved < 0.2 && e.decision <= 0) {
          e.turn *= -1;
          e.decision = 1;
        }
      } else if (e.kind !== 6 && !(e.attackWindup && e.attackWindup > 0)) {
        // Flank while in firing range; long-range units reverse away from a rush.
        const retreat = dist < range * 0.55 && [2, 3, 5, 8].includes(e.kind);
        const maneuver = angle + (retreat ? Math.PI : (e.turn * Math.PI) / 2);
        const speed =
          e.speed * dt * (retreat ? 0.8 : 0.48) * ((e.slow ?? 0) > 0 ? 0.4 : 1);
        const moved = this.move(
          e,
          Math.cos(maneuver) * speed,
          Math.sin(maneuver) * speed,
        );
        if (moved < 0.1) e.turn *= -1;
        e.angle = maneuver;
      }
      if (e.kind === 3 && (e.attackWindup ?? 0) > 0) {
        e.attackWindup = Math.max(0, e.attackWindup! - dt);
        if (e.attackWindup === 0) {
          this.shoot(e, true);
        }
        continue;
      }
      if (
        e.kind !== 6 &&
        !wounded &&
        dist < (e.kind === 5 ? 1000 : 730) &&
        Math.abs(difference) < 0.14 &&
        e.cooldown <= 0 &&
        !this.walls.some((w) => w.hp > 0 && segmentRect(e, target, w) !== null)
      ) {
        if (e.kind === 3) {
          e.attackWindup = 0.9 - this.bossThreshold * 0.15;
          this.notice = `${bossName(this.mission)} · ${this.bossThreshold === 2 ? '火箭齐射' : this.bossThreshold === 1 ? '榴弹齐射' : '重炮齐射'}预警，侧移或使用脉冲`;
          this.noticeTime = 1.5;
        } else this.shoot(e, true);
      }
    }
    for (let i = 0; i < this.enemies.length; i++) {
      const a = this.enemies[i];
      if (a.hp <= 0) continue;
      for (let j = i + 1; j < this.enemies.length; j++) {
        const b = this.enemies[j];
        if (b.hp <= 0) continue;
        const d = distance(a, b),
          min = a.radius + b.radius + 4;
        if (d < min && d > 0.01) {
          const push = (min - d) / 2;
          this.move(a, ((a.x - b.x) / d) * push, ((a.y - b.y) / d) * push);
          this.move(b, ((b.x - a.x) / d) * push, ((b.y - a.y) / d) * push);
        }
      }
      const d = distance(a, p),
        min = a.radius + p.radius;
      if (d < min) {
        const nx = d > 0.01 ? (a.x - p.x) / d : 1,
          ny = d > 0.01 ? (a.y - p.y) / d : 0;
        this.move(a, nx * (min - d), ny * (min - d));
        const remaining = min - distance(a, p);
        if (remaining > 0) this.move(p, -nx * remaining, -ny * remaining);
      }
    }
    for (const b of this.bullets) {
      if (b.life <= 0) continue;
      b.life -= dt;
      if (!b.enemy && b.weapon === 6) {
        const heading = Math.atan2(b.vy, b.vx);
        let target = this.enemies.find(
          (e) => e.id === b.homing && e.hp > 0 && e.spawn <= 0,
        );
        // Seek only forward, visible targets; rockets still collide with cover.
        if (!target) target = this.rocketTarget(b, heading);
        b.homing = target?.id;
        if (target) {
          const desired = Math.atan2(target.y - b.y, target.x - b.x);
          const delta = Math.atan2(
            Math.sin(desired - heading),
            Math.cos(desired - heading),
          );
          const angle = heading + clamp(delta, -2.8 * dt, 2.8 * dt);
          const speed = Math.hypot(b.vx, b.vy);
          b.vx = Math.cos(angle) * speed;
          b.vy = Math.sin(angle) * speed;
        }
      }
      const from = { x: b.x, y: b.y },
        to = { x: b.x + b.vx * dt, y: b.y + b.vy * dt };
      let nearest = 2;
      let hit: Wall | Tank | Objective | typeof this.base | null = null;
      let hitType = '';
      for (const w of this.walls) {
        if (w.hp <= 0) continue;
        const t = segmentRect(from, to, w);
        if (t !== null && t < nearest) {
          nearest = t;
          hit = w;
          hitType = 'wall';
        }
      }
      const tanks = b.enemy ? [p] : this.enemies;
      for (const t of tanks) {
        if (t.hp <= 0 || t.spawn > 0 || b.hits?.includes(t.id)) continue;
        const at = segmentCircle(from, to, t, t.radius + 3);
        if (at !== null && at < nearest) {
          nearest = at;
          hit = t;
          hitType = b.enemy ? 'player' : 'enemy';
        }
      }
      if (!b.enemy)
        for (const o of this.objectives) {
          if (o.kind !== 'facility' || o.done || o.hp <= 0) continue;
          const at = segmentCircle(from, to, o, 36);
          if (at !== null && at < nearest) {
            nearest = at;
            hit = o;
            hitType = 'facility';
          }
        }
      if (b.enemy && this.protectsBase) {
        const at = segmentCircle(from, to, this.base, 28);
        if (at !== null && at < nearest) {
          nearest = at;
          hit = this.base;
          hitType = 'base';
        }
      }
      if (hit) {
        b.x = from.x + (to.x - from.x) * nearest;
        b.y = from.y + (to.y - from.y) * nearest;
        b.life = 0;
        if (hitType !== 'player' && !(b.splash ?? 0))
          this.impact(b.x, b.y, b.weapon ?? 0);
        if (hitType === 'wall') {
          const w = hit as Wall;
          w.hp -= b.damage;
          if (w.hp <= 0) {
            this.burst(b.x, b.y, 20, 95, '#aaa083');
            this.burst(b.x, b.y, 7, 30, '#686153', true);
            this.explode(b.x, b.y, 0.8, 'masonry');
          }
        } else if (hitType === 'enemy') {
          const e = hit as Tank;
          const frontal =
            e.kind === 4 &&
            e.stun <= 0 &&
            -(b.vx * Math.cos(e.angle) + b.vy * Math.sin(e.angle)) /
              Math.hypot(b.vx, b.vy) >
              0.5;
          this.hitEnemy(e, b.damage * (frontal ? 0.45 : 1));
          e.slow = Math.max(e.slow ?? 0, b.slow ?? 0);
          if ((b.pierce ?? 0) > 0) {
            b.pierce = (b.pierce ?? 0) - 1;
            (b.hits ??= []).push(e.id);
            b.life = 1.5;
            b.x += b.vx * 0.00001;
            b.y += b.vy * 0.00001;
          }
        } else if (hitType === 'facility') {
          (hit as Objective).hp = Math.max(0, (hit as Objective).hp - b.damage);
        } else if (hitType === 'player') {
          this.playerHit(b.damage, b);
        } else if (hitType === 'base') {
          this.base.hp = Math.max(0, this.base.hp - b.damage);
        }
        if ((b.splash ?? 0) > 0) {
          const radius = b.splash!;
          this.burst(b.x, b.y, 22, 110);
          this.explode(b.x, b.y, radius / 100, 'shell');
          this.explosions[this.explosions.length - 1].weapon = b.weapon;
          this.onSound?.('explosion');
          const speed = Math.hypot(b.vx, b.vy) || 1;
          const origin =
            hitType === 'wall'
              ? { x: b.x - (b.vx / speed) * 0.5, y: b.y - (b.vy / speed) * 0.5 }
              : b;
          const exposed = (v: Vec) =>
            distance(b, v) < radius &&
            !this.walls.some(
              (w) => w.hp > 0 && segmentRect(origin, v, w) !== null,
            );
          if (!b.enemy) {
            for (const e of this.enemies)
              if (e !== hit && e.hp > 0 && e.spawn <= 0 && exposed(e))
                this.hitEnemy(e, b.damage * 0.65);
            for (const o of this.objectives)
              if (o !== hit && o.kind === 'facility' && exposed(o))
                o.hp = Math.max(0, o.hp - b.damage * 0.65);
          } else {
            if (hitType !== 'player' && this.shield <= 0 && exposed(p)) {
              this.playerHit(b.damage * 0.65, b);
            }
            if (hitType !== 'base' && this.protectsBase && exposed(this.base))
              this.base.hp = Math.max(0, this.base.hp - b.damage * 0.65);
          }
        }
      } else {
        b.x = to.x;
        b.y = to.y;
      }
      if (b.x < 0 || b.x > W || b.y < 0 || b.y > H) b.life = 0;
    }
    this.bullets = this.bullets.filter((b) => b.life > 0);
    for (const s of this.particles) {
      s.life -= dt;
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.vx *= 1 - dt * 2;
      s.vy *= 1 - dt * 2;
    }
    this.particles = this.particles.filter((s) => s.life > 0);
    this.tracks.forEach((t) => (t.life -= dt));
    this.tracks = this.tracks.filter((t) => t.life > 0).slice(-160);
    for (const s of this.pickups) {
      s.life -= dt;
      if (
        s.life > 0 &&
        p.hp > 0 &&
        distance(s, p) < (this.save.module === 3 ? 140 : 65)
      ) {
        if (
          s.kind === 3 &&
          s.weapon &&
          this.ammo[s.weapon] >= WEAPONS[s.weapon].capacity
        )
          continue;
        s.life = 0;
        if (s.kind === 3 && s.weapon && WEAPONS[s.weapon]) {
          const weapon = WEAPONS[s.weapon];
          const before = this.ammo[s.weapon];
          this.ammo[s.weapon] = Math.min(
            weapon.capacity,
            before + (s.amount ?? weapon.supply),
          );
          if (before === 0 && this.weapon === 0) this.selectWeapon(s.weapon);
          this.notice = `${weapon.name} +${this.ammo[s.weapon] - before} · 备弹 ${this.ammo[s.weapon]}`;
        } else if (s.kind === 0) {
          p.hp = Math.min(p.maxHp, p.hp + 50);
          this.notice = '维修补给 · 恢复 50 装甲';
        } else if (s.kind === 1) {
          this.rapid = 8;
          this.notice = '超频装填 · 8 秒双倍射速';
        } else {
          this.shield = 6;
          this.notice = '能量护盾 · 6 秒免疫伤害';
        }
        this.noticeTime = 2.5;
        this.onSound?.('pickup');
      }
    }
    this.pickups = this.pickups.filter((s) => s.life > 0);
    this.enemies = this.enemies.filter((e) => e.hp > 0);
    this.updateMines(previousPositions);
    this.enemies = this.enemies.filter((e) => e.hp > 0);
    if (p.hp <= 0 || (this.protectsBase && this.base.hp <= 0)) {
      const wreck = p.hp <= 0 ? p : this.base;
      this.explode(wreck.x, wreck.y, p.hp <= 0 ? 1.3 : 2.2, 'fuel');
      this.onSound?.('explosion');
      this.finish(false);
      return;
    }
    this.updateObjectives(dt);
    if (!this.endless && this.bossDefeated) {
      if (
        (this.fieldMission &&
          this.type !== 'escort' &&
          this.objectives.every((o) => o.done)) ||
        (this.type === 'escort' && this.routeIndex >= this.route.length)
      )
        this.finish(true);
      else if (this.isBoss && !this.boss) this.finish(true);
      else if (this.isDefend && this.elapsed >= MISSIONS[this.mission].duration)
        this.finish(true);
      else if (
        this.type === 'assault' &&
        this.spawned >= this.target &&
        this.enemies.length === 0
      )
        this.finish(true);
    }
  }
  finish(won: boolean) {
    if (this.result) return;
    this.result = {
      runId: this.runId,
      startingKills: this.startingKills,
      totalKills: this.startingKills + this.kills,
      won,
      kills: this.kills,
      score:
        this.score +
        (won
          ? Math.round(this.player.hp) * 5 +
            Math.max(0, 500 - Math.round(this.elapsed) * 2)
          : 0),
      time: this.elapsed,
      mission: this.mission,
      endless: this.endless,
      hp: this.player.hp,
    };
  }
}
