import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import ts from 'typescript';
const tmp = await fs.mkdtemp(path.join(os.tmpdir(), 'iron-embers-test-'));
for (const name of [
  'campaign',
  'terrain',
  'navigation',
  'performance',
  'engine',
  'gamepad',
  'fixed-step',
  'progression',
]) {
  const source = await fs.readFile(
    new URL(`../lib/${name}.ts`, import.meta.url),
    'utf8',
  );
  const js = ts
    .transpileModule(source, {
      compilerOptions: {
        module: ts.ModuleKind.ES2022,
        target: ts.ScriptTarget.ES2022,
      },
    })
    .outputText.replace(
      /from (['"])(\.{1,2}\/[^'"]+)\1/g,
      (_, q, p) => `from ${q}${p}.mjs${q}`,
    );
  await fs.writeFile(path.join(tmp, `${name}.mjs`), js);
}
const {
  Battle,
  W,
  H,
  ENEMY_GATES,
  ENEMY_SPAWN_DISTANCE,
  segmentCircle,
  segmentRect,
} = await import(pathToFileURL(path.join(tmp, 'engine.mjs')));
const {
  defaultSave,
  parseSave,
  MISSIONS,
  WEAPONS,
  loadoutStats,
  beginRun,
  creditRunKills,
  settleRun,
} = await import(pathToFileURL(path.join(tmp, 'campaign.mjs')));
const { PadReader, deadzone } = await import(
  pathToFileURL(path.join(tmp, 'gamepad.mjs'))
);
const { FixedStep } = await import(
  pathToFileURL(path.join(tmp, 'fixed-step.mjs'))
);
const { progression, killsForLevel, MAX_LEVEL, EVOLUTIONS } = await import(
  pathToFileURL(path.join(tmp, 'progression.mjs'))
);
const idle = { x: 0, y: 0, aim: null, fire: false, dash: false, emp: false };
const config = () => ({
  ...defaultSave,
  upgrades: [0, 0, 0, 0, 0, 0],
  completed: [],
});
const make = (mission = 0, endless = false) =>
  new Battle(mission, endless, config(), 1234);
// Supply fixtures exercise the real pickup path before testing equipped weapons.
const stock = (b) => {
  for (let weapon = 1; weapon < WEAPONS.length; weapon++)
    b.pickups.push({
      x: b.player.x,
      y: b.player.y,
      kind: 3,
      weapon,
      amount: WEAPONS[weapon].capacity,
      life: 10,
    });
  b.step(0, idle);
  b.selectWeapon(0);
  b.player.cooldown = 0;
};
let passed = 0;
const test = (name, fn) => {
  try {
    fn();
    console.log(`PASS ${name}`);
    passed++;
  } catch (error) {
    console.error(`FAIL ${name}`, error);
    process.exitCode = 1;
  }
};
test('all 18 mission starts and enemy spawn safety across 360 seeds', () => {
  for (let m = 0; m < MISSIONS.length; m++)
    for (let seed = 1; seed <= 20; seed++) {
      const b = new Battle(m, false, config(), seed);
      assert.equal(b.enemies.length, b.isBoss ? 1 : 3);
      assert.equal(b.enemies.filter((e) => e.kind === 3).length, 1);
      assert(b.canOccupy(b.player.x, b.player.y, b.player.radius));
      for (const e of b.enemies) {
        assert(b.canOccupy(e.x, e.y, e.radius));
        assert(
          Math.hypot(e.x - b.player.x, e.y - b.player.y) >=
            ENEMY_SPAWN_DISTANCE,
        );
        assert(e.y >= 110 && e.y <= 305);
        assert(ENEMY_GATES.some((gate) => Math.abs(gate.x - e.x) <= 14));
      }
    }
});
test('diagonal movement is normalized', () => {
  const a = make(),
    b = make();
  a.step(0.05, { ...idle, x: 1 });
  b.step(0.05, { ...idle, x: 1, y: 1 });
  assert(
    Math.abs(
      Math.hypot(a.player.x - W / 2, a.player.y - (H - 185)) -
        Math.hypot(b.player.x - W / 2, b.player.y - (H - 185)),
    ) < 0.001,
  );
});
test('tank and dash remain outside steel walls', () => {
  const b = make();
  b.walls = [
    {
      x: 410,
      y: 270,
      w: 44,
      h: 160,
      hp: Infinity,
      maxHp: Infinity,
      steel: true,
    },
  ];
  b.player.x = 380;
  b.player.y = 340;
  b.step(0.05, { ...idle, x: 1, dash: true });
  assert(b.player.x <= 390);
  assert(b.canOccupy(b.player.x, b.player.y, 20));
});
test('enemy against wall cannot overlap the player', () => {
  const b = make();
  b.enemies = b.enemies.slice(0, 1);
  const e = b.enemies[0];
  b.walls = [
    {
      x: 410,
      y: 270,
      w: 44,
      h: 160,
      hp: Infinity,
      maxHp: Infinity,
      steel: true,
    },
  ];
  e.x = 391;
  e.y = 340;
  e.spawn = 0;
  e.stun = 5;
  b.player.x = 352;
  b.player.y = 340;
  b.step(0.05, { ...idle, x: 1 });
  assert(Math.hypot(e.x - b.player.x, e.y - b.player.y) >= 39 - 0.01);
});
test('failed spawn retries without incrementing count', () => {
  const b = make();
  b.enemies = [];
  b.player.x = 70;
  b.player.y = 70;
  b.random = () => 0;
  b.canOccupy = () => false;
  const count = b.spawned;
  b.spawnEnemy(0);
  assert.equal(b.enemies.length, 0);
  assert.equal(b.spawned, count);
});
test('swept projectile hits thin steel before targets behind it', () => {
  const b = make();
  const e = b.enemies[0];
  b.walls = [
    {
      x: 410,
      y: 270,
      w: 44,
      h: 160,
      hp: Infinity,
      maxHp: Infinity,
      steel: true,
    },
  ];
  e.x = 485;
  e.y = 340;
  e.spawn = 0;
  e.stun = 5;
  const hp = e.hp;
  b.bullets = [
    { x: 370, y: 340, vx: 5000, vy: 0, damage: 999, enemy: false, life: 2 },
  ];
  b.step(0.05, idle);
  assert.equal(e.hp, hp);
  assert.equal(b.bullets.length, 0);
});
test('one projectile damages only the nearest target', () => {
  const b = make();
  b.walls = [];
  const [a, c] = b.enemies;
  a.x = 300;
  a.y = 300;
  a.spawn = 0;
  a.stun = 5;
  c.x = 380;
  c.y = 300;
  c.spawn = 0;
  c.stun = 5;
  const hp = c.hp;
  b.bullets = [
    { x: 240, y: 300, vx: 5000, vy: 0, damage: 999, enemy: false, life: 2 },
  ];
  b.step(0.05, idle);
  assert.equal(a.hp, 0);
  assert.equal(c.hp, hp);
  assert.equal(b.kills, 1);
});
test('pause freezes simulation, spawns, bullets, and cooldowns', () => {
  const b = make();
  b.dashCd = 2;
  b.paused = true;
  const before = JSON.stringify(b);
  b.step(0.05, { ...idle, x: 1, fire: true, emp: true });
  assert.equal(JSON.stringify(b), before);
});
test('fatal hit cannot be undone by same-frame repair or kill recovery', () => {
  const b = make();
  b.walls = [];
  b.save.upgrades[5] = 3;
  b.spawned = b.target;
  b.player.hp = 10;
  b.player.x = 600;
  b.player.y = 600;
  b.enemies = b.enemies.slice(0, 1);
  const e = b.enemies[0];
  e.x = 300;
  e.y = 300;
  e.hp = 1;
  e.spawn = 0;
  e.stun = 5;
  b.pickups = [{ x: 600, y: 600, kind: 0, life: 10 }];
  b.bullets = [
    { x: 575, y: 600, vx: 300, vy: 0, damage: 20, enemy: true, life: 2 },
    { x: 275, y: 300, vx: 620, vy: 0, damage: 40, enemy: false, life: 2 },
  ];
  b.step(0.05, idle);
  assert.equal(b.player.hp, 0);
  assert.equal(b.result?.won, false);
});
test('defense base loss takes priority over time objective', () => {
  const b = make(1);
  b.elapsed = 44.99;
  b.base.hp = 0;
  b.step(0.03, idle);
  assert.equal(b.result?.won, false);
});
test('assault waits for every planned enemy and ends once', () => {
  const b = make();
  b.hitEnemy(b.boss, 99999);
  b.enemies = [];
  b.spawnTimer = 99;
  b.step(0.01, idle);
  assert.equal(b.result, null);
  b.spawned = b.target;
  b.step(0.01, idle);
  assert.equal(b.result.won, true);
  const before = JSON.stringify(b);
  b.step(0.05, { ...idle, x: 1, fire: true });
  assert.equal(JSON.stringify(b), before);
});
test('boss thresholds trigger exactly two reinforcement pairs', () => {
  const b = make(5);
  const boss = b.boss;
  boss.hp = boss.maxHp * 0.3;
  boss.stun = 10;
  b.step(0.01, idle);
  b.step(0.01, idle);
  assert.equal(b.bossThreshold, 2);
  assert.equal(b.enemies.length, 5);
  for (let i = 0; i < 30; i++) b.step(0.01, idle);
  assert.equal(b.enemies.length, 5);
  b.hitEnemy(boss, 9999);
  b.step(0.01, idle);
  assert.equal(b.result.won, true);
});
test('save parser rejects corrupt and out-of-range fields', () => {
  assert.deepEqual(parseSave('{invalid'), defaultSave);
  const s = parseSave(
    JSON.stringify({
      points: -4,
      chassis: 99,
      completed: [0, 0, 99, -1, '2'],
      upgrades: [9, -1, 2, 'a', 0, null],
    }),
  );
  assert.equal(s.chassis, 1);
  assert.equal(s.points, 0);
  assert.deepEqual(s.completed, [0]);
  assert.deepEqual(s.upgrades, [0, 0, 2, 0, 0, 0]);
  assert.equal(s.music, true);
  assert.equal(s.musicVolume, 40);
  assert.equal(parseSave(JSON.stringify({ sound: false })).music, false);
  assert.equal(
    parseSave(JSON.stringify({ sound: false, music: true, musicVolume: 75 }))
      .musicVolume,
    75,
  );
  assert.equal(parseSave(JSON.stringify({ musicVolume: 101 })).musicVolume, 40);
  assert.equal(
    parseSave(JSON.stringify({ musicVolume: '50' })).musicVolume,
    40,
  );
  assert.equal(parseSave(JSON.stringify({ musicVolume: 0 })).musicVolume, 0);
});
test('segment intersection returns first impact', () => {
  assert.equal(
    segmentCircle({ x: 0, y: 0 }, { x: 100, y: 0 }, { x: 50, y: 0 }, 10),
    0.4,
  );
  assert.equal(
    segmentRect(
      { x: 0, y: 0 },
      { x: 100, y: 0 },
      { x: 30, y: -10, w: 3, h: 20 },
    ),
    0.3,
  );
});
test('endless runs beyond campaign spawn cap with bounded effects', () => {
  const b = make(0, true);
  b.player.hp = b.player.maxHp = 100000;
  for (let i = 0; i < 60 * 100; i++) {
    if (i % 120 === 0) for (const e of b.enemies) b.hitEnemy(e, 9999);
    b.shield = 1;
    b.step(1 / 60, { ...idle, fire: true, emp: i % 900 === 0 });
  }
  assert(b.spawned > 6);
  assert.equal(b.result, null);
  assert(b.particles.length <= 650);
  assert(b.tracks.length <= 160);
});

const quiet = (m) => {
  const b = make(m);
  // These fixtures isolate the original objective; Boss gating has its own suite.
  b.bossDefeated = true;
  b.enemies = [];
  b.spawnTimer = 1e6;
  return b;
};
const stepFor = (b, seconds, input = idle) => {
  for (let i = 0; i < Math.ceil(seconds * 60); i++) b.step(1 / 60, input);
};
test('map is nine times the original size and every mission objective has a traversable approach', () => {
  assert.equal(W * H, 1280 * 800 * 9);
  for (let m = 0; m < MISSIONS.length; m++) {
    const b = make(m),
      step = 40,
      visited = new Set(),
      queue = [
        {
          x: Math.round(b.player.x / step) * step,
          y: Math.round(b.player.y / step) * step,
        },
      ];
    visited.add(`${queue[0].x},${queue[0].y}`);
    for (let i = 0; i < queue.length; i++)
      for (const [dx, dy] of [
        [step, 0],
        [-step, 0],
        [0, step],
        [0, -step],
      ]) {
        const v = { x: queue[i].x + dx, y: queue[i].y + dy },
          key = `${v.x},${v.y}`;
        if (!visited.has(key) && b.canOccupy(v.x, v.y, 22)) {
          visited.add(key);
          queue.push(v);
        }
      }
    for (const target of [
      ...b.objectives,
      ...b.route,
      b.base,
      { x: W / 2, y: 200 },
    ])
      assert(
        queue.some((v) => Math.hypot(v.x - target.x, v.y - target.y) < 100),
        `mission ${m + 1} unreachable objective ${target.id}`,
      );
    assert(
      queue.some((v) => v.x > W * 0.78 && v.y < 300),
      `mission ${m + 1} expanded northeast unreachable`,
    );
  }
});
test('capture needs presence, pauses while contested, and cannot win by killing enemies', () => {
  const b = quiet(6);
  b.spawned = b.target;
  b.step(0.01, idle);
  assert.equal(b.result, null);
  const o = b.objectives[0];
  Object.assign(b.player, { x: o.x, y: o.y });
  stepFor(b, 2);
  const progress = o.progress;
  assert(progress > 1.9);
  b.spawnEnemy(0);
  const e = b.enemies[0];
  Object.assign(e, { x: o.x + 90, y: o.y, spawn: 0, stun: 100 });
  stepFor(b, 1);
  assert.equal(o.progress, progress);
  b.enemies = [];
  b.player.x += 200;
  stepFor(b, 1);
  assert.equal(o.progress, progress);
  for (const objective of b.objectives) {
    Object.assign(b.player, { x: objective.x, y: objective.y });
    stepFor(b, 8.1);
  }
  assert.equal(b.result?.won, true);
});
test('escort stops without proximity or under attack, reaches destination, and loss wins tie', () => {
  const b = quiet(7),
    before = { ...b.base };
  b.player.x = 100;
  b.step(0.05, idle);
  assert.equal(b.base.x, before.x);
  assert.equal(b.base.y, before.y);
  Object.assign(b.player, { x: b.base.x + 100, y: b.base.y });
  b.spawnEnemy(0);
  Object.assign(b.enemies[0], {
    x: b.base.x + 140,
    y: b.base.y,
    spawn: 0,
    stun: 100,
  });
  b.step(0.05, idle);
  assert.equal(b.base.y, before.y);
  b.enemies = [];
  const travelSeconds = b.route
    .slice(1)
    .reduce(
      (seconds, point, index) =>
        seconds +
        Math.hypot(point.x - b.route[index].x, point.y - b.route[index].y) / 78,
      0,
    );
  for (let i = 0; i < 60 * (travelSeconds + 2) && !b.result; i++) {
    Object.assign(b.player, { x: b.base.x + 100, y: b.base.y });
    b.step(1 / 60, idle);
  }
  assert.equal(b.result?.won, true);
  const fatal = quiet(7);
  fatal.routeIndex = fatal.route.length;
  fatal.base.hp = 0;
  fatal.step(0.01, idle);
  assert.equal(fatal.result?.won, false);
});
test('intel persists, requires extraction, and every copy is collected exactly once', () => {
  const b = quiet(8);
  stepFor(b, 30);
  assert(b.objectives.every((o) => !o.done));
  const exit = b.objectives.find((o) => o.kind === 'exit');
  Object.assign(b.player, { x: exit.x, y: exit.y });
  b.step(0.01, idle);
  assert(!exit.done);
  for (const o of b.objectives.filter((o) => o.kind === 'intel')) {
    Object.assign(b.player, { x: o.x, y: o.y });
    b.step(0.01, idle);
  }
  assert.equal(b.result, null);
  const score = b.score;
  b.step(0.01, idle);
  assert.equal(b.score, score);
  Object.assign(b.player, { x: exit.x, y: exit.y });
  b.step(0.01, idle);
  assert.equal(b.result?.won, true);
});
test('sabotage facilities take projectile damage, block tanks, and finish only after all destroyed', () => {
  const b = quiet(9);
  b.walls = [];
  for (const o of b.objectives) {
    assert(!b.canOccupy(o.x, o.y, 20));
    b.bullets.push({
      x: o.x - 70,
      y: o.y,
      vx: 1000,
      vy: 0,
      damage: 999,
      life: 2,
      enemy: false,
    });
    b.step(0.05, idle);
    assert(o.done);
    assert(b.canOccupy(o.x, o.y, 20));
  }
  assert.equal(b.result?.won, true);
  assert.equal(b.kills, 0);
});
test('all 7 weapons produce distinct functional fire modes', () => {
  const outcomes = [];
  for (let weapon = 0; weapon < WEAPONS.length; weapon++) {
    const b = new Battle(0, false, { ...config(), weapon });
    stock(b);
    b.selectWeapon(weapon);
    b.shoot(b.player, false);
    outcomes.push({
      count: b.bullets.length,
      damage: b.bullets[0].damage,
      rate: b.player.cooldown,
      speed: Math.hypot(b.bullets[0].vx, b.bullets[0].vy),
      splash: b.bullets[0].splash,
      pierce: b.bullets[0].pierce,
      slow: b.bullets[0].slow,
    });
  }
  assert(outcomes[1].rate < outcomes[0].rate / 3);
  assert.equal(outcomes[2].count, 5);
  assert.equal(outcomes[3].pierce, 2);
  assert(outcomes[3].speed > outcomes[0].speed * 2);
  assert(outcomes[4].splash >= 100);
  assert(outcomes[5].slow > 0);
});
test('railgun penetrates three tanks, cryo slows targets, and frontal armor can be flanked', () => {
  const b = quiet(0);
  stock(b);
  b.walls = [];
  b.player.x = 200;
  b.player.y = 300;
  b.player.turret = 0;
  for (let i = 0; i < 3; i++) {
    b.spawned = 0;
    b.spawnEnemy(0);
    Object.assign(b.enemies[i], {
      x: 300 + i * 60,
      y: 300,
      spawn: 0,
      stun: 100,
      hp: 200,
      maxHp: 200,
    });
  }
  b.selectWeapon(3);
  b.player.damage = 50;
  b.shoot(b.player, false);
  stepFor(b, 0.25);
  assert(b.enemies.every((e) => e.hp < 200));
  b.bullets = [];
  b.selectWeapon(5);
  b.shoot(b.player, false);
  stepFor(b, 0.15);
  assert(b.enemies.some((e) => (e.slow ?? 0) > 1.5));
  const damageFrom = (front) => {
    const a = quiet(0);
    a.walls = [];
    a.spawned = 0;
    a.spawnEnemy(4);
    const e = a.enemies[0];
    Object.assign(e, {
      x: 500,
      y: 400,
      spawn: 0,
      angle: 0,
      turret: 0,
      speed: 0,
      cooldown: 100,
    });
    a.bullets = [
      {
        x: front ? 540 : 460,
        y: 400,
        vx: front ? -1000 : 1000,
        vy: 0,
        damage: 40,
        life: 2,
        enemy: false,
      },
    ];
    a.step(0.02, idle);
    return e.maxHp - e.hp;
  };
  assert(damageFrom(true) < damageFrom(false));
});
test('explosive shell damages nearby enemies on the near side of cover only', () => {
  const b = quiet(0);
  b.spawnEnemy(0);
  b.spawnEnemy(0);
  const [front, back] = b.enemies;
  Object.assign(front, { x: 500, y: 350, spawn: 0, stun: 100 });
  Object.assign(back, { x: 625, y: 310, spawn: 0, stun: 100 });
  b.walls = [
    {
      x: 550,
      y: 250,
      w: 60,
      h: 160,
      hp: Infinity,
      maxHp: Infinity,
      steel: true,
    },
  ];
  const hp = front.hp,
    hp2 = back.hp;
  b.bullets = [
    {
      x: 520,
      y: 300,
      vx: 1000,
      vy: 0,
      damage: 60,
      life: 2,
      enemy: false,
      splash: 105,
    },
  ];
  b.step(0.05, idle);
  assert(front.hp < hp, 'wall-facing side should receive splash');
  assert.equal(back.hp, hp2, 'steel shields far side');
});
test('support modules repair, shield, acquire visible targets and respect cooldowns', () => {
  for (let support = 0; support < 3; support++) {
    const b = new Battle(0, false, { ...config(), support });
    stock(b);
    b.walls = [];
    b.player.hp = 30;
    b.enemies.forEach((e, i) =>
      Object.assign(e, {
        x: b.player.x + 180 + i * 100,
        y: b.player.y,
        spawn: 0,
        stun: 100,
      }),
    );
    b.useSupport();
    assert(b.supportCd > 0);
    if (support === 0) assert.equal(b.player.hp, 95);
    if (support === 1) assert.equal(b.shield, 4);
    if (support === 2)
      assert.equal(b.bullets.filter((v) => v.homing !== undefined).length, 3);
    const before = JSON.stringify(b);
    b.useSupport();
    assert.equal(JSON.stringify(b), before);
  }
  const b = quiet(0);
  b.save.support = 2;
  b.useSupport();
  assert.equal(b.supportCd, 0);
});
test('enemy specialists heal, rush-explode, and launch different projectile patterns', () => {
  const b = quiet(0);
  b.walls = [];
  for (const kind of [7, 0, 6, 5, 8]) {
    b.spawned = 0;
    assert(b.spawnEnemy(kind));
  }
  b.player.x = 900;
  b.player.y = 500;
  const [medic, ally, suicide, sniper, rocket] = b.enemies;
  Object.assign(medic, { x: 500, y: 500, spawn: 0, cooldown: 100 });
  Object.assign(ally, { x: 580, y: 500, hp: 10, spawn: 0, stun: 100 });
  Object.assign(suicide, { x: 850, y: 500, spawn: 0 });
  sniper.spawn = 0;
  rocket.spawn = 0;
  const hp = b.player.hp;
  b.step(0.05, idle);
  assert(ally.hp > 10);
  assert(b.player.hp < hp);
  assert(!b.enemies.includes(suicide));
  b.bullets = [];
  b.shoot(sniper, true);
  assert(Math.hypot(b.bullets[0].vx, b.bullets[0].vy) > 700);
  b.bullets = [];
  b.shoot(rocket, true);
  assert.equal(b.bullets.length, 3);
  assert(b.bullets.every((v) => v.splash > 0));
});
test('new saves retain all 18 chapters and old saves retain upgrades with default equipment', () => {
  const old = parseSave(
    JSON.stringify({
      completed: [0, 1, 2, 3, 4, 5],
      points: 4,
      upgrades: [1, 2, 3, 0, 1, 2],
      chassis: 2,
    }),
  );
  assert.equal(old.weapon, 0);
  assert.equal(old.support, 0);
  assert.equal(old.module, 0);
  assert.equal(old.upgrades[2], 3);
  assert.equal(old.completed.length, 6);
  const fresh = {
    ...old,
    completed: MISSIONS.map((_, i) => i),
    weapon: 5,
    support: 2,
    module: 3,
  };
  assert.deepEqual(parseSave(JSON.stringify(fresh)), fresh);
  const heavy = loadoutStats({ ...config(), module: 1 }),
    fast = loadoutStats({ ...config(), module: 2 });
  assert(heavy.hp > fast.hp);
  assert(heavy.speed < fast.speed);
});
const pad = (
  buttons = [],
  axes = [0, 0, 0, 0],
  index = 2,
  mapping = 'standard',
) => ({
  index,
  id: 'Test pad',
  connected: true,
  mapping,
  axes,
  buttons: Array.from({ length: 17 }, (_, i) => ({
    pressed: buttons.includes(i),
    value: buttons.includes(i) ? 1 : 0,
  })),
});
test('gamepad deadzones eliminate drift and preserve normalized analog movement', () => {
  assert.deepEqual(deadzone(0.1, -0.1), { x: 0, y: 0 });
  assert.deepEqual(deadzone(NaN, 1), { x: 0, y: 0 });
  const full = deadzone(1, 1);
  assert(Math.abs(Math.hypot(full.x, full.y) - 1) < 1e-8);
  assert(deadzone(0.6, 0).x < 1);
});
test('gamepad sparse index, button edges, held fire and disconnect are deterministic', () => {
  const r = new PadReader();
  let f = r.sample([null, null, pad([0])], 0);
  assert(f.connected);
  assert(!f.confirm);
  r.sample([null, pad()], 10);
  f = r.sample([pad([4, 5, 6, 7, 9, 3, 0, 1])], 20);
  assert(
    f.dash &&
      f.emp &&
      f.support &&
      f.fire &&
      f.pause &&
      f.camera &&
      f.confirm &&
      f.back,
  );
  f = r.sample([pad([4, 5, 6, 7, 9])], 30);
  assert(f.fire);
  assert(!f.dash && !f.emp && !f.support && !f.pause);
  f = r.sample([], 40);
  assert(f.disconnected && !f.fire && !f.connected);
  assert(!r.sample([pad([], [], 0, '')], 50).connected);
});
test('gamepad menus repeat after delay and Start cannot retrigger without release', () => {
  const r = new PadReader();
  r.sample([pad()], 0);
  assert.equal(r.sample([pad([13, 9])], 10).direction, 3);
  assert.equal(r.sample([pad([13, 9])], 100).direction, 0);
  const f = r.sample([pad([13, 9])], 380);
  assert.equal(f.direction, 3);
  assert(!f.pause);
  r.sample([pad()], 400);
  assert(r.sample([pad([9])], 410).pause);
});
test('support press survives high refresh and is consumed once over multiple simulation steps', () => {
  const b = quiet(0);
  b.player.hp = 10;
  const fixed = new FixedStep(),
    input = { ...idle, support: true };
  fixed.advance(b, 1 / 120, input);
  assert(input.support);
  fixed.advance(b, 1 / 120, input);
  assert(!input.support);
  assert.equal(b.player.hp, 75);
  fixed.advance(b, 0.1, input);
  assert.equal(b.player.hp, 75);
});

test('30 rank thresholds progress monotonically, cap correctly and migrate old kills', () => {
  assert.equal(progression(0).level, 1);
  assert.equal(progression(-10).level, 1);
  for (let level = 2; level <= MAX_LEVEL; level++) {
    const n = killsForLevel(level);
    assert.equal(progression(n - 1).level, level - 1);
    assert.equal(progression(n).level, level);
    assert.equal(progression(n).remaining, killsForLevel(level + 1) - n);
  }
  assert(progression(1e9).maxed);
  assert.equal(progression(1e9).level, 30);
  assert.equal(progression(493).progress, 1);
  const old = parseSave(
    JSON.stringify({
      kills: 150,
      upgrades: [2, 1, 0, 1, 0, 0],
      completed: [0, 1],
    }),
  );
  assert.equal(progression(old.kills).level, 16);
  assert.equal(old.activeRun, null);
  assert.equal(
    new Set(EVOLUTIONS.map((e) => progression(killsForLevel(e.level)).stage))
      .size,
    7,
  );
});
test('kill credits persist before finish, reject duplicate and stale reports, settle only once', () => {
  let saved = beginRun(config(), 'first'),
    disk = JSON.stringify(saved);
  const b = new Battle(0, false, saved, 9, 'first');
  b.onProgress = (kills) => {
    saved = creditRunKills(saved, b.runId, kills);
    disk = JSON.stringify(saved);
  };
  const e = b.enemies[0];
  b.hitEnemy(e, 99999);
  b.hitEnemy(e, 99999);
  assert.equal(saved.kills, 1);
  assert.equal(parseSave(disk).kills, 1);
  assert.equal(b.result, null);
  assert.equal(creditRunKills(saved, 'first', 1), saved);
  assert.equal(creditRunKills(saved, 'first', 0), saved);
  const result = {
    runId: 'first',
    kills: 1,
    mission: 0,
    won: false,
    endless: false,
    score: 300,
  };
  const settled = settleRun(saved, result);
  assert.equal(settled.save.kills, 1);
  assert(settled.accepted);
  assert(!settleRun(settled.save, result).accepted);
  saved = beginRun(parseSave(disk), 'retry');
  assert.equal(saved.kills, 1);
  assert.equal(creditRunKills(saved, 'first', 99), saved);
  saved = creditRunKills(saved, 'retry', 2);
  assert.equal(saved.kills, 3);
  const win = { ...result, runId: 'retry', kills: 3, won: true };
  const finish = settleRun(saved, win);
  assert.equal(finish.save.kills, 4);
  assert.equal(finish.reward, 2);
  assert(!settleRun(finish.save, win).accepted);
  const replay = settleRun(beginRun(finish.save, 'replay'), {
    ...win,
    runId: 'replay',
    kills: 1,
  });
  assert.equal(replay.reward, 0);
  assert.equal(replay.save.kills, 5);
});
test('kills upgrade immediately, preserve damage taken and never resurrect a dead player', () => {
  const saved = { ...config(), kills: killsForLevel(6) - 1 },
    b = new Battle(0, false, saved);
  const before = {
    hp: b.player.hp,
    damage: b.player.damage,
    speed: b.player.speed,
    rate: b.player.rate,
  };
  b.player.hp -= 40;
  b.hitEnemy(b.enemies[0], 9999);
  assert.equal(b.level, 6);
  assert.equal(b.career.stage, 1);
  assert.equal(b.player.hp, before.hp - 40 + 6);
  assert(b.player.damage > before.damage);
  assert(b.player.speed > before.speed);
  assert(b.player.rate < before.rate);
  assert(b.levelUpTime > 0);
  const expected = loadoutStats(saved, saved.kills + 1);
  assert.equal(b.player.damage, expected.damage);
  b.hitEnemy(b.enemies[0], 9999);
  assert.equal(b.player.damage, expected.damage);
  const dead = new Battle(0, false, saved);
  dead.player.hp = 0;
  dead.hitEnemy(dead.enemies[0], 9999);
  assert.equal(dead.level, 6);
  assert.equal(dead.player.hp, 0);
  dead.step(0.01, idle);
  assert.equal(dead.result.won, false);
  assert.equal(dead.result.totalKills, 25);
});
test('EMP multi-kill credits once per enemy and crosses consecutive early ranks', () => {
  const b = new Battle(0, true, config());
  b.walls = [];
  b.enemies = [];
  for (let i = 0; i < 7; i++) {
    b.spawnEnemy(0);
    Object.assign(b.enemies[i], {
      x: b.player.x + 70 + i * 24,
      y: b.player.y,
      spawn: 0,
      hp: 20,
      stun: 100,
    });
  }
  let saved = beginRun(config(), 'multi');
  b.onProgress = (n) => {
    saved = creditRunKills(saved, 'multi', n);
  };
  b.step(0.01, { ...idle, emp: true });
  assert.equal(b.kills, 7);
  assert.equal(saved.kills, 7);
  assert.equal(b.level, 3);
  assert.equal(b.player.maxHp, 162);
  const hp = b.player.maxHp;
  b.step(0.01, idle);
  assert.equal(b.player.maxHp, hp);
});
test('growth stacks with all loadouts and remains stable at the final level', () => {
  for (let chassis = 0; chassis < 3; chassis++)
    for (let weapon = 0; weapon < 6; weapon++) {
      const base = {
          ...config(),
          chassis,
          weapon,
          upgrades: [3, 3, 3, 3, 3, 3],
        },
        low = loadoutStats(base),
        high = loadoutStats({ ...base, kills: 493 });
      assert.equal(high.hp - low.hp, 174);
      assert(high.damage > low.damage * 2);
      assert(high.rate < low.rate);
      assert(high.speed > low.speed);
    }
  const b = new Battle(0, false, { ...config(), kills: 493 });
  const before = {
    hp: b.player.maxHp,
    damage: b.player.damage,
    rate: b.player.rate,
  };
  b.hitEnemy(b.enemies[0], 9999);
  assert.equal(b.level, 30);
  assert.deepEqual(
    { hp: b.player.maxHp, damage: b.player.damage, rate: b.player.rate },
    before,
  );
});
test('city warehouse detour reaches line of sight instead of oscillating for two minutes', () => {
  const b = make();
  b.player.x = 772.4;
  b.player.y = 630;
  b.player.hp = 1e9;
  b.spawnTimer = 1e9;
  const e = b.enemies[0];
  Object.assign(e, {
    x: 772.4,
    y: 308,
    spawn: 0,
    turn: 1,
    damage: 0,
    speed: 75,
  });
  b.enemies = [e];
  assert(b.canOccupy(e.x, e.y, e.radius));
  assert(b.canOccupy(b.player.x, b.player.y, b.player.radius));
  for (let i = 0; i < 60 * 35; i++) b.step(1 / 60, idle);
  assert(
    Math.hypot(e.x - b.player.x, e.y - b.player.y) < 230,
    `enemy stuck at ${e.x}, ${e.y}`,
  );
  assert(
    !b.walls.some((w) => w.hp > 0 && segmentRect(e, b.player, w) !== null),
  );
});
test('every escort segment clears buildings for a full-size convoy', () => {
  for (const mission of [7, 13]) {
    const b = make(mission);
    for (let i = 1; i < b.route.length; i++) {
      for (let t = 0; t <= 1; t += 0.01) {
        const a = b.route[i - 1],
          z = b.route[i];
        assert(b.canOccupy(a.x + (z.x - a.x) * t, a.y + (z.y - a.y) * t, 46));
      }
    }
  }
});
const { FramePacer, AdaptiveResolution, renderPolicy } = await import(
  pathToFileURL(path.join(tmp, 'performance.mjs'))
);
test('30/45/60 pacing stays accurate on 60/90/120Hz displays without catch-up bursts', () => {
  for (const hz of [60, 90, 120])
    for (const fps of [30, 45, 60]) {
      const pacer = new FramePacer();
      let count = 0;
      for (let i = 0; i < hz * 10; i++)
        if (pacer.take((i * 1000) / hz, fps)) count++;
      assert(Math.abs(count - fps * 10) <= 1, `${hz}Hz/${fps}FPS: ${count}`);
      pacer.reset();
      assert(pacer.take(60000, fps));
      assert(!pacer.take(60001, fps));
    }
});
test('thermal and power saving cap GPU load; sustained alternating dropped frames lower resolution', () => {
  const cool = { thermal: 0, powerSave: false, background: false };
  assert.equal(renderPolicy(60, true, cool).fps, 60);
  assert.equal(renderPolicy(60, true, { ...cool, thermal: 2 }).fps, 30);
  const hot = renderPolicy(60, true, { ...cool, thermal: 3 });
  assert.equal(hot.fps, 20);
  assert(hot.scale > 1.5);
  assert(hot.effects < 0.5);
  assert.equal(renderPolicy(45, true, { ...cool, powerSave: true }).fps, 30);
  const adaptive = new AdaptiveResolution();
  for (let i = 0; i < 240; i++)
    adaptive.sample(i % 2 ? 1000 / 30 : 1000 / 60, 60);
  assert(adaptive.pressure > 0);
  const reduced = adaptive.pressure;
  for (let i = 0; i < 600; i++) adaptive.sample(1000 / 60, 60);
  assert.equal(adaptive.pressure, reduced);
  for (let i = 0; i < 1200; i++) adaptive.sample(1000 / 60, 60);
  assert(adaptive.pressure < reduced);
});
test('explosion descriptors are bounded, expire on simulation time and never consume combat RNG', () => {
  const b = make(),
    copy = make();
  const hp = b.enemies[0].hp;
  for (let i = 0; i < 200; i++) b.explode(1200 + i, 800, 1, 'armor');
  assert.equal(b.explosions.length, 32);
  assert.equal(new Set(b.explosions.map((e) => e.id)).size, 32);
  assert.equal(b.enemies[0].hp, hp);
  assert.equal(b.kills, 0);
  assert.equal(b.random(), copy.random());
  b.paused = true;
  const before = JSON.stringify(b.explosions);
  b.step(10, idle);
  assert.equal(JSON.stringify(b.explosions), before);
  b.paused = false;
  b.elapsed = 6;
  b.step(0.01, idle);
  assert.equal(b.explosions.length, 0);
});
test('one destroyed tank produces exactly one armor detonation and one credited kill', () => {
  const b = make(),
    target = b.enemies[0];
  b.hitEnemy(target, 9999);
  b.hitEnemy(target, 9999);
  assert.equal(b.kills, 1);
  assert.equal(b.explosions.filter((e) => e.kind === 'armor').length, 1);
});
test('living cover has real collision and is removed by the same destruction rules', () => {
  for (let mission = 0; mission < 18; mission++) {
    const b = make(mission),
      trees = b.walls.filter((w) => w.kind === 'tree');
    assert(trees.length >= 8, `mission ${mission + 1} needs visible trees`);
    for (const tree of trees) {
      const x = tree.x + tree.w / 2,
        y = tree.y + tree.h / 2;
      assert(!b.canOccupy(x, y, 1));
      tree.hp = 0;
      assert(b.canOccupy(x, y, 1));
      tree.hp = tree.maxHp;
    }
  }
});
test('switching uses independent reloads, preserves HP and leaves garage saves untouched', () => {
  const save = { ...config(), kills: 24 },
    before = JSON.stringify(save);
  const b = new Battle(0, true, save, 33);
  stock(b);
  b.player.hp = 70;
  assert(b.selectWeapon(6));
  assert.equal(b.player.hp, 70);
  b.shoot(b.player, false);
  const reload = b.player.cooldown;
  const missile = JSON.stringify(b.bullets[0]);
  assert(b.selectWeapon(1));
  assert.equal(b.player.cooldown, 0.25);
  b.elapsed += 0.2;
  assert(b.selectWeapon(6));
  assert(Math.abs(b.player.cooldown - (reload - 0.2)) < 1e-8);
  const cooldown = b.player.cooldown;
  assert(!b.selectWeapon(6));
  assert.equal(b.player.cooldown, cooldown);
  assert.equal(JSON.stringify(b.bullets[0]), missile);
  b.hitEnemy(b.enemies[0], 9999);
  assert.equal(b.weapon, 6);
  assert.equal(
    b.player.damage,
    loadoutStats(save, b.startingKills + b.kills, 6).damage,
  );
  assert.equal(JSON.stringify(save), before);
  b.paused = true;
  assert(!b.selectWeapon(1));
  b.paused = false;
  b.finish(true);
  assert(!b.selectWeapon(1));
  const timed = quiet(0),
    shots = [];
  stock(timed);
  timed.selectWeapon(6);
  timed.player.cooldown = 0;
  timed.onSound = (sound) => {
    if (sound === 'fire') shots.push(timed.elapsed);
  };
  timed.step(1 / 60, { ...idle, fire: true });
  const readyAt = timed.elapsed + timed.player.cooldown;
  timed.step(1 / 60, { ...idle, weapon: 1 });
  timed.step(1 / 60, { ...idle, weapon: 6, fire: true });
  for (let i = 0; i < 180 && shots.length < 2; i++)
    timed.step(1 / 60, { ...idle, fire: true });
  assert.equal(shots.length, 2);
  assert(shots[1] >= readyAt, 'switching must not subtract reload time twice');
});
test('weapon selection inputs fire once and handpad X requires release between switches', () => {
  const reader = new PadReader();
  assert(!reader.sample([pad([2])], 0).weapon);
  reader.sample([pad()], 1);
  assert(reader.sample([pad([2])], 2).weapon);
  assert(!reader.sample([pad([2])], 3).weapon);
  reader.sample([pad()], 4);
  assert(reader.sample([pad([2])], 5).weapon);
  assert(!reader.sample([], 6).weapon);
  const b = quiet(0),
    fixed = new FixedStep(),
    input = { ...idle, nextWeapon: true };
  stock(b);
  fixed.advance(b, 0.1, input);
  assert.equal(b.weapon, 1);
  fixed.advance(b, 0.1, input);
  assert.equal(b.weapon, 1);
  assert(!b.selectWeapon(NaN));
  assert(!b.selectWeapon(1.5));
  assert(!b.selectWeapon(99));
});
test('guided rockets lock only visible forward targets and retain their launch properties', () => {
  const b = quiet(0);
  stock(b);
  b.spawned = 0;
  assert(b.spawnEnemy(0));
  const enemy = b.enemies[0];
  b.walls = [];
  Object.assign(b.player, { x: 1280, y: 1000, turret: -Math.PI / 2 });
  Object.assign(enemy, { x: 1290, y: 650, spawn: 0, stun: 100 });
  b.selectWeapon(6);
  b.shoot(b.player, false);
  const rocket = b.bullets[0];
  assert.equal(rocket.homing, enemy.id);
  assert.equal(rocket.weapon, 6);
  assert.equal(rocket.splash, 120);
  const damage = rocket.damage;
  b.selectWeapon(1);
  b.step(0.05, idle);
  assert.equal(rocket.damage, damage);
  assert.equal(rocket.weapon, 6);
  b.bullets = [];
  b.walls = [
    {
      x: 1200,
      y: 800,
      w: 180,
      h: 30,
      hp: Infinity,
      maxHp: Infinity,
      steel: true,
    },
  ];
  b.selectWeapon(6);
  b.shoot(b.player, false);
  assert.equal(b.bullets[0].homing, undefined);
});
test('north entries keep distance, wait when blocked and preserve pending boss reinforcements', () => {
  const b = quiet(0);
  b.walls = [];
  b.player.x = 1280;
  b.player.y = 110;
  for (let i = 0; i < 20; i++) {
    b.enemies = [];
    b.spawned = 0;
    assert(b.spawnEnemy(0));
    assert(
      Math.hypot(b.enemies[0].x - b.player.x, b.enemies[0].y - b.player.y) >=
        700,
    );
  }
  const blockers = ENEMY_GATES.map((gate) => ({
    x: gate.x - 70,
    y: 40,
    w: 140,
    h: 330,
    hp: Infinity,
    maxHp: Infinity,
    steel: true,
  }));
  b.enemies = [];
  b.spawned = 0;
  b.walls = blockers;
  assert.equal(b.spawnEnemy(0), false);
  assert.equal(b.spawned, 0);
  b.walls = [];
  assert(b.spawnEnemy(0));
  assert.equal(b.spawned, 1);
  const boss = make(5);
  boss.boss.spawn = 0;
  boss.boss.stun = 100;
  boss.boss.hp = boss.boss.maxHp * 0.6;
  boss.walls = blockers;
  boss.step(0.05, idle);
  assert.equal(boss.bossThreshold, 1);
  assert.equal(boss.enemies.length, 1);
  boss.walls = [];
  stepFor(boss, 0.8);
  assert.equal(boss.enemies.length, 3);
  stepFor(boss, 0.8);
  assert.equal(boss.enemies.length, 3);
});
test('four permanent perimeter walls stop dashes and every projectile while entries stay traversable', () => {
  for (let mission = 0; mission < 18; mission++) {
    const b = make(mission),
      walls = b.walls.filter((w) => w.kind === 'boundary');
    assert.equal(walls.length, 4);
    assert(walls.every((w) => w.steel && w.hp === Infinity));
    for (const gate of ENEMY_GATES) {
      assert(b.canOccupy(gate.x, gate.y, 46));
      // Sabotage facilities occupy junctions: enemies must be able to route
      // around them, rather than requiring a straight path through the target.
      assert(
        b.navigation.guide(gate, b.player, 46, 0),
        `mission ${mission}: entrance ${gate.x} must reach the battlefield`,
      );
    }
  }
  for (const weapon of [0, 1, 3, 6])
    for (const [x, y, angle] of [
      [60, 800, Math.PI],
      [W - 60, 800, 0],
      [1280, 60, -Math.PI / 2],
      [1280, H - 60, Math.PI / 2],
    ]) {
      const b = quiet(0);
      stock(b);
      b.walls = b.walls.filter((w) => w.kind === 'boundary');
      Object.assign(b.player, { x, y, turret: angle });
      b.selectWeapon(weapon);
      b.shoot(b.player, false);
      b.step(0.05, idle);
      assert.equal(b.bullets.length, 0);
      assert(b.walls.every((w) => w.hp === Infinity));
      b.move(b.player, Math.cos(angle) * 600, Math.sin(angle) * 600);
      assert(
        b.player.x >= 45 &&
          b.player.x <= W - 45 &&
          b.player.y >= 45 &&
          b.player.y <= H - 45,
      );
    }
});
test('special ammo starts empty, comes from kills once, auto-equips on pickup and resets on retry', () => {
  const b = new Battle(0, true, { ...config(), weapon: 6 });
  assert.equal(b.weapon, 0);
  assert.equal(b.player.damage, loadoutStats(b.save, 0, 0).damage);
  assert.deepEqual(b.ammo, [Infinity, 0, 0, 0, 0, 0, 0]);
  assert(!b.selectWeapon(6));
  const enemy = b.enemies[0];
  b.hitEnemy(enemy, 9999);
  b.hitEnemy(enemy, 9999);
  assert.equal(b.kills, 1);
  const supply = b.pickups.find((s) => s.kind === 3);
  assert.equal(b.pickups.filter((s) => s.kind === 3).length, 1);
  assert.equal(supply.weapon, 6);
  b.player.x = supply.x;
  b.player.y = supply.y;
  b.step(0, idle);
  assert.equal(b.weapon, 6);
  assert.equal(b.ammo[6], WEAPONS[6].supply);
  const fresh = new Battle(0, true, b.save);
  assert.equal(fresh.ammo[6], 0);
  assert.equal(fresh.weapon, 0);
});
test('one shotgun shot spends one round, last rocket keeps its damage and falls back safely', () => {
  const b = quiet(0);
  stock(b);
  b.selectWeapon(2);
  const before = b.ammo[2];
  b.shoot(b.player, false);
  assert.equal(b.ammo[2], before - 1);
  assert.equal(b.bullets.length, 5);
  b.bullets = [];
  b.selectWeapon(6);
  b.ammo[6] = 1;
  const damage = b.player.damage;
  b.shoot(b.player, false);
  assert.equal(b.ammo[6], 0);
  assert.equal(b.weapon, 0);
  assert.equal(b.bullets[0].weapon, 6);
  assert.equal(b.bullets[0].damage, damage);
  assert.equal(b.bullets[0].splash, 120);
  assert.equal(
    b.player.damage,
    loadoutStats(b.save, b.startingKills, 0).damage,
  );
  assert(!b.selectWeapon(6));
  const ammo = [...b.ammo],
    bullets = b.bullets.length;
  b.paused = true;
  b.step(1, { ...idle, fire: true });
  assert.deepEqual(b.ammo, ammo);
  assert.equal(b.bullets.length, bullets);
  assert(WEAPONS[1].damage / WEAPONS[1].rate < 0.75);
});
test('supplies cap reserves, expire without collecting, and cycle skips empty slots', () => {
  const b = quiet(0);
  b.pickups = [{ ...b.player, kind: 3, weapon: 3, amount: 999, life: 2 }];
  b.step(0, idle);
  assert.equal(b.ammo[3], WEAPONS[3].capacity);
  b.step(0, { ...idle, nextWeapon: true });
  assert.equal(b.weapon, 0);
  b.step(0, { ...idle, nextWeapon: true });
  assert.equal(b.weapon, 3);
  b.pickups = [{ ...b.player, kind: 3, weapon: 6, amount: 5, life: 0.001 }];
  b.step(0.01, idle);
  assert.equal(b.ammo[6], 0);
  const before = b.ammo[3];
  b.pickups = [{ ...b.player, kind: 3, weapon: 3, amount: 5, life: 2 }];
  b.step(0, idle);
  assert.equal(b.ammo[3], before);
  assert.equal(b.pickups.length, 1);
});
test('rocket support shares finite ammunition and never charges an empty or targetless launch', () => {
  const b = quiet(0);
  b.save.support = 2;
  b.walls = [];
  b.useSupport();
  assert.equal(b.supportCd, 0);
  assert.equal(b.bullets.length, 0);
  b.ammo[6] = 2;
  b.useSupport();
  assert.equal(b.ammo[6], 2);
  assert.equal(b.supportCd, 0);
  for (let i = 0; i < 3; i++) {
    b.spawned = 0;
    b.spawnEnemy(0);
  }
  b.enemies.forEach((e, i) =>
    Object.assign(e, { x: b.player.x + 150 + i * 80, y: b.player.y, spawn: 0 }),
  );
  b.useSupport();
  assert.equal(b.ammo[6], 0);
  assert.equal(b.bullets.length, 2);
  assert(b.supportCd > 0);
});
test('rockets turn smoothly, re-acquire living targets, and cannot bypass a wall', () => {
  const b = quiet(0);
  stock(b);
  b.walls = [];
  b.spawned = 0;
  b.spawnEnemy(0);
  b.spawnEnemy(0);
  Object.assign(b.player, { x: 500, y: 500, turret: 0 });
  b.enemies.forEach((e, i) =>
    Object.assign(e, { x: 850, y: 500 + i * 80, spawn: 0, stun: 100 }),
  );
  b.selectWeapon(6);
  b.shoot(b.player, false);
  const rocket = b.bullets[0],
    target = b.enemies[0];
  target.y += 200;
  b.step(0.05, idle);
  const angle = Math.atan2(rocket.vy, rocket.vx);
  assert(angle > 0 && angle <= 2.8 * 0.05 + 1e-9);
  target.hp = 0;
  b.step(0.05, idle);
  assert.equal(rocket.homing, b.enemies[0].id);
  b.walls = [
    {
      x: rocket.x + 5,
      y: rocket.y - 100,
      w: 20,
      h: 200,
      hp: Infinity,
      maxHp: Infinity,
      steel: true,
    },
  ];
  b.step(0.05, idle);
  assert(!b.bullets.includes(rocket));
});
test('enemy specialists own seven distinct weapons and player hits emit matching impacts', () => {
  const seen = new Set();
  for (const kind of [0, 1, 2, 4, 5, 7, 8]) {
    const b = quiet(0);
    b.walls = [];
    b.spawned = 0;
    b.spawnEnemy(kind);
    const enemy = b.enemies[0];
    enemy.spawn = 0;
    Object.assign(b.player, { x: 500, y: 500 });
    Object.assign(enemy, { x: 600, y: 500, turret: Math.PI, stun: 100 });
    b.shoot(enemy, true);
    const bullet = b.bullets[0];
    seen.add(bullet.weapon);
    b.bullets = [{ ...bullet, x: 540, y: 500, vx: -1000, vy: 0 }];
    const hp = b.player.hp;
    b.step(0.05, idle);
    assert(b.player.hp < hp);
    assert(
      b.explosions.some(
        (e) => e.kind === 'impact' && e.weapon === bullet.weapon,
      ),
    );
    assert.equal(b.kills, 0);
    assert.equal(b.pickups.length, 0);
    if (kind === 7) assert(b.player.slow > 1);
  }
  assert.equal(seen.size, 7);
});
test('same shotgun volley aggregates pellets while shields still block subsequent attacks', () => {
  const b = quiet(0);
  b.walls = [];
  Object.assign(b.player, { x: 500, y: 500 });
  const hp = b.player.hp;
  b.bullets = Array.from({ length: 5 }, () => ({
    x: 530,
    y: 500,
    vx: -1000,
    vy: 0,
    damage: 8,
    weapon: 2,
    salvo: 88,
    enemy: true,
    life: 1,
  }));
  b.step(0.05, idle);
  assert.equal(b.player.hp, hp - 40);
  b.bullets = [
    { x: 530, y: 500, vx: -1000, vy: 0, damage: 40, enemy: true, life: 1 },
  ];
  b.step(0.01, idle);
  assert.equal(b.player.hp, hp - 40);
  b.shield = 4;
  b.bullets = [
    {
      x: 530,
      y: 500,
      vx: -1000,
      vy: 0,
      damage: 8,
      weapon: 2,
      salvo: 88,
      enemy: true,
      life: 1,
    },
  ];
  b.step(0.01, idle);
  assert.equal(b.player.hp, hp - 40);
});
test('music switching on gamepad View uses a release edge and saves validate the selected score', () => {
  const reader = new PadReader();
  reader.sample([pad()], 0);
  assert(reader.sample([pad([8])], 1).music);
  assert(!reader.sample([pad([8])], 2).music);
  reader.sample([pad()], 3);
  assert(reader.sample([pad([8])], 4).music);
  assert(!reader.sample([], 5).music);
  assert.equal(parseSave(JSON.stringify({ musicTrack: 2 })).musicTrack, 2);
  assert.equal(parseSave(JSON.stringify({ musicTrack: 9 })).musicTrack, 0);
});
console.log(`\n${passed} gameplay checks passed.`);
await fs.rm(tmp, { recursive: true, force: true });
