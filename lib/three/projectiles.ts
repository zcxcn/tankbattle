import {
  Matrix,
  Mesh,
  MeshBuilder,
  Quaternion,
  Scene,
  Vector3,
  type Material,
} from './babylon';
import { type Bullet, type Battle } from '../engine';
import { emissive, pbr, type Quality } from './materials';
import { heading, worldPosition } from './world';

const COLORS = [
  '#ffd57a',
  '#ff824b',
  '#f5eee1',
  '#b995ff',
  '#ffa333',
  '#55e8ff',
  '#d99764',
];
const TRAIL_LIFE = [0.035, 0.022, 0.035, 0.2, 0.18, 0.14, 0.56];
type Sample = { position: Vector3; time: number };
type Flight = {
  weapon: number;
  enemy: boolean;
  born: number;
  tracer: boolean;
  seed: number;
  points: Sample[];
  retired?: number;
};

/** One draw batch per shape/material; matrices and colors have fixed capacity. */
class Batch {
  count = 0;
  readonly matrices: Float32Array;
  private colors: Float32Array;
  private matrix = Matrix.Identity();
  private rotation = Quaternion.Identity();
  private scale = Vector3.One();
  constructor(
    readonly mesh: Mesh,
    readonly capacity: number,
    material: Material,
  ) {
    this.matrices = new Float32Array(capacity * 16);
    this.colors = new Float32Array(capacity * 4).fill(1);
    mesh.material = material;
    mesh.isPickable = false;
    mesh.alwaysSelectAsActiveMesh = true;
    mesh.doNotSyncBoundingInfo = true;
    mesh.hasVertexAlpha = true;
    mesh.thinInstanceSetBuffer('matrix', this.matrices, 16, false);
    mesh.thinInstanceSetBuffer('color', this.colors, 4, false);
    mesh.thinInstanceCount = 0;
    mesh.setEnabled(false);
  }
  add(
    position: Vector3,
    x: number,
    y: number,
    z: number,
    yaw = 0,
    roll = 0,
    alpha = 1,
    pitch = 0,
  ) {
    if (this.count >= this.capacity) return;
    this.scale.set(x, y, z);
    Quaternion.RotationYawPitchRollToRef(yaw, pitch, roll, this.rotation);
    Matrix.ComposeToRef(this.scale, this.rotation, position, this.matrix);
    this.matrix.copyToArray(this.matrices, this.count * 16);
    this.colors[this.count * 4 + 3] = alpha;
    this.count++;
  }
  flush() {
    this.mesh.thinInstanceCount = this.count;
    this.mesh.setEnabled(this.count > 0);
    if (this.count) {
      this.mesh.thinInstanceBufferUpdated('matrix');
      this.mesh.thinInstanceBufferUpdated('color');
    }
  }
}

