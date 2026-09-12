import {
  Mesh,
  MeshBuilder,
  RawTexture,
  Scene,
  ShaderMaterial,
  TransformNode,
  Vector3,
  VertexData,
} from './babylon';
import { Battle, H, W, seeded, type Wall } from '../engine';
import { pbr, type Quality } from './materials';
import { box } from './tank-model';
import { applySurface } from './surface-textures';
import { battlefieldPalette } from './battlefield-scenery';

export function natureMaterials(
  scene: Scene,
  assets: boolean,
  quality: Quality,
  biome = 'city',
) {
  const palette = battlefieldPalette(biome);
  const bark = pbr(scene, 'split-tree-bark', '#b5aa96', 0, 0.97);
  const leaves = pbr(scene, 'sunlit-olive-foliage', palette.foliage, 0, 0.94);
  const pine = pbr(scene, 'pine-needle-clusters', '#67785d', 0, 0.96);
  const stone = pbr(scene, 'weathered-ridge-stone', palette.stone, 0, 0.94);
  const soil = pbr(scene, 'overgrown-verge-soil', palette.soil, 0, 0.98);
  leaves.backFaceCulling = false;
  pine.backFaceCulling = false;
  if (assets) {
    const mobile = quality === 'performance';
    applySurface(soil, scene, 'soil', { repeat: 1, mobile });
    applySurface(stone, scene, 'rock', { repeat: 1, mobile, strength: 0.7 });
    applySurface(bark, scene, 'bark', { repeat: 2, mobile, strength: 0.8 });
    // Opaque micro-colour is shared by all folded leaves. Geometry supplies
    // canopy gaps, so alpha blending cannot sort incorrectly through smoke.
    const size = mobile ? 64 : 128,
      pixels = new Uint8Array(size * size * 4),
      random = seeded(91831);
    for (let y = 0; y < size; y++)
      for (let x = 0; x < size; x++) {
        const leaf = Math.max(
            0,
            Math.sin(x * 0.68 + Math.sin(y * 0.47)) *
              Math.cos(y * 0.9 + x * 0.21),
          ),
          shadow = 0.49 + leaf * 0.45 + random() * 0.06,
          at = (y * size + x) * 4;
        pixels[at] = Math.round(shadow * 236);
        pixels[at + 1] = Math.round(shadow * 255);
        pixels[at + 2] = Math.round(shadow * 211);
        pixels[at + 3] = 255;
      }
    const foliage = RawTexture.CreateRGBATexture(
      pixels,
      size,
      size,
      scene,
      true,
      false,
    );
    foliage.name = 'clustered-leaf-micro-colour';
    foliage.uScale = foliage.vScale = 2;
    leaves.albedoTexture = pine.albedoTexture = foliage;
  }
  return { bark, leaves, pine, stone, soil };
}
type NatureMaterials = ReturnType<typeof natureMaterials>;

