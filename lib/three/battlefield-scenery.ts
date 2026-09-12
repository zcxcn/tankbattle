import { CreateBoxVertexData } from '@babylonjs/core/Meshes/Builders/boxBuilder.js';
import { Mesh, Scene, ShaderMaterial, VertexData } from './babylon';
import { H, W, seeded, type Battle } from '../engine';
import { pbr, type Materials, type Quality } from './materials';
import { applySurface } from './surface-textures';

// Natural colour belongs to each map; the same local surface library supplies
// micro-detail, so changing the biome never introduces another download.
export function battlefieldPalette(biome: string) {
  const palettes = {
    city: [
      '#a5aaa5',
      '#485b68',
      '#fff0d3',
      '#b5b4a9',
      '#aeb3b1',
      '#acafa6',
      '#b9b99e',
      '#899071',
    ],
    highlands: [
      '#aab9b5',
      '#536d80',
      '#f1edd6',
      '#969f79',
      '#a3a18b',
      '#a4aaa0',
      '#adb28b',
      '#78916c',
    ],
    desert: [
      '#cfb79a',
      '#72858e',
      '#fff0ce',
      '#d1b17c',
      '#c1a783',
      '#c8ae8a',
      '#d3b986',
      '#9b9a66',
    ],
    tropical: [
      '#afc4ba',
      '#4c7b8c',
      '#f4f0d5',
      '#87956c',
      '#9a9e83',
      '#969e8d',
      '#91aa79',
      '#689464',
    ],
    railway: [
      '#a5b3b7',
      '#4b6375',
      '#f1e8d5',
      '#a8a79a',
      '#a5aaa8',
      '#a7aaa5',
      '#a8ae93',
      '#7f8d6b',
    ],
    wetlands: [
      '#b1c2ba',
      '#5c7a88',
      '#edf0d9',
      '#8e9b80',
      '#a6ac98',
      '#a0aa9b',
      '#a9b396',
      '#7f996b',
    ],
  };
  const p = palettes[biome as keyof typeof palettes] ?? palettes.city;
  return {
    horizon: p[0],
    zenith: p[1],
    sun: p[2],
    ground: p[3],
    road: p[4],
    stone: p[5],
    soil: p[6],
    foliage: p[7],
  };
}
type Geometry = {
  positions: number[];
  normals: number[];
  uvs: number[];
  indices: number[];
  colors: number[];
};
const geometry = (): Geometry => ({
  positions: [],
  normals: [],
  uvs: [],
  indices: [],
  colors: [],
});
const cube = CreateBoxVertexData({ size: 1 });
function addBox(
  data: Geometry,
  x: number,
  y: number,
  z: number,
  w: number,
  h: number,
  d: number,
) {
  const start = data.positions.length / 3;
  for (let i = 0; i < cube.positions!.length; i += 3) {
    const px = cube.positions![i] * w + x,
      py = cube.positions![i + 1] * h + y,
      pz = cube.positions![i + 2] * d + z;
    data.positions.push(px, py, pz);
    data.normals.push(
      cube.normals![i],
      cube.normals![i + 1],
      cube.normals![i + 2],
    );
    data.uvs.push(
      (Math.abs(cube.normals![i]) > 0.5 ? pz : px) / 3,
      (Math.abs(cube.normals![i + 1]) > 0.5 ? pz : py) / 3,
    );
    data.colors.push(1, 1, 1, 1);
  }
  for (const index of cube.indices!) data.indices.push(index + start);
}
type Point = [number, number, number];
function addTriangle(data: Geometry, a: Point, b: Point, c: Point, shade = 1) {
  const at = data.positions.length / 3,
    ux = b[0] - a[0],
    uy = b[1] - a[1],
    uz = b[2] - a[2],
    vx = c[0] - a[0],
    vy = c[1] - a[1],
    vz = c[2] - a[2],
    nx = uy * vz - uz * vy,
    ny = uz * vx - ux * vz,
    nz = ux * vy - uy * vx,
    length = Math.hypot(nx, ny, nz) || 1;
  for (const point of [a, b, c]) {
    data.positions.push(...point);
    data.normals.push(nx / length, ny / length, nz / length);
    data.uvs.push(point[0] / 3, point[2] / 3);
    data.colors.push(shade, shade, shade * 0.96, 1);
  }
  data.indices.push(at, at + 1, at + 2);
}
function addShoreline(
  soil: Geometry,
  rocks: Geometry,
  reeds: Geometry,
  x: number,
  z: number,
  width: number,
  depth: number,
  low: boolean,
  seed: number,
) {
  const random = seeded(seed),
    inset = Math.min(1.35, Math.min(width, depth) * 0.16);
  for (const acrossX of [true, false])
    for (const side of [-1, 1]) {
      const length = acrossX ? width : depth,
        cross = acrossX ? depth : width,
        segments = Math.min(
          low ? 36 : 72,
          Math.max(4, Math.ceil(length / (low ? 3 : 1.8))),
        );
      const point = (along: number, inward: number, height: number): Point =>
        acrossX
          ? [x + along, height, z + side * (cross / 2 - inward)]
          : [x + side * (cross / 2 - inward), height, z + along];
      let previous: Point[] | null = null;
      for (let step = 0; step <= segments; step++) {
        const along = -length / 2 + (length * step) / segments,
          reach = inset * (0.38 + random() * 0.62),
          crest = 0.07 + random() * 0.07,
          row = [
            point(along, 0, 0.038),
            point(along, reach * 0.45, crest),
            point(along, reach, 0.052),
          ];
        if (previous)
          for (let strip = 0; strip < 2; strip++) {
            const a = previous[strip],
              b = previous[strip + 1],
              c = row[strip],
              d = row[strip + 1],
              shade = 0.78 + random() * 0.2;
            // Keep winding upward on all four shores, without a vertical wall.
            const up = acrossX ? side > 0 : side < 0;
            if (up) {
              addTriangle(soil, a, c, b, shade);
              addTriangle(soil, b, c, d, shade);
            } else {
              addTriangle(soil, a, b, c, shade);
              addTriangle(soil, b, d, c, shade);
            }
          }
        previous = row;
        if (step === 0 || step === segments) continue;
        const radius = 0.19 + random() * Math.min(0.31, inset * 0.2),
          inward = Math.min(
            cross - radius,
            radius + random() * Math.max(0, reach - radius),
          ),
          safeAlong = Math.max(
            -length / 2 + radius,
            Math.min(length / 2 - radius, along),
          ),
          at = point(safeAlong, inward, 0.065);
        if (random() < (low ? 0.3 : 0.48)) {
          const sides = 6,
            top: Point = [
              at[0] + radius * 0.1,
              0.16 + random() * 0.2,
              at[2] - radius * 0.12,
            ],
            ring: Point[] = [];
          for (let corner = 0; corner < sides; corner++) {
            const angle = (corner * Math.PI * 2) / sides,
              r = radius * (0.72 + random() * 0.28);
            ring.push([
              at[0] + Math.cos(angle) * r,
              0.055 + random() * 0.05,
              at[2] + Math.sin(angle) * r,
            ]);
          }
          for (let corner = 0; corner < sides; corner++)
            addTriangle(
              rocks,
              ring[corner],
              top,
              ring[(corner + 1) % sides],
              0.68 + random() * 0.29,
            );
        }
        if (random() < (low ? 0.36 : 0.62)) {
          const plant = point(
            safeAlong,
            Math.min(cross - 0.2, 0.2 + random() * Math.max(0.1, reach - 0.3)),
            0.07,
          );
          for (let blade = 0; blade < (low ? 3 : 5); blade++) {
            const angle = random() * Math.PI * 2,
              half = 0.025 + random() * 0.017,
              height = 0.35 + random() * 0.52,
              dx = Math.cos(angle),
              dz = Math.sin(angle),
              lean = 0.08 + random() * 0.07;
            addTriangle(
              reeds,
              [plant[0] - dx * half, 0.07, plant[2] - dz * half],
              [plant[0] + dx * half, 0.07, plant[2] + dz * half],
              [plant[0] + dz * lean, height, plant[2] - dx * lean],
              0.78 + random() * 0.22,
            );
          }
        }
      }
    }
}

