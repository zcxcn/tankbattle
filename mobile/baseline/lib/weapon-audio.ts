/** Short original synthesized recordings, cached once per weapon by GameAudio. */
export const SHOT_SECONDS = [0.65, 0.16, 0.58, 0.72, 0.8, 0.58, 1.05] as const;
export function weaponRecording(weapon: number, sampleRate: number) {
  const kind = Math.max(0, Math.min(6, Math.floor(weapon)));
  const length = Math.ceil(SHOT_SECONDS[kind] * sampleRate);
  const data = new Float32Array(length);
  let seed = 8017 + kind * 379,
    low = 0,
    mid = 0,
    phase = 0;
  const noise = () => {
    seed = (Math.imul(seed, 1664525) + 1013904223) | 0;
    return (seed >>> 0) / 2147483648 - 1;
  };
  for (let i = 0; i < length; i++) {
    const t = i / sampleRate,
      n = noise();
    low += (n - low) * (1 - Math.exp((-Math.PI * 2 * 360) / sampleRate));
    mid += (n - mid) * (1 - Math.exp((-Math.PI * 2 * 2800) / sampleRate));
    const crack = n - mid;
    const attack = Math.min(1, t * 2200);
    let signal = 0;
    if (kind === 0) {
      // Cannon: sharp ignition, chesty pressure wave, steel breech.
      phase += (Math.PI * 2 * (45 + 95 * Math.exp(-t * 25))) / sampleRate;
      signal =
        0.8 * Math.sin(phase) * Math.exp(-t * 10) +
        crack * Math.exp(-t * 85) * 1.6 +
        low * Math.exp(-t * 9) * 1.5;
    } else if (kind === 1) {
      // Dry machine-gun crack, with a short bolt click.
      phase += (Math.PI * 2 * (110 + 110 * Math.exp(-t * 90))) / sampleRate;
      signal =
        (crack * 1.2 + mid * 0.9) * Math.exp(-t * 75) +
        Math.sin(phase) * 0.5 * Math.exp(-t * 42);
      signal += crack * 0.35 * Math.exp(-Math.abs(t - 0.065) * 500);
    } else if (kind === 2) {
      // Shotgun: wide blast followed by the pump/chamber clack.
      phase += (Math.PI * 2 * (65 + 120 * Math.exp(-t * 45))) / sampleRate;
      signal =
        mid * 1.8 * Math.exp(-t * 23) +
        Math.sin(phase) * 0.6 * Math.exp(-t * 15);
      signal += crack * 0.55 * Math.exp(-Math.abs(t - 0.21) * 110);
    } else if (kind === 3) {
      // Magnetic rail discharge with a descending electrical arc.
      phase += (Math.PI * 2 * (190 + 2100 * Math.exp(-t * 15))) / sampleRate;
      signal =
        Math.sin(phase) *
          (0.3 + Math.sin(phase * 0.51) * 0.16) *
          Math.exp(-t * 7) +
        crack * Math.exp(-t * 33) * 1.2 +
        low * Math.exp(-t * 13);
    } else if (kind === 4) {
      // Grenade launcher: hollow tube thump and resonant casing.
      phase += (Math.PI * 2 * (38 + 78 * Math.exp(-t * 16))) / sampleRate;
      signal =
        Math.sin(phase) * Math.exp(-t * 8) * 0.85 +
        low * Math.exp(-t * 11) * 2 +
        crack * Math.exp(-t * 120) * 0.4;
      signal += Math.sin(t * Math.PI * 2 * 410) * Math.exp(-t * 18) * 0.12;
    } else if (kind === 5) {
      // Frost emitter: icy electrical pulse, three fading ripples.
      phase += (Math.PI * 2 * (330 + 1250 * Math.exp(-t * 9))) / sampleRate;
      signal =
        (Math.sin(phase) * 0.45 + Math.sin(phase * 1.501) * 0.2) *
          Math.exp(-t * 7) *
          (0.7 + 0.3 * Math.cos(t * 58)) +
        crack * Math.exp(-t * 18) * 0.35;
    } else {
      // Rocket: launch charge followed by a sustained turbine/gas rush.
      phase += (Math.PI * 2 * (42 + 100 * Math.exp(-t * 35))) / sampleRate;
      const jet = Math.min(1, t * 35) * Math.exp(-t * 4.8);
      signal =
        Math.sin(phase) * Math.exp(-t * 16) * 0.7 +
        low * jet * 2.8 +
        mid * jet * 0.35 +
        crack * Math.exp(-t * 90);
    }
    data[i] = Math.tanh(signal * 1.3) * attack;
  }
  // Very short outdoor reflections; baked in to avoid per-shot reverb nodes.
  if (kind !== 1)
    for (const [delay, gain] of [
      [0.073, 0.16],
      [0.127, 0.09],
    ]) {
      const offset = Math.round(delay * sampleRate);
      for (let i = length - 1; i >= offset; i--)
        data[i] += data[i - offset] * gain;
    }
  let peak = 0;
  for (let i = 0; i < length; i++) {
    data[i] *= Math.min(1, (length - 1 - i) / (sampleRate * 0.025));
    peak = Math.max(peak, Math.abs(data[i]));
  }
  const gain = (kind === 1 ? 0.65 : 0.88) / Math.max(peak, 0.01);
  for (let i = 0; i < length; i++) data[i] *= gain;
  return data;
}
