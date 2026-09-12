import {
  Mesh,
  PBRMaterial,
  Scene,
  ShaderMaterial,
  VertexData,
} from './babylon';
import { H, W, seeded, type Battle } from '../engine';
import { pbr, type Materials, type Quality } from './materials';
import { applySurface } from './surface-textures';

export function battlefieldPalette(biome: string) {
  const p =
    biome === 'highlands'
      ? [
          '#aab9b5',
          '#536d80',
          '#f1edd6',
          '#969f79',
          '#a3a18b',
          '#a4aaa0',
          '#a5b391',
          '#78916c',
        ]
      : [
          '#a5aaa5',
          '#485b68',
          '#fff0d3',
          '#b5b4a9',
          '#aeb3b1',
          '#acafa6',
          '#b9b99e',
          '#899071',
        ];
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
function makeMesh(scene: Scene, name: string, data: Geometry) {
  const mesh = new Mesh(name, scene),
    vertices = new VertexData();
  VertexData.ComputeNormals(data.positions, data.indices, data.normals, {
    useRightHandedSystem: true,
  });
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
// The outer ring is the exact ellipse used by simulation. Only interior height
// varies: asymmetric shoulders and several rocky ridges never enlarge collision.
function ellipseGeometry(
  x: number,
  z: number,
  width: number,
  depth: number,
  sides: number,
  rings: number,
  sample: (
    u: number,
    v: number,
    radius: number,
  ) => { height: number; color: number[] },
): Geometry {
  const data = geometry();
  const vertex = (u: number, v: number, radius: number) => {
    const value = sample(u, v, radius),
      px = x + (u * width) / 2,
      pz = z + (v * depth) / 2;
    data.positions.push(px, value.height, pz);
    data.colors.push(...value.color);
    data.uvs.push(px / 4, pz / 4);
  };
  vertex(0, 0, 0);
  for (let ring = 1; ring <= rings; ring++)
    for (let side = 0; side < sides; side++) {
      const radius = ring / rings,
        angle = (side * Math.PI * 2) / sides;
      vertex(Math.cos(angle) * radius, Math.sin(angle) * radius, radius);
      const current = 1 + (ring - 1) * sides + side,
        next = 1 + (ring - 1) * sides + ((side + 1) % sides);
      if (ring === 1) data.indices.push(0, next, current);
      else {
        const previous = current - sides,
          previousNext = next - sides;
        data.indices.push(
          previous,
          next,
          current,
          previous,
          previousNext,
          next,
        );
      }
    }
  return data;
}
const waterVertex = `precision highp float;attribute vec3 position;attribute vec4 color;uniform mat4 worldViewProjection;varying vec3 vPosition;varying vec4 vColor;void main(){vPosition=position;vColor=color;gl_Position=worldViewProjection*vec4(position,1.);}`;
const waterFragment = `precision highp float;
varying vec3 vPosition;varying vec4 vColor;uniform float time;uniform vec3 fogColor;uniform vec3 eye;uniform float fogDensity;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1.,0.)),f.x),mix(hash(i+vec2(0.,1.)),hash(i+vec2(1.,1.)),f.x),f.y);}
void main(){vec2 p=vPosition.xz;vec2 flow=vec2(time*.024,-time*.012);vec2 warp=vec2(noise(p*.067+flow),noise(p*.083-flow+vec2(8.3,2.7)))-.5;
float broad=noise(p*.115+warp*1.4+flow),detail=noise(p*vec2(.29,.17)+warp*.8-flow*.7);
float ripple=.5+.5*sin(dot(p,vec2(.53,.31))+warp.x*4.2+warp.y*2.8-time*.38);
float glint=smoothstep(.79,.98,ripple)*smoothstep(.4,.85,detail)*.032;
vec3 col=mix(vec3(.25,.38,.34),vec3(.39,.49,.40),broad*.6+detail*.15)+vec3(.65,.78,.73)*glint;
float fog=1.-exp(-pow(length(vPosition-eye)*fogDensity,2.));gl_FragColor=vec4(mix(col,fogColor,fog),vColor.a);}`;

/** Ford surfaces are deliberately flat and translucent. The sandy bed remains
 * visible through water, and a fading waterline communicates a shallow crossing
 * without a raised bank, railing, or any visual-only obstacle. */
export function createBattlefieldScenery(
  scene: Scene,
  battle: Battle,
  _materials: Materials,
  quality: Quality,
  assets: boolean,
) {
  const low = quality === 'performance',
    palette = battlefieldPalette(battle.battlefield.biome),
    meshes: Mesh[] = [],
    stone = pbr(scene, 'battlefield-layered-rock', palette.stone, 0, 0.96),
    bed = pbr(scene, 'ford-sandy-bottom', '#acb198', 0, 0.96);
  if (assets) {
    applySurface(stone, scene, 'rock', { mobile: low, strength: 0.68 });
    applySurface(bed, scene, 'soil', { mobile: low, strength: 0.34 });
  }
  bed.transparencyMode = PBRMaterial.MATERIAL_ALPHABLEND;
  const water = new ShaderMaterial(
    'shallow-fordable-water',
    scene,
    { vertexSource: waterVertex, fragmentSource: waterFragment },
    {
      attributes: ['position', 'color'],
      uniforms: [
        'worldViewProjection',
        'time',
        'fogColor',
        'eye',
        'fogDensity',
      ],
      needAlphaBlending: true,
    },
  );
  water.backFaceCulling = false;
  water.disableDepthWrite = true;
  for (const [index, feature] of battle.terrain.entries()) {
    const x = (feature.x + feature.w / 2 - W / 2) * 0.1,
      z = (feature.y + feature.h / 2 - H / 2) * 0.1,
      width = feature.w * 0.1,
      depth = feature.h * 0.1,
      sides = low ? 32 : 56;
    if (feature.kind === 'hill') {
      const phase =
        seeded(3143 + index * 941 + battle.mission * 37)() * Math.PI * 2;
      const data = ellipseGeometry(
        x,
        z,
        width,
        depth,
        sides,
        low ? 7 : 12,
        (u, v, radius) => {
          const shoulder =
              0.84 +
              Math.sin(u * 4.8 + v * 2.7 + phase) * 0.12 +
              Math.sin(v * 7.1 - u * 2.3) * 0.08,
            height =
              0.045 +
              Math.pow(Math.max(0, 1 - radius * radius), 1.32) *
                feature.height *
                shoulder,
            exposed = Math.min(1, (height / Math.max(1, feature.height)) * 1.4),
            band = 0.8 + Math.sin(height * 1.1 + u * 3) * 0.045;
          return {
            height,
            color: [
              band * (0.81 + exposed * 0.16),
              band * (0.94 + exposed * 0.03),
              band * (0.73 + exposed * 0.19),
              1,
            ],
          };
        },
      );
      const mesh = makeMesh(scene, 'collidable-rounded-highland', data);
      mesh.material = stone;
      mesh.metadata = { terrain: 'hill', footprint: feature, shape: 'ellipse' };
      meshes.push(mesh);
    } else if (feature.kind === 'water') {
      const bottom = ellipseGeometry(
        x,
        z,
        width,
        depth,
        sides,
        4,
        (u, v, radius) => {
          const fleck =
            0.88 +
            Math.sin(u * 18.1 + v * 7.3) * Math.sin(v * 17.7 - u * 3.1) * 0.035;
          return {
            height: 0.039,
            color: [
              fleck,
              fleck,
              fleck * 0.91,
              Math.min(0.93, (1 - radius) * 4),
            ],
          };
        },
      );
      const bottomMesh = makeMesh(scene, 'ford-visible-sandy-bed', bottom);
      bottomMesh.material = bed;
      bottomMesh.hasVertexAlpha = true;
      bottomMesh.metadata = {
        terrain: 'ford-bottom',
        footprint: feature,
        fordable: true,
      };
      meshes.push(bottomMesh);
      const surface = ellipseGeometry(
        x,
        z,
        width,
        depth,
        sides,
        5,
        (_u, _v, radius) => ({
          height: 0.059,
          color: [
            1,
            1,
            1,
            Math.pow(Math.max(0, 1 - radius * radius), 0.34) * 0.48,
          ],
        }),
      );
      const waterMesh = makeMesh(
        scene,
        'shallow-fordable-water-surface',
        surface,
      );
      waterMesh.material = water;
      waterMesh.hasVertexAlpha = true;
      waterMesh.receiveShadows = false;
      waterMesh.metadata = {
        terrain: 'water',
        footprint: feature,
        fordable: true,
      };
      meshes.push(waterMesh);
    }
  }
  stone.freeze();
  bed.freeze();
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
