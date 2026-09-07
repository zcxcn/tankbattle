/** Offline fallback; the web game normally plays licensed library recordings. */
export const SHOT_SECONDS = [2.4, 0.24, 0.85, 0.95, 0.95, 0.8, 1.45] as const;
const profiles = [
  [0.4, 0.018, 1.65, 0.16, 2.3, 0.46, 68, 31, 0.4, 0.36],
  [1.45, 0.006, 1.05, 0.022, 0.45, 0.044, 150, 95, 0.12, 0.025],
  [1.25, 0.011, 1.65, 0.062, 0.95, 0.13, 95, 56, 0.14, 0.1],
  [1.8, 0.01, 1, 0.045, 1.05, 0.17, 160, 70, 0.12, 0.12],
  [0.48, 0.012, 0.95, 0.055, 1.5, 0.19, 112, 58, 0.2, 0.12],
  [0.7, 0.02, 0.6, 0.075, 0.9, 0.14, 420, 170, 0.18, 0.13],
  [1, 0.009, 0.9, 0.1, 1, 0.19, 80, 40, 0.14, 0.12],
] as const;
export function weaponRecording(weapon: number, sampleRate: number) {
  const kind = Number.isFinite(weapon)
    ? Math.max(0, Math.min(6, Math.floor(weapon)))
    : 0;
  const length = Math.ceil(SHOT_SECONDS[kind] * sampleRate);
  const data = new Float32Array(length);
  const [cg, ct, bg, bt, pg, pt, start, end, tg, tt] = profiles[kind];
  const alpha = (hz: number) => 1 - Math.exp((-2 * Math.PI * hz) / sampleRate);
  const a70 = alpha(70),
    a260 = alpha(260),
    a1400 = alpha(1400),
    a6500 = alpha(6500);
  let seed = 8017 + kind * 379,
    lp70 = 0,
    lp260 = 0,
    lp1400 = 0,
    lp6500 = 0,
    phase = 0;
  for (let i = 0; i < length; i++) {
    seed = (Math.imul(seed, 1664525) + 1013904223) | 0;
    const n = (seed >>> 0) / 2147483648 - 1,
      t = i / sampleRate;
    lp70 += (n - lp70) * a70;
    lp260 += (n - lp260) * a260;
    lp1400 += (n - lp1400) * a1400;
    lp6500 += (n - lp6500) * a6500;
    const pressure = (lp260 - lp70) * 3.5,
      blast = (lp1400 - lp260) * 1.8,
      crack = lp6500 - lp1400;
    phase +=
      (Math.PI * 2 * (end + (start - end) * Math.exp(-t * 28))) / sampleRate;
    let signal =
      crack * cg * Math.exp(-t / ct) +
      blast * bg * Math.exp(-t / bt) +
      pressure * pg * Math.exp(-t / pt) +
      Math.sin(phase) * tg * Math.exp(-t / tt);
    const click = (at: number, width: number, gain: number) =>
      crack * gain * Math.exp(-Math.abs(t - at) / width);
    if (kind === 0)
      signal += click(0.19, 0.012, 0.18) + click(0.29, 0.007, 0.08);
    if (kind === 1)
      signal += click(0.035, 0.003, 0.16) + click(0.07, 0.003, 0.08);
    if (kind === 2)
      signal += click(0.19, 0.012, 0.16) + click(0.28, 0.009, 0.12);
    if (kind === 3)
      signal +=
        Math.sin(950 * t - 22 * Math.exp(-t * 16)) * 0.09 * Math.exp(-t * 13);
    if (kind === 5)
      signal +=
        (crack * 0.4 + Math.sin(phase) * 0.07) *
        (Math.exp(-Math.abs(t - 0.045) * 180) +
          Math.exp(-Math.abs(t - 0.09) * 180));
    if (kind === 6)
      signal +=
        (blast * 0.7 + pressure * 1.3) *
        (1 - Math.exp(-t * 32)) *
        Math.exp(-t * 3.8);
    data[i] = Math.tanh(signal * 1.1) * Math.min(1, t * 3000);
  }
  // Immutable dry source: reflections never recursively echo each other.
  const dry = data.slice();
  for (const [delay, gain] of [
    [0.047, 0.18],
    [0.103, 0.115],
    [0.189, 0.07],
    [0.31, 0.035],
  ]) {
    const offset = Math.round(delay * sampleRate);
    for (let i = offset; i < length; i++)
      data[i] += dry[i - offset] * gain * (kind === 1 ? 0.5 : 1);
  }
  let peak = 0;
  for (let i = 0; i < length; i++) {
    data[i] *= Math.min(1, (length - 1 - i) / (sampleRate * 0.035));
    peak = Math.max(peak, Math.abs(data[i]));
  }
  const gain = (kind === 1 ? 0.65 : 0.88) / Math.max(peak, 0.01);
  for (let i = 0; i < length; i++) data[i] *= gain;
  return data;
}
