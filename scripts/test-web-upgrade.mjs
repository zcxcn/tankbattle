import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import ts from 'typescript';

const root = path.resolve('outputs/test-web-upgrade');
await fs.mkdir(root, { recursive: true });
for (const name of [
  'campaign',
  'terrain',
  'navigation',
  'performance',
  'engine',
  'fixed-step',
  'progression',
  'gamepad',
  'weapon-audio',
]) {
  const source = await fs.readFile(`lib/${name}.ts`, 'utf8');
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
  await fs.writeFile(path.join(root, name + '.mjs'), js);
}
const read = (name) => import(pathToFileURL(path.join(root, name + '.mjs')));
const { Battle } = await read('engine');
const { defaultSave, MISSIONS } = await read('campaign');
const { FixedStep } = await read('fixed-step');
const { PadReader } = await read('gamepad');
const { weaponRecording, SHOT_SECONDS } = await read('weapon-audio');
const idle = { x: 0, y: 0, aim: null, fire: false, dash: false, emp: false };
const make = (mission = 0, endless = false) =>
  new Battle(
    mission,
    endless,
    { ...defaultSave, upgrades: [0, 0, 0, 0, 0, 0] },
    2049,
  );
const arena = () => {
  const b = make(0, true);
  b.walls = [];
  b.enemies = [];
  b.spawnTimer = 999;
  b.player.x = b.player.y = 1000;
  return b;
};
const seconds = (b, t, input = idle) => {
  for (let i = 0; i < Math.ceil(t * 60); i++) b.step(1 / 60, input);
};
const enemy = (b, x = 1300, y = 1000, kind = 0) => {
  b.spawnEnemy(kind);
  const e = b.enemies.at(-1);
  Object.assign(e, { x, y, spawn: 0, stun: 999, mineReadyAt: 999 });
  return e;
};
let passed = 0;
function test(name, fn) {
  fn();
  console.log('PASS ' + name);
  passed++;
}
function objectiveComplete(b) {
  b.spawned = b.target;
  b.elapsed = Math.max(b.elapsed, MISSIONS[b.mission].duration ?? 0);
  b.objectives.forEach((o) => {
    o.done = true;
    o.progress = 8;
    o.hp = 0;
  });
  b.routeIndex = b.route.length;
}
test('all 18 missions require both Boss defeat and the original objective', () => {
  for (let mission = 0; mission < 18; mission++) {
    const b = make(mission),
      boss = b.boss;
    assert(boss && b.bossSpawned && !b.bossDefeated);
    b.enemies = [boss];
    boss.stun = 999;
    b.spawnTimer = 999;
    objectiveComplete(b);
    b.step(0, idle);
    assert.equal(b.result, null, `mission ${mission + 1} bypassed Boss`);
    b.hitEnemy(boss, 999999);
    b.step(0, idle);
    assert.equal(b.result?.won, true);
    const c = make(mission);
    c.hitEnemy(c.boss, 999999);
    c.step(0, idle);
    if (!c.isBoss)
      assert.equal(
        c.result,
        null,
        `mission ${mission + 1} bypassed primary objective`,
      );
  }
});
test('blocked Boss retries and a defeated Boss never respawns', () => {
  const b = make();
  b.enemies = [];
  b.bossSpawned = false;
  b.spawnTimer = 999;
  const occupy = b.canOccupy.bind(b);
  b.canOccupy = () => false;
  objectiveComplete(b);
  b.step(0.01, idle);
  assert.equal(b.result, null);
  assert(!b.boss);
  b.canOccupy = occupy;
  seconds(b, 0.8);
  assert(b.boss);
  b.hitEnemy(b.boss, 999999);
  b.step(0.01, idle);
  assert(b.bossDefeated);
  assert(b.result.won);
});
test('Boss windup freezes the telegraph and EMP cancels the attack', () => {
  const b = arena(),
    boss = enemy(b, 1250, 1000, 3);
  Object.assign(boss, { stun: 0, turret: Math.PI, cooldown: 0 });
  b.step(1 / 60, idle);
  assert(boss.attackWindup > 0);
  assert.equal(b.bullets.length, 0);
  const direction = boss.turret,
    position = { x: boss.x, y: boss.y };
  seconds(b, 0.3, { ...idle, y: 1 });
  assert.equal(boss.turret, direction);
  assert.deepEqual({ x: boss.x, y: boss.y }, position);
  b.player.x = boss.x - 160;
  b.player.y = boss.y;
  b.step(0.01, { ...idle, emp: true });
  assert.equal(boss.attackWindup, 0);
  assert(boss.stun > 2.9);
  assert.equal(b.bullets.length, 0);
});
test('Boss phase weapon changes at the advertised 70 and 35 percent thresholds', () => {
  const b = arena(),
    boss = enemy(b, 1300, 1000, 3);
  for (const [fraction, weapon] of [
    [1, 0],
    [0.7, 4],
    [0.35, 6],
  ]) {
    b.bullets = [];
    boss.hp = boss.maxHp * fraction;
    b.shoot(boss, true);
    assert(b.bullets.length >= 3);
    assert(b.bullets.every((p) => p.weapon === weapon));
  }
});
test('invalid mine placement spends nothing; fixed substeps consume M once', () => {
  const b = arena();
  const occupy = b.canOccupy.bind(b);
  b.canOccupy = () => false;
  assert(!b.layMine());
  assert.equal(b.mineAmmo, 6);
  assert.equal(b.mineCd, 0);
  b.canOccupy = occupy;
  const input = { ...idle, mine: true };
  new FixedStep().advance(b, 0.15, input);
  assert.equal(b.mines.length, 1);
  assert.equal(b.mineAmmo, 5);
  assert.equal(input.mine, false);
  assert(!b.layMine());
});
test('friendly mine arms after a delay, kills once, and never hurts the player', () => {
  const b = arena();
  assert(b.layMine());
  const mine = b.mines[0];
  const e = enemy(b, mine.x, mine.y);
  const hp = b.player.hp;
  let reports = 0;
  b.onProgress = () => reports++;
  seconds(b, 0.8);
  assert.equal(b.kills, 0);
  assert.equal(b.mines.length, 1);
  // Reset the enemy onto the trigger after collision separation from its owner.
  e.x = mine.x;
  e.y = mine.y;
  b.player.x += 200;
  seconds(b, 0.5);
  assert.equal(b.kills, 1);
  assert.equal(reports, 1);
  assert.equal(b.mines.length, 0);
  assert.equal(b.player.hp, hp);
  seconds(b, 0.5);
  assert.equal(reports, 1);
});
test('enemy mines do not trigger on allies but hit the player and respect shields', () => {
  for (const shield of [0, 5]) {
    const b = arena(),
      e = enemy(b, 1300, 1000);
    e.angle = 0;
    assert(b.layMine(e, true));
    const mine = b.mines[0];
    mine.armedAt = 0;
    e.x = mine.x;
    e.y = mine.y;
    b.step(0, idle);
    assert.equal(b.mines.length, 1);
    e.x = 1500;
    b.player.x = mine.x;
    b.player.y = mine.y;
    b.shield = shield;
    const hp = b.player.hp;
    b.step(0, idle);
    assert.equal(b.mines.length, 0);
    assert.equal(b.kills, 0);
    assert.equal(b.player.hp, shield ? hp : hp - mine.damage);
  }
});
test('EMP safely removes both armed and unarmed mines only inside its radius', () => {
  const b = arena();
  b.mines = [0, 1, 2].map((id) => ({
    id,
    x: 1000 + [40, 300, 301][id],
    y: 1000,
    enemy: id !== 0,
    owner: id,
    damage: 999,
    armedAt: id === 0 ? 0 : 999,
    expiresAt: 999,
  }));
  const hp = b.player.hp;
  b.step(0.01, { ...idle, emp: true });
  assert.deepEqual(
    b.mines.map((m) => m.id),
    [2],
  );
  assert.equal(b.player.hp, hp);
  assert.equal(b.kills, 0);
  assert.equal(b.explosions.length, 0);
});
test('mine blast cannot damage a target through intact cover', () => {
  const b = arena(),
    trigger = enemy(b, 1020, 1000),
    covered = enemy(b, 1070, 1000);
  b.player.x = 800;
  b.walls = [
    { x: 1040, y: 900, w: 12, h: 200, hp: 999, maxHp: 999, steel: true },
  ];
  b.mines = [
    {
      id: 80,
      x: 1000,
      y: 1000,
      enemy: false,
      owner: 0,
      damage: 500,
      armedAt: 0,
      expiresAt: 99,
    },
  ];
  const hp = covered.hp;
  b.step(0, idle);
  assert.equal(trigger.hp, 0);
  assert.equal(covered.hp, hp);
});
test('enemy AI lays mines with a cooldown and global limits', () => {
  const b = arena(),
    e = enemy(b, 1300, 1000, 3);
  Object.assign(e, { stun: 0, mineReadyAt: 0, cooldown: 99 });
  b.step(0.01, idle);
  assert.equal(b.mines.length, 1);
  assert(b.mines[0].enemy);
  seconds(b, 0.4);
  assert.equal(b.mines.length, 1);
  for (let i = 0; i < 40; i++) {
    b.player.x = 500 + i * 40;
    b.mineCd = 0;
    b.mineAmmo = 8;
    b.layMine();
  }
  assert(b.mines.length <= 32);
  assert(b.mines.filter((m) => m.owner === 0).length <= 8);
});
test('pause and terminal states freeze mine time and forbid new placement', () => {
  const b = arena();
  b.layMine();
  b.paused = true;
  const before = JSON.stringify(b);
  seconds(b, 1, { ...idle, mine: true, emp: true });
  assert.equal(JSON.stringify(b), before);
  assert(!b.layMine());
  b.paused = false;
  b.finish(false);
  assert(!b.layMine());
});
test('expired mines disappear and kill resupply stays bounded', () => {
  const b = arena();
  b.layMine();
  b.mines[0].expiresAt = 0.1;
  seconds(b, 0.2);
  assert.equal(b.mines.length, 0);
  const before = b.mineAmmo;
  for (let i = 0; i < 3; i++) b.hitEnemy(enemy(b, 1300 + i * 100, 1000), 99999);
  assert.equal(b.mineAmmo, before + 1);
});
test('R3 uses a press edge, not a held-button repeat', () => {
  const reader = new PadReader();
  const pad = {
    index: 0,
    id: 'test',
    mapping: 'standard',
    connected: true,
    axes: [0, 0, 0, 0],
    buttons: Array.from({ length: 17 }, () => ({ pressed: false, value: 0 })),
  };
  reader.sample([pad], 0);
  pad.buttons[11] = { pressed: true, value: 1 };
  assert(reader.sample([pad], 1).mine);
  assert(!reader.sample([pad], 2).mine);
});
test('seven shot samples have bounded peaks, silent endpoints, and distinct fingerprints', () => {
  for (const rate of [22050, 32000, 44100, 48000]) {
    const fingerprints = new Set();
    for (let weapon = 0; weapon < 7; weapon++) {
      const samples = weaponRecording(weapon, rate);
      assert.equal(samples.length, Math.ceil(SHOT_SECONDS[weapon] * rate));
      let peak = 0,
        energy = 0;
      for (const s of samples) {
        assert(Number.isFinite(s));
        peak = Math.max(peak, Math.abs(s));
        energy += s * s;
      }
      assert(peak <= 0.881 && energy > 1);
      assert(samples[0] === 0);
      assert(samples.at(-1) === 0);
      fingerprints.add(samples.slice(10, 40).join(','));
    }
    assert.equal(fingerprints.size, 7);
  }
});
console.log(`\n${passed} web upgrade checks passed.`);
