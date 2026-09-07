type MotionRecording = 'engine' | 'tracks';

const TAU = Math.PI * 2;
const unit = (value: number) =>
  Number.isFinite(value) ? Math.max(0, Math.min(1, Math.abs(value))) : 0;

/** Original, deterministic diesel and steel-tread recordings, made locally. */
export function tankMotionRecording(
  kind: MotionRecording,
  sampleRate: number,
): Float32Array<ArrayBuffer> {
  if (!Number.isFinite(sampleRate) || sampleRate < 8000 || sampleRate > 192000)
    throw new RangeError('Unsupported motion audio sample rate');
  const length = Math.round(sampleRate * 2),
    crossfade = Math.round(sampleRate * 0.04),
    noise = new Float32Array(length + crossfade),
    samples = new Float32Array(length);
  let seed = kind === 'engine' ? 9137 : 45139,
    low = 0,
    slow = 0;
  const random = () => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return seed / 2147483648 - 1;
  };
  // Filter the random signal before crossing the loop seam. The first few
  // samples then follow the final samples naturally, without a periodic click.
  const lowAmount =
      1 - Math.exp((-TAU * (kind === 'engine' ? 190 : 1900)) / sampleRate),
    slowAmount =
      1 - Math.exp((-TAU * (kind === 'engine' ? 28 : 340)) / sampleRate);
  for (let i = 0; i < noise.length; i++) {
    const white = random();
    low += lowAmount * (white - low);
    slow += slowAmount * (white - slow);
    noise[i] = low - slow;
  }
  const clanks = Array.from({ length: 17 }, (_, i) => ({
    time: (i + random() * 0.09) / 8.5,
    strength: 0.65 + (random() + 1) * 0.2,
    tone: 540 + random() * 90,
  }));
  let peak = 0;
  for (let i = 0; i < length; i++) {
    const t = i / sampleRate,
      blend = Math.min(1, i / crossfade),
      grain =
        i < crossfade
          ? noise[i] * blend + noise[length + i] * (1 - blend)
          : noise[i];
    let value: number;
    if (kind === 'engine') {
      // Uneven combustion harmonics under a broad low diesel rumble.
      const combustion =
        Math.sin(TAU * 36 * t) * 0.39 +
        Math.sin(TAU * 72 * t + 0.65) * 0.19 +
        Math.sin(TAU * 108 * t + 1.4) * 0.09;
      value =
        combustion * (0.83 + Math.sin(TAU * 4 * t) * 0.11) +
        Math.sin(TAU * 23 * t) * 0.12 +
        grain * 1.45;
    } else {
      // Link impacts have short dry attacks and several damped metal modes.
      // Modular age lets a ringing link cross the seam without being cut off.
      value = grain * (0.36 + Math.sin(TAU * 8.5 * t) ** 2 * 0.18);
      for (const clank of clanks) {
        const age = (((t - clank.time) % 2) + 2) % 2;
        if (age > 0.24) continue;
        const attack = Math.min(1, age / 0.0025),
          ring =
            Math.sin(TAU * clank.tone * age) * Math.exp(-age * 62) +
            Math.sin(TAU * clank.tone * 1.83 * age) *
              Math.exp(-age * 95) *
              0.32,
          knock = Math.sin(TAU * 145 * age) * Math.exp(-age * 80) * 0.52;
        value +=
          (ring + knock + grain * Math.exp(-age * 70) * 1.8) *
          attack *
          clank.strength;
      }
    }
    samples[i] = value;
    peak = Math.max(peak, Math.abs(value));
  }
  const scale = 0.88 / Math.max(peak, 0.001);
  for (let i = 0; i < length; i++) samples[i] *= scale;
  return samples;
}

