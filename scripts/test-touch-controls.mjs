import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import vm from 'node:vm';
import ts from 'typescript';

// Run the production pointer handlers; replace only DOM/capture/audio boundaries.
const filename = 'components/game/battle-game.tsx';
const source = await fs.readFile(filename, 'utf8');
const ast = ts.createSourceFile(
  filename,
  source,
  ts.ScriptTarget.ES2022,
  true,
  ts.ScriptKind.TSX,
);
const handlers = new Map();
function visit(node) {
  if (
    ts.isVariableDeclaration(node) &&
    node.initializer &&
    ts.isArrowFunction(node.initializer)
  )
    handlers.set(node.name.getText(ast), node.initializer.getText(ast));
  ts.forEachChild(node, visit);
}
visit(ast);
const ref = (current) => ({ current });
function target(left = 0) {
  const properties = new Map();
  return {
    captured: null,
    getBoundingClientRect: () => ({ left, top: 0, width: 100, height: 100 }),
    setPointerCapture(id) {
      this.captured = id;
    },
    style: { setProperty: (name, value) => properties.set(name, value) },
    properties,
  };
}
const move = target(),
  aim = target(300);
const context = vm.createContext({
  paused: false,
  loading: false,
  loadError: '',
  stickPointers: ref({ move: null, aim: null }),
  touch: ref({ x: 0, y: 0 }),
  touchAim: ref({ x: 0, y: -1, fire: false }),
  aimSource: ref('mouse'),
  sound: ref({ unlock() {} }),
  mouseFire: ref(false),
  firingPointer: ref(null),
  controls: ref({ aim: null }),
  keys: new Set(),
  pad: null,
  document: { querySelectorAll: () => [move, aim] },
  fixed: { reset() {} },
  pacer: { reset() {} },
});
for (const name of ['stick', 'stickStart', 'stickEnd', 'clear', 'up']) {
  assert(handlers.has(name), `${name} production handler exists`);
  context[name] = vm.runInContext(
    ts.transpileModule(`(${handlers.get(name)})`, {
      compilerOptions: { target: ts.ScriptTarget.ES2022 },
    }).outputText,
    context,
  );
}
const event = (pointerId, currentTarget, x = 50, y = 50) => ({
  pointerId,
  currentTarget,
  clientX: x + currentTarget.getBoundingClientRect().left,
  clientY: y,
});
context.stickStart(event(11, move, 53));
assert.equal(
  context.touch.current.x,
  0,
  'resting-thumb jitter must not move the tank',
);
context.stick(event(11, move, 67.5));
assert(
  context.touch.current.x > 0 && context.touch.current.x < 0.5,
  'partial travel is gradual',
);
context.stick(event(11, move, 120, 120));
assert(
  Math.abs(Math.hypot(context.touch.current.x, context.touch.current.y) - 1) <
    1e-9,
  'diagonal speed is capped',
);
context.stickStart(event(22, aim, 50, 15), true);
assert.equal(
  context.touchAim.current.fire,
  true,
  'second finger aims and fires while moving',
);
assert.equal(context.touchAim.current.y, -1);
assert.equal(move.captured, 11);
assert.equal(aim.captured, 22);
context.stickEnd(event(99, move));
context.stick(event(99, aim), true);
context.stickStart(event(33, move));
assert.equal(
  context.stickPointers.current.move,
  11,
  'foreign fingers cannot steal movement',
);
assert.equal(
  context.touchAim.current.fire,
  true,
  'foreign release cannot stop another thumb',
);
context.stickEnd(event(11, move));
assert.equal(context.touch.current.x, 0);
assert.equal(context.touch.current.y, 0);
assert.equal(
  context.touchAim.current.fire,
  true,
  'releasing movement leaves aiming active',
);
context.stick(event(22, aim, 52), true);
assert.equal(context.touchAim.current.fire, false, 'centering aim stops fire');
context.stick(event(22, aim, 50, 120), true);
context.stickEnd(event(22, aim), true);
assert.equal(
  context.touchAim.current.fire,
  false,
  'up/cancel/lost capture stops firing',
);
assert.equal(aim.properties.get('--sy'), '0px');
context.stickStart(event(41, move, 85));
context.stickStart(event(42, aim, 85), true);
context.mouseFire.current = true;
context.firingPointer.current = 43;
context.controls.current = { aim: null, mine: true, emp: true, dash: true };
context.clear();
assert.equal(context.touch.current.x, 0, 'rotation/pause clears movement');
assert.equal(
  context.touchAim.current.fire,
  false,
  'rotation/pause clears aim fire',
);
assert.equal(context.mouseFire.current, false);
assert.equal(context.firingPointer.current, null);
assert.equal(context.stickPointers.current.move, null);
assert.equal(context.stickPointers.current.aim, null);
assert(
  !context.controls.current.mine && !context.controls.current.emp,
  'queued abilities are cleared',
);
context.stick(event(41, move, 85));
assert.equal(
  context.touch.current.x,
  0,
  'old pointer cannot move after viewport change',
);
context.stickStart(event(51, move, 85));
assert.equal(context.touch.current.x, 1, 'a fresh touch works after rotation');
context.clear();
for (const state of ['paused', 'loading', 'loadError']) {
  context[state] = state === 'loadError' ? 'failed' : true;
  context.stickStart(event(61, move, 85));
  context.stickStart(event(62, aim, 85), true);
  assert.equal(
    context.stickPointers.current.move,
    null,
    `${state} rejects movement`,
  );
  assert.equal(context.touchAim.current.fire, false, `${state} rejects firing`);
  context[state] = state === 'loadError' ? '' : false;
}
context.mouseFire.current = true;
context.firingPointer.current = 71;
context.up({ pointerId: 72 });
assert.equal(context.mouseFire.current, true);
context.up({ pointerId: 71 });
assert.equal(
  context.mouseFire.current,
  false,
  'global pointer cancellation releases auto fire',
);
console.log(
  'PASS: touch dead zone, normalized speed, simultaneous thumbs, capture ownership, release/cancel, pause/resize reset, inactive input and auto fire',
);
