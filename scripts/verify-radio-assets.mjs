import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import ts from 'typescript';

const js = ts.transpileModule(
  await fs.readFile('lib/tactical-radio.ts', 'utf8'),
  {
    compilerOptions: {
      module: ts.ModuleKind.ES2022,
      target: ts.ScriptTarget.ES2022,
    },
  },
).outputText;
const { RADIO_LINES } = await import(
  'data:text/javascript;base64,' + Buffer.from(js).toString('base64')
);
const assets = await fs.readFile('lib/radio-assets.ts', 'utf8');
const wavFiles = (await fs.readdir('web/audio/radio'))
  .filter((name) => name.endsWith('.wav'))
  .sort();
assert.deepEqual(
  wavFiles,
  Object.keys(RADIO_LINES)
    .map((id) => id + '.wav')
    .sort(),
);
let bytes = 0;
for (const [id, line] of Object.entries(RADIO_LINES)) {
  assert(/^[\x20-\x7e]+$/.test(line), 'English radio script');
  assert(assets.includes(`import ${id} from '../web/audio/radio/${id}.wav'`));
  const wav = await fs.readFile('web/audio/radio/' + id + '.wav');
  bytes += wav.length;
  assert.equal(wav.toString('ascii', 0, 4), 'RIFF');
  assert.equal(wav.toString('ascii', 8, 12), 'WAVE');
  assert.equal(wav.readUInt16LE(20), 1);
  assert.equal(wav.readUInt16LE(22), 1);
  assert.equal(wav.readUInt32LE(24), 22050);
  assert.equal(wav.readUInt16LE(34), 16);
  const frames = wav.readUInt32LE(40) / 2;
  const duration = frames / 22050;
  assert(duration > 0.6 && duration < 3.8, id + ' bounded speech duration');
  let peak = 0,
    energy = 0;
  for (let i = 0; i < frames; i++) {
    const sample = wav.readInt16LE(44 + i * 2) / 32768;
    peak = Math.max(peak, Math.abs(sample));
    energy += sample * sample;
  }
  assert(peak > 0.6 && peak < 0.9, id + ' clear unclipped level');
  assert(Math.sqrt(energy / frames) > 0.1, id + ' audible voice');
  assert.equal(wav.readInt16LE(44), 0);
  assert.equal(wav.readInt16LE(wav.length - 2), 0);
}
assert(bytes < 2500000, 'Small bundled radio library');
console.log(
  `PASS ${wavFiles.length} English radio clips, ${(bytes / 1048576).toFixed(2)} MiB, safe peaks and durations; web-only imports.`,
);
