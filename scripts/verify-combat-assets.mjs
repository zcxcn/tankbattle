import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { createHash } from 'node:crypto';

const directory = 'web/audio/combat/';
const provenance = JSON.parse(
  await fs.readFile(directory + 'provenance.json', 'utf8'),
);
const manifest = await fs.readFile('lib/combat-audio-assets.ts', 'utf8');
const files = (await fs.readdir(directory))
  .filter((file) => file.endsWith('.wav'))
  .sort();
assert.deepEqual(files, provenance.files.map((entry) => entry.file).sort());
const imports = [
  ...manifest.matchAll(/from '\.\.\/web\/audio\/combat\/([^']+)'/g),
]
  .map((m) => m[1])
  .sort();
assert.deepEqual(
  files,
  imports,
  'every shipped recording is wired into the web audio manifest',
);
let bytes = 0;
for (const entry of provenance.files) {
  const wav = await fs.readFile(directory + entry.file);
  bytes += wav.length;
  assert.equal(
    createHash('sha256').update(wav).digest('hex'),
    entry.sha256,
    entry.file + ' provenance hash',
  );
  assert.equal(wav.length, entry.bytes);
  assert.equal(wav.toString('ascii', 0, 4), 'RIFF');
  assert.equal(wav.toString('ascii', 8, 12), 'WAVE');
  assert.equal(wav.readUInt16LE(20), 1, 'PCM');
  assert.equal(wav.readUInt16LE(22), 1, 'mono');
  assert.equal(wav.readUInt16LE(34), 16);
  const sampleRate = wav.readUInt32LE(24),
    frames = wav.readUInt32LE(40) / 2;
  assert([44100, 48000].includes(sampleRate));
  const duration = frames / sampleRate;
  assert(duration > 0.1 && duration <= 5);
  assert(Math.abs(duration - entry.durationSeconds) < 0.00001);
  let peak = 0,
    energy = 0,
    steps = 0,
    tail = 0;
  for (let i = 0; i < frames; i++) {
    const sample = wav.readInt16LE(44 + i * 2) / 32768;
    peak = Math.max(peak, Math.abs(sample));
    energy += sample * sample;
    if (i > sampleRate * 0.35) tail += sample * sample;
    if (i) steps += (wav.readInt16LE(42 + i * 2) / 32768 - sample) ** 2;
  }
  assert(peak > 0.4 && peak < 0.9, entry.file + ' unclipped headroom');
  assert(Math.sqrt(energy / frames) > 0.015, entry.file + ' audible signal');
  if (entry.loop) {
    const seam =
      Math.abs(wav.readInt16LE(44) - wav.readInt16LE(wav.length - 2)) / 32768;
    assert(
      seam < Math.sqrt(steps / (frames - 1)) * 5,
      entry.file + ' natural loop seam',
    );
  } else {
    assert.equal(wav.readInt16LE(44), 0, entry.file + ' start fade');
    assert.equal(wav.readInt16LE(wav.length - 2), 0, entry.file + ' end fade');
  }
  if (entry.kind === 'cannon') {
    assert(duration > 2.5, 'retain the field recording decay');
    assert(
      tail / energy > 0.025,
      entry.file + ' audible decay after initial report',
    );
  }
  assert(entry.sources.length && entry.processing.length > 30);
  for (const id of entry.sources) {
    const source = provenance.sources.find((source) => source.id === id);
    assert(
      source?.sourceUrl?.startsWith('https://'),
      entry.file + ' exact source',
    );
    assert(
      source.creator && source.title && source.license && source.licenseUrl,
    );
  }
}
assert.equal(bytes, provenance.totalBytes);
assert(bytes < 5 * 1048576, 'small self-hosted combat library');
console.log(
  `PASS ${files.length} combat recordings, ${(bytes / 1048576).toFixed(2)} MiB, PCM/hashes/levels/loops/tails and source attribution.`,
);