function crown(
  scene: Scene,
  name: string,
  at: number[],
  scale: number[],
  seed: number,
  material: NatureMaterials['leaves'],
  parent: TransformNode,
  low: boolean,
) {
  const mesh = new Mesh(name, scene),
    vertices = new VertexData(),
    positions: number[] = [],
    normals: number[] = [],
    colors: number[] = [],
    uvs: number[] = [],
    indices: number[] = [],
    random = seeded(Math.floor(seed * 937 + 6103)),
    pine = name.startsWith('pine'),
    count = low ? 16 : pine ? 34 : 42;
  // Folded pointed leaflets are distributed around several offset sprays.
  // There is no solid sphere under them: the interleaved patches leave real
  // gaps around branches, with silhouettes stable in the game camera.
  for (let leaf = 0; leaf < count; leaf++) {
    const angle = leaf * 2.39996 + seed * 0.31,
      elevation = 0.78 - ((leaf + 0.5) / count) * 1.5,
      radius = Math.sqrt(1 - elevation * elevation) * (0.68 + random() * 0.3),
      center = new Vector3(
        Math.cos(angle) * radius,
        elevation * (pine ? 0.65 : 1),
        Math.sin(angle) * radius,
      ),
      normal = center.normalizeToNew(),
      tangent = new Vector3(
        -Math.sin(angle),
        0.18 + random() * 0.22,
        Math.cos(angle),
      ).normalize(),
      across = Vector3.Cross(normal, tangent).normalize(),
      length = (pine ? 0.3 : 0.23) + random() * (low ? 0.18 : 0.1),
      breadth = (pine ? 0.095 : 0.15) * (low ? 1.25 : 1),
      light = 0.72 + random() * 0.19 + Math.max(0, elevation) * 0.17,
      start = positions.length / 3;
    const points = [
      center.subtract(tangent.scale(length)),
      center.subtract(across.scale(breadth)),
      center.add(tangent.scale(length)),
      center.add(across.scale(breadth)),
      center.add(normal.scale(0.075)),
    ];
    for (let vertex = 0; vertex < points.length; vertex++) {
      const point = points[vertex],
        // Radial, volume-smoothed normals keep paper-thin leaves sunlit from
        // either camera side instead of displaying harsh alternating cards.
        lightingNormal = point.normalizeToNew(),
        vein = vertex === 4 ? 0.84 : vertex === 2 ? 1.05 : 1;
      positions.push(point.x, point.y, point.z);
      normals.push(lightingNormal.x, lightingNormal.y, lightingNormal.z);
      colors.push(light * 0.97 * vein, light * vein, light * 0.79 * vein, 1);
    }
    uvs.push(0.5, 0, 0, 0.5, 0.5, 1, 1, 0.5, 0.5, 0.5);
    for (let side = 0; side < 4; side++)
      indices.push(start + side, start + ((side + 1) % 4), start + 4);
  }
  vertices.positions = positions;
  vertices.normals = normals;
  vertices.colors = colors;
  vertices.uvs = uvs;
  vertices.indices = indices;
  vertices.applyToMesh(mesh);
  mesh.position.set(at[0], at[1], at[2]);
  mesh.scaling.set(scale[0], scale[1], scale[2]);
  mesh.rotation.y = seed * 1.7;
  mesh.material = material;
  mesh.parent = parent;
  mesh.isPickable = false;
  mesh.receiveShadows = true;
  mesh.metadata = { foliageGeometry: 'opaque-folded-leaves', leafCount: count };
  return mesh;
}

/** A swept woody limb with an uneven taper and no independently shaded rings. */
function woodyLimb(
  scene: Scene,
  name: string,
  points: Vector3[],
  radii: number[],
  parent: TransformNode,
  material: NatureMaterials['bark'],
  low: boolean,
  seed: number,
) {
  const sides = low ? 5 : 8,
    positions: number[] = [],
    normals: number[] = [],
    indices: number[] = [],
    uvs: number[] = [],
    colors: number[] = [];
  let length = 0;
  for (let ring = 0; ring < points.length; ring++) {
    const point = points[ring],
      direction = points[Math.min(points.length - 1, ring + 1)]
        .subtract(points[Math.max(0, ring - 1)])
        .normalize(),
      reference = Math.abs(direction.y) > 0.92 ? Vector3.Right() : Vector3.Up(),
      sideways = Vector3.Cross(direction, reference).normalize(),
      outward = Vector3.Cross(sideways, direction).normalize();
    if (ring) length += Vector3.Distance(point, points[ring - 1]);
    for (let side = 0; side <= sides; side++) {
      const angle = (side / sides) * Math.PI * 2,
        fissure =
          1 +
          Math.sin(angle * 3 + seed) * 0.11 +
          Math.cos(angle * 5 - ring * 0.4) * 0.045,
        radial = sideways
          .scale(Math.cos(angle))
          .add(outward.scale(Math.sin(angle))),
        vertex = point.add(radial.scale(radii[ring] * fissure)),
        shade =
          0.68 + Math.max(0, Math.sin(angle * 3 + seed)) * 0.25 + ring * 0.025;
      positions.push(vertex.x, vertex.y, vertex.z);
      normals.push(radial.x, radial.y, radial.z);
      colors.push(shade, shade * 0.97, shade * 0.91, 1);
      uvs.push(side / sides, length * 0.7);
      if (ring < points.length - 1 && side < sides) {
        const at = ring * (sides + 1) + side,
          next = at + sides + 1;
        indices.push(at, next, at + 1, at + 1, next, next + 1);
      }
    }
  }
  const mesh = new Mesh(name, scene),
    data = new VertexData();
  data.positions = positions;
  data.normals = normals;
  data.indices = indices;
  data.uvs = uvs;
  data.colors = colors;
  data.applyToMesh(mesh);
  mesh.parent = parent;
  mesh.material = material;
  mesh.isPickable = false;
  return mesh;
}

