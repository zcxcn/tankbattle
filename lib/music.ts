import { assetUrl } from './asset-url';
export type MusicScene =
  | 'menu'
  | 'patrol'
  | 'battle'
  | 'boss'
  | 'danger'
  | 'victory'
  | 'defeat';
export type MusicStatus =
  | 'locked'
  | 'loading'
  | 'playing'
  | 'paused'
  | 'off'
  | 'error';
export type AudioSettings = {
  sound: boolean;
  music: boolean;
  musicVolume: number;
  musicTrack: number;
};
export const MUSIC_TRACKS = [
  { name: '钢铁风暴', style: '136 BPM · 工业重鼓', file: 'industrial-war' },
  { name: '极速追击', style: '160 BPM · 电子突袭', file: 'electronic-pursuit' },
  { name: '决战重围', style: '144 BPM · 史诗战鼓', file: 'epic-siege' },
] as const;
const ENERGY: Record<MusicScene, number> = {
  menu: 0.5,
  patrol: 0.8,
  battle: 1,
  boss: 1.08,
  danger: 1.1,
  victory: 0.75,
  defeat: 0.4,
};
type Voice = { source: AudioBufferSourceNode; gain: GainNode };

/** One selected score plus a short crossfade. Scene changes never restart the music. */
export class GameMusic {
  private context: AudioContext | null = null;
  private master: GainNode | null = null;
  private compressor: DynamicsCompressorNode | null = null;
  private voice: Voice | null = null;
  private fading: Voice | null = null;
  private cache = new Map<number, AudioBuffer>();
  private request: AbortController | null = null;
  private generation = 0;
  private loading = false;
  private failed = false;
  private loadedTrack = -1;
  private track = 0;
  private disposed = false;
  private paused = false;
  private enabled = true;
  private volume = 40;
  private radioActive = false;
  private scene: MusicScene = 'menu';
  private status: MusicStatus = 'locked';
  private resuming = false;
  constructor(private report: (status: MusicStatus) => void = () => {}) {}
  private setStatus(status: MusicStatus) {
    if (this.disposed || status === this.status) return;
    this.status = status;
    this.report(status);
  }
  private get audible() {
    return this.enabled && this.volume > 0 && !this.paused && !this.disposed;
  }
  setPreferences(enabled: boolean, volume: number, track = this.track) {
    this.enabled = enabled;
    this.volume = Number.isFinite(volume)
      ? Math.max(0, Math.min(100, volume))
      : 40;
    const next = Number.isInteger(track) && MUSIC_TRACKS[track] ? track : 0;
    if (next !== this.track || (this.failed && enabled)) {
      this.track = next;
      if (this.context) this.load();
    }
    this.mix();
    this.sync();
  }
  setScene(scene: MusicScene) {
    this.scene = scene;
    this.mix();
  }
  setRadioActive(active: boolean) {
    this.radioActive = active;
    this.mix();
  }
  setPaused(paused: boolean) {
    this.paused = paused;
    this.sync();
  }
  unlock() {
    if (!this.audible) return;
    try {
      if (!this.context) {
        this.context = new AudioContext({ latencyHint: 'playback' });
        this.master = this.context.createGain();
        this.compressor = this.context.createDynamicsCompressor();
        this.compressor.threshold.value = -10;
        this.compressor.knee.value = 10;
        this.compressor.ratio.value = 3;
        this.compressor.attack.value = 0.01;
        this.compressor.release.value = 0.3;
        this.master.connect(this.compressor);
        this.compressor.connect(this.context.destination);
        this.context.onstatechange = () => this.updateStatus();
        this.mix();
      }
      this.sync(true);
      if (!this.loading && this.loadedTrack !== this.track) this.load();
    } catch {
      this.setStatus('error');
    }
  }
  private stop(voice: Voice | null) {
    if (!voice) return;
    voice.source.onended = null;
    try {
      voice.source.stop();
    } catch {}
    voice.source.disconnect();
    voice.gain.disconnect();
  }
  private load() {
    const context = this.context;
    if (!context || this.disposed) return;
    this.request?.abort();
    const request = (this.request = new AbortController());
    const generation = ++this.generation,
      track = this.track;
    this.loading = true;
    this.failed = false;
    this.setStatus('loading');
    void (async () => {
      let buffer = this.cache.get(track);
      if (!buffer) {
        const response = await fetch(
          assetUrl(`/music/${MUSIC_TRACKS[track].file}.wav`),
          {
            signal: request.signal,
          },
        );
        if (!response.ok) throw new Error('Music unavailable');
        buffer = await context.decodeAudioData(await response.arrayBuffer());
      }
      if (
        this.disposed ||
        generation !== this.generation ||
        context !== this.context
      )
        return;
      this.cache.set(track, buffer);
      const source = context.createBufferSource(),
        gain = context.createGain();
      source.buffer = buffer;
      source.loop = true;
      source.loopEnd = buffer.duration;
      gain.gain.value = 0;
      source.connect(gain);
      gain.connect(this.master!);
      this.stop(this.fading);
      this.fading = this.voice;
      this.voice = { source, gain };
      const at = context.currentTime + 0.025;
      if (this.fading) {
        const old = this.fading;
        old.gain.gain.cancelScheduledValues(context.currentTime);
        old.gain.gain.setValueAtTime(old.gain.gain.value, context.currentTime);
        old.gain.gain.setTargetAtTime(0, at, 0.08);
        old.source.onended = () => {
          old.source.disconnect();
          old.gain.disconnect();
          if (this.fading === old) this.fading = null;
        };
        old.source.stop(at + 0.45);
      }
      source.start(at);
      gain.gain.setTargetAtTime(1, at, 0.1);
      this.loadedTrack = track;
      this.mix();
      this.sync();
    })()
      .catch(() => {
        if (!this.disposed && generation === this.generation) {
          this.failed = true;
          this.setStatus('error');
        }
      })
      .finally(() => {
        if (generation !== this.generation || this.disposed) return;
        this.loading = false;
        this.updateStatus();
      });
  }
  private mix() {
    if (!this.context || !this.master) return;
    const t = this.context.currentTime,
      param = this.master.gain;
    param.cancelScheduledValues(t);
    param.setValueAtTime(param.value, t);
    param.setTargetAtTime(
      this.enabled
        ? Math.pow(this.volume / 100, 1.25) *
            0.65 *
            ENERGY[this.scene] *
            (this.radioActive ? 0.3 : 1)
        : 0,
      t,
      0.14,
    );
  }
  private sync(forceResume = false) {
    const context = this.context;
    if (!this.audible) {
      if (context?.state === 'running')
        void context
          .suspend()
          .catch(() => {})
          .finally(() => {
            if (this.audible) this.sync();
          });
      this.updateStatus();
      return;
    }
    if (
      context &&
      context.state !== 'running' &&
      context.state !== 'closed' &&
      (forceResume || !this.resuming)
    ) {
      this.resuming = true;
      void context
        .resume()
        .then(() => {
          if (!this.audible && context.state === 'running')
            void context.suspend().catch(() => {});
        })
        .catch(() => {})
        .finally(() => {
          this.resuming = false;
          this.updateStatus();
        });
    }
    this.updateStatus();
  }
  private updateStatus() {
    if (!this.enabled || this.volume === 0) this.setStatus('off');
    else if (this.failed) this.setStatus('error');
    else if (this.paused) this.setStatus('paused');
    else if (this.loading) this.setStatus('loading');
    else if (this.voice && this.context?.state === 'running')
      this.setStatus('playing');
    else this.setStatus('locked');
  }
  dispose() {
    this.disposed = true;
    this.generation++;
    this.request?.abort();
    this.stop(this.voice);
    this.stop(this.fading);
    this.voice = this.fading = null;
    this.cache.clear();
    this.master?.disconnect();
    this.compressor?.disconnect();
    if (this.context) {
      this.context.onstatechange = null;
      void this.context.close().catch(() => {});
    }
    this.context = null;
  }
}
