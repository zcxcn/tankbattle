import type { Battle, Mine } from './engine';

/** Original command-center lines; their IDs also name the bundled voice clips. */
export const RADIO_LINES = {
  command_online: 'Command online. Weapons ready.',
  enemy_approaching: 'Enemy armor approaching.',
  target_destroyed: 'Target destroyed.',
  multiple_targets: 'Multiple targets eliminated.',
  boss_detected: 'Heavy armor detected. Engage with caution.',
  boss_escalating: 'Heavy armor escalating. Reinforcements inbound.',
  boss_final_assault: 'Boss entering final assault. Keep moving.',
  boss_destroyed: 'Heavy target destroyed.',
  incoming_barrage: 'Incoming barrage.',
  armor_low: 'Warning. Armor integrity low.',
  armor_critical: 'Armor critical. Seek repairs.',
  armor_restored: 'Repairs confirmed. Armor restored.',
  mine_deployed: 'Mine deployed.',
  hostile_mines: 'Hostile mines nearby. Use your pulse.',
  mines_cleared: 'Pulse successful. Mines cleared.',
  pulse_activated: 'Electromagnetic pulse activated.',
  ammo_low: 'Special weapon ammunition low.',
  ammo_depleted: 'Special ammunition depleted.',
  objective_secured: 'Objective secured.',
  mission_complete: 'Mission complete. Good work, commander.',
  mission_failed: 'Mission failed. Command out.',
} as const;

export type RadioId = keyof typeof RADIO_LINES;
export type RadioCue = {
  id: RadioId;
  text: string;
  priority: number;
  maxDelayMs?: number;
  valid?: () => boolean;
};
type Pending = Omit<RadioCue, 'valid'> & {
  readyAt: number;
  expiresAt: number;
  order: number;
  valid?: (battle: Battle) => boolean;
};
type Snapshot = {
  kills: number;
  bossId: number | undefined;
  bossDefeated: boolean;
  phase: number;
  windup: number;
  hp: number;
  empCd: number;
  ammo: number[];
  mines: Map<number, Mine>;
  objectives: Set<number>;
};
const distance = (a: { x: number; y: number }, b: { x: number; y: number }) =>
  Math.hypot(a.x - b.x, a.y - b.y);
const armor = (b: Battle) => b.player.hp / Math.max(1, b.player.maxHp);

/**
 * Observes gameplay, independently of audio playback. All time is simulation time,
 * so pausing freezes both speech cooldowns and pending events. Call once after
 * advancing the simulation; a new director belongs to each new battle.
 */
export class TacticalRadioDirector {
  private previous: Snapshot | null = null;
  private pending = new Map<string, Pending>();
  private announced = new Map<RadioId, number>();
  private sequence = 0;
  private lastAt = -Infinity;
  private lastPriority = 0;
  private ended = false;
  private enemyNear = false;
  private enemyClearSince = -Infinity;
  private mineNear = false;
  private armorState = 0;
  private killBatch = 0;
  private killDueAt = Infinity;

  private enqueue(
    id: RadioId,
    priority: number,
    now: number,
    options: {
      group?: string;
      ttl?: number;
      delay?: number;
      cooldown?: number;
      valid?: (battle: Battle) => boolean;
    } = {},
  ) {
    if (now - (this.announced.get(id) ?? -Infinity) < (options.cooldown ?? 0))
      return;
    this.pending.set(options.group ?? id, {
      id,
      text: RADIO_LINES[id],
      priority,
      readyAt: now + (options.delay ?? 0),
      expiresAt: now + (options.ttl ?? 8),
      order: this.sequence++,
      valid: options.valid,
    });
  }

