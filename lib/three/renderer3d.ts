import { WEAPONS } from '../campaign';
import {
  isMobileDevice,
  resolutionScale,
  type Resolution,
} from '../performance';
import {
  Engine,
  Scene,
  UniversalCamera,
  Vector3,
  Matrix,
  Color3,
  DynamicTexture,
  Mesh,
  MeshBuilder,
  TransformNode,
  PointLight,
  DefaultRenderingPipeline,
  ImageProcessingConfiguration,
  type AbstractEngine,
  type Material,
} from './babylon';
import {
  Battle,
  W,
  H,
  muzzleDistance,
  muzzleHeight,
  type Tank,
  type Vec,
} from '../engine';
import {
  createMaterials,
  emissive,
  type Materials,
  type Quality,
} from './materials';
import { buildTank, box, type TankModel } from './tank-model';
import { ExplosionEffects } from './explosions';
import { createWeaponMount } from './weapon-mount';
import { ProjectileEffects } from './projectiles';
import { MuzzleEffects, recoilDistance } from './muzzle';
import { createSupplyModel, configureSupplyModel } from './supplies';
import {
  createWorld,
  createWorldAsync,
  heading,
  simulationPosition,
  worldPosition,
  type World,
} from './world';
export type CameraMode = 'assault' | 'tactical';
export type RendererProgress = { progress: number; label: string };
export type RendererOptions = {
  quality?: Quality;
  headlessEngine?: AbstractEngine;
  assets?: boolean;
  mobile?: boolean;
  onProgress?: (state: RendererProgress) => void;
};
export class Renderer3D {
  canvas: HTMLCanvasElement;
  engine: AbstractEngine;
  scene: Scene;
  camera: UniversalCamera;
  world!: World;
  materials!: Materials;
  models = new Map<number, TankModel>();
  quality!: Quality;
  mode: CameraMode = 'assault';
  disposed = false;
  ready: Promise<void>;
  private pipeline: DefaultRenderingPipeline | null = null;
  private contactShadows = new Map<number, Mesh>();
  readonly projectiles!: ProjectileEffects;
  readonly muzzles!: MuzzleEffects;
  private weaponMount: ReturnType<typeof createWeaponMount> | null = null;
  private sparkPool: Mesh[] = [];
  private trackPool: Mesh[] = [];
  readonly explosions!: ExplosionEffects;
  private pickupPool: TransformNode[] = [];
  private minePool: TransformNode[] = [];
  private supplyColors: Material[] = [];
  private supplyLabels: Material[] = [];
  private healthBars = new Map<number, { root: TransformNode; fill: Mesh }>();
  private flashLight!: PointLight;
  private cursor!: Mesh;
  private emp!: Mesh;
  private playerRing!: Mesh;
  private base: TransformNode | null = null;
  private objectiveViews = new Map<
    number,
    { root: TransformNode; ring: Mesh; body: Mesh; bar: Mesh }
  >();
  private sniperLines = new Map<number, Mesh>();
  private cameraTarget = Vector3.Zero();
  private initialized = false;
  private lastTime = 0;
  private zoom = 1;
  private muzzleTimer = 0;
  private mobile: boolean;
  private effectScale = 1;
  private resolutionScale = 1;
  private resolutionMode: Resolution;
  private budgetScale = 1;
  private renderOnlyRandom = 37;
  private resizeGeneration = 0;
  constructor(
    canvas: HTMLCanvasElement,
    b: Battle,
    options: RendererOptions = {},
  ) {
    const startedAt = performance.now();
    const timings: Record<string, number> = {};
    const progress = (value: number, label: string) =>
      options.onProgress?.({ progress: value, label });
    const completed = (stage: string) => {
      timings[stage] = Math.round(performance.now() - startedAt);
    };
    progress(0, '连接图形设备');
    this.canvas = canvas;
    this.mobile = options.mobile ?? isMobileDevice();
    this.quality = options.quality ?? 'balanced';
    this.resolutionMode = b.save.resolution ?? 'sharp';
    this.engine =
      options.headlessEngine ??
      new Engine(
        canvas,
        this.mobile || this.quality !== 'performance',
        {
          stencil: false,
          preserveDrawingBuffer: false,
          powerPreference:
            this.mobile && this.resolutionMode === 'adaptive'
              ? 'low-power'
              : 'high-performance',
          adaptToDeviceRatio: false,
        },
        false,
      );
    const headless = !!options.headlessEngine;
    if (!headless) {
      this.resolutionScale = this.mobile
        ? resolutionScale(
            canvas.clientWidth,
            canvas.clientHeight,
            window.devicePixelRatio,
            this.resolutionMode,
          )
        : this.quality === 'cinematic'
          ? 1 / Math.min(window.devicePixelRatio || 1, 1.6)
          : this.quality === 'performance'
            ? 1.5
            : 1;
      this.engine.setHardwareScalingLevel(this.resolutionScale);
    }
    const scene = (this.scene = new Scene(this.engine));
    scene.useRightHandedSystem = true;
    scene.skipPointerMovePicking = true;
    this.camera = new UniversalCamera(
      'player-follow-camera',
      new Vector3(0, 36, 52),
      scene,
    );
    this.camera.minZ = 1;
    this.camera.maxZ = 700;
    this.camera.fov = 0.86;
    this.camera.inputs.clear();
    scene.activeCamera = this.camera;
    completed('device');
    progress(6, '图形设备已连接 · 装载材质');
    this.materials = createMaterials(
      scene,
      options.assets !== false,
      this.mobile,
    );
    const supplyNames = [
      '加农',
      '机枪',
      '霰弹',
      '磁轨',
      '榴弹',
      '脉冲',
      '火箭',
      '维修',
      '超频',
      '护盾',
    ];
    [...WEAPONS.map((w) => w.color), '#7bffc9', '#ffe888', '#b5d9ff'].forEach(
      (color, index) => {
        this.supplyColors.push(
          emissive(scene, 'supply-glow-' + index, color, 1.1),
        );
        const label = emissive(scene, 'supply-label-' + index, '#ffffff', 1);
        if (!headless) {
          const texture = new DynamicTexture(
            'supply-type-' + index,
            { width: 384, height: 128 },
            scene,
            false,
          );
          texture.hasAlpha = true;
          const ctx = texture.getContext() as CanvasRenderingContext2D;
          ctx.fillStyle = '#14221de8';
          ctx.fillRect(0, 0, 384, 128);
          ctx.strokeStyle = color;
          ctx.lineWidth = 7;
          ctx.strokeRect(4, 4, 376, 120);
          ctx.fillStyle = color;
          ctx.font = 'bold 52px sans-serif';
          ctx.textAlign = 'center';
          const amount = WEAPONS[index]?.supply;
          ctx.fillText(
            supplyNames[index] + (amount ? ' +' + amount : ''),
            192,
            84,
          );
          texture.update();
          label.diffuseTexture = texture;
          label.emissiveTexture = texture;
          label.opacityTexture = texture;
          label.useAlphaFromDiffuseTexture = true;
          label.backFaceCulling = false;
        }
        this.supplyLabels.push(label);
      },
    );
    this.explosions = new ExplosionEffects(
      scene,
      this.materials,
      this.quality,
      this.mobile,
    );
    this.projectiles = new ProjectileEffects(scene, this.quality, this.mobile);
    this.muzzles = new MuzzleEffects(scene, this.mobile);
    completed('materials');
    progress(12, '材质已登记 · 构建战场');
    const finish = () => {
      scene.imageProcessingConfiguration.toneMappingEnabled = true;
      scene.imageProcessingConfiguration.toneMappingType =
        ImageProcessingConfiguration.TONEMAPPING_ACES;
      scene.imageProcessingConfiguration.exposure = 1;
      scene.imageProcessingConfiguration.contrast = 1.04;
      if (!headless && this.quality !== 'performance' && !this.mobile) {
        const pipe = (this.pipeline = new DefaultRenderingPipeline(
          'cinematic-image-pipeline',
          true,
          scene,
          [this.camera],
        ));
        pipe.fxaaEnabled = true;
        pipe.samples = this.quality === 'cinematic' ? 4 : 1;
        pipe.bloomEnabled = true;
        pipe.bloomThreshold = 1.35;
        pipe.bloomWeight = 0.1;
        pipe.bloomKernel = 40;
        pipe.imageProcessingEnabled = true;
        scene.imageProcessingConfiguration.toneMappingEnabled = true;
        scene.imageProcessingConfiguration.toneMappingType =
          ImageProcessingConfiguration.TONEMAPPING_ACES;
        scene.imageProcessingConfiguration.exposure = 1;
        scene.imageProcessingConfiguration.contrast = 1.04;
        pipe.sharpenEnabled = this.quality === 'cinematic';
        if (pipe.sharpenEnabled) {
          pipe.sharpen.edgeAmount = 0.16;
          pipe.sharpen.colorAmount = 1;
        }
        scene.imageProcessingConfiguration.vignetteEnabled = true;
        scene.imageProcessingConfiguration.vignetteWeight = 0.85;
        scene.imageProcessingConfiguration.vignetteStretch = 0.25;
      }
      this.flashLight = new PointLight(
        'pooled-muzzle-light',
        Vector3.Zero(),
        scene,
      );
      this.flashLight.intensity = 0;
      this.flashLight.range = 18;
      this.flashLight.diffuse = new Color3(1, 0.57, 0.23);
      this.cursor = MeshBuilder.CreateTorus(
        'ground-target-reticle',
        { diameter: 2.2, thickness: 0.085, tessellation: 40 },
        scene,
      );
      this.cursor.material = this.materials.white;
      this.cursor.isPickable = false;
      this.cursor.setEnabled(false);
      this.emp = MeshBuilder.CreateTorus(
        'emp-shock-front',
        { diameter: 2, thickness: 0.07, tessellation: 64 },
        scene,
      );
      this.emp.material = this.materials.blue;
      this.emp.isPickable = false;
      this.emp.setEnabled(false);
      this.playerRing = MeshBuilder.CreateTorus(
        'friendly-marker',
        { diameter: 5.2, thickness: 0.026, tessellation: 48 },
        scene,
      );
      this.playerRing.material = this.materials.blue;
      this.playerRing.isPickable = false;
      this.playerRing.visibility = 0.6;
      if (b.protectsBase) {
        this.base = new TransformNode('evacuation-beacon', scene);
        this.base.position.copyFrom(worldPosition(b.base.x, b.base.y));
        box(
          scene,
          'beacon-plinth',
          [4, 0.5, 4],
          [0, 0.25, 0],
          this.materials.steel,
          this.base,
        );
        box(
          scene,
          'beacon-battery',
          [2.7, 1.2, 2.7],
          [0, 0.9, 0],
          this.materials.armor,
          this.base,
        );
        box(
          scene,
          'beacon-spire',
          [0.2, 3.5, 0.2],
          [0, 2.5, 0],
          this.materials.steel,
          this.base,
        );
        const ring = MeshBuilder.CreateTorus(
          'beacon-ring',
          { diameter: 3, thickness: 0.1, tessellation: 32 },
          scene,
        );
        ring.parent = this.base;
        ring.position.y = 2.3;
        ring.material = this.materials.blue;
        const beam = MeshBuilder.CreateCylinder(
          'beacon-light-column',
          {
            height: 15,
            diameterTop: 0.08,
            diameterBottom: 1.2,
            tessellation: 16,
          },
          scene,
        );
        beam.parent = this.base;
        beam.position.y = 8;
        beam.material = this.materials.blue;
        beam.visibility = 0.1;
      }
      if (b.type === 'escort' && this.base) {
        for (const child of this.base.getChildMeshes()) child.dispose();
        const m = this.materials,
          root = this.base;
        box(
          scene,
          'convoy-armored-bed',
          [4.4, 1.5, 7],
          [0, 1.6, 0],
          m.armor,
          root,
        );
        box(
          scene,
          'convoy-cabin',
          [4.1, 2.2, 2.4],
          [0, 2.2, 2.4],
          m.heavy,
          root,
        );
        box(
          scene,
          'convoy-windshield',
          [3.5, 0.7, 0.12],
          [0, 2.65, 3.64],
          m.glass,
          root,
        );
        box(
          scene,
          'medical-cross-h',
          [2, 0.12, 0.45],
          [0, 2.42, -0.8],
          m.blue,
          root,
        );
        box(
          scene,
          'medical-cross-v',
          [0.45, 0.12, 2],
          [0, 2.43, -0.8],
          m.blue,
          root,
        );
        for (const side of [-1, 1])
          for (const z of [-2, 0, 2])
            box(
              scene,
              'convoy-wheel',
              [0.8, 1.3, 1.3],
              [side * 2.2, 0.8, z],
              m.rubber,
              root,
            );
        for (const x of [-1.6, 1.6])
          box(
            scene,
            'convoy-headlight',
            [0.5, 0.4, 0.15],
            [x, 1.7, 3.7],
            m.lamp,
            root,
          );
      }
      for (const o of b.objectives) {
        const root = new TransformNode('objective-' + o.id, scene),
          m = this.materials;
        root.position.copyFrom(worldPosition(o.x, o.y));
        const ring = MeshBuilder.CreateTorus(
          'objective-zone',
          {
            diameter: o.kind === 'capture' ? 23 : o.kind === 'exit' ? 20 : 9,
            thickness: 0.12,
            tessellation: 48,
          },
          scene,
        );
        ring.parent = root;
        ring.position.y = 0.13;
        ring.material = m.ember;
        ring.isPickable = false;
        const body = box(
          scene,
          'objective-' + o.kind,
          o.kind === 'facility'
            ? [5, 5, 5]
            : o.kind === 'intel'
              ? [2, 1.4, 2]
              : [0.25, 7, 0.25],
          [0, o.kind === 'facility' ? 2.5 : o.kind === 'intel' ? 0.8 : 3.5, 0],
          m.heavy,
          root,
        );
        if (o.kind === 'facility')
          for (const x of [-2, 2])
            box(
              scene,
              'reactor-light',
              [0.18, 4, 5.1],
              [x, 2.5, 0],
              m.ember,
              root,
            );
        if (o.kind === 'capture')
          box(scene, 'radio-flag', [3, 1.5, 0.15], [1.5, 6, 0], m.ember, root);
        const bar = box(
          scene,
          'objective-progress',
          [4, 0.18, 0.12],
          [0, 7.8, 0],
          m.ember,
          root,
        );
        body.isPickable = o.kind === 'facility';
        body.metadata = { objectiveId: o.id };
        bar.isPickable = false;
        this.objectiveViews.set(o.id, { root, ring, body, bar });
      }
      for (const [i, point] of b.route.entries()) {
        const ring = MeshBuilder.CreateTorus(
          'convoy-waypoint-' + i,
          { diameter: 8, thickness: 0.12, tessellation: 24 },
          scene,
        );
        ring.position.copyFrom(worldPosition(point.x, point.y, 0.12));
        ring.material = this.materials.blue;
        ring.isPickable = false;
      }
      this.syncTank(b.player, b);
      for (const e of b.enemies) this.syncTank(e, b);
      this.updateCamera(b, 0, true);
      this.scene.render();
      completed('units');
      progress(80, '装甲与任务目标已部署');
    };
    if (options.onProgress && !headless) {
      this.ready = (async () => {
        this.world = await createWorldAsync(
          scene,
          b,
          this.materials,
          this.quality,
          headless,
          options.assets !== false,
          (done, total, label) =>
            progress(12 + (done / Math.max(1, total)) * 58, label),
          () => this.disposed,
        );
        completed('world');
        if (this.disposed)
          throw new DOMException('Deployment cancelled', 'AbortError');
        // Give the completed world stage a paint before building vehicle pools.
        await new Promise<void>((resolve) => setTimeout(resolve, 0));
        if (this.disposed)
          throw new DOMException('Deployment cancelled', 'AbortError');
        finish();
        await this.prepareFirstFrame(progress, b);
        completed('ready');
        console.info(
          '[battle-load]',
          JSON.stringify({
            mission: b.mission,
            ...timings,
            meshes: scene.meshes.length,
            textures: scene.textures.length,
          }),
        );
      })();
    } else {
      this.world = createWorld(
        scene,
        b,
        this.materials,
        this.quality,
        headless,
        options.assets !== false,
      );
      finish();
      this.ready = headless ? Promise.resolve() : this.scene.whenReadyAsync();
    }
  }
  private async prepareFirstFrame(
    report: (progress: number, label: string) => void,
    battle?: Battle,
  ): Promise<void> {
    // Scene.whenReadyAsync compiles even disabled rubble and distant effect
    // variants. Prepare what the opening camera and its local shadow pass draw.
    const generation = this.resizeGeneration;
    if (battle) {
      this.updateCamera(battle, 0, true);
      this.scene.updateTransformMatrix(true);
    }
    const required = new Set(
      this.scene.meshes.filter((mesh) => {
        if (!mesh.isEnabled() || !mesh.isVisible || mesh.visibility <= 0)
          return false;
        mesh.computeWorldMatrix(true);
        return mesh.alwaysSelectAsActiveMesh || this.camera.isInFrustum(mesh);
      }),
    );
    const shadowMap = this.world.shadow?.getShadowMap();
    const casters = shadowMap?.renderList ?? [];
    const localCasters =
      shadowMap?.getCustomRenderList?.(0, casters, casters.length) ?? casters;
    for (const mesh of localCasters)
      if (mesh.isEnabled() && mesh.isVisible) required.add(mesh);
    const meshes = [...required];
    const textures = new Set(
      meshes.flatMap((mesh) => mesh.material?.getActiveTextures() ?? []),
    );
    if (this.scene.environmentTexture)
      textures.add(this.scene.environmentTexture);
    const assets = [...textures].filter((texture) => !texture.isRenderTarget);
    let previousCheck = performance.now(),
      activeWait = 0;
    let lastProgress = 80;
    const publish = (value: number, label: string) => {
      lastProgress = Math.max(lastProgress, value);
      report(lastProgress, label);
    };
    while (true) {
      if (this.disposed)
        throw new DOMException('Deployment cancelled', 'AbortError');
      const now = performance.now();
      const hidden = typeof document !== 'undefined' && document.hidden;
      if (!hidden)
        activeWait += Math.min(1000, Math.max(0, now - previousCheck));
      previousCheck = now;
      if (hidden) {
        await new Promise<void>((resolve) => setTimeout(resolve, 128));
        continue;
      }
      if (battle && generation !== this.resizeGeneration)
        return this.prepareFirstFrame(publish, battle);
      const failed = assets.find((texture) => texture.loadingError);
      if (failed)
        throw new Error('Required texture could not load: ' + failed.name);
      if (activeWait > 45_000)
        throw new Error('First-frame assets or shaders did not become ready');
      const loaded = assets.filter((texture) => texture.isReady()).length;
      if (loaded < assets.length) {
        publish(
          80 + (loaded / Math.max(1, assets.length)) * 12,
          `装载首屏材质 ${loaded} / ${assets.length}`,
        );
      } else {
        this.scene.incrementRenderId();
        // Check every required mesh so independent shaders compile in parallel.
        let ready = 0;
        for (const mesh of meshes) if (mesh.isReady(true)) ready++;
        const cameraReady = this.camera.isReady(true);
        if (cameraReady) ready++;
        publish(
          92 + (ready / (meshes.length + 1)) * 7,
          `准备首屏光照 ${ready} / ${meshes.length + 1}`,
        );
        if (ready === meshes.length + 1) {
          this.scene.render();
          publish(100, '战场已就绪');
          return;
        }
        // Postprocess readiness can require its render targets to be initialized.
        this.scene.render();
      }
      await new Promise<void>((resolve) => setTimeout(resolve, 32));
    }
  }
  get fps() {
    return Math.round(this.engine.getFps());
  }
  get meshCount() {
    return this.scene.meshes.length;
  }
  resize() {
    if (this.disposed) return;
    this.resizeGeneration++;
    if (this.mobile) this.setBudget(this.budgetScale, this.effectScale);
    this.engine.resize();
  }
  toggleCamera() {
    this.mode = this.mode === 'assault' ? 'tactical' : 'assault';
    return this.mode;
  }
  setZoom(delta: number) {
    this.zoom = Math.max(0.72, Math.min(1.5, this.zoom + delta * 0.0008));
  }
  private random() {
    this.renderOnlyRandom =
      (this.renderOnlyRandom * 1664525 + 1013904223) >>> 0;
    return this.renderOnlyRandom / 4294967296;
  }
  updateCamera(b: Battle, dt: number, snap = false) {
    const p = worldPosition(b.player.x, b.player.y, 1);
    const ahead = new Vector3(
      Math.cos(b.player.turret) * 4,
      0,
      Math.sin(b.player.turret) * 4,
    );
    const target = p.add(ahead);
    const amount = snap ? 1 : 1 - Math.exp(-Math.min(dt, 0.06) * 5);
    Vector3.LerpToRef(this.cameraTarget, target, amount, this.cameraTarget);
    const portrait =
      this.engine.getRenderWidth() / this.engine.getRenderHeight() < 1;
    const height =
      (this.mode === 'tactical' ? 76 : 29) * (portrait ? 1.24 : 1) * this.zoom;
    const back = (this.mode === 'tactical' ? 31 : 30) * this.zoom;
    const cameraPos = new Vector3(
      this.cameraTarget.x,
      this.cameraTarget.y + height,
      this.cameraTarget.z + back,
    );
    if (b.save.shake && b.shake > 0 && !b.paused) {
      cameraPos.x += Math.sin(b.elapsed * 119) * b.shake * 0.022;
      cameraPos.y += Math.cos(b.elapsed * 147) * b.shake * 0.012;
    }
    this.camera.position.copyFrom(cameraPos);
    this.camera.setTarget(this.cameraTarget);
    this.camera.computeWorldMatrix();
    this.camera.getViewMatrix(true);
    this.scene.updateTransformMatrix(true);
    this.world.updateShadow(this.cameraTarget);
  }
  pointer(clientX: number, clientY: number): Vec | null {
    if (this.disposed) return null;
    const rect = this.canvas.getBoundingClientRect(),
      hardwareScale = this.engine.getHardwareScalingLevel(),
      x =
        ((clientX - rect.left) * this.engine.getRenderWidth() * hardwareScale) /
        rect.width,
      y =
        ((clientY - rect.top) * this.engine.getRenderHeight() * hardwareScale) /
        rect.height;
    const ray = this.scene.createPickingRay(
      x,
      y,
      Matrix.Identity(),
      this.camera,
      false,
    );
    const pick = this.scene.pickWithRay(
      ray,
      (mesh) =>
        mesh.isPickable &&
        mesh.isEnabled() &&
        mesh.isVisible &&
        ((mesh.metadata?.tankId !== undefined && mesh.metadata.tankId !== 0) ||
          mesh.metadata?.objectiveId !== undefined) &&
        !mesh.isDisposed(),
      false,
    );
    if (pick?.hit && pick.pickedMesh) {
      const objective = this.objectiveViews.get(
        pick.pickedMesh.metadata.objectiveId,
      );
      if (objective) return simulationPosition(objective.root.position);
      const root = this.models.get(pick.pickedMesh.metadata.tankId);
      if (root) return simulationPosition(root.root.position);
    }
    if (Math.abs(ray.direction.y) < 0.0001) return null;
    const distance = -ray.origin.y / ray.direction.y;
    if (distance < 0) return null;
    const point = ray.origin.add(ray.direction.scale(distance));
    const sim = simulationPosition(point);
    return {
      x: Math.max(0, Math.min(W, sim.x)),
      y: Math.max(0, Math.min(H, sim.y)),
    };
  }
  setBudget(scale: number, effects: number) {
    this.effectScale = effects;
    this.budgetScale = scale;
    // Only resize on policy transitions; never reallocate render targets each frame.
    const next = this.mobile
      ? resolutionScale(
          this.canvas.clientWidth,
          this.canvas.clientHeight,
          typeof window === 'undefined' ? 1 : window.devicePixelRatio,
          this.resolutionMode,
          scale,
        )
      : this.resolutionScale;
    if (Math.abs(next - this.resolutionScale) > 0.04) {
      this.resolutionScale = next;
      this.engine.setHardwareScalingLevel(next);
      this.engine.resize();
    }
    if (this.world?.shadow) this.world.sun.shadowEnabled = effects > 0.6;
  }
  private syncTank(t: Tank, b: Battle) {
    let model = this.models.get(t.id);
    if (model && t.id === 0 && model.evolutionLevel !== b.level) {
      for (const mesh of model.meshes)
        this.world.shadow?.removeShadowCaster(mesh);
      model.dispose();
      this.models.delete(t.id);
      model = undefined;
    }
    if (!model) {
      model = buildTank(
        this.scene,
        this.materials,
        t.id === 0
          ? b.save.chassis
          : t.kind === 1
            ? 0
            : t.kind === 2 || t.kind === 3
              ? 2
              : 1,
        t.id !== 0,
        t.kind === 3,
        t.id === 0 ? b.level : 1,
        this.mobile || this.quality === 'performance',
      );
      const extras: Mesh[] = [];
      const add = (
        name: string,
        size: [number, number, number],
        pos: [number, number, number],
        material: Material = this.materials.steel,
      ) =>
        extras.push(box(this.scene, name, size, pos, material, model!.turret));
      if (t.kind === 5) {
        add(
          'sniper-rangefinder',
          [1.1, 0.4, 0.8],
          [0, 2.8, 0.4],
          this.materials.red,
        );
        add('sniper-breech', [0.5, 0.5, 2], [0, 2.2, 1.5]);
      }
      if (t.kind === 6) {
        for (const x of [-0.65, 0.65])
          add(
            'volatile-charge',
            [0.8, 1, 1.5],
            [x, 2.2, 0],
            this.materials.ember,
          );
      }
      if (t.kind === 7) {
        add(
          'repair-cross-horizontal',
          [1.8, 0.2, 0.45],
          [0, 3, 0],
          this.materials.blue,
        );
        add(
          'repair-cross-vertical',
          [0.45, 0.2, 1.8],
          [0, 3.02, 0],
          this.materials.blue,
        );
        add('repair-mast', [0.12, 2, 0.12], [0, 3, -1]);
      }
      if (t.kind === 8) {
        for (const x of [-1.2, 1.2]) {
          add('rocket-pod', [0.9, 0.8, 2.6], [x, 2.6, 0]);
          add(
            'rocket-pod-hot',
            [0.7, 0.55, 0.08],
            [x, 2.6, 1.33],
            this.materials.red,
          );
        }
      }
      if (t.kind === 4)
        add(
          'guard-frontal-plate',
          [3.6, 1, 0.45],
          [0, 1.5, 1.75],
          this.materials.heavy,
        );
      model.meshes.push(...extras);
      this.models.set(t.id, model);
      for (const mesh of model.meshes) {
        this.world.shadow?.addShadowCaster(mesh);
        mesh.metadata = { tankId: t.id };
        mesh.isPickable = t.id !== 0;
      }
      if (t.id !== 0) {
        const root = new TransformNode('enemy-health-bar', this.scene);
        box(
          this.scene,
          'health-background',
          [3.6, 0.15, 0.05],
          [0, 0, 0],
          this.materials.rubber,
          root,
        );
        const fill = box(
          this.scene,
          'health-remaining',
          [3.6, 0.13, 0.07],
          [0, 0, -0.012],
          this.materials.red,
          root,
        );
        root.billboardMode = Mesh.BILLBOARDMODE_ALL;
        this.healthBars.set(t.id, { root, fill });
      }
    }
    if (
      t.id === 0 &&
      (this.weaponMount?.model !== model || this.weaponMount.index !== b.weapon)
    ) {
      if (this.weaponMount) {
        for (const mesh of this.weaponMount.meshes)
          this.world.shadow?.removeShadowCaster(mesh);
        this.weaponMount.root.dispose();
      }
      this.weaponMount = createWeaponMount(
        this.scene,
        model,
        b.weapon,
        this.materials,
      );
      for (const mesh of this.weaponMount.meshes)
        this.world.shadow?.addShadowCaster(mesh);
    }
    model.root.setEnabled(t.hp > 0);
    let contact = this.contactShadows.get(t.id);
    if (!contact) {
      contact = MeshBuilder.CreateGround(
        'tank-contact-' + t.id,
        { width: 4.5, height: 5.2 },
        this.scene,
      );
      contact.material = this.materials.contact;
      contact.isPickable = false;
      this.contactShadows.set(t.id, contact);
    }
    contact.position.copyFrom(worldPosition(t.x, t.y, 0.085));
    contact.rotation.y = heading(t.angle);
    contact.scaling.set(t.radius / 20, 1, t.radius / 20);
    contact.setEnabled(t.hp > 0);
    model.root.position.copyFrom(worldPosition(t.x, t.y));
    model.root.scaling.setAll(t.radius / 20);
    model.body.rotation.y = heading(t.angle);
    model.turret.rotation.y = heading(t.turret);
    model.barrel.scaling.z =
      (muzzleDistance(t.radius) * 0.1) / (4.06 * (t.radius / 20));
    const shotAge = t.lastShot ? b.elapsed - t.lastShot.at : Infinity;
    model.barrel.position.z = -recoilDistance(t.lastShot?.weapon ?? 0, shotAge);
    // Retain the shared muzzle anchor; the firing effects use transparent volumes.
    model.flash.setEnabled(false);
    model.shield.setEnabled(
      t.id === 0
        ? b.shield > 0.3
        : t.stun > 0 || t.spawn > 0 || (t.slow ?? 0) > 0,
    );
    const health = this.healthBars.get(t.id);
    if (health) {
      health.root.position.copyFrom(
        worldPosition(t.x, t.y, (t.radius / 20) * 3.7),
      );
      health.fill.scaling.x = Math.max(0, t.hp / t.maxHp);
      health.fill.position.x = -(1 - t.hp / t.maxHp) * 1.8;
      health.root.setEnabled(t.spawn <= 0);
    }
    if (shotAge >= 0 && shotAge < 0.045) {
      this.flashLight.position.copyFrom(
        worldPosition(
          t.x + Math.cos(t.turret) * muzzleDistance(t.radius),
          t.y + Math.sin(t.turret) * muzzleDistance(t.radius),
          muzzleHeight(t.radius) * 0.1,
        ),
      );
      this.flashLight.intensity = t.id === 0 ? 30 : 16;
      this.muzzleTimer = 0.09;
    }
  }
  private pool(pool: Mesh[], i: number, kind: 'spark' | 'track') {
    if (pool[i]) return pool[i];
    let mesh: Mesh;
    if (kind === 'spark') {
      mesh = MeshBuilder.CreateBox('pooled-spark', { size: 0.08 }, this.scene);
      mesh.material = this.materials.ember;
    } else {
      mesh = MeshBuilder.CreateBox(
        'pooled-track-mark',
        { width: 0.55, height: 0.008, depth: 0.4 },
        this.scene,
      );
      mesh.material = this.materials.rubber;
    }
    mesh.isPickable = false;
    pool.push(mesh);
    return mesh;
  }
  private showPool(pool: Mesh[], count: number) {
    for (let i = count; i < pool.length; i++) pool[i].setEnabled(false);
  }
  draw(b: Battle, aim: Vec | null, effectTime = b.elapsed) {
    if (this.disposed) return;
    const dt = this.initialized
      ? Math.max(0, b.elapsed - this.lastTime)
      : 1 / 60;
    this.lastTime = b.elapsed;
    this.initialized = true;
    const alive = new Set([0, ...b.enemies.map((e) => e.id)]);
    for (const [id, model] of this.models) {
      if (!alive.has(id)) {
        for (const mesh of model.meshes)
          this.world.shadow?.removeShadowCaster(mesh);
        model.dispose();
        this.models.delete(id);
        this.contactShadows.get(id)?.dispose();
        this.contactShadows.delete(id);
        this.healthBars.get(id)?.root.dispose();
        this.healthBars.delete(id);
        this.sniperLines.get(id)?.dispose();
        this.sniperLines.delete(id);
      }
    }
    this.syncTank(b.player, b);
    for (const e of b.enemies) {
      this.syncTank(e, b);
      if (e.kind === 5 || e.kind === 3) {
        let line = this.sniperLines.get(e.id);
        if (!line) {
          line = box(
            this.scene,
            'sniper-targeting-line',
            [0.045, 0.045, 1],
            [0, 0, 0],
            this.materials.red,
          );
          line.isPickable = false;
          this.sniperLines.set(e.id, line);
        }
        const length = 65;
        line.scaling.z = length;
        line.position.copyFrom(
          worldPosition(
            e.x + Math.cos(e.turret) * length * 5,
            e.y + Math.sin(e.turret) * length * 5,
            0.35,
          ),
        );
        line.rotation.y = heading(e.turret);
        line.scaling.x = e.kind === 3 ? 3 : 1;
        line.setEnabled(
          e.spawn <= 0 &&
            e.stun <= 0 &&
            (e.kind === 3 ? (e.attackWindup ?? 0) > 0 : e.cooldown < 1.2),
        );
      }
    }
    b.mines.forEach((mine, i) => {
      let root = this.minePool[i];
      if (!root) {
        root = new TransformNode('anti-tank-mine', this.scene);
        const body = MeshBuilder.CreateCylinder(
          'mine-casing',
          { diameter: 2.2, height: 0.3, tessellation: 20 },
          this.scene,
        );
        body.parent = root;
        body.position.y = 0.22;
        body.material = this.materials.steel;
        const plate = MeshBuilder.CreateCylinder(
          'mine-pressure-plate',
          { diameter: 1.55, height: 0.15, tessellation: 20 },
          this.scene,
        );
        plate.parent = root;
        plate.position.y = 0.42;
        plate.material = this.materials.heavy;
        const ring = MeshBuilder.CreateTorus(
          'mine-team-marker',
          { diameter: 3, thickness: 0.09, tessellation: 24 },
          this.scene,
        );
        ring.parent = root;
        ring.position.y = 0.08;
        for (const side of [-1, 1])
          box(
            this.scene,
            'mine-carry-handle',
            [0.18, 0.18, 0.75],
            [side * 1.06, 0.28, 0],
            this.materials.edges,
            root,
          );
        for (const child of root.getChildMeshes()) child.isPickable = false;
        this.minePool[i] = root;
      }
      root.position.copyFrom(worldPosition(mine.x, mine.y));
      const ring = root
        .getChildMeshes()
        .find((m) => m.name === 'mine-team-marker')!;
      ring.material = mine.enemy ? this.materials.red : this.materials.blue;
      ring.visibility =
        b.elapsed < mine.armedAt ? 0.3 + Math.sin(b.elapsed * 18) * 0.2 : 0.8;
      root.setEnabled(true);
    });
    for (let i = b.mines.length; i < this.minePool.length; i++)
      this.minePool[i].setEnabled(false);
    if (this.base) {
      this.base.position.copyFrom(worldPosition(b.base.x, b.base.y));
      if (b.type === 'escort') {
        const next = b.route[Math.min(b.routeIndex, b.route.length - 1)];
        this.base.rotation.y = heading(
          Math.atan2(next.y - b.base.y, next.x - b.base.x),
        );
      }
    }
    for (const o of b.objectives) {
      const v = this.objectiveViews.get(o.id)!;
      v.ring.material = o.done
        ? this.materials.blue
        : o.contested
          ? this.materials.red
          : this.materials.ember;
      v.body.setEnabled(!o.done || o.kind === 'capture');
      for (const mesh of v.root.getChildMeshes())
        if (mesh.name === 'reactor-light') mesh.setEnabled(!o.done);
      v.bar.scaling.x =
        o.kind === 'capture' ? Math.max(0.01, o.progress / 8) : o.hp / o.maxHp;
      v.bar.setEnabled(
        !o.done && (o.kind === 'capture' || o.kind === 'facility'),
      );
      if (o.kind === 'intel') {
        v.body.rotation.y = b.elapsed;
        v.body.position.y = 0.8 + Math.sin(b.elapsed * 2) * 0.2;
      }
    }
    this.world.updateDamage();
    this.muzzleTimer = Math.max(0, this.muzzleTimer - dt);
    if (this.muzzleTimer === 0) this.flashLight.intensity = 0;
    this.projectiles.update(b, this.effectScale);
    this.muzzles.update(b, this.effectScale);
    let sparks = 0;
    const limit =
      this.quality === 'performance'
        ? Math.floor(24 * this.effectScale)
        : this.quality === 'cinematic'
          ? 220
          : 135;
    for (const p of b.particles) {
      if (this.mobile && Math.hypot(p.x - b.player.x, p.y - b.player.y) > 1000)
        continue;
      if (!p.smoke) {
        if (sparks >= limit) continue;
        const mesh = this.pool(this.sparkPool, sparks++, 'spark'),
          age = 1 - p.life / p.max;
        mesh.setEnabled(true);
        mesh.position.copyFrom(
          worldPosition(p.x, p.y, 0.3 + Math.sin(age * Math.PI) * 2.4),
        );
        mesh.scaling.set(
          p.size * 0.22,
          p.size * 0.22,
          p.size * 0.45 + Math.hypot(p.vx, p.vy) * 0.025,
        );
        mesh.rotation.y = heading(Math.atan2(p.vy, p.vx));
        mesh.visibility = p.life / p.max;
      }
    }
    this.showPool(this.sparkPool, sparks);
    const trackCount = Math.min(
      this.quality === 'performance' ? 14 : 60,
      b.tracks.length,
    );
    for (let i = 0; i < trackCount; i++) {
      const mark = b.tracks[b.tracks.length - trackCount + i];
      for (let side = 0; side < 2; side++) {
        const mesh = this.pool(this.trackPool, i * 2 + side, 'track'),
          offset = (side === 0 ? -1 : 1) * 16;
        mesh.setEnabled(true);
        mesh.position.copyFrom(
          worldPosition(
            mark.x + Math.cos(mark.angle + Math.PI / 2) * offset,
            mark.y + Math.sin(mark.angle + Math.PI / 2) * offset,
            0.045,
          ),
        );
        mesh.rotation.y = heading(mark.angle);
        mesh.visibility = Math.min(0.45, mark.life * 0.08);
      }
    }
    this.showPool(this.trackPool, trackCount * 2);
    const supplies = b.pickups
      .filter(
        (item) => Math.hypot(item.x - b.player.x, item.y - b.player.y) < 1100,
      )
      .slice(0, this.mobile ? 12 : 20);
    for (let i = 0; i < supplies.length; i++) {
      const item = supplies[i];
      let node = this.pickupPool[i];
      if (!node) {
        node = createSupplyModel(this.scene, this.materials, this.quality);
        this.pickupPool.push(node);
      }
      node.setEnabled(true);
      node.position.copyFrom(
        worldPosition(item.x, item.y, 0.15 + Math.sin(b.elapsed * 2 + i) * 0.1),
      );
      const type = item.kind === 3 ? (item.weapon ?? 1) : 7 + item.kind;
      configureSupplyModel(
        node,
        item.kind,
        type,
        this.supplyColors[type],
        this.supplyLabels[type],
      );
    }
    for (let i = supplies.length; i < this.pickupPool.length; i++)
      this.pickupPool[i].setEnabled(false);
    const playerModel = this.models.get(0);
    if (
      playerModel &&
      b.tracks.length &&
      b.tracks[b.tracks.length - 1].life > 8.9
    ) {
      playerModel.body.rotation.z = Math.sin(b.elapsed * 28) * 0.009;
      playerModel.root.position.y = Math.sin(b.elapsed * 21) * 0.025;
    }
    this.playerRing.material =
      b.levelUpTime > 0 ? this.materials.ember : this.materials.blue;
    this.playerRing.scaling.setAll(
      b.levelUpTime > 0 ? 1 + (3.2 - b.levelUpTime) * 1.5 : 1,
    );
    this.playerRing.position.copyFrom(
      worldPosition(b.player.x, b.player.y, 0.06),
    );
    this.emp.setEnabled(b.pulse > 0);
    if (b.pulse > 0) {
      this.emp.position.copyFrom(worldPosition(b.player.x, b.player.y, 0.4));
      this.emp.scaling.setAll((1 - b.pulse) * 30);
      this.emp.visibility = b.pulse;
    }
    this.cursor.setEnabled(!!aim);
    if (aim) this.cursor.position.copyFrom(worldPosition(aim.x, aim.y, 0.09));
    this.updateCamera(b, dt);
    this.world.nature.update(b.elapsed);
    this.explosions.update(b, this.effectScale, effectTime);
    this.scene.render();
  }
  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    this.projectiles?.dispose();
    this.muzzles?.dispose();
    this.scene.dispose();
    this.engine.dispose();
    this.models.clear();
    this.contactShadows.clear();
    this.healthBars.clear();
  }
}
