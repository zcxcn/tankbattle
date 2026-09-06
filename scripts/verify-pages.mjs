import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import ts from 'typescript';

const root = path.resolve('outputs/github-pages');
const base = '/tankbattle/';
const html = await fs.readFile(path.join(root, 'index.html'), 'utf8');
assert(html.includes('钢铁余烬 · 3D 坦克大战'));
assert(!html.includes('Android</title>'));
const resourceUrls = [...html.matchAll(/(?:src|href)="([^"]+)"/g)].map(
  (m) => m[1],
);
assert(resourceUrls.some((url) => url.startsWith(base + 'assets/')));
for (const url of resourceUrls) {
  assert(
    url.startsWith(base),
    'HTML resource must stay under /tankbattle/: ' + url,
  );
  await fs.access(path.join(root, url.slice(base.length)));
}
const required = [
  'keyart.png',
  'favicon.svg',
  'aim-cursor.svg',
  'armor-texture.png',
  'ground-texture.png',
  'environment.env',
  'woodland-ground.webp',
  'mobile/armor.webp',
  'mobile/ground.webp',
  'mobile/keyart.webp',
  'music/industrial-war.wav',
  'music/electronic-pursuit.wav',
  'music/epic-siege.wav',
];
for (const file of required)
  assert((await fs.stat(path.join(root, file))).size > 0, file);
const assetSource = await fs.readFile('lib/asset-url.ts', 'utf8');
const js = ts.transpileModule(assetSource, {
  compilerOptions: { module: ts.ModuleKind.ES2022 },
}).outputText;
for (const mount of ['/', base]) {
  const assetModule = await import(
    'data:text/javascript;base64,' +
      Buffer.from(
        `const __GAME_BASE_PATH__ = ${JSON.stringify(mount)};\n` + js,
      ).toString('base64')
  );
  for (const file of required) {
    assert.equal(assetModule.assetUrl('/' + file), mount + file);
    assert.equal(assetModule.assetUrl(file), mount + file);
  }
  assert.equal(assetModule.assetUrl('/'), mount);
}
const assets = await fs.readdir(path.join(root, 'assets'));
let cssCount = 0,
  jsCount = 0;
for (const file of assets) {
  const content = await fs.readFile(path.join(root, 'assets', file), 'utf8');
  if (file.endsWith('.js')) {
    jsCount++;
    for (const match of content.matchAll(
      /(?:from|import\()\s*["'](\.\/[^"']+\.js)["']/g,
    )) {
      await fs.access(path.join(root, 'assets', match[1]));
    }
  }
  if (file.endsWith('.css')) {
    cssCount++;
    for (const match of content.matchAll(/url\(["']?([^"')]+)["']?\)/g)) {
      if (match[1].startsWith('data:')) continue;
      assert(
        match[1].startsWith(base),
        'CSS asset escapes Pages path: ' + match[1],
      );
      await fs.access(path.join(root, match[1].slice(base.length)));
    }
  }
}
assert(cssCount > 0 && jsCount > 0);
assert(!(await fs.stat(path.join(root, '.openai')).catch(() => null)));
console.log(
  `Pages verified: ${required.length} required assets, ${jsCount} JS chunks, ${cssCount} stylesheets; root and /tankbattle/ asset URLs pass.`,
);
