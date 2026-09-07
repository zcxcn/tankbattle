import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import ts from 'typescript';

const tmp = await fs.mkdtemp(path.join(os.tmpdir(), 'iron-music-'));
const source = await fs.readFile(
  new URL('../lib/music.ts', import.meta.url),
  'utf8',
);
await fs.writeFile(
  path.join(tmp, 'music.mjs'),
  ts
    .transpileModule(source, {
      compilerOptions: {
        module: ts.ModuleKind.ES2022,
        target: ts.ScriptTarget.ES2022,
      },
    })
    .outputText.replace("'./asset-url'", "'./asset-url.mjs'"),
);
await fs.writeFile(
  path.join(tmp, 'asset-url.mjs'),
  ts.transpileModule(
    await fs.readFile(new URL('../lib/asset-url.ts', import.meta.url), 'utf8'),
    {
      compilerOptions: {
        module: ts.ModuleKind.ES2022,
        target: ts.ScriptTarget.ES2022,
      },
    },
  ).outputText,
);
const { GameMusic } = await import(pathToFileURL(path.join(tmp, 'music.mjs')));
let passed = 0;
const test = async (name, fn) => {
  await fn();
  passed++;
  console.log('PASS ' + name);
};
const tick = () => new Promise((resolve) => setImmediate(resolve));
const settle = async () => {
  for (let i = 0; i < 12; i++) await tick();
};
const files = await Promise.all(
  ['industrial-war', 'electronic-pursuit', 'epic-siege'].map((name) =>
    fs.readFile(new URL(`../public/music/${name}.wav`, import.meta.url)),
  ),
);

class Param {
  value = 1;
  cancelScheduledValues() {}
  setValueAtTime(value) {
    this.value = value;
  }
  setTargetAtTime(value) {
    this.value = value;
  }
}
class Node {
  disconnected = false;
  connect(target) {
    this.target = target;
  }
  disconnect() {
    this.disconnected = true;
  }
}
class Source extends Node {
  starts = [];
  playbackRate = new Param();
  stops = 0;
  start(at) {
    this.starts.push(at);
  }
  stop() {
    this.stops++;
  }
}
class Context {
  static instances = [];
  static blocked = false;
  state = 'suspended';
  currentTime = 0;
  destination = new Node();
  sampleRate = 32000;
  createBuffer(channels, length, sampleRate) {
    return {
      duration: length / sampleRate,
      length,
      copyToChannel() {},
      getChannelData: () => new Float32Array(length),
    };
  }
  gains = [];
  sources = [];
  resumes = 0;
  constructor() {
    Context.instances.push(this);
  }
  createGain() {
    const node = new Node();
    node.gain = new Param();
    this.gains.push(node);
    return node;
  }
  createDynamicsCompressor() {
    const node = new Node();
    for (const prop of ['threshold', 'knee', 'ratio', 'attack', 'release'])
      node[prop] = new Param();
    return node;
  }
  createBufferSource() {
    const source = new Source();
    this.sources.push(source);
    return source;
  }
  async decodeAudioData(bytes) {
    const wav = Buffer.from(bytes);
    return {
      duration:
        wav.readUInt32LE(40) / wav.readUInt16LE(32) / wav.readUInt32LE(24),
    };
  }
  async resume() {
    this.resumes++;
    if (Context.blocked) throw new Error('User activation required');
    this.state = 'running';
    this.onstatechange?.();
  }
  async suspend() {
    this.state = 'suspended';
    this.onstatechange?.();
  }
  async close() {
    this.state = 'closed';
    this.onstatechange?.();
  }
}
const originalFetch = globalThis.fetch,
  originalContext = globalThis.AudioContext;
