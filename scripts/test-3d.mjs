import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import ts from 'typescript';
import { NullEngine } from '@babylonjs/core/Engines/nullEngine.js';
import { Vector3, Matrix } from '@babylonjs/core/Maths/math.vector.js';
import { Ray } from '@babylonjs/core/Culling/ray.js';
import { TransformNode } from '@babylonjs/core/Meshes/transformNode.js';
import { TimingTools } from '@babylonjs/core/Misc/timingTools.js';
const root = path.resolve('outputs/test-3d');
await fs.mkdir(path.join(root, 'three'), { recursive: true });
for (const name of [
  'asset-url',
  'campaign',
  'terrain',
  'navigation',
  'performance',
  'progression',
  'engine',
  'fixed-step',
  'three/babylon',
  'three/surface-textures',
  'three/materials',
  'three/tank-model',
  'three/world',
  'three/nature',
  'three/explosions',
  'three/muzzle',
  'three/weapon-mount',
  'three/projectiles',
  'three/renderer3d',
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
      (_, q, p) => `from ${q}${p}.js${q}`,
    );
  await fs.writeFile(path.join(root, `${name}.js`), js);
}
const { Battle, W, H } = await import(
  pathToFileURL(path.join(root, 'engine.js'))
);
const { defaultSave, WEAPONS } = await import(
  pathToFileURL(path.join(root, 'campaign.js'))
);
const { FixedStep } = await import(
  pathToFileURL(path.join(root, 'fixed-step.js'))
);
const { Renderer3D } = await import(
  pathToFileURL(path.join(root, 'three/renderer3d.js'))
);
const { ProjectileEffects } = await import(
  pathToFileURL(path.join(root, 'three/projectiles.js'))
);
const { MuzzleEffects, recoilDistance } = await import(
  pathToFileURL(path.join(root, 'three/muzzle.js'))
);
const { Scene } = await import('@babylonjs/core/scene.js');
const { worldPosition, simulationPosition } = await import(
  pathToFileURL(path.join(root, 'three/world.js'))
);
const { EVOLUTIONS } = await import(
  pathToFileURL(path.join(root, 'progression.js'))
);
const { buildTank } = await import(
  pathToFileURL(path.join(root, 'three/tank-model.js'))
);
const { natureMaterials, buildLivingCover } = await import(
  pathToFileURL(path.join(root, 'three/nature.js'))
);
const config = () => ({
  ...defaultSave,
  upgrades: [0, 0, 0, 0, 0, 0],
  completed: [],
});
const idle = { x: 0, y: 0, fire: false, aim: null, dash: false, emp: false };
const canvas = {
  getBoundingClientRect: () => ({ left: 0, top: 0, width: 1280, height: 800 }),
};
const engine = new NullEngine({
  renderWidth: 1280,
  renderHeight: 800,
  textureSize: 512,
  deterministicLockstep: true,
  lockstepMaxSteps: 4,
});
const battle = new Battle(0, false, config(), 1234);
const r = new Renderer3D(canvas, battle, {
  headlessEngine: engine,
  assets: false,
});
await r.ready;
let passed = 0;
async function flushSceneWork() {
  // Scene.addMesh/material/node queues creation notifications that retain even
  // already-disposed merged source geometry. Drain Babylon's actual timer queue
  // before building another fixture, just as a browser yields between frames.
  await new Promise((resolve) => TimingTools.SetImmediate(resolve));
  await new Promise((resolve) => setImmediate(resolve));
}
async function test(name, fn) {
  await fn();
  await flushSceneWork();
  console.log('PASS ' + name);
  passed++;
}
await test('3D scene has modeled tanks, perspective camera, PBR materials and industrial scenery', () => {
  assert(r.models.size === 4);
  assert(r.scene.meshes.length > 65);
  assert(r.materials.armor.getClassName() === 'PBRMaterial');
  assert(r.camera.mode === 0);
  assert(r.world.walls.size === battle.walls.length);
});
await test('ground coordinates round trip and camera respects screen directions', () => {
  const pt = worldPosition(513, 692, 0);
  const back = simulationPosition(pt);
  assert(Math.abs(back.x - 513) < 1e-8);
  assert(Math.abs(back.y - 692) < 1e-8);
  const viewport = r.camera.viewport.toGlobal(1280, 800),
    proj = (x, y) =>
      Vector3.Project(
        worldPosition(x, y),
        Matrix.Identity(),
        r.scene.getTransformMatrix(),
        viewport,
      );
  const center = proj(W / 2, H - 185);
  assert(proj(W / 2 + 30, H - 185).x > center.x, 'east must be screen right');
  assert(proj(W / 2, H - 215).y < center.y, 'north must be screen up');
});
await test('muzzle and simulation headings agree in every cardinal direction', () => {
  for (const a of [0, Math.PI / 2, Math.PI, -Math.PI / 2]) {
    battle.player.turret = a;
    r.draw(battle, null);
    const model = r.models.get(0);
    model.turret.computeWorldMatrix(true);
    const origin = Vector3.TransformCoordinates(
      Vector3.Zero(),
      model.turret.getWorldMatrix(),
    );
    const tip = Vector3.TransformCoordinates(
      new Vector3(0, 0, 4),
      model.turret.getWorldMatrix(),
    );
    const dir = tip.subtract(origin).normalize();
    assert(Math.abs(dir.x - Math.cos(a)) < 1e-5);
    assert(Math.abs(dir.z - Math.sin(a)) < 1e-5);
  }
});
await test('merged tank geometry stays near the chassis and above the ground', () => {
  const model = r.models.get(0);
  const all = model.meshes;
  for (const mesh of all) {
    mesh.computeWorldMatrix(true);
    const box = mesh.getBoundingInfo().boundingBox;
    assert(
      box.maximumWorld.y < 6,
      'turret transform must not be applied twice',
    );
    assert(box.minimumWorld.y > -0.15);
    assert(Vector3.Distance(box.centerWorld, model.root.position) < 6);
  }
});
await test('custom armor top faces have upward PBR normals in the right-handed scene', () => {
  const model = r.models.get(0);
  for (const node of [model.body, model.turret]) {
    let top = 0;
    for (const mesh of node.getChildMeshes(true)) {
      const p = mesh.getVerticesData('position'),
        n = mesh.getVerticesData('normal');
      if (!p || !n) continue;
      for (let i = 0; i < p.length; i += 3) {
        if (
          Math.abs(p[i + 1] - (node === model.body ? 1.75 : 0.91)) < 0.001 &&
          Math.abs(n[i + 1]) > 0.9
        ) {
          assert(n[i + 1] > 0.9);
          top++;
        }
      }
    }
    assert(top >= 4);
  }
});
await test('perspective pointer projects to actual ground coordinates', () => {
  r.updateCamera(battle, 0, true);
  const viewport = r.camera.viewport.toGlobal(1280, 800);
  const expected = { x: W / 2 + 60, y: H - 210 };
  const screen = Vector3.Project(
    worldPosition(expected.x, expected.y),
    Matrix.Identity(),
    r.scene.getTransformMatrix(),
    viewport,
  );
  const aim = r.pointer(screen.x, screen.y);
  assert(aim);
  assert(Math.abs(aim.x - expected.x) < 0.02);
  assert(Math.abs(aim.y - expected.y) < 0.02);
});
await test('aim stays accurate across performance and high-DPR render scaling', () => {
  const viewport = r.camera.viewport.toGlobal(1280, 800),
    expected = { x: W / 2 + 70, y: H - 220 };
  const projected = Vector3.Project(
    worldPosition(expected.x, expected.y),
    Matrix.Identity(),
    r.scene.getTransformMatrix(),
    viewport,
  );
  const bounds = canvas.getBoundingClientRect;
  for (const rect of [
    bounds(),
    { left: 0, top: 66, width: 390, height: 778 },
    { left: 0, top: 66, width: 844, height: 324 },
    { left: 12, top: 66, width: 320, height: 502 },
  ]) {
    canvas.getBoundingClientRect = () => rect;
    for (const scale of [1 / 3, 0.5, 0.625, 1, 1.5]) {
      engine.setHardwareScalingLevel(scale);
      const aim = r.pointer(
        rect.left + (projected.x / 1280) * rect.width,
        rect.top + (projected.y / 800) * rect.height,
      );
      assert(aim);
      assert(
        Math.abs(aim.x - expected.x) < 0.03,
        `x aim at scale ${scale}, width ${rect.width}`,
      );
      assert(
        Math.abs(aim.y - expected.y) < 0.03,
        `y aim at scale ${scale}, height ${rect.height}`,
      );
    }
  }
  canvas.getBoundingClientRect = bounds;
  engine.setHardwareScalingLevel(1);
});
await test('clicking own armor does not snap the cannon toward the player center', () => {
  const viewport = r.camera.viewport.toGlobal(1280, 800);
  const projected = Vector3.Project(
    worldPosition(battle.player.x, battle.player.y, 2.1),
    Matrix.Identity(),
    r.scene.getTransformMatrix(),
    viewport,
  );
  const aim = r.pointer(projected.x, projected.y);
  assert(aim);
  assert(Math.abs(aim.y - battle.player.y) > 5);
});
await test('render updates cannot mutate combat state or its random generator', () => {
  const before = JSON.stringify(battle);
  for (let i = 0; i < 4; i++) r.draw(battle, { x: 670, y: 560 });
  assert.equal(JSON.stringify(battle), before);
  const copy = new Battle(0, false, config(), 1234);
  assert.equal(battle.random(), copy.random());
});
await test('destroyed cover swaps to rubble and defeated tanks are removed from picking', () => {
  const w = battle.walls.find((w) => !w.steel),
    view = r.world.walls.get(w);
  w.hp = 0;
  const e = battle.enemies[0];
  battle.hitEnemy(e, 9999);
  battle.enemies = battle.enemies.filter((t) => t.hp > 0);
  r.draw(battle, null);
  assert(!view.solid.isEnabled());
  assert(view.rubble.isEnabled());
  assert(!r.models.has(e.id));
  assert(!r.scene.meshes.some((m) => m.metadata?.tankId === e.id));
  assert(!r.scene.meshes.some((m) => m.name === 'tank-contact-' + e.id));
});
await test('render mesh pools stop growing for a stable battle state', () => {
  r.draw(battle, null);
  const count = r.meshCount;
  for (let i = 0; i < 20; i++) r.draw(battle, null);
  assert.equal(r.meshCount, count);
});
await test('vehicle contact shading follows chassis motion without becoming an aiming target or leaking per frame', () => {
  const footprints = r.scene.meshes.filter(
    (m) => m.material === r.materials.contact,
  );
  assert.equal(footprints.length, r.models.size);
  assert(
    footprints.every((m) => !m.isPickable && m.material.needAlphaBlending()),
  );
  const player = footprints.find((m) => m.name === 'tank-contact-0');
  const oldAngle = battle.player.angle,
    oldX = battle.player.x;
  const materials = r.scene.materials.length,
    textures = r.scene.textures.length;
  battle.player.angle += 0.6;
  battle.player.x += 5;
  r.draw(battle, null);
  assert(
    Math.abs(
      player.position.x - worldPosition(battle.player.x, battle.player.y).x,
    ) < 1e-6,
  );
  assert(Math.abs(player.rotation.y - r.models.get(0).body.rotation.y) < 1e-6);
  assert.equal(r.scene.materials.length, materials);
  assert.equal(r.scene.textures.length, textures);
  battle.player.angle = oldAngle;
  battle.player.x = oldX;
  r.draw(battle, null);
});
await test('camera toggles and zoom do not change combat state', () => {
  const before = JSON.stringify(battle);
  assert.equal(r.toggleCamera(), 'tactical');
  r.setZoom(200);
  r.draw(battle, null);
  assert.equal(JSON.stringify(battle), before);
  assert.equal(r.toggleCamera(), 'assault');
});
await test('fixed simulation clock preserves movement and time at 15, 30, 60, 120 FPS', () => {
  const outcomes = [];
  for (const fps of [15, 30, 60, 120]) {
    const b = new Battle(0, true, config(), 42);
    b.walls = [];
    b.enemies = [];
    b.spawnTimer = 100;
    b.player.x = 300;
    b.player.y = 300;
    const fixed = new FixedStep();
    for (let i = 0; i < fps * 2; i++)
      fixed.advance(b, 1 / fps, { ...idle, x: 1 });
    outcomes.push([b.player.x, b.elapsed]);
  }
  for (const a of outcomes) {
    assert(Math.abs(a[0] - outcomes[0][0]) < 1e-6);
    assert(Math.abs(a[1] - 2) < 1e-6);
  }
});
await test('paused fixed clock discards backlog and consumes a skill only once', () => {
  const b = new Battle(0, false, config(), 42),
    fixed = new FixedStep();
  b.paused = true;
  fixed.advance(b, 3, { ...idle, x: 1 });
  assert.equal(b.elapsed, 0);
  b.paused = false;
  const input = { ...idle, emp: true };
  const steps = fixed.advance(b, 0.1, input);
  assert.equal(steps, 6);
  assert.equal(input.emp, false);
  assert(Math.abs(b.empCd - (13 - 5 / 60)) < 1e-6);
});
await test('projectile muzzle origin and elevation match normal and siege tank models', async () => {
  for (const mission of [0, 5]) {
    const b = new Battle(mission, false, config(), 19);
    const testEngine = new NullEngine({
      renderWidth: 1280,
      renderHeight: 800,
      textureSize: 256,
      deterministicLockstep: true,
      lockstepMaxSteps: 4,
    });
    const view = new Renderer3D(canvas, b, {
      headlessEngine: testEngine,
      assets: false,
    });
    const t = mission === 5 ? b.boss : b.player;
    t.spawn = 0;
    t.turret = 0.73;
    t.flash = 0;
    view.draw(b, null);
    const model = view.models.get(t.id);
    model.flash.computeWorldMatrix(true);
    const muzzle = Vector3.TransformCoordinates(
      Vector3.Zero(),
      model.flash.getWorldMatrix(),
    );
    b.shoot(t, mission === 5);
    const bullet = b.bullets[mission === 5 ? 1 : 0];
    const start = worldPosition(bullet.x, bullet.y, bullet.height * 0.1);
    assert(Vector3.Distance(muzzle, start) < 0.03);
    view.dispose();
    await flushSceneWork();
  }
});

