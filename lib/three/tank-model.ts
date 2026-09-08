import {
  Matrix,
  Mesh,
  MeshBuilder,
  Scene,
  TransformNode,
  Vector3,
  VertexData,
  type Material,
} from './babylon';
import { pbr, emissive, type Materials } from './materials';
import { progression, killsForLevel } from '../progression';
export type TankModel = {
  evolutionLevel: number;
  root: TransformNode;
  body: TransformNode;
  turret: TransformNode;
  barrel: TransformNode;
  flash: Mesh;
  shield: Mesh;
  leftTrack: Mesh;
  rightTrack: Mesh;
  meshes: Mesh[];
  dispose: () => void;
};
export function box(
  scene: Scene,
  name: string,
  size: number[],
  at: number[],
  material: Material,
  parent?: TransformNode,
) {
  const m = MeshBuilder.CreateBox(
    name,
    { width: size[0], height: size[1], depth: size[2] },
    scene,
  );
  m.position.set(at[0], at[1], at[2]);
  m.material = material;
  if (parent) m.parent = parent;
  m.isPickable = false;
  m.receiveShadows = true;
  return m;
}
function cylinder(
  scene: Scene,
  name: string,
  radius: number,
  height: number,
  at: number[],
  material: Material,
  parent: TransformNode,
  rotationZ = 0,
  tessellation = 16,
) {
  const m = MeshBuilder.CreateCylinder(
    name,
    { diameter: radius * 2, height, tessellation },
    scene,
  );
  m.position.set(...(at as [number, number, number]));
  m.material = material;
  m.parent = parent;
  m.rotation.z = rotationZ;
  m.isPickable = false;
  return m;
}
/** Revolve a closed section around +Z, including real inner walls and shoulders. */
export function turnedPart(
  scene: Scene,
  name: string,
  section: [number, number][],
  material: Material,
  parent: TransformNode,
  segments = 16,
) {
  const positions: number[] = [],
    normals: number[] = [],
    uvs: number[] = [],
    colors: number[] = [],
    indices: number[] = [];
  let distance = 0;
  for (let edge = 0; edge < section.length; edge++) {
    const [z0, r0] = section[edge],
      [z1, r1] = section[(edge + 1) % section.length],
      length = Math.hypot(z1 - z0, r1 - r0);
    if (length < 1e-6) continue;
    const start = positions.length / 3,
      radial = (z1 - z0) / length,
      axial = (r0 - r1) / length;
    for (let i = 0; i <= segments; i++) {
      const a = (i / segments) * Math.PI * 2,
        c = Math.cos(a),
        s = Math.sin(a);
      for (const [z, radius, v] of [
        [z0, r0, distance],
        [z1, r1, distance + length],
      ]) {
        positions.push(c * radius, s * radius, z);
        normals.push(c * radial, s * radial, axial);
        uvs.push((a * Math.max(r0, r1)) / 2, v / 2);
        // Subtle structural shading; the inner bore receives little sky light.
        const shade = radial < -0.5 ? 0.52 : 0.94 + s * 0.06;
        colors.push(shade, shade, shade, 1);
      }
      if (i < segments) {
        const n = start + i * 2;
        if (scene.useRightHandedSystem)
          indices.push(n, n + 2, n + 1, n + 1, n + 2, n + 3);
        else indices.push(n, n + 1, n + 2, n + 1, n + 3, n + 2);
      }
    }
    distance += length;
  }
  const mesh = new Mesh(name, scene),
    data = new VertexData();
  Object.assign(data, { positions, normals, indices, uvs, colors });
  data.applyToMesh(mesh);
  mesh.material = material;
  mesh.parent = parent;
  mesh.isPickable = false;
  mesh.receiveShadows = true;
  return mesh;
}
export function armoredHull(
  scene: Scene,
  name: string,
  width: number,
  length: number,
  low: number,
  high: number,
  parent: TransformNode,
  material: Material,
) {
  const mesh = new Mesh(name, scene);
  const w = width / 2,
    l = length / 2;
  // Chamfer the corner plates instead of stretching a box into a wedge. The
  // turret keeps its broad front cheeks, while the hull has a long glacis.
  const turret = name.includes('turret') || name.includes('mantlet');
  const footprint = [
    [-0.69, -1],
    [0.69, -1],
    [1, -0.7],
    [1, 0.58],
    [0.66, 1],
    [-0.66, 1],
    [-1, 0.58],
    [-1, -0.7],
  ];
  const roof = turret
    ? [
        [-0.59, -0.9],
        [0.59, -0.9],
        [0.77, -0.62],
        [0.75, 0.42],
        [0.48, 0.75],
        [-0.48, 0.75],
        [-0.75, 0.42],
        [-0.77, -0.62],
      ]
    : [
        [-0.62, -0.88],
        [0.62, -0.88],
        [0.83, -0.68],
        [0.76, 0.35],
        [0.58, 0.6],
        [-0.58, 0.6],
        [-0.76, 0.35],
        [-0.83, -0.68],
      ];
  // A narrow belly, broad shoulder and beveled roof produce a lower glacis and
  // an upper glacis. The turret has an undercut below its main armor cheeks.
  const rings = [
    footprint.map(([x, z]) => [
      x * w * (turret ? 0.88 : 0.8),
      low,
      z * l * 0.94,
    ]),
    footprint.map(([x, z]) => [
      x * w,
      low + (high - low) * (turret ? 0.22 : 0.38),
      z * l,
    ]),
    roof.map(([x, z]) => [
      x * w * 1.025,
      high - (high - low) * 0.07,
      z * l * 1.025,
    ]),
    roof.map(([x, z]) => [x * w, high, z * l]),
  ];
  const vertices = rings.flat();
  const faces: number[][] = [
    [0, 1, 2, 3, 4, 5, 6, 7],
    [31, 30, 29, 28, 27, 26, 25, 24],
    ...rings
      .slice(1)
      .flatMap((_, ring) =>
        footprint.map((_, i) => [
          ring * 8 + i,
          (ring + 1) * 8 + i,
          (ring + 1) * 8 + ((i + 1) % 8),
          ring * 8 + ((i + 1) % 8),
        ]),
      ),
  ];
  const positions: number[] = [],
    indices: number[] = [],
    uvs: number[] = [],
    colors: number[] = [];
  for (const face of faces) {
    const offset = positions.length / 3;
    const origin = Vector3.FromArray(vertices[face[0]]);
    const uAxis = Vector3.FromArray(vertices[face[1]])
      .subtract(origin)
      .normalize();
    const last = Vector3.FromArray(vertices[face.at(-1)!]).subtract(origin);
    const vAxis = last
      .subtract(uAxis.scale(Vector3.Dot(last, uAxis)))
      .normalize();
    for (let j = 0; j < face.length; j++) {
      const vertex = vertices[face[j]];
      positions.push(...vertex);
      // Two world units per texture repeat on every facet, including bevels.
      // Orthogonal planar axes keep paint grain and scratches undistorted.
      const at = Vector3.FromArray(vertex).subtract(origin);
      uvs.push(Vector3.Dot(at, uAxis) / 2, Vector3.Dot(at, vAxis) / 2);
      const height = (vertex[1] - low) / (high - low),
        shade = 0.8 + 0.2 * Math.sqrt(Math.max(0, height));
      colors.push(shade, shade, shade, 1);
    }
    for (let i = 1; i < face.length - 1; i++)
      indices.push(offset, offset + i, offset + i + 1);
  }
  const normals: number[] = [];
  VertexData.ComputeNormals(positions, indices, normals, {
    useRightHandedSystem: scene.useRightHandedSystem,
  });
  const data = new VertexData();
  Object.assign(data, { positions, indices, normals, uvs, colors });
  data.applyToMesh(mesh);
  mesh.material = material;
  mesh.parent = parent;
  mesh.isPickable = false;
  mesh.receiveShadows = true;
  return mesh;
}
function trackBelt(
  scene: Scene,
  material: Material,
  parent: TransformNode,
  x: number,
  length: number,
  lowDetail: boolean,
) {
  // A hollow capsule follows the sprocket/idler, leaving the suspension open.
  const segments = lowDetail ? 6 : 12;
  const perimeter: [number, number][] = [];
  for (const end of [1, -1])
    for (let i = 0; i <= segments; i++) {
      const a = (i / segments) * Math.PI;
      perimeter.push([end * Math.cos(a), end * Math.sin(a)]);
    }
  const positions: number[] = [],
    indices: number[] = [],
    uvs: number[] = [];
  const vertices = (index: number, radius: number, side: number) => {
    const [y, z] = perimeter[index];
    const end = index <= segments ? 1 : -1;
    return [x + side * 0.39, 0.64 + y * radius, end * length + z * radius];
  };
  const quad = (points: number[][]) => {
    const start = positions.length / 3;
    for (const point of points) positions.push(...point);
    uvs.push(0, 0, 1, 0, 1, 1, 0, 1);
    indices.push(start, start + 1, start + 2, start, start + 2, start + 3);
  };
  for (let i = 0; i < perimeter.length; i++) {
    const j = (i + 1) % perimeter.length;
    quad([
      vertices(i, 0.5, -1),
      vertices(j, 0.5, -1),
      vertices(j, 0.5, 1),
      vertices(i, 0.5, 1),
    ]);
    quad([
      vertices(i, 0.42, 1),
      vertices(j, 0.42, 1),
      vertices(j, 0.42, -1),
      vertices(i, 0.42, -1),
    ]);
    for (const side of [-1, 1]) {
      const face = [
        vertices(i, 0.42, side),
        vertices(j, 0.42, side),
        vertices(j, 0.5, side),
        vertices(i, 0.5, side),
      ];
      quad(side === 1 ? face.reverse() : face);
    }
  }
  const mesh = new Mesh('continuous-rounded-track-belt', scene);
  const data = new VertexData(),
    normals: number[] = [];
  VertexData.ComputeNormals(positions, indices, normals, {
    useRightHandedSystem: scene.useRightHandedSystem,
  });
  Object.assign(data, { positions, indices, normals, uvs });
  data.applyToMesh(mesh);
  mesh.material = material;
  mesh.parent = parent;
  mesh.isPickable = false;
  mesh.receiveShadows = true;
  return mesh;
}
export function mergeByMaterial(node: TransformNode) {
  const buckets = new Map<Material, Mesh[]>();
  for (const mesh of node.getChildMeshes(true)) {
    if (!(mesh instanceof Mesh) || !mesh.material) continue;
    // Merge custom shaded sections and stock details without dropping colors.
    if (!mesh.isVerticesDataPresent('color'))
      mesh.setVerticesData(
        'color',
        new Float32Array(mesh.getTotalVertices() * 4).fill(1),
      );
    const list = buckets.get(mesh.material) || [];
    list.push(mesh);
    buckets.set(mesh.material, list);
  }
  const merged: Mesh[] = [];
  for (const meshes of buckets.values()) {
    if (meshes.length === 1) {
      merged.push(meshes[0]);
      continue;
    }
    const m = Mesh.MergeMeshes(meshes, true, true, undefined, false, false);
    if (m) {
      m.bakeTransformIntoVertices(Matrix.Invert(node.computeWorldMatrix(true)));
      m.parent = node;
      m.isPickable = false;
      m.receiveShadows = true;
      merged.push(m);
    }
  }
  return merged;
}
export function buildTank(
  scene: Scene,
  mats: Materials,
  chassis = 1,
  enemy = false,
  boss = false,
  level = 1,
  lowDetail = false,
): TankModel {
  const root = new TransformNode('tank-root', scene),
    body = new TransformNode('hull-heading', scene),
    turret = new TransformNode('independent-turret', scene),
    barrel = new TransformNode('barrel-recoil', scene);
  body.parent = root;
  turret.parent = root;
  barrel.parent = turret;
  turret.position.y = 1.62;
  const growth = enemy ? null : progression(killsForLevel(level));
  const stage = growth?.stage ?? 2;
  const owned: Material[] = [];
  const grownArmor = growth
    ? pbr(
        scene,
        'evolution-armor-' + growth.level,
        growth.evolution.color,
        0.18 + stage * 0.012,
        0.78 - stage * 0.014,
      )
    : null;
  if (grownArmor) {
    grownArmor.albedoTexture = mats.armor.albedoTexture;
    grownArmor.bumpTexture = mats.armor.bumpTexture;
    grownArmor.metallicTexture = mats.armor.metallicTexture;
    grownArmor.useRoughnessFromMetallicTextureAlpha =
      mats.armor.useRoughnessFromMetallicTextureAlpha;
    grownArmor.useRoughnessFromMetallicTextureGreen =
      mats.armor.useRoughnessFromMetallicTextureGreen;
    grownArmor.useMetallnessFromMetallicTextureBlue =
      mats.armor.useMetallnessFromMetallicTextureBlue;
    grownArmor.useAmbientOcclusionFromMetallicTextureRed =
      mats.armor.useAmbientOcclusionFromMetallicTextureRed;
    grownArmor.invertNormalMapX = mats.armor.invertNormalMapX;
    grownArmor.invertNormalMapY = mats.armor.invertNormalMapY;
    owned.push(grownArmor);
  }
  const accent = growth
    ? emissive(
        scene,
        'evolution-accent-' + growth.level,
        growth.evolution.accent,
        stage >= 4 ? 0.35 : 0.12,
      )
    : mats.marking;
  if (growth) owned.push(accent);
  const armor = boss ? mats.heavy : enemy ? mats.enemy : grownArmor!;
  const wide = chassis === 2 ? 1.14 : chassis === 0 ? 0.87 : 1;
  const long = chassis === 0 ? 0.9 : 1;
  armoredHull(
    scene,
    'sloped-cast-hull',
    3.4 * wide,
    5.45 * long,
    0.65,
    1.75,
    body,
    armor,
  );
  box(
    scene,
    'underside',
    [2.7 * wide, 0.6, 4.65 * long],
    [0, 0.55, 0],
    mats.steel,
    body,
  );
  box(
    scene,
    'engine-deck',
    [2.7 * wide, 0.1, 1.7],
    [0, 1.77, -1.6 * long],
    mats.steel,
    body,
  );
  for (let i = 0; i < 11; i++)
    box(
      scene,
      'cooling-louver',
      [2.55 * wide, 0.075, 0.045],
      [0, 1.85, -2.27 * long + i * 0.135],
      armor,
      body,
    );
  for (const side of [-1, 1]) {
    trackBelt(
      scene,
      mats.rubber,
      body,
      side * 1.67 * wide,
      2.45 * long,
      lowDetail,
    );
    // Thin fenders sit above the running gear instead of a solid rubber box.
    box(
      scene,
      'track-fender',
      [0.87, 0.085, 5.05 * long],
      [side * 1.66 * wide, 1.24, 0],
      armor,
      body,
    );
    // Six non-intersecting wheels remain in both quality levels. Put their
    // axles inside the track belt; lower tessellation supplies the mobile LOD.
    const axleX = side * 1.67 * wide;
    for (let i = 0; i < 6; i++) {
      const z = (-1.96 + i * 0.784) * long,
        radius = 0.37 * long;
      const tire = turnedPart(
        scene,
        'beveled-road-wheel-tire',
        [
          [-0.24, radius * 0.9],
          [-0.18, radius],
          [0.2, radius],
          [0.27, radius * 0.89],
          [0.27, radius * 0.74],
          [-0.24, radius * 0.74],
        ],
        mats.rubber,
        body,
        lowDetail ? 8 : 16,
      );
      const disc = turnedPart(
        scene,
        'dished-road-wheel-disc',
        [
          [0.12, radius * 0.74],
          [0.25, radius * 0.78],
          [0.28, radius * 0.68],
          [0.2, radius * 0.34],
          [0.28, radius * 0.26],
          [0.12, radius * 0.26],
        ],
        armor,
        body,
        lowDetail ? 8 : 16,
      );
      for (const part of [tire, disc]) {
        part.position.set(axleX, 0.61, z);
        part.rotation.y = (side * Math.PI) / 2;
      }
      cylinder(
        scene,
        'road-wheel-axle-cap',
        radius * 0.25,
        0.095,
        [axleX + side * 0.28, 0.61, z],
        mats.steel,
        body,
        Math.PI / 2,
        lowDetail ? 6 : 12,
      );
      if (!lowDetail) {
        // Swing arms meet the inboard wheel hubs, instead of floating discs.
        const arm = box(
          scene,
          'suspension-swing-arm',
          [0.13, 0.15, 0.52],
          [axleX - side * 0.2, 0.69, z - 0.16],
          mats.steel,
          body,
        );
        arm.rotation.x = -0.35;
        for (let bolt = 0; bolt < 5; bolt++) {
          const a = (bolt * Math.PI * 2) / 5;
          cylinder(
            scene,
            'road-wheel-lug',
            0.027,
            0.026,
            [
              axleX + side * 0.27,
              0.61 + Math.cos(a) * radius * 0.49,
              z + Math.sin(a) * radius * 0.49,
            ],
            mats.steel,
            body,
            Math.PI / 2,
            6,
          );
        }
      }
    }
    for (const end of [-1, 1]) {
      cylinder(
        scene,
        end === 1 ? 'front-idler-wheel' : 'drive-sprocket',
        0.37,
        0.2,
        [axleX, 0.64, end * 2.45 * long],
        mats.steel,
        body,
        Math.PI / 2,
      );
      cylinder(
        scene,
        'idler-bearing-cap',
        0.16,
        0.26,
        [axleX + side * 0.12, 0.64, end * 2.45 * long],
        armor,
        body,
        Math.PI / 2,
      );
      if (!lowDetail && end === -1)
        for (let tooth = 0; tooth < 10; tooth++) {
          const a = (tooth * Math.PI) / 5;
          const cog = box(
            scene,
            'sprocket-tooth',
            [0.13, 0.11, 0.09],
            [
              axleX,
              0.64 + Math.cos(a) * 0.37,
              end * 2.45 * long + Math.sin(a) * 0.37,
            ],
            mats.steel,
            body,
          );
          cog.rotation.x = a;
        }
    }
    for (let i = 0; i < (lowDetail ? 10 : 22); i++) {
      const z = (-2.52 + i * (lowDetail ? 0.56 : 0.24)) * long;
      box(
        scene,
        'tread-shoe',
        [0.82, 0.08, 0.18],
        [side * 1.67 * wide, 0.14, z],
        mats.steel,
        body,
      );
      box(
        scene,
        'tread-shoe',
        [0.82, 0.08, 0.18],
        [side * 1.67 * wide, 1.13, z],
        mats.steel,
        body,
      );
    }
    for (let i = 0; i < (stage >= 1 ? 5 : 0); i++) {
      const panel = box(
        scene,
        'side-skirt',
        [0.12, 0.67, 0.85],
        [side * 2.08 * wide, 1.38, (-1.92 + i * 0.94) * long],
        armor,
        body,
      );
      panel.rotation.z = side * 0.07;
      box(
        scene,
        'skirt-top-hinge',
        [0.16, 0.075, 0.29],
        [side * 2.08 * wide, 1.75, (-1.92 + i * 0.94) * long],
        mats.steel,
        body,
      );
      box(
        scene,
        'skirt-fastener',
        [0.035, 0.06, 0.09],
        [side * 2.15 * wide, 1.62, (-1.92 + i * 0.94) * long],
        mats.edges,
        body,
      );
    }
    for (let i = 0; i < (stage >= 2 ? 3 : 0); i++) {
      const plateZ = (1.64 + i * 0.33) * long;
      const plate = box(
        scene,
        'frontal-reactive-armor',
        [0.73 * wide, 0.16, 0.47],
        [
          side * 0.74 * wide,
          1.805 - ((plateZ - 1.635 * long) * 0.626) / long,
          plateZ,
        ],
        armor,
        body,
      );
      plate.rotation.x = Math.atan(0.626 / long);
    }
    box(
      scene,
      'headlight-mount',
      [0.35, 0.25, 0.2],
      [side * 1.34 * wide, 1.38, 2.23 * long],
      mats.steel,
      body,
    );
    box(
      scene,
      'headlight-lens',
      [0.24, 0.15, 0.025],
      [side * 1.34 * wide, 1.4, 2.345 * long],
      enemy ? mats.red : mats.lamp,
      body,
    );
    for (const edge of [-1, 1])
      box(
        scene,
        'headlight-protective-guard',
        [0.045, 0.34, 0.12],
        [side * 1.34 * wide + edge * 0.19, 1.44, 2.36 * long],
        armor,
        body,
      );
    box(
      scene,
      'headlight-guard-bridge',
      [0.42, 0.045, 0.12],
      [side * 1.34 * wide, 1.62, 2.36 * long],
      armor,
      body,
    );
    box(
      scene,
      'rear-brake-light',
      [0.25, 0.15, 0.05],
      [side * 1.3 * wide, 1.35, -2.47 * long],
      mats.red,
      body,
    );
    const exhaust = cylinder(
      scene,
      'exhaust-pipe',
      0.16,
      0.65,
      [side * 1.28, 1.25, -2.55 * long],
      mats.steel,
      body,
      Math.PI / 2,
    );
    exhaust.rotation.x = Math.PI / 2;
  }
  cylinder(scene, 'turret-ring', 1.19, 0.22, [0, 0, 0], mats.steel, turret);
  armoredHull(
    scene,
    'angular-turret',
    2.5 * wide,
    2.85,
    0.06,
    0.91,
    turret,
    armor,
  );
  if (stage >= 1) {
    box(
      scene,
      'rear-turret-basket',
      [2.05 * wide, 0.055, 0.7],
      [0, 0.16, -1.65],
      mats.steel,
      turret,
    );
    for (let i = 0; i < 6; i++)
      box(
        scene,
        'basket-slat',
        [0.045, 0.42, 0.045],
        [(-0.88 + i * 0.35) * wide, 0.37, -1.98],
        armor,
        turret,
      );
    const basketRail = MeshBuilder.CreateTube(
      'open-stowage-basket-rail',
      {
        path: [
          new Vector3(-1 * wide, 0.59, -1.31),
          new Vector3(-1 * wide, 0.59, -1.98),
          new Vector3(1 * wide, 0.59, -1.98),
          new Vector3(1 * wide, 0.59, -1.31),
        ],
        radius: 0.035,
        tessellation: 6,
      },
      scene,
    );
    basketRail.material = mats.steel;
    basketRail.parent = turret;
    basketRail.isPickable = false;
  }
  cylinder(
    scene,
    'commander-cupola',
    0.4,
    0.16,
    [-0.5, 0.98, -0.2],
    mats.steel,
    turret,
  );
  cylinder(scene, 'hatch-cover', 0.35, 0.1, [-0.5, 1.09, -0.2], armor, turret);
  box(
    scene,
    'hatch-hinge',
    [0.29, 0.11, 0.12],
    [-0.5, 1.14, -0.55],
    mats.steel,
    turret,
  );
  for (const x of [-0.64, -0.36])
    box(
      scene,
      'hatch-handle-foot',
      [0.035, 0.075, 0.035],
      [x, 1.18, -0.15],
      mats.steel,
      turret,
    );
  box(
    scene,
    'hatch-grab-handle',
    [0.315, 0.035, 0.035],
    [-0.5, 1.22, -0.15],
    mats.steel,
    turret,
  );
  for (const angle of [-0.9, 0, 0.9]) {
    const slit = box(
      scene,
      'cupola-vision-block',
      [0.18, 0.085, 0.055],
      [-0.5 + Math.sin(angle) * 0.38, 1, -0.2 + Math.cos(angle) * 0.38],
      mats.glass,
      turret,
    );
    slit.rotation.y = angle;
  }
  box(
    scene,
    'gunner-optic',
    [0.46, 0.23, 0.38],
    [0.52, 1.01, 0.2],
    mats.steel,
    turret,
  );
  box(
    scene,
    'optic-lens',
    [0.32, 0.12, 0.03],
    [0.52, 1.03, 0.41],
    enemy ? mats.red : mats.glass,
    turret,
  );
  const mantlet = armoredHull(
    scene,
    'cast-gun-mantlet',
    1.03,
    0.79,
    0.13,
    0.86,
    turret,
    armor,
  );
  mantlet.position.z = 1.12;
  const trunnion = cylinder(
    scene,
    'mantlet-trunnion',
    0.31,
    0.25,
    [0, 0.5, 1.48],
    mats.steel,
    turret,
  );
  trunnion.rotation.x = Math.PI / 2;
  const coax = cylinder(
    scene,
    'coaxial-gun-recess',
    0.085,
    0.035,
    [0.4, 0.45, 1.5],
    mats.rubber,
    turret,
  );
  coax.rotation.x = Math.PI / 2;
  const caliber = chassis === 2 ? 1.16 : 1;
  const gun = turnedPart(
    scene,
    'tapered-cannon-open-bore',
    [
      [1.36, 0.18],
      [2.76, 0.15],
      [3.9, 0.125],
      [4.06, 0.14],
      [4.06, 0.095],
      [3.74, 0.095],
      [1.36, 0.115],
    ].map<[number, number]>(([z, radius]) => [z, radius * caliber]),
    mats.steel,
    barrel,
    lowDetail ? 12 : 24,
  );
  gun.position.y = 0.5;
  const sleeve = turnedPart(
    scene,
    'thermal-jacket-and-fume-extractor',
    [
      [1.46, 0.205],
      [1.53, 0.225],
      [2.3, 0.225],
      [2.37, 0.27],
      [2.65, 0.27],
      [2.74, 0.19],
      [2.86, 0.19],
      [2.86, 0.16],
      [1.46, 0.18],
    ],
    armor,
    barrel,
    lowDetail ? 10 : 20,
  );
  sleeve.position.y = 0.5;
  for (const x of stage >= 2 ? [-0.95, 0.95] : []) {
    for (let i = 0; i < 3; i++) {
      const s = cylinder(
        scene,
        'smoke-launcher',
        0.1,
        0.32,
        [x, 0.62, 0.6 - i * 0.24],
        mats.steel,
        turret,
        Math.PI / 3,
      );
      s.rotation.x = 0.7;
    }
  }
  const antenna = cylinder(
    scene,
    'radio-antenna',
    0.018,
    2.1,
    [0.92, 1.66, -0.91],
    mats.steel,
    turret,
  );
  antenna.rotation.z = -0.1;
  box(
    scene,
    'recognition-stripe',
    [0.31, 0.025, 0.8],
    [-0.5, 0.925, 0.43],
    mats.marking,
    turret,
  );
  box(
    scene,
    'recognition-stripe',
    [0.09, 0.025, 0.8],
    [-0.27, 0.926, 0.43],
    mats.marking,
    turret,
  );
  if (boss) {
    for (const x of [-1.3, 1.3]) {
      box(
        scene,
        'siege-rocket-bank',
        [0.7, 0.7, 1.55],
        [x, 0.65, -0.2],
        mats.heavy,
        turret,
      );
      for (let j = 0; j < 4; j++) {
        const missile = cylinder(
          scene,
          'launcher-tube',
          0.11,
          0.1,
          [x + ((j % 2) - 0.5) * 0.25, 0.55 + Math.floor(j / 2) * 0.24, 0.62],
          mats.red,
          turret,
        );
        missile.rotation.x = Math.PI / 2;
      }
    }
  }
  if (growth) {
    // Geometry evolves without moving the gun's muzzle or changing the physics footprint.
    for (const side of [-1, 1]) {
      for (let i = 0; i < Math.min(5, ((growth.level - 1) % 5) + 1); i++)
        box(
          scene,
          'rank-chevron',
          [0.2, 0.06, 0.28],
          [side * (0.65 + i * 0.23), 1.83, -1.1],
          accent,
          body,
        );
      if (stage >= 1) {
        box(
          scene,
          'evolution-shoulder',
          [0.27, 0.4, 1.8],
          [side * 1.7, 1.72, -0.2],
          armor,
          body,
        );
        box(
          scene,
          'evolution-stripe',
          [0.06, 0.07, 2.2],
          [side * 1.9, 1.77, -0.4],
          accent,
          body,
        );
      }
      if (stage >= 2)
        for (let i = 0; i < 3; i++) {
          const cheek = box(
            scene,
            'evolution-turret-cheek',
            [0.32, 0.5, 0.63],
            [side * 1.27, 0.55, 0.75 - i * 0.69],
            armor,
            turret,
          );
          cheek.rotation.z = side * 0.2;
        }
      if (stage >= 3) {
        for (let i = 0; i < 4; i++)
          box(
            scene,
            'evolution-layered-skirt',
            [0.22, 0.55, 0.95],
            [side * 2.17, 1.46, -1.65 + i * 1.02],
            armor,
            body,
          );
        const plow = box(
          scene,
          'evolution-front-wedge',
          [1.45, 0.52, 0.24],
          [side * 0.85, 1.08, 2.65],
          mats.heavy,
          body,
        );
        plow.rotation.x = -0.3;
        box(
          scene,
          'evolution-cannon-jacket',
          [0.58, 0.32, 1.15],
          [side * 0.25, 0.5, 2.12],
          armor,
          barrel,
        );
      }
      if (stage >= 4) {
        box(
          scene,
          'evolution-cooling-pod',
          [0.5, 0.55, 1.35],
          [side * 1.36, 0.6, -1.4],
          mats.heavy,
          turret,
        );
        for (let i = 0; i < 4; i++)
          box(
            scene,
            'evolution-active-defense',
            [0.14, 0.23, 0.17],
            [side * 1.62, 0.82, -1.8 + i * 0.28],
            accent,
            turret,
          );
        box(
          scene,
          'evolution-sensor-array',
          [0.45, 0.28, 0.7],
          [side * 0.8, 1.22, -0.68],
          armor,
          turret,
        );
      }
      if (stage >= 5) {
        const shell = box(
          scene,
          'evolution-fortress-shoulder',
          [0.56, 0.45, 1.7],
          [side * 1.55, 1.02, 0.05],
          armor,
          turret,
        );
        shell.rotation.z = side * 0.18;
        box(
          scene,
          'evolution-energy-rail',
          [0.085, 0.085, 2.3],
          [side * 0.33, 0.75, 2.3],
          accent,
          barrel,
        );
        box(
          scene,
          'evolution-reactor-conduit',
          [0.11, 0.08, 3.7],
          [side * 1.52, 1.94, -0.2],
          accent,
          body,
        );
      }
      if (stage >= 6) {
        const fin = box(
          scene,
          'evolution-crown-fin',
          [0.14, 0.82, 1.24],
          [side * 0.83, 1.28, -0.87],
          armor,
          turret,
        );
        fin.rotation.z = -side * 0.27;
        for (let i = 0; i < 3; i++)
          box(
            scene,
            'evolution-final-armor',
            [0.35, 0.22, 0.75],
            [side * 2.15, 1.9, -1.22 + i * 0.9],
            armor,
            body,
          );
      }
    }
    if (stage >= 4) {
      cylinder(
        scene,
        'evolution-radar-mast',
        0.065,
        0.55,
        [0.2, 1.32, -1.2],
        mats.steel,
        turret,
      );
      const radar = cylinder(
        scene,
        'evolution-radar',
        0.48,
        0.13,
        [0.2, 1.6, -1.2],
        armor,
        turret,
      );
      radar.rotation.z = 0.32;
    }
    if (stage >= 5) {
      cylinder(
        scene,
        'evolution-reactor-core',
        0.42,
        0.2,
        [0, 1.03, -0.55],
        accent,
        turret,
      );
      const ring = MeshBuilder.CreateTorus(
        'evolution-reactor-ring',
        { diameter: 1.25, thickness: 0.1, tessellation: 24 },
        scene,
      );
      ring.parent = turret;
      ring.position.set(0, 1.21, -0.55);
      ring.material = armor;
      ring.isPickable = false;
    }
    if (stage >= 6) {
      box(
        scene,
        'evolution-crown-center',
        [0.42, 0.38, 0.7],
        [0, 1.3, 0.3],
        armor,
        turret,
      );
      const seal = MeshBuilder.CreateTorus(
        'evolution-final-seal',
        { diameter: 1.7, thickness: 0.07, tessellation: 24 },
        scene,
      );
      seal.parent = turret;
      seal.position.set(0, 1.45, -0.55);
      seal.material = accent;
      seal.isPickable = false;
    }
  }
  // Manufactured details retain independent turret/recoil transforms and share materials.
  for (const side of [-1, 1]) {
    for (const end of [-1, 1]) {
      for (let i = 1; i < (lowDetail ? 5 : 10); i++) {
        const angle = (i / (lowDetail ? 5 : 10)) * Math.PI;
        const shoe = box(
          scene,
          'curved-track-return',
          [0.82, 0.085, 0.19],
          [
            side * 1.67 * wide,
            0.64 + 0.49 * Math.cos(angle),
            end * (2.45 * long + 0.49 * Math.sin(angle)),
          ],
          mats.steel,
          body,
        );
        shoe.rotation.x = end * angle;
      }
      const tow = MeshBuilder.CreateTorus(
        'forged-towing-eye',
        { diameter: 0.3, thickness: 0.075, tessellation: 12 },
        scene,
      );
      tow.parent = body;
      tow.position.set(side * 1.08 * wide, 0.9, end * 2.68 * long);
      tow.rotation.x = Math.PI / 2;
      tow.material = mats.steel;
      tow.isPickable = false;
    }
    for (let i = 0; i < 5; i++) {
      box(
        scene,
        'dried-mud-skirt',
        [0.035, 0.12 + (i % 3) * 0.04, 0.72],
        [side * 2.15 * wide, 1.07, (-1.9 + i * 0.94) * long],
        mats.mud,
        body,
      );
    }
    // Long wedge modules follow the turret shoulder, with a narrow expansion
    // joint between them instead of a row of disconnected rectangular blocks.
    for (const [z, length, width] of [
      [0.43, 1.22, 0.44],
      [-0.61, 0.76, 0.3],
    ]) {
      const cheek = armoredHull(
        scene,
        'spaced-turret-cheek',
        width,
        length,
        0.16,
        0.77,
        turret,
        armor,
      );
      cheek.position.set(side * 1.13 * wide, 0, z);
      cheek.rotation.z = side * 0.09;
      cheek.rotation.y = side * -0.08;
    }
    box(
      scene,
      'rear-stowage-box',
      [0.68, 0.44, 0.72],
      [side * 1.08, 1.82, -2.02 * long],
      armor,
      body,
    );
    box(
      scene,
      'stowage-lid-seam',
      [0.7, 0.032, 0.74],
      [side * 1.08, 1.99, -2.02 * long],
      mats.steel,
      body,
    );
    box(
      scene,
      'stowage-lid',
      [0.7, 0.06, 0.74],
      [side * 1.08, 2.035, -2.02 * long],
      armor,
      body,
    );
    for (let i = 0; i < 3; i++)
      box(
        scene,
        'stowage-clasp',
        [0.045, 0.06, 0.75],
        [side * 1.08 - 0.2 + i * 0.2, 2.06, -2.02 * long],
        mats.steel,
        body,
      );
    if (!lowDetail) {
      for (let i = 0; i < 9; i++)
        box(
          scene,
          'deck-weld-bead',
          [0.055, 0.025, 0.14],
          [side * 1.36 * wide, 1.71, -2 + i * 0.18],
          mats.steel,
          body,
        );
      const cable = MeshBuilder.CreateTube(
        'looped-towing-cable',
        {
          path: [
            new Vector3(side * 1.35 * wide, 1.79, 0.55),
            new Vector3(side * 1.57 * wide, 1.83, 0.4),
            new Vector3(side * 1.61 * wide, 1.83, -0.15),
            new Vector3(side * 1.61 * wide, 1.83, -1.2),
            new Vector3(side * 1.51 * wide, 1.86, -1.53),
            new Vector3(side * 1.32 * wide, 1.86, -1.61),
            new Vector3(side * 1.2 * wide, 1.83, -1.38),
            new Vector3(side * 1.23 * wide, 1.8, -0.98),
          ],
          radius: 0.038,
          tessellation: 6,
        },
        scene,
      );
      cable.material = mats.edges;
      cable.parent = body;
      cable.isPickable = false;
      cable.receiveShadows = true;
      for (const z of [-0.2, -0.95])
        box(
          scene,
          'cable-retaining-clip',
          [0.18, 0.06, 0.09],
          [side * 1.61 * wide, 1.88, z],
          mats.steel,
          body,
        );
      for (let i = 0; i < 4; i++)
        box(
          scene,
          'turret-roof-weld',
          [0.18, 0.018, 0.024],
          [side * (0.12 + i * 0.2), 0.923, -1.04],
          mats.steel,
          turret,
        );
    }
  }
  for (const z of [1.61, 2.19]) {
    const band = turnedPart(
      scene,
      'thermal-jacket-retaining-band',
      [
        [z, 0.23],
        [z + 0.045, 0.23],
        [z + 0.045, 0.22],
        [z, 0.22],
      ],
      mats.edges,
      barrel,
      lowDetail ? 10 : 16,
    );
    band.position.y = 0.5;
  }
  const bodyMeshes = mergeByMaterial(body),
    turretMeshes = mergeByMaterial(turret),
    barrelMeshes = mergeByMaterial(barrel);
  const flash = MeshBuilder.CreateSphere(
    'muzzle-flash',
    { diameter: 1, segments: 6 },
    scene,
  );
  flash.parent = barrel;
  flash.position.set(0, 0.5, 4.06);
  flash.scaling.set(0.75, 0.65, 2.2);
  flash.material = mats.white;
  flash.isPickable = false;
  flash.setEnabled(false);
  const shield = MeshBuilder.CreateSphere(
    'energy-shield',
    { diameter: 6.2, segments: 16 },
    scene,
  );
  shield.parent = root;
  shield.position.y = 1.05;
  shield.scaling.y = 0.65;
  shield.material = mats.blue;
  shield.isPickable = false;
  shield.visibility = 0.13;
  shield.setEnabled(false);
  const leftTrack = bodyMeshes[0],
    rightTrack = bodyMeshes[1] || leftTrack;
  let disposed = false;
  return {
    evolutionLevel: growth?.level ?? 0,
    root,
    body,
    turret,
    barrel,
    flash,
    shield,
    leftTrack,
    rightTrack,
    meshes: [...bodyMeshes, ...turretMeshes, ...barrelMeshes],
    dispose: () => {
      if (disposed) return;
      disposed = true;
      root.dispose(false, false);
      for (const material of owned) material.dispose(false, false);
    },
  };
}
