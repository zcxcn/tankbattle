import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import ts from 'typescript';

const output = path.resolve('outputs/test-tactical-radio');
await fs.mkdir(output, { recursive: true });
for (const name of [
  'campaign',
  'battlefields',
  'terrain',
  'navigation',
  'performance',
  'progression',
  'engine',
  'tactical-radio',
]) {
  const source = await fs.readFile(`lib/${name}.ts`, 'utf8');
  await fs.writeFile(
    path.join(output, `${name}.mjs`),
    ts
      .transpileModule(source, {
        compilerOptions: {
          module: ts.ModuleKind.ES2022,
          target: ts.ScriptTarget.ES2022,
        },
      })
      .outputText.replace(
        /from (['"])(\.{1,2}\/[^'"]+)\1/g,
        (_, quote, url) => `from ${quote}${url}.mjs${quote}`,
      ),
  );
}
const { TacticalRadioDirector, RADIO_LINES } = await import(
  pathToFileURL(path.join(output, 'tactical-radio.mjs'))
);
const enemy = (id = 1, x = 1000, kind = 0) => ({
  id,
  x,
  y: 0,
  hp: 100,
  maxHp: 100,
  kind,
  spawn: 0,
  attackWindup: 0,
});
const mine = (id = 1, isEnemy = true, x = 100) => ({
  id,
  enemy: isEnemy,
  owner: isEnemy ? 1 : 0,
  x,
  y: 0,
  armedAt: 0,
  expiresAt: 100,
  damage: 75,
});
const fixture = () => {
  const b = {
    elapsed: 0,
    paused: false,
    result: null,
    player: { x: 0, y: 0, hp: 100, maxHp: 100 },
    enemies: [],
    walls: [],
    kills: 0,
    bossDefeated: false,
    bossThreshold: 0,
    get boss() {
      return this.enemies.find((e) => e.kind === 3 && e.hp > 0);
    },
    empCd: 0,
    ammo: [Infinity, 0, 0, 0, 0, 0, 0],
    mines: [],
    objectives: [],
  };
  const radio = new TacticalRadioDirector();
  const next = (time, patch) => {
    Object.assign(b, patch);
    b.elapsed = time;
    return radio.update(b)?.id ?? null;
  };
  return { b, radio, next };
};
let passed = 0;
const test = (name, fn) => {
  fn();
  console.log('PASS ' + name);
  passed++;
};

test('all bundled tactical lines are short English cues with stable IDs', () => {
  assert.equal(Object.keys(RADIO_LINES).length, 21);
  for (const [id, line] of Object.entries(RADIO_LINES)) {
    assert.match(id, /^[a-z_]+$/);
    assert.match(line, /^[A-Za-z ,.]+\.$/);
    assert(line.length < 70);
  }
});
test('command starts once and an initial visible nearby Boss is announced after a clean gap', () => {
  const { b, next } = fixture();
  b.enemies = [enemy(3, 600, 3)];
  assert.equal(next(0), 'command_online');
  assert.equal(next(1), null);
  assert.equal(next(4), 'boss_detected');
  assert.equal(next(10), null);
});
test('a distant Boss stays silent and is detected only once on a later clear approach', () => {
  const { b, next } = fixture();
  b.enemies = [enemy(3, 1500, 3)];
  assert.equal(next(0), 'command_online');
  assert.equal(next(4), null);
  assert.equal(next(20), null);
  b.boss.x = 600;
  assert.equal(next(21), 'boss_detected');
  b.boss.x = 1500;
  next(26);
  b.boss.x = 600;
  assert.equal(next(31), null);
});
test('Boss detection waits for a live, spawned target and clear sight through cover', () => {
  const { b, next } = fixture();
  b.enemies = [{ ...enemy(3, 600, 3), spawn: 1 }];
  next(0);
  assert.equal(next(4), null);
  b.boss.spawn = 0;
  b.walls = [
    { x: 280, y: -20, w: 40, h: 40, hp: 50, kind: 'hill', shape: 'ellipse' },
  ];
  assert.equal(next(5), null);
  b.walls[0].kind = 'water';
  assert.equal(
    next(6),
    'boss_detected',
    'water does not obstruct visual detection',
  );
});
test('blocked pending detection is dropped and can requeue after sight clears', () => {
  const { b, next } = fixture();
  b.enemies = [enemy(3, 600, 3)];
  next(0);
  b.walls = [{ x: 280, y: -20, w: 40, h: 40, hp: 50, kind: 'building' }];
  assert.equal(next(1), null);
  assert.equal(next(4), null);
  b.walls[0].hp = 0;
  assert.equal(next(5), 'boss_detected');
  b.enemies = [enemy(4, 600, 3)];
  assert.equal(
    next(10),
    'boss_detected',
    'a different encountered Boss is announced once',
  );
});
test('proximity ignores distant, dead, and spawning units', () => {
  const { b, next } = fixture();
  next(0);
  b.enemies = [
    enemy(),
    { ...enemy(2, 100), hp: 0 },
    { ...enemy(3, 100), spawn: 1 },
  ];
  assert.equal(next(5), null);
  b.enemies[0].x = 420;
  assert.equal(next(6), 'enemy_approaching');
  assert.equal(next(24), null);
});
test('enemy proximity uses hysteresis, clear time, and a repeat cooldown', () => {
  const { b, next } = fixture();
  next(0);
  b.enemies = [enemy(1, 420)];
  assert.equal(next(5), 'enemy_approaching');
  b.enemies[0].x = 500;
  next(12);
  b.enemies[0].x = 420;
  assert.equal(next(24), null);
  b.enemies[0].x = 700;
  next(25);
  b.enemies[0].x = 420;
  assert.equal(next(26), null);
  b.enemies[0].x = 700;
  next(30);
  next(33);
  b.enemies[0].x = 420;
  assert.equal(next(34), 'enemy_approaching');
});
test('proximity event is dropped when the threat leaves before the radio gap', () => {
  const { b, next } = fixture();
  next(0);
  b.enemies = [enemy(1, 200)];
  next(1);
  b.enemies = [];
  assert.equal(next(4), null);
});
test('one enemy kill is acknowledged once after the grouping window', () => {
  const { next } = fixture();
  next(0);
  assert.equal(next(5, { kills: 1 }), null);
  assert.equal(next(5.8), 'target_destroyed');
  assert.equal(next(15), null);
});
test('rapid kills coalesce into one multi-target line and suppress kill spam', () => {
  const { next } = fixture();
  next(0);
  next(5, { kills: 1 });
  next(5.2, { kills: 3 });
  assert.equal(next(5.8), 'multiple_targets');
  next(6, { kills: 4 });
  assert.equal(next(7), null);
  assert.equal(next(10), null);
  next(14, { kills: 5 });
  assert.equal(next(15), 'target_destroyed');
});
test('critical armor takes precedence over all coincident chatter', () => {
  const { b, next } = fixture();
  next(0);
  b.player.hp = 15;
  b.enemies = [enemy(1, 100)];
  b.mines = [mine()];
  b.kills = 2;
  assert.equal(next(5), 'armor_critical');
  assert.equal(next(6), null);
});
test('critical armor can interrupt ordinary radio after 350 milliseconds', () => {
  const { b, next } = fixture();
  next(0);
  b.player.hp = 10;
  assert.equal(next(0.1), null);
  assert.equal(next(0.4), 'armor_critical');
  assert.equal(next(5), null);
});
test('armor warnings remain urgent and attack windup never triggers barrage chatter', () => {
  const { b, next } = fixture();
  b.enemies = [enemy(3, 600, 3)];
  next(0);
  assert.equal(next(4), 'boss_detected');
  b.boss.attackWindup = 0.8;
  assert.equal(next(4.5), null);
  b.player.hp = 10;
  assert.equal(next(4.6), 'armor_critical');
  b.boss.attackWindup = 0;
  assert.equal(next(5), null);
  b.boss.attackWindup = 0.8;
  assert.equal(next(5.4), null);
});
test('selected cues retain condition checks and a bounded decode deadline', () => {
  const { b, radio, next } = fixture();
  next(0);
  b.enemies = [enemy(1, 200)];
  b.elapsed = 5;
  const approaching = radio.update(b);
  assert.equal(approaching.id, 'enemy_approaching');
  assert.equal(approaching.maxDelayMs, 2000);
  assert.equal(approaching.valid(), true);
  b.enemies = [];
  assert.equal(approaching.valid(), false);
  b.player.hp = 10;
  b.elapsed = 6;
  const critical = radio.update(b);
  assert.equal(critical.id, 'armor_critical');
  assert.equal(critical.valid(), true);
  b.player.hp = 90;
  assert.equal(critical.valid(), false);
});
test('selected Boss detection remains valid only while the same target is visible nearby', () => {
  const { b, radio, next } = fixture();
  b.enemies = [enemy(3, 600, 3)];
  next(0);
  b.elapsed = 4;
  const detection = radio.update(b);
  assert.equal(detection.id, 'boss_detected');
  assert.equal(detection.valid(), true);
  b.boss.x = 1000;
  assert.equal(detection.valid(), false);
  b.boss.x = 600;
  b.walls = [{ x: 280, y: -20, w: 40, h: 40, hp: 50, kind: 'building' }];
  assert.equal(detection.valid(), false);
  b.walls = [];
  b.paused = true;
  assert.equal(detection.valid(), false);
});
test('repairs invalidate pending warnings and rearm armor threshold detection', () => {
  const { b, next } = fixture();
  next(0);
  b.player.hp = 35;
  assert.equal(next(1), null);
  b.player.hp = 90;
  assert.equal(next(2), null);
  assert.equal(next(4), 'armor_restored');
  b.player.hp = 30;
  assert.equal(next(9), 'armor_low');
  b.player.hp = 10;
  assert.equal(next(10), 'armor_critical');
});
test('Boss escalation coalesces phase changes and is invalidated by death', () => {
  const { b, next } = fixture();
  next(0);
  b.enemies = [enemy(3, 600, 3)];
  assert.equal(next(4), 'boss_detected');
  next(5, { bossThreshold: 1 });
  next(6, { bossThreshold: 2 });
  assert.equal(next(8), 'boss_final_assault');
  b.enemies = [];
  assert.equal(next(12, { bossDefeated: true, kills: 1 }), 'boss_destroyed');
  assert.equal(next(16), null);
});
test('Boss destruction supersedes pending ordinary kills and coincident multi-kills', () => {
  const { b, next } = fixture();
  b.enemies = [enemy(3, 600, 3)];
  next(0);
  next(4);
  next(5, { kills: 1 });
  next(5.8);
  b.enemies = [];
  next(6, { kills: 4, bossDefeated: true });
  assert.equal(next(8), 'boss_destroyed');
  assert.equal(next(12), null);
});
test('phase one identifies reinforcements without inventing ordinary spawn events', () => {
  const { b, next } = fixture();
  b.enemies = [enemy(3, 600, 3)];
  next(0);
  next(4);
  assert.equal(next(8, { bossThreshold: 1 }), 'boss_escalating');
  b.enemies.push(enemy(4, 1000));
  assert.equal(next(12), null);
});
test('repeated local and distant Boss windups never produce barrage speech or text', () => {
  const { b, radio, next } = fixture();
  b.enemies = [enemy(3, 600, 3)];
  next(0);
  next(4);
  for (const x of [600, 1800]) {
    b.boss.x = x;
    for (let index = 0; index < 8; index++) {
      b.elapsed += 3;
      b.boss.attackWindup = index % 2 ? 0 : 0.8;
      const cue = radio.update(b);
      assert.notEqual(cue?.id, 'incoming_barrage');
      assert(!cue?.text.includes('barrage'));
    }
  }
});
test('mine deployment follows a new friendly mine, without inventory false positives', () => {
  const { b, next } = fixture();
  next(0);
  b.mines = [mine(1, false)];
  assert.equal(next(5), 'mine_deployed');
  b.mines = [];
  assert.equal(next(10), null);
});
test('hostile mines warn once until the player leaves the larger safety radius', () => {
  const { b, next } = fixture();
  next(0);
  b.mines = [mine(1, true)];
  assert.equal(next(5), 'hostile_mines');
  assert.equal(next(24), null);
  b.player.x = 600;
  next(25);
  b.player.x = 0;
  assert.equal(next(26), 'hostile_mines');
});
test('EMP reports clearing only when observed nearby mines disappear', () => {
  const { b, next } = fixture();
  next(0);
  b.mines = [mine(1, false)];
  next(1);
  b.mines = [];
  assert.equal(next(5, { empCd: 13 }), 'mines_cleared');
  next(18, { empCd: 0 });
  assert.equal(next(19, { empCd: 13 }), 'pulse_activated');
});
test('mine detonation, expiration, and distant removal do not claim EMP clearing', () => {
  for (const oldMine of [
    mine(1, false, 800),
    { ...mine(1, false), expiresAt: 4 },
  ]) {
    const { b, next } = fixture();
    next(0);
    b.mines = [oldMine];
    next(1);
    b.mines = [];
    assert.equal(next(5, { empCd: 13 }), 'pulse_activated');
  }
  const { b, next } = fixture();
  b.mines = [mine()];
  next(0);
  b.mines = [];
  assert.notEqual(next(5), 'mines_cleared');
});
test('special ammo exhaustion is detected despite automatic weapon fallback', () => {
  const { b, next } = fixture();
  b.ammo[1] = 5;
  next(0);
  b.ammo[1] = 3;
  assert.equal(next(5), 'ammo_low');
  b.ammo[1] = 0;
  b.weapon = 0;
  assert.equal(next(9), 'ammo_depleted');
  assert.equal(next(14), null);
});
test('resupply cancels pending ammo warnings and depletion outranks simultaneous low ammo', () => {
  const { b, next } = fixture();
  b.ammo[1] = 5;
  b.ammo[2] = 5;
  next(0);
  b.ammo[1] = 0;
  next(1);
  b.ammo[1] = 10;
  assert.equal(next(4), null);
  b.ammo[1] = 0;
  b.ammo[2] = 2;
  assert.equal(next(5), 'ammo_depleted');
});
test('objectives are announced on completion once; exit markers do not fake captures', () => {
  const { b, next } = fixture();
  b.objectives = [
    { id: 1, kind: 'capture', done: false },
    { id: 2, kind: 'exit', done: false },
  ];
  next(0);
  b.objectives[0].done = true;
  assert.equal(next(5), 'objective_secured');
  assert.equal(next(10), null);
  b.objectives[1].done = true;
  assert.equal(next(15), null);
});
test('pause freezes observations and completion clears all pending lines exactly once', () => {
  const { b, next } = fixture();
  next(0);
  b.paused = true;
  b.player.hp = 10;
  assert.equal(next(0), null);
  b.paused = false;
  assert.equal(next(0.4), 'armor_critical');
  assert.equal(next(0.5, { result: { won: true } }), 'mission_complete');
  assert.equal(next(10), null);
  const failed = fixture();
  assert.equal(failed.next(0, { result: { won: false } }), 'mission_failed');
});

console.log(`Tactical radio: ${passed} tests passed.`);
