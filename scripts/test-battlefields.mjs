import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import ts from 'typescript';
import { NullEngine } from '@babylonjs/core/Engines/nullEngine.js';

const root = path.resolve('outputs/test-battlefields');
await fs.mkdir(path.join(root, 'three'), { recursive: true });
for (const name of [
  'asset-url',
  'campaign',
  'battlefields',
  'terrain',
  'navigation',
  'performance',
  'progression',
  'engine',
  'three/babylon',
  'three/surface-textures',
  'three/materials',
  'three/tank-model',
  'three/world',
  'three/nature',
  'three/battlefield-scenery',
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
      /import (\w+) from ['"]([^'"]+\.(?:webp|png)\?url)['"];?/g,
      (_, name, url) => `const ${name} = ${JSON.stringify(url)};`,
    )
    .replace(
      /from (['"])(\.{1,2}\/[^'"]+)\1/g,
      (_, quote, url) => `from ${quote}${url}.js${quote}`,
    );
  await fs.writeFile(path.join(root, `${name}.js`), js);
}
const read = (name) => import(pathToFileURL(path.join(root, name + '.js')));
const { Battle, W, H } = await read('engine');
const { BATTLEFIELDS } = await read('battlefields');
const { defaultSave } = await read('campaign');
const { Scene } = await read('three/babylon');
const { createMaterials } = await read('three/materials');
const { createWorld, createWorldAsync } = await read('three/world');
const engine = new NullEngine({
  renderWidth: 1280,
  renderHeight: 800,
  textureSize: 256,
});
for (const { id: battlefield } of BATTLEFIELDS) {
  const scene = new Scene(engine),
    b = new Battle(0, false, { ...defaultSave, battlefield }, 1234);
  const world = createWorld(
    scene,
    b,
    createMaterials(scene, false),
    'performance',
    true,
    false,
  );
  assert.equal(world.walls.size, b.walls.length);
  const hills = world.staticMeshes.filter(
    (mesh) => mesh.metadata?.terrain === 'hill',
  );
  assert.equal(
    hills.length,
    b.terrain.filter((feature) => feature.kind === 'hill').length,
  );
  for (const mesh of hills) {
    mesh.computeWorldMatrix(true);
    const bounds = mesh.getBoundingInfo().boundingBox,
      feature = mesh.metadata.footprint;
    assert(Math.abs(bounds.minimumWorld.x - (feature.x - W / 2) * 0.1) < 0.001);
    assert(
      Math.abs(bounds.maximumWorld.z - (feature.y + feature.h - H / 2) * 0.1) <
        0.001,
    );
    assert(bounds.minimumWorld.y >= 0);
    assert(
      mesh
        .getVerticesData('normal')
        .filter((_, i) => i % 3 === 1)
        .every((value) => value > 0),
    );
    const positions = mesh.getVerticesData('position');
    let edgeVertices = 0;
    assert.equal(feature.shape, 'ellipse');
    for (let i = 0; i < positions.length; i += 3) {
      const u =
        (positions[i] - (feature.x + feature.w / 2 - W / 2) * 0.1) /
        (feature.w * 0.05);
      const v =
        (positions[i + 2] - (feature.y + feature.h / 2 - H / 2) * 0.1) /
        (feature.h * 0.05);
      const radius = u * u + v * v;
      assert(
        radius <= 1.00001,
        'hill geometry stays within its elliptical collision',
      );
      if (radius > 0.99999) {
        edgeVertices++;
        assert(
          Math.abs(positions[i + 1] - 0.045) < 0.0001,
          'hill foot meets the ground without a slab',
        );
      }
    }
    assert(edgeVertices >= 32);
  }
  const wall = b.walls.find(
    (wall) => wall.kind === 'office' || wall.kind === 'warehouse',
  );
  if (battlefield === 'city') {
    assert(wall && Number.isFinite(wall.maxHp));
    const view = world.walls.get(wall),
      allocations = [scene.meshes.length, scene.materials.length];
    for (const [ratio, stage] of [
      [0.7, 1],
      [0.3, 2],
      [0, 0],
      [1, 0],
    ]) {
      wall.hp = wall.maxHp * ratio;
      world.updateDamage();
      assert.equal(view.solid.metadata.damageStage, stage);
      assert.equal(view.solid.isEnabled(), ratio > 0);
      assert.equal(view.rubble.isEnabled(), ratio <= 0);
      assert(view.rubble.getChildMeshes().length > 0);
      assert.deepEqual(
        [scene.meshes.length, scene.materials.length],
        allocations,
      );
    }
    console.log(
      `PASS ${battlefield}: staged damage and rubble without new allocations`,
    );
  } else {
    assert(!wall);
    assert(
      !b.walls.some((wall) =>
        ['office', 'warehouse', 'container', 'water'].includes(wall.kind),
      ),
    );
    assert(
      !world.staticMeshes.some((mesh) =>
        /distant-industrial|rail-spur|rail-sleeper/.test(mesh.name),
      ),
    );
    const water = world.staticMeshes.filter(
      (mesh) => mesh.metadata?.terrain === 'water',
    );
    const bottoms = world.staticMeshes.filter(
      (mesh) => mesh.metadata?.terrain === 'ford-bottom',
    );
    assert.equal(water.length, 3);
    assert.equal(bottoms.length, 3);
    for (const mesh of water) {
      assert(mesh.metadata.fordable && mesh.material.needAlphaBlending());
      assert(
        Math.max(
          ...mesh.getVerticesData('position').filter((_, i) => i % 3 === 1),
        ) < 0.07,
      );
      assert(
        mesh
          .getVerticesData('color')
          .some((value, i) => i % 4 === 3 && value === 0),
      );
    }
    console.log(
      `PASS ${battlefield}: rounded hills match collision, fordable shallow water, no houses or rail`,
    );
  }
  scene.dispose();
  await new Promise((resolve) => setTimeout(resolve, 0));
}
const scene = new Scene(engine),
  b = new Battle(0, false, { ...defaultSave, battlefield: 'highlands' }, 1234),
  progress = [];
let ticks = 0;
const timer = setInterval(() => ticks++, 0);
try {
  await createWorldAsync(
    scene,
    b,
    createMaterials(scene, false),
    'performance',
    true,
    false,
    (completed, total, label) => progress.push({ completed, total, label }),
  );
} finally {
  clearInterval(timer);
}
assert(ticks > 0, 'loading batches must yield to input and painting');
assert.equal(progress.at(-1).completed, progress.at(-1).total);
assert(
  progress.every(
    (value, i) => i === 0 || value.completed > progress[i - 1].completed,
  ),
);
scene.dispose();
const cancelled = new Scene(engine);
await assert.rejects(
  createWorldAsync(
    cancelled,
    b,
    createMaterials(cancelled, false),
    'performance',
    true,
    false,
    undefined,
    () => true,
  ),
  { name: 'AbortError' },
);
cancelled.dispose();
engine.dispose();
console.log('PASS asynchronous world progress, real yields, and cancellation');
