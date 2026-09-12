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
  filters = [];
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
    const filter = new Node();
    this.filters.push(filter);
    return filter;
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
  await test('all seven weapons use library buffers, cannon reports stay consistent, and shot voices stay bounded', async () => {
    const game = new GameAudio();
    game.unlock();
    await settle();
    const context = game.context;
    for (let index = 0; index < 3; index++) game.play('fire', 0);
    assert.equal(new Set(context.sources.map((s) => s.buffer.url)).size, 1);
    assert(
      context.sources.every(
        (source) => source.buffer.url === COMBAT_AUDIO_ASSETS.cannon01,
      ),
    );
    assert(
      context.sources.every((source) => source.playbackRate.value === 0.94),
    );
    assert.equal(
      context.filters.length,
      6,
      'each cannon report gets the same bounded EQ chain',
    );
    for (let index = 0; index < context.filters.length; index += 2) {
      assert.equal(context.filters[index].type, 'lowpass');
      assert.equal(context.filters[index].frequency.value, 1600);
      assert.equal(context.filters[index + 1].type, 'lowshelf');
      assert.equal(context.filters[index + 1].frequency.value, 180);
      assert.equal(context.filters[index + 1].gain.value, 3);
    }
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
  await test('player fire preempts the oldest enemy tail at the shared voice limit and releases every counter', async () => {
    const game = new GameAudio();
    game.unlock();
    await settle();
    const context = game.context;
    const enemyShot = () => {
      context.currentTime += 0.1; // Each request is outside enemy-fire throttling.
      game.play('enemyfire', 0);
    };
    for (let index = 0; index < 6; index++) enemyShot();
    const enemies = context.sources.slice();
    assert.equal(enemies.length, 6);
    assert.equal(game.enemyShots.size, 6);
    enemyShot();
    assert.equal(
      context.sources.length,
      6,
      'enemy tails must keep room for player fire',
    );
    for (let index = 0; index < 6; index++) game.play('fire', 0);
    assert.equal(context.sources.length, 12);
    assert.equal(game.shotVoices, 12);
    const oldestEnded = enemies[0].onended;
    game.play('fire', 0);
    assert.equal(
      context.sources.length,
      13,
      'a player shot must still start when 12 tails are active',
    );
    assert.equal(context.sources.at(-1).starts, 1);
    assert.equal(enemies[0].stops, 1, 'replace the oldest enemy tail first');
    assert(enemies[0].disconnected && enemies[0].target.disconnected);
    assert(enemies.slice(1).every((source) => source.stops === 0));
    assert(
      context.sources.slice(6).every((source) => source.stops === 0),
      'player tails must not be evicted while enemy tails remain',
    );
    assert.equal(game.shotVoices, 12);
    assert.equal(game.voices.size, 12);
    assert.equal(game.enemyShots.size, 5);
    oldestEnded?.(); // A queued ended event after preemption cannot decrement twice.
    assert.equal(game.shotVoices, 12);
    assert.equal(game.enemyShots.size, 5);
    for (const source of context.sources) source.onended?.();
    assert.equal(game.shotVoices, 0);
    assert.equal(game.enemyShots.size, 0);
    assert.equal(game.voices.size, 0);
    assert(
      context.sources.every(
        (source) => source.disconnected && source.target.disconnected,
      ),
    );

    const beforeSecondVolley = context.sources.length;
    for (let index = 0; index < 6; index++) enemyShot();
    for (let index = 0; index < 6; index++) game.play('fire', 0);
    assert.equal(game.shotVoices, 12);
    assert.equal(game.enemyShots.size, 6);
    game.suspend();
    assert.equal(game.shotVoices, 0);
    assert.equal(game.enemyShots.size, 0);
    assert.equal(game.voices.size, 0);
    assert(
      context.sources
        .slice(beforeSecondVolley)
        .every(
          (source) =>
            source.stops === 1 &&
            source.disconnected &&
            source.target.disconnected,
        ),
    );
    game.dispose();
    assert.equal(game.shotVoices, 0);
    assert.equal(game.enemyShots.size, 0);
  });
  await test('late recordings cannot replace a cannon report or replay a shot after pause', async () => {
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
    assert.equal(
      context.sources.at(-1).buffer,
      first.buffer,
      'cannon retains its selected fallback even after a pause and late decode',
    );
    assert.equal(
      context.sources.at(-1).playbackRate.value,
      first.playbackRate.value,
    );
    game.play('fire', 1);
    assert.equal(
      context.sources.at(-1).buffer.url,
      COMBAT_AUDIO_ASSETS.mg,
      'other weapons still use their downloaded recordings',
    );
    game.dispose();
    assert.equal(game.cannonBuffer, null);
    assert(context.filters.every((filter) => filter.disconnected));
  });
  await test('partial loading and enemy volleys cannot select a bright alternate cannon take', async () => {
    const canonical = deferred();
    globalThis.fetch = async (url) => {
      if (url === COMBAT_AUDIO_ASSETS.cannon01) await canonical.promise;
      return response(url);
    };
    const game = new GameAudio();
    game.unlock();
    await settle();
    const context = game.context;
    assert(
      game.recordings.get('cannon03'),
      'the brighter alternate finished decoding first',
    );
    game.play('fire', 0);
    const first = context.sources.at(-1);
    assert(
      first.buffer.fallback,
      'never substitute another weapon/source for the canonical report',
    );
    canonical.resolve();
    await settle();
    for (let index = 0; index < 4; index++) {
      context.currentTime += 0.1;
      game.play('enemyfire', 1);
      game.play('fire', 0);
      const source = context.sources.at(-1);
      assert.equal(source.buffer, first.buffer);
      assert.equal(
        source.playbackRate.value,
        first.playbackRate.value,
        'enemy sequence cannot alter player cannon pitch',
      );
      source.onended?.();
    }
    game.dispose();
    assert(context.filters.every((filter) => filter.disconnected));
    const next = new GameAudio();
    next.unlock();
    await settle();
    next.play('fire', 0);
    assert.equal(
      next.context.sources.at(-1).buffer.url,
      COMBAT_AUDIO_ASSETS.cannon01,
      'a new deployment may select the now-ready field recording',
    );
    next.dispose();
  });
  await test('actual WAV PCM and synthesized PCM keep a fixed cannon timbre through mixed fire and late decode', async () => {
    class PcmContext extends Context {
      createBuffer(channels, length, sampleRate) {
        const data = Array.from(
          { length: channels },
          () => new Float32Array(length),
        );
        return {
          fallback: true,
          length,
          sampleRate,
          duration: length / sampleRate,
          getChannelData: (channel) => data[channel],
          copyToChannel: (samples, channel) => data[channel].set(samples),
        };
      }
      async decodeAudioData(bytes) {
        // The shipped assets are PCM WAV: decode their real samples without
        // requiring a speaker or substituting URL-only buffers in this test.
        const view = Buffer.from(bytes);
        assert.equal(view.toString('ascii', 0, 4), 'RIFF');
        assert.equal(view.toString('ascii', 8, 12), 'WAVE');
        let format = 0,
          samples = 0,
          size = 0;
        for (let at = 12; at + 8 <= view.length;) {
          const name = view.toString('ascii', at, at + 4),
            length = view.readUInt32LE(at + 4);
          if (name === 'fmt ') format = at + 8;
          if (name === 'data') {
            samples = at + 8;
            size = length;
          }
          at += 8 + length + (length % 2);
        }
        assert(format && samples);
        assert.equal(view.readUInt16LE(format), 1);
        assert.equal(view.readUInt16LE(format + 2), 1);
        assert.equal(view.readUInt16LE(format + 14), 16);
        const buffer = this.createBuffer(
          1,
          size / 2,
          view.readUInt32LE(format + 4),
        );
        const data = buffer.getChannelData(0);
        for (let index = 0; index < data.length; index++)
          data[index] = view.readInt16LE(samples + index * 2) / 32768;
        buffer.fallback = false;
        this.decodes.push(buffer);
        return buffer;
      }
    }
    globalThis.AudioContext = PcmContext;
    for (const fireBeforeDecode of [false, true]) {
      const ready = deferred();
      globalThis.fetch = async (url) => {
        if (fireBeforeDecode && url === COMBAT_AUDIO_ASSETS.cannon01)
          await ready.promise;
        const bytes = await fs.readFile(
          path.join('web/audio/combat', path.basename(url)),
        );
        return {
          ok: true,
          arrayBuffer: async () =>
            bytes.buffer.slice(
              bytes.byteOffset,
              bytes.byteOffset + bytes.byteLength,
            ),
        };
      };
      const game = new GameAudio();
      game.unlock();
      if (!fireBeforeDecode) await game.recordings.preload();
      game.play('fire', 0);
      const context = game.context,
        first = context.sources.at(-1);
      assert.equal(first.buffer.fallback, fireBeforeDecode);
      const waveform = first.buffer.getChannelData(0).slice();
      assert(
        waveform.some((sample) => Math.abs(sample) > 0.25),
        'real audible PCM',
      );
      assert(
        first.buffer.duration >= 2.4,
        'cannon has a substantial recorded or synthesized decay',
      );
      ready.resolve();
      await game.recordings.preload();
      assert.equal(game.recordings.get('cannon01').fallback, false);
      if (!fireBeforeDecode)
        assert.equal(first.buffer, game.recordings.get('cannon01'));
      for (const weapon of [1, 3, 6, 0]) {
        context.currentTime += 0.1;
        game.play('enemyfire', weapon);
        game.play('fire', 0);
        const next = context.sources.at(-1);
        assert.equal(next.buffer, first.buffer);
        assert.equal(next.playbackRate.value, first.playbackRate.value);
        assert.deepEqual(next.buffer.getChannelData(0), waveform);
        assert.equal(next.target.type, 'lowpass');
        assert.equal(next.target.frequency.value, 1600);
        assert.equal(next.target.target.type, 'lowshelf');
        assert.equal(next.target.target.gain.value, 3);
        next.onended?.();
      }
      game.dispose();
      assert(context.filters.every((filter) => filter.disconnected));
    }
    globalThis.AudioContext = Context;
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
