import { assetUrl } from '../asset-url';
import {
  Mesh,
  MeshBuilder,
  Scene,
  ShaderMaterial,
  Texture,
  TransformNode,
  VertexData,
} from './babylon';
import { Battle, H, W, seeded, type Wall } from '../engine';
import { pbr, type Quality } from './materials';
import { box } from './tank-model';

export function natureMaterials(
  scene: Scene,
  assets: boolean,
  quality: Quality,
) {
  const bark = pbr(scene, 'split-tree-bark', '#655641', 0, 0.97);
  const leaves = pbr(scene, 'sunlit-olive-foliage', '#758757', 0, 0.94);
  const pine = pbr(scene, 'pine-needle-clusters', '#435b48', 0, 0.96);
  const stone = pbr(scene, 'weathered-ridge-stone', '#8c8c7b', 0, 0.94);
  const soil = pbr(scene, 'overgrown-verge-soil', '#a1a285', 0, 0.98);
  leaves.backFaceCulling = false;
  pine.backFaceCulling = false;
  if (assets && quality !== 'performance') {
    const texture = new Texture(assetUrl('/woodland-ground.webp'), scene);
    texture.anisotropicFilteringLevel = quality === 'cinematic' ? 8 : 4;
    soil.albedoTexture = texture;
    stone.albedoTexture = texture;
    bark.albedoTexture = texture;
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
  const mesh = MeshBuilder.CreateIcoSphere(
    name,
    { radius: 1, subdivisions: low ? 1 : 2, flat: false },
    scene,
  );
  const vertices = mesh.getVerticesData('position')!;
  const colors: number[] = [],
    normals: number[] = [];
  for (let i = 0; i < vertices.length; i += 3) {
    const shade =
      0.74 + 0.24 * Math.sin(vertices[i] * 13 + vertices[i + 2] * 9 + seed);
    const jitter = 0.85 + shade * 0.22;
    vertices[i] *= jitter;
    vertices[i + 1] *= jitter;
    vertices[i + 2] *= jitter;
    const light = 0.63 + 0.22 * (vertices[i + 1] + 1) + shade * 0.12;
    colors.push(light, light, light * 0.94, 1);
  }
  // Built-in sphere indices retain Babylon's winding even in a RH scene.
  VertexData.ComputeNormals(vertices, mesh.getIndices()!, normals);
  mesh.setVerticesData('position', vertices);
  mesh.setVerticesData('normal', normals);
  mesh.setVerticesData('color', colors);
  mesh.position.set(at[0], at[1], at[2]);
  mesh.scaling.set(scale[0], scale[1], scale[2]);
  mesh.material = material;
  mesh.parent = parent;
  mesh.isPickable = false;
  return mesh;
}

export function buildLivingCover(
  scene: Scene,
  wall: Wall,
  solid: TransformNode,
  rubble: TransformNode,
  materials: NatureMaterials,
  quality: Quality,
  index: number,
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
  const height = wall.height ?? 7,
    evergreen = index % 3 === 0;
  const trunk = MeshBuilder.CreateCylinder(
    'solid-tree-trunk',
    {
      height: height * 0.76,
      diameterBottom: width,
      diameterTop: width * 0.25,
      tessellation: low ? 6 : 9,
    },
    scene,
  );
  trunk.position.y = height * 0.38;
  trunk.material = materials.bark;
  trunk.parent = solid;
  trunk.isPickable = false;
  const clumps = low ? 5 : evergreen ? 12 : 11;
  for (let i = 0; i < clumps; i++) {
    const angle = i * 2.4 + rand() * 0.4;
    const tier = i / clumps;
    const spread = evergreen ? (1 - tier) * 2.1 : 1.2 + rand() * 0.85;
    const y = evergreen
      ? height * (0.36 + tier * 0.58)
      : height * (0.66 + rand() * 0.24);
    const branch = MeshBuilder.CreateCylinder(
      'tree-branch',
      {
        height: spread * 1.3,
        diameterBottom: 0.19,
        diameterTop: 0.055,
        tessellation: 5,
      },
      scene,
    );
    branch.position.set(
      Math.cos(angle) * spread * 0.45,
      y - 0.3,
      Math.sin(angle) * spread * 0.45,
    );
    branch.rotation.set(Math.sin(angle) * 0.9, 0, -Math.cos(angle) * 0.9);
    branch.material = materials.bark;
    branch.parent = solid;
    branch.isPickable = false;
    crown(
      scene,
      evergreen ? 'pine-bough' : 'broadleaf-canopy',
      [Math.cos(angle) * spread, y, Math.sin(angle) * spread],
      evergreen
        ? [1.2 - tier * 0.5, 0.68, 1.2 - tier * 0.5]
        : [1.3, 1 + rand() * 0.4, 1.35],
      i + index,
      evergreen ? materials.pine : materials.leaves,
      solid,
      low,
    );
  }
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
const grassVertex = `precision highp float;attribute vec3 position;attribute vec4 color;uniform mat4 worldViewProjection;uniform float time;varying vec4 vColor;varying vec3 vPosition;void main(){vec3 p=position;p.x+=sin(time*1.3+p.x*.85+p.z*.34)*p.y*.12;p.z+=cos(time*.9+p.x*.5)*p.y*.06;vColor=color;vPosition=p;gl_Position=worldViewProjection*vec4(p,1.);}`;
const grassFragment = `precision highp float;varying vec4 vColor;varying vec3 vPosition;uniform vec3 fogColor;uniform vec3 eye;uniform float fogDensity;void main(){float fog=1.-exp(-pow(length(vPosition-eye)*fogDensity,2.));gl_FragColor=vec4(mix(vColor.rgb,fogColor,fog),1.);}`;

export function createNature(
  scene: Scene,
  b: Battle,
  materials: NatureMaterials,
  quality: Quality,
) {
  const low = quality === 'performance',
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
        segments = low ? 10 : 20,
        peak = 16 + rand() * 20;
      for (let row = 0; row <= segments; row++)
        for (let col = 0; col <= segments; col++) {
          const u = col / segments,
            v = row / segments;
          const envelope = Math.pow(
            Math.max(0, Math.sin(u * Math.PI) * Math.sin(v * Math.PI)),
            0.7,
          );
          const ridge =
            0.72 +
            0.18 * Math.sin(u * 19 + v * 11 + side) +
            0.1 * Math.cos(v * 31 - u * 7);
          const h = envelope * peak * ridge;
          data.positions.push(
            x + (u - 0.5) * width,
            h - 0.15,
            z + (v - 0.5) * depth,
          );
          const rock = Math.min(1, 0.48 + (h / peak) * 0.5);
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
  const chunks = new Map<string, { grass: Geometry; soil: Geometry }>();
  const excluded = (x: number, y: number) =>
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
  const step = low ? 68 : quality === 'cinematic' ? 32 : 43;
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
          px = wx + Math.cos(angle) * radius,
          pz = wz + Math.sin(angle) * radius;
        chunk.soil.positions.push(px, 0.028, pz);
        chunk.soil.colors.push(0.72, 0.76, 0.66, 1);
        chunk.soil.uvs.push(px * 0.12, pz * 0.12);
        if (k < 8) chunk.soil.indices.push(start, start + k + 2, start + k + 1);
      }
      for (let tuft = 0; tuft < (low ? 2 : 5); tuft++) {
        const gx = wx + (rand() - 0.5) * radius * 1.5,
          gz = wz + (rand() - 0.5) * radius * 1.5;
        const height = 0.18 + rand() * 0.3,
          brown = rand();
        for (let blade = 0; blade < (low ? 3 : 5); blade++) {
          const angle = rand() * Math.PI * 2,
            dx = Math.cos(angle) * 0.045,
            dz = Math.sin(angle) * 0.045;
          const lean = (rand() - 0.5) * 0.32,
            base = chunk.grass.positions.length / 3;
          chunk.grass.positions.push(
            gx - dx,
            0.05,
            gz - dz,
            gx + dx,
            0.05,
            gz + dz,
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
          );
          chunk.grass.uvs.push(0, 0, 1, 0, 0.5, 1);
          chunk.grass.indices.push(base, base + 1, base + 2);
        }
        tufts++;
      }
    }
  for (const [key, chunk] of chunks) {
    const soil = geometryMesh(scene, 'natural-verge-' + key, chunk.soil);
    soil.material = materials.soil;
    const grass = geometryMesh(scene, 'grass-cluster-' + key, chunk.grass);
    grass.material = grassMaterial;
    meshes.push(soil, grass);
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
