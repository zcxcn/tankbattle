import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import vm from 'node:vm';
import { pathToFileURL } from 'node:url';
import ts from 'typescript';

const root = path.resolve('outputs/test-battle-hud');
await fs.mkdir(root, { recursive: true });
for (const name of [
  'campaign',
  'terrain',
  'navigation',
  'progression',
  'engine',
  'fixed-step',
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
      (_, q, p) => `from ${q}${p}.js${q}`,
    );
  await fs.writeFile(path.join(root, `${name}.js`), js);
}
const { Battle } = await import(pathToFileURL(path.join(root, 'engine.js')));
const { FixedStep } = await import(
  pathToFileURL(path.join(root, 'fixed-step.js'))
);
const { defaultSave } = await import(
  pathToFileURL(path.join(root, 'campaign.js'))
);

// Exercise the real frame loop with a real combat simulation. Only the browser
// rendering/audio boundary is replaced, so the test catches stale snapshots
// without duplicating the production condition or requiring a WebGL browser.
const filename = 'components/game/battle-game.tsx';
const source = await fs.readFile(filename, 'utf8');
const ast = ts.createSourceFile(
  filename,
  source,
  ts.ScriptTarget.ES2022,
  true,
  ts.ScriptKind.TSX,
);
let frameLoop, keydownSource;
function visit(node) {
  if (
    ts.isVariableDeclaration(node) &&
    node.initializer &&
    ts.isArrowFunction(node.initializer)
  ) {
    if (node.name.getText(ast) === 'loop')
      frameLoop = node.initializer.getText(ast);
    if (node.name.getText(ast) === 'keydown')
      keydownSource = node.initializer.getText(ast);
  }
  ts.forEachChild(node, visit);
}
visit(ast);
assert(frameLoop, 'battle animation loop must exist');
const javascript = ts.transpileModule(`(${frameLoop})`, {
  compilerOptions: {
    target: ts.ScriptTarget.ES2022,
    module: ts.ModuleKind.ES2022,
  },
}).outputText;

for (const outcome of ['defeat', 'victory']) {
  const battle = new Battle(
    0,
    false,
    { ...defaultSave, kills: 0, upgrades: [0, 0, 0, 0, 0, 0] },
    2049,
    outcome,
  );
  battle.walls = [];
  battle.pickups = [];
  battle.spawnTimer = Infinity;
  battle.bossSpawned = true;
  battle.spawned = battle.target;
  battle.elapsed = 27;
  battle.player.x = 500;
  battle.player.y = 500;
  battle.player.hp = outcome === 'defeat' ? 11 : battle.player.maxHp;
  battle.shield = 0;
  const boss = battle.boss;
  if (outcome === 'defeat') battle.enemies = [];
  else {
    Object.assign(boss, {
      x: 650,
      y: 500,
      hp: 10,
      maxHp: 10,
      spawn: 0,
      stun: Infinity,
      cooldown: Infinity,
      mineReadyAt: Infinity,
    });
    battle.enemies = [boss];
  }
  const snapshots = [],
    results = [],
    music = [];
  const controls = {
    current: { x: 0, y: 0, aim: null, fire: false, dash: false, emp: false },
  };
  const context = {
    b: battle,
    disposed: false,
    r: {
      draw() {},
      pointer() {
        return null;
      },
    },
    frame: 0,
    requestAnimationFrame: () => 1,
    document: { hidden: false },
    deviceState: { background: false },
    errorRef: { current: '' },
    reported: false,
    finaleStarted: 0,
    previous: 0,
    nextHud: 0,
    nextBudget: Infinity,
    initialized: true,
    mobile: false,
    policy: { fps: 60 },
    pacer: { take: () => true, reset() {} },
    fixed: new FixedStep(),
    controls,
    keys: new Set(),
    touch: { current: { x: 0, y: 0 } },
    pad: null,
    mouseFire: { current: false },
    touchAim: { current: { fire: false } },
    aimSource: { current: 'mouse' },
    pointerScreen: { current: null },
    renderDirty: { current: false },
    radio: { update: () => null },
    a: { setMotion() {}, radioBusy: false },
    clear() {},
    musicCallback: { current: (scene) => music.push(scene) },
    callback: { current: (result) => results.push(result) },
    setHud: (snapshot) => snapshots.push(snapshot),
  };
  const loop = vm.runInNewContext(javascript, context, { filename });
  context.loop = loop;
  loop(1); // Publish a normal HUD; no complete simulation step has elapsed.
  assert.equal(snapshots.length, 1);
  assert.equal(snapshots[0].hp, battle.player.hp);
  if (outcome === 'victory') assert.equal(snapshots[0].boss, 10);

  const target = outcome === 'defeat' ? battle.player : boss;
  battle.bullets.push({
    x: target.x,
    y: target.y,
    vx: 600,
    vy: 0,
    damage: 30,
    enemy: outcome === 'defeat',
    life: 2,
    weapon: 0,
  });
  loop(18); // Decisive hit lands well before the next normal HUD tick (101 ms).
  assert.equal(battle.result?.won, outcome === 'victory');
  assert.equal(
    snapshots.length,
    2,
    'the terminal frame must publish its final HUD immediately',
  );
  const finalHud = snapshots.at(-1),
    finalTime = battle.elapsed;
  assert.equal(finalHud.hp, battle.result.hp);
  assert.equal(finalHud.time, battle.result.time);
  assert.equal(finalHud.kills, battle.result.kills);
  if (outcome === 'defeat') assert.equal(finalHud.hp, 0);
  else {
    assert.equal(finalHud.boss, 0);
    assert.equal(finalHud.bossMax, 0);
    assert.equal(finalHud.kills, 1);
  }
  loop(30);
  loop(900);
  loop(1000);
  assert.equal(
    battle.elapsed,
    finalTime,
    'the finale must not advance the combat clock',
  );
  assert.equal(results.length, 1, 'the result must be delivered once');
  assert.equal(results[0], battle.result);
  assert.equal(
    snapshots.length,
    2,
    'the final snapshot stays stable during the finale',
  );
  assert.equal(music.at(-1), outcome);
  console.log(
    `PASS: ${outcome} publishes final HP, time and Boss state between HUD ticks`,
  );
}