function buildPalmCover(
  scene: Scene,
  wall: Wall,
  solid: TransformNode,
  rubble: TransformNode,
  materials: NatureMaterials,
  low: boolean,
  seed: number,
) {
  const width = wall.w * 0.1,
    height = wall.height ?? 7,
    bend = width * 0.24;
  woodyLimb(
    scene,
    'palm-ringed-trunk',
    [
      new Vector3(0, 0, 0),
      new Vector3(bend * 0.2, height * 0.3, 0),
      new Vector3(bend, height * 0.7, bend * 0.2),
      new Vector3(bend * 1.3, height, bend * 0.4),
    ],
    [width * 0.42, width * 0.29, width * 0.22, width * 0.18],
    solid,
    materials.bark,
    low,
    seed,
  );
  const positions: number[] = [],
    indices: number[] = [],
    colors: number[] = [],
    uv: number[] = [],
    normals: number[] = [],
    count = low ? 7 : 10;
  for (let frond = 0; frond < count; frond++) {
    const angle = frond * 2.399 + seed,
      dx = Math.cos(angle),
      dz = Math.sin(angle),
      reach = 2.8 + Math.sin(frond * 7) * 0.55;
    for (let leaf = 1; leaf < (low ? 6 : 9); leaf++) {
      const t = leaf / (low ? 6 : 9),
        along = t * reach,
        y = height + Math.sin(t * Math.PI) * 0.52 - t * t * 1.25,
        spread = Math.sin(t * Math.PI) * 0.58,
        x = bend * 1.3 + dx * along,
        z = bend * 0.4 + dz * along;
      for (const side of [-1, 1]) {
        const start = positions.length / 3;
        positions.push(
          x,
          y,
          z,
          x - dx * 0.12 - dz * spread * side,
          y - 0.11,
          z - dz * 0.12 + dx * spread * side,
          x + dx * 0.38 - dz * spread * side * 0.35,
          y - 0.14,
          z + dz * 0.38 + dx * spread * side * 0.35,
          x + dx * 0.3,
          y + 0.04,
          z + dz * 0.3,
        );
        indices.push(
          start,
          start + 1,
          start + 3,
          start + 1,
          start + 2,
          start + 3,
        );
        for (let v = 0; v < 4; v++) {
          const shade = 0.79 + t * 0.2 + (v === 3 ? 0.08 : 0);
          colors.push(shade * 0.9, shade, shade * 0.82, 1);
        }
        uv.push(0, 0, 0, 1, 1, 1, 1, 0);
      }
    }
  }
  VertexData.ComputeNormals(positions, indices, normals);
  const mesh = new Mesh('arched-palm-fronds', scene),
    data = new VertexData();
  data.positions = positions;
  data.indices = indices;
  data.normals = normals;
  data.colors = colors;
  data.uvs = uv;
  data.applyToMesh(mesh);
  mesh.material = materials.leaves;
  mesh.parent = solid;
  mesh.isPickable = false;
  box(
    scene,
    'shattered-palm-stump',
    [width * 0.62, 0.48, width * 0.62],
    [0, 0.24, 0],
    materials.bark,
    rubble,
  );
  for (let piece = 0; piece < 3; piece++)
    box(
      scene,
      'fallen-palm-frond',
      [0.17, 0.08, 1.4],
      [(piece - 1) * 0.55, 0.08, 0],
      materials.leaves,
      rubble,
    ).rotation.y = piece * 2.4;
}

