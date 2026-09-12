import { assetUrl } from '../asset-url';
import { CreateBoxVertexData } from '@babylonjs/core/Meshes/Builders/boxBuilder.js';
import {
  Matrix,
  Color3,
  Color4,
  CubeTexture,
  DirectionalLight,
  HemisphericLight,
  Mesh,
  MeshBuilder,
  Scene,
  ShaderMaterial,
  ShadowGenerator,
  StandardMaterial,
  TransformNode,
  Vector3,
  VertexData,
  type Material,
} from './babylon';
import type { AbstractMesh } from '@babylonjs/core/Meshes/abstractMesh.js';
import { Battle, W, H, ENEMY_GATES, seeded, type Wall } from '../engine';
import { type Materials, type Quality, pbr, emissive } from './materials';
import { buildLivingCover, createNature, natureMaterials } from './nature';
import { applySurface } from './surface-textures';
import {
  battlefieldPalette,
  createBattlefieldScenery,
} from './battlefield-scenery';
export const UNIT = 0.1;
export const worldPosition = (x: number, y: number, height = 0) =>
  new Vector3((x - W / 2) * UNIT, height, (y - H / 2) * UNIT);
export const simulationPosition = (p: Vector3) => ({
  x: p.x / UNIT + W / 2,
  y: p.z / UNIT + H / 2,
});
export const heading = (angle: number) => Math.PI / 2 - angle;
export type World = {
  ground: Mesh;
  walls: Map<Wall, { solid: TransformNode; rubble: TransformNode }>;
  shadow: ShadowGenerator | null;
  sun: DirectionalLight;
  staticMeshes: Mesh[];
  nature: ReturnType<typeof createNature>;
  updateShadow(target: Vector3): void;
  updateDamage(): void;
};
const skyVertex = `precision highp float;attribute vec3 position;uniform mat4 worldViewProjection;varying vec3 vPosition;void main(){vPosition=position;gl_Position=worldViewProjection*vec4(position,1.);}`;
const skyFragment = `precision highp float;varying vec3 vPosition;uniform vec3 horizon;uniform vec3 zenith;uniform vec3 sunDirection;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1.,0.)),f.x),mix(hash(i+vec2(0.,1.)),hash(i+vec2(1.,1.)),f.x),f.y);}void main(){vec3 d=normalize(vPosition);float h=max(0.,d.y);vec3 col=mix(horizon,zenith,pow(h,.55));float cloud=noise(d.xz/(h+.18)*3.)*.6+noise(d.xz/(h+.18)*8.)*.3+noise(d.xz/(h+.18)*20.)*.1;col=mix(col,col*.55+vec3(.13),smoothstep(.42,.7,cloud)*smoothstep(.0,.18,h)*.65);float sun=pow(max(0.,dot(d,sunDirection)),300.);float glow=pow(max(0.,dot(d,sunDirection)),9.);col+=vec3(1.,.69,.35)*sun*2.5+vec3(.26,.14,.04)*glow;gl_FragColor=vec4(col,1.);}`;
type StaticBox = {
  name: string;
  size: [number, number, number];
  position: Vector3;
  rotation: Vector3;
  material: Material;
  tile?: number;
};
const pendingBoxes = new WeakMap<TransformNode, StaticBox[]>();
const unitBox = CreateBoxVertexData({ size: 1 });
// Keep architectural parts as plain transforms until the parent is complete.
// Creating/discarding tens of thousands of temporary Babylon meshes blocks the
// UI and retains their buffers in deferred scene notifications. These parts go
// straight into the same final material batches without changing their detail.
function box(
  _scene: Scene,
  name: string,
  size: [number, number, number],
  at: [number, number, number],
  material: Material,
  parent: TransformNode,
): StaticBox {
  const part: StaticBox = {
    name,
    size,
    position: new Vector3(...at),
    rotation: Vector3.Zero(),
    material,
  };
  let parts = pendingBoxes.get(parent);
  if (!parts) pendingBoxes.set(parent, (parts = []));
  parts.push(part);
  return part;
}
function flushBoxes(parent: TransformNode, chunks: boolean) {
  const parts = pendingBoxes.get(parent);
  if (!parts) return;
  pendingBoxes.delete(parent);
  const groups = new Map<string, StaticBox[]>();
  for (const part of parts) {
    const chunk = chunks
      ? Math.floor(part.position.x / 40) +
        ',' +
        Math.floor(part.position.z / 40)
      : 'all';
    const key = part.material.uniqueId + ':' + chunk;
    let group = groups.get(key);
    if (!group) groups.set(key, (group = []));
    group.push(part);
  }
  const basis = unitBox.positions!,
    baseNormals = unitBox.normals!,
    baseUV = unitBox.uvs!,
    baseIndices = unitBox.indices!,
    vertexCount = basis.length / 3,
    rotation = Matrix.Identity();
  for (const [key, group] of groups) {
    const positions = new Float32Array(group.length * basis.length),
      normals = new Float32Array(positions.length),
      uv = new Float32Array(group.length * baseUV.length),
      indices =
        group.length * vertexCount > 65535
          ? new Uint32Array(group.length * baseIndices.length)
          : new Uint16Array(group.length * baseIndices.length);
    for (let item = 0; item < group.length; item++) {
      const part = group[item],
        offset = item * basis.length;
      Matrix.RotationYawPitchRollToRef(
        part.rotation.y,
        part.rotation.x,
        part.rotation.z,
        rotation,
      );
      const transform = rotation.m;
      for (let v = 0; v < vertexCount; v++) {
        const i = v * 3,
          x = basis[i] * part.size[0],
          y = basis[i + 1] * part.size[1],
          z = basis[i + 2] * part.size[2],
          nx = baseNormals[i],
          ny = baseNormals[i + 1],
          nz = baseNormals[i + 2];
        positions[offset + i] =
          x * transform[0] +
          y * transform[4] +
          z * transform[8] +
          part.position.x;
        positions[offset + i + 1] =
          x * transform[1] +
          y * transform[5] +
          z * transform[9] +
          part.position.y;
        positions[offset + i + 2] =
          x * transform[2] +
          y * transform[6] +
          z * transform[10] +
          part.position.z;
        normals[offset + i] =
          nx * transform[0] + ny * transform[4] + nz * transform[8];
        normals[offset + i + 1] =
          nx * transform[1] + ny * transform[5] + nz * transform[9];
        normals[offset + i + 2] =
          nx * transform[2] + ny * transform[6] + nz * transform[10];
        const uvIndex = item * baseUV.length + v * 2;
        if (part.tile) {
          uv[uvIndex] =
            (Math.abs(nx) > 0.5 ? z + part.position.z : x + part.position.x) /
            part.tile;
          uv[uvIndex + 1] =
            (Math.abs(ny) > 0.5 ? z + part.position.z : y + part.position.y) /
            part.tile;
        } else {
          uv[uvIndex] = baseUV[v * 2];
          uv[uvIndex + 1] = baseUV[v * 2 + 1];
        }
      }
      for (let i = 0; i < baseIndices.length; i++)
        indices[item * baseIndices.length + i] =
          baseIndices[i] + item * vertexCount;
    }
    const mesh = new Mesh(group[0].name + '-batched', parent.getScene()),
      data = new VertexData();
    data.positions = positions;
    data.normals = normals;
    data.uvs = uv;
    data.indices = indices;
    data.applyToMesh(mesh);
    mesh.parent = parent;
    mesh.material = group[0].material;
    mesh.metadata = { staticChunk: key.slice(key.indexOf(':') + 1) };
  }
}
function mergeStatic(parent: TransformNode, chunks = false) {
  flushBoxes(parent, chunks);
  const groups = new Map<string, Mesh[]>();
  for (const child of parent.getChildMeshes(true)) {
    if (!(child instanceof Mesh) || !child.material) continue;
    const key = `${child.material.uniqueId}:${chunks ? (child.metadata?.staticChunk ?? Math.floor(child.position.x / 40) + ',' + Math.floor(child.position.z / 40)) : 'all'}`;
    const g = groups.get(key) || [];
    g.push(child);
    groups.set(key, g);
  }
  const result: Mesh[] = [];
  for (const list of groups.values()) {
    const vertexAlpha = list.some((mesh) => mesh.hasVertexAlpha);
    const mesh =
      list.length > 1
        ? Mesh.MergeMeshes(list, true, true, undefined, false, false)
        : list[0];
    if (mesh) {
      if (list.length > 1)
        mesh.bakeTransformIntoVertices(
          Matrix.Invert(parent.computeWorldMatrix(true)),
        );
      mesh.parent = parent;
      mesh.hasVertexAlpha = vertexAlpha;
      mesh.isPickable = false;
      mesh.receiveShadows = true;
      mesh.freezeWorldMatrix();
      result.push(mesh);
    }
  }
  return result;
}
// Box defaults stretch one image across every face. Metric UVs keep masonry,
// road aggregate and roofing the same apparent size on long and short surfaces.
function surfaceBox(
  scene: Scene,
  name: string,
  size: [number, number, number],
  at: [number, number, number],
  material: ReturnType<typeof pbr>,
  parent: TransformNode,
  tile = 3,
) {
  const part = box(scene, name, size, at, material, parent);
  part.tile = tile;
  return part;
}

