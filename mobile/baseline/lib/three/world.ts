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
} from './babylon';
import { Battle, W, H, ENEMY_GATES, seeded, type Wall } from '../engine';
import { box } from './tank-model';
import { type Materials, type Quality, pbr, emissive } from './materials';
import { buildLivingCover, createNature, natureMaterials } from './nature';
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
function mergeStatic(parent: TransformNode, chunks = false) {
  const groups = new Map<string, Mesh[]>();
  for (const child of parent.getChildMeshes(true)) {
    if (!(child instanceof Mesh) || !child.material) continue;
    const key = `${child.material.uniqueId}:${chunks ? Math.floor(child.position.x / 40) + ',' + Math.floor(child.position.z / 40) : 'all'}`;
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
    ['#939481', '#363f3f', '#f9d39b'],
    ['#81989d', '#253c4e', '#b4d5e6'],
    ['#ab9480', '#474644', '#ffce8c'],
    ['#89968d', '#313f40', '#e6d3a2'],
    ['#888291', '#303341', '#efb986'],
    ['#c5997d', '#43444b', '#ffb973'],
  ][b.mission % 6];
  scene.clearColor = Color4.FromHexString(themes[1] + 'ff');
  scene.fogMode = Scene.FOGMODE_EXP2;
  scene.fogDensity = 0.004;
  scene.fogColor = Color3.FromHexString(themes[0]).scale(0.7);
  scene.ambientColor = new Color3(0.12, 0.14, 0.14);
  const ambient = new HemisphericLight(
    'overcast-sky-light',
    new Vector3(0.2, 1, 0.1),
    scene,
  );
  ambient.intensity = 0.62;
  ambient.diffuse = new Color3(0.8, 0.87, 1);
  ambient.groundColor = new Color3(0.19, 0.2, 0.17);
  const sun = new DirectionalLight(
    'late-afternoon-sun',
    new Vector3(0.65, -1, 0.65),
    scene,
  );
  sun.position.set(-110, 150, -110);
  sun.diffuse = Color3.FromHexString(themes[2]);
  sun.intensity = 3;
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
    scene.environmentIntensity = 0.5;
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
  const asphalt = pbr(scene, 'wet-road', '#303936', 0.24, 0.47),
    puddle = pbr(scene, 'shallow-puddles', '#28342e', 0.65, 0.16),
    windowMat = pbr(scene, 'abandoned-windows', '#202b2b', 0.45, 0.34),
    roof = pbr(scene, 'warehouse-roof', '#4c5352', 0.65, 0.65),
    roadPaint = pbr(scene, 'worn-road-lines', '#b6ab78', 0.03, 0.9);
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
    return box(
      scene,
      name,
      [w * UNIT, 0.012, h * UNIT],
      [p.x, p.y, p.z],
      material,
      staticRoot,
    );
  };
  // A connected street network, intersections, crosswalks and loading aprons.
  for (const road of b.roads) {
    stamp('street-asphalt', road.x, road.y, road.w, road.h, asphalt);
    const vertical = road.h > road.w;
    const length = vertical ? road.h : road.w;
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
  for (let i = 0; i < (quality === 'performance' ? 14 : 28); i++) {
    const road = b.roads[i % b.roads.length];
    const x = road.x + rand() * road.w,
      y = road.y + rand() * road.h;
    stamp(
      'road-repair-patch',
      x,
      y,
      12 + rand() * 28,
      8 + rand() * 20,
      puddle,
      0.043,
    );
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
      box(
        scene,
        office ? 'office-block' : 'warehouse-block',
        [width, height, depth],
        [0, height / 2, 0],
        office ? m.concrete : m.brick,
        solid,
      );
      box(
        scene,
        'building-roof',
        [width + 0.12, 0.22, depth + 0.12],
        [0, height + 0.1, 0],
        roof,
        solid,
      );
      for (const side of [-1, 1]) {
        if (office) {
          for (let floor = 1.9; floor < height - 0.5; floor += 2.6)
            for (let x = -width / 2 + 1; x < width / 2 - 0.5; x += 2)
              box(
                scene,
                'office-window',
                [1.15, 1.3, 0.035],
                [x, floor, side * (depth / 2 + 0.024)],
                windowMat,
                solid,
              );
        } else {
          box(
            scene,
            'loading-shutter',
            [Math.min(3.8, width * 0.7), 2.8, 0.05],
            [0, 1.4, side * (depth / 2 + 0.035)],
            m.steel,
            solid,
          );
          box(
            scene,
            'loading-canopy',
            [Math.min(4.2, width * 0.8), 0.13, 0.7],
            [0, 3, side * (depth / 2 + 0.25)],
            roof,
            solid,
          );
          box(
            scene,
            'clerestory',
            [width * 0.72, 0.5, 0.035],
            [0, height - 0.55, side * (depth / 2 + 0.035)],
            windowMat,
            solid,
          );
        }
      }
      box(
        scene,
        'rooftop-vent',
        [1.1, 0.45, 1.3],
        [width * 0.24, height + 0.4, 0],
        m.steel,
        solid,
      );
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
    roof,
    roadPaint,
    hazardPaint,
    perimeterMetal,
    perimeterReflector,
  ])
    material.freeze();
  return { ground, walls: wallViews, shadow, sun, staticMeshes, nature };
}