export function buildLivingCover(
  scene: Scene,
  wall: Wall,
  solid: TransformNode,
  rubble: TransformNode,
  materials: NatureMaterials,
  quality: Quality,
  index: number,
  biome = 'city',
) {
  const rand = seeded(index * 193 + Math.floor(wall.x * 3 + wall.y));
  const low = quality === 'performance',
    width = wall.w * 0.1,
    depth = wall.h * 0.1;
  if (wall.kind === 'hedge') {
    box(
      scene,
      'hedge-root-bed',
      [width, 0.24, depth],
      [0, 0.12, 0],
      materials.soil,
      solid,
    );
    const count = Math.max(2, Math.ceil(width / 0.7));
    for (let i = 0; i < count; i++)
      crown(
        scene,
        'wild-hedgerow',
        [-width / 2 + ((i + 0.5) * width) / count, 0.68, 0],
        [(width / count) * 0.66, 0.55 + rand() * 0.15, depth * 0.51],
        i,
        materials.leaves,
        solid,
        low,
      );
    for (let i = 0; i < 4; i++)
      box(
        scene,
        'crushed-hedge-branches',
        [0.07, 0.06, depth * 0.8],
        [(rand() - 0.5) * width, 0.06, 0],
        materials.bark,
        rubble,
      ).rotation.y = rand() * 6;
    return;
  }
  if (biome === 'tropical' || (biome === 'wetlands' && index % 3 === 0)) {
    buildPalmCover(scene, wall, solid, rubble, materials, low, index);
    return;
  }
  const height = wall.height ?? 7,
    evergreen =
      biome === 'highlands' || (biome !== 'desert' && index % 3 === 0),
    lean = (rand() - 0.5) * width * 0.35;
  woodyLimb(
    scene,
    'solid-tree-trunk',
    [
      new Vector3(0, 0, 0),
      new Vector3(lean * 0.35, height * 0.13, -lean * 0.2),
      new Vector3(lean, height * 0.39, lean * 0.25),
      new Vector3(lean * 0.45, height * 0.63, lean),
      new Vector3(lean * 0.8, height * 0.9, lean * 0.55),
    ],
    [width * 0.49, width * 0.3, width * 0.23, width * 0.14, width * 0.035],
    solid,
    materials.bark,
    low,
    index,
  );
  // Buttress roots keep tall trunks anchored to the ground and break the
  // perfectly cylindrical silhouette without extending the colliding trunk.
  for (let root = 0; root < (low ? 3 : 5); root++) {
    const angle = (root * Math.PI * 2) / (low ? 3 : 5);
    woodyLimb(
      scene,
      'tree-buttress-root',
      [
        new Vector3(
          Math.cos(angle) * width * 0.43,
          0.035,
          Math.sin(angle) * width * 0.43,
        ),
        new Vector3(
          Math.cos(angle) * width * 0.31,
          0.23,
          Math.sin(angle) * width * 0.31,
        ),
        new Vector3(lean * 0.35, height * 0.21, -lean * 0.2),
      ],
      [width * 0.11, width * 0.15, width * 0.085],
      solid,
      materials.bark,
      true,
      root,
    );
  }
  const clumps = low ? 6 : evergreen ? 14 : 12;
  for (let i = 0; i < clumps; i++) {
    const angle = i * 2.4 + rand() * 0.4;
    const tier = i / clumps;
    const spread = evergreen ? (1 - tier) * 2.3 : 1.1 + rand() * 1.12;
    const y = evergreen
      ? height * (0.36 + tier * 0.58)
      : height * (0.55 + rand() * 0.38);
    const limbEnd = new Vector3(
      Math.cos(angle) * spread,
      y,
      Math.sin(angle) * spread,
    );
    woodyLimb(
      scene,
      'tree-branch',
      [
        new Vector3(lean * 0.65, y - (evergreen ? 0.28 : 0.85), lean * 0.4),
        new Vector3(
          Math.cos(angle + 0.12) * spread * 0.55,
          y - 0.18,
          Math.sin(angle + 0.12) * spread * 0.55,
        ),
        limbEnd,
      ],
      [evergreen ? 0.11 : 0.17, 0.085, 0.023],
      solid,
      materials.bark,
      true,
      i,
    );
    crown(
      scene,
      evergreen ? 'pine-bough' : 'broadleaf-canopy',
      [Math.cos(angle) * spread, y, Math.sin(angle) * spread],
      evergreen
        ? [1.12 - tier * 0.63, 0.3 + tier * 0.16, 1.12 - tier * 0.63]
        : [0.8 + rand() * 0.2, 0.6 + rand() * 0.6, 0.83 + rand() * 0.22],
      i + index,
      evergreen ? materials.pine : materials.leaves,
      solid,
      low,
    );
    if (!low) {
      const twigAngle = angle + (i % 2 ? 0.58 : -0.58),
        reach = spread + (evergreen ? 0.55 : 0.65);
      woodyLimb(
        scene,
        'forked-crown-twig',
        [
          limbEnd.scale(0.76).add(new Vector3(0, y * 0.24 - 0.08, 0)),
          new Vector3(
            Math.cos(twigAngle) * reach,
            y + (evergreen ? -0.08 : 0.23),
            Math.sin(twigAngle) * reach,
          ),
        ],
        [0.046, 0.012],
        solid,
        materials.bark,
        true,
        i + 4,
      );
      crown(
        scene,
        evergreen ? 'pine-bough-tip' : 'broadleaf-canopy-offshoot',
        [
          Math.cos(twigAngle) * reach,
          y + (evergreen ? -0.08 : 0.23),
          Math.sin(twigAngle) * reach,
        ],
        evergreen ? [0.47, 0.21, 0.47] : [0.58, 0.48 + rand() * 0.22, 0.56],
        index + i * 3.1,
        evergreen ? materials.pine : materials.leaves,
        solid,
        false,
      );
    }
  }
  if (evergreen)
    crown(
      scene,
      'pine-bough-terminal-leader',
      [0.03, height * 0.97, -0.02],
      [0.3, 0.62, 0.3],
      index + 31,
      materials.pine,
      solid,
      low,
    );
  const stump = MeshBuilder.CreateCylinder(
    'shattered-tree-stump',
    {
      height: 0.7,
      diameterBottom: width,
      diameterTop: width * 0.6,
      tessellation: 7,
    },
    scene,
  );
  stump.position.y = 0.35;
  stump.material = materials.bark;
  stump.parent = rubble;
  stump.isPickable = false;
  for (let i = 0; i < (low ? 3 : 6); i++) {
    const piece = box(
      scene,
      'splintered-wood',
      [0.18, 0.14, 0.6 + rand() * 1.6],
      [(rand() - 0.5) * 3, 0.1, (rand() - 0.5) * 3],
      materials.bark,
      rubble,
    );
    piece.rotation.y = rand() * Math.PI * 2;
  }
}

