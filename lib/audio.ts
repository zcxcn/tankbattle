import type { SoundEvent } from './engine';
import { weaponRecording } from './weapon-audio';
export class GameAudio {
  context: AudioContext | null = null;
  enabled = true;
  lastEnemy = 0;
  private motor: OscillatorNode | null = null;
  private motorGain: GainNode | null = null;
  private master: DynamicsCompressorNode | null = null;
  private noise = new Map<number, AudioBuffer>();
  private explosionVoices = 0;
  private shotVoices = 0;
  private shotSequence = 0;
  private shots = new Map<number, AudioBuffer>();
  private output() {
    const c = this.context!;
    if (!this.master) {
      this.master = c.createDynamicsCompressor();
      this.master.threshold.value = -14;
      this.master.knee.value = 8;
      this.master.ratio.value = 5;
      this.master.attack.value = 0.003;
      this.master.release.value = 0.24;
      this.master.connect(c.destination);
    }
    return this.master;
  }
  private noiseBuffer(seconds: number) {
    let buffer = this.noise.get(seconds);
    if (!buffer) {
      const c = this.context!;
      buffer = c.createBuffer(
        1,
        Math.ceil(c.sampleRate * seconds),
        c.sampleRate,
      );
      const data = buffer.getChannelData(0);
      for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
      this.noise.set(seconds, buffer);
    }
    return buffer;
  }
  private explosion() {
    if (this.explosionVoices >= 6) return;
    const c = this.context!,
      t = c.currentTime,
      output = this.output();
    this.explosionVoices++;
    const boom = c.createOscillator(),
      body = c.createGain();
    boom.type = 'sine';
    boom.frequency.setValueAtTime(84, t);
    boom.frequency.exponentialRampToValueAtTime(24, t + 0.85);
    body.gain.setValueAtTime(0.001, t);
    body.gain.exponentialRampToValueAtTime(0.34, t + 0.012);
    body.gain.exponentialRampToValueAtTime(0.001, t + 1.35);
    boom.connect(body);
    body.connect(output);
    boom.onended = () => {
      boom.disconnect();
      body.disconnect();
      this.explosionVoices--;
    };
    boom.start(t);
    boom.stop(t + 1.4);
    for (const [frequency, duration, volume] of [
      [2600, 0.14, 0.3],
      [480, 1.35, 0.28],
      [140, 1.5, 0.23],
    ]) {
      const source = c.createBufferSource(),
        filter = c.createBiquadFilter(),
        gain = c.createGain();
      source.buffer = this.noiseBuffer(1.6);
      filter.type = 'bandpass';
      filter.Q.value = 0.65;
      filter.frequency.setValueAtTime(frequency, t);
      filter.frequency.exponentialRampToValueAtTime(
        frequency * 0.3,
        t + duration,
      );
      gain.gain.setValueAtTime(volume, t);
      gain.gain.exponentialRampToValueAtTime(0.001, t + duration);
      source.connect(filter);
      filter.connect(gain);
      gain.connect(output);
      source.onended = () => {
        source.disconnect();
        filter.disconnect();
        gain.disconnect();
      };
      source.start(t);
      source.stop(t + duration);
    }
  }
  unlock() {
    try {
      this.context ??= new AudioContext();
      if (this.context.state === 'suspended')
        void this.context.resume().catch(() => {});
    } catch {}
  }
  setMotion(throttle: number, active: boolean) {
    const c = this.context;
    if (!c) return;
    if (!this.motor) {
      this.motor = c.createOscillator();
      this.motor.type = 'sawtooth';
      this.motorGain = c.createGain();
      const filter = c.createBiquadFilter();
      filter.type = 'lowpass';
      filter.frequency.value = 160;
      this.motor.connect(filter);
      filter.connect(this.motorGain);
      this.motorGain.connect(this.output());
      this.motorGain.gain.value = 0;
      this.motor.start();
    }
    this.motor.frequency.setTargetAtTime(
      38 + Math.min(1, throttle) * 32,
      c.currentTime,
      0.2,
    );
    this.motorGain!.gain.setTargetAtTime(
      active && this.enabled ? 0.012 + Math.min(1, throttle) * 0.013 : 0,
      c.currentTime,
      0.12,
    );
  }
  private shot(weapon: number, enemy: boolean) {
    if (this.shotVoices >= 12) return;
    const c = this.context!;
    const index =
      Number.isInteger(weapon) && weapon >= 0 && weapon < 7 ? weapon : 0;
    let buffer = this.shots.get(index);
    if (!buffer) {
      const samples = weaponRecording(index, c.sampleRate);
      buffer = c.createBuffer(1, samples.length, c.sampleRate);
      buffer.copyToChannel(samples, 0);
      this.shots.set(index, buffer);
    }
    const source = c.createBufferSource(),
      gain = c.createGain();
    source.buffer = buffer;
    source.playbackRate.value =
      (enemy ? 0.94 : 1) * [0.987, 1, 1.013][this.shotSequence++ % 3];
    gain.gain.value = enemy ? 0.17 : index === 1 ? 0.3 : 0.48;
    source.connect(gain);
    gain.connect(this.output());
    this.shotVoices++;
    source.onended = () => {
      source.disconnect();
      gain.disconnect();
      this.shotVoices = Math.max(0, this.shotVoices - 1);
    };
    source.start();
  }
  play(kind: SoundEvent, weapon = 0) {
    if (!this.enabled || !this.context) return;
    const c = this.context,
      t = c.currentTime;
    if (kind === 'enemyfire' && t - this.lastEnemy < 0.08) return;
    if (kind === 'enemyfire') this.lastEnemy = t;
    try {
      if (kind === 'fire' || kind === 'enemyfire') {
        this.shot(weapon, kind === 'enemyfire');
        return;
      }
      if (kind === 'explosion') {
        this.explosion();
        return;
      }
      if (kind === 'hit') {
        const length = 0.18,
          buffer = this.noiseBuffer(length);
        const src = c.createBufferSource(),
          filter = c.createBiquadFilter(),
          gain = c.createGain();
        src.buffer = buffer;
        filter.type = 'lowpass';
        filter.frequency.setValueAtTime(
          weapon === 3 || weapon === 5 ? 3600 : 1900,
          t,
        );
        filter.frequency.exponentialRampToValueAtTime(70, t + length);
        gain.gain.setValueAtTime(weapon === 1 ? 0.1 : 0.22, t);
        gain.gain.exponentialRampToValueAtTime(0.001, t + length);
        src.connect(filter);
        filter.connect(gain);
        gain.connect(this.output());
        src.onended = () => {
          src.disconnect();
          filter.disconnect();
          gain.disconnect();
        };
        src.start();
        src.stop(t + length);
      }
      const osc = c.createOscillator(),
        gain = c.createGain();
      osc.type = kind === 'pickup' || kind === 'levelup' ? 'sine' : 'triangle';
      const notes: { [key: string]: [number, number, number] } = {
        fire: [145, 40, 0.15],
        enemyfire: [100, 35, 0.1],
        explosion: [75, 18, 0.6],
        hit: [90, 35, 0.2],
        emp: [800, 45, 0.7],
        pickup: [420, 840, 0.24],
        dash: [190, 600, 0.2],
        levelup: [520, 1560, 0.65],
      };
      const [a, z, d] = notes[kind];
      osc.frequency.setValueAtTime(a, t);
      osc.frequency.exponentialRampToValueAtTime(z, t + d);
      gain.gain.setValueAtTime(0.1, t);
      gain.gain.exponentialRampToValueAtTime(0.001, t + d);
      osc.connect(gain);
      gain.connect(this.output());
      osc.onended = () => {
        osc.disconnect();
        gain.disconnect();
      };
      osc.start();
      osc.stop(t + d);
    } catch {}
  }
  suspend() {
    this.setMotion(0, false);
    if (this.context?.state === 'running')
      void this.context.suspend().catch(() => {});
  }
  dispose() {
    if (this.context) void this.context.close().catch(() => {});
    this.context = null;
    this.motor = null;
    this.motorGain = null;
    this.master = null;
    this.noise.clear();
    this.shots.clear();
  }
}