export class ProjectileEffects {
  private batches: Batch[] = [];
  private bodies: Batch[];
  private trails: Batch[];
  private core: Batch;
  private flame: Batch;
  private rocketNose: Batch;
  private enemyShell: Batch;
  private enemyTrail: Batch;
  private flights = new Map<Bullet, Flight>();
  private retired: Flight[] = [];
  private lastTime = -1;
  private shotSequence = 0;
  private bodyCount = 0;
  private trailCount = 0;
  private materials: Material[] = [];
  constructor(
    private scene: Scene,
    private quality: Quality,
    private mobile: boolean,
  ) {
    const batch = (mesh: Mesh, material: Material, capacity = 100) => {
      const result = new Batch(mesh, capacity, material);
      this.batches.push(result);
      return result;
    };
    const glow = (name: string, color: string, strength = 1.8, alpha = 1) => {
      const material = emissive(scene, name, color, strength);
      material.alpha = alpha;
      material.disableDepthWrite = alpha < 1;
      this.materials.push(material);
      return material;
    };
    const metal = (
      name: string,
      color: string,
      metallic = 0.62,
      roughness = 0.58,
      alpha = 1,
    ) => {
      const material = pbr(scene, name, color, metallic, roughness);
      material.alpha = alpha;
      material.disableDepthWrite = alpha < 1;
      this.materials.push(material);
      return material;
    };
    const axial = (
      name: string,
      diameter: number,
      height: number,
      tip = diameter,
      tessellation = 8,
    ) => {
      const mesh = MeshBuilder.CreateCylinder(
        name,
        { diameterBottom: diameter, diameterTop: tip, height, tessellation },
        scene,
      );
      mesh.rotation.x = Math.PI / 2;
      mesh.bakeCurrentTransformIntoVertices();
      return mesh;
    };
    const sphere = (name: string, diameter: number) =>
      MeshBuilder.CreateSphere(name, { diameter, segments: 6 }, scene);
    const bodyMeshes = [
      axial('shell-ap-steel', 0.12, 0.68, 0.045),
      axial('machinegun-jacketed-round', 0.045, 0.24, 0.012),
      sphere('shotgun-tungsten-pellet', 0.075),
      axial('railgun-violet-lance', 0.19, 2.7, 0.035, 4),
      axial('grenade-heavy-casing', 0.24, 0.43, 0.12),
      MeshBuilder.CreatePolyhedron(
        'cryo-crystal',
        { type: 1, size: 0.38 },
        scene,
      ),
      axial('guided-rocket-hull', 0.32, 1.1),
    ];
    // Rocket fins share a single geometry and draw call with the metal fuselage.
    const fins = [0, Math.PI / 2].map((rotation) => {
      const fin = MeshBuilder.CreateBox(
        'rocket-fin',
        { width: 0.9, height: 0.055, depth: 0.42 },
        scene,
      );
      fin.position.z = -0.39;
      fin.rotation.z = rotation;
      return fin;
    });
    bodyMeshes[6] = Mesh.MergeMeshes([bodyMeshes[6], ...fins], true, true)!;
    bodyMeshes[6].name = 'guided-rocket-finned-hull';
    const bodyMaterials = [
      metal('ap-projectile-steel', '#b2a484'),
      metal('machinegun-copper-jacket', '#9b8872', 0.75),
      metal('tungsten-pellet-metal', '#9aa0a0', 0.8),
      glow('projectile-color-3', COLORS[3], 1.65),
      metal('grenade-olive-casing', '#646958', 0.22, 0.78),
      glow('projectile-color-5', COLORS[5], 0.95),
      metal('rocket-titanium', '#c1c7bd', 0.45, 0.6),
    ];
    this.bodies = bodyMeshes.map((mesh, i) => batch(mesh, bodyMaterials[i]));
    this.trails = COLORS.map((color, i) => {
      const mesh =
        i === 6
          ? sphere('rocket-smoke-trail', 1)
          : i === 4
            ? sphere('grenade-dust-trail', 1)
            : i === 5
              ? MeshBuilder.CreateTorus(
                  'cryo-wave-trail',
                  { diameter: 1, thickness: 0.075, tessellation: 12 },
                  scene,
                )
              : MeshBuilder.CreateBox('weapon-trail-' + i, { size: 1 }, scene);
      if (i === 5) {
        mesh.rotation.x = Math.PI / 2;
        mesh.bakeCurrentTransformIntoVertices();
      }
      return batch(
        mesh,
        i === 6 || i === 4
          ? metal(
              'projectile-smoke-' + i,
              i === 6 ? '#8c918b' : '#8b8272',
              0,
              0.98,
              i === 6 ? 0.27 : 0.12,
            )
          : glow(
              'trail-color-' + i,
              color,
              i === 3 ? 1.4 : 0.9,
              i === 3 ? 0.55 : 0.45,
            ),
        360,
      );
    });
    this.core = batch(
      axial('projectile-white-core', 0.07, 1),
      glow('projectile-core-white', '#e9ddff', 1.7),
    );
    this.flame = batch(
      axial('rocket-tapered-exhaust', 0.24, 1, 0.015),
      glow('rocket-orange-exhaust', '#fcb574', 1.6, 0.7),
    );
    this.rocketNose = batch(
      axial('rocket-red-nose', 0.33, 0.45, 0),
      metal('rocket-nose-red', '#745646', 0.2, 0.76),
    );
    this.enemyShell = batch(
      axial('enemy-red-shell', 0.13, 0.72, 0.05),
      metal('hostile-ap-shell-metal', '#887665'),
    );
    this.enemyTrail = batch(
      MeshBuilder.CreateBox('hostile-red-trail', { size: 1 }, scene),
      glow('hostile-trail-red', '#dc8962', 1, 0.45),
      360,
    );
  }
  get stats() {
    return {
      bodies: this.bodyCount,
      trails: this.trailCount,
      flights: this.flights.size,
      retired: this.retired.length,
      batches: this.batches.length,
    };
  }
  update(b: Battle, effectScale = 1) {
    const now = b.elapsed;
    if (now < this.lastTime) {
      this.flights.clear();
      this.retired = [];
      this.shotSequence = 0;
    }
    this.lastTime = now;
    this.bodyCount = 0;
    this.trailCount = 0;
    for (const batch of this.batches) batch.count = 0;
    const visible = b.bullets
      .filter((bullet) => bullet.life > 0)
      .slice(0, this.mobile ? 48 : 100);
    const active = new Set(visible);
    for (const [bullet, flight] of this.flights) {
      if (active.has(bullet)) continue;
      if (flight.points.length > 1 && [3, 4, 6].includes(flight.weapon)) {
        flight.retired = now;
        this.retired.push(flight);
      }
      this.flights.delete(bullet);
    }
    this.retired = this.retired
      .filter((flight) => now - flight.retired! < TRAIL_LIFE[flight.weapon])
      .slice(-24);
    const trailLimit = Math.floor(
      (this.mobile || this.quality === 'performance'
        ? 72
        : this.quality === 'cinematic'
          ? 360
          : 240) * Math.max(0, Math.min(1, effectScale)),
    );
    for (const bullet of visible) {
      const weapon =
        Number.isInteger(bullet.weapon) &&
        bullet.weapon! >= 0 &&
        bullet.weapon! < 7
          ? bullet.weapon!
          : 0;
      let flight = this.flights.get(bullet);
      if (!flight) {
        const sequence = this.shotSequence++;
        flight = {
          weapon,
          enemy: bullet.enemy,
          born: now,
          points: [],
          // Tracer ammunition is mixed into a machine-gun belt. Selection is
          // stable for the life of a shot and never depends on render timing.
          tracer: weapon !== 1 || sequence % 4 === 0,
          seed: sequence % 1024,
        };
        this.flights.set(bullet, flight);
      }
      const position = worldPosition(
        bullet.x,
        bullet.y,
        (bullet.height ?? 18.5) * 0.1,
      );
      const previous = flight.points.at(-1);
      if (
        !previous ||
        (now > previous.time &&
          Vector3.DistanceSquared(previous.position, position) > 0.0001)
      ) {
        flight.points.push({ position, time: now });
        if (flight.points.length > (this.mobile ? 12 : 28))
          flight.points.shift();
      }
      const yaw = heading(Math.atan2(bullet.vy, bullet.vx)),
        age = now - flight.born;
      const body =
        bullet.enemy && weapon === 0 ? this.enemyShell : this.bodies[weapon];
      body.add(
        position,
        1,
        1,
        weapon === 5 ? 1.45 : 1,
        yaw,
        weapon === 4 ? age * 9 : weapon === 5 ? age * 3 : 0,
        1,
        -Math.atan2(
          bullet.verticalVelocity ?? 0,
          Math.hypot(bullet.vx, bullet.vy),
        ),
      );
      this.bodyCount++;
      if (weapon === 3) this.core.add(position, 1, 1, 2.4, yaw);
      if (weapon === 6) {
        const length = Math.hypot(bullet.vx, bullet.vy) || 1;
        const direction = new Vector3(
          bullet.vx / length,
          0,
          bullet.vy / length,
        );
        this.rocketNose.add(position.add(direction.scale(0.75)), 1, 1, 1, yaw);
        this.flame.add(
          position.subtract(direction.scale(0.91)),
          0.85,
          0.85,
          0.88 + Math.sin(age * 28 + flight.seed) * 0.1,
          yaw + Math.PI,
        );
      }
      this.drawTrail(flight, now, trailLimit);
    }
    for (const flight of this.retired) this.drawTrail(flight, now, trailLimit);
    for (const batch of this.batches) batch.flush();
  }
  private drawTrail(flight: Flight, now: number, limit: number) {
    const weapon = flight.weapon,
      points = flight.points;
    if (!flight.tracer) return;
    const batch =
      flight.enemy && weapon === 0 ? this.enemyTrail : this.trails[weapon];
    // AP/MG tracer is a compact exposure streak behind the actual round. It
    // must never bridge an entire low-FPS movement segment like a laser beam.
    let remaining =
      weapon === 0
        ? 0.95
        : weapon === 1
          ? 0.42
          : weapon === 2
            ? 0.16
            : Infinity;
    for (let i = points.length - 1; i > 0 && this.trailCount < limit; i--) {
      const current = points[i],
        previous = points[i - 1];
      const fade = 1 - (now - current.time) / TRAIL_LIFE[weapon];
      if (fade <= 0) continue;
      const direction = current.position.subtract(previous.position),
        length = direction.length();
      if (length < 0.001) continue;
      const yaw = heading(Math.atan2(direction.z, direction.x));
      const center = Vector3.Center(current.position, previous.position);
      if (weapon === 6) {
        // Sample by distance as well as time so a dropped frame cannot tear
        // gaps in the exhaust. Old smoke drifts away from the saved flight path.
        const samples = Math.max(1, Math.min(12, Math.ceil(length / 0.45)));
        for (
          let sample = samples - 1;
          sample >= 0 && this.trailCount < limit;
          sample--
        ) {
          const t = (sample + 0.5) / samples,
            born = previous.time + (current.time - previous.time) * t,
            age = now - born,
            life = 1 - age / TRAIL_LIFE[6];
          if (life <= 0) continue;
          const smoke = Vector3.Lerp(previous.position, current.position, t),
            expansion = Math.min(1, age / TRAIL_LIFE[6]),
            turbulence = Math.sin(born * 41 + flight.seed * 2.3),
            size = 0.2 + expansion * 0.95;
          smoke.subtractInPlace(direction.scale(0.56 / length));
          smoke.x += age * 0.18 + turbulence * expansion * 0.06;
          smoke.y += age * 0.22;
          smoke.z -= age * 0.08;
          batch.add(
            smoke,
            size,
            size * (0.82 + 0.12 * turbulence),
            size,
            0,
            0,
            life * life * 0.75,
          );
          this.trailCount++;
        }
        continue;
      } else if (weapon === 5) {
        const size = 0.48 + (1 - fade) * 0.65;
        batch.add(center, size, size, size, yaw, 0, fade);
      } else if (weapon === 4) {
        const size = 0.06 + (1 - fade) * 0.1;
        center.y += (1 - fade) * 0.08;
        batch.add(center, size, size, size, yaw, 0, fade * 0.55);
      } else {
        const width =
          (weapon === 3
            ? 0.12
            : weapon === 0
              ? 0.065
              : weapon === 2
                ? 0.018
                : 0.028) * fade;
        const visibleLength = Math.min(length, remaining);
        if (visibleLength <= 0) break;
        center
          .copyFrom(current.position)
          .subtractInPlace(direction.scale(visibleLength / length / 2));
        batch.add(center, width, width, visibleLength, yaw, 0, fade);
        remaining -= visibleLength;
      }
      this.trailCount++;
    }
  }
  dispose() {
    this.flights.clear();
    this.retired = [];
    for (const batch of this.batches) batch.mesh.dispose();
    for (const material of this.materials) material.dispose();
    this.batches = [];
    this.materials = [];
  }
}
