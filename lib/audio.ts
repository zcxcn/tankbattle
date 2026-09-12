import type { SoundEvent } from './engine';
import { weaponRecording } from './weapon-audio';
import { TankMotionAudio } from './track-audio';
import { RadioAudio } from './radio-audio';
import { CombatAudioBank } from './combat-audio';
import { WEAPON_CLIPS, type CombatClip } from './combat-audio-assets';
import type { RadioCue } from './tactical-radio';
export class GameAudio {
  context: AudioContext | null = null;
  private effectsEnabled = true;
  lastEnemy = 0;
  private motion: TankMotionAudio | null = null;
  private radio: RadioAudio | null = null;
  private recordings: CombatAudioBank | null = null;
  private effects: GainNode | null = null;
  private speaking = false;
  private paused = false;
  private disposed = false;
  private master: DynamicsCompressorNode | null = null;
  private noise = new Map<number, AudioBuffer>();
  private explosionVoices = 0;
  private shotVoices = 0;
  private shotSequence = 0;
  private effectSequence = 0;
  private effectVoices = 0;
  private voices = new Set<{ stop: () => void }>();
  private enemyShots = new Set<{ stop: () => void }>();
  private shots = new Map<number, AudioBuffer>();
  private cannonBuffer: AudioBuffer | null = null;
  constructor(
    private onRadio: (cue: RadioCue | null) => void = () => {},
    private onSpeaking: (active: boolean) => void = () => {},
  ) {}
  get enabled() {
    return this.effectsEnabled;
  }
  set enabled(value: boolean) {
    this.effectsEnabled = value;
    if (!value) {
      this.radio?.stop();
      this.motion?.update(0, false);
    }
    this.mix();
  }
  get radioBusy() {
    return this.radio?.busy ?? false;
  }
  private mix() {
    if (!this.effects || !this.context) return;
    this.effects.gain.setTargetAtTime(
      this.enabled ? (this.speaking ? 0.42 : 1) : 0,
      this.context.currentTime,
      0.06,
    );
  }
  private masterOutput() {
    const c = this.context!;
    if (!this.master) {
      this.master = c.createDynamicsCompressor();
      this.master.threshold.value = -10;
      this.master.knee.value = 8;
      this.master.ratio.value = 3.5;
      this.master.attack.value = 0.008;
      this.master.release.value = 0.3;
      this.master.connect(c.destination);
    }
    return this.master;
  }
  private output() {
    if (!this.effects) {
      this.effects = this.context!.createGain();
      this.effects.gain.value = this.enabled ? (this.speaking ? 0.42 : 1) : 0;
      this.effects.connect(this.masterOutput());
    }
    return this.effects;
  }
  prepareRadio() {
    if (!this.context || this.radio) return;
    this.radio = new RadioAudio(
      this.context,
      this.masterOutput(),
      this.onRadio,
      (active) => {
        this.speaking = active;
        this.mix();
        this.onSpeaking(active);
      },
    );
    void this.radio.preload();
  }
  announce(cue: RadioCue) {
    if (!this.enabled || this.paused || this.context?.state !== 'running')
      return;
    this.prepareRadio();
    this.radio?.play(cue);
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
    if (this.recordedEffect(['explosion01', 'explosion02'], 0.62, 1, true))
      return;
    if (this.explosionVoices >= 6) return;
    const c = this.context!,
      t = c.currentTime,
      output = this.output();
    const boom = c.createOscillator(),
      body = c.createGain();
    const sources: AudioScheduledSourceNode[] = [boom],
      nodes: AudioNode[] = [boom, body],
      durations = [1.4];
    boom.type = 'sine';
    boom.frequency.setValueAtTime(84, t);
    boom.frequency.exponentialRampToValueAtTime(24, t + 0.85);
    body.gain.setValueAtTime(0.001, t);
    body.gain.exponentialRampToValueAtTime(0.34, t + 0.012);
    body.gain.exponentialRampToValueAtTime(0.001, t + 1.35);
    boom.connect(body);
    body.connect(output);
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
      sources.push(source);
      nodes.push(source, filter, gain);
      durations.push(duration);
    }
    const voice = this.ownVoice('explosion', sources, nodes);
    try {
      sources.forEach((source, index) => {
        source.start(t);
        source.stop(t + durations[index]);
      });
    } catch {
      voice.stop();
    }
  }
  unlock() {
    if (this.disposed) return;
    this.paused = false;
    try {
      this.context ??= new AudioContext();
      if (!this.recordings) {
        this.recordings = new CombatAudioBank(this.context);
        void this.recordings.preload();
      }
      this.syncContext();
    } catch {}
  }
  private syncContext() {
    const context = this.context;
    if (!context || this.disposed || context.state === 'closed') return;
    const desired = this.paused ? 'suspended' : 'running';
    if (context.state === desired) return;
    const change = this.paused ? context.suspend() : context.resume();
    void change
      .then(() => {
        // A rapid resume can arrive before suspend() settles (and vice versa).
        if (
          this.context === context &&
          (this.paused ? 'suspended' : 'running') !== desired
        )
          this.syncContext();
      })
      .catch(() => {});
  }
  setMotion(throttle: number, active: boolean, turning = 0) {
    const c = this.context;
    if (!c || this.disposed) return;
    // Decode the loops before starting their fixed voices. Missing assets fall
    // back independently; movement updates never rebuild or restart a loop.
    if (
      !this.motion &&
      active &&
      this.enabled &&
      !this.paused &&
      this.recordings?.settled('engine') &&
      this.recordings.settled('tracks')
    )
      this.motion = new TankMotionAudio(c, this.output(), {
        engine: this.recordings.get('engine'),
        tracks: this.recordings.get('tracks'),
      });
    this.motion?.update(
      throttle,
      active && this.enabled && !this.paused,
      turning,
    );
  }
  private shot(weapon: number, enemy: boolean) {
    // Longer recorded tails must not let distant volleys silence the player.
    if (enemy && this.enemyShots.size >= 6) return;
    if (this.shotVoices >= 12) {
      if (enemy) return;
      this.enemyShots.values().next().value?.stop();
      if (this.shotVoices >= 12) return;
    }
    const c = this.context!;
    const index =
      Number.isInteger(weapon) && weapon >= 0 && weapon < 7 ? weapon : 0;
    const sequence = this.shotSequence++;
    const clips = WEAPON_CLIPS[index];
    // Keep the cannon's first selected report for the entire deployment. A
    // late decode must not change its timbre between shots or after a pause.
    let buffer =
      index === 0
        ? (this.cannonBuffer ??
          this.recordings?.get(clips[0]) ??
          this.shots.get(0))
        : (this.recordings?.get(clips[sequence % clips.length]) ??
          clips.map((id) => this.recordings?.get(id)).find(Boolean) ??
          this.shots.get(index));
    if (!buffer) {
      const samples = weaponRecording(index, c.sampleRate);
      buffer = c.createBuffer(1, samples.length, c.sampleRate);
      buffer.copyToChannel(samples, 0);
      this.shots.set(index, buffer);
    }
    if (index === 0) this.cannonBuffer = buffer;
    this.startSample(
      buffer,
      enemy ? 0.19 : index === 0 ? 0.7 : index === 1 ? 0.27 : 0.48,
      index === 0
        ? enemy
          ? 0.91
          : 0.94
        : (enemy ? 0.96 : 1) * [0.987, 1, 1.013][sequence % 3],
      'shot',
      enemy,
      index === 0,
    );
  }
  /** One budgeted voice may contain several layered scheduled sources. */
  private ownVoice(
    category: 'shot' | 'effect' | 'explosion',
    sources: AudioScheduledSourceNode[],
    nodes: AudioNode[],
  ) {
    const counter =
      category === 'shot'
        ? 'shotVoices'
        : category === 'explosion'
          ? 'explosionVoices'
          : 'effectVoices';
    const pending = new Set(sources);
    const finish = () => {
      if (!this.voices.delete(voice)) return;
      this.enemyShots.delete(voice);
      for (const source of sources) source.onended = null;
      pending.clear();
      for (const node of nodes) node.disconnect();
      this[counter] = Math.max(0, this[counter] - 1);
    };
    const voice = {
      stop: () => {
        for (const source of sources) {
          try {
            source.stop();
          } catch {}
        }
        finish();
      },
    };
    this.voices.add(voice);
    this[counter]++;
    for (const source of sources)
      source.onended = () => {
        pending.delete(source);
        if (!pending.size) finish();
      };
    return voice;
  }
  private startSample(
    buffer: AudioBuffer,
    volume: number,
    rate: number,
    category: 'shot' | 'effect' | 'explosion',
    enemy = false,
    cannon = false,
  ) {
    const c = this.context!;
    const source = c.createBufferSource(),
      gain = c.createGain();
    source.buffer = buffer;
    source.playbackRate.value = rate;
    gain.gain.value = volume;
    const nodes: AudioNode[] = [source, gain];
    if (cannon) {
      // The recording and offline source share the same deep, restrained report.
      const lowpass = c.createBiquadFilter(),
        body = c.createBiquadFilter();
      lowpass.type = 'lowpass';
      lowpass.frequency.value = 1600;
      lowpass.Q.value = 0.7;
      body.type = 'lowshelf';
      body.frequency.value = 180;
      body.gain.value = 3;
      source.connect(lowpass);
      lowpass.connect(body);
      body.connect(gain);
      nodes.push(lowpass, body);
    } else source.connect(gain);
    gain.connect(this.output());
    const voice = this.ownVoice(category, [source], nodes);
    if (enemy) this.enemyShots.add(voice);
    try {
      source.start();
    } catch {
      voice.stop();
    }
  }
  private recordedEffect(
    clips: readonly CombatClip[],
    volume: number,
    rate = 1,
    explosion = false,
  ) {
    const sequence = this.effectSequence++;
    const buffer =
      this.recordings?.get(clips[sequence % clips.length]) ??
      clips.map((id) => this.recordings?.get(id)).find(Boolean);
    if (!buffer) return false;
    if (explosion ? this.explosionVoices < 6 : this.effectVoices < 10)
      this.startSample(
        buffer,
        volume,
        rate * [1, 0.975, 1.018][sequence % 3],
        explosion ? 'explosion' : 'effect',
      );
    return true;
  }
  play(kind: SoundEvent, weapon = 0) {
    if (
      !this.enabled ||
      this.context?.state !== 'running' ||
      this.paused ||
      this.disposed
    )
      return;
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
        const clips: CombatClip[] =
          weapon === 1 && this.effectSequence % 3 === 0
            ? ['ricochet01', 'ricochet02']
            : ['armor01', 'armor02'];
        if (this.recordedEffect(clips, weapon === 1 ? 0.16 : 0.42)) return;
      }
      if (kind === 'emp' && this.recordedEffect(['emp'], 0.44)) return;
      if (kind === 'pickup' && this.recordedEffect(['pickup'], 0.24)) return;
      if (kind === 'levelup' && this.recordedEffect(['pickup'], 0.35, 1.25))
        return;
      if (kind === 'dash' && this.recordedEffect(['rocket'], 0.18, 1.45))
        return;
      if (this.effectVoices >= 10) return;
      const sources: AudioScheduledSourceNode[] = [],
        nodes: AudioNode[] = [],
        durations: number[] = [];
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
        sources.push(src);
        nodes.push(src, filter, gain);
        durations.push(length);
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
      sources.push(osc);
      nodes.push(osc, gain);
      durations.push(d);
      const voice = this.ownVoice('effect', sources, nodes);
      try {
        sources.forEach((source, index) => {
          source.start(t);
          source.stop(t + durations[index]);
        });
      } catch {
        voice.stop();
      }
    } catch {}
  }
  suspend() {
    this.paused = true;
    for (const voice of this.voices) voice.stop();
    this.radio?.stop();
    this.setMotion(0, false);
    this.syncContext();
  }
  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    this.recordings?.dispose();
    for (const voice of this.voices) voice.stop();
    this.radio?.dispose();
    this.motion?.dispose();
    this.effects?.disconnect();
    this.master?.disconnect();
    if (this.context) void this.context.close().catch(() => {});
    this.context = null;
    this.motion = null;
    this.radio = null;
    this.recordings = null;
    this.effects = null;
    this.master = null;
    this.noise.clear();
    this.shots.clear();
    this.cannonBuffer = null;
  }
}