/** Two fixed looping voices; changing movement never allocates audio nodes. */
export class TankMotionAudio {
  private readonly engine: AudioBufferSourceNode;
  private readonly tracks: AudioBufferSourceNode;
  private readonly engineFilter: BiquadFilterNode;
  private readonly trackFilter: BiquadFilterNode;
  private readonly engineGain: GainNode;
  private readonly trackGain: GainNode;
  private readonly bus: GainNode;
  private readonly nodes: AudioNode[];
  private disposed = false;
  private active = false;
  private speed = -1;
  private turn = -1;

  constructor(
    private readonly context: AudioContext,
    output: AudioNode,
  ) {
    const makeLoop = (kind: MotionRecording) => {
      const recording = tankMotionRecording(kind, context.sampleRate),
        buffer = context.createBuffer(1, recording.length, context.sampleRate),
        source = context.createBufferSource();
      buffer.copyToChannel(recording, 0);
      source.buffer = buffer;
      source.loop = true;
      return source;
    };
    this.engine = makeLoop('engine');
    this.tracks = makeLoop('tracks');
    this.engineFilter = context.createBiquadFilter();
    this.engineFilter.type = 'lowpass';
    this.engineFilter.frequency.value = 240;
    this.engineFilter.Q.value = 0.6;
    this.trackFilter = context.createBiquadFilter();
    this.trackFilter.type = 'lowpass';
    this.trackFilter.frequency.value = 1400;
    this.trackFilter.Q.value = 0.55;
    this.engineGain = context.createGain();
    this.trackGain = context.createGain();
    this.bus = context.createGain();
    this.engineGain.gain.value = 0;
    this.trackGain.gain.value = 0;
    this.bus.gain.value = 0;
    this.engine.connect(this.engineFilter);
    this.engineFilter.connect(this.engineGain);
    this.engineGain.connect(this.bus);
    this.tracks.connect(this.trackFilter);
    this.trackFilter.connect(this.trackGain);
    this.trackGain.connect(this.bus);
    this.bus.connect(output);
    this.nodes = [
      this.engine,
      this.tracks,
      this.engineFilter,
      this.trackFilter,
      this.engineGain,
      this.trackGain,
      this.bus,
    ];
    this.engine.start();
    this.tracks.start();
  }

  update(throttle: number, active: boolean, turning = 0) {
    if (this.disposed || this.context.state === 'closed') return;
    const speed = unit(throttle),
      turn = unit(turning),
      now = this.context.currentTime;
    if (active !== this.active) {
      this.bus.gain.setTargetAtTime(active ? 1 : 0, now, active ? 0.09 : 0.025);
      this.active = active;
    }
    if (
      Math.abs(speed - this.speed) < 0.01 &&
      Math.abs(turn - this.turn) < 0.01
    )
      return;
    this.speed = speed;
    this.turn = turn;
    const movement = Math.max(speed, turn * 0.62),
      moving = movement > 0.015;
    this.engine.playbackRate.setTargetAtTime(
      0.82 + speed * 0.48 + turn * 0.12,
      now,
      0.2,
    );
    this.tracks.playbackRate.setTargetAtTime(0.46 + movement * 1.65, now, 0.09);
    this.engineFilter.frequency.setTargetAtTime(
      210 + movement * 130,
      now,
      0.12,
    );
    this.trackFilter.frequency.setTargetAtTime(
      1050 + movement * 1050 + turn * 380,
      now,
      0.1,
    );
    this.engineGain.gain.setTargetAtTime(
      0.06 + speed * 0.025 + turn * 0.012,
      now,
      0.16,
    );
    this.trackGain.gain.setTargetAtTime(
      moving ? 0.07 + movement * 0.095 : 0,
      now,
      moving ? 0.08 : 0.045,
    );
  }

  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    // Disconnect synchronously so an exit is silent even if the context is paused.
    this.bus.disconnect();
    for (const source of [this.engine, this.tracks]) {
      try {
        source.stop();
      } catch {}
      source.buffer = null;
    }
    for (const node of this.nodes) node.disconnect();
  }
}
