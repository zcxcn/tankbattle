import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import vm from 'node:vm';
import ts from 'typescript';

const filename = 'components/game/battle-game.tsx';
const source = await fs.readFile(filename, 'utf8');
const ast = ts.createSourceFile(filename, source, ts.ScriptTarget.ES2022, true, ts.ScriptKind.TSX);
const functions = new Map();
const arrows = new Map();
const listeners = new Map();
function visit(node) {
  if (ts.isFunctionDeclaration(node) && node.name) functions.set(node.name.text, node.getText(ast));
  if (ts.isVariableDeclaration(node) && node.initializer && ts.isArrowFunction(node.initializer))
    arrows.set(node.name.getText(ast), node.initializer.getText(ast));
  if (ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression) &&
    node.expression.name.text === 'on' && ts.isStringLiteral(node.arguments[0]) &&
    ts.isArrowFunction(node.arguments[1])) {
    const event = node.arguments[0].text;
    listeners.set(event, [...(listeners.get(event) ?? []), node.arguments[1].getText(ast)]);
  }
  ts.forEachChild(node, visit);
}
visit(ast);
const compile = (typescript) => ts.transpileModule(typescript, {
  compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 },
}).outputText;
const evaluate = (expression, context) => vm.runInNewContext(compile(`(${expression})`), context, { filename });
const helpers = vm.runInNewContext(compile([
  functions.get('createNetworkSnapshot'),
  functions.get('snapshotSequenceOf'),
  functions.get('sendGuestActions'),
  functions.get('parseRemoteAction'),
  functions.get('mergeQueuedActions'),
  '({createNetworkSnapshot,snapshotSequenceOf,sendGuestActions,parseRemoteAction,mergeQueuedActions})',
].join('\n')), { WEAPONS: Array(7) }, { filename });
assert(helpers.sendGuestActions && helpers.mergeQueuedActions && helpers.parseRemoteAction);

const outgoing = [];
const controls = { x: 0.6, y: -0.4, aim: { x: 100, y: 200 }, fire: true,
  dash: true, emp: true, support: true, mine: true, weapon: 2, nextWeapon: true };
helpers.sendGuestActions(controls, (action) => { outgoing.push(action); return false; });
assert.equal(controls.weapon, 2, 'an action remains pending when reliable channel is unavailable');
assert.equal(controls.dash, true);
assert.equal(outgoing.length, 1, 'later actions cannot overtake a failed reliable send');
helpers.sendGuestActions(controls, (action) => { outgoing.push(action); return true; });
assert.equal(controls.weapon, undefined);
for (const key of ['dash', 'emp', 'support', 'mine', 'nextWeapon']) assert.equal(controls[key], false);
const sent = outgoing.length;
helpers.sendGuestActions(controls, (action) => { outgoing.push(action); return true; });
assert.equal(outgoing.length, sent, 'an accepted action is never sent twice');
assert.equal(helpers.parseRemoteAction({ type: 'action', action: 'weapon', weapon: 2 }).weapon, 2);
assert.equal(helpers.parseRemoteAction({ type: 'action', action: 'weapon', weapon: 999 }), null);
assert.equal(helpers.parseRemoteAction({ type: 'action', action: 'dash', weapon: 999 }).action, 'dash');

const remoteActions = new Map();
const remoteInputs = new Map();
const roster = { host: 0, guest: -10 };
const session = { role: 'host', peers: new Map([['guest', {}]]) };
const hostInput = evaluate(listeners.get('input')[0], {
  roster, remoteInputs, W: 2000, H: 1400, performance: { now: () => 10 },
});
hostInput({ peerId: 'guest', input: { x: 0.5, y: -0.5, aim: { x: 500, y: 300 },
  fire: true, dash: true, emp: true, support: true, mine: true, weapon: 6, nextWeapon: true } });
assert.equal(remoteInputs.get(-10).input.fire, true);
for (const key of ['dash', 'emp', 'support', 'mine', 'nextWeapon'])
  assert.equal(remoteInputs.get(-10).input[key] ?? false, false,
    `${key} cannot sneak through the unreliable realtime channel`);
assert.equal(remoteInputs.get(-10).input.weapon, undefined);

const hostControl = evaluate(listeners.get('control')[0], {
  roster, session, remoteActions, parseRemoteAction: helpers.parseRemoteAction,
});
for (const action of [
  { type: 'action', action: 'dash' },
  { type: 'action', action: 'weapon', weapon: 1 },
  { type: 'action', action: 'weapon', weapon: 2 },
]) hostControl({ peerId: 'guest', control: action });
hostControl({ peerId: 'guest', control: { type: 'action', action: 'weapon', weapon: 999 } });
assert.equal(remoteActions.get(-10).length, 3);

