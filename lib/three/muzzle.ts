import { Mesh, MeshBuilder, ShaderMaterial, type Scene } from './babylon';
import type { Battle, Tank } from '../engine';
import { worldPosition } from './world';
import { blastVertex, blastFragment } from './explosions';

type Shot = NonNullable<Tank['lastShot']>;

/** Fast recoil followed by a damped return; hits never trigger a firing action. */
export function recoilDistance(weapon: number, age: number) {
  const duration = weapon === 1 ? 0.1 : weapon === 6 ? 0.2 : 0.34;
  const peak =
    weapon === 1 ? 0.045 : weapon === 6 ? 0.12 : weapon === 0 ? 0.46 : 0.3;
  if (!Number.isFinite(age) || age < 0 || age >= duration) return 0;
  const attack = 0.025;
  return age < attack
    ? peak * Math.sin(((age / attack) * Math.PI) / 2)
    : peak * (1 - (age - attack) / (duration - attack)) ** 2;
}

/** Fixed-size sprite pool, using the same turbulent fire/smoke shader as impacts. */
export class MuzzleEffects {
  private material: ShaderMaterial;
  private pool: Mesh[] = [];
  private seen = new WeakSet<Shot>();
  private shots: Shot[] = [];
  private lastTime = -1;
  private used = 0;
  constructor(
    private scene: Scene,
    private mobile: boolean,
  ) {
    this.material = new ShaderMaterial(
      'muzzle-gas-and-dust',
      scene,
      { vertexSource: blastVertex, fragmentSource: blastFragment },
      {
        attributes: ['position', 'uv'],
        uniforms: [
          'worldViewProjection',
          'world',
          'puff',
          'weapon',
          'fogColor',
          'eye',
          'fogDensity',
        ],
        needAlphaBlending: true,
      },
    );
    this.material.backFaceCulling = false;
    this.material.disableDepthWrite = true;
    this.material.onBindObservable.add((mesh) => {
      const p = mesh?.metadata;
      if (!p) return;
      const effect = this.material.getEffect();
      if (!effect) return;
      effect.setFloat4('puff', p.age, p.seed, p.alpha, p.mode);
      effect.setFloat('weapon', p.weapon);
      effect.setColor3('fogColor', scene.fogColor);
      effect.setFloat('fogDensity', scene.fogDensity);
      if (scene.activeCamera)
        effect.setVector3('eye', scene.activeCamera.globalPosition);
    });
  }
  get stats() {
    return {
      active: this.shots.length,
      visible: this.used,
      pooled: this.pool.length,
    };
  }
  update(b: Battle, effectScale = 1) {
    if (b.elapsed < this.lastTime) {
      this.shots = [];
      this.seen = new WeakSet();
    }
    this.lastTime = b.elapsed;
    for (const tank of [b.player, ...b.enemies]) {
      const shot = tank.lastShot;
      if (!shot || this.seen.has(shot)) continue;
      this.seen.add(shot);
      if (b.elapsed - shot.at < 0.7) this.shots.push(shot);
    }
    this.shots = this.shots
      .filter((s) => b.elapsed - s.at < 0.7)
      .slice(this.mobile ? -8 : -16);
    this.used = 0;
    const limit = Math.floor(
      (this.mobile ? 24 : 64) * Math.max(0, Math.min(1, effectScale)),
    );
    // Latest shots get the bright transient before older smoke uses the budget.
    for (const shot of [...this.shots].reverse()) {
      const age = b.elapsed - shot.at;
      if (age < 0) continue;
      const light = shot.weapon === 1;
      const scale = light ? 0.28 : shot.weapon === 6 ? 0.55 : 1;
      const puff = (
        mode: number,
        forward: number,
        height: number,
        width: number,
        depth: number,
        alpha: number,
        seed = 0,
      ) => {
        if (this.used >= limit || alpha < 0.01) return;
        let mesh = this.pool[this.used];
        if (!mesh) {
          mesh = MeshBuilder.CreatePlane(
            'pooled-muzzle-gas',
            { size: 1 },
            this.scene,
          );
          mesh.material = this.material;
          mesh.isPickable = false;
          mesh.metadata = {};
          this.pool.push(mesh);
        }
        this.used++;
        mesh.setEnabled(true);
        mesh.position.copyFrom(
          worldPosition(
            shot.x + Math.cos(shot.angle) * forward * 10,
            shot.y + Math.sin(shot.angle) * forward * 10,
            height,
          ),
        );
        mesh.scaling.set(width, depth, 1);
        mesh.rotation.set(
          mode === 5 ? Math.PI / 2 : 0,
          mode === 5 ? -shot.angle : 0,
          0,
        );
        mesh.billboardMode =
          mode === 5 ? Mesh.BILLBOARDMODE_NONE : Mesh.BILLBOARDMODE_ALL;
        Object.assign(mesh.metadata, {
          age,
          mode,
          alpha,
          seed: shot.at * 31 + shot.x * 0.07 + seed,
          weapon: shot.weapon,
        });
      };
      const elevation = shot.height * 0.1;
      if (age < 0.045)
        puff(
          3,
          0.12,
          elevation,
          0.7 * scale,
          0.6 * scale,
          (1 - age / 0.045) * 0.9,
        );
      if (age < 0.085)
        puff(
          0,
          0.25 + age * 9,
          elevation,
          (0.6 + age * 10) * scale,
          (0.45 + age * 8) * scale,
          (1 - age / 0.085) * 0.85,
          7,
        );
      if (!light && age > 0.025) {
        const fade = Math.min(1, age * 16) * (1 - age / 0.7) ** 2;
        puff(
          1,
          0.25 + age * 2.2,
          elevation + age * 0.65,
          (0.45 + age * 2.8) * scale,
          (0.4 + age * 2.1) * scale,
          fade * 0.32,
          13,
        );
        if (shot.weapon === 0 || shot.weapon === 4)
          puff(
            5,
            0.5 + age,
            0.12,
            1.1 + age * 5,
            0.65 + age * 2.6,
            fade * 0.25,
            23,
          );
      }
    }
    for (let i = this.used; i < this.pool.length; i++)
      this.pool[i].setEnabled(false);
  }
  dispose() {
    for (const mesh of this.pool) mesh.dispose();
    this.material.dispose();
    this.pool = [];
    this.shots = [];
    this.seen = new WeakSet();
  }
}