type Geometry = {
  positions: number[];
  indices: number[];
  colors: number[];
  uvs: number[];
};
const geometry = (): Geometry => ({
  positions: [],
  indices: [],
  colors: [],
  uvs: [],
});
function geometryMesh(scene: Scene, name: string, data: Geometry) {
  const mesh = new Mesh(name, scene),
    vertex = new VertexData(),
    normals: number[] = [];
  VertexData.ComputeNormals(data.positions, data.indices, normals, {
    useRightHandedSystem: true,
  });
  vertex.positions = data.positions;
  vertex.indices = data.indices;
  vertex.normals = normals;
  vertex.colors = data.colors;
  vertex.uvs = data.uvs;
  vertex.applyToMesh(mesh);
  mesh.isPickable = false;
  mesh.receiveShadows = true;
  mesh.freezeWorldMatrix();
  return mesh;
}

function vergeStone(
  data: Geometry,
  x: number,
  z: number,
  size: number,
  seed: number,
) {
  const random = seeded(seed),
    sides = 7,
    points: Vector3[][] = [],
    height = size * (0.2 + random() * 0.16);
  for (let ring = 0; ring < 3; ring++) {
    const vertices: Vector3[] = [];
    for (let side = 0; side < sides; side++) {
      const angle = (side / sides) * Math.PI * 2 + seed,
        radius =
          size *
          (ring === 0 ? 0.65 : ring === 1 ? 0.59 : 0.34) *
          (0.85 + random() * 0.24);
      vertices.push(
        new Vector3(
          x + Math.cos(angle) * radius + ring * size * 0.035,
          0.04 +
            height *
              (ring === 0 ? 0 : ring === 1 ? 0.52 : 0.93 + random() * 0.12),
          z + Math.sin(angle) * radius * 0.72,
        ),
      );
    }
    points.push(vertices);
  }
  const triangle = (a: Vector3, b: Vector3, c: Vector3, light: number) => {
    const index = data.positions.length / 3;
    for (const point of [a, b, c]) {
      data.positions.push(point.x, point.y, point.z);
      data.colors.push(light * 0.96, light, light * 0.93, 1);
      data.uvs.push(point.x * 0.7, point.z * 0.7 + point.y * 0.5);
    }
    data.indices.push(index, index + 2, index + 1);
  };
  for (let side = 0; side < sides; side++) {
    const next = (side + 1) % sides;
    for (let ring = 0; ring < 2; ring++) {
      const shade = 0.62 + ring * 0.19 + random() * 0.09;
      triangle(
        points[ring][side],
        points[ring][next],
        points[ring + 1][side],
        shade,
      );
      triangle(
        points[ring][next],
        points[ring + 1][next],
        points[ring + 1][side],
        shade,
      );
    }
    triangle(
      points[2][side],
      points[2][next],
      new Vector3(x + size * 0.05, height + 0.04, z),
      0.89,
    );
  }
}
const grassVertex = `precision highp float;attribute vec3 position;attribute vec4 color;uniform mat4 worldViewProjection;uniform float time;varying vec4 vColor;varying vec3 vPosition;void main(){vec3 p=position;p.x+=sin(time*1.3+p.x*.85+p.z*.34)*p.y*.12;p.z+=cos(time*.9+p.x*.5)*p.y*.06;vColor=color;vPosition=p;gl_Position=worldViewProjection*vec4(p,1.);}`;
const grassFragment = `precision highp float;varying vec4 vColor;varying vec3 vPosition;uniform vec3 fogColor;uniform vec3 eye;uniform float fogDensity;void main(){float fog=1.-exp(-pow(length(vPosition-eye)*fogDensity,2.));gl_FragColor=vec4(mix(vColor.rgb,fogColor,fog),1.);}`;

