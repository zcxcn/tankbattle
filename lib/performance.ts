export type FrameRate = 30 | 45 | 60;
export type Resolution = 'adaptive' | 'sharp' | 'ultra';

/** Babylon scaling is CSS pixels per rendered pixel, not device pixels. */
export function resolutionScale(
  width: number,
  height: number,
  dpr: number,
  mode: Resolution = 'sharp',
  load = 1,
) {
  const w = Math.max(1, width || 1),
    h = Math.max(1, height || 1);
  const native = Number.isFinite(dpr) ? Math.max(1, Math.min(4, dpr)) : 1;
  const density = Math.min(
    native,
    mode === 'ultra' ? 3 : mode === 'sharp' ? 2 : 1.5,
  );
  const pixels =
    mode === 'ultra' ? 3_200_000 : mode === 'sharp' ? 2_000_000 : 1_000_000;
  const edge = mode === 'ultra' ? 2800 : mode === 'sharp' ? 2400 : 1800;
  // A bounded pixel budget protects tablets and rotation without blurring small phones.
  const base = Math.max(
    1 / density,
    Math.sqrt((w * h) / pixels),
    Math.max(w, h) / edge,
  );
  return base * Math.max(1, Math.min(2.2, Number.isFinite(load) ? load : 1));
}
export type DeviceState = {
  thermal: number;
  powerSave: boolean;
  background: boolean;
};
export const deviceState: DeviceState = {
  thermal: 0,
  powerSave: false,
  background: false,
};
export function isMobileDevice() {
  return (
    typeof window !== 'undefined' &&
    (/Android|iPhone|iPad/i.test(navigator.userAgent) ||
      navigator.maxTouchPoints > 1)
  );
}
export function renderPolicy(
  fps: FrameRate,
  mobile: boolean,
  state: DeviceState,
  pressure = 0,
) {
  const severe = state.thermal >= 3;
  const limited = state.powerSave || state.thermal >= 2;
  return {
    fps: severe ? 20 : limited ? Math.min(fps, 30) : fps,
    scale:
      1 *
      (severe ? 1.6 : limited ? 1.3 : 1) *
      (1 + Math.max(0, pressure - 1) * 0.12),
    // Reduce optional effects first; retain crisp geometry during brief GPU pressure.
    effects: severe
      ? 0.35
      : limited
        ? 0.6
        : Math.max(0.55, 1 - pressure * 0.15),
    label: severe
      ? '降温保护 · 20 帧'
      : limited
        ? '温控省电 · 30 帧'
        : `${fps} 帧${mobile ? ' · 自适应画面' : ''}`,
  };
}

/** Deadline pacing works at 60/90/120 Hz without accumulating drift. */
export class FramePacer {
  private due = 0;
  reset() {
    this.due = 0;
  }
  take(now: number, fps: number) {
    if (now + 0.5 < this.due) return false;
    const interval = 1000 / fps;
    this.due =
      this.due && now - this.due < interval * 2
        ? this.due + interval
        : now + interval;
    return true;
  }
}

/** Lower resolution only after sustained slow frames; recover slowly to avoid oscillation. */
export class AdaptiveResolution {
  pressure = 0;
  private elapsed = 0;
  private samples = 0;
  private healthyMs = 0;
  sample(elapsedMs: number, targetFps: number) {
    this.elapsed += elapsedMs;
    this.samples++;
    if (this.elapsed < 4000) return this.pressure;
    const average = this.elapsed / this.samples;
    if (average > (1000 / targetFps) * 1.2) {
      this.pressure = Math.min(3, this.pressure + 1);
      this.healthyMs = 0;
    } else {
      this.healthyMs += this.elapsed;
      if (this.healthyMs >= 20000 && this.pressure > 0) {
        this.pressure--;
        this.healthyMs = 0;
      }
    }
    this.elapsed = 0;
    this.samples = 0;
    return this.pressure;
  }
}
