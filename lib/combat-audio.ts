import { COMBAT_AUDIO_ASSETS, type CombatClip } from './combat-audio-assets';

/** Decode once; a late download may supply future sounds, never replay an old shot. */
export class CombatAudioBank {
  private buffers = new Map<CombatClip, AudioBuffer>();
  private finished = new Set<CombatClip>();
  private requests = new Set<AbortController>();
  private loading: Promise<void> | null = null;
  private disposed = false;

  constructor(private readonly context: AudioContext) {}

  get(id: CombatClip) {
    return this.buffers.get(id);
  }

  settled(id: CombatClip) {
    return this.finished.has(id) || !COMBAT_AUDIO_ASSETS[id];
  }

  preload(): Promise<void> {
    if (this.disposed) return Promise.resolve();
    return (this.loading ??= this.loadAll());
  }

  private async loadAll() {
    const queue = Object.keys(COMBAT_AUDIO_ASSETS) as CombatClip[];
    const worker = async () => {
      while (queue.length && !this.disposed) {
        const id = queue.shift()!;
        const request = new AbortController();
        this.requests.add(request);
        const timeout = setTimeout(() => request.abort(), 10_000);
        try {
          const response = await fetch(COMBAT_AUDIO_ASSETS[id], {
            signal: request.signal,
          });
          if (!response.ok) continue;
          const bytes = await response.arrayBuffer();
          if (this.disposed || request.signal.aborted) continue;
          const buffer = await this.context.decodeAudioData(bytes);
          if (!this.disposed && !request.signal.aborted)
            this.buffers.set(id, buffer);
        } catch {
          // Offline/failed clips use the procedural fallback for this battle.
        } finally {
          clearTimeout(timeout);
          this.requests.delete(request);
          this.finished.add(id);
        }
      }
    };
    await Promise.all(Array.from({ length: 3 }, worker));
  }

  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    for (const request of this.requests) request.abort();
    this.requests.clear();
    this.buffers.clear();
  }
}
