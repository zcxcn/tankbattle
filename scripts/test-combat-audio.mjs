import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import ts from 'typescript';

const tmp = await fs.mkdtemp(path.join(os.tmpdir(), 'iron-combat-'));
const modules = [
  'combat-audio-assets',
  'combat-audio',
  'audio',
  'radio-audio',
  'track-audio',
  'weapon-audio',
];
for (const name of modules) {
  const source = await fs.readFile(`lib/${name}.ts`, 'utf8');
  const js = ts
    .transpileModule(source, {
      compilerOptions: {
        module: ts.ModuleKind.ES2022,
        target: ts.ScriptTarget.ES2022,
      },
    })
    .outputText.replace(
      /import (\w+) from '(\.\.\/web\/audio\/combat\/[^']+)';/g,
      'const $1 = "$2";',
    )
    .replace(/'\.\/([^']+)'/g, "'./$1.mjs'");
  await fs.writeFile(path.join(tmp, `${name}.mjs`), js);
}
await fs.writeFile(
  path.join(tmp, 'radio-assets.mjs'),
  'export const RADIO_ASSETS = {};',
);
const { CombatAudioBank } = await import(
  pathToFileURL(path.join(tmp, 'combat-audio.mjs'))
);
const { COMBAT_AUDIO_ASSETS, WEAPON_CLIPS } = await import(
  pathToFileURL(path.join(tmp, 'combat-audio-assets.mjs'))
);
const { GameAudio } = await import(pathToFileURL(path.join(tmp, 'audio.mjs')));
const originalFetch = globalThis.fetch,
  originalContext = globalThis.AudioContext;
