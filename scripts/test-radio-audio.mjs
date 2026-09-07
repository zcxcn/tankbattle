import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import ts from 'typescript';

const tmp = await fs.mkdtemp(path.join(os.tmpdir(), 'iron-radio-audio-'));
const source = await fs.readFile(
  new URL('../lib/radio-audio.ts', import.meta.url),
  'utf8',
);
await fs.writeFile(
  path.join(tmp, 'radio-audio.mjs'),
  ts
    .transpileModule(source, {
      compilerOptions: {
        module: ts.ModuleKind.ES2022,
        target: ts.ScriptTarget.ES2022,
      },
    })
    .outputText.replace("'./radio-assets'", "'./radio-assets.mjs'"),
);
await fs.writeFile(
  path.join(tmp, 'radio-assets.mjs'),
  `export const RADIO_ASSETS = ${JSON.stringify(
    Object.fromEntries(
      ['a', 'b', 'c', 'd', 'e', 'f', 'g'].map((id) => [id, `/radio/${id}.wav`]),
    ),
  )};`,
);
const { RadioAudio } = await import(
  pathToFileURL(path.join(tmp, 'radio-audio.mjs'))
);
const originalFetch = globalThis.fetch;
const tick = () => new Promise((resolve) => setImmediate(resolve));
const settle = async () => {
  for (let i = 0; i < 8; i++) await tick();
};
const deferred = () => {
  let resolve;
  let reject;
  const promise = new Promise((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
};
class AudioNode {
  disconnected = false;
  connect(target) {
    this.target = target;
  }
  disconnect() {
    this.disconnected = true;
  }
}
class Source extends AudioNode {
  stops = 0;
  starts = 0;
  onended = null;
  start() {
    this.starts++;
  }
  stop() {
    this.stops++;
    this.onended?.();
  }
  end() {
    this.onended?.();
  }
}
class Context {
  state = 'running';
  currentTime = 12;
  destination = new AudioNode();
  sources = [];
  gains = [];
  decodes = 0;
  createBufferSource() {
    if (this.state === 'closed') throw new Error('Audio context closed');
    const source = new Source();
    this.sources.push(source);
    return source;
  }
  createGain() {
    const gain = new AudioNode();
    gain.gain = { value: 1 };
    this.gains.push(gain);
    return gain;
  }
  async decodeAudioData() {
    this.decodes++;
    return { duration: 2 };
  }
}
const cue = (id = 'a', priority = 1) => ({
  id,
  priority,
  text: `Transmission ${id}.`,
});
const response = () => ({
  ok: true,
  arrayBuffer: async () => new ArrayBuffer(4),
});
const setup = () => {
  const context = new Context();
  const captions = [];
  const speaking = [];
  const radio = new RadioAudio(
    context,
    context.destination,
    (value) => captions.push(value),
    (value) => speaking.push(value),
  );
  return { context, radio, captions, speaking };
};
let passed = 0;
const test = async (name, run) => {
  globalThis.fetch = async () => response();
  await run();
  passed++;
  console.log(`PASS ${name}`);
};

try {
  await test('recordings are cached and node lifetimes end with each transmission', async () => {
    let requests = 0;
    globalThis.fetch = async () => {
      requests++;
      return response();
    };
    const { context, radio, captions, speaking } = setup();
    radio.play(cue());
    assert.equal(radio.busy, true);
    assert.deepEqual(captions, []);
    await settle();
    const first = context.sources[0];
    assert.equal(first.starts, 1);
    assert.equal(context.gains[0].gain.value, 0.85);
    assert.deepEqual(captions, [cue()]);
    assert.deepEqual(speaking, [true]);
    first.end();
    assert.equal(radio.busy, false);
    assert.equal(first.disconnected, true);
    assert.equal(context.gains[0].disconnected, true);
    assert.equal(captions.at(-1), null);
    assert.equal(speaking.at(-1), false);
    radio.play(cue());
    await settle();
    assert.equal(requests, 1);
    assert.equal(context.decodes, 1);
    assert.equal(context.sources.length, 2);
    radio.dispose();
  });

  await test('priority prevents chatter from interrupting a warning, and urgent warnings preempt', async () => {
    const { context, radio } = setup();
    radio.play(cue('a', 3));
    await settle();
    const first = context.sources[0];
    const oldEnded = first.onended;
    radio.play(cue('b', 1));
    radio.play(cue('c', 3));
    await settle();
    assert.equal(context.sources.length, 1);
    assert.equal(first.stops, 0);
    radio.play(cue('d', 5));
    await settle();
    assert.equal(first.stops, 1);
    assert.equal(first.disconnected, true);
    assert.equal(context.sources.length, 2);
    oldEnded();
    assert.equal(
      radio.busy,
      true,
      'a stale source ending must not clear its replacement',
    );
    radio.dispose();
    assert.equal(context.sources[1].stops, 1);
  });

  await test('higher priority also replaces an in-flight transmission before decoding', async () => {
    const a = deferred();
    globalThis.fetch = (url) =>
      url.includes('/a.') ? a.promise : Promise.resolve(response());
    const { context, radio, captions } = setup();
    radio.play(cue('a', 1));
    radio.play(cue('b', 2));
    await settle();
    assert.equal(captions[0].id, 'b');
    a.resolve(response());
    await settle();
    assert.equal(context.sources.length, 1);
    assert.equal(captions.length, 1);
    radio.dispose();
  });

  await test('stopping during decode cannot resume a stale line after unpausing', async () => {
    const decoded = deferred();
    const { context, radio, captions } = setup();
    context.decodeAudioData = () => decoded.promise;
    radio.play(cue());
    await settle();
    radio.stop();
    assert.equal(radio.busy, false);
    decoded.resolve({ duration: 2 });
    await settle();
    assert.equal(context.sources.length, 0);
    assert.deepEqual(captions, []);
    radio.play(cue());
    await settle();
    assert.equal(
      context.sources.length,
      1,
      'a later explicit line can use the loaded buffer',
    );
    radio.dispose();
  });

  await test('suspended contexts never start radio audio, including after an asynchronous load', async () => {
    let requests = 0;
    const pending = deferred();
    globalThis.fetch = () => {
      requests++;
      return pending.promise;
    };
    const { context, radio } = setup();
    context.state = 'suspended';
    radio.play(cue());
    assert.equal(requests, 0);
    assert.equal(radio.busy, false);
    context.state = 'running';
    radio.play(cue());
    context.state = 'suspended';
    pending.resolve(response());
    await settle();
    assert.equal(context.sources.length, 0);
    assert.equal(radio.busy, false);
    radio.dispose();
  });

  await test('late warnings expire after two seconds instead of playing obsolete information', async () => {
    const pending = deferred();
    globalThis.fetch = () => pending.promise;
    const { context, radio } = setup();
    radio.play(cue());
    await new Promise((resolve) => setTimeout(resolve, 2_050));
    assert.equal(radio.busy, false);
    pending.resolve(response());
    await settle();
    assert.equal(context.sources.length, 0);
    radio.dispose();
  });

  await test('short-lived barrage warnings expire before their gameplay deadline', async () => {
    const pending = deferred();
    globalThis.fetch = () => pending.promise;
    const { context, radio } = setup();
    radio.play({ ...cue('a', 95), maxDelayMs: 40 });
    await new Promise((resolve) => setTimeout(resolve, 70));
    assert.equal(radio.busy, false);
    pending.resolve(response());
    await settle();
    assert.equal(context.sources.length, 0);
    radio.dispose();
  });

  await test('a barrage canceled during loading cannot announce an obsolete attack', async () => {
    const pending = deferred();
    globalThis.fetch = () => pending.promise;
    const { context, radio, captions } = setup();
    let windingUp = true;
    const warning = {
      ...cue('a', 95),
      maxDelayMs: 500,
      valid: () => windingUp,
    };
    radio.play(warning);
    windingUp = false;
    pending.resolve(response());
    await settle();
    assert.equal(context.sources.length, 0);
    assert.equal(radio.busy, false);
    assert.deepEqual(captions, []);
    windingUp = true;
    radio.play(warning);
    await settle();
    assert.equal(
      context.sources.length,
      1,
      'a fresh attack can use the cached recording',
    );
    radio.dispose();
  });

  await test('invalid or already expired warnings cannot interrupt an active transmission', async () => {
    let requests = 0;
    globalThis.fetch = async () => {
      requests++;
      return response();
    };
    const { context, radio } = setup();
    radio.play(cue('a', 30));
    await settle();
    radio.play({ ...cue('b', 95), valid: () => false });
    radio.play({ ...cue('c', 95), maxDelayMs: 0 });
    await settle();
    assert.equal(requests, 1);
    assert.equal(context.sources[0].stops, 0);
    assert.equal(radio.busy, true);
    radio.dispose();
  });

  await test('preload bounds fetch and decode concurrency and prioritizes a live request', async () => {
    const pending = [];
    const requested = [];
    let active = 0;
    let peak = 0;
    globalThis.fetch = (url) => {
      const gate = deferred();
      active++;
      peak = Math.max(active, peak);
      pending.push(() => {
        active--;
        gate.resolve(response());
      });
      requested.push(url);
      return gate.promise;
    };
    const { context, radio, captions } = setup();
    const preloaded = radio.preload();
    assert.equal(requested.length, 3);
    radio.play(cue('g', 5));
    pending.shift()();
    await settle();
    assert.equal(requested[3], '/radio/g.wav');
    while (pending.length) {
      pending.shift()();
      await settle();
    }
    await preloaded;
    assert.equal(peak, 3);
    assert.equal(context.decodes, 7);
    assert.equal(requested.length, 7);
    assert.equal(captions[0].id, 'g');
    await radio.preload();
    assert.equal(requested.length, 7);
    radio.dispose();
  });

  await test('decode occupies a loading slot so compressed audio cannot flood the decoder', async () => {
    const decodes = [];
    const { context, radio } = setup();
    context.decodeAudioData = () => {
      const gate = deferred();
      decodes.push(gate);
      return gate.promise;
    };
    const preloaded = radio.preload();
    await settle();
    assert.equal(decodes.length, 3);
    let completed = 0;
    while (completed < 7) {
      decodes[completed++].resolve({ duration: 2 });
      await settle();
      assert.ok(decodes.length - completed <= 3);
    }
    await preloaded;
    radio.dispose();
  });

  await test('failed recordings stay optional and may be retried on a later event', async () => {
    let attempts = 0;
    globalThis.fetch = async () => {
      attempts++;
      if (attempts === 1) throw new Error('Offline');
      if (attempts === 2) return { ok: false };
      return response();
    };
    const { context, radio } = setup();
    for (let i = 0; i < 3; i++) {
      radio.play(cue());
      await settle();
    }
    assert.equal(context.sources.length, 1);
    assert.equal(attempts, 3);
    radio.dispose();
  });

  await test('disposal aborts network work, clears queued preload and prevents future playback', async () => {
    let requests = 0;
    let aborted = 0;
    globalThis.fetch = (_url, options) =>
      new Promise((_resolve, reject) => {
        requests++;
        options.signal.addEventListener('abort', () => {
          aborted++;
          reject(new Error('Aborted'));
        });
      });
    const { context, radio } = setup();
    const preloaded = radio.preload();
    radio.play(cue('g', 5));
    radio.dispose();
    radio.dispose();
    await preloaded;
    await radio.preload();
    radio.play(cue());
    await settle();
    assert.equal(requests, 3);
    assert.equal(aborted, 3);
    assert.equal(radio.busy, false);
    assert.equal(context.sources.length, 0);
  });

  await test('a context closing during decoding does not play or reject the game loop', async () => {
    const decoded = deferred();
    const { context, radio } = setup();
    context.decodeAudioData = () => decoded.promise;
    radio.play(cue());
    await settle();
    context.state = 'closed';
    decoded.reject(new Error('Context closed'));
    await settle();
    assert.equal(radio.busy, false);
    assert.equal(context.sources.length, 0);
    radio.dispose();
  });
  console.log(`${passed} radio audio tests passed.`);
} finally {
  globalThis.fetch = originalFetch;
  await fs.rm(tmp, { recursive: true, force: true });
}
