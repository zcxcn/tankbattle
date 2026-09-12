import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import vm from 'node:vm';
import ts from 'typescript';

// Execute production first-frame readiness against controlled browser boundaries.
const source = await fs.readFile('lib/three/renderer3d.ts', 'utf8');
const ast = ts.createSourceFile(
  'renderer3d.ts',
  source,
  ts.ScriptTarget.ES2022,
  true,
);
const renderer = ast.statements.find(
  (node) => ts.isClassDeclaration(node) && node.name?.text === 'Renderer3D',
);
const method = renderer.members.find(
  (node) =>
    ts.isMethodDeclaration(node) &&
    node.name.getText(ast) === 'prepareFirstFrame',
);
assert(method, 'renderer exposes the production readiness method');
const dispose = renderer.members.find(
  (node) =>
    ts.isMethodDeclaration(node) && node.name.getText(ast) === 'dispose',
);
const code = ts.transpileModule(
  `class ReadinessHarness { ${method.getText(ast)} ${dispose.getText(ast)} } globalThis.ReadinessHarness = ReadinessHarness;`,
  {
    compilerOptions: {
      target: ts.ScriptTarget.ES2022,
      module: ts.ModuleKind.ES2022,
    },
  },
).outputText;
function setup(onTick = () => {}) {
  let now = 0,
    tick = 0;
  const context = vm.createContext({
    DOMException,
    document: { hidden: false },
    performance: { now: () => now },
    setTimeout(callback) {
      now += 32;
      onTick(++tick);
      queueMicrotask(callback);
    },
  });
  vm.runInContext(code, context);
  const harness = new context.ReadinessHarness();
  const texture = {
    isRenderTarget: false,
    loadingError: false,
    ready: false,
    name: 'required-texture',
    isReady() {
      return this.ready;
    },
  };
  const mesh = (name, inView, enabled = true) => ({
    name,
    inView,
    enabled,
    shaderReady: false,
    checks: 0,
    isVisible: true,
    visibility: 1,
    material: { getActiveTextures: () => [texture] },
    isEnabled() {
      return this.enabled;
    },
    computeWorldMatrix() {},
    isReady() {
      this.checks++;
      return this.shaderReady;
    },
  });
  const near = mesh('near', true),
    far = mesh('far', false),
    hidden = mesh('hidden', true, false),
    shadow = mesh('local-shadow', false);
  const camera = {
    ready: false,
    isInFrustum: (mesh) => mesh.inView,
    isReady() {
      return this.ready;
    },
  };
  const scene = {
    meshes: [near, far, hidden, shadow],
    environmentTexture: texture,
    draws: 0,
    incrementRenderId() {},
    render() {
      this.draws++;
    },
  };
  const world = {
    shadow: {
      getShadowMap: () => ({
        renderList: [shadow, far],
        getCustomRenderList: () => [shadow],
      }),
    },
  };
  Object.assign(harness, {
    scene,
    camera,
    world,
    disposed: false,
    resizeGeneration: 0,
    updateCamera() {},
  });
  scene.updateTransformMatrix = () => {};
  const progress = [];
  return {
    harness,
    document: context.document,
    texture,
    near,
    far,
    hidden,
    shadow,
    camera,
    scene,
    progress,
    run: (battle) =>
      harness.prepareFirstFrame(
        (value, label) => progress.push({ value, label, draws: scene.draws }),
        battle,
      ),
  };
}
let active;
active = setup((tick) => {
  if (tick === 2) active.texture.ready = true;
  if (tick === 3) active.near.shaderReady = true;
  if (tick === 4) active.shadow.shaderReady = true;
  if (tick === 5) active.camera.ready = true;
});
await active.run();
assert.equal(
  active.progress[0].value,
  active.progress[1].value,
  'elapsed time cannot advance asset progress',
);
assert(
  active.progress.slice(0, -1).every(({ value }) => value < 100),
  'only the completed first frame reaches 100',
);
assert.equal(active.progress.at(-1).value, 100);
assert(active.progress.at(-1).draws > 0, '100 follows actual frame submission');
assert.equal(active.far.checks, 0, 'distant shaders do not delay entry');
assert.equal(active.hidden.checks, 0, 'disabled rubble does not delay entry');
assert(
  active.shadow.checks > 0,
  'offscreen local shadow casters must be ready',
);
assert(
  active.progress.every(({ value }, i, all) => !i || value >= all[i - 1].value),
);
console.log(
  'PASS actual asset/shader progress, local shadow readiness, frame submission, and distant work exclusion',
);

active = setup(() => {
  active.harness.disposed = true;
});
await assert.rejects(active.run(), (error) => error.name === 'AbortError');
assert(active.progress.every(({ value }) => value < 100));
assert.equal(active.scene.draws, 0);
console.log('PASS cancellation stops first-frame work before readiness');

active = setup();
active.texture.loadingError = true;
await assert.rejects(active.run(), /Required texture could not load/);
assert.equal(active.progress.length, 0);
console.log('PASS required asset failure cannot claim readiness');

active = setup();
await assert.rejects(active.run(), /did not become ready/);
assert(active.progress.every(({ value }) => value < 100));
console.log('PASS stalled assets time out without invented progress');

active = setup((tick) => {
  if (tick === 1600) {
    active.document.hidden = false;
    active.texture.ready = true;
    active.near.shaderReady = true;
    active.shadow.shaderReady = true;
    active.camera.ready = true;
  }
});
active.document.hidden = true;
await active.run();
assert.equal(active.progress.at(-1).value, 100);
console.log(
  'PASS background deployment does not consume the foreground timeout',
);

active = setup((tick) => {
  if (tick === 1) {
    active.harness.resizeGeneration++;
    active.far.inView = true;
    active.texture.ready = true;
    active.near.shaderReady = true;
    active.shadow.shaderReady = true;
    active.camera.ready = true;
  }
  if (tick === 3) active.far.shaderReady = true;
});
await active.run({});
assert(
  active.far.checks > 0,
  'rotated viewport must prepare newly visible meshes',
);
assert(
  active.progress.every(
    (value, i, all) => !i || value.value >= all[i - 1].value,
  ),
);
console.log('PASS rotation updates required meshes without reversing progress');

active = setup();
let released = 0;
Object.assign(active.harness, {
  scene: { dispose: () => released++ },
  engine: { dispose: () => released++ },
  models: new Map(),
  contactShadows: new Map(),
  healthBars: new Map(),
});
active.harness.dispose();
active.harness.dispose();
assert.equal(released, 2);
console.log(
  'PASS cancellation before vehicle/effect creation safely releases partial resources once',
);
