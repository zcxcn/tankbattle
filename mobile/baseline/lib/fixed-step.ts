import type { Battle, Input } from './engine';
/** The renderer may run at any refresh rate; combat always advances at 60 Hz. */
export class FixedStep {
  accumulator = 0;
  readonly step = 1 / 60;
  advance(battle: Battle, delta: number, input: Input) {
    if (battle.paused || battle.result) {
      this.accumulator = 0;
      return 0;
    }
    this.accumulator += Math.min(0.15, Math.max(0, delta));
    let steps = 0;
    while (this.accumulator + 1e-10 >= this.step && steps < 9) {
      battle.step(this.step, input);
      input.dash = false;
      input.emp = false;
      input.support = false;
      input.weapon = undefined;
      input.nextWeapon = false;
      this.accumulator -= this.step;
      steps++;
      if (battle.result) break;
    }
    return steps;
  }
  reset() {
    this.accumulator = 0;
  }
}
