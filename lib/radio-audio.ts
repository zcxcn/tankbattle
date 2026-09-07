import { RADIO_ASSETS } from './radio-assets';
import type { RadioCue } from './tactical-radio';

type RadioId = RadioCue['id'];
type LoadRequest = {
  id: RadioId;
  resolve: (buffer: AudioBuffer | null) => void;
};
type PendingCue = {
  cue: RadioCue;
  generation: number;
  expiresAt: number;
  timeout: ReturnType<typeof setTimeout>;
};
type Voice = {
  source: AudioBufferSourceNode;
  gain: GainNode;
  priority: number;
};

const LOAD_CONCURRENCY = 3;
const CUE_LIFETIME_MS = 2_000;

/** A single command radio channel. Its recordings share the game's audio graph. */
export class RadioAudio {
  private buffers = new Map<RadioId, AudioBuffer>();
  private loads = new Map<RadioId, Promise<AudioBuffer | null>>();
  private queue: LoadRequest[] = [];
  private loading = 0;
  private abort = new AbortController();
  private pending: PendingCue | null = null;
  private voice: Voice | null = null;
  private generation = 0;
  private disposed = false;

  constructor(
    private context: AudioContext,
    private output: AudioNode,
    private onCue: (cue: RadioCue | null) => void = () => {},
    private onSpeaking: (speaking: boolean) => void = () => {},
  ) {}

  get busy() {
    return !!this.pending || !!this.voice;
  }

  async preload(): Promise<void> {
    await Promise.all(
      (Object.keys(RADIO_ASSETS) as RadioId[]).map((id) => this.load(id)),
    );
  }

  play(cue: RadioCue): void {
    if (
      this.disposed ||
      this.context.state !== 'running' ||
      (cue.valid && !cue.valid())
    )
      return;
    const lifetime = Number.isFinite(cue.maxDelayMs)
      ? Math.min(CUE_LIFETIME_MS, Math.max(0, cue.maxDelayMs!))
      : CUE_LIFETIME_MS;
    if (lifetime <= 0) return;
    const priority = this.pending?.cue.priority ?? this.voice?.priority;
    if (priority !== undefined && cue.priority <= priority) return;
    this.stop();
    const generation = this.generation;
    this.pending = {
      cue,
      generation,
      expiresAt: performance.now() + lifetime,
      timeout: setTimeout(() => this.clearPending(generation), lifetime),
    };
    void this.load(cue.id, true).then((buffer) => {
      const pending = this.pending;
      if (!pending || pending.generation !== generation) return;
      const expired = performance.now() >= pending.expiresAt;
      this.clearPending(generation);
      if (
        !buffer ||
        expired ||
        this.disposed ||
        this.context.state !== 'running' ||
        (cue.valid && !cue.valid())
      )
        return;

      let source: AudioBufferSourceNode | undefined;
      let gain: GainNode | undefined;
      try {
        source = this.context.createBufferSource();
        gain = this.context.createGain();
        source.buffer = buffer;
        gain.gain.value = 0.85;
        source.connect(gain);
        gain.connect(this.output);
        const voice = { source, gain, priority: cue.priority };
        source.onended = () => {
          if (this.voice !== voice) return;
          this.voice = null;
          source!.disconnect();
          gain!.disconnect();
          this.onCue(null);
          this.onSpeaking(false);
        };
        source.start(this.context.currentTime);
        this.voice = voice;
        this.onCue(cue);
        this.onSpeaking(true);
      } catch {
        // A closing audio context can invalidate nodes while a clip is loading.
        if (this.voice?.source === source) this.voice = null;
        if (source) {
          source.onended = null;
          try {
            source.stop();
          } catch {}
          source.disconnect();
        }
        gain?.disconnect();
        this.onCue(null);
        this.onSpeaking(false);
      }
    });
  }

  stop(): void {
    this.generation++;
    if (this.pending) this.clearPending(this.pending.generation);
    const voice = this.voice;
    this.voice = null;
    if (voice) {
      voice.source.onended = null;
      try {
        voice.source.stop();
      } catch {}
      voice.source.disconnect();
      voice.gain.disconnect();
      this.onCue(null);
      this.onSpeaking(false);
    }
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.stop();
    this.abort.abort();
    for (const request of this.queue) request.resolve(null);
    this.queue = [];
    this.loads.clear();
    this.buffers.clear();
  }

  private clearPending(generation: number) {
    if (this.pending?.generation !== generation) return;
    clearTimeout(this.pending.timeout);
    this.pending = null;
  }

  private load(id: RadioId, urgent = false): Promise<AudioBuffer | null> {
    if (this.disposed) return Promise.resolve(null);
    const cached = this.buffers.get(id);
    if (cached) return Promise.resolve(cached);
    const loading = this.loads.get(id);
    if (loading) {
      // A live warning should not sit behind the remaining preload backlog.
      if (urgent) {
        const index = this.queue.findIndex((request) => request.id === id);
        if (index > 0) this.queue.unshift(...this.queue.splice(index, 1));
      }
      return loading;
    }
    let resolve!: LoadRequest['resolve'];
    const promise = new Promise<AudioBuffer | null>((done) => {
      resolve = done;
    });
    this.loads.set(id, promise);
    const request = { id, resolve };
    if (urgent) this.queue.unshift(request);
    else this.queue.push(request);
    this.drain();
    return promise;
  }

  private drain() {
    while (
      !this.disposed &&
      this.loading < LOAD_CONCURRENCY &&
      this.queue.length
    ) {
      const request = this.queue.shift()!;
      this.loading++;
      void this.fetchBuffer(request);
    }
  }

  private async fetchBuffer(request: LoadRequest) {
    let buffer: AudioBuffer | null = null;
    try {
      const response = await fetch(RADIO_ASSETS[request.id], {
        signal: this.abort.signal,
      });
      if (response.ok && !this.disposed) {
        const data = await response.arrayBuffer();
        if (!this.disposed && this.context.state !== 'closed') {
          const decoded = await this.context.decodeAudioData(data);
          if (!this.disposed) {
            buffer = decoded;
            this.buffers.set(request.id, decoded);
          }
        }
      }
    } catch {
      // Optional radio audio must never prevent the game from starting.
    } finally {
      this.loads.delete(request.id);
      this.loading--;
      request.resolve(buffer);
      this.drain();
    }
  }
}
