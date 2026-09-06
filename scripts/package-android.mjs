import fs from 'node:fs/promises';
import path from 'node:path';

const root = path.resolve('outputs/android-web');
// All Android source references are rewritten by the mobile Vite plugin before hashing.
for (const name of ['armor-texture.png', 'ground-texture.png', 'keyart.png'])
  await fs.rm(path.join(root, name), { force: true });
const files = await fs.readdir(root, { recursive: true });
for (const name of files.filter((v) => /\.(js|css|html)$/.test(v))) {
  const text = await fs.readFile(path.join(root, name), 'utf8');
  if (/\/(armor-texture|ground-texture|keyart)\.png/.test(text))
    throw new Error(`Unoptimized texture reference in ${name}`);
}
for (const name of [
  'index.html',
  'environment.env',
  'mobile/armor.webp',
  'mobile/ground.webp',
  'mobile/keyart.webp',
])
  await fs.access(path.join(root, name));
console.log(
  'Offline Android assets verified; optimized WebP textures included.',
);