// A feathered ground ring is visible at the wall foot even on the mobile
// budget. Its centre remains empty: aprons retain their concrete surface.
function contactRing(
  scene: Scene,
  parent: TransformNode,
  material: StandardMaterial,
  x: number,
  z: number,
  width: number,
  depth: number,
) {
  const positions: number[] = [],
    colors: number[] = [],
    indices: number[] = [];
  for (const padding of [-0.04, 0.25, 1.1]) {
    const halfX = width / 2 + padding,
      halfZ = depth / 2 + padding,
      bevel = Math.max(0.035, padding * 0.6);
    for (const [px, pz] of [
      [-halfX + bevel, -halfZ],
      [halfX - bevel, -halfZ],
      [halfX, -halfZ + bevel],
      [halfX, halfZ - bevel],
      [halfX - bevel, halfZ],
      [-halfX + bevel, halfZ],
      [-halfX, halfZ - bevel],
      [-halfX, -halfZ + bevel],
    ]) {
      positions.push(x + px, 0.071, z + pz);
      colors.push(1, 1, 1, padding < 0 ? 0.38 : padding < 1 ? 0.17 : 0);
    }
  }
  for (let ring = 0; ring < 2; ring++)
    for (let i = 0; i < 8; i++) {
      const a = ring * 8 + i,
        next = ring * 8 + ((i + 1) % 8);
      indices.push(a, next + 8, next, a, a + 8, next + 8);
    }
  const mesh = new Mesh('feathered-building-contact', scene),
    data = new VertexData();
  data.positions = positions;
  data.normals = positions.map((_, index) => (index % 3 === 1 ? 1 : 0));
  data.colors = colors;
  data.indices = indices;
  data.applyToMesh(mesh);
  mesh.material = material;
  mesh.parent = parent;
  mesh.hasVertexAlpha = true;
  mesh.metadata = {
    staticChunk: Math.floor(x / 40) + ',' + Math.floor(z / 40),
  };
}