function makeMesh(scene: Scene, name: string, data: Geometry) {
  const mesh = new Mesh(name, scene),
    vertices = new VertexData();
  vertices.positions = data.positions;
  vertices.indices = data.indices;
  vertices.normals = data.normals;
  vertices.uvs = data.uvs;
  vertices.colors = data.colors;
  vertices.applyToMesh(mesh);
  mesh.isPickable = false;
  mesh.receiveShadows = true;
  mesh.freezeWorldMatrix();
  return mesh;
}
const waterVertex = `precision highp float;attribute vec3 position;uniform mat4 worldViewProjection;varying vec3 vPosition;void main(){vPosition=position;gl_Position=worldViewProjection*vec4(position,1.);}`;
const waterFragment = `precision highp float;
varying vec3 vPosition;
uniform float time;
uniform vec3 fogColor;
uniform vec3 eye;
uniform float fogDensity;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1.,0.)),f.x),mix(hash(i+vec2(0.,1.)),hash(i+vec2(1.,1.)),f.x),f.y);}
void main(){
  vec2 p=vPosition.xz;
  vec2 flow=vec2(time*.027,-time*.016);
  vec2 warp=vec2(noise(p*.067+flow),noise(p*.083-flow+vec2(8.3,2.7)))-.5;
  float broad=noise(p*.115+warp*1.4+flow);
  float detail=noise(p*vec2(.29,.17)+warp*.8-flow*.7);
  float current=dot(p,vec2(.53,.31))+warp.x*4.2+warp.y*2.8-time*.38;
  float ripple=.5+.5*sin(current);
  float glint=smoothstep(.79,.98,ripple)*smoothstep(.4,.85,detail)*.035;
  float sheen=pow(1.-max(0.,normalize(eye-vPosition).y),3.)*.024;
  vec3 col=mix(vec3(.12,.225,.205),vec3(.17,.295,.26),broad*.67+detail*.14);
  col+=vec3(.65,.78,.73)*(glint+sheen);
  float fog=1.-exp(-pow(length(vPosition-eye)*fogDensity,2.));
  gl_FragColor=vec4(mix(col,fogColor,fog),1.);
}`;

