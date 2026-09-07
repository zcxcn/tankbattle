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
const surfaceFiles = (await fs.readdir('web/assets/surfaces')).filter((file) =>
  file.endsWith('.webp'),
);
const visualFiles = [
  'web/assets/iron-embers-cover.png',
  ...surfaceFiles.map((file) => 'web/assets/surfaces/' + file),
];
let visualBytes = 0;
const publishedVisuals = [];
for (const file of visualFiles) {
  const ext = path.extname(file);
  const id = path.basename(file, ext);
  const published = assets.filter(
    (asset) => asset.startsWith(id + '-') && asset.endsWith(ext),
  );
  assert.equal(published.length, 1, 'one hashed visual asset: ' + id);
  const source = await fs.readFile(file);
  visualBytes += source.length;
  assert.deepEqual(
    await fs.readFile(path.join(root, 'assets', published[0])),
    source,
  );
  publishedVisuals.push(base + 'assets/' + published[0]);
}
assert(
  visualBytes < 8 * 1024 * 1024,
  'new visual assets must stay below 8 MiB',
);
const radioFiles = (await fs.readdir('web/audio/radio')).filter((file) =>
  file.endsWith('.wav'),
);
for (const file of radioFiles) {
  const id = file.slice(0, -4);
  const published = assets.filter(
    (asset) => asset.startsWith(id + '-') && asset.endsWith('.wav'),
  );
  assert.equal(published.length, 1, 'one hashed radio clip: ' + id);
  assert.deepEqual(
    await fs.readFile(path.join(root, 'assets', published[0])),
    await fs.readFile(path.join('web/audio/radio', file)),
  );
}
let cssCount = 0,
  jsCount = 0;
let jsContent = '';
for (const file of assets) {
  if (!file.endsWith('.js') && !file.endsWith('.css')) continue;
  const content = await fs.readFile(path.join(root, 'assets', file), 'utf8');
  if (file.endsWith('.js')) {
    jsCount++;
    jsContent += content;
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
for (const url of publishedVisuals)
  assert(
    jsContent.includes(url),
    'visual asset must use the Pages base URL: ' + url,
  );
assert(!(await fs.stat(path.join(root, '.openai')).catch(() => null)));
console.log(
  `Pages verified: ${required.length} required assets, ${radioFiles.length} English voice clips, ${visualFiles.length} new visual assets (${(visualBytes / 1048576).toFixed(2)} MiB), ${jsCount} JS chunks, ${cssCount} stylesheets; root and /tankbattle/ asset URLs pass.`,
);