export function createNature(
  scene: Scene,
  b: Battle,
  materials: NatureMaterials,
  quality: Quality,
) {
  const low = quality === 'performance',
    desert = b.battlefield.biome === 'desert',
    rand = seeded(1777 + b.mission * 61);
  const meshes: Mesh[] = [],
    mountains: { x: number; z: number; width: number; depth: number }[] = [];
  // Mountain bases are entirely outside the simulation, never invisible obstacles.
  for (let side = 0; side < 4; side++) {
    for (let j = 0; j < (low ? 2 : 3); j++) {
      const width = 65 + rand() * 35,
        depth = 52 + rand() * 25;
      const x =
        side < 2
          ? (side ? 1 : -1) * (W * 0.05 + width / 2 + 12)
          : -110 + j * 105;
      const z =
        side >= 2
          ? (side === 2 ? -1 : 1) * (H * 0.05 + depth / 2 + 17)
          : -65 + j * 60;
      mountains.push({ x, z, width, depth });
      const data = geometry(),
        segments = low ? 10 : quality === 'cinematic' ? 28 : 24,
        peak = desert
          ? 9 + rand() * 12
          : b.battlefield.biome === 'highlands'
            ? 27 + rand() * 24
            : 16 + rand() * 20;
      for (let row = 0; row <= segments; row++)
        for (let col = 0; col <= segments; col++) {
          const u = col / segments,
            v = row / segments;
          const envelope = Math.pow(
            Math.max(0, Math.sin(u * Math.PI) * Math.sin(v * Math.PI)),
            0.7,
          );
          const ridge =
              0.67 +
              0.18 * Math.abs(Math.sin(u * 10.4 - v * 5.2 + side)) +
              0.1 * Math.cos(v * 17 - u * 7) +
              0.05 * Math.sin(u * 33 + v * 23 + j),
            baseHeight = envelope * peak * ridge,
            // Soft ledges and alternating strata interrupt smooth, cone-like
            // hills while retaining the same bounded heightfield footprint.
            strata = Math.sin(baseHeight * 1.35 + u * 0.6) * 0.35,
            h = Math.max(0, baseHeight + strata * envelope);
          data.positions.push(
            x + (u - 0.5) * width,
            h - 0.15,
            z + (v - 0.5) * depth,
          );
          const rock =
            Math.min(1, 0.48 + (h / peak) * 0.5) *
            (0.88 +
              0.1 * Math.sin(baseHeight * 1.35 + u * 0.6) +
              0.03 * Math.cos(v * 40));
          data.colors.push(rock, rock * 1.02, rock * 0.94, 1);
          data.uvs.push(u * 5, v * 5);
          if (row < segments && col < segments) {
            const at = row * (segments + 1) + col;
            data.indices.push(
              at,
              at + segments + 1,
              at + 1,
              at + 1,
              at + segments + 1,
              at + segments + 2,
            );
          }
        }
      const mesh = geometryMesh(scene, 'layered-mountain-ridge', data);
      mesh.material = materials.stone;
      mesh.metadata = { decoration: 'mountain', x, z, width, depth };
      meshes.push(mesh);
    }
  }
  const grassMaterial = new ShaderMaterial(
    'wind-brushed-wild-grass',
    scene,
    { vertexSource: grassVertex, fragmentSource: grassFragment },
    {
      attributes: ['position', 'color'],
      uniforms: [
        'worldViewProjection',
        'time',
        'fogColor',
        'eye',
        'fogDensity',
      ],
    },
  );
  grassMaterial.backFaceCulling = false;
  const chunks = new Map<string, { grass: Geometry; soil: Geometry }>(),
    stones = geometry();
  const excluded = (x: number, y: number) =>
    b.terrain.some(
      (feature) =>
        x > feature.x - 12 &&
        x < feature.x + feature.w + 12 &&
        y > feature.y - 12 &&
        y < feature.y + feature.h + 12,
    ) ||
    b.roads.some(
      (r) =>
        x > r.x - 12 &&
        x < r.x + r.w + 12 &&
        y > r.y - 12 &&
        y < r.y + r.h + 12,
    ) ||
    b.walls.some(
      (w) =>
        x > w.x - 9 && x < w.x + w.w + 9 && y > w.y - 9 && y < w.y + w.h + 9,
    ) ||
    [b.player, b.base, ...b.objectives, ...b.route].some(
      (p) => Math.hypot(x - p.x, y - p.y) < 75,
    );
  const step = desert
    ? low
      ? 110
      : 82
    : low
      ? 68
      : quality === 'cinematic'
        ? 32
        : 43;
  let tufts = 0;
  for (let y = 20; y < H - 20; y += step)
    for (let x = 20; x < W - 20; x += step) {
      const sx = x + rand() * 12,
        sy = y + rand() * 12;
      if (excluded(sx, sy) || rand() > 0.82) continue;
      const key = Math.floor(sx / 480) + ':' + Math.floor(sy / 480);
      let chunk = chunks.get(key);
      if (!chunk) {
        chunk = { grass: geometry(), soil: geometry() };
        chunks.set(key, chunk);
      }
      const wx = (sx - W / 2) * 0.1,
        wz = (sy - H / 2) * 0.1;
      // Low, irregular textured patches blend the concrete into untended verges.
      const start = chunk.soil.positions.length / 3,
        radius = 1.3 + rand() * 0.9;
      chunk.soil.positions.push(wx, 0.033, wz);
      chunk.soil.colors.push(0.91, 0.96, 0.79, 1);
      chunk.soil.uvs.push(wx * 0.12, wz * 0.12);
      for (let k = 0; k <= 8; k++) {
        const angle = (k / 8) * Math.PI * 2,
          edge =
            radius *
            (0.88 +
              Math.sin(angle * 3 + sx) * 0.16 +
              Math.cos(angle * 5 + sy) * 0.1),
          px = wx + Math.cos(angle) * edge,
          pz = wz + Math.sin(angle) * edge;
        chunk.soil.positions.push(px, 0.028, pz);
        chunk.soil.colors.push(0.72, 0.76, 0.66, 1);
        chunk.soil.uvs.push(px * 0.12, pz * 0.12);
        if (k < 8) chunk.soil.indices.push(start, start + k + 2, start + k + 1);
      }
      // A single shared mesh batches low stones throughout the verges. They
      // stay below running gear and outside roads/objectives, with no collision.
      if (rand() < (low ? 0.045 : 0.08))
        vergeStone(
          stones,
          wx + radius * 0.25,
          wz - radius * 0.22,
          0.6 + rand() * 0.7,
          Math.floor(sx * 17 + sy),
        );
      for (let tuft = 0; tuft < (low ? 2 : 5); tuft++) {
        const gx = wx + (rand() - 0.5) * radius * 1.5,
          gz = wz + (rand() - 0.5) * radius * 1.5;
        const height = 0.18 + rand() * 0.3,
          brown = rand();
        for (let blade = 0; blade < (low ? 2 : 3); blade++) {
          const angle = rand() * Math.PI * 2,
            dx = Math.cos(angle) * 0.045,
            dz = Math.sin(angle) * 0.045;
          const lean = (rand() - 0.5) * 0.42,
            base = chunk.grass.positions.length / 3;
          chunk.grass.positions.push(
            gx - dx,
            0.05,
            gz - dz,
            gx + dx,
            0.05,
            gz + dz,
            gx + lean * 0.35 - dx * 0.55,
            height * 0.56,
            gz + lean * 0.18 - dz * 0.55,
            gx + lean * 0.35 + dx * 0.55,
            height * 0.56,
            gz + lean * 0.18 + dz * 0.55,
            gx + lean,
            height,
            gz + lean * 0.5,
          );
          chunk.grass.colors.push(
            0.19,
            0.23,
            0.12,
            1,
            0.19,
            0.23,
            0.12,
            1,
            0.4 + brown * 0.1,
            0.46,
            0.23,
            1,
            0.4 + brown * 0.1,
            0.46,
            0.23,
            1,
            0.5 + brown * 0.1,
            0.52,
            0.29,
            1,
          );
          chunk.grass.uvs.push(0, 0, 1, 0, 0.22, 0.56, 0.78, 0.56, 0.5, 1);
          chunk.grass.indices.push(
            base,
            base + 1,
            base + 2,
            base + 1,
            base + 3,
            base + 2,
            base + 2,
            base + 3,
            base + 4,
          );
        }
        if (!low && tuft === 0 && rand() < 0.32) {
          // Low rosettes break up the uniform grass silhouette without another
          // material, mesh, transparency pass, or shadow caster.
          for (let leaf = 0; leaf < 4; leaf++) {
            const angle = leaf * 2.399 + rand(),
              reach = 0.2 + rand() * 0.17,
              dx = Math.cos(angle),
              dz = Math.sin(angle),
              at = chunk.grass.positions.length / 3;
            chunk.grass.positions.push(
              gx,
              0.065,
              gz,
              gx + dx * reach * 0.52 - dz * 0.065,
              0.14,
              gz + dz * reach * 0.52 + dx * 0.065,
              gx + dx * reach,
              0.1 + rand() * 0.11,
              gz + dz * reach,
              gx + dx * reach * 0.52 + dz * 0.065,
              0.14,
              gz + dz * reach * 0.52 - dx * 0.065,
            );
            chunk.grass.colors.push(
              0.2,
              0.25,
              0.12,
              1,
              0.34,
              0.4,
              0.2,
              1,
              0.39,
              0.45,
              0.23,
              1,
              0.29,
              0.36,
              0.17,
              1,
            );
            chunk.grass.uvs.push(0.5, 0, 0, 0.5, 0.5, 1, 1, 0.5);
            chunk.grass.indices.push(at, at + 1, at + 2, at, at + 2, at + 3);
          }
        }
        tufts++;
      }
    }
  for (const [key, chunk] of chunks) {
    if (desert)
      for (let i = 0; i < chunk.grass.colors.length; i += 4) {
        chunk.grass.colors[i] = Math.min(0.72, chunk.grass.colors[i] * 1.55);
        chunk.grass.colors[i + 1] *= 1.16;
        chunk.grass.colors[i + 2] *= 1.22;
      }
    const soil = geometryMesh(scene, 'natural-verge-' + key, chunk.soil);
    soil.material = materials.soil;
    const grass = geometryMesh(scene, 'grass-cluster-' + key, chunk.grass);
    grass.material = grassMaterial;
    meshes.push(soil, grass);
  }
  if (stones.indices.length) {
    const mesh = geometryMesh(scene, 'verge-layered-stones', stones);
    mesh.material = materials.stone;
    meshes.push(mesh);
  }
  return {
    meshes,
    mountains,
    tufts,
    update(time: number) {
      grassMaterial.setFloat('time', time);
      grassMaterial.setColor3('fogColor', scene.fogColor);
      grassMaterial.setFloat('fogDensity', scene.fogDensity);
      if (scene.activeCamera)
        grassMaterial.setVector3('eye', scene.activeCamera.globalPosition);
    },
  };
}
