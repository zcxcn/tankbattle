/** Standard Gamepad API mapping. Keep browser access separate so controls are testable. */
export type PadSnapshot = {
  index: number;
  id: string;
  connected: boolean;
  mapping: string;
  axes: readonly number[];
  buttons: readonly { pressed: boolean; value: number }[];
};
export type PadFrame = {
  connected: boolean;
  disconnected: boolean;
  name: string;
  x: number;
  y: number;
  aimX: number;
  aimY: number;
  fire: boolean;
  dash: boolean;
  emp: boolean;
  support: boolean;
  mine: boolean;
  pause: boolean;
  camera: boolean;
  weapon: boolean;
  music: boolean;
  confirm: boolean;
  back: boolean;
  direction: number;
  active: boolean;
};
const blank = (): PadFrame => ({
  connected: false,
  disconnected: false,
  name: '',
  x: 0,
  y: 0,
  aimX: 0,
  aimY: 0,
  fire: false,
  dash: false,
  emp: false,
  support: false,
  mine: false,
  pause: false,
  camera: false,
  weapon: false,
  music: false,
  confirm: false,
  back: false,
  direction: 0,
  active: false,
});
export function deadzone(x = 0, y = 0, threshold = 0.2) {
  if (!Number.isFinite(x) || !Number.isFinite(y)) return { x: 0, y: 0 };
  const length = Math.hypot(x, y);
  if (length <= threshold) return { x: 0, y: 0 };
  const scale = Math.min(1, (length - threshold) / (1 - threshold)) / length;
  return { x: x * scale, y: y * scale };
}
export class PadReader {
  index: number | null = null;
  private held: boolean[] = [];
  private direction = 0;
  private repeatAt = 0;
  sample(pads: readonly (PadSnapshot | null)[], now: number): PadFrame {
    const old = this.index;
    let pad = pads.find(
      (p) => p?.index === old && p.connected && p.mapping === 'standard',
    );
    if (!pad && old !== null) {
      this.index = null;
      this.held = [];
      this.direction = 0;
      return { ...blank(), disconnected: true };
    }
    pad ??= pads.find((p) => p?.connected && p.mapping === 'standard');
    if (!pad) return blank();
    const fresh = this.index !== pad.index;
    this.index = pad.index;
    const buttons = Array.from(pad.buttons, (b) => b.pressed || b.value > 0.25);
    const pressed = (n: number) => !!buttons[n] && !this.held[n] && !fresh;
    const move = deadzone(pad.axes[0], pad.axes[1], 0.18),
      aim = deadzone(pad.axes[2], pad.axes[3], 0.22);
    // 1 up, 2 right, 3 down, 4 left; held directions repeat for menu navigation.
    const dir = buttons[12]
      ? 1
      : buttons[15]
        ? 2
        : buttons[13]
          ? 3
          : buttons[14]
            ? 4
            : Math.max(Math.abs(move.x), Math.abs(move.y)) < 0.5
              ? 0
              : Math.abs(move.x) > Math.abs(move.y)
                ? move.x > 0
                  ? 2
                  : 4
                : move.y > 0
                  ? 3
                  : 1;
    let direction = 0;
    if (dir && (dir !== this.direction || now >= this.repeatAt)) {
      direction = dir;
      this.repeatAt = now + (dir !== this.direction ? 360 : 140);
    }
    this.direction = dir;
    const frame: PadFrame = {
      connected: true,
      disconnected: false,
      name: pad.id,
      x: move.x,
      y: move.y,
      aimX: aim.x,
      aimY: aim.y,
      fire: !!buttons[7],
      dash: pressed(4),
      emp: pressed(5),
      support: pressed(6),
      mine: pressed(11),
      pause: pressed(9),
      camera: pressed(3),
      weapon: pressed(2),
      music: pressed(8),
      confirm: pressed(0),
      back: pressed(1),
      direction,
      active:
        buttons.some(Boolean) || !!move.x || !!move.y || !!aim.x || !!aim.y,
    };
    this.held = buttons;
    return frame;
  }
}