const tmp = await fs.mkdtemp(path.join(os.tmpdir(), 'tankbattle-action-test-'));
const fixedSource = await fs.readFile('lib/fixed-step.ts', 'utf8');
await fs.writeFile(path.join(tmp, 'fixed-step.mjs'), compile(fixedSource));
const { FixedStep } = await import(pathToFileURL(path.join(tmp, 'fixed-step.mjs')));
const simulated = [];
const battle = {
  elapsed: 0, paused: false, result: null,
  viewPlayer: { x: 100, y: 100, angle: 0, speed: 100 },
  step(dt, _local, remotes) {
    simulated.push(JSON.parse(JSON.stringify(remotes[-10])));
    this.elapsed += dt;
  },
};
function loopContext(role, actionQueue, received) {
  const input = { x: 0, y: 0, aim: null, fire: false, dash: false, emp: false };
  return {
    b: battle, disposed: false, r: { draw() {}, pointer() { return null; } },
    frame: 0, requestAnimationFrame: () => 1,
    document: { hidden: false }, deviceState: { background: false }, errorRef: { current: '' },
    reported: false, finaleStarted: 0, previous: 0, nextHud: Infinity, nextBudget: Infinity,
    initialized: true, mobile: false, policy: { fps: 60 }, pacer: { take: () => true, reset() {} },
    fixed: new FixedStep(), multiplayer: {
      roster, session: { ...session, role, sendInput: (value) => { received.input.push(value); return true; },
        sendControl: (value) => { received.control.push(value); return received.accept; },
        sendSnapshot() { return true; } },
    },
    controls: { current: input }, keys: new Set(), touch: { current: { x: 0, y: 0 } },
    pad: null, mouseFire: { current: false }, touchAim: { current: { fire: false } },
    aimSource: { current: 'mouse' }, pointerScreen: { current: null },
    renderDirty: { current: false }, radio: { update: () => null },
    a: { setMotion() {}, radioBusy: false }, clear() {},
    musicCallback: { current() {} }, callback: { current() {} },
    remoteInputs, remoteActions: actionQueue, mergeQueuedActions: helpers.mergeQueuedActions,
    sendGuestActions: helpers.sendGuestActions, nextInput: 0, nextSnapshot: Infinity,
    publishFinalSnapshot() {}, flushStateSnapshots() {}, pendingStateSnapshots: { current: new Map() },
  };
}
const hostContext = loopContext('host', remoteActions, { input: [], control: [], accept: true });
const hostLoop = evaluate(arrows.get('loop'), hostContext);
hostContext.loop = hostLoop;
hostLoop(1);
assert.equal(remoteActions.get(-10).length, 3, 'actions wait until a fixed simulation step runs');
hostLoop(18);
assert.equal(simulated[0].dash, true);
assert.equal(simulated[0].weapon, 1);
assert.equal(remoteActions.get(-10).length, 1, 'only actions applied in the fixed step are removed');
hostLoop(35);
assert.equal(simulated[1].dash, false, 'dash does not fire again');
assert.equal(simulated[1].weapon, 2, 'second weapon command executes on the next step');
assert.equal(remoteActions.get(-10).length, 0);
hostLoop(52);
assert.equal(simulated[2].weapon, undefined, 'weapon command does not repeat');

const received = { input: [], control: [], accept: false };
const guestContext = loopContext('guest', new Map(), received);
guestContext.controls.current.dash = true;
guestContext.controls.current.mine = true;
guestContext.controls.current.weapon = 4;
const guestLoop = evaluate(arrows.get('loop'), guestContext);
guestContext.loop = guestLoop;
guestLoop(1);
assert.equal(guestContext.controls.current.dash, true);
assert.equal(received.input.length, 1);
assert.equal(received.input[0].dash, undefined, 'realtime input excludes one-shot commands');
assert.equal(received.input[0].weapon, undefined);
received.accept = true;
guestLoop(40);
assert.equal(guestContext.controls.current.dash, false);
assert.equal(guestContext.controls.current.weapon, undefined);
const acceptedControls = received.control.length;
guestLoop(50);
assert.equal(received.control.length, acceptedControls, 'accepted one-shot is not repeated on later frames');

const finalSends = [];
const finalBattle = { result: { runId: 'run-1', won: true }, createSnapshot: () => ({ result: finalBattle.result }) };
const finalContext = {
  b: finalBattle, multiplayer: { session: { role: 'host', peers: new Map([['p1', {}], ['p2', {}]]),
    sendControl: (message, peerId) => { finalSends.push({ message, peerId }); return peerId === 'p1' || finalSends.length > 2; } } },
  finalSnapshot: null, finalRecipients: new Set(), snapshotSequence: { current: 0 },
  createNetworkSnapshot: helpers.createNetworkSnapshot,
};
const publishFinalSnapshot = evaluate(arrows.get('publishFinalSnapshot'), finalContext);
publishFinalSnapshot();
publishFinalSnapshot();
publishFinalSnapshot();
assert.deepEqual(finalSends.map((entry) => entry.peerId), ['p1', 'p2', 'p2'],
  'reliable final snapshot retries only unsent peers');