function localSunShadows(
  scene: Scene,
  sun: DirectionalLight,
  shadow: ShadowGenerator | null,
  roofCeiling: number,
) {
  const forward = sun.direction.normalizeToNew(),
    right = Vector3.Cross(Vector3.Up(), forward).normalize(),
    up = Vector3.Cross(forward, right).normalize(),
    inverse = Matrix.Identity(),
    clip = Vector3.Zero(),
    far = Vector3.Zero(),
    point = Vector3.Zero(),
    localCasters: AbstractMesh[] = [];
  let centerX = 0,
    centerY = 0,
    halfX = 64,
    halfY = 64;
  const map = shadow?.getShadowMap();
  if (map) {
    // Keep the original list so runtime tank spawns/removals and destructible
    // wall state continue to work. Only the shadow pass receives the short list.
    map.getCustomRenderList = (_face, renderList, length) => {
      localCasters.length = 0;
      if (!renderList) return null;
      for (let i = 0; i < length; i++) {
        const mesh = renderList[i];
        if (!mesh.isEnabled() || !mesh.isVisible) continue;
        mesh.computeWorldMatrix();
        const bound = mesh.getBoundingInfo().boundingSphere,
          radius = bound.radiusWorld,
          center = bound.centerWorld;
        if (
          Math.abs(Vector3.Dot(center, right) - centerX) <= halfX + radius &&
          Math.abs(Vector3.Dot(center, up) - centerY) <= halfY + radius
        )
          localCasters.push(mesh);
      }
      return localCasters;
    };
    scene.onDisposeObservable.addOnce(() => {
      localCasters.length = 0;
    });
  }
  return (target: Vector3) => {
    const camera = scene.activeCamera;
    if (!camera) return;
    camera
      .getViewMatrix(true)
      .multiplyToRef(camera.getProjectionMatrix(true), inverse);
    inverse.invert();
    let minX = Infinity,
      maxX = -Infinity,
      minY = Infinity,
      maxY = -Infinity;
    // The camera matrix includes portrait aspect, both camera modes, zoom, and
    // recoil. Ground plus the highest roof bounds all visible solid receivers.
    for (const sx of [-1, 1])
      for (const sy of [-1, 1]) {
        clip.set(sx, sy, 1);
        Vector3.TransformCoordinatesToRef(clip, inverse, far);
        for (const elevation of [
          0,
          Math.min(roofCeiling, camera.globalPosition.y - 1),
        ]) {
          const t =
            (elevation - camera.globalPosition.y) /
            (far.y - camera.globalPosition.y);
          if (!Number.isFinite(t) || t <= 0) continue;
          Vector3.LerpToRef(camera.globalPosition, far, t, point);
          const px = Vector3.Dot(point, right),
            py = Vector3.Dot(point, up);
          minX = Math.min(minX, px);
          maxX = Math.max(maxX, px);
          minY = Math.min(minY, py);
          maxY = Math.max(maxY, py);
        }
      }
    if (!Number.isFinite(minX)) return;
    halfX = Math.max(24, Math.ceil(((maxX - minX) / 2 + 8) / 8) * 8);
    halfY = Math.max(24, Math.ceil(((maxY - minY) / 2 + 8) / 8) * 8);
    const resolution = map?.getSize().width ?? 1024,
      texelX = (2 * halfX) / resolution,
      texelY = (2 * halfY) / resolution;
    centerX = Math.round((minX + maxX) / 2 / texelX) * texelX;
    centerY = Math.round((minY + maxY) / 2 / texelY) * texelY;
    const depth = Vector3.Dot(target, forward) - 170;
    sun.position.set(
      right.x * centerX + up.x * centerY + forward.x * depth,
      right.y * centerX + up.y * centerY + forward.y * depth,
      right.z * centerX + up.z * centerY + forward.z * depth,
    );
    sun.orthoLeft = -halfX;
    sun.orthoRight = halfX;
    sun.orthoBottom = -halfY;
    sun.orthoTop = halfY;
  };
}
function* worldSteps(
  scene: Scene,
  b: Battle,
  m: Materials,
  quality: Quality = 'balanced',
  headless = false,
  assets = !headless,
): Generator<{ completed: number; total: number; label: string }, World, void> {
  let completed = 0;
  const total = b.roads.length + b.walls.length + 2;
  const progress = (label: string) => ({
    completed: ++completed,
    total,
    label,
  });
  const rand = seeded(379 + b.mission),
    staticRoot = new TransformNode('industrial-district', scene),
    wallViews = new Map<
      Wall,
      { solid: TransformNode; rubble: TransformNode }
    >();
  const naturalMaterials = natureMaterials(
    scene,
    assets,
    quality,
    b.battlefield.biome,
  );
  const palette = battlefieldPalette(b.battlefield.biome),
    rural = b.battlefield.biome === 'highlands';
  const themes = [palette.horizon, palette.zenith, palette.sun];
  scene.clearColor = Color4.FromHexString(themes[1] + 'ff');
  scene.fogMode = Scene.FOGMODE_EXP2;
  scene.fogDensity = 0.0035;
  scene.fogColor = Color3.FromHexString(themes[0]).scale(0.86);
  scene.ambientColor = new Color3(0.1, 0.12, 0.14);
  const ambient = new HemisphericLight(
    'overcast-sky-light',
    new Vector3(0.2, 1, 0.1),
    scene,
  );
  ambient.intensity = 0.58;
  ambient.diffuse = new Color3(0.8, 0.88, 1);
  ambient.groundColor = new Color3(0.25, 0.23, 0.19);
  const sun = new DirectionalLight(
    'late-afternoon-sun',
    new Vector3(0.55, -1, 0.72),
    scene,
  );
  sun.position.set(-110, 150, -110);
  sun.diffuse = Color3.FromHexString(themes[2]);
  // A broad daylight key preserves scanned surface colour instead of clipping it.
  sun.intensity = 2.05;
  sun.autoUpdateExtends = false;
  sun.orthoLeft = -(W + H) * UNIT * 0.48;
  sun.orthoRight = (W + H) * UNIT * 0.48;
  sun.orthoTop = (W + H) * UNIT * 0.4;
  sun.orthoBottom = -(W + H) * UNIT * 0.4;
  sun.shadowMinZ = 1;
  sun.shadowMaxZ = 350;
  let shadow: ShadowGenerator | null = null;
  if (!headless && quality !== 'performance') {
    shadow = new ShadowGenerator(quality === 'cinematic' ? 2048 : 1024, sun);
    shadow.usePercentageCloserFiltering = true;
    shadow.filteringQuality =
      quality === 'cinematic'
        ? ShadowGenerator.QUALITY_HIGH
        : ShadowGenerator.QUALITY_LOW;
    shadow.bias = 0.00045;
    shadow.normalBias = 0.035;
    shadow.darkness = 0.12;
  }
  const updateShadow = localSunShadows(
    scene,
    sun,
    shadow,
    Math.max(10, ...b.walls.map((w) => (w.height ?? 2) + 3)),
  );
  if (!headless) {
    scene.environmentTexture = CubeTexture.CreateFromPrefilteredData(
      assetUrl('/environment.env'),
      scene,
    );
    scene.environmentIntensity = 0.58;
    const sky = MeshBuilder.CreateSphere(
      'atmospheric-sky',
      { diameter: 900, segments: 24, sideOrientation: Mesh.BACKSIDE },
      scene,
    );
    const skyMat = new ShaderMaterial(
      'atmospheric-scattering',
      scene,
      { vertexSource: skyVertex, fragmentSource: skyFragment },
      {
        attributes: ['position'],
        uniforms: ['worldViewProjection', 'horizon', 'zenith', 'sunDirection'],
      },
    );
    skyMat.setColor3('horizon', Color3.FromHexString(themes[0]));
    skyMat.setColor3('zenith', Color3.FromHexString(themes[1]));
    skyMat.setVector3('sunDirection', sun.direction.negate().normalize());
    skyMat.backFaceCulling = false;
    skyMat.disableDepthWrite = true;
    sky.material = skyMat;
    sky.infiniteDistance = true;
    sky.isPickable = false;
  }
  const ground = MeshBuilder.CreateGround(
    'battlefield-ground',
    { width: W * UNIT + 140, height: H * UNIT + 140, subdivisions: 1 },
    scene,
  );
  ground.material = rural ? naturalMaterials.soil : m.ground;
  ground.receiveShadows = true;
  ground.isPickable = true;
  const groundUV = ground.getVerticesData('uv')!;
  for (let i = 0; i < groundUV.length; i += 2) {
    groundUV[i] *= (W * UNIT + 140) / (rural ? 10 : 100);
    groundUV[i + 1] *= (H * UNIT + 140) / (rural ? 10 : 100);
  }
  // This material is shared with the 60 m hangar. Resize UVs, not its textures.
  ground.setVerticesData('uv', groundUV);
  const asphalt = pbr(scene, 'wet-road', palette.road, 0.02, 0.9),
    puddle = pbr(scene, 'shallow-puddles', '#303b40', 0.12, 0.18),
    windowMat = pbr(scene, 'abandoned-windows', '#243b44', 0.04, 0.2),
    windowDust = pbr(scene, 'dusty-window-glass', '#415456', 0.02, 0.46),
    roof = pbr(scene, 'warehouse-roof', '#919493', 0.62, 0.63),
    roofFelt = pbr(scene, 'office-roof-felt', '#676863', 0.03, 0.93),
    facadeTrim = pbr(scene, 'aged-limestone-trim', '#b4b3a7', 0.03, 0.88),
    shutter = pbr(scene, 'zinc-shutter-panels', '#6e7a78', 0.55, 0.66),
    grime = pbr(scene, 'damp-building-plinth', '#51574c', 0, 0.98),
    tar = pbr(scene, 'sealed-asphalt-fissures', '#222725', 0.01, 0.8),
    roadPaint = pbr(scene, 'worn-road-lines', '#c4bd9b', 0.03, 0.94);
  const contactShade = new StandardMaterial('soft-building-occlusion', scene);
  contactShade.disableLighting = true;
  contactShade.emissiveColor = new Color3(0.065, 0.076, 0.079);
  contactShade.specularColor = Color3.Black();
  contactShade.transparencyMode = StandardMaterial.MATERIAL_ALPHABLEND;
  contactShade.backFaceCulling = true;
  if (assets) {
    applySurface(asphalt, scene, rural ? 'soil' : 'asphalt', {
      repeat: 1,
      mobile: quality === 'performance',
    });
    applySurface(roof, scene, 'roof', {
      repeat: 1,
      mobile: quality === 'performance',
    });
    applySurface(roofFelt, scene, 'asphalt', {
      repeat: 1,
      mobile: quality === 'performance',
      strength: 0.45,
    });
    applySurface(facadeTrim, scene, 'concrete', {
      repeat: 1,
      mobile: quality === 'performance',
      strength: 0.45,
    });
    applySurface(shutter, scene, 'paintedMetal', {
      repeat: 1,
      mobile: quality === 'performance',
      strength: 0.45,
    });
  }
  const hazardPaint = pbr(
    scene,
    'perimeter-warning-yellow',
    '#e7b34d',
    0.05,
    0.8,
  );
  const perimeterMetal = pbr(
    scene,
    'perimeter-matte-armor',
    '#444b44',
    0.3,
    0.78,
  );
  const perimeterReflector = emissive(
    scene,
    'perimeter-steady-reflector',
    '#eab570',
    0.65,
  );
  const stamp = (
    name: string,
    x: number,
    y: number,
    w: number,
    h: number,
    material: typeof asphalt,
    elevation = 0.026,
  ) => {
    const p = worldPosition(x + w / 2, y + h / 2, elevation);
    return surfaceBox(
      scene,
      name,
      [w * UNIT, 0.012, h * UNIT],
      [p.x, p.y, p.z],
      material,
      staticRoot,
      5,
    );
  };
  yield progress('地表与光照');
  // A connected street network, intersections, crosswalks and loading aprons.
  for (const road of b.roads) {
    stamp('street-asphalt', road.x, road.y, road.w, road.h, asphalt);
    const vertical = road.h > road.w;
    const length = vertical ? road.h : road.w;
    // Flush shoulders and drains convey scale without creating unseen obstacles.
    for (const side of rural ? [] : [0, 1]) {
      stamp(
        'concrete-road-gutter',
        road.x + (vertical ? side * (road.w - 3) : 0),
        road.y + (vertical ? 0 : side * (road.h - 3)),
        vertical ? 3 : road.w,
        vertical ? road.h : 3,
        m.concrete,
        0.036,
      );
      for (let t = 85; t < length; t += 155) {
        const dx = road.x + (vertical ? (side ? road.w - 9 : 4) : t),
          dy = road.y + (vertical ? t : side ? road.h - 9 : 4);
        stamp(
          'storm-drain-recess',
          dx,
          dy,
          vertical ? 5 : 11,
          vertical ? 11 : 5,
          tar,
          0.043,
        );
        for (let rib = 0; rib < 5; rib++)
          stamp(
            'storm-drain-grating',
            dx + (vertical ? 0 : rib * 2.2),
            dy + (vertical ? rib * 2.2 : 0),
            vertical ? 5 : 0.7,
            vertical ? 0.7 : 5,
            m.steel,
            0.049,
          );
      }
    }
    for (let t = 24; !rural && t < length; t += 58) {
      const x = vertical ? road.x + road.w / 2 : road.x + t;
      const y = vertical ? road.y + t : road.y + road.h / 2;
      if (
        b.roads.some(
          (other) =>
            other !== road &&
            x > other.x - 20 &&
            x < other.x + other.w + 20 &&
            y > other.y - 20 &&
            y < other.y + other.h + 20,
        )
      )
        continue;
      stamp(
        'faded-center-line',
        x,
        y,
        vertical ? 1.4 : 24,
        vertical ? 24 : 1.4,
        roadPaint,
        0.045,
      );
    }
    // Cast-iron inspection covers and the cut concrete surrounding them remain
    // flush: their readable circular scale never invents a gameplay obstacle.
    for (
      let t = 160;
      !rural && t < length;
      t += quality === 'performance' ? 860 : 430
    ) {
      const at = worldPosition(
        road.x + (vertical ? road.w * 0.36 : t),
        road.y + (vertical ? t : road.h * 0.36),
        0.061,
      );
      surfaceBox(
        scene,
        'utility-cover-road-repair',
        [1.55, 0.018, 1.55],
        [at.x, 0.045, at.z],
        grime,
        staticRoot,
        2,
      );
      const cover = MeshBuilder.CreateCylinder(
        'cast-iron-street-cover',
        {
          diameter: 1.08,
          height: 0.035,
          tessellation: quality === 'performance' ? 12 : 20,
        },
        scene,
      );
      cover.position.copyFrom(at);
      cover.material = shutter;
      cover.parent = staticRoot;
      for (const side of [-1, 1])
        box(
          scene,
          'inspection-cover-lifting-slot',
          [0.22, 0.008, 0.07],
          [at.x + side * 0.27, 0.082, at.z],
          tar,
          staticRoot,
        );
      for (let rib = -2; rib <= 2; rib++)
        box(
          scene,
          'inspection-cover-rib',
          [0.65, 0.011, 0.027],
          [at.x, 0.086, at.z + rib * 0.135],
          m.steel,
          staticRoot,
        );
    }
    yield progress('道路网络');
  }
  for (const vertical of b.roads.filter((r) => !rural && r.h > r.w)) {
    for (const horizontal of b.roads.filter((r) => r.w > r.h)) {
      for (const side of [-1, 1]) {
        for (let i = 0; i < 8; i++)
          stamp(
            'zebra-crossing',
            vertical.x + 12 + i * 14,
            horizontal.y + (side < 0 ? -28 : horizontal.h + 8),
            7,
            20,
            roadPaint,
            0.045,
          );
      }
    }
  }
  for (const w of b.walls.filter(
    (v) => v.kind === 'warehouse' || v.kind === 'office',
  )) {
    stamp(
      'concrete-building-apron',
      w.x - 12,
      w.y - 12,
      w.w + 24,
      w.h + 24,
      m.concrete,
      0.05,
    );
    const centre = worldPosition(w.x + w.w / 2, w.y + w.h / 2);
    contactRing(
      scene,
      staticRoot,
      contactShade,
      centre.x,
      centre.z,
      w.w * UNIT,
      w.h * UNIT,
    );
    // Expansion joints terminate at the real wall line, leaving the sidewalk
    // at street level so tanks can still enter every marked service alley.
    for (let x = w.x - 10; x < w.x + w.w + 10; x += 32)
      for (const side of [-1, 1])
        stamp(
          'apron-concrete-expansion-joint',
          x,
          side < 0 ? w.y - 11 : w.y + w.h,
          0.22,
          11,
          grime,
          0.064,
        );
    for (let y = w.y; y < w.y + w.h; y += 32)
      for (const side of [-1, 1])
        stamp(
          'apron-concrete-expansion-joint',
          side < 0 ? w.x - 11 : w.x + w.w,
          y,
          11,
          0.22,
          grime,
          0.064,
        );
    for (let x = w.x; x < w.x + w.w - 20; x += 35) {
      stamp('loading-bay-line', x, w.y + w.h + 17, 1.2, 27, roadPaint, 0.05);
      stamp('loading-bay-stop', x, w.y + w.h + 44, 30, 1.2, roadPaint, 0.05);
    }
  }
  for (let i = 0; i < (quality === 'performance' ? 16 : 40); i++) {
    const road = b.roads[i % b.roads.length];
    const x = road.x + rand() * road.w,
      y = road.y + rand() * road.h;
    const center = worldPosition(x, y, 0.043),
      radiusX = Math.min(1.5 + rand() * 2.3, road.w * UNIT * 0.3),
      radiusZ = Math.min(0.6 + rand() * 1.1, road.h * UNIT * 0.3),
      positions = [center.x, center.y, center.z],
      uvs = [center.x / 4, center.z / 4],
      indices: number[] = [];
    for (let vertex = 0; vertex < 9; vertex++) {
      const angle = (vertex / 9) * Math.PI * 2,
        roughEdge = 0.74 + rand() * 0.26,
        px = Math.max(
          (road.x - W / 2) * UNIT,
          Math.min(
            (road.x + road.w - W / 2) * UNIT,
            center.x + Math.cos(angle) * radiusX * roughEdge,
          ),
        ),
        pz = Math.max(
          (road.y - H / 2) * UNIT,
          Math.min(
            (road.y + road.h - H / 2) * UNIT,
            center.z + Math.sin(angle) * radiusZ * roughEdge,
          ),
        );
      positions.push(px, center.y, pz);
      uvs.push(px / 4, pz / 4);
      indices.push(0, vertex + 1, ((vertex + 1) % 9) + 1);
    }
    const patch = new Mesh('irregular-road-repair', scene),
      vertices = new VertexData();
    vertices.positions = positions;
    vertices.indices = indices;
    vertices.normals = Array.from({ length: positions.length }, (_, at) =>
      at % 3 === 1 ? 1 : 0,
    );
    vertices.uvs = uvs;
    vertices.applyToMesh(patch);
    patch.material = i % 5 === 0 ? puddle : grime;
    patch.parent = staticRoot;
    // Thin wandering tar repairs break up the broad uniform road plane.
    for (
      let segment = 0;
      segment < (quality === 'performance' ? 2 : 4);
      segment++
    ) {
      const crack = stamp(
        'asphalt-repaired-crack',
        x + segment * 8,
        y + Math.sin(segment * 1.7 + i) * 4,
        8.5,
        0.45,
        tar,
        0.048,
      );
      crack.rotation.y = (rand() - 0.5) * 0.7;
    }
  }
  // The industrial skyline is outside the playable perimeter, never invisible cover.
  for (let i = 0; !rural && i < 13; i++) {
    const x = -140 + i * 23,
      z = (-H * UNIT) / 2 - 20;
    const height = 9 + rand() * 14;
    box(
      scene,
      'distant-industrial-block',
      [15, height, 18],
      [x, height / 2, z],
      m.concrete,
      staticRoot,
    );
    box(
      scene,
      'distant-roof',
      [15.5, 0.3, 18.5],
      [x, height, z],
      roof,
      staticRoot,
    );
  }
  // Rail spur, sleepers and perimeter curbs establish a usable district boundary.
  for (const x of rural ? [] : [(-W * UNIT) / 2 - 5, (-W * UNIT) / 2 - 7])
    box(
      scene,
      'rail-spur',
      [0.13, 0.1, H * UNIT],
      [x, 0.1, 0],
      m.steel,
      staticRoot,
    );
  for (let z = (-H * UNIT) / 2; !rural && z < (H * UNIT) / 2; z += 2)
    box(
      scene,
      'rail-sleeper',
      [3.8, 0.12, 0.3],
      [(-W * UNIT) / 2 - 6, 0.05, z],
      m.steel,
      staticRoot,
    );
  for (const side of [-1, 1]) {
    box(
      scene,
      'perimeter-curb',
      [0.6, 0.3, H * UNIT],
      [side * ((W * UNIT) / 2 + 0.3), 0.15, 0],
      m.concrete,
      staticRoot,
    );
  }
  const damageViews = new Map<
    Wall,
    { nodes: TransformNode[]; stage: number }
  >();
  const registerWall = (
    wall: Wall,
    solid: TransformNode,
    rubble: TransformNode,
  ) => {
    wallViews.set(wall, { solid, rubble });
    if (
      !Number.isFinite(wall.maxHp) ||
      wall.maxHp <= 0 ||
      wall.kind === 'tree' ||
      wall.kind === 'hedge'
    )
      return;
    const width = wall.w * UNIT,
      depth = wall.h * UNIT,
      height = wall.height ?? 1.65,
      random = seeded(Math.floor(wall.x * 31 + wall.y * 17)),
      nodes: TransformNode[] = [];
    for (let stage = 0; stage < 2; stage++) {
      const node = new TransformNode('damage-stage-' + (stage + 1), scene);
      node.position.copyFrom(solid.position);
      node.metadata = { damageStage: stage + 1 };
      // Every stage is built once. Scorch and fractured edges sit just outside
      // each true facade; no visual hole appears while the building collides.
      for (const acrossX of [true, false])
        for (const side of [-1, 1]) {
          const span = acrossX ? width : depth,
            edge = (acrossX ? depth : width) / 2 + 0.05;
          for (
            let mark = 0;
            mark < (quality === 'performance' ? 2 : 4);
            mark++
          ) {
            const at = (random() - 0.5) * span * 0.78,
              y = height * (0.18 + random() * 0.64),
              reach = Math.min(span * 0.25, 0.7 + random() * (stage + 1));
            const scar = box(
              scene,
              'shell-scorched-facade',
              acrossX
                ? [reach, reach * 0.65, 0.018]
                : [0.018, reach * 0.65, reach],
              acrossX ? [at, y, side * edge] : [side * edge, y, at],
              m.rubber,
              node,
            );
            if (acrossX) scar.rotation.z = (random() - 0.5) * 0.5;
            else scar.rotation.x = (random() - 0.5) * 0.5;
            for (let branch = 0; branch < 2; branch++) {
              const crack = box(
                scene,
                'fresh-impact-fracture',
                acrossX
                  ? [0.045, reach * 1.9, 0.026]
                  : [0.026, reach * 1.9, 0.045],
                acrossX
                  ? [at + branch * 0.15, y, side * (edge + 0.02)]
                  : [side * (edge + 0.02), y, at + branch * 0.15],
                m.rubber,
                node,
              );
              if (acrossX) crack.rotation.z = (branch ? 1 : -1) * 0.48;
              else crack.rotation.x = (branch ? 1 : -1) * 0.48;
            }
          }
        }
      mergeStatic(node);
      node.setEnabled(false);
      nodes.push(node);
    }
    if (
      wall.kind === 'office' ||
      wall.kind === 'warehouse' ||
      wall.kind === 'container'
    ) {
      // Low rubble permits travel through a destroyed footprint. The slab and
      // torn beams preserve the scale of a collapsed building without leaving
      // tall walls that would imply collision after the engine releases it.
      surfaceBox(
        scene,
        'collapsed-building-foundation',
        [width * 0.97, 0.08, depth * 0.97],
        [0, 0.04, 0],
        grime,
        rubble,
      );
      const count = Math.min(
        quality === 'performance' ? 14 : 28,
        Math.ceil((width + depth) * 0.7),
      );
      for (let piece = 0; piece < count; piece++) {
        const chunk = box(
          scene,
          'collapsed-building-debris',
          [
            0.45 + random() * 1.1,
            0.13 + random() * 0.24,
            0.35 + random() * 0.8,
          ],
          [
            (random() - 0.5) * width * 0.93,
            0.13,
            (random() - 0.5) * depth * 0.93,
          ],
          piece % 4 === 0 ? m.steel : grime,
          rubble,
        );
        chunk.rotation.set(random() * 0.2, random() * Math.PI, random() * 0.2);
      }
      mergeStatic(rubble);
    }
    damageViews.set(wall, { nodes, stage: -1 });
  };
  const updateDamage = () => {
    for (const [wall, view] of wallViews) {
      const intact = wall.hp > 0;
      if (view.solid.isEnabled() !== intact) view.solid.setEnabled(intact);
      if (view.rubble.isEnabled() === intact) view.rubble.setEnabled(!intact);
      const damage = damageViews.get(wall);
      if (!damage) continue;
      const ratio = wall.hp / wall.maxHp,
        stage = !intact ? 0 : ratio <= 0.35 ? 2 : ratio <= 0.75 ? 1 : 0;
      if (stage === damage.stage) continue;
      damage.stage = stage;
      view.solid.metadata = { ...view.solid.metadata, damageStage: stage };
      for (let index = 0; index < damage.nodes.length; index++)
        damage.nodes[index].setEnabled(stage > index);
    }
  };
  for (const w of b.walls) {
    const solid = new TransformNode('cover-' + wallViews.size, scene),
      rubble = new TransformNode('destroyed-cover-' + wallViews.size, scene);
    const center = worldPosition(w.x + w.w / 2, w.y + w.h / 2),
      width = w.w * UNIT,
      depth = w.h * UNIT;
    solid.position.copyFrom(center);
    rubble.position.copyFrom(center);
    const height = w.height ?? (w.steel ? 2.5 : 1.65);
    if (w.kind === 'hill' || w.kind === 'water') {
      solid.metadata = { terrain: w.kind };
      rubble.setEnabled(false);
      registerWall(w, solid, rubble);
      yield progress('山地与水域');
      continue;
    }
    if (w.kind === 'boundary') {
      const horizontal = width > depth,
        length = horizontal ? width : depth;
      box(
        scene,
        'perimeter-solid-concrete',
        [width, height, depth],
        [0, height / 2, 0],
        m.concrete,
        solid,
      );
      box(
        scene,
        'perimeter-armored-cap',
        [width, 0.28, depth],
        [0, height + 0.14, 0],
        perimeterMetal,
        solid,
      );
      const facing = horizontal
        ? center.z < 0
          ? 1
          : -1
        : center.x < 0
          ? 1
          : -1;
      for (let at = -length / 2 + 1.2; at < length / 2; at += 2.8) {
        const stripe = box(
          scene,
          'yellow-black-boundary-stripe',
          [1.2, 1.05, 0.035],
          horizontal
            ? [at, 1.65, facing * (depth / 2 + 0.025)]
            : [facing * (width / 2 + 0.025), 1.65, at],
          hazardPaint,
          solid,
        );
        stripe.rotation.y = horizontal ? 0 : Math.PI / 2;
        stripe.rotation.z = -0.4;
      }
      for (let at = -length / 2 + 4; at < length / 2; at += 9) {
        box(
          scene,
          'perimeter-reinforcing-buttress',
          horizontal
            ? [0.45, height + 0.2, depth + 0.16]
            : [width + 0.16, height + 0.2, 0.45],
          horizontal ? [at, height / 2, 0] : [0, height / 2, at],
          perimeterMetal,
          solid,
        );
        box(
          scene,
          'perimeter-amber-reflector',
          [0.38, 0.16, 0.38],
          horizontal ? [at, height + 0.32, 0] : [0, height + 0.32, at],
          perimeterReflector,
          solid,
        );
      }
      for (const mesh of mergeStatic(solid)) {
        // Paint and tiny reflectors do not cast unstable subpixel shadows.
        mesh.receiveShadows =
          mesh.material === m.concrete || mesh.material === perimeterMetal;
        if (mesh.receiveShadows) shadow?.addShadowCaster(mesh);
      }
      rubble.setEnabled(false);
      registerWall(w, solid, rubble);
      yield progress('建筑与掩体');
      continue;
    }
    if (w.kind === 'tree' || w.kind === 'hedge') {
      buildLivingCover(
        scene,
        w,
        solid,
        rubble,
        naturalMaterials,
        quality,
        wallViews.size + b.mission,
        b.battlefield.biome,
      );
      for (const mesh of mergeStatic(solid)) shadow?.addShadowCaster(mesh);
      mergeStatic(rubble);
      rubble.setEnabled(false);
      registerWall(w, solid, rubble);
      yield progress('建筑与掩体');
      continue;
    }
    if (w.kind === 'warehouse' || w.kind === 'office') {
      const office = w.kind === 'office';
      const facade = office ? m.concrete : m.brick;
      const architecture =
        ((Math.round(w.x * 13 + w.y * 7) ^ (b.mission * 31)) >>> 0) % 3;
      solid.metadata = {
        architecture: office
          ? ['terraced-office', 'brick-service-office', 'rooflight-office'][
              architecture
            ]
          : ['multi-span-workshop', 'northlight-factory', 'monitor-warehouse'][
              architecture
            ],
      };
      // Solid interior backing sits behind the facade: panes really sit in
      // shaded recesses, while the architectural footprint remains collision.
      surfaceBox(
        scene,
        office ? 'office-interior-core' : 'warehouse-interior-core',
        [width - 0.4, height, depth - 0.4],
        [0, height / 2, 0],
        facade,
        solid,
      );
      surfaceBox(
        scene,
        'weathered-building-foundation',
        [width, 0.44, depth],
        [0, 0.22, 0],
        grime,
        solid,
      );
      for (const acrossX of [true, false]) {
        const span = acrossX ? width : depth,
          halfDepth = (acrossX ? depth : width) / 2;
        for (const side of [-1, 1]) {
          const face = (
            name: string,
            length: number,
            tall: number,
            thickness: number,
            at: number,
            y: number,
            inset: number,
            material: ReturnType<typeof pbr>,
          ) =>
            surfaceBox(
              scene,
              name,
              acrossX ? [length, tall, thickness] : [thickness, tall, length],
              acrossX
                ? [at, y, side * (halfDepth + inset)]
                : [side * (halfDepth + inset), y, at],
              material,
              solid,
            );
          if (office) {
            const bays = Math.max(
                1,
                Math.floor(
                  span /
                    (quality === 'performance'
                      ? 3.9
                      : architecture === 1
                        ? 2.7
                        : 2.15),
                ),
              ),
              pitch = span / bays,
              floors = Math.max(1, Math.floor(height / 2.45)),
              storey = height / floors;
            for (let floor = 0; floor < floors; floor++) {
              const bottom = floor * storey;
              face(
                'office-spandrel-band',
                span,
                0.73,
                0.22,
                0,
                bottom + 0.365,
                -0.11,
                architecture === 1 && floor > 0 ? m.brick : facade,
              );
              face(
                'cast-concrete-floor-edge',
                span,
                0.16,
                0.27,
                0,
                bottom + 0.72,
                -0.015,
                facadeTrim,
              );
              for (let bay = 0; bay < bays; bay++) {
                const at = -span / 2 + (bay + 0.5) * pitch,
                  windowHeight = storey - 1.0,
                  centerY = bottom + 0.82 + windowHeight / 2;
                face(
                  'deep-window-reveal',
                  pitch - 0.29,
                  windowHeight + 0.14,
                  0.06,
                  at,
                  centerY,
                  -0.145,
                  m.rubber,
                );
                face(
                  'recessed-office-window',
                  pitch - 0.44,
                  windowHeight,
                  0.032,
                  at,
                  centerY,
                  -0.109,
                  (bay + floor + wallViews.size) % 4 === 0
                    ? windowDust
                    : windowMat,
                );
                face(
                  'window-stone-sill',
                  pitch - 0.21,
                  0.13,
                  0.33,
                  at,
                  bottom + 0.76,
                  -0.005,
                  facadeTrim,
                );
                face(
                  'window-upper-lintel',
                  pitch,
                  0.23,
                  0.2,
                  at,
                  bottom + storey - 0.115,
                  -0.1,
                  facade,
                );
                face(
                  'window-vertical-mullion',
                  0.055,
                  windowHeight,
                  0.07,
                  at,
                  centerY,
                  -0.068,
                  shutter,
                );
                if (quality !== 'performance')
                  face(
                    'window-transom-bar',
                    pitch - 0.43,
                    0.05,
                    0.07,
                    at,
                    centerY + windowHeight * 0.18,
                    -0.068,
                    shutter,
                  );
              }
            }
            for (let bay = 0; bay <= bays; bay++)
              face(
                'masonry-facade-pier',
                0.26,
                height,
                0.23,
                Math.max(
                  -span / 2 + 0.13,
                  Math.min(span / 2 - 0.13, -span / 2 + bay * pitch),
                ),
                height / 2,
                -0.115,
                facade,
              );
            if (acrossX && side === -1) {
              face(
                'office-entrance-reveal',
                1.6,
                2.3,
                0.04,
                0,
                1.15,
                0.083,
                m.rubber,
              );
              face(
                'office-steel-door',
                1.37,
                2.12,
                0.035,
                0,
                1.13,
                0.109,
                shutter,
              );
              face(
                'office-door-glazing',
                0.92,
                0.72,
                0.036,
                0,
                1.57,
                0.132,
                windowMat,
              );
              face(
                'office-door-push-bar',
                0.9,
                0.055,
                0.08,
                0,
                0.99,
                0.17,
                m.edges,
              );
              face(
                'office-entry-weatherhood',
                2.1,
                0.12,
                0.62,
                0,
                2.4,
                0.2,
                roof,
              );
            }
          } else if (acrossX) {
            const doorWidth = Math.min(4.6, width * 0.66),
              wing = (span - doorWidth) / 2,
              lintelHeight = height - 2.9;
            for (const edge of [-1, 1]) {
              face(
                'warehouse-brick-door-wing',
                wing,
                height,
                0.21,
                edge * (doorWidth / 2 + wing / 2),
                height / 2,
                -0.105,
                facade,
              );
              face(
                'loading-portal-jamb',
                0.19,
                2.92,
                0.32,
                edge * (doorWidth / 2 - 0.08),
                1.46,
                -0.02,
                facadeTrim,
              );
            }
            face(
              'warehouse-brick-lintel',
              doorWidth,
              lintelHeight,
              0.21,
              0,
              2.9 + lintelHeight / 2,
              -0.105,
              facade,
            );
            face(
              'loading-door-dark-reveal',
              doorWidth - 0.3,
              2.82,
              0.04,
              0,
              1.44,
              -0.144,
              m.rubber,
            );
            face(
              'recessed-loading-shutter',
              doorWidth - 0.43,
              2.7,
              0.05,
              0,
              1.42,
              -0.108,
              shutter,
            );
            for (
              let rib = 0.3;
              rib < 2.75;
              rib += quality === 'performance' ? 0.43 : 0.24
            )
              face(
                'shutter-rolled-steel-seam',
                doorWidth - 0.44,
                0.036,
                0.045,
                0,
                rib,
                -0.064,
                m.steel,
              );
            face(
              'loading-canopy',
              doorWidth + 0.35,
              0.13,
              0.84,
              0,
              3.05,
              0.26,
              roof,
            );
            face(
              'warehouse-clerestory-recess',
              width * 0.73,
              0.46,
              0.04,
              0,
              height - 0.41,
              0.065,
              m.rubber,
            );
            face(
              'warehouse-clerestory-glazing',
              width * 0.71,
              0.35,
              0.032,
              0,
              height - 0.41,
              0.091,
              windowDust,
            );
            for (
              let mullion = -width * 0.32;
              mullion < width * 0.35;
              mullion += 1.1
            )
              face(
                'clerestory-steel-mullion',
                0.055,
                0.39,
                0.075,
                mullion,
                height - 0.41,
                0.111,
                shutter,
              );
          } else {
            face(
              'warehouse-side-brickwork',
              span,
              height,
              0.2,
              0,
              height / 2,
              -0.1,
              facade,
            );
            for (
              let pilaster = -span / 2 + 0.14;
              pilaster < span / 2;
              pilaster += 3.1
            )
              face(
                'warehouse-structural-pilaster',
                0.24,
                height,
                0.29,
                pilaster,
                height / 2,
                -0.005,
                facadeTrim,
              );
            face(
              'warehouse-side-damp-course',
              span,
              0.29,
              0.035,
              0,
              0.23,
              0.059,
              grime,
            );
          }
          face(
            'building-cornice',
            span,
            0.19,
            0.29,
            0,
            height - 0.055,
            -0.005,
            facadeTrim,
          );
          // Narrow rain streaks sit beneath the eaves, away from glass openings.
          for (
            let stain = 0;
            stain < (quality === 'performance' ? 1 : 3);
            stain++
          )
            face(
              'facade-runoff-stain',
              0.035 + rand() * 0.045,
              0.18 + rand() * 0.18,
              0.012,
              (rand() - 0.5) * span * 0.78,
              height - 0.31,
              0.113,
              grime,
            );
        }
      }
      const roofSpans =
          office || architecture === 2
            ? 1
            : Math.max(1, Math.round(width / 11)),
        roofSpan = width / roofSpans,
        roofRise = office ? 0 : Math.min(1.35, roofSpan * 0.15),
        northlight = !office && architecture === 1;
      const roofAt = (x: number) => {
        if (office) return height + 0.14;
        const spanPosition =
          (Math.max(0, Math.min(width - 0.0001, x + width / 2)) % roofSpan) /
          roofSpan;
        return (
          height +
          0.14 +
          roofRise *
            (northlight ? spanPosition : 1 - Math.abs(2 * spanPosition - 1))
        );
      };
      const roofHeight = height + roofRise + 0.14;
      if (office) {
        surfaceBox(
          scene,
          'recessed-office-roof',
          [width, 0.17, depth],
          [0, roofHeight, 0],
          roofFelt,
          solid,
          4,
        );
        for (const side of [-1, 1]) {
          surfaceBox(
            scene,
            'office-roof-parapet',
            [width, 0.48, 0.19],
            [0, height + 0.36, side * (depth / 2 - 0.095)],
            facade,
            solid,
          );
          surfaceBox(
            scene,
            'office-roof-parapet',
            [0.19, 0.48, depth - 0.38],
            [side * (width / 2 - 0.095), height + 0.36, 0],
            facade,
            solid,
          );
          surfaceBox(
            scene,
            'parapet-metal-flashing',
            [width + 0.06, 0.055, 0.26],
            [0, height + 0.63, side * (depth / 2 - 0.095)],
            shutter,
            solid,
          );
          surfaceBox(
            scene,
            'parapet-metal-flashing',
            [0.26, 0.055, depth - 0.26],
            [side * (width / 2 - 0.095), height + 0.63, 0],
            shutter,
            solid,
          );
        }
        // A substantial set-back service floor changes the skyline from the
        // combat camera. The occupied ground floor still meets all four walls.
        const coreWidth = Math.min(
            width * (architecture === 0 ? 0.48 : 0.34),
            10,
          ),
          coreDepth = Math.min(depth * 0.44, 7),
          coreX = -width * 0.2,
          coreZ = -depth * 0.19,
          coreHeight = architecture === 0 ? 2.1 : 1.55,
          coreTop = roofHeight + 0.1 + coreHeight;
        surfaceBox(
          scene,
          'setback-office-service-floor',
          [coreWidth, coreHeight, coreDepth],
          [coreX, roofHeight + 0.1 + coreHeight / 2, coreZ],
          architecture === 1 ? m.brick : facade,
          solid,
        );
        surfaceBox(
          scene,
          'service-floor-flat-roof',
          [coreWidth + 0.12, 0.15, coreDepth + 0.12],
          [coreX, coreTop + 0.025, coreZ],
          roofFelt,
          solid,
          4,
        );
        for (const side of [-1, 1]) {
          box(
            scene,
            'service-floor-metal-coping',
            [coreWidth + 0.16, 0.11, 0.12],
            [coreX, coreTop + 0.13, coreZ + side * (coreDepth / 2 + 0.025)],
            shutter,
            solid,
          );
          box(
            scene,
            'service-floor-metal-coping',
            [0.12, 0.11, coreDepth],
            [coreX + side * (coreWidth / 2 + 0.025), coreTop + 0.13, coreZ],
            shutter,
            solid,
          );
          box(
            scene,
            'service-floor-recessed-vent',
            [coreWidth * 0.7, 0.61, 0.06],
            [coreX, coreTop - 0.62, coreZ + side * (coreDepth / 2 + 0.017)],
            m.rubber,
            solid,
          );
          for (let louver = 0; louver < 4; louver++)
            box(
              scene,
              'service-floor-vent-louver',
              [coreWidth * 0.69, 0.075, 0.085],
              [
                coreX,
                coreTop - 0.87 + louver * 0.17,
                coreZ + side * (coreDepth / 2 + 0.05),
              ],
              shutter,
              solid,
            );
        }
        box(
          scene,
          'service-floor-access-door',
          [0.045, 1.3, 0.78],
          [
            coreX + coreWidth / 2 + 0.04,
            roofHeight + 0.77,
            coreZ + coreDepth * 0.15,
          ],
          shutter,
          solid,
        );
        for (let seam = -width / 2 + 1.6; seam < width / 2; seam += 2.6)
          box(
            scene,
            'roofing-membrane-lap',
            [0.035, 0.012, depth - 0.42],
            [seam, roofHeight + 0.095, 0],
            tar,
            solid,
          );
        // Raised, framed rooflights and concrete maintenance slabs are large
        // enough to distinguish the roof from a flat rectangular lid.
        const lightWidth = Math.min(width * 0.22, 3.8),
          lightDepth = Math.min(depth * 0.28, 3.6),
          lightX = width * 0.26,
          lightZ = -depth * 0.22;
        box(
          scene,
          'office-rooflight-curb',
          [lightWidth + 0.18, 0.32, lightDepth + 0.18],
          [lightX, roofHeight + 0.21, lightZ],
          shutter,
          solid,
        );
        const glazing = box(
          scene,
          'office-rooflight-glazing',
          [lightWidth, 0.065, lightDepth],
          [lightX, roofHeight + 0.4, lightZ],
          windowMat,
          solid,
        );
        glazing.rotation.x = -0.055;
        for (
          let mullion = -lightWidth / 2 + 0.8;
          mullion < lightWidth / 2;
          mullion += 0.9
        ) {
          const bar = box(
            scene,
            'office-rooflight-crossbar',
            [0.065, 0.07, lightDepth + 0.05],
            [lightX + mullion, roofHeight + 0.45, lightZ],
            shutter,
            solid,
          );
          bar.rotation.x = -0.055;
        }
        for (let slab = 0; slab < Math.min(7, Math.floor(width / 1.3)); slab++)
          surfaceBox(
            scene,
            'roof-maintenance-walkway',
            [0.95, 0.055, 0.72],
            [-width * 0.3 + slab * 1.07, roofHeight + 0.135, depth * 0.3],
            facadeTrim,
            solid,
          );
      } else {
        const positions: number[] = [],
          normals: number[] = [],
          uvs: number[] = [],
          indices: number[] = [];
        for (let span = 0; span < roofSpans; span++) {
          const left = -width / 2 + span * roofSpan,
            centre = left + roofSpan / 2;
          for (const side of [-1, 1]) {
            const start = positions.length / 3,
              peak = northlight ? left + roofSpan : centre;
            positions.push(
              left,
              height,
              (side * depth) / 2,
              left + roofSpan,
              height,
              (side * depth) / 2,
              peak,
              roofHeight - 0.02,
              (side * depth) / 2,
            );
            normals.push(0, 0, side, 0, 0, side, 0, 0, side);
            uvs.push(
              left / 3,
              height / 3,
              (left + roofSpan) / 3,
              height / 3,
              peak / 3,
              (roofHeight - 0.02) / 3,
            );
            indices.push(
              ...(side > 0
                ? [start + 2, start + 1, start]
                : [start, start + 1, start + 2]),
            );
          }
          for (const side of northlight ? [0] : [-1, 1]) {
            const run = northlight ? roofSpan : roofSpan / 2,
              slope = Math.atan2(roofRise, run) * (northlight ? 1 : -side),
              panelWidth = Math.hypot(run, roofRise) + 0.065,
              panelX = northlight ? centre : centre + (side * roofSpan) / 4;
            const panel = surfaceBox(
              scene,
              northlight ? 'northlight-sloped-roof' : 'multi-span-pitched-roof',
              [panelWidth, 0.1, depth + 0.18],
              [panelX, height + roofRise / 2 + 0.12, 0],
              roof,
              solid,
              3,
            );
            panel.rotation.z = slope;
            for (
              let seam = -depth / 2;
              seam <= depth / 2;
              seam += quality === 'performance' ? 1.5 : 0.8
            ) {
              const fold = box(
                scene,
                'raised-roof-seam',
                [panelWidth, 0.042, 0.038],
                [panelX, height + roofRise / 2 + 0.184, seam],
                shutter,
                solid,
              );
              fold.rotation.z = slope;
            }
          }
          if (northlight) {
            const frameX = left + roofSpan - 0.04;
            box(
              scene,
              'northlight-steel-glazing-frame',
              [0.1, roofRise + 0.12, depth + 0.08],
              [frameX, height + roofRise / 2 + 0.11, 0],
              shutter,
              solid,
            );
            box(
              scene,
              'north-facing-factory-glazing',
              [0.045, roofRise - 0.15, depth - 0.17],
              [frameX + 0.065, height + roofRise / 2 + 0.1, 0],
              windowDust,
              solid,
            );
            for (let z = -depth / 2 + 1.1; z < depth / 2; z += 1.45)
              box(
                scene,
                'northlight-window-mullion',
                [0.1, roofRise + 0.05, 0.065],
                [frameX + 0.085, height + roofRise / 2 + 0.12, z],
                shutter,
                solid,
              );
            box(
              scene,
              'northlight-ridge-flashing',
              [0.21, 0.075, depth + 0.19],
              [left + roofSpan - 0.035, roofHeight + 0.02, 0],
              shutter,
              solid,
            );
          } else {
            box(
              scene,
              'warehouse-roof-ridge-cap',
              [0.22, 0.12, depth + 0.19],
              [centre, roofHeight, 0],
              shutter,
              solid,
            );
            if (architecture === 0) {
              const lightX = left + roofSpan * 0.26,
                lightZ = -depth * 0.16,
                lightWidth = roofSpan * 0.31,
                lightDepth = depth * 0.42,
                slope = Math.atan2(roofRise, roofSpan / 2);
              const curb = box(
                scene,
                'workshop-rooflight-curb',
                [lightWidth + 0.14, 0.15, lightDepth + 0.14],
                [lightX, roofAt(lightX) + 0.12, lightZ],
                shutter,
                solid,
              );
              curb.rotation.z = slope;
              const glazing = box(
                scene,
                'workshop-framed-rooflight',
                [lightWidth, 0.045, lightDepth],
                [lightX, roofAt(lightX) + 0.22, lightZ],
                windowDust,
                solid,
              );
              glazing.rotation.z = slope;
              for (
                let z = -lightDepth / 2 + 0.9;
                z < lightDepth / 2;
                z += 1.1
              ) {
                const bar = box(
                  scene,
                  'workshop-rooflight-crossbar',
                  [lightWidth + 0.1, 0.035, 0.055],
                  [lightX, roofAt(lightX) + 0.26, lightZ + z],
                  shutter,
                  solid,
                );
                bar.rotation.z = slope;
              }
            }
          }
          box(
            scene,
            'roof-valley-drainage-channel',
            [0.15, 0.075, depth + 0.18],
            [left + 0.015, height + 0.125, 0],
            shutter,
            solid,
          );
        }
        const gables = new Mesh('warehouse-masonry-gables', scene),
          shape = new VertexData();
        shape.positions = positions;
        shape.normals = normals;
        shape.uvs = uvs;
        shape.indices = indices;
        shape.applyToMesh(gables);
        gables.material = facade;
        gables.parent = solid;
        for (const side of [-1, 1])
          box(
            scene,
            'warehouse-eaves-gutter',
            [0.16, 0.15, depth + 0.14],
            [side * (width / 2 + 0.06), height + 0.045, 0],
            shutter,
            solid,
          );
        if (architecture === 2) {
          const monitorWidth = Math.min(4.2, width * 0.32),
            monitorDepth = depth * 0.61,
            monitorBottom = roofAt(monitorWidth / 2) - 0.045,
            monitorTop = roofHeight + 0.85;
          surfaceBox(
            scene,
            'raised-warehouse-roof-monitor',
            [monitorWidth, monitorTop - monitorBottom, monitorDepth],
            [0, (monitorTop + monitorBottom) / 2, 0],
            shutter,
            solid,
          );
          for (const side of [-1, 1]) {
            box(
              scene,
              'monitor-clerestory-glass',
              [0.035, 0.62, monitorDepth - 0.2],
              [side * (monitorWidth / 2 + 0.023), roofHeight + 0.42, 0],
              windowMat,
              solid,
            );
            for (
              let z = -monitorDepth / 2 + 0.7;
              z < monitorDepth / 2;
              z += 1.15
            )
              box(
                scene,
                'monitor-vertical-steel-frame',
                [0.08, 0.76, 0.065],
                [side * (monitorWidth / 2 + 0.04), roofHeight + 0.42, z],
                shutter,
                solid,
              );
          }
          surfaceBox(
            scene,
            'roof-monitor-overhanging-cap',
            [monitorWidth + 0.24, 0.13, monitorDepth + 0.22],
            [0, roofHeight + 0.94, 0],
            roof,
            solid,
          );
          for (let z = -monitorDepth / 2; z <= monitorDepth / 2; z += 0.85)
            box(
              scene,
              'monitor-cap-standing-seam',
              [monitorWidth + 0.2, 0.035, 0.035],
              [0, roofHeight + 1.02, z],
              shutter,
              solid,
            );
        }
      }
      for (const side of [-1, 1]) {
        const downpipe = MeshBuilder.CreateCylinder(
          'rainwater-downpipe',
          {
            height: height - 0.1,
            diameter: 0.105,
            tessellation: quality === 'performance' ? 5 : 8,
          },
          scene,
        );
        downpipe.position.set(
          side * (width / 2 - 0.3),
          height / 2,
          depth / 2 + 0.12,
        );
        downpipe.parent = solid;
        downpipe.material = shutter;
        for (let clamp = 0.65; clamp < height; clamp += 1.6)
          box(
            scene,
            'downpipe-wall-bracket',
            [0.17, 0.045, 0.18],
            [side * (width / 2 - 0.3), clamp, depth / 2 + 0.07],
            m.steel,
            solid,
          );
      }
      const ventX = Math.max(
          0,
          Math.min(width * (office ? 0.2 : 0.33), width / 2 - 0.87),
        ),
        ventZ = depth * 0.19,
        curbBottom =
          Math.min(roofAt(ventX + 0.79), roofAt(ventX - 0.79)) - 0.025,
        curbHeight = roofHeight + 0.255 - curbBottom;
      surfaceBox(
        scene,
        'roof-hvac-curb',
        [1.58, curbHeight, 1.22],
        [ventX, curbBottom + curbHeight / 2, ventZ],
        m.rubber,
        solid,
      );
      surfaceBox(
        scene,
        'industrial-rooftop-air-handler',
        [1.45, 0.72, 1.05],
        [ventX, roofHeight + 0.54, ventZ],
        shutter,
        solid,
      );
      for (let louver = 0; louver < 5; louver++)
        box(
          scene,
          'hvac-horizontal-louver',
          [1.18, 0.036, 0.035],
          [ventX, roofHeight + 0.31 + louver * 0.1, ventZ + 0.54],
          m.steel,
          solid,
        );
      const fan = MeshBuilder.CreateCylinder(
        'rooftop-extractor-fan',
        {
          height: 0.055,
          diameter: 0.62,
          tessellation: quality === 'performance' ? 10 : 16,
        },
        scene,
      );
      fan.position.set(ventX, roofHeight + 0.93, ventZ);
      fan.parent = solid;
      fan.material = m.steel;
      for (let blade = 0; blade < 4; blade++) {
        const guard = box(
          scene,
          'vent-fan-grille',
          [0.57, 0.025, 0.027],
          [ventX, roofHeight + 0.973, ventZ],
          shutter,
          solid,
        );
        guard.rotation.y = (blade * Math.PI) / 4;
      }
      if (quality !== 'performance') {
        const ductStart = office
            ? 0
            : architecture === 2
              ? Math.min(4.2, width * 0.32) / 2
              : ventX - 2.7,
          ductEnd = ventX - 0.62,
          ductLength = Math.max(0.55, ductEnd - ductStart),
          ductX = ductEnd - ductLength / 2;
        surfaceBox(
          scene,
          'roof-service-duct',
          [ductLength, 0.28, 0.35],
          [ductX, roofHeight + 0.23, ventZ],
          shutter,
          solid,
        );
        for (const side of [-1, 1]) {
          const x = ductX + side * ductLength * 0.36,
            baseY = roofAt(x) - 0.02,
            supportHeight = roofHeight + 0.1 - baseY;
          box(
            scene,
            'roof-duct-support',
            [0.065, supportHeight, 0.42],
            [x, baseY + supportHeight / 2, ventZ],
            m.steel,
            solid,
          );
        }
        const hatchX = office ? -width * 0.24 : -width / 2 + roofSpan * 0.77;
        const hatch = surfaceBox(
          scene,
          'roof-access-hatch',
          [0.95, 0.16, 1.25],
          [hatchX, roofAt(hatchX) + 0.11, office ? depth * 0.15 : depth * 0.33],
          grime,
          solid,
        );
        if (!office)
          hatch.rotation.z = Math.atan2(
            roofAt(hatchX + 0.1) - roofAt(hatchX - 0.1),
            0.2,
          );
      }
      for (const mesh of mergeStatic(solid)) shadow?.addShadowCaster(mesh);
      rubble.setEnabled(false);
      registerWall(w, solid, rubble);
      yield progress('建筑与掩体');
      continue;
    }
    const wallStyle = (wallViews.size + b.mission) % 3;
    const wallMaterial =
      w.steel || w.kind === 'container'
        ? m.steel
        : wallStyle === 0
          ? m.brick
          : wallStyle === 1
            ? m.concrete
            : naturalMaterials.stone;
    box(
      scene,
      w.steel || w.kind === 'container'
        ? 'reinforced-container'
        : 'brick-barricade',
      [width, height, depth],
      [0, height / 2, 0],
      wallMaterial,
      solid,
    );
    if (w.steel || w.kind === 'container') {
      for (let x = -width / 2 + 0.3; x < width / 2; x += 0.5) {
        box(
          scene,
          'container-rib',
          [0.055, height * 0.86, depth + 0.075],
          [x, height / 2, 0],
          m.edges,
          solid,
        );
      }
      box(
        scene,
        'container-top',
        [width + 0.1, 0.12, depth + 0.1],
        [0, height + 0.06, 0],
        m.heavy,
        solid,
      );
    } else {
      box(
        scene,
        'concrete-cap',
        [width + 0.15, 0.19, depth + 0.15],
        [0, height + 0.02, 0],
        m.concrete,
        solid,
      );
      for (let y = 0.32; y < height; y += wallStyle === 0 ? 0.33 : 0.57)
        box(
          scene,
          'mortar-line',
          [width + 0.015, 0.025, depth + 0.015],
          [0, y, 0],
          m.concrete,
          solid,
        );
      for (let x = -width / 2 + 0.7; x < width / 2; x += 1.5) {
        box(
          scene,
          'brick-joint',
          [0.028, height, depth + 0.016],
          [x, height / 2, 0],
          m.concrete,
          solid,
        );
      }
      // Surface damage never opens a visual hole through intact collision.
      for (const side of [-1, 1]) {
        for (let i = 0; i < (quality === 'performance' ? 2 : 5); i++) {
          const crack = box(
            scene,
            'weathered-wall-fracture',
            [0.035, 0.28 + rand() * 0.5, 0.014],
            [
              (rand() - 0.5) * width * 0.86,
              0.3 + rand() * (height - 0.5),
              side * (depth / 2 + 0.025),
            ],
            m.rubber,
            solid,
          );
          crack.rotation.z = (rand() - 0.5) * 1.5;
        }
        box(
          scene,
          'moss-at-wall-foot',
          [width * 0.93, 0.12, 0.02],
          [0, 0.08, side * (depth / 2 + 0.029)],
          naturalMaterials.leaves,
          solid,
        );
      }
      if (wallStyle !== 0)
        for (let i = 0; i < 3; i++) {
          const rebar = box(
            scene,
            'exposed-steel-rebar',
            [0.045, 0.25 + rand() * 0.2, 0.045],
            [(i - 1) * width * 0.22, height + 0.1, 0],
            m.steel,
            solid,
          );
          rebar.rotation.z = (rand() - 0.5) * 0.5;
        }
    }
    for (
      let j = 0;
      j < (w.steel ? 0 : quality === 'performance' ? 6 : 12);
      j++
    ) {
      const piece = box(
        scene,
        'collapsed-masonry',
        [0.28 + rand() * 0.5, 0.12 + rand() * 0.4, 0.22 + rand() * 0.5],
        [(rand() - 0.5) * width, 0.12, (rand() - 0.5) * depth],
        j % 3 === 0 ? m.concrete : m.brick,
        rubble,
      );
      piece.rotation.set(rand() * 0.5, rand() * 6, rand() * 0.5);
    }
    const solids = mergeStatic(solid);
    mergeStatic(rubble);
    for (const mesh of solids) {
      mesh.unfreezeWorldMatrix();
      shadow?.addShadowCaster(mesh);
    }
    rubble.setEnabled(false);
    registerWall(w, solid, rubble);
    yield progress('建筑与掩体');
  }
  // These are marked mustering areas inside a continuous, colliding perimeter.
  for (const gate of ENEMY_GATES) {
    const at = worldPosition(gate.x, 25, 2.45);
    box(
      scene,
      'enemy-entry-red-band',
      [8, 0.2, 0.05],
      [at.x, at.y, at.z + 0.035],
      m.red,
      staticRoot,
    );
    for (const side of [-1, 1]) {
      const p = worldPosition(gate.x + side * 47, 12.5, 3.7);
      box(
        scene,
        'enemy-entry-warning-beacon',
        [0.28, 0.6, 0.28],
        [p.x, p.y, p.z],
        m.red,
        staticRoot,
      );
    }
    for (let i = 0; i < 3; i++)
      stamp(
        'enemy-entry-ground-mark',
        gate.x - 30,
        gate.y + i * 32,
        60,
        5,
        hazardPaint,
        0.064,
      );
  }
  const staticMeshes = mergeStatic(staticRoot, true);
  const nature = createNature(scene, b, naturalMaterials, quality);
  const scenery = createBattlefieldScenery(scene, b, m, quality, assets),
    updateNature = nature.update.bind(nature);
  nature.update = (time: number) => {
    updateNature(time);
    scenery.update(time);
  };
  staticMeshes.push(...nature.meshes, ...scenery.meshes);
  updateDamage();
  yield progress('植被与河道');
  for (const material of [
    asphalt,
    puddle,
    windowMat,
    windowDust,
    roof,
    roofFelt,
    facadeTrim,
    shutter,
    grime,
    tar,
    roadPaint,
    hazardPaint,
    perimeterMetal,
    perimeterReflector,
    contactShade,
  ])
    material.freeze();
  return {
    ground,
    walls: wallViews,
    shadow,
    sun,
    staticMeshes,
    nature,
    updateShadow,
    updateDamage,
  };
}