/** Rectangles come from surviving simulation obstacles and their carved gaps.
 * Banks stay inside water footprints; decks and rails are low enough for the
 * planar tank simulation. No decorative barrier closes a navigable crossing. */
export function createBattlefieldScenery(
  scene: Scene,
  battle: Battle,
  materials: Materials,
  quality: Quality,
  assets: boolean,
) {
  const low = quality === 'performance',
    palette = battlefieldPalette(battle.battlefield.biome);
  const meshes: Mesh[] = [],
    stone = pbr(scene, 'battlefield-layered-rock', palette.stone, 0, 0.96),
    bank = pbr(scene, 'battlefield-wet-bank', palette.soil, 0, 0.98),
    reed = pbr(scene, 'riverbank-reeds', '#73875a', 0, 0.97);
  reed.backFaceCulling = false;
  if (assets) {
    applySurface(stone, scene, 'rock', { mobile: low, strength: 0.68 });
    applySurface(bank, scene, 'soil', { mobile: low, strength: 0.65 });
  }
  const water = new ShaderMaterial(
    'shallow-moving-river',
    scene,
    { vertexSource: waterVertex, fragmentSource: waterFragment },
    {
      attributes: ['position'],
      uniforms: [
        'worldViewProjection',
        'time',
        'fogColor',
        'eye',
        'fogDensity',
      ],
    },
  );
  water.backFaceCulling = false;
  const batches = new Map<
    string,
    { data: Geometry; material: Mesh['material'] }
  >();
  const batch = (key: string, material: Mesh['material']) => {
    let value = batches.get(key);
    if (!value) {
      value = { data: geometry(), material };
      batches.set(key, value);
    }
    return value.data;
  };
  for (const [index, feature] of battle.terrain.entries()) {
    const x = (feature.x + feature.w / 2 - W / 2) * 0.1,
      z = (feature.y + feature.h / 2 - H / 2) * 0.1,
      width = feature.w * 0.1,
      depth = feature.h * 0.1,
      key = Math.floor(x / 48) + ',' + Math.floor(z / 48);
    if (feature.kind === 'hill') {
      const data = geometry(),
        segments = low ? 8 : 16,
        random = seeded(index * 941 + battle.mission * 37),
        phase = random() * 6,
        desert = battle.battlefield.biome === 'desert';
      for (let row = 0; row <= segments; row++)
        for (let col = 0; col <= segments; col++) {
          const u = col / segments,
            v = row / segments,
            edge = Math.min(u, v, 1 - u, 1 - v),
            envelope = Math.min(1, Math.max(0, edge * (desert ? 7 : 4.5))),
            ridge = desert
              ? 0.84 + Math.sin(u * 13 + v * 7 + phase) * 0.07
              : 0.66 +
                Math.sin(u * 8 + phase) * 0.17 +
                Math.sin(v * 11 - u * 4) * 0.1,
            y =
              0.045 +
              Math.pow(envelope, desert ? 0.5 : 0.75) * feature.height * ridge,
            shade =
              0.71 + (y / feature.height) * 0.26 + Math.sin(y * 2.3) * 0.04;
          data.positions.push(x + (u - 0.5) * width, y, z + (v - 0.5) * depth);
          data.uvs.push((u * width) / 4, (v * depth) / 4);
          data.colors.push(
            shade,
            shade * (desert ? 0.94 : 1),
            shade * (desert ? 0.84 : 0.94),
            1,
          );
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
      VertexData.ComputeNormals(data.positions, data.indices, data.normals, {
        useRightHandedSystem: true,
      });
      const mesh = makeMesh(
        scene,
        desert ? 'collidable-sandstone-mesa' : 'collidable-rocky-highland',
        data,
      );
      mesh.material = stone;
      mesh.metadata = { terrain: feature.kind, footprint: feature };
      meshes.push(mesh);
    } else if (feature.kind === 'water') {
      addBox(batch('water:' + key, water), x, 0.044, z, width, 0.012, depth);
      addShoreline(
        batch('bank:' + key, bank),
        batch('bank-stones:' + key, stone),
        batch('reeds:' + key, reed),
        x,
        z,
        width,
        depth,
        low,
        3721 + battle.mission * 71 + index * 283,
      );
    } else if (feature.kind === 'bridge') {
      const deck = batch('deck:' + key, materials.concrete),
        metal = batch('steel:' + key, materials.steel),
        vertical = depth > width;
      addBox(deck, x, 0.058, z, width, 0.1, depth);
      // Edge girders stop at the ends of the span; approaches stay flush.
      for (const side of [-1, 1])
        addBox(
          metal,
          x + (vertical ? side * (width / 2 - 0.14) : 0),
          0.105,
          z + (vertical ? 0 : side * (depth / 2 - 0.14)),
          vertical ? 0.2 : width,
          0.025,
          vertical ? depth : 0.2,
        );
      for (
        let along = -(vertical ? depth : width) / 2 + 1.5;
        along < (vertical ? depth : width) / 2;
        along += low ? 4 : 2.5
      ) {
        addBox(
          metal,
          x + (vertical ? 0 : along),
          0.114,
          z + (vertical ? along : 0),
          vertical ? width : 0.035,
          0.008,
          vertical ? 0.035 : depth,
        );
      }
      // Raised rails only occupy adjacent permanent water, never the deck or
      // its approaches. This gives bridges scale without inventing collision.
      for (const shore of battle.terrain) {
        if (shore.kind !== 'water') continue;
        const sx = (shore.x - W / 2) * 0.1,
          sz = (shore.y - H / 2) * 0.1,
          ex = sx + shore.w * 0.1,
          ez = sz + shore.h * 0.1,
          left = x - width / 2,
          right = x + width / 2,
          top = z - depth / 2,
          bottom = z + depth / 2;
        const guard = (
          alongX: boolean,
          fixed: number,
          start: number,
          end: number,
        ) => {
          start += 0.25;
          end -= 0.25;
          if (end - start < 1.5) return;
          const span = end - start,
            center = (start + end) / 2;
          for (const height of [0.25, 0.46])
            addBox(
              metal,
              alongX ? center : fixed,
              height,
              alongX ? fixed : center,
              alongX ? span : 0.065,
              0.055,
              alongX ? 0.065 : span,
            );
          const posts = Math.max(1, Math.ceil(span / (low ? 3.6 : 2.7)));
          for (let post = 0; post <= posts; post++) {
            const at = start + (span * post) / posts;
            addBox(
              metal,
              alongX ? at : fixed,
              0.24,
              alongX ? fixed : at,
              0.075,
              0.46,
              0.075,
            );
          }
        };
        if (ex <= left + 0.05 && left - ex <= 2.5)
          guard(false, ex - 0.18, Math.max(top, sz), Math.min(bottom, ez));
        if (sx >= right - 0.05 && sx - right <= 2.5)
          guard(false, sx + 0.18, Math.max(top, sz), Math.min(bottom, ez));
        if (ez <= top + 0.05 && top - ez <= 2.5)
          guard(true, ez - 0.18, Math.max(left, sx), Math.min(right, ex));
        if (sz >= bottom - 0.05 && sz - bottom <= 2.5)
          guard(true, sz + 0.18, Math.max(left, sx), Math.min(right, ex));
      }
    } else if (feature.kind === 'rail') {
      const ballast = batch('ballast:' + key, stone),
        metal = batch('steel:' + key, materials.steel),
        sleepers = batch('sleepers:' + key, materials.mud),
        vertical = depth > width,
        length = vertical ? depth : width;
      addBox(ballast, x, 0.016, z, width, 0.025, depth);
      for (const side of [-1, 1])
        addBox(
          metal,
          x + (vertical ? side * 0.82 : 0),
          0.065,
          z + (vertical ? 0 : side * 0.82),
          vertical ? 0.085 : width,
          0.07,
          vertical ? depth : 0.085,
        );
      for (
        let along = -length / 2 + 0.45;
        along < length / 2;
        along += low ? 1.8 : 1.15
      )
        addBox(
          sleepers,
          x + (vertical ? 0 : along),
          0.043,
          z + (vertical ? along : 0),
          vertical ? 2.55 : 0.24,
          0.045,
          vertical ? 0.24 : 2.55,
        );
    }
  }
  for (const [key, { data, material }] of batches) {
    const mesh = makeMesh(scene, 'battlefield-' + key, data);
    mesh.material = material;
    mesh.metadata = { terrainBatch: key };
    meshes.push(mesh);
  }
  stone.freeze();
  bank.freeze();
  reed.freeze();
  return {
    meshes,
    update(time: number) {
      water.setFloat('time', time);
      water.setColor3('fogColor', scene.fogColor);
      water.setFloat('fogDensity', scene.fogDensity);
      if (scene.activeCamera)
        water.setVector3('eye', scene.activeCamera.globalPosition);
    },
  };
}
