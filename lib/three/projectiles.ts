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
const TRAIL_LIFE = [0.11, 0.065, 0.055, 0.24, 0.3, 0.18, 0.48];
type Sample = { position: Vector3; time: number };
type Flight = {
  weapon: number;
  enemy: boolean;
  born: number;
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
  ) {
    if (this.count >= this.capacity) return;
    this.scale.set(x, y, z);
    Quaternion.RotationYawPitchRollToRef(yaw, 0, roll, this.rotation);
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
      axial('shell-ap-brass', 0.32, 1.15, 0.13),
      axial('machinegun-hot-needle', 0.12, 1.05, 0.045),
      sphere('shotgun-tungsten-pellet', 0.3),
      axial('railgun-violet-lance', 0.19, 2.7, 0.035, 4),
      MeshBuilder.CreateIcoSphere(
        'grenade-spinning-core',
        { radius: 0.34, subdivisions: 1 },
        scene,
      ),
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
    const metal = pbr(scene, 'rocket-titanium', '#c1c7bd', 0.45, 0.6);
    this.materials.push(metal);
    this.bodies = bodyMeshes.map((mesh, i) =>
      batch(
        mesh,
        i === 6
          ? metal
          : glow(
              'projectile-color-' + i,
              COLORS[i],
              i === 1 || i === 3 ? 2.3 : 1.3,
            ),
      ),
    );
    this.trails = COLORS.map((color, i) => {
      const mesh =
        i === 6
          ? sphere('rocket-smoke-trail', 1)
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
        glow(
          'trail-color-' + i,
          i === 6 ? '#a7b0aa' : color,
          i === 6 ? 0.6 : 1.7,
          i === 6 ? 0.3 : 0.7,
        ),
        360,
      );
    });
    this.core = batch(
      axial('projectile-white-core', 0.07, 1),
      glow('projectile-core-white', '#ffffff', 2.7),
    );
    this.flame = batch(
      axial('rocket-tapered-exhaust', 0.24, 1, 0.015),
      glow('rocket-orange-exhaust', '#ffb04c', 2.4, 0.8),
    );
    this.rocketNose = batch(
      axial('rocket-red-nose', 0.33, 0.45, 0),
      glow('rocket-nose-red', '#e9502c', 1),
    );
    this.enemyShell = batch(
      axial('enemy-red-shell', 0.26, 1, 0.08),
      glow('hostile-tracer-red', '#ff5b3f', 2),
    );
    this.enemyTrail = batch(
      MeshBuilder.CreateBox('hostile-red-trail', { size: 1 }, scene),
      glow('hostile-trail-red', '#ff604b', 1.5, 0.6),
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
        flight = { weapon, enemy: bullet.enemy, born: now, points: [] };
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
        if (flight.points.length > (this.mobile ? 9 : 16))
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
      );
      this.bodyCount++;
      if (weapon === 0 || weapon === 1 || weapon === 3)
        this.core.add(position, 1, 1, weapon === 3 ? 2.4 : 0.65, yaw);
      if (weapon === 6) {
        const length = Math.hypot(bullet.vx, bullet.vy) || 1;
        const direction = new Vector3(
          bullet.vx / length,
          0,
          bullet.vy / length,
        );
        this.rocketNose.add(position.add(direction.scale(0.75)), 1, 1, 1, yaw);
        this.flame.add(
          position.subtract(direction.scale(1.05)),
          1,
          1,
          1.2 + Math.sin(age * 28) * 0.14,
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
    const batch =
      flight.enemy && weapon === 0 ? this.enemyTrail : this.trails[weapon];
    for (let i = points.length - 1; i > 0 && this.trailCount < limit; i--) {
      const current = points[i],
        previous = points[i - 1];
      const fade = 1 - (now - previous.time) / TRAIL_LIFE[weapon];
      if (fade <= 0) continue;
      const direction = current.position.subtract(previous.position),
        length = direction.length();
      if (length < 0.001) continue;
      const yaw = heading(Math.atan2(direction.z, direction.x));
      const center = Vector3.Center(current.position, previous.position);
      if (weapon === 6) {
        const size = 0.28 + (1 - fade) * 0.95;
        center.y += (1 - fade) * 0.28;
        batch.add(center, size, size, size, 0, 0, fade * 0.8);
      } else if (weapon === 5) {
        const size = 0.48 + (1 - fade) * 0.65;
        batch.add(center, size, size, size, yaw, 0, fade);
      } else if (weapon === 4) {
        const size = 0.12 + fade * 0.12;
        batch.add(center, size, size, size, yaw, (now - flight.born) * 3, fade);
      } else {
        const width =
          (weapon === 3
            ? 0.12
            : weapon === 0
              ? 0.13
              : weapon === 2
                ? 0.045
                : 0.055) * fade;
        batch.add(center, width, width, length, yaw, 0, fade);
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