await test('new mission scenery, objectives and convoy stay synchronized without changing simulation', async () => {
  for (const mission of [6, 7, 8, 9, 11, 12, 13, 14, 15, 17]) {
    const b = new Battle(mission, false, config(), 7);
    const view = new Renderer3D(canvas, b, {
      headlessEngine: new NullEngine({
        renderWidth: 1280,
        renderHeight: 800,
        textureSize: 128,
      }),
      assets: false,
    });
    const before = JSON.stringify(b);
    view.draw(b, null);
    assert.equal(JSON.stringify(b), before);
    assert.equal(view.objectiveViews.size, b.objectives.length);
    if (b.type === 'sabotage') {
      const o = b.objectives[0];
      b.player.x = o.x;
      b.player.y = o.y + 250;
      view.updateCamera(b, 0, true);
      const screen = Vector3.Project(
        worldPosition(o.x, o.y, 2.5),
        Matrix.Identity(),
        view.scene.getTransformMatrix(),
        view.camera.viewport.toGlobal(1280, 800),
      );
      const aim = view.pointer(screen.x, screen.y);
      assert(
        aim && Math.hypot(aim.x - o.x, aim.y - o.y) < 0.1,
        'picking tower aims its center',
      );
      o.done = true;
      view.draw(b, null);
      assert(
        view.objectiveViews
          .get(o.id)
          .root.getChildMeshes()
          .filter((m) => m.name === 'reactor-light')
          .every((m) => !m.isEnabled()),
      );
    }
    if (b.type === 'escort') {
      b.base.x += 40;
      view.draw(b, null);
      assert(
        Vector3.Distance(
          view.base.position,
          worldPosition(b.base.x, b.base.y),
        ) < 1e-8,
      );
    }
    for (const mesh of view.world.staticMeshes) {
      if (mesh.name.includes('factory-block')) {
        mesh.computeWorldMatrix(true);
        const bounds = mesh.getBoundingInfo().boundingBox;
        assert(
          bounds.minimumWorld.z <= -H * 0.05 ||
            Math.abs(bounds.centerWorld.x) >= W * 0.05,
        );
      }
    }
    view.dispose();
    assert(view.scene.isDisposed);
    await flushSceneWork();
  }
});
await test('all 9 enemy variants and 7 equipped weapons have bounded disposable geometry', async () => {
  const b = new Battle(0, true, config(), 3);
  b.walls = [];
  b.enemies = [];
  for (let k = 0; k < 9; k++) b.spawnEnemy(k);
  const view = new Renderer3D(canvas, b, {
    headlessEngine: new NullEngine({
      renderWidth: 1280,
      renderHeight: 800,
      textureSize: 128,
    }),
    assets: false,
  });
  assert.equal(view.models.size, b.enemies.length + 1);
  view.draw(b, null);
  assert(view.scene.meshes.some((m) => m.name === 'rocket-pod'));
  assert(view.scene.meshes.some((m) => m.name === 'repair-cross-horizontal'));
  const count = view.meshCount;
  for (let i = 0; i < 5; i++) view.draw(b, null);
  assert.equal(view.meshCount, count);
  view.dispose();
  await flushSceneWork();
  for (let weapon = 0; weapon < WEAPONS.length; weapon++) {
    const a = new Battle(0, false, { ...config(), weapon }, 2);
    a.ammo[weapon] = weapon === 0 ? Infinity : 20;
    a.selectWeapon(weapon);
    const v = new Renderer3D(canvas, a, {
      headlessEngine: new NullEngine({
        renderWidth: 1280,
        renderHeight: 800,
        textureSize: 128,
      }),
      assets: false,
    });
    v.draw(a, null);
    assert(v.models.has(0));
    v.dispose();
    await flushSceneWork();
  }
});

