import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import ts from 'typescript';

const tmp = await fs.mkdtemp(path.join(os.tmpdir(), 'iron-track-audio-'));
await fs.writeFile(
  path.join(tmp, 'track-audio.mjs'),
  ts.transpileModule(
    await fs.readFile(
      new URL('../lib/track-audio.ts', import.meta.url),
      'utf8',
    ),
    {
      compilerOptions: {
        module: ts.ModuleKind.ES2022,
        target: ts.ScriptTarget.ES2022,
      },
    },
  ).outputText,
);
const { tankMotionRecording, TankMotionAudio } = await import(
  pathToFileURL(path.join(tmp, 'track-audio.mjs'))
);
let passed = 0;
const test = (name, fn) => {
  fn();
  passed++;
  console.log('PASS ' + name);
};
class Param {
  value = 0;
  changes = [];
  setTargetAtTime(value, at, timeConstant) {
    assert.ok(Number.isFinite(value));
    this.value = value;
    this.changes.push({ value, at, timeConstant });
  }
}
class Node {
  disconnected = false;
  connections = [];
  gain = new Param();
  frequency = new Param();
  playbackRate = new Param();
  Q = new Param();
  starts = 0;
  stops = 0;
  connect(node) {
    this.connections.push(node);
  }
  disconnect() {
    this.disconnected = true;
  }
  start() {
    this.starts++;
  }
  stop() {
    this.stops++;
  }
}
class Context {
  sampleRate = 32000;
  currentTime = 0;
  state = 'running';
  sources = [];
  gains = [];
  filters = [];
  createBuffer(channels, length, sampleRate) {
    assert.equal(channels, 1);
    return {
      duration: length / sampleRate,
      copyToChannel(data) {
        assert.equal(data.length, length);
      },
    };
  }
  createBufferSource() {
    const node = new Node();
    this.sources.push(node);
    return node;
  }
  createGain() {
    const node = new Node();
    this.gains.push(node);
    return node;
  }
  createBiquadFilter() {
    const node = new Node();
    this.filters.push(node);
    return node;
  }
}
try {
  test('engine and tracks are deterministic finite recordings with safe level and natural loop seams', () => {
    for (const kind of ['engine', 'tracks']) {
      for (const sampleRate of [22050, 32000, 44100, 48000]) {
        const samples = tankMotionRecording(kind, sampleRate);
        assert.equal(samples.length, sampleRate * 2);
        assert.deepEqual(samples, tankMotionRecording(kind, sampleRate));
        let power = 0,
          peak = 0,
          derivativePower = 0;
        for (let i = 0; i < samples.length; i++) {
          assert.ok(Number.isFinite(samples[i]));
          power += samples[i] ** 2;
          peak = Math.max(peak, Math.abs(samples[i]));
          if (i) derivativePower += (samples[i] - samples[i - 1]) ** 2;
        }
        assert.ok(peak > 0.8 && peak < 0.9);
        assert.ok(Math.sqrt(power / samples.length) > 0.07);
        const seam = Math.abs(samples[0] - samples.at(-1)),
          normalStep = Math.sqrt(derivativePower / (samples.length - 1));
        assert.ok(
          seam < normalStep * 5,
          `${kind} ${sampleRate} seam ${seam} vs ${normalStep}`,
        );
      }
    }
    assert.throws(() => tankMotionRecording('engine', NaN), RangeError);
    assert.throws(() => tankMotionRecording('tracks', 1), RangeError);
  });
  test('stationary tank idles without tread noise; driving and pivoting change tread speed and load', () => {
    const context = new Context(),
      motion = new TankMotionAudio(context, new Node());
    const [engine, tracks] = context.sources,
      [engineGain, trackGain, bus] = context.gains;
    assert.equal(bus.gain.value, 0);
    motion.update(0, true);
    assert.ok(engineGain.gain.value > 0);
    assert.equal(trackGain.gain.value, 0);
    const idle = engine.playbackRate.value;
    motion.update(0.5, true);
    assert.ok(trackGain.gain.value > 0);
    assert.ok(engine.playbackRate.value > idle);
    const mediumTrackRate = tracks.playbackRate.value;
    motion.update(1, true);
    assert.ok(tracks.playbackRate.value > mediumTrackRate);
    motion.update(0, true, -0.8);
    assert.ok(trackGain.gain.value > 0, 'pivoting still moves the tracks');
    motion.update(0, true, 0);
    assert.equal(trackGain.gain.value, 0);
    motion.dispose();
  });
  test('pause fades to silence, resumes, and thousands of updates keep exactly two looping voices', () => {
    const context = new Context(),
      motion = new TankMotionAudio(context, new Node());
    for (let i = 0; i < 5000; i++) {
      context.currentTime = i / 60;
      motion.update((i % 60) / 59, true, (i % 10) / 9);
    }
    assert.equal(context.sources.length, 2);
    assert.equal(context.filters.length, 2);
    assert.equal(context.gains.length, 3);
    for (const source of context.sources) {
      assert.equal(source.starts, 1);
      assert.equal(source.loop, true);
    }
    const bus = context.gains[2];
    motion.update(0, false);
    assert.equal(bus.gain.value, 0);
    assert.ok(bus.gain.changes.at(-1).timeConstant <= 0.03);
    motion.update(0, true);
    assert.equal(bus.gain.value, 1);
    motion.dispose();
  });
  test('repeated unchanged state does not schedule redundant automation and invalid movement is clamped', () => {
    const context = new Context(),
      motion = new TankMotionAudio(context, new Node());
    motion.update(0.5, true, 0.2);
    const before = context.sources[0].playbackRate.changes.length;
    for (let i = 0; i < 1000; i++) motion.update(0.5, true, 0.2);
    assert.equal(context.sources[0].playbackRate.changes.length, before);
    motion.update(NaN, true, Infinity);
    assert.equal(context.gains[1].gain.value, 0);
    motion.update(500, true, -500);
    assert.ok(context.sources[0].playbackRate.value < 1.5);
    assert.ok(context.sources[1].playbackRate.value < 2.2);
    motion.dispose();
  });
  test('disposal synchronously disconnects all nodes and repeated disposal or updates do nothing', () => {
    const context = new Context(),
      motion = new TankMotionAudio(context, new Node());
    motion.update(1, true);
    context.state = 'suspended';
    motion.dispose();
    const counts = context.sources.map(
      (source) => source.playbackRate.changes.length,
    );
    motion.dispose();
    motion.update(1, true, 1);
    for (const node of [
      ...context.sources,
      ...context.gains,
      ...context.filters,
    ])
      assert.equal(node.disconnected, true);
    context.sources.forEach((source, index) => {
      assert.equal(source.stops, 1);
      assert.equal(source.buffer, null);
      assert.equal(source.playbackRate.changes.length, counts[index]);
    });
  });
  console.log(`${passed} tank motion audio tests passed`);
} finally {
  await fs.rm(tmp, { recursive: true, force: true });
}