const settle = async () => {
  for (let i = 0; i < 12; i++) await new Promise(setImmediate);
};
const deferred = () => {
  let resolve;
  const promise = new Promise((done) => {
    resolve = done;
  });
  return { promise, resolve };
};
const response = (url) => ({
  ok: true,
  arrayBuffer: async () => new TextEncoder().encode(url).buffer,
});
const fetchAll = async (url) => response(url);
class Param {
  value = 1;
  setTargetAtTime(value) {
    this.value = value;
  }
  setValueAtTime(value) {
    this.value = value;
  }
  exponentialRampToValueAtTime(value) {
    this.value = value;
  }
}
class Node {
  gain = new Param();
  playbackRate = new Param();
  frequency = new Param();
  Q = new Param();
  starts = 0;
  stops = 0;
  disconnected = false;
  connect(target) {
    this.target = target;
  }
  disconnect() {
    this.disconnected = true;
  }
  start() {
    this.starts++;
  }
  stop(at) {
    this.stops++;
    if (at === undefined) this.onended?.();
  }
}
class Context {
  static instances = [];
  currentTime = 10;
  sampleRate = 32000;
  state = 'suspended';
  destination = new Node();
  sources = [];
  decodes = [];
  constructor() {
    Context.instances.push(this);
  }
  createBufferSource() {
    const source = new Node();
    this.sources.push(source);
    return source;
  }
  createGain() {
    return new Node();
  }
  createBiquadFilter() {
    return new Node();
  }
  createOscillator() {
    return this.createBufferSource();
  }
  createDynamicsCompressor() {
    const node = new Node();
    for (const key of ['threshold', 'knee', 'ratio', 'attack', 'release'])
      node[key] = new Param();
    return node;
  }
  createBuffer(channels, length, sampleRate) {
    return {
      fallback: true,
      duration: length / sampleRate,
      copyToChannel() {},
      getChannelData: () => new Float32Array(length),
    };
  }
  async decodeAudioData(bytes) {
    const buffer = { url: new TextDecoder().decode(bytes), duration: 3 };
    this.decodes.push(buffer);
    return buffer;
  }
  async resume() {
    this.state = 'running';
  }
  async suspend() {
    this.state = 'suspended';
  }
  async close() {
    this.state = 'closed';
  }
}
let passed = 0;
const test = async (name, run) => {
  globalThis.fetch = fetchAll;
  await run();
  passed++;
  console.log('PASS ' + name);
};
try {
  globalThis.AudioContext = Context;
  await test('library loading caps concurrency, decodes once and tolerates individual failures', async () => {
    const requests = [];
    globalThis.fetch = (url, { signal }) => {
      const wait = deferred();
      requests.push({ ...wait, url, signal });
      return wait.promise;
    };
    const context = new Context(),
      bank = new CombatAudioBank(context);
    const load = bank.preload();
    assert.equal(bank.preload(), load);
    assert.equal(requests.length, 3);
    assert.deepEqual(
      requests.map((r) => r.url),
      ['cannon01', 'engine', 'tracks'].map((id) => COMBAT_AUDIO_ASSETS[id]),
    );
    requests[0].resolve({ ok: false });
    await settle();
    assert.equal(requests.length, 4, 'failed cannon frees a loading slot');
    assert(bank.settled('cannon01'));
    for (
      let index = 1;
      index < Object.keys(COMBAT_AUDIO_ASSETS).length;
      index++
    ) {
      requests[index].resolve(response(requests[index].url));
      await settle();
    }
    await load;
    assert.equal(
      context.decodes.length,
      Object.keys(COMBAT_AUDIO_ASSETS).length - 1,
    );
    assert.equal(bank.get('cannon01'), undefined);
    assert.equal(bank.get('cannon02').url, COMBAT_AUDIO_ASSETS.cannon02);
    await bank.preload();
    assert.equal(requests.length, Object.keys(COMBAT_AUDIO_ASSETS).length);
    bank.dispose();
  });
  await test('dispose aborts active requests and ignores a decode already in progress', async () => {
    const signals = [],
      decoding = deferred(),
      context = new Context();
    globalThis.fetch = async (url, { signal }) => {
      signals.push(signal);
      return response(url);
    };
    context.decodeAudioData = () => decoding.promise;
    const bank = new CombatAudioBank(context),
      loading = bank.preload();
    await settle();
    bank.dispose();
    bank.dispose();
    assert(signals.every((s) => s.aborted));
    decoding.resolve({ duration: 3 });
    await loading;
    assert.equal(
      signals.length,
      3,
      'disposed loader never starts the remaining queue',
    );
    assert.equal(bank.get('cannon01'), undefined);
    await bank.preload();
    assert.equal(signals.length, 3);
  });
  await test('all seven weapons use library buffers, cannon reports vary, and shot voices stay bounded', async () => {
    const game = new GameAudio();
    game.unlock();
    await settle();
    const context = game.context;
    for (let index = 0; index < 3; index++) game.play('fire', 0);
    assert.equal(new Set(context.sources.map((s) => s.buffer.url)).size, 3);
    for (let weapon = 0; weapon < 7; weapon++) {
      game.play('fire', weapon);
      assert(
        WEAPON_CLIPS[weapon].some(
          (id) => COMBAT_AUDIO_ASSETS[id] === context.sources.at(-1).buffer.url,
        ),
      );
    }
    assert.equal(
      game.shots.size,
      0,
      'ready library completely replaces synthesized gunshots',
    );
    for (let i = 0; i < 100; i++) game.play('fire', 1);
    assert.equal(context.sources.length, 12);
    for (const source of context.sources) source.onended?.();
    assert.equal(game.shotVoices, 0);
    game.dispose();
  });
  await test('late recordings only affect future shots and never replay a shot after pause', async () => {
    const ready = deferred();
    globalThis.fetch = async (url) => {
      await ready.promise;
      return response(url);
    };
    const game = new GameAudio();
    game.unlock();
    game.play('fire', 0);
    const context = game.context,
      first = context.sources[0];
    assert(first.buffer.fallback);
    game.suspend();
    assert.equal(first.stops, 1);
    assert.equal(game.shotVoices, 0);
    ready.resolve();
    await settle();
    assert.equal(
      context.sources.length,
      1,
      'a loaded file cannot produce a delayed shot',
    );
    game.play('fire', 0);
    game.setMotion(1, true);
    assert.equal(
      context.sources.length,
      1,
      'pause prevents firing and new movement voices',
    );
    game.unlock();
    await settle();
    game.play('fire', 0);
    assert(!context.sources.at(-1).buffer.fallback);
    game.dispose();
  });
  await test('library explosions, armor, EMP and pickups use bounded voices and mute live audio', async () => {
    const game = new GameAudio();
    game.unlock();
    await settle();
    const context = game.context;
    for (const event of [
      'explosion',
      'hit',
      'emp',
      'pickup',
      'dash',
      'levelup',
    ])
      game.play(event, 0);
    assert(
      context.sources.every((source) => source.buffer?.url),
      'all effects use library samples',
    );
    for (let i = 0; i < 100; i++) {
      game.play('explosion');
      game.play('hit');
    }
    assert.equal(game.explosionVoices, 6);
    assert.equal(game.effectVoices, 10);
    const count = context.sources.length;
    game.enabled = false;
    assert.equal(game.effects.gain.value, 0);
    game.play('fire', 0);
    assert.equal(context.sources.length, count);
    game.suspend();
    assert.equal(game.explosionVoices, 0);
    assert.equal(game.effectVoices, 0);
    assert(context.sources.every((source) => source.disconnected));
    game.dispose();
  });
  await test('movement uses downloaded loops, keeps two voices, and stops on disposal', async () => {
    const game = new GameAudio();
    game.unlock();
    await settle();
    const context = game.context;
    for (let i = 0; i < 2000; i++)
      game.setMotion((i % 60) / 60, true, (i % 10) / 10);
    assert.equal(context.sources.length, 2);
    assert.equal(context.sources[0].buffer.url, COMBAT_AUDIO_ASSETS.engine);
    assert.equal(context.sources[1].buffer.url, COMBAT_AUDIO_ASSETS.tracks);
    assert(
      context.sources.every((source) => source.loop && source.starts === 1),
    );
    game.dispose();
    game.dispose();
    game.unlock();
    game.setMotion(1, true);
    assert.equal(context.state, 'closed');
    assert(
      context.sources.every(
        (source) => source.stops === 1 && source.disconnected,
      ),
    );
    assert.equal(context.sources.length, 2);
  });
  await test('offline layered effects respect budgets and cannot resume stale tails after pause', async () => {
    globalThis.fetch = async () => ({ ok: false });
    const game = new GameAudio();
    game.unlock();
    await settle();
    const context = game.context;
    for (const event of ['hit', 'emp', 'pickup', 'dash', 'levelup'])
      game.play(event);
    for (let i = 0; i < 40; i++) {
      game.play('explosion');
      game.play('hit');
    }
    assert.equal(game.explosionVoices, 6);
    assert.equal(game.effectVoices, 10);
    const count = context.sources.length;
    game.suspend();
    assert.equal(game.explosionVoices, 0);
    assert.equal(game.effectVoices, 0);
    assert(
      context.sources.every(
        (source) => source.disconnected && source.stops === 2,
      ),
    );
    game.unlock();
    await settle();
    assert.equal(context.sources.length, count);
    game.dispose();
  });
  await test('first gunshot is already ducked if the radio starts before the effects bus', async () => {
    const game = new GameAudio();
    game.unlock();
    game.prepareRadio();
    await settle();
    game.radio.onSpeaking(true);
    game.play('fire');
    assert.equal(game.effects.gain.value, 0.42);
    game.radio.onSpeaking(false);
    assert.equal(game.effects.gain.value, 1);
    game.dispose();
  });
  await test('a failed source start releases sampled and layered fallback voices exactly once', async () => {
    const game = new GameAudio();
    game.unlock();
    await settle();
    const context = game.context,
      create = context.createBufferSource.bind(context);
    context.createBufferSource = () => {
      const source = create();
      source.start = () => {
        throw new Error('closing context');
      };
      return source;
    };
    game.play('fire');
    assert.equal(game.shotVoices, 0);
    assert(context.sources.every((source) => source.disconnected));
    game.recordings.dispose();
    game.play('explosion');
    assert.equal(game.explosionVoices, 0);
    assert(context.sources.every((source) => source.disconnected));
    game.dispose();
  });
  console.log(`${passed} combat audio tests passed.`);
} finally {
  globalThis.fetch = originalFetch;
  globalThis.AudioContext = originalContext;
  await fs.rm(tmp, { recursive: true, force: true });
}
