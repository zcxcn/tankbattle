import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { createHash } from 'node:crypto';
const manifest = JSON.parse(
  await fs.readFile('mobile/baseline/manifest.json', 'utf8'),
);
for (const [file, expected] of Object.entries(manifest.files)) {
  const bytes = await fs.readFile(file);
  // Git may convert line endings; game semantics must remain exactly the same.
  const normalized = /\.(tsx?|css|java|xml|gradle|properties)$/.test(file)
    ? Buffer.from(bytes.toString('utf8').replaceAll('\r\n', '\n'))
    : bytes;
  assert.equal(
    createHash('sha256').update(normalized).digest('hex'),
    expected,
    `Android baseline changed: ${file}`,
  );
}
console.log(
  `Android baseline verified: ${Object.keys(manifest.files).length} frozen source, native and asset files unchanged.`,
);