const response = (i) => ({
  ok: true,
  arrayBuffer: async () =>
    files[i].buffer.slice(
      files[i].byteOffset,
      files[i].byteOffset + files[i].byteLength,
    ),
});
let requests = 0;
const fetchMusic = async (url) => {
  requests++;
  return response(
    ['industrial-war', 'electronic-pursuit', 'epic-siege'].findIndex((name) =>
      url.includes(name),
    ),
  );
};
globalThis.AudioContext = Context;
globalThis.fetch = fetchMusic;
try {
  await test('three intense original loops have complete stereo bars, strong signal and clean seams', () => {
    for (const [index, file] of files.entries()) {
      assert.equal(file.toString('ascii', 0, 4), 'RIFF');
      assert.equal(file.toString('ascii', 8, 12), 'WAVE');
      assert.equal(file.readUInt16LE(20), 1);
      assert.equal(file.readUInt16LE(22), 2);
      assert.equal(file.readUInt16LE(34), 16);
      assert.equal(file.readUInt32LE(24), 32000);
      const frames = file.readUInt32LE(40) / 4;
      assert.equal(
        frames,
        Math.round(((32 * 60) / [136, 160, 144][index]) * 32000),
      );
      let peak = 0,
        sum = 0;
      for (let c = 0; c < 2; c++) {
        let previous = file.readInt16LE(44 + c * 2) / 32768,
          differences = 0;
        for (let frame = 0; frame < frames; frame++) {
          const sample = file.readInt16LE(44 + frame * 4 + c * 2) / 32768;
          peak = Math.max(peak, Math.abs(sample));
          sum += sample * sample;
          differences += (sample - previous) ** 2;
          previous = sample;
        }
        const seam = Math.abs(file.readInt16LE(44 + c * 2) / 32768 - previous);
        assert(
          seam < Math.sqrt(differences / (frames - 1)),
          'loop seam must not exceed ordinary waveform steps',
        );
      }
      assert(peak < 0.9 && peak > 0.8);
      assert(Math.sqrt(sum / (frames * 2)) > 0.2);
    }
  });
  await test('music stays silent before user activation and lazily starts one selected source only once', async () => {
    const states = [],
      count = Context.instances.length,
      before = requests;
    const music = new GameMusic((status) => states.push(status));
    music.setPreferences(true, 40);
    music.setScene('battle');
    assert.equal(Context.instances.length, count);
    music.unlock();
    await settle();
    const c = Context.instances.at(-1);
    assert.equal(c.sources.length, 1);
    assert(
      c.sources.every(
        (s) =>
          s.loop &&
          Math.abs(s.loopEnd - 14.11765625) < 0.0001 &&
          s.starts[0] === c.sources[0].starts[0],
      ),
    );
    for (let i = 0; i < 30; i++) {
      music.setScene(i % 2 ? 'boss' : 'patrol');
      music.unlock();
    }
    assert.equal(c.sources.length, 1);
    assert.equal(requests - before, 1);
    assert.equal(states.at(-1), 'playing');
    music.dispose();
  });
  await test('scene intensity and independent volume change without restarting; pause and mute suspend playback', async () => {
    const states = [],
      music = new GameMusic((status) => states.push(status));
    music.unlock();
    await settle();
    const c = Context.instances.at(-1);
    const calm = c.gains[0].gain.value;
    music.setScene('boss');
    assert(c.gains[0].gain.value > calm);
    const high = c.gains[0].gain.value;
    music.setPreferences(true, 20);
    assert(c.gains[0].gain.value < high);
    music.setPaused(true);
    await settle();
    assert.equal(c.state, 'suspended');
    assert.equal(states.at(-1), 'paused');
    music.setPaused(false);
    await settle();
    assert.equal(c.state, 'running');
    music.setPreferences(false, 20);
    await settle();
    assert.equal(c.state, 'suspended');
    assert.equal(states.at(-1), 'off');
    music.setPreferences(true, 0);
    await settle();
    assert.equal(c.state, 'suspended');
    music.setPreferences(true, 60);
    await settle();
    assert.equal(c.state, 'running');
    assert(c.sources.every((s) => s.starts.length === 1));
    music.dispose();
    music.dispose();
    assert.equal(c.state, 'closed');
    assert(c.sources.every((s) => s.stops === 1 && s.disconnected));
  });
  await test('command radio ducks the current music without restarting and restores the selected volume', async () => {
    const music = new GameMusic();
    music.unlock();
    await settle();
    const c = Context.instances.at(-1);
    const level = c.gains[0].gain.value;
    music.setRadioActive(true);
    assert(Math.abs(c.gains[0].gain.value - level * 0.3) < 1e-8);
    music.setRadioActive(false);
    assert.equal(c.gains[0].gain.value, level);
    assert.equal(c.sources.length, 1);
    music.setPreferences(false, 40);
    music.setRadioActive(true);
    music.setRadioActive(false);
    assert.equal(c.gains[0].gain.value, 0);
    music.dispose();
  });
  await test('blocked browser autoplay never claims playback and a later gesture can recover', async () => {
    Context.blocked = true;
    const states = [],
      music = new GameMusic((status) => states.push(status));
    music.unlock();
    await settle();
    assert(!states.includes('playing'));
    assert.equal(states.at(-1), 'locked');
    Context.blocked = false;
    music.unlock();
    await settle();
    assert.equal(states.at(-1), 'playing');
    music.dispose();
  });
  await test('disposal aborts in-flight loading and late results cannot resurrect music', async () => {
    const waiting = [],
      signals = [];
    globalThis.fetch = (url, { signal }) =>
      new Promise((resolve) => {
        waiting.push(resolve);
        signals.push(signal);
      });
    const music = new GameMusic();
    music.unlock();
    const c = Context.instances.at(-1);
    music.dispose();
    assert(signals.every((signal) => signal.aborted));
    waiting.forEach((resolve, i) => resolve(response(i)));
    await settle();
    assert.equal(c.sources.length, 0);
    assert.equal(c.state, 'closed');
    globalThis.fetch = fetchMusic;
  });
  await test('failed music downloads remain optional and can be retried from another interaction', async () => {
    globalThis.fetch = async () => ({ ok: false });
    const states = [],
      music = new GameMusic((status) => states.push(status));
    music.unlock();
    await settle();
    assert.equal(states.at(-1), 'error');
    globalThis.fetch = fetchMusic;
    music.unlock();
    await settle();
    assert.equal(states.at(-1), 'playing');
    music.dispose();
  });
  await test('switching tracks caches decoded audio, crossfades with at most two live voices, and preserves mute', async () => {
    const before = requests,
      music = new GameMusic();
    music.unlock();
    await settle();
    const c = Context.instances.at(-1);
    for (const track of [1, 2, 0, 2, 1, 0]) {
      music.setPreferences(true, 40, track);
      await settle();
      assert.equal(music.loadedTrack, track);
      assert(c.sources.filter((s) => !s.disconnected).length <= 2);
    }
    assert.equal(requests - before, 3);
    assert.equal(music.cache.size, 3);
    music.setPaused(true);
    music.setPreferences(false, 40, 2);
    await settle();
    assert.equal(c.state, 'suspended');
    music.dispose();
    assert(c.sources.every((s) => s.disconnected));
  });
  await test('a late old request cannot replace a newer track, even when fetch ignores abort', async () => {
    const waiting = [];
    globalThis.fetch = (url, { signal }) =>
      new Promise((resolve) => waiting.push({ url, signal, resolve }));
    const music = new GameMusic();
    music.unlock();
    music.setPreferences(true, 40, 1);
    music.setPreferences(true, 40, 2);
    assert(waiting[0].signal.aborted && waiting[1].signal.aborted);
    waiting[2].resolve(response(2));
    await settle();
    waiting[0].resolve(response(0));
    waiting[1].resolve(response(1));
    await settle();
    assert.equal(music.loadedTrack, 2);
    assert.equal(Context.instances.at(-1).sources.length, 1);
    music.dispose();
    globalThis.fetch = fetchMusic;
  });
  await test('a failed switch remains visible through pause/resume and retries while paused', async () => {
    const states = [],
      music = new GameMusic((status) => states.push(status));
    music.unlock();
    await settle();
    globalThis.fetch = async () => ({ ok: false });
    music.setPreferences(true, 40, 1);
    await settle();
    assert.equal(states.at(-1), 'error');
    music.setPaused(true);
    music.setPaused(false);
    await settle();
    assert.equal(states.at(-1), 'error');
    music.setPaused(true);
    globalThis.fetch = fetchMusic;
    music.setPreferences(true, 40, 1);
    await settle();
    assert.equal(music.loadedTrack, 1);
    assert.equal(Context.instances.at(-1).state, 'suspended');
    music.dispose();
  });
  // Audio asset URL imports are supplied by Vite in production; radio playback has its own tests.
  await fs.writeFile(
    path.join(tmp, 'radio-assets.mjs'),
    'export const RADIO_ASSETS = {};',
  );
  await fs.writeFile(
    path.join(tmp, 'combat-audio-assets.mjs'),
    'export const COMBAT_AUDIO_ASSETS = {}; export const WEAPON_CLIPS = Array.from({length: 7}, () => []);',
  );
  for (const name of [
    'weapon-audio',
    'track-audio',
    'radio-audio',
    'combat-audio',
    'audio',
  ]) {
    const source = await fs.readFile(
      new URL(`../lib/${name}.ts`, import.meta.url),
      'utf8',
    );
    await fs.writeFile(
      path.join(tmp, `${name}.mjs`),
      ts
        .transpileModule(source, {
          compilerOptions: {
            module: ts.ModuleKind.ES2022,
            target: ts.ScriptTarget.ES2022,
          },
        })
        .outputText.replace(
          /'\.\/(weapon-audio|track-audio|radio-audio|radio-assets|combat-audio|combat-audio-assets)'/g,
          "'./$1.mjs'",
        ),
    );
  }
  const { weaponRecording } = await import(
    pathToFileURL(path.join(tmp, 'weapon-audio.mjs'))
  );
  const { GameAudio } = await import(
    pathToFileURL(path.join(tmp, 'audio.mjs'))
  );
  await test('seven weapon recordings have distinct bodies, audible tails and no clipping', () => {
    const signatures = new Set();
    for (let weapon = 0; weapon < 7; weapon++) {
      const samples = weaponRecording(weapon, 32000);
      let peak = 0,
        power = 0,
        high = 0;
      samples.forEach((value, index) => {
        assert(Number.isFinite(value));
        peak = Math.max(peak, Math.abs(value));
        power += value * value;
        if (index) high += Math.abs(value - samples[index - 1]);
      });
      assert(peak <= 0.9 && peak > 0.6);
      assert(Math.sqrt(power / samples.length) > 0.04);
      assert.equal(Math.abs(samples[0]), 0);
      assert.equal(Math.abs(samples.at(-1)), 0);
      signatures.add(`${samples.length}/${Math.round(high)}`);
    }
    assert.equal(signatures.size, 7);
  });
  await test('gunshots use cached recordings and cap concurrent audio voices', async () => {
    const audio = new GameAudio();
    audio.unlock();
    await settle();
    const c = Context.instances.at(-1);
    for (let weapon = 0; weapon < 7; weapon++) audio.play('fire', weapon);
    assert.equal(audio.shots.size, 7);
    assert.equal(c.sources.length, 7);
    assert.equal(new Set(c.sources.map((s) => s.buffer)).size, 7);
    for (let i = 0; i < 100; i++) audio.play('fire', 1);
    assert.equal(audio.shotVoices, 12);
    assert.equal(c.sources.length, 12);
    for (const source of c.sources) source.onended();
    assert.equal(audio.shotVoices, 0);
    const before = c.sources.length;
    audio.enabled = false;
    assert.equal(
      audio.effects.gain.value,
      0,
      'mute silences already connected gunshot voices',
    );
    audio.play('fire', 0);
    assert.equal(c.sources.length, before);
    audio.dispose();
  });
  await test('rapid pause/resume reconciles an in-flight audio suspension and disposed contexts stay closed', async () => {
    const audio = new GameAudio();
    audio.unlock();
    await settle();
    const c = Context.instances.at(-1);
    let finishSuspend;
    c.suspend = () =>
      new Promise((resolve) => {
        finishSuspend = () => {
          c.state = 'suspended';
          resolve();
        };
      });
    audio.suspend();
    audio.unlock();
    finishSuspend();
    await settle();
    assert.equal(c.state, 'running');
    audio.suspend();
    audio.dispose();
    finishSuspend();
    await settle();
    const resumes = c.resumes;
    audio.unlock();
    assert.equal(
      c.resumes,
      resumes,
      'disposal cannot recreate or resume an audio context',
    );
    assert.equal(audio.context, null);
  });
  console.log(`\n${passed} music checks passed.`);
} finally {
  globalThis.fetch = originalFetch;
  globalThis.AudioContext = originalContext;
  await fs.rm(tmp, { recursive: true, force: true });
}