assert(finalSends.every((entry) => entry.message.type === 'final-snapshot'));
assert.equal(finalSends[0].message.snapshot.networkSequence, 1);

const stateSends = [];
let acceptState = false;
const stateBattle = { paused: false, result: null, createSnapshot() {
  return { result: null, state: { paused: this.paused } };
} };
const stateContext = {
  b: stateBattle, engine: { current: stateBattle }, errorRef: { current: '' },
  multiplayer: { session: { role: 'host', peers: new Map([['p1', {}], ['p2', {}]]),
    sendControl(message, peerId) { stateSends.push({ message, peerId }); return peerId === 'p1' || acceptState; } } },
  pendingStateSnapshots: { current: new Map() }, snapshotSequence: { current: 0 },
  createNetworkSnapshot: helpers.createNetworkSnapshot,
  sound: { current: { suspend() {}, unlock() {} } }, clearInput: { current() {} },
  mouseFire: { current: false }, controls: { current: { x: 1, y: 1 } },
  touch: { current: { x: 1, y: 1 } }, setPaused() {},
};
stateContext.flushStateSnapshots = evaluate(functions.get('flushStateSnapshots'), stateContext);
stateContext.queueStateSnapshot = evaluate(functions.get('queueStateSnapshot'), stateContext);
const pause = evaluate(functions.get('pause'), stateContext);
pause(true);
assert.equal(stateBattle.paused, true);
assert(stateSends.every((entry) => entry.message.type === 'state-snapshot'));
assert.equal(stateSends[0].message.snapshot.state.paused, true);
assert.equal(stateContext.pendingStateSnapshots.current.size, 1, 'failed reliable pause send stays queued');
acceptState = true;
stateContext.flushStateSnapshots();
assert.equal(stateContext.pendingStateSnapshots.current.size, 0);
pause(false);
assert.equal(stateSends.at(-1).message.snapshot.state.paused, false);
assert.equal(stateSends.at(-1).message.snapshot.networkSequence, 2);

let applied = 0;
const guestBattle = { runId: 'run-1', paused: false, result: null,
  applySnapshot(snapshot) { applied++; this.result = snapshot.result; this.paused = snapshot.state?.paused ?? false; } };
const audio = { suspend: 0, unlock: 0 };
const guestFinalContext = {
  b: guestBattle, session: { hostId: 'host' }, finalSnapshotApplied: false, lastAppliedSnapshot: 0,
  snapshotSequenceOf: helpers.snapshotSequenceOf,
  a: { play() {}, unlock() { audio.unlock++; }, suspend() { audio.suspend++; } }, setPaused() {},
  renderDirty: { current: false }, setConnectionError: (error) => { throw new Error(error); },
  document: { hidden: false },
};
guestFinalContext.applyHostSnapshot = evaluate(arrows.get('applyHostSnapshot'), guestFinalContext);
const guestControl = evaluate(listeners.get('control')[1], guestFinalContext);
const guestSnapshot = evaluate(listeners.get('snapshot')[0], guestFinalContext);
guestSnapshot({ peerId: 'host', snapshot: { networkSequence: 1, result: null, state: { paused: false } } });
guestControl({ peerId: 'host', control: { type: 'state-snapshot', snapshot: { networkSequence: 2, result: null, state: { paused: true } } } });
assert.equal(guestBattle.paused, true);
guestSnapshot({ peerId: 'host', snapshot: { networkSequence: 1, result: null, state: { paused: false } } });
assert.equal(guestBattle.paused, true, 'late realtime state cannot undo reliable pause');
guestControl({ peerId: 'host', control: { type: 'state-snapshot', snapshot: { networkSequence: 3, result: null, state: { paused: false } } } });
assert.equal(guestBattle.paused, false);
assert.equal(audio.suspend, 1);
assert.equal(audio.unlock, 1);
guestControl({ peerId: 'host', control: { type: 'final-snapshot', snapshot: { networkSequence: 4, result: { runId: 'run-1', won: true }, state: { paused: false } } } });
assert.equal(guestBattle.result.won, true);
const appliedAtFinish = applied;
guestControl({ peerId: 'host', control: { type: 'final-snapshot', snapshot: { networkSequence: 4, result: { runId: 'run-1', won: true } } } });
guestSnapshot({ peerId: 'host', snapshot: { networkSequence: 5, result: null } });
assert.equal(applied, appliedAtFinish, 'duplicate final and delayed realtime snapshot cannot reverse the result');
console.log('PASS reliable one-shot actions, pause/resume, and terminal snapshot delivery');
