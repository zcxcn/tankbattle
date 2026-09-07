import { assetUrl } from '../asset-url';
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
  TransformNode,
  Vector3,
  VertexData,
  type Material,
} from './babylon';
import { Battle, W, H, ENEMY_GATES, seeded, type Wall } from '../engine';
import { type Materials, type Quality, pbr, emissive } from './materials';
import { buildLivingCover, createNature, natureMaterials } from './nature';
import { applySurface } from './surface-textures';
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
};
const skyVertex = `precision highp float;attribute vec3 position;uniform mat4 worldViewProjection;varying vec3 vPosition;void main(){vPosition=position;gl_Position=worldViewProjection*vec4(position,1.);}`;
const skyFragment = `precision highp float;varying vec3 vPosition;uniform vec3 horizon;uniform vec3 zenith;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1.,0.)),f.x),mix(hash(i+vec2(0.,1.)),hash(i+vec2(1.,1.)),f.x),f.y);}void main(){vec3 d=normalize(vPosition);float h=max(0.,d.y);vec3 col=mix(horizon,zenith,pow(h,.55));float cloud=noise(d.xz/(h+.18)*3.)*.6+noise(d.xz/(h+.18)*8.)*.3+noise(d.xz/(h+.18)*20.)*.1;col=mix(col,col*.55+vec3(.13),smoothstep(.42,.7,cloud)*smoothstep(.0,.18,h)*.65);float sun=pow(max(0.,dot(d,normalize(vec3(-.6,.3,-.7)))),300.);float glow=pow(max(0.,dot(d,normalize(vec3(-.6,.3,-.7)))),9.);col+=vec3(1.,.69,.35)*sun*2.5+vec3(.26,.14,.04)*glow;gl_FragColor=vec4(col,1.);}`;
type StaticBox = {
  name: string;
  size: [number, number, number];
  position: Vector3;
  rotation: Vector3;
  material: Material;
  tile?: number;
};
const pendingBoxes = new WeakMap<TransformNode, StaticBox[]>();
const unitBox = VertexData.CreateBox({ size: 1 });
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
export function createWorld(
  scene: Scene,
  b: Battle,
  m: Materials,
  quality: Quality = 'balanced',
  headless = false,
  assets = !headless,
): World {
  const rand = seeded(379 + b.mission),
    staticRoot = new TransformNode('industrial-district', scene),
    wallViews = new Map<
      Wall,
      { solid: TransformNode; rubble: TransformNode }
    >();
  const naturalMaterials = natureMaterials(scene, assets, quality);
  const themes = [
    ['#a5aaa5', '#485b68', '#fff0d3'],
    ['#96a6ae', '#364c60', '#d3e5f1'],
    ['#aea59b', '#53606a', '#ffe8c5'],
    ['#a0aaa5', '#425864', '#eaf0df'],
    ['#a2a1ac', '#454b60', '#f5ddc9'],
    ['#b6a397', '#535767', '#ffe0b4'],
  ][b.mission % 6];
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
  ambient.intensity = 0.72;
  ambient.diffuse = new Color3(0.85, 0.91, 1);
  ambient.groundColor = new Color3(0.25, 0.23, 0.19);
  const sun = new DirectionalLight(
    'late-afternoon-sun',
    new Vector3(0.55, -1, 0.72),
    scene,
  );
  sun.position.set(-110, 150, -110);
  sun.diffuse = Color3.FromHexString(themes[2]);
  // A broad daylight key preserves scanned surface colour instead of clipping it.
  sun.intensity = 2.15;
  sun.autoUpdateExtends = false;
  sun.orthoLeft = -(W + H) * UNIT * 0.48;
  sun.orthoRight = (W + H) * UNIT * 0.48;
  sun.orthoTop = (W + H) * UNIT * 0.4;
  sun.orthoBottom = -(W + H) * UNIT * 0.4;
  sun.shadowMinZ = 1;
  sun.shadowMaxZ = 750;
  let shadow: ShadowGenerator | null = null;
  if (!headless && quality !== 'performance') {
    shadow = new ShadowGenerator(quality === 'cinematic' ? 2048 : 1024, sun);
    shadow.usePercentageCloserFiltering = true;
    shadow.filteringQuality =
      quality === 'cinematic'
        ? ShadowGenerator.QUALITY_HIGH
        : ShadowGenerator.QUALITY_LOW;
    shadow.bias = 0.0012;
    shadow.normalBias = 0.06;
    shadow.darkness = 0.22;
  }
  if (!headless) {
    scene.environmentTexture = CubeTexture.CreateFromPrefilteredData(
      assetUrl('/environment.env'),
      scene,
    );
    scene.environmentIntensity = 0.65;
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
        uniforms: ['worldViewProjection', 'horizon', 'zenith'],
      },
    );
    skyMat.setColor3('horizon', Color3.FromHexString(themes[0]));
    skyMat.setColor3('zenith', Color3.FromHexString(themes[1]));
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
  ground.material = m.ground;
  ground.receiveShadows = true;
  ground.isPickable = true;
  const asphalt = pbr(scene, 'wet-road', '#d2d7d5', 0.02, 0.9),
    puddle = pbr(scene, 'shallow-puddles', '#303b40', 0.12, 0.18),
    windowMat = pbr(scene, 'abandoned-windows', '#243b44', 0.35, 0.24),
    windowDust = pbr(scene, 'dusty-window-glass', '#415456', 0.2, 0.51),
    roof = pbr(scene, 'warehouse-roof', '#919493', 0.62, 0.63),
    roofFelt = pbr(scene, 'office-roof-felt', '#676863', 0.03, 0.93),
    facadeTrim = pbr(scene, 'aged-limestone-trim', '#b4b3a7', 0.03, 0.88),
    shutter = pbr(scene, 'zinc-shutter-panels', '#6e7a78', 0.55, 0.66),
    grime = pbr(scene, 'damp-building-plinth', '#51574c', 0, 0.98),
    tar = pbr(scene, 'sealed-asphalt-fissures', '#222725', 0.01, 0.8),
    roadPaint = pbr(scene, 'worn-road-lines', '#c4bd9b', 0.03, 0.94);
  if (assets) {
    applySurface(asphalt, scene, 'asphalt', {
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
  // A connected street network, intersections, crosswalks and loading aprons.
  for (const road of b.roads) {
    stamp('street-asphalt', road.x, road.y, road.w, road.h, asphalt);
    const vertical = road.h > road.w;
    const length = vertical ? road.h : road.w;
    // Flush shoulders and drains convey scale without creating unseen obstacles.
    for (const side of [0, 1]) {
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
    for (let t = 24; t < length; t += 58) {
      const x = vertical ? road.x + road.w / 2 : t;
      const y = vertical ? t : road.y + road.h / 2;
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
  }
  for (const vertical of b.roads.filter((r) => r.h > r.w)) {
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
    // Ground-only ambient shadows give mobile objects weight without a shadow pass.
    stamp(
      'building-contact-shadow',
      w.x - 5,
      w.y - 5,
      w.w + 22,
      w.h + 22,
      asphalt,
      0.065,
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
      indices.push(0, ((vertex + 1) % 9) + 1, vertex + 1);
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
  for (let i = 0; i < 13; i++) {
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
  for (const x of [(-W * UNIT) / 2 - 5, (-W * UNIT) / 2 - 7])
    box(
      scene,
      'rail-spur',
      [0.13, 0.1, H * UNIT],
      [x, 0.1, 0],
      m.steel,
      staticRoot,
    );
  for (let z = (-H * UNIT) / 2; z < (H * UNIT) / 2; z += 2)
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
  for (const w of b.walls) {
    const solid = new TransformNode('cover-' + wallViews.size, scene),
      rubble = new TransformNode('destroyed-cover-' + wallViews.size, scene);
    const center = worldPosition(w.x + w.w / 2, w.y + w.h / 2),
      width = w.w * UNIT,
      depth = w.h * UNIT;
    solid.position.copyFrom(center);
    rubble.position.copyFrom(center);
    const height = w.height ?? (w.steel ? 2.5 : 1.65);
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
      wallViews.set(w, { solid, rubble });
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
      );
      for (const mesh of mergeStatic(solid)) shadow?.addShadowCaster(mesh);
      mergeStatic(rubble);
      rubble.setEnabled(false);
      wallViews.set(w, { solid, rubble });
      continue;
    }
    if (w.kind === 'warehouse' || w.kind === 'office') {
      const office = w.kind === 'office';
      const facade = office ? m.concrete : m.brick;
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
            const bays = Math.max(1, Math.floor(span / 2.15)),
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
                facade,
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
      let roofHeight = height + 0.14;
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
      } else {
        const rise = Math.min(0.48, width * 0.07),
          slope = Math.atan2(rise, width / 2),
          panelWidth = Math.hypot(width / 2, rise) + 0.12;
        roofHeight = height + rise + 0.14;
        for (const side of [-1, 1]) {
          const gable = new Mesh('warehouse-masonry-gable', scene),
            shape = new VertexData();
          shape.positions = [
            -width / 2,
            height,
            (side * depth) / 2,
            width / 2,
            height,
            (side * depth) / 2,
            0,
            height + rise + 0.12,
            (side * depth) / 2,
          ];
          shape.indices = side > 0 ? [0, 1, 2] : [2, 1, 0];
          shape.normals = [0, 0, side, 0, 0, side, 0, 0, side];
          shape.uvs = [0, 0, width / 3, 0, width / 6, (rise + 0.12) / 3];
          shape.applyToMesh(gable);
          gable.material = facade;
          gable.parent = solid;
          const panel = surfaceBox(
            scene,
            'pitched-standing-seam-roof',
            [panelWidth, 0.1, depth + 0.22],
            [(side * width) / 4, height + rise / 2 + 0.12, 0],
            roof,
            solid,
            3,
          );
          panel.rotation.z = -side * slope;
          for (
            let seam = -depth / 2;
            seam <= depth / 2;
            seam += quality === 'performance' ? 1.3 : 0.65
          ) {
            const fold = box(
              scene,
              'raised-roof-seam',
              [panelWidth, 0.045, 0.04],
              [(side * width) / 4, height + rise / 2 + 0.185, seam],
              shutter,
              solid,
            );
            fold.rotation.z = -side * slope;
          }
          box(
            scene,
            'warehouse-eaves-gutter',
            [0.16, 0.15, depth + 0.14],
            [side * (width / 2 + 0.06), height + 0.045, 0],
            shutter,
            solid,
          );
        }
        box(
          scene,
          'warehouse-roof-ridge-cap',
          [0.24, 0.12, depth + 0.22],
          [0, roofHeight, 0],
          shutter,
          solid,
        );
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
      const ventX = Math.max(0, Math.min(width * 0.2, width / 2 - 0.87)),
        ventZ = depth * 0.19,
        roofRise = office ? 0 : Math.min(0.48, width * 0.07),
        roofAt = (x: number) =>
          roofHeight - roofRise * Math.min(1, (2 * Math.abs(x)) / width),
        curbBottom = roofAt(ventX + 0.79) - 0.025,
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
        const ductLength = Math.min(width * 0.27, 2.2);
        surfaceBox(
          scene,
          'roof-service-duct',
          [ductLength, 0.28, 0.35],
          [0, roofHeight + 0.23, ventZ],
          shutter,
          solid,
        );
        for (const side of [-1, 1]) {
          const x = side * ductLength * 0.36,
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
        const hatch = surfaceBox(
          scene,
          'roof-access-hatch',
          [0.95, 0.16, 1.25],
          [-width * 0.24, roofAt(-width * 0.24) + 0.08, -depth * 0.19],
          grime,
          solid,
        );
        if (!office) hatch.rotation.z = Math.atan2(roofRise, width / 2);
      }
      for (const mesh of mergeStatic(solid)) shadow?.addShadowCaster(mesh);
      rubble.setEnabled(false);
      wallViews.set(w, { solid, rubble });
      continue;
    }
    const wallStyle = (wallViews.size + b.mission) % 3;
    const wallMaterial = w.steel
      ? m.steel
      : wallStyle === 0
        ? m.brick
        : wallStyle === 1
          ? m.concrete
          : naturalMaterials.stone;
    box(
      scene,
      w.steel ? 'reinforced-container' : 'brick-barricade',
      [width, height, depth],
      [0, height / 2, 0],
      wallMaterial,
      solid,
    );
    if (w.steel) {
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
    wallViews.set(w, { solid, rubble });
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
  staticMeshes.push(...nature.meshes);
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
  ])
    material.freeze();
  return { ground, walls: wallViews, shadow, sun, staticMeshes, nature };
}