/** Synchronous construction remains available to deterministic headless tests. */
export function createWorld(
  scene: Scene,
  b: Battle,
  materials: Materials,
  quality: Quality = 'balanced',
  headless = false,
  assets = !headless,
): World {
  const steps = worldSteps(scene, b, materials, quality, headless, assets);
  let next = steps.next();
  while (!next.done) next = steps.next();
  return next.value;
}

/** Yield between completed batches so loading progress can actually paint. */
export async function createWorldAsync(
  scene: Scene,
  b: Battle,
  materials: Materials,
  quality: Quality = 'balanced',
  headless = false,
  assets = !headless,
  onProgress?: (completed: number, total: number, label: string) => void,
  cancelled?: () => boolean,
): Promise<World> {
  const steps = worldSteps(scene, b, materials, quality, headless, assets);
  let deadline = Date.now() + 8;
  onProgress?.(0, b.roads.length + b.walls.length + 2, '正在准备战场');
  for (;;) {
    if (cancelled?.()) {
      steps.return(undefined as never);
      throw new DOMException('Battlefield loading cancelled', 'AbortError');
    }
    const next = steps.next();
    if (next.done) return next.value;
    onProgress?.(next.value.completed, next.value.total, next.value.label);
    if (Date.now() >= deadline) {
      await new Promise<void>((resolve) => setTimeout(resolve, 0));
      deadline = Date.now() + 8;
    }
  }
}