await test('30 tank levels share correct muzzle geometry, seven forms change silhouette and release materials', async () => {
  const snapshots = [];
  for (let level = 1; level <= 30; level++) {
    const count = r.scene.materials.length,
      model = buildTank(r.scene, r.materials, 1, false, false, level);
    assert.equal(model.evolutionLevel, level);
    model.root.computeWorldMatrix(true);
    model.flash.computeWorldMatrix(true);
    const tip = Vector3.TransformCoordinates(
      Vector3.Zero(),
      model.flash.getWorldMatrix(),
    );
    assert(Math.abs(tip.y - 2.12) < 0.001);
    assert(Math.abs(tip.z - 4.06) < 0.001);
    const vertices = model.meshes.reduce((n, m) => n + m.getTotalVertices(), 0);
    if (EVOLUTIONS.some((e) => e.level === level)) snapshots.push(vertices);
    for (const mesh of model.meshes) {
      mesh.computeWorldMatrix(true);
      const bounds = mesh.getBoundingInfo().boundingBox;
      assert(bounds.minimumWorld.y > -0.15);
      assert(bounds.maximumWorld.y < 6);
    }
    model.dispose();
    model.dispose();
    assert.equal(
      r.scene.materials.length,
      count,
      'rank materials must not leak',
    );
    assert(r.scene.materials.includes(r.materials.armor));
    await flushSceneWork();
  }
  assert.equal(new Set(snapshots).size, 7);
  assert(
    snapshots.at(-1) > snapshots[0] * 1.2,
    'final form has substantial additional geometry',
  );
});
await test('live rank changes rebuild the player once, keep enemy models and release old GPU objects', () => {
  const b = new Battle(0, false, { ...config(), kills: 24 }, 12),
    view = new Renderer3D(canvas, b, {
      headlessEngine: new NullEngine({
        renderWidth: 1280,
        renderHeight: 800,
        textureSize: 128,
      }),
      assets: false,
    });
  const old = view.models.get(0),
    enemy = view.models.get(b.enemies[1].id);
  const oldRankMaterials = view.scene.materials.filter((m) =>
    m.name.startsWith('evolution-'),
  );
  b.hitEnemy(b.enemies[0], 9999);
  view.draw(b, null);
  const evolved = view.models.get(0);
  assert.notEqual(evolved, old);
  assert(old.root.isDisposed());
  assert.equal(evolved.evolutionLevel, 6);
  assert.equal(view.models.get(b.enemies[1].id), enemy);
  assert(oldRankMaterials.every((m) => !view.scene.materials.includes(m)));
  assert.equal(
    view.scene.materials.filter((m) => m.name.startsWith('evolution-')).length,
    2,
  );
  const warmedMaterials = view.scene.materials.length;
  for (let i = 0; i < 5; i++) view.draw(b, null);
  assert.equal(view.models.get(0), evolved);
  assert.equal(view.scene.materials.length, warmedMaterials);
  assert.equal(
    evolved.root.position.x,
    worldPosition(b.player.x, b.player.y).x,
  );
  view.dispose();
});
await test('mobile detail keeps seven evolution forms and muzzle positions with fewer vertices', async () => {
  for (const level of [1, 6, 11, 16, 21, 26, 30]) {
    const full = buildTank(r.scene, r.materials, 1, false, false, level, false);
    const light = buildTank(r.scene, r.materials, 1, false, false, level, true);
    const count = (m) =>
      m.meshes.reduce((n, mesh) => n + mesh.getTotalVertices(), 0);
    assert(count(light) < count(full) * 0.8);
    assert.equal(light.flash.position.z, full.flash.position.z);
    assert.equal(light.flash.position.y, full.flash.position.y);
    full.dispose();
    light.dispose();
    await flushSceneWork();
  }
});
await test('city building bodies match collision footprints', () => {
  for (const [w, view] of r.world.walls) {
    if (!['office', 'warehouse'].includes(w.kind)) continue;
    const body = view.solid
      .getChildMeshes()
      .find(
        (mesh) =>
          mesh.material.name ===
          (w.kind === 'office' ? 'old-concrete' : 'exposed-brick'),
      );
    assert(body);
    body.computeWorldMatrix(true);
    const box = body.getBoundingInfo().boundingBox;
    const center = worldPosition(w.x + w.w / 2, w.y + w.h / 2);
    assert(Math.abs(box.centerWorld.x - center.x) < 0.01);
    assert(Math.abs(box.centerWorld.z - center.z) < 0.01);
    assert(Math.abs(box.extendSizeWorld.x * 2 - w.w * 0.1) < 0.01);
    assert(Math.abs(box.extendSizeWorld.z * 2 - w.h * 0.1) < 0.01);
  }
});
await test('deformed foliage keeps outward normals for sunlit trees and hedges at both detail levels', async () => {
  const materials = natureMaterials(r.scene, false, 'balanced');
  for (const quality of ['balanced', 'performance'])
    for (const index of [0, 1]) {
      const solid = new TransformNode('foliage-test', r.scene),
        rubble = new TransformNode('foliage-test-rubble', r.scene);
      buildLivingCover(
        r.scene,
        {
          x: 300,
          y: 300,
          w: 14,
          h: 14,
          height: 7,
          kind: 'tree',
          hp: 180,
          maxHp: 180,
          steel: false,
        },
        solid,
        rubble,
        materials,
        quality,
        index,
      );
      const crowns = solid
        .getChildMeshes()
        .filter((mesh) => /pine-bough|broadleaf-canopy/.test(mesh.name));
      assert(crowns.length > 0);
      for (const mesh of crowns) {
        const positions = mesh.getVerticesData('position'),
          normals = mesh.getVerticesData('normal');
        for (let i = 0; i < positions.length; i += 3)
          assert(
            positions[i] * normals[i] +
              positions[i + 1] * normals[i + 1] +
              positions[i + 2] * normals[i + 2] >
              0.1,
          );
      }
      solid.dispose();
      rubble.dispose();
      await flushSceneWork();
    }
  Object.values(materials).forEach((material) => material.dispose());
});
await test('natural scenery has upward surfaces, bounded mountain bases and batched grass', () => {
  const nature = r.world.nature;
  assert(nature.mountains.length >= 8);
  assert(nature.tufts > 200);
  assert(nature.meshes.length < 120);
  for (const mountain of nature.mountains) {
    const { x, z, width, depth } = mountain;
    assert(
      x + width / 2 < -W * 0.05 ||
        x - width / 2 > W * 0.05 ||
        z + depth / 2 < -H * 0.05 ||
        z - depth / 2 > H * 0.05,
    );
  }
  const terrain = nature.meshes.filter(
    (mesh) =>
      mesh.name.startsWith('layered-mountain') ||
      mesh.name.startsWith('natural-verge'),
  );
  assert(terrain.length > 12);
  for (const mesh of terrain) {
    assert(!mesh.isPickable);
    const normals = mesh.getVerticesData('normal');
    for (let i = 1; i < normals.length; i += 3)
      assert(normals[i] > 0, mesh.name + ' inverted normal');
  }
  const tree = battle.walls.find((wall) => wall.kind === 'tree');
  const model = r.world.walls.get(tree);
  tree.hp = 0;
  r.draw(battle, null);
  assert(!model.solid.isEnabled());
  assert(model.rubble.isEnabled());
  assert(model.rubble.getChildMeshes().length > 0);
});
await test('explosion pools are bounded across volleys, freeze on pause and disable when expired', () => {
  const b = new Battle(0, true, config(), 41);
  const view = new Renderer3D(canvas, b, {
    assets: false,
    headlessEngine: new NullEngine({
      renderWidth: 1280,
      renderHeight: 800,
      textureSize: 128,
    }),
  });
  for (let i = 0; i < 200; i++)
    b.explode(b.player.x + (i % 10), b.player.y - 70);
  const ages = [0.04, 0.4, 0.7, 1.2, 2.1, 3.2, 4.8];
  for (const age of ages) {
    b.elapsed = age;
    view.draw(b, null);
  }
  const warmed = [
    view.meshCount,
    view.scene.materials.length,
    view.scene.lights.length,
  ];
  for (let repeat = 0; repeat < 3; repeat++)
    for (const age of ages) {
      b.elapsed = age;
      view.draw(b, null);
      assert.deepEqual(
        [view.meshCount, view.scene.materials.length, view.scene.lights.length],
        warmed,
      );
    }
  // Seven visible groups, each bounded to flash/fire/smoke/dust layers.
  assert(view.explosions.sprites.length <= 126);
  assert(view.explosions.fragments.length <= 56);
  assert.equal(
    view.scene.lights.filter((light) => light.name === 'shared-explosion-flash')
      .length,
    1,
  );
  b.elapsed = 0.4;
  b.paused = true;
  view.draw(b, null);
  const snapshot = JSON.stringify(b),
    metadata = JSON.stringify(view.explosions.sprites.map((m) => m.metadata));
  view.draw(b, null);
  assert.equal(JSON.stringify(b), snapshot);
  assert.equal(
    JSON.stringify(view.explosions.sprites.map((m) => m.metadata)),
    metadata,
  );
  assert(view.explosions.sprites.every((mesh) => !mesh.isPickable));
  const full = view.explosions.sprites.filter((mesh) =>
    mesh.isEnabled(),
  ).length;
  view.explosions.update(b, 0.3);
  assert(
    view.explosions.sprites.filter((mesh) => mesh.isEnabled()).length < full,
  );
  // Terminal presentation can animate without changing score or combat time.
  b.finish(true);
  const resultSnapshot = JSON.stringify(b);
  view.draw(b, null, b.elapsed + 0.85);
  assert.equal(JSON.stringify(b), resultSnapshot);
  b.elapsed = 6;
  view.draw(b, null);
  assert(view.explosions.sprites.every((mesh) => !mesh.isEnabled()));
  assert(view.explosions.fragments.every((mesh) => !mesh.isEnabled()));
  assert.equal(view.explosions.light.intensity, 0);
  view.dispose();
  assert(view.scene.isDisposed);
});
await test('switching live gun mounts preserves the tank and releases previous attachments', () => {
  const b = new Battle(0, true, config(), 3),
    view = new Renderer3D(canvas, b, {
      headlessEngine: new NullEngine({
        renderWidth: 1280,
        renderHeight: 800,
        textureSize: 128,
      }),
      assets: false,
    });
  const tank = view.models.get(0),
    materials = view.scene.materials.length,
    counts = new Map();
  for (let i = 0; i < 35; i++) {
    const index = i % WEAPONS.length,
      previous = view.weaponMount;
    b.ammo[index] = index === 0 ? Infinity : 20;
    b.selectWeapon(index);
    view.draw(b, null);
    assert.equal(view.models.get(0), tank);
    assert.equal(view.weaponMount.index, index);
    if (previous !== view.weaponMount) assert(previous.root.isDisposed());
    assert.equal(view.scene.materials.length, materials);
    if (counts.has(index)) assert.equal(view.meshCount, counts.get(index));
    counts.set(index, view.meshCount);
    assert(view.weaponMount.meshes.every((mesh) => !mesh.isPickable));
    if (i > 0 && i < WEAPONS.length) {
      const bore = new Ray(
        new Vector3(0, 0.5, 4.08),
        new Vector3(0, 0, -1),
        0.1,
      );
      let muzzle = -Infinity;
      for (const mesh of view.weaponMount.meshes) {
        const positions = mesh.getVerticesData('position'),
          indices = mesh.getIndices();
        for (let p = 2; p < positions.length; p += 3)
          muzzle = Math.max(muzzle, positions[p]);
        for (let triangle = 0; triangle < indices.length; triangle += 3) {
          const hit = bore.intersectsTriangle(
            ...[0, 1, 2].map((corner) =>
              Vector3.FromArray(positions, indices[triangle + corner] * 3),
            ),
          );
          assert(
            !hit || hit.distance > bore.length,
            'the firing channel must be open at weapon ' + index,
          );
        }
      }
      assert(
        Math.abs(muzzle - 4.06) < 0.001,
        'visual barrel ends at the shared ballistic muzzle',
      );
    }
  }
  view.dispose();
});
await test('boundary concrete matches the actual four collision rectangles', () => {
  const boundaries = [...r.world.walls].filter(
    ([wall]) => wall.kind === 'boundary',
  );
  assert.equal(boundaries.length, 4);
  for (const [wall, view] of boundaries) {
    assert(view.solid.isEnabled());
    const body = view.solid
      .getChildMeshes()
      .find((mesh) => mesh.material === r.materials.concrete);
    assert(body);
    body.computeWorldMatrix(true);
    const bounds = body.getBoundingInfo().boundingBox;
    const center = worldPosition(wall.x + wall.w / 2, wall.y + wall.h / 2);
    assert(Math.abs(bounds.centerWorld.x - center.x) < 0.001);
    assert(Math.abs(bounds.centerWorld.z - center.z) < 0.001);
    assert(Math.abs(bounds.extendSizeWorld.x * 2 - wall.w * 0.1) < 0.001);
    assert(Math.abs(bounds.extendSizeWorld.z * 2 - wall.h * 0.1) < 0.001);
  }
});
const projectileFixture = (mobile = false) => {
  const e = new NullEngine({
    renderWidth: 1280,
    renderHeight: 800,
    textureSize: 256,
  });
  const scene = new Scene(e);
  scene.useRightHandedSystem = true;
  const fx = new ProjectileEffects(scene, 'balanced', mobile);
  return {
    scene,
    fx,
    dispose: () => {
      fx.dispose();
      scene.dispose();
      e.dispose();
    },
  };
};
const visualBullet = (weapon, x = 1000, y = 800) => ({
  weapon,
  x,
  y,
  height: 21.2,
  vx: 620,
  vy: 0,
  life: 3.5,
  enemy: false,
  damage: 10,
});
await test('seven projectile silhouettes and colors are distinct and their centers match physical bullets', () => {
  const f = projectileFixture();
  const b = {
    elapsed: 0,
    bullets: Array.from({ length: 7 }, (_, i) =>
      visualBullet(i, 700 + i * 120),
    ),
  };
  const before = JSON.stringify(b);
  f.fx.update(b);
  assert.equal(f.fx.stats.bodies, 7);
  const signatures = new Set(),
    colors = new Set();
  f.fx.bodies.forEach((batch, i) => {
    assert.equal(batch.count, 1);
    const center = worldPosition(b.bullets[i].x, b.bullets[i].y, 2.12);
    for (const [offset, coordinate] of [
      [12, center.x],
      [13, center.y],
      [14, center.z],
    ])
      assert(Math.abs(batch.matrices[offset] - coordinate) < 1e-5);
    signatures.add(JSON.stringify(batch.mesh.getVerticesData('position')));
    colors.add(
      (
        batch.mesh.material.albedoColor ?? batch.mesh.material.emissiveColor
      ).toHexString(),
    );
  });
  assert.equal(signatures.size, 7);
  assert.equal(colors.size, 7);
  assert(
    f.fx.flame.matrices[8] < 0,
    'the exhaust cone must taper away from forward flight',
  );
  assert.equal(JSON.stringify(b), before);
  assert(f.scene.meshes.every((mesh) => !mesh.isPickable));
  f.dispose();
});
await test('conventional projectile tracers stay short at low frame rates and machine-gun belts mix unlit rounds', () => {
  const f = projectileFixture();
  const bullets = Array.from({ length: 12 }, (_, index) =>
    visualBullet(1, 1000 + index * 15),
  );
  bullets.push(visualBullet(0, 1500), visualBullet(4, 1650));
  const b = { elapsed: 0, weapon: 1, bullets };
  f.fx.update(b);
  const before = JSON.stringify(bullets);
  assert.equal(
    f.fx.core.count,
    0,
    'ordinary metal rounds must not carry a white laser core',
  );
  for (const weapon of [0, 1, 2, 4]) {
    const material = f.fx.bodies[weapon].mesh.material;
    assert.equal(material.getClassName(), 'PBRMaterial');
    assert.equal(material.emissiveColor.toHexString(), '#000000');
  }
  assert.equal(
    JSON.stringify(bullets),
    before,
    'rendering must not alter combat bullets',
  );
  b.elapsed = 1 / 15;
  bullets.forEach((bullet) => {
    bullet.x += 60;
  });
  b.weapon = 6; // Switching the equipped weapon cannot change rounds in flight.
  f.fx.update(b);
  assert.equal(f.fx.bodies[1].count, 12);
  assert.equal(
    f.fx.trails[1].count,
    3,
    'one stable tracer in each four-round belt group',
  );
  assert.equal(f.fx.trails[0].count, 1);
  for (const [weapon, maximum] of [
    [0, 0.95],
    [1, 0.42],
    [2, 0.16],
  ]) {
    const batch = f.fx.trails[weapon];
    for (let index = 0; index < batch.count; index++) {
      const at = index * 16;
      const length = Math.hypot(
        batch.matrices[at + 8],
        batch.matrices[at + 9],
        batch.matrices[at + 10],
      );
      assert(
        length <= maximum + 1e-5,
        'a delayed render frame must not stretch AP/MG into a beam',
      );
    }
  }
  const matrix = f.fx.bodies[4].matrices;
  assert(
    Math.abs(matrix[13] - 2.12) < 1e-5,
    'grenade visuals must stay at the collision system height',
  );
  const tracerSnapshot = Array.from(f.fx.trails[1].matrices);
  f.fx.update(b);
  assert.deepEqual(
    Array.from(f.fx.trails[1].matrices),
    tracerSnapshot,
    'paused tracer selection must remain stable',
  );
  f.dispose();
});
await test('rocket projectile exhaust stays connected across low-FPS turns without moving recorded hit paths', () => {
  const f = projectileFixture(),
    rocket = visualBullet(6, W / 2 + 120),
    b = { elapsed: 0, weapon: 6, bullets: [rocket] };
  f.fx.update(b);
  b.elapsed = 0.1;
  rocket.x += 50;
  f.fx.update(b);
  assert(
    f.fx.trails[6].count >= 10,
    'a long render step needs multiple evenly spaced smoke samples',
  );
  const firstFlight = f.fx.flights.get(rocket),
    originalPoints = firstFlight.points.map((point) => point.position.clone());
  b.elapsed = 0.2;
  rocket.vx = 0;
  rocket.vy = 620;
  rocket.y += 50;
  b.weapon = 0;
  f.fx.update(b);
  assert.equal(f.fx.flights.get(rocket), firstFlight);
  assert(firstFlight.points[0].position.equals(originalPoints[0]));
  assert(firstFlight.points[1].position.equals(originalPoints[1]));
  const smoke = f.fx.trails[6],
    centers = Array.from({ length: smoke.count }, (_, index) =>
      Vector3.FromArray(smoke.matrices, index * 16 + 12),
    );
  assert(centers.some((point) => point.z > originalPoints[1].z + 1));
  assert(centers.some((point) => point.x < originalPoints[1].x - 1));
  assert(
    centers.every((point) => point.y >= 2.12 && point.y < 2.4),
    'smoke rises gently while the physical rocket stays on its flight height',
  );
  assert.equal(smoke.mesh.material.getClassName(), 'PBRMaterial');
  assert.equal(smoke.mesh.material.emissiveColor.toHexString(), '#000000');
  const rocketCenter = worldPosition(rocket.x, rocket.y, 2.12);
  for (const [offset, coordinate] of [
    [12, rocketCenter.x],
    [13, rocketCenter.y],
    [14, rocketCenter.z],
  ])
    assert(Math.abs(f.fx.bodies[6].matrices[offset] - coordinate) < 1e-5);
  b.bullets = [];
  f.fx.update(b);
  assert.equal(f.fx.stats.bodies, 0);
  assert(f.fx.stats.retired > 0);
  b.elapsed += 0.6;
  f.fx.update(b);
  assert.equal(f.fx.stats.trails, 0);
  assert.equal(f.fx.stats.retired, 0);
  f.dispose();
});
await test('projectile history follows each actual shot through deletion, switching, homing and pause', () => {
  const f = projectileFixture(),
    first = visualBullet(0, 300),
    rocket = visualBullet(6, W / 2 + 120);
  const b = { elapsed: 0, weapon: 0, bullets: [first, rocket] };
  f.fx.update(b);
  for (let i = 0; i < 4; i++) {
    b.elapsed += 1 / 60;
    first.x += 10;
    rocket.x += 8;
    rocket.y += 4;
    f.fx.update(b);
  }
  const flight = f.fx.flights.get(rocket);
  const history = flight.points.map((point) => point.position.clone());
  b.bullets.shift();
  b.weapon = 1;
  rocket.vx = 0;
  rocket.vy = 620;
  rocket.y += 10;
  b.elapsed += 1 / 60;
  f.fx.update(b);
  assert.equal(f.fx.flights.size, 1);
  assert.equal(f.fx.flights.get(rocket), flight);
  assert.equal(flight.weapon, 6);
  assert(flight.points.every((point) => point.position.x > 10));
  assert(flight.points[0].position.equals(history[0]));
  const snapshot = JSON.stringify(flight),
    matrices = Array.from(f.fx.bodies[6].matrices);
  for (let i = 0; i < 20; i++) f.fx.update(b);
  assert.equal(JSON.stringify(flight), snapshot);
  assert.deepEqual(Array.from(f.fx.bodies[6].matrices), matrices);
  b.bullets = [];
  f.fx.update(b);
  assert.equal(f.fx.stats.bodies, 0);
  assert.equal(f.fx.stats.flights, 0);
  b.elapsed += 0.6;
  f.fx.update(b);
  assert.equal(f.fx.stats.retired, 0);
  assert.equal(f.fx.stats.trails, 0);
  assert(f.scene.meshes.every((mesh) => !mesh.isEnabled()));
  f.dispose();
});
await test('projectile batches and GPU buffers remain fixed across heavy mixed volleys at both detail levels', async () => {
  for (const mobile of [false, true]) {
    const f = projectileFixture(mobile),
      meshes = f.scene.meshes.length,
      materials = f.scene.materials.length;
    const b = { elapsed: 0, bullets: [] };
    for (let volley = 0; volley < 4; volley++) {
      b.bullets = Array.from({ length: 160 }, (_, i) =>
        visualBullet(i % 7, 500 + i),
      );
      for (let frame = 0; frame < 24; frame++) {
        b.elapsed += 1 / 60;
        b.bullets.forEach((bullet) => {
          bullet.x += 10;
        });
        f.fx.update(b);
        assert(f.fx.stats.bodies <= (mobile ? 48 : 100));
        assert(f.fx.stats.flights <= (mobile ? 48 : 100));
        assert(f.fx.stats.trails <= (mobile ? 72 : 240));
        assert(f.fx.stats.retired <= 24);
      }
    }
    assert.equal(f.scene.meshes.length, meshes);
    assert.equal(f.scene.materials.length, materials);
    assert.equal(f.scene.lights.length, 0);
    f.dispose();
    await flushSceneWork();
  }
});
await test('perimeter armor has no coplanar side triangles overlapping the concrete wall', () => {
  for (const [wall, view] of r.world.walls) {
    if (wall.kind !== 'boundary') continue;
    const armor = view.solid
      .getChildMeshes()
      .find((mesh) => mesh.material.name === 'perimeter-matte-armor');
    assert(armor && armor.material.roughness >= 0.7);
    armor.computeWorldMatrix(true);
    const vertices = armor.getVerticesData('position'),
      indices = armor.getIndices();
    const horizontal = wall.w > wall.h,
      axis = horizontal ? 'z' : 'x';
    const center = worldPosition(wall.x + wall.w / 2, wall.y + wall.h / 2);
    const half = (horizontal ? wall.h : wall.w) * 0.05;
    for (let i = 0; i < indices.length; i += 3) {
      const points = [0, 1, 2].map((j) =>
        Vector3.TransformCoordinates(
          Vector3.FromArray(vertices, indices[i + j] * 3),
          armor.getWorldMatrix(),
        ),
      );
      const overlapsHeight =
        Math.min(...points.map((p) => p.y)) < wall.height - 0.005 &&
        Math.max(...points.map((p) => p.y)) > 0.005;
      if (!overlapsHeight) continue;
      for (const side of [-1, 1])
        assert(
          !points.every(
            (point) =>
              Math.abs(point[axis] - (center[axis] + half * side)) < 1e-4,
          ),
          'steel and concrete must not compete at the same depth',
        );
    }
    for (const mesh of view.solid.getChildMeshes()) {
      if (
        ['perimeter-warning-yellow', 'perimeter-steady-reflector'].includes(
          mesh.material.name,
        )
      )
        assert.equal(mesh.receiveShadows, false);
    }
  }
  assert.equal(r.camera.minZ, 1);
});
await test('enemy specialists retain weapon silhouettes instead of sharing one red shell', () => {
  const f = projectileFixture();
  const b = {
    elapsed: 0,
    bullets: Array.from({ length: 7 }, (_, index) => ({
      ...visualBullet(index),
      enemy: true,
    })),
  };
  f.fx.update(b);
  assert.equal(f.fx.stats.bodies, 7);
  assert.equal(f.fx.enemyShell.count, 1);
  for (let index = 1; index < 7; index++)
    assert.equal(f.fx.bodies[index].count, 1);
  f.dispose();
});
await test('larger supplies are labeled, non-pickable, color-coded and bounded near the player', () => {
  const b = new Battle(0, true, config());
  b.walls = [];
  const view = new Renderer3D(canvas, b, {
    assets: false,
    headlessEngine: new NullEngine({
      renderWidth: 1280,
      renderHeight: 800,
      textureSize: 128,
    }),
  });
  b.pickups = Array.from({ length: 48 }, (_, i) => ({
    x: b.player.x + i * 4,
    y: b.player.y - 90,
    kind: 3,
    weapon: 1 + (i % 6),
    life: 10,
  }));
  view.draw(b, null);
  assert.equal(view.pickupPool.length, 20);
  assert(
    view.pickupPool.every((node) =>
      node.getChildMeshes().every((mesh) => !mesh.isPickable),
    ),
  );
  const first = view.pickupPool[0];
  assert(
    first
      .getChildMeshes()
      .some(
        (mesh) =>
          mesh.name === 'supply-label' &&
          mesh.material.name === 'supply-label-1',
      ),
  );
  const box = first
    .getChildMeshes()
    .find((mesh) => mesh.name === 'supply-case');
  box.computeWorldMatrix(true);
  assert(box.getBoundingInfo().boundingBox.extendSizeWorld.x > 1.5);
  const count = view.meshCount;
  for (let i = 0; i < 20; i++) view.draw(b, null);
  assert.equal(view.meshCount, count);
  b.pickups = [];
  view.draw(b, null);
  assert(view.pickupPool.every((node) => !node.isEnabled()));
  view.dispose();
});
await test('weapon impacts use short colored volumes and ground covers every enlarged boundary', () => {
  const b = new Battle(0, true, config());
  b.walls = [];
  const view = new Renderer3D(canvas, b, {
    assets: false,
    headlessEngine: new NullEngine({
      renderWidth: 1280,
      renderHeight: 800,
      textureSize: 128,
    }),
  });
  for (let weapon = 0; weapon < 7; weapon++)
    b.explosions.push({
      id: weapon + 1,
      x: b.player.x,
      y: b.player.y - 20,
      kind: 'impact',
      weapon,
      bornAt: 0,
      scale: 0.65,
    });
  b.elapsed = 0.12;
  view.draw(b, null);
  const styles = new Set(
    view.explosions.sprites
      .filter((mesh) => mesh.isEnabled())
      .map((mesh) => mesh.metadata.weapon),
  );
  assert.equal(styles.size, 7);
  b.elapsed = 0.7;
  view.draw(b, null);
  assert(view.explosions.sprites.every((mesh) => !mesh.isEnabled()));
  const ground = view.world.ground;
  ground.computeWorldMatrix(true);
  const extents = ground.getBoundingInfo().boundingBox.extendSizeWorld;
  assert(extents.x > W * 0.05 && extents.z > H * 0.05);
  view.dispose();
});
await test('received hits keep their flash, fire and sparks under load, then clear the tank quickly at both quality levels', async () => {
  for (const quality of ['performance', 'balanced']) {
    const b = new Battle(0, true, config(), 85);
    const view = new Renderer3D(canvas, b, {
      assets: false,
      quality,
      headlessEngine: new NullEngine({
        renderWidth: 1280,
        renderHeight: 800,
        textureSize: 128,
      }),
    });
    const hit = {
      id: 901,
      x: b.player.x,
      y: b.player.y,
      bornAt: 0,
      scale: 1.4,
      kind: 'impact',
      weapon: 0,
      playerHit: true,
    };
    // Later incoming pellets must not evict the main damage flash in the 3-slot budget.
    b.explosions = [
      hit,
      ...Array.from({ length: 12 }, (_, i) => ({
        ...hit,
        id: 902 + i,
        playerHit: false,
        scale: 0.45,
      })),
    ];
    b.elapsed = 0.08;
    const snapshot = JSON.stringify(b);
    view.draw(b, null);
    assert.equal(JSON.stringify(b), snapshot);
    const active = () =>
      view.explosions.sprites.filter((mesh) => mesh.isEnabled());
    const modes = new Set(active().map((mesh) => mesh.metadata.mode));
    for (const mode of [0, 1, 2, 3, 6])
      assert(modes.has(mode), 'damage effect layer ' + mode);
    assert(active().filter((mesh) => mesh.metadata.mode === 6).length >= 5);
    assert(
      active().some((mesh) => mesh.metadata.mode === 3 && mesh.scaling.x > 5),
    );
    assert.equal(view.explosions.light.intensity > 0, quality === 'balanced');
    b.paused = true;
    const frozen = JSON.stringify(
      active().map((m) => [
        m.metadata,
        m.position.asArray(),
        m.scaling.asArray(),
      ]),
    );
    view.draw(b, null);
    assert.equal(
      JSON.stringify(
        active().map((m) => [
          m.metadata,
          m.position.asArray(),
          m.scaling.asArray(),
        ]),
      ),
      frozen,
    );
    b.paused = false;
    b.elapsed = 0.8;
    view.draw(b, null);
    assert(
      active().length > 0 && active().every((mesh) => mesh.metadata.mode === 1),
      'brief smoke tail, not a wreck fire',
    );
    b.elapsed = 1.21;
    view.draw(b, null);
    assert.equal(active().length, 0);
    assert.equal(view.explosions.light.intensity, 0);
    for (const weapon of [3, 5]) {
      b.explosions = [{ ...hit, weapon }];
      b.elapsed = 0.08;
      view.draw(b, null);
      assert(active().every((mesh) => mesh.metadata.weapon === weapon));
    }
    const ages = [0.04, 0.15, 0.4, 0.8, 1.21];
    b.explosions = Array.from({ length: 32 }, (_, i) => ({
      ...hit,
      id: i + 1000,
    }));
    for (const age of ages) {
      b.elapsed = age;
      view.draw(b, null);
    }
    const warmed = [
      view.meshCount,
      view.scene.materials.length,
      view.scene.lights.length,
    ];
    for (const age of ages) {
      b.elapsed = age;
      view.draw(b, null);
      assert.deepEqual(
        [view.meshCount, view.scene.materials.length, view.scene.lights.length],
        warmed,
      );
    }
    assert(
      view.explosions.sprites.length <= (quality === 'performance' ? 33 : 119),
    );
    assert(view.explosions.sprites.every((mesh) => !mesh.isPickable));
    view.dispose();
    await flushSceneWork();
  }
});
await test('mine models show team markers, are reused after EMP and never mutate combat', () => {
  const b = new Battle(0, true, config(), 93);
  const view = new Renderer3D(canvas, b, {
    assets: false,
    headlessEngine: new NullEngine({
      renderWidth: 1280,
      renderHeight: 800,
      textureSize: 128,
    }),
  });
  b.walls = [];
  b.enemies = [];
  b.spawnTimer = 999;
  assert(b.layMine());
  b.mines[0].enemy = true;
  const snapshot = JSON.stringify(b);
  view.draw(b, null);
  assert.equal(JSON.stringify(b), snapshot);
  const marker = view.scene.getMeshByName('mine-team-marker');
  assert(marker && marker.isEnabled());
  assert.equal(marker.material, view.materials.red);
  assert(!marker.isPickable);
  const meshCount = view.meshCount;
  b.step(0.01, { ...idle, emp: true });
  view.draw(b, null);
  assert(!marker.isEnabled());
  b.mineCd = 0;
  b.player.x += 200;
  assert(b.layMine());
  view.draw(b, null);
  assert(marker.isEnabled());
  assert.equal(marker.material, view.materials.blue);
  assert.equal(view.meshCount, meshCount);
  b.explode(b.player.x, b.player.y - 50, 1, 'armor');
  b.elapsed += 0.4;
  view.draw(b, null);
  assert(
    view.explosions.sprites.some((m) => m.isEnabled() && m.metadata.mode === 5),
  );
  assert(
    view.materials.armor.metallic < 0.3 && view.materials.armor.roughness > 0.7,
  );
  view.dispose();
  assert(view.scene.isDisposed);
});
await test('falling cannon rounds point along their actual three-dimensional velocity', () => {
  const f = projectileFixture();
  for (const angle of [0, Math.PI / 2, Math.PI, -Math.PI / 2]) {
    const round = {
      ...visualBullet(0),
      vx: Math.cos(angle) * 1240,
      vy: Math.sin(angle) * 1240,
      verticalVelocity: -4,
    };
    f.fx.update({ elapsed: 0.2, bullets: [round] });
    const matrix = Matrix.FromArray(f.fx.bodies[0].matrices);
    const forward = Vector3.TransformNormal(
      new Vector3(0, 0, 1),
      matrix,
    ).normalize();
    const velocity = new Vector3(
      round.vx,
      round.verticalVelocity,
      round.vy,
    ).normalize();
    assert(Vector3.Distance(forward, velocity) < 1e-6);
  }
  f.dispose();
});
await test('cannon muzzle smoke stays at the firing location, freezes on pause, expires, and never fires from damage', () => {
  const e = new NullEngine();
  const scene = new Scene(e);
  const fx = new MuzzleEffects(scene, true);
  const b = {
    elapsed: 1,
    player: { x: 1000, y: 800, flash: 0.09 },
    enemies: [],
  };
  fx.update(b);
  assert.equal(fx.stats.visible, 0);
  b.player.lastShot = {
    at: 1,
    x: 1032,
    y: 800,
    angle: 0,
    height: 21.2,
    weapon: 0,
  };
  fx.update(b);
  assert.equal(fx.stats.active, 1);
  assert.equal(fx.stats.visible, 2);
  b.elapsed = 1.15;
  fx.update(b);
  assert(
    fx.pool
      .filter((m) => m.isEnabled())
      .every((m) => m.metadata.mode === 1 || m.metadata.mode === 5),
  );
  const snapshot = () =>
    JSON.stringify(
      fx.pool.map((m) => [
        m.position.asArray(),
        m.scaling.asArray(),
        m.metadata,
        m.isEnabled(),
      ]),
    );
  const frozen = snapshot();
  b.player.x += 500;
  b.player.y += 500;
  fx.update(b);
  assert.equal(
    snapshot(),
    frozen,
    'smoke cannot follow a moving tank or advance while paused',
  );
  assert.equal(fx.stats.active, 1, 'same shot cannot be replayed each render');
  b.elapsed = 1.8;
  fx.update(b);
  assert.equal(fx.stats.visible, 0);
  assert.equal(fx.stats.active, 0);
  for (let volley = 0; volley < 100; volley++) {
    b.elapsed += 0.01;
    b.enemies = Array.from({ length: 30 }, (_, i) => ({
      lastShot: { ...b.player.lastShot, x: 1000 + i, at: b.elapsed },
    }));
    fx.update(b);
    assert(
      fx.stats.active <= 8 && fx.stats.visible <= 24 && fx.stats.pooled <= 24,
    );
  }
  assert.equal(scene.lights.length, 0);
  fx.update(b, 0);
  assert.equal(fx.stats.visible, 0);
  b.elapsed = 0;
  b.player.lastShot = undefined;
  b.enemies = [];
  fx.update(b);
  assert.equal(fx.stats.active, 0);
  assert.equal(recoilDistance(0, Infinity), 0);
  assert.equal(recoilDistance(0, 0), 0);
  assert(recoilDistance(0, 0.025) > 0.45);
  assert(recoilDistance(0, 0.08) > recoilDistance(0, 0.2));
  assert.equal(recoilDistance(0, 0.34), 0);
  fx.dispose();
  assert.equal(scene.meshes.length, 0);
  scene.dispose();
  e.dispose();
});
await test('renderer teardown releases all scene resources and is idempotent', () => {
  r.dispose();
  assert(r.disposed);
  assert(r.scene.isDisposed);
  assert.equal(r.models.size, 0);
  r.dispose();
});
console.log(`\n${passed} Babylon.js 3D integration checks passed.`);
console.log(
  `Peak resident memory: ${(process.resourceUsage().maxRSS / 1024).toFixed(0)} MiB.`,
);
