import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import ts from 'typescript';
import { NullEngine } from '@babylonjs/core/Engines/nullEngine.js';
import { TimingTools } from '@babylonjs/core/Misc/timingTools.js';

const root = path.resolve('outputs/test-surface-materials');
await fs.mkdir(path.join(root, 'three'), { recursive: true });
for (const name of [
  'progression',
  'three/babylon',
  'three/surface-textures',
  'three/materials',
  'three/tank-model',
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
      (_, q, url) => `from ${q}${url}.js${q}`,
    );
  await fs.writeFile(path.join(root, `${name}.js`), js);
}
const { Scene, Texture } = await import(
  pathToFileURL(path.join(root, 'three/babylon.js'))
);
const { createMaterials, pbr } = await import(
  pathToFileURL(path.join(root, 'three/materials.js'))
);
const { applySurface } = await import(
  pathToFileURL(path.join(root, 'three/surface-textures.js'))
);
const { buildTank } = await import(
  pathToFileURL(path.join(root, 'three/tank-model.js'))
);
const { EVOLUTIONS } = await import(
  pathToFileURL(path.join(root, 'progression.js'))
);

// NullEngine creates real Texture/PBRMaterial objects without fetching image
// bytes. Pages verification checks their emitted files; this tests bindings.
const engine = new NullEngine();
const scene = new Scene(engine);
try {
  const plain = createMaterials(scene, false);
  for (const name of ['armor', 'enemy', 'heavy', 'brick', 'ground', 'concrete'])
    assert.equal(
      plain[name].albedoTexture,
      null,
      'assets=false skips surface images',
    );
  const mats = createMaterials(scene, true);
  const generated = (material, file) => {
    assert(material.albedoTexture.url.endsWith(`/generated/${file}?url`));
    assert.equal(material.albedoTexture.gammaSpace, true);
    assert.equal(material.bumpTexture, null, 'no unrelated scanned relief');
    assert.equal(material.metallicTexture, null, 'use scalar roughness');
    assert.equal(material.useRoughnessFromMetallicTextureGreen, false);
    assert.equal(material.useRoughnessFromMetallicTextureAlpha, false);
  };
  for (const name of ['armor', 'enemy', 'heavy', 'brick']) {
    generated(
      mats[name],
      name === 'brick' ? 'brick-wall-v1.webp' : 'armor-painted-v1.webp',
    );
    assert.deepEqual(mats[name].albedoColor, plain[name].albedoColor);
    assert.equal(mats[name].roughness, plain[name].roughness);
    assert.equal(mats[name].metallic, plain[name].metallic);
  }
  assert.equal(mats.enemy.albedoTexture, mats.armor.albedoTexture);
  assert.equal(mats.heavy.albedoTexture, mats.armor.albedoTexture);

  const roof = pbr(scene, 'roof-test', '#919493', 0.62, 0.63);
  const shutter = pbr(scene, 'shutter-test', '#6e7a78', 0.55, 0.66);
  applySurface(roof, scene, 'roof');
  applySurface(shutter, scene, 'paintedMetal');
  assert(
    roof.albedoTexture.url.endsWith('/surfaces/painted-metal-color.webp?url'),
  );
  assert(
    roof.bumpTexture.url.endsWith('/surfaces/painted-metal-normal.webp?url'),
  );
  assert(
    roof.metallicTexture.url.endsWith(
      '/surfaces/painted-metal-roughness.webp?url',
    ),
  );
  assert.equal(roof.albedoTexture, shutter.albedoTexture);
  assert.notEqual(roof.albedoTexture, mats.armor.albedoTexture);
  assert.equal(roof.bumpTexture.gammaSpace, false);
  assert.equal(roof.metallicTexture.gammaSpace, false);
  assert.equal(roof.useRoughnessFromMetallicTextureGreen, true);
  assert.equal(roof.invertNormalMapY, true);

  // Rebinding an existing scanned material must clear its old auxiliary maps.
  const road = pbr(scene, 'road-test', '#d2d7d5', 0.02, 0.9);
  applySurface(road, scene, 'concrete');
  applySurface(road, scene, 'asphalt', { repeat: 3 });
  generated(road, 'asphalt-v1.webp');
  assert.equal(road.roughness, 0.9);
  assert.equal(road.albedoTexture.uScale, 3);
  assert.equal(road.albedoTexture.vScale, 3);
  assert.equal(road.albedoTexture.wrapU, Texture.WRAP_ADDRESSMODE);
  assert.equal(road.albedoTexture.wrapV, Texture.WRAP_ADDRESSMODE);
  assert.equal(road.albedoTexture.anisotropicFilteringLevel, 8);
  const roadAgain = pbr(scene, 'road-again', '#ffffff');
  const count = scene.textures.length;
  applySurface(roadAgain, scene, 'asphalt', { repeat: 3, strength: 0.1 });
  assert.equal(roadAgain.albedoTexture, road.albedoTexture);
  assert.equal(scene.textures.length, count, 'reuse albedo with no normal map');
  applySurface(roadAgain, scene, 'asphalt', { repeat: 3, mobile: true });
  assert.notEqual(roadAgain.albedoTexture, road.albedoTexture);
  assert.equal(roadAgain.albedoTexture.anisotropicFilteringLevel, 2);
  assert.equal(road.albedoTexture.anisotropicFilteringLevel, 8);
  console.log(
    'PASS generated material bindings, scanned industrial surfaces and tiling cache',
  );

  const armorTexture = mats.armor.albedoTexture;
  for (const evolution of [EVOLUTIONS[0], EVOLUTIONS.at(-1)]) {
    const model = buildTank(
      scene,
      mats,
      1,
      false,
      false,
      evolution.level,
      true,
    );
    const armor = model.meshes.find(
      (mesh) => mesh.material.name === `evolution-armor-${evolution.level}`,
    )?.material;
    assert(armor, 'player model must actually use its evolution material');
    generated(armor, 'armor-painted-v1.webp');
    assert.equal(armor.albedoTexture, armorTexture);
    assert.equal(
      armor.albedoColor.toHexString().toLowerCase(),
      evolution.color,
    );
    model.dispose();
    assert(
      scene.textures.includes(armorTexture),
      'tank disposal preserves shared texture',
    );
    await new Promise((resolve) => TimingTools.SetImmediate(resolve));
    await new Promise((resolve) => setImmediate(resolve));
  }
  console.log(
    'PASS first and final evolution inherit generated armor and preserve shared textures',
  );

  const owned = [...scene.textures];
  const disposed = new Map(owned.map((texture) => [texture, 0]));
  for (const texture of owned)
    texture.onDisposeObservable.add(() =>
      disposed.set(texture, disposed.get(texture) + 1),
    );
  scene.dispose();
  for (const count of disposed.values()) assert.equal(count, 1);
  const nextScene = new Scene(engine);
  try {
    const next = createMaterials(nextScene, true);
    generated(next.armor, 'armor-painted-v1.webp');
    assert.notEqual(next.armor.albedoTexture, armorTexture);
    assert.equal(next.armor.albedoTexture.getScene(), nextScene);
  } finally {
    nextScene.dispose();
  }
  console.log(
    'PASS scene disposal releases every texture and a new scene gets fresh bindings',
  );
} finally {
  scene.dispose();
  engine.dispose();
}