  update(b: Battle): RadioCue | null {
    if (this.ended || b.paused) return null;
    const now = b.elapsed;
    if (b.result) {
      this.ended = true;
      this.pending.clear();
      const id = b.result.won ? 'mission_complete' : 'mission_failed';
      return { id, text: RADIO_LINES[id], priority: 120 };
    }

    const previous = this.previous;
    const boss = b.boss;
    if (!previous) {
      this.enqueue('command_online', 85, now, { ttl: 4 });
      if (boss)
        this.enqueue('boss_detected', 70, now, {
          delay: 3,
          ttl: 12,
          valid: (battle) => !!battle.boss,
        });
    } else {
      if (boss && boss.id !== previous.bossId)
        this.enqueue('boss_detected', 70, now, {
          ttl: 10,
          valid: (battle) => !!battle.boss,
        });
      if (b.bossDefeated && !previous.bossDefeated) {
        this.pending.delete('boss_detected');
        this.pending.delete('boss-phase');
        this.pending.delete('incoming_barrage');
        this.pending.delete('kills');
        this.killBatch = 0;
        this.killDueAt = Infinity;
        this.enqueue('boss_destroyed', 75, now);
      }
      if (boss && b.bossThreshold > previous.phase)
        this.enqueue(
          b.bossThreshold >= 2 ? 'boss_final_assault' : 'boss_escalating',
          78,
          now,
          { group: 'boss-phase', valid: (battle) => !!battle.boss },
        );
      if (
        boss &&
        (boss.attackWindup ?? 0) > 0 &&
        (previous.windup <= 0 || boss.id !== previous.bossId)
      )
        this.enqueue('incoming_barrage', 95, now, {
          ttl: Math.min(0.6, boss.attackWindup!),
          cooldown: 9,
          valid: (battle) =>
            !!battle.boss && (battle.boss.attackWindup ?? 0) > 0,
        });

      const defeated = b.kills - previous.kills;
      if (defeated > 0 && !(b.bossDefeated && !previous.bossDefeated)) {
        if (this.killBatch === 0) {
          this.killDueAt = now + 0.75;
        }
        this.killBatch += defeated;
      }
      if (now >= this.killDueAt) {
        this.enqueue(
          this.killBatch > 1 ? 'multiple_targets' : 'target_destroyed',
          30,
          now,
          { group: 'kills', ttl: 5, cooldown: 7 },
        );
        this.killBatch = 0;
        this.killDueAt = Infinity;
      }

      const pulseUsed = b.empCd > previous.empCd + 0.5;
      const cleared =
        pulseUsed &&
        [...previous.mines.values()].some(
          (mine) =>
            mine.expiresAt > now &&
            distance(mine, b.player) <= 300 &&
            !b.mines.some((current) => current.id === mine.id),
        );
      if (pulseUsed) {
        this.pending.delete('hostile_mines');
        this.enqueue(cleared ? 'mines_cleared' : 'pulse_activated', 55, now, {
          group: 'pulse',
          ttl: 5,
        });
      }
      if (b.mines.some((mine) => !mine.enemy && !previous.mines.has(mine.id)))
        this.enqueue('mine_deployed', 35, now, {
          ttl: 4,
          cooldown: 6,
        });

      const depleted = b.ammo.findIndex(
        (amount, index) =>
          index > 0 && amount === 0 && previous.ammo[index] > 0,
      );
      const low = b.ammo.findIndex(
        (amount, index) =>
          index > 0 && amount > 0 && amount <= 3 && previous.ammo[index] > 3,
      );
      if (depleted > 0)
        this.enqueue('ammo_depleted', 65, now, {
          group: 'ammo',
          ttl: 6,
          cooldown: 8,
          valid: (battle) => battle.ammo[depleted] === 0,
        });
      else if (
        low > 0 &&
        !(
          this.pending.get('ammo')?.id === 'ammo_depleted' &&
          this.pending.get('ammo')?.valid?.(b)
        )
      )
        this.enqueue('ammo_low', 40, now, {
          group: 'ammo',
          ttl: 5,
          cooldown: 12,
          valid: (battle) => battle.ammo[low] > 0 && battle.ammo[low] <= 3,
        });
      if (
        b.objectives.some(
          (objective) =>
            objective.done &&
            objective.kind !== 'exit' &&
            !previous.objectives.has(objective.id),
        )
      )
        this.enqueue('objective_secured', 60, now, { ttl: 9 });
    }

    const ratio = armor(b);
    if (ratio <= 0.2 && this.armorState < 2) {
      this.armorState = 2;
      this.enqueue('armor_critical', 100, now, {
        group: 'armor',
        cooldown: 12,
        valid: (battle) => armor(battle) <= 0.3,
      });
    } else if (ratio <= 0.4 && this.armorState === 0) {
      this.armorState = 1;
      this.enqueue('armor_low', 80, now, {
        group: 'armor',
        cooldown: 16,
        valid: (battle) => armor(battle) <= 0.45,
      });
    } else if (ratio >= 0.58 && this.armorState > 0) {
      this.armorState = 0;
      this.pending.delete('armor');
      if (previous && b.player.hp > previous.hp)
        this.enqueue('armor_restored', 25, now, {
          ttl: 5,
          cooldown: 20,
          valid: (battle) => armor(battle) >= 0.58,
        });
    } else if (ratio >= 0.32 && this.armorState === 2) this.armorState = 1;

    const nearest = b.enemies.reduce(
      (minimum, enemy) =>
        enemy.hp > 0 && enemy.spawn <= 0
          ? Math.min(minimum, distance(enemy, b.player))
          : minimum,
      Infinity,
    );
    if (nearest <= 430 && !this.enemyNear) {
      this.enemyNear = true;
      this.enqueue('enemy_approaching', 50, now, {
        ttl: 6,
        cooldown: 16,
        valid: (battle) =>
          battle.enemies.some(
            (enemy) =>
              enemy.hp > 0 &&
              enemy.spawn <= 0 &&
              distance(enemy, battle.player) <= 600,
          ),
      });
    }
    if (nearest > 600) {
      if (this.enemyClearSince === Infinity) this.enemyClearSince = now;
      if (now - this.enemyClearSince >= 3) this.enemyNear = false;
    } else this.enemyClearSince = Infinity;

    const nearMine = b.mines.some(
      (mine) => mine.enemy && distance(mine, b.player) <= 220,
    );
    if (nearMine && !this.mineNear) {
      this.mineNear = true;
      this.enqueue('hostile_mines', 88, now, {
        ttl: 5,
        cooldown: 14,
        valid: (battle) =>
          battle.mines.some(
            (mine) => mine.enemy && distance(mine, battle.player) <= 300,
          ),
      });
    } else if (
      !b.mines.some((mine) => mine.enemy && distance(mine, b.player) <= 340)
    ) {
      this.mineNear = false;
      this.pending.delete('hostile_mines');
    }

    this.previous = {
      kills: b.kills,
      bossId: boss?.id,
      bossDefeated: b.bossDefeated,
      phase: b.bossThreshold,
      windup: boss?.attackWindup ?? 0,
      hp: b.player.hp,
      empCd: b.empCd,
      ammo: [...b.ammo],
      mines: new Map(b.mines.map((mine) => [mine.id, { ...mine }])),
      objectives: new Set(b.objectives.filter((o) => o.done).map((o) => o.id)),
    };
    for (const [key, cue] of this.pending)
      if (cue.expiresAt < now || (cue.valid && !cue.valid(b)))
        this.pending.delete(key);

    const available = [...this.pending.entries()]
      .filter(
        ([, cue]) =>
          cue.readyAt <= now &&
          (now - this.lastAt >= 4 ||
            (cue.priority >= 90 &&
              cue.priority > this.lastPriority &&
              now - this.lastAt >= 0.35)),
      )
      .sort((a, z) => z[1].priority - a[1].priority || a[1].order - z[1].order);
    const selected = available[0];
    if (!selected) return null;
    const [key, cue] = selected;
    this.pending.delete(key);
    this.lastAt = now;
    this.lastPriority = cue.priority;
    this.announced.set(cue.id, now);
    if (key === 'kills') {
      // A quiet interval after either kill line also throttles its alternate.
      this.announced.set('target_destroyed', now);
      this.announced.set('multiple_targets', now);
    }
    return {
      id: cue.id,
      text: cue.text,
      priority: cue.priority,
      maxDelayMs: Math.max(0, Math.min(2000, (cue.expiresAt - now) * 1000)),
      valid: () =>
        !b.paused &&
        !b.result &&
        b.elapsed <= cue.expiresAt &&
        (!cue.valid || cue.valid(b)),
    };
  }
}