assert(keydownSource, 'battle keyboard handler must exist');
const keyboardJavascript = ts.transpileModule(`(${keydownSource})`, {
  compilerOptions: {
    target: ts.ScriptTarget.ES2022,
    module: ts.ModuleKind.ES2022,
  },
}).outputText;
// The handler only needs DOM ancestry/selector matching. Keep that boundary
// minimal while executing its actual preventDefault and command dispatch.
class ElementStub {
  constructor(tag, attributes = {}, parent = null) {
    this.tag = tag;
    this.attributes = attributes;
    this.parent = parent;
  }
  closest(selectors) {
    for (let node = this; node; node = node.parent)
      for (const selector of selectors
        .split(',')
        .map((value) => value.trim())) {
        if (selector === node.tag) return node;
        const attribute = selector.match(/^\[([^=]+)="([^"]*)"\]$/);
        if (attribute && node.attributes[attribute[1]] === attribute[2])
          return node;
      }
    return null;
  }
}
const battle = { paused: false, result: null },
  controls = { current: {} },
  keys = new Set(),
  calls = { camera: 0, fullscreen: 0, unlock: 0, pause: 0 };
const keyboardContext = {
  b: battle,
  initialized: true,
  Element: ElementStub,
  controls,
  keys,
  pause(value) {
    battle.paused = value;
    calls.pause++;
  },
  switchCamera() {
    calls.camera++;
  },
  fullscreen() {
    calls.fullscreen++;
  },
  a: {
    unlock() {
      calls.unlock++;
    },
  },
};
const keydown = vm.runInNewContext(keyboardJavascript, keyboardContext, {
  filename,
});
const button = new ElementStub('button');
function press(key, target = button, overrides = {}) {
  const event = {
    key,
    target,
    repeat: false,
    defaultPrevented: false,
    preventDefault() {
      this.defaultPrevented = true;
    },
    ...overrides,
  };
  keydown(event);
  return event;
}
assert(press(' ').defaultPrevented);
assert.equal(
  controls.current.dash,
  true,
  'Space must still dash in an active battle',
);
controls.current.dash = false;
press(' ', button, { repeat: true });
assert.equal(
  controls.current.dash,
  false,
  'holding Space must not queue repeated dashes',
);
press('c');
press('f');
assert.equal(calls.camera, 1);
assert.equal(calls.fullscreen, 1);

for (const state of ['paused', 'result', 'loading']) {
  battle.paused = state === 'paused';
  battle.result = state === 'result' ? { won: false } : null;
  keyboardContext.initialized = state !== 'loading';
  controls.current = {};
  keys.clear();
  const before = { ...calls };
  for (const key of [' ', 'c', 'f', 'w', 'e', 'm', '1'])
    assert.equal(
      press(key).defaultPrevented,
      false,
      `${state}: ${key} must remain available to the UI`,
    );
  assert.deepEqual(controls.current, {});
  assert.equal(keys.size, 0);
  assert.deepEqual(
    calls,
    before,
    `${state}: camera/fullscreen/combat must stay inactive`,
  );
}
battle.paused = false;
battle.result = null;
keyboardContext.initialized = true;
for (const target of [
  new ElementStub('input'),
  new ElementStub('input', { disabled: '' }),
  new ElementStub('textarea'),
  new ElementStub('select'),
  new ElementStub(
    'span',
    {},
    new ElementStub('div', { contenteditable: 'true' }),
  ),
  new ElementStub('span', {}, new ElementStub('div', { contenteditable: '' })),
  new ElementStub('button', {}, new ElementStub('div', { role: 'dialog' })),
  new ElementStub(
    'button',
    {},
    new ElementStub('div', { role: 'alertdialog' }),
  ),
]) {
  controls.current = {};
  keys.clear();
  const before = { ...calls };
  for (const key of [' ', 'c', 'f', 'w', 'e', 'm', '1', 'Escape'])
    assert.equal(
      press(key, target).defaultPrevented,
      false,
      `focused ${target.tag} must own ${key}`,
    );
  assert.deepEqual(controls.current, {});
  assert.equal(keys.size, 0);
  assert.deepEqual(calls, before);
}
const beforeHandled = { ...calls };
press('c', button, { defaultPrevented: true });
assert.deepEqual(
  calls,
  beforeHandled,
  'already handled UI keys must not dispatch combat shortcuts',
);
assert(press('Escape').defaultPrevented);
assert.equal(battle.paused, true, 'Escape must still pause active combat');
console.log(
  'PASS: dialogs and form controls retain Space/C/F while active battle shortcuts still work',
);
